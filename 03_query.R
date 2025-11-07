library(tidyverse)
library(duckdb)


db <- dbConnect(duckdb("processed_data/votes.duckdb", read_only = TRUE))

tbl(db, "vote") |> left_join(tbl(db, "party"), by = join_by(party_id == id)) |> head(100) |> collect()

df <- 
  tbl(db, "main") |> 
  arrange(bureau_id, party_id, candidate_nr) |> 
  select(
    bureau_id, gemeente, party, candidate_nr, candidate_id, 
    first_name, infix, last_name, gender, 
    votes, party_votes, bureau_votes,
    x_centroid, y_centroid
  ) |> 
  collect()


# create plot of votes per candidate for parties 1-20
df_can <- 
  tbl(db, "vote") |> 
  group_by(party_id, candidate_nr) |> 
  summarize(votes = sum(votes, na.rm = TRUE), .groups = "drop") |> 
  left_join(tbl(db, "party"), by = join_by(party_id == id)) |>
  rename(party = name) |> 
  arrange(party_id, candidate_nr) |> 
  collect()

df_can |> 
  filter(party_id < 21, candidate_nr < 50) |> 
  ggplot(aes(x = candidate_nr, y = votes)) +
  geom_col(fill = "lightseagreen") +
  scale_y_log10(labels = scales::label_log()) +
  theme_linedraw() +
  facet_wrap(vars(as_factor(party)), scales = "fixed") +
  labs(
    title = "Stemmen per kandidaat, per partij, TK2025",
    subtitle = "Bron: github.com/sodascience/election_database",
    y = "Aantal stemmen",
    x = "Kandidaat (positie op kieslijst)"
  )

ggsave("img/votes_per_party_candidate.png", dpi = 300, width = 13.5, height = 9.5)


# create plot of votes per party
df_pty <- 
  tbl(db, "vote") |> 
  left_join(tbl(db, "party"), by = join_by(party_id == id)) |>
  rename(party = name) |> 
  summarize(votes = sum(votes, na.rm = TRUE), .by = c(party_id, party)) |> 
  arrange(-party_id) |> 
  collect() |> 
  mutate(party = as_factor(party))

df_pty |> 
  ggplot(aes(y = party, x = votes)) +
  geom_col(fill = "#11443366", color = "#343434", linewidth = 0.2) + 
  scale_x_continuous(labels = scales::label_number()) +
  theme_linedraw() +
  labs(
    title = "Stemmen per partij, TK2025",
    subtitle = "Bron: github.com/sodascience/election_database",
    x = "Aantal stemmen",
    y = ""
  )

ggsave("img/votes_per_party.png", dpi = 300, width = 9, height = 7)
