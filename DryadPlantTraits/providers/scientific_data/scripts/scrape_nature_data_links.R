#!/usr/bin/env Rscript
# scrape_nature_data_links.R
# Scrapes Nature.com landing pages for Scientific Data papers that have no
# resolved data repository links, then optionally re-runs Phase 2 file resolution.
#
# Usage (from any directory):
#   Rscript scrape_nature_data_links.R \
#     [--candidate-csv=<path>]    # default: output/providers/scientific_data/providers/scientific_data/candidate_datasets.csv
#     [--output-dir=<dir>]        # default: output/providers/scientific_data
#     [--dry-run=TRUE]            # print links without writing
#     [--sleep=2]                 # seconds between Nature requests (default 2)

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x

# --- Locate project root ---
find_sdata_project_root <- function() {
  cwd <- getwd()
  if (basename(cwd) == "DryadPlantTraits") return(cwd)
  if (basename(cwd) == "scripts" && basename(dirname(cwd)) %in% c("DryadPlantTraits", "scientific_data")) {
    candidate <- dirname(dirname(dirname(cwd)))  # scripts -> scientific_data -> providers -> DryadPlantTraits
    if (basename(candidate) == "DryadPlantTraits") return(candidate)
    candidate2 <- dirname(cwd)  # scripts -> DryadPlantTraits
    if (basename(candidate2) == "DryadPlantTraits") return(candidate2)
  }
  probe <- file.path(cwd, "DryadPlantTraits")
  if (dir.exists(probe)) return(probe)
  stop("Cannot locate DryadPlantTraits project root from: ", cwd, call. = FALSE)
}

root       <- find_sdata_project_root()
sdata_root <- file.path(root, "providers", "scientific_data")
common_r   <- file.path(root, "providers", "common", "R", "provider_common.R")

source(file.path(root, "R", "dryad_api.R"))
if (file.exists(common_r)) source(common_r)
source(file.path(sdata_root, "R", "repo_resolver.R"))
source(file.path(sdata_root, "R", "nature_scraper.R"))

# --- Parse args ---
args <- if (exists("provider_parse_named_args")) {
  provider_parse_named_args(commandArgs(trailingOnly = TRUE))
} else {
  raw <- commandArgs(trailingOnly = TRUE)
  vals <- list()
  for (a in raw) {
    if (!startsWith(a, "--")) next
    parts <- strsplit(sub("^--", "", a), "=", fixed = TRUE)[[1]]
    vals[[parts[1]]] <- if (length(parts) > 1L) paste(parts[-1L], collapse = "=") else "TRUE"
  }
  vals
}

output_dir    <- args$`output-dir` %||% file.path(root, "output", "providers", "scientific_data")
candidate_csv <- args$`candidate-csv` %||%
  file.path(root, "output", "providers", "scientific_data", "providers", "scientific_data", "candidate_datasets.csv")
dry_run       <- isTRUE(args$`dry-run` == "TRUE")
sleep_sec     <- as.numeric(args$sleep %||% "2")

message("=== Nature Landing-Page Scraper for Scientific Data ===")
message("Candidate CSV : ", candidate_csv)
message("Output dir    : ", output_dir)
message("Dry run       : ", dry_run)

# --- Load candidates ---
if (!file.exists(candidate_csv)) {
  stop("Candidate CSV not found: ", candidate_csv, call. = FALSE)
}
candidates <- read.csv(candidate_csv, stringsAsFactors = FALSE)
message(sprintf("Loaded %d candidate papers.", nrow(candidates)))

# Target: keep=TRUE rows with no data_links (or only the paper URL itself)
kept <- candidates[isTRUE(candidates$candidate_keep) | candidates$candidate_keep == "TRUE", , drop = FALSE]

is_empty_link <- function(x) {
  is.na(x) | !nzchar(trimws(x)) |
  # Only the Nature landing page URL itself — no actual data repo link
  grepl("^https?://(www\\.nature\\.com|doi\\.org/10\\.1038)/", trimws(x)) &
  !grepl("10\\.(6084|5281|5061|1594)", trimws(x))
}

no_data_links <- kept[is_empty_link(kept$data_links), , drop = FALSE]
message(sprintf("Papers with no resolved data links: %d", nrow(no_data_links)))

if (nrow(no_data_links) == 0L) {
  message("All kept papers already have data links — nothing to scrape.")
  quit(save = "no", status = 0L)
}

# --- Scrape ---
message(sprintf("\nScraping %d Nature.com landing pages (sleep=%.1fs between requests)...",
                nrow(no_data_links), sleep_sec))

scraped <- nature_scrape_batch(no_data_links$doi, sleep_sec = sleep_sec, verbose = TRUE)

message("\n=== Scrape Results ===")
print(scraped[, c("doi", "data_links", "scrape_status")])

found <- scraped[!is.na(scraped$data_links), , drop = FALSE]
message(sprintf("\n%d / %d papers returned data links from Nature.com.", nrow(found), nrow(scraped)))

if (dry_run) {
  message("\nDry run — not writing any files.")
  quit(save = "no", status = 0L)
}

# --- Merge back into candidates ---
if (nrow(found) > 0L) {
  for (i in seq_len(nrow(found))) {
    doi_i <- found$doi[i]
    links_i <- found$data_links[i]
    row_idx <- which(candidates$doi == doi_i)
    if (!length(row_idx)) next

    existing <- trimws(candidates$data_links[row_idx[1]])
    if (is.na(existing) || !nzchar(existing)) {
      candidates$data_links[row_idx[1]] <- links_i
    } else {
      # Append new links
      all_links <- unique(c(
        strsplit(existing, ",\\s*")[[1]],
        strsplit(links_i, ",\\s*")[[1]]
      ))
      candidates$data_links[row_idx[1]] <- paste(trimws(all_links), collapse = ", ")
    }
  }
}

# Write updated candidate_datasets.csv
write.csv(candidates, candidate_csv, row.names = FALSE, na = "")
message("\nUpdated candidate_datasets.csv written to: ", candidate_csv)

# Write scrape log
scrape_log_path <- file.path(output_dir, "nature_scrape_log.csv")
write.csv(scraped, scrape_log_path, row.names = FALSE, na = "")
message("Scrape log written to: ", scrape_log_path)

message("\nDone. Run phase2_resolve_sdata_files.R to resolve files from newly added links.")
