library(tidyverse)
library(emld)
library(parallel)
library(pbapply)

extract_data <- function(eml) {
  kieskring <- eml$Count$Election$Contests$Contest$ContestIdentifier$ContestName
  kieskring_id <- eml$Count$Election$Contests$Contest$ContestIdentifier$Id
  gemeente <- eml$ManagingAuthority$AuthorityIdentifier$AuthorityIdentifier
  gemeente_id <- eml$ManagingAuthority$AuthorityIdentifier$Id
  stembureau_resultaten <- eml$Count$Election$Contests$Contest$ReportingUnitVotes
  
  # if there is only one stembureau, then the results are one level higher
  if (!is_null(names(stembureau_resultaten))) return(
    selection_to_votes(stembureau_resultaten$Selection) |>
      mutate(
        bureau = stembureau_resultaten$ReportingUnitIdentifier$ReportingUnitIdentifier,
        bureau_id = stembureau_resultaten$ReportingUnitIdentifier$Id
      ) |> 
      mutate(
        bureau = as_factor(bureau),
        bureau_id = as_factor(bureau_id),
        gemeente = as_factor(gemeente),
        gemeente_id = as_factor(gemeente_id),
        kieskring = as_factor(kieskring),
        kieskring_id = as_factor(kieskring_id)
      )
  )
  
  # this is the most common case, loop over all stembureaus in the gemeente
  lapply(stembureau_resultaten, function(s) {
    selection_to_votes(s$Selection) |>
      mutate(
        bureau = s$ReportingUnitIdentifier$ReportingUnitIdentifier,
        bureau_id = s$ReportingUnitIdentifier$Id
      )
  }) |>
    bind_rows() |>
    mutate(
      bureau = as_factor(bureau),
      bureau_id = as_factor(bureau_id),
      gemeente = as_factor(gemeente),
      gemeente_id = as_factor(gemeente_id),
      kieskring = as_factor(kieskring),
      kieskring_id = as_factor(kieskring_id)
    )
}

selection_to_votes <- function(selection) {
  col_party <- c()
  col_pid <- c()
  col_cid <- c()
  col_votes <- c()

  for (i in 1:length(selection)) {
    if (!is.null(selection[[i]]$AffiliationIdentifier)) {
      party <- selection[[i]]$AffiliationIdentifier$RegisteredName
      party_id <- parse_integer(selection[[i]]$AffiliationIdentifier$Id)
      next
    }

    col_party <- c(col_party, party)
    col_pid <- c(col_pid, party_id)
    col_cid <- c(col_cid, parse_integer(selection[[i]]$Candidate$CandidateIdentifier$Id))
    col_votes <- c(col_votes, parse_integer(selection[[i]]$ValidVotes))
  }
  return(tibble(party = as_factor(col_party), party_id = col_pid, candidate_id = col_cid, votes = col_votes))
}


emls <- list.files("raw_data/Gemeente tellingen/", pattern = ".eml.xml", full.names = TRUE)
clus <- makeCluster(10)
clusterEvalQ(clus, {
  library(tidyverse)
  library(emld)
})
clusterExport(clus, c("extract_data", "selection_to_votes"))


pboptions(use_lb = TRUE)

pbwalk(emls, function(p) {
  gid <- readLines(p, warn = FALSE) |> str_extract("AuthorityIdentifier Id=\"(\\d+)\"", group = 1)
  outpath <- paste0("processed_data/gemeente/", gid, ".rds")
  if (file.exists(outpath)) {
    cat("\nFile exists:", outpath)
    return()
  }
    
  eml <- as_emld(p)
  df <- tryCatch(
    extract_data(eml), 
    error = function(err) {
      cat("error in ", p, ": ", err$message)
      return(NULL)
    }
  )
  if (!is.null(df))
    write_rds(df, paste0("processed_data/gemeente/", as.character(df$gemeente_id[1]), ".rds"))
}, cl = clus)


stopCluster(clus)

