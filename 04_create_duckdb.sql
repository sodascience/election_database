# First open the votes database
.open processed_data/votes.duckdb

# First, create all these tables
CREATE TABLE kieskring AS SELECT * FROM read_parquet("processed_data/votes_data/kieskring.parquet");
CREATE TABLE party AS SELECT * FROM read_parquet("processed_data/votes_data/party.parquet");
CREATE TABLE candidate AS SELECT * FROM read_parquet("processed_data/votes_data/candidate.parquet");
CREATE TABLE gemeente AS SELECT * FROM read_parquet("processed_data/votes_data/gemeente.parquet");
CREATE TABLE bureau AS SELECT * FROM read_parquet("processed_data/votes_data/bureau.parquet");
CREATE TABLE postcode AS SELECT * FROM read_parquet("processed_data/votes_data/postcode.parquet");
CREATE TABLE vote AS SELECT * FROM read_parquet("processed_data/votes_data/vote.parquet");

# then, create a view with the full table that people will want to use
CREATE VIEW main AS
SELECT
  votetab.kieskring_id AS kieskring_id,
  kieskring."name" AS kieskring,
  gemeente_id,
  gemeente."name" AS gemeente,
  bureau_id,
  "location",
  bureau.postcode AS postcode,
  votetab.party_id AS party_id,
  party."name" AS party,
  votetab.candidate_nr AS candidate_nr,
  candidate_id,
  first_name,
  infix,
  last_name,
  gender,
  "language",
  votes,
  party_votes,
  bureau_votes,
  x_centroid,
  y_centroid,
  population,
  area_m2
FROM (
  SELECT q01.*, SUM(votes) OVER (PARTITION BY bureau_id) AS bureau_votes
  FROM (
    SELECT
      vote.*,
      SUM(votes) OVER (PARTITION BY bureau_id, party_id) AS party_votes
    FROM vote
  ) q01
) AS votetab
LEFT JOIN kieskring
  ON (votetab.kieskring_id = kieskring.id)
LEFT JOIN gemeente
  ON (votetab.gemeente_id = gemeente.id)
LEFT JOIN bureau
  ON (votetab.bureau_id = bureau.id)
LEFT JOIN party
  ON (votetab.party_id = party.id)
LEFT JOIN candidate
  ON (
    votetab.kieskring_id = candidate.kieskring_id AND
    votetab.party_id = candidate.party_id AND
    votetab.candidate_nr = candidate.candidate_nr
  )
LEFT JOIN postcode
  ON (bureau.postcode = postcode.postcode);