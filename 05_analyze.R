library(tidyverse)
library(duckdb)
library(splines)

db <- dbConnect(duckdb("processed_data/votes_tk2025.duckdb", read_only = TRUE))


# Example analysis: estimating a nerdvote.nl effect
nerdvote_candidates <- c(
  "Barbara Kathmann", 
  "Hanneke van der Werf", 
  "Jan Valize", 
  "Marieke Koekkoek", 
  "Erik Kemp", 
  "Sarah El Boujdaini", 
  "Hemin Hawezy", 
  "Martijn Buijsse", 
  "Queeny-Aimée Rajkowski", 
  "Cynthia Pallandt"
)

df_analysis <- 
  tbl(db, "main") |> 
  mutate(nerdvote = paste(first_name, infix, last_name) %in% nerdvote_candidates) |> 
  select(
    gemeente_id, bureau_id, party_id, party, 
    candidate_nr, votes, bureau_votes, 
    candidate_id, nerdvote, gender, 
    first_name, infix, last_name
  ) |> 
  collect()


fit <- glm(
  votes / bureau_votes ~ party + ns(candidate_nr, df = 5) + nerdvote, 
  family = binomial(),
  weight = bureau_votes, 
  data = df_analysis,
  model = FALSE
)

write_rds(fit, "processed_data/nerdvote_model.rds")


summary(fit)
nerdvote_param <- summary(fit)[["coefficients"]]["nerdvoteTRUE","Estimate"]
exp(nerdvote_param) # Odds ratio of almost 4!


# What would happen if we would make number 22 on CDA a nerd?
total_votes_can <- df_analysis |> filter(party == "CDA", candidate_nr == 22) |> pull(votes) |> sum()
total_votes  <- df_analysis |> pull(votes) |> sum()
p_can <- (total_votes_can / total_votes)
log_odds_can <- log(p_can) - log(1-p_can) 
log_odds_new <- log_odds_can + nerdvote_param
p_new <- 1 / (1 + exp(-log_odds_new))

cat("Number 22 of CDA would go from", total_votes_can, "votes to [", qbinom(c(0.025, 0.975), size = total_votes, prob = p_new), "]")
