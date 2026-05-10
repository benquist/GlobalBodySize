## scripts/run_taxon_reconciliation.R
## Run GBIF backbone reconciliation on tier1_combined.csv
## Output: data/compiled/tier1_reconciled.csv + data/compiled/taxon_match_cache.csv

suppressPackageStartupMessages({
  library(data.table)
})

source("R/taxon_reconciliation.R")

TIER1_FILE  <- "data/compiled/tier1_combined.csv"
OUT_FILE    <- "data/compiled/tier1_reconciled.csv"
CACHE_FILE  <- "data/compiled/taxon_match_cache.csv"

if (!file.exists(TIER1_FILE)) {
  stop("Run scripts/merge_tier1.R first: ", TIER1_FILE, " not found.", call. = FALSE)
}

message("Reading tier1_combined.csv...")
tier1 <- data.table::fread(TIER1_FILE, data.table = FALSE)
message(sprintf("  %d rows loaded", nrow(tier1)))

## Unique verbatim taxon names to reconcile (not re-querying cached names)
names_to_query <- unique(trimws(tier1$verbatim_taxon_name))
names_to_query <- names_to_query[nzchar(names_to_query)]
message(sprintf("  %d unique verbatim taxon names to reconcile", length(names_to_query)))

## Run reconciliation (uses cache to skip previously queried names)
matches <- gbif_reconcile_names(
  names_vec   = names_to_query,
  cache_file  = CACHE_FILE,
  batch_size  = 200,
  verbose     = TRUE
)

message(sprintf("Reconciliation complete: %d matches returned", nrow(matches)))

## Merge match results back onto tier1 rows by verbatim_taxon_name
tier1_rec <- merge(
  tier1, matches,
  by.x = "verbatim_taxon_name",
  by.y = "input_name_verbatim",
  all.x = TRUE
)

## Summary
n_exact    <- sum(tier1_rec$match_type == "EXACT",    na.rm = TRUE)
n_fuzzy    <- sum(tier1_rec$match_type == "FUZZY",    na.rm = TRUE)
n_none     <- sum(is.na(tier1_rec$match_type) | tier1_rec$match_type %in% c("NONE","error"), na.rm = TRUE)
n_synonym  <- sum(grepl("SYNONYM", tier1_rec$matched_status %||% "", ignore.case = TRUE), na.rm = TRUE)

message(sprintf("Match summary: EXACT=%d  FUZZY=%d  NONE/error=%d  SYNONYM=%d",
                n_exact, n_fuzzy, n_none, n_synonym))

dir.create("data/compiled", recursive = TRUE, showWarnings = FALSE)
data.table::fwrite(tier1_rec, OUT_FILE)
message(sprintf("tier1_reconciled.csv written: %d rows -> %s", nrow(tier1_rec), OUT_FILE))
