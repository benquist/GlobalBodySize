#!/usr/bin/env Rscript
# populate_sdata_data_links_from_crossref.R
# Fetches data repository links from CrossRef for Scientific Data papers
# with missing data_links, then writes the updated candidate_datasets.csv.
#
# Usage:
#   Rscript populate_sdata_data_links_from_crossref.R \
#     --candidate-csv=DryadPlantTraits/output/providers/scientific_data/providers/scientific_data/candidate_datasets.csv \
#     --output-csv=DryadPlantTraits/output/providers/scientific_data/providers/scientific_data/candidate_datasets.csv

# Define %||% operator (null coalescing)
`%||%` <- function(x, y) if (is.null(x)) y else x

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
arg_list <- list()
for (arg in args) {
  if (grepl("^--", arg)) {
    kv <- sub("^--", "", arg)
    if (grepl("=", kv)) {
      k <- sub("=.*", "", kv)
      v <- sub("^[^=]+=", "", kv)
      arg_list[[k]] <- v
    }
  }
}

candidate_csv <- arg_list$`candidate-csv` %||% "DryadPlantTraits/output/providers/scientific_data/providers/scientific_data/candidate_datasets.csv"
output_csv    <- arg_list$`output-csv` %||% candidate_csv

if (!file.exists(candidate_csv)) {
  stop("candidate_csv does not exist: ", candidate_csv, call. = FALSE)
}

# ---------------------------------------------------------------------------
# Locate project root and source dependencies
# ---------------------------------------------------------------------------

# Find project root: look for DryadPlantTraits parent
cwd <- getwd()
if (basename(cwd) == "DryadPlantTraits") {
  project_root <- cwd
} else if (dir.exists(file.path(cwd, "DryadPlantTraits"))) {
  project_root <- file.path(cwd, "DryadPlantTraits")
} else {
  # Walk up directories looking for DryadPlantTraits
  probe <- cwd
  for (i in 1:5) {
    probe <- dirname(probe)
    if (file.exists(file.path(probe, "DryadPlantTraits", "R", "dryad_api.R"))) {
      project_root <- file.path(probe, "DryadPlantTraits")
      break
    }
  }
}

if (!dir.exists(project_root) || !file.exists(file.path(project_root, "R", "dryad_api.R"))) {
  stop("Cannot locate DryadPlantTraits project root from: ", cwd, call. = FALSE)
}

message("Project root: ", project_root)

source(file.path(project_root, "R", "dryad_api.R"),  local = FALSE)
source(file.path(project_root, "providers", "scientific_data", "R", "crossref_api.R"), local = FALSE)

# ---------------------------------------------------------------------------
# Load candidate datasets
# ---------------------------------------------------------------------------

message("Loading candidate_datasets from: ", candidate_csv)
candidate_datasets <- tryCatch(
  utils::read.csv(candidate_csv, stringsAsFactors = FALSE, check.names = FALSE),
  error = function(e) {
    stop("Failed to read candidate_csv: ", conditionMessage(e), call. = FALSE)
  }
)

message(sprintf("Loaded %d rows with %d columns.", nrow(candidate_datasets), ncol(candidate_datasets)))

# Identify rows with missing data_links
missing_indices <- which(is.na(candidate_datasets$data_links) | !nzchar(trimws(candidate_datasets$data_links %||% "")))
message(sprintf("Found %d rows with missing/empty data_links.", length(missing_indices)))

if (!length(missing_indices)) {
  message("All data_links populated — nothing to do.")
  quit(status = 0)
}

# Filter to kept papers only (for efficiency)
if ("candidate_keep" %in% names(candidate_datasets)) {
  kept_indices <- which(missing_indices %in% which(candidate_datasets$candidate_keep %in% TRUE))
  message(sprintf("Filtering to %d kept papers with missing data_links.", length(kept_indices)))
  missing_indices <- missing_indices[kept_indices]
}

if (!length(missing_indices)) {
  message("No kept papers with missing data_links — nothing to do.")
  quit(status = 0)
}

# ---------------------------------------------------------------------------
# Fetch CrossRef relations for papers with missing data_links
# ---------------------------------------------------------------------------

message("\nFetching CrossRef relations for papers with missing data_links...")

for (idx in missing_indices) {
  doi <- candidate_datasets$doi[idx]
  if (is.na(doi) || !nzchar(trimws(doi))) next

  message(sprintf("  [%d/%d] Fetching CrossRef for %s", which(missing_indices == idx), length(missing_indices), doi))

  relations <- crossref_fetch_paper_relations(doi)

  if (length(relations$links) > 0L) {
    data_links_str <- paste(relations$links, collapse = ", ")
    message(sprintf("    Found %d links: %s", length(relations$links), data_links_str))
    candidate_datasets$data_links[idx] <- data_links_str
  } else {
    message(sprintf("    No links found. Error: %s", relations$error %||% "Unknown"))
  }

  Sys.sleep(0.5)
}

# ---------------------------------------------------------------------------
# Write updated CSV
# ---------------------------------------------------------------------------

message("\nWriting updated candidate_datasets to: ", output_csv)
utils::write.csv(candidate_datasets, output_csv, row.names = FALSE)
message(sprintf("✓ Wrote %d rows.", nrow(candidate_datasets)))

# Summary
updated <- length(which(!is.na(candidate_datasets$data_links[missing_indices]) & nzchar(trimws(candidate_datasets$data_links[missing_indices] %||% ""))))
message(sprintf("\nSummary: Updated %d / %d rows with data_links.", updated, length(missing_indices)))
