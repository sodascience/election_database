library(tidyverse)
library(digest)
library(nanoparquet)
library(sf)

# DATA LOADING ----
# Votes data
df_votes <- 
  list.files("processed_data/gemeente/", pattern = "\\d+.rds", full.names = TRUE) |> 
  map(read_rds, .progress = TRUE) |> 
  bind_rows() |> 
  rename(candidate_nr = candidate_id)

# candidates data
df_candidates <- 
  read_delim("raw_data/Overzicht+Kandidatenlijsten_TK2025_csv.csv", delim = ";") |> 
  select(
    kieskring_id = Kieskring,
    party = `Politieke Groepering`, 
    candidate_nr = `Nr.`, 
    first_name = Roepnaam, 
    infix = Tussenvoegsel, 
    last_name = Achternaam, 
    gender = Geslacht, 
    language = Taal
  ) |> 
  distinct() |> 
  mutate(
    kieskring_id = factor(kieskring_id),
    candidate_nr = as.integer(candidate_nr)
  )

sf_postcode <- 
  st_read("raw_data/pc6.gpkg", query = "SELECT postcode6, aantal_inwoners, geom FROM postcode6") |> 
  mutate(
    aantal_inwoners = na_if(aantal_inwoners, -99997),
    area_m2 = as.numeric(st_area(geom)),
  ) |> 
  rename(
    postcode = postcode6,
    population = aantal_inwoners
  )

# DATABASE CREATION ----

# create parties table
df_party <- 
  df_votes |> 
  summarize(.by = c(party_id, party)) |> 
  rename(id = party_id, name = party) |> 
  mutate(name = as.character(name)) |> 
  arrange(id)

write_parquet(df_party, "processed_data/votes_data/party.parquet")

# create kieskring table
df_kieskring <- 
  df_votes |> 
  summarize(.by = c(kieskring_id, kieskring)) |> 
  mutate(id = as.integer(as.character(kieskring_id)), name = kieskring, .keep = "unused") |>
  arrange(id) |> 
  mutate(name = as_factor(as.character(name)))

write_parquet(df_kieskring, "processed_data/votes_data/kieskring.parquet")

# create gemeente table
df_gemeente <- 
  df_votes |> 
  summarize(.by = c(gemeente_id, gemeente)) |> 
  mutate(id = as.character(gemeente_id), name = as.character(gemeente), .keep = "unused") |>
  arrange(id) |> 
  mutate(id = as_factor(id), name = as_factor(name))

write_parquet(df_gemeente, "processed_data/votes_data/gemeente.parquet")

# create postcodes table (using geoparquet)

df_postcode <-
  sf_postcode |> 
  as_tibble() |> 
  select(-geom) |> 
  bind_cols(as_tibble(st_coordinates(st_centroid(sf_postcode)))) |> 
  rename(x_centroid = X, y_centroid = Y)

write_parquet(df_postcode, "processed_data/votes_data/postcode.parquet")

# create bureaus table
df_bureaus <- 
  df_votes |>
  summarize(.by = c(bureau_id, bureau)) |> 
  mutate(
    id = as.character(bureau_id),
    location = str_extract(bureau, "Stembureau (?<adres>.+) \\(postcode:", group = 1),
    postcode = str_extract(bureau, "\\(postcode: (?<postcode>\\d{4} \\w{2})\\)", group = 1),
    postcode = str_replace(postcode, " ", "")
  ) |> 
  select(-bureau_id, -bureau)

write_parquet(df_bureaus, "processed_data/votes_data/bureau.parquet")


# Create candidates table 
# this is a bit weird because candidate rank may differ per "kieskring"
# so we create an expanded table with kieskring, party, candidate
candidates_exp <- expand_grid(
  kieskring_id = as.character(1:20),
  party = as.character(unique(df_candidates$party)),
  candidate_nr = 1:max(df_candidates$candidate_nr)
)

# first, enter the "all" kieskring parties, which are all the same
# so join only by party and candidate id
ce_all <- 
  candidates_exp |>
  left_join(
    df_candidates |> 
      filter(kieskring_id == "alle") |> 
      select(-kieskring_id), 
    by = join_by(party, candidate_nr)
  )

# first, enter the kieskring-specific parties
# so join by kieskring, party, and candidate id
ce_specific <- 
  ce_all |>
  filter(is.na(first_name)) |>
  select(-first_name:-language) |>
  left_join(
    df_candidates |> 
      filter(kieskring_id != "alle"), 
    by = join_by(kieskring_id, party, candidate_nr)
  )

# then combine both
df_candidates_full <- 
  ce_all |>
  filter(!is.na(first_name)) |>
  bind_rows(ce_specific |> filter(!is.na(first_name))) |> 
  left_join(df_party, by = join_by(party == name)) |>
  rename(party_id = id) |>
  mutate(
    kieskring_id = as.integer(kieskring_id), 
    gender = as_factor(gender), 
    language = as_factor(language)
  ) |> 
  rowwise() |> 
  mutate(candidate_id = digest(paste(first_name, infix, last_name), algo = "xxhash32", serialize = FALSE)) |>
  ungroup() |> 
  select(kieskring_id, party_id, candidate_nr, candidate_id, first_name:language)

write_parquet(df_candidates_full, "processed_data/votes_data/candidate.parquet")

# last, the votes themselves, which can be quite simple / small now
df_votes_simplified <- 
  df_votes |> 
  select(kieskring_id, gemeente_id, bureau_id, party_id, candidate_nr, votes)

write_parquet(df_votes_simplified, "processed_data/votes_data/vote.parquet")
