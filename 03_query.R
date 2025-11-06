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


