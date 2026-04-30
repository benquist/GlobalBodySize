#!/usr/bin/env Rscript
# discover_zenodo_traits.R
# CLI discovery pipeline for plant trait datasets on Zenodo.
# Uses the Zenodo public REST API (no API key required for public records).
#
# Rate limits:
#   - Unauthenticated: 100 requests/hour  → use --max-pages=2 or set ZENODO_API_TOKEN
#   - Authenticated:   5000 requests/hour → set ZENODO_API_TOKEN env var
#
# Usage:
#   # Unauthenticated (safe, slow):
#   Rscript providers/zenodo/scripts/discover_zenodo_traits.R \
#     --output-dir=output/providers/zenodo \
#     --per-page=100 \
#     --max-pages=2 \
#     --resume=TRUE
#
#   # Authenticated (recommended for full run):
#   export ZENODO_API_TOKEN="<your_token>"
#   Rscript providers/zenodo/scripts/discover_zenodo_traits.R \
#     --output-dir=output/providers/zenodo \
#     --per-page=100 \
#     --max-pages=20 \
#     --resume=TRUE

# ---------------------------------------------------------------------------
# Locate project root
# ---------------------------------------------------------------------------

zenodo_find_project_root <- function() {
  cwd <- getwd()
  if (basename(cwd) == "DryadPlantTraits") return(cwd)
  if (basename(cwd) == "scripts" &&
      basename(dirname(cwd)) == "zenodo" &&
      grepl("providers$", dirname(dirname(cwd)))) {
    return(dirname(dirname(dirname(cwd))))
  }
  probe <- file.path(cwd, "DryadPlantTraits")
  if (dir.exists(probe)) return(probe)
  stop("Cannot locate DryadPlantTraits project root from: ", cwd, call. = FALSE)
}

project_root <- zenodo_find_project_root()

# ---------------------------------------------------------------------------
# Source dependencies
# ---------------------------------------------------------------------------

source(file.path(project_root, "providers", "common", "R", "provider_common.R"), local = FALSE)
source(file.path(project_root, "R", "search_terms.R"),                           local = FALSE)
source(file.path(project_root, "R", "candidate_filter.R"),                       local = FALSE)
source(file.path(project_root, "R", "dryad_api.R"),                              local = FALSE)
source(file.path(project_root, "providers", "zenodo", "R", "zenodo_api.R"),      local = FALSE)

# ---------------------------------------------------------------------------
# Parse CLI args
# ---------------------------------------------------------------------------

args           <- provider_parse_named_args(commandArgs(trailingOnly = TRUE))
base_output_dir <- args$`output-dir` %||% args$output_dir %||%
                   file.path(project_root, "output")
output_dir  <- file.path(base_output_dir, "providers", "zenodo")
per_page    <- min(as.integer(args$`per-page`  %||% "100"), 100L)
max_pages   <- as.integer(args$`max-pages` %||% "20")
resume      <- identical(args$resume, "TRUE")

if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

tok <- Sys.getenv("ZENODO_API_TOKEN", unset = "")
if (nzchar(tok)) {
  message("ZENODO_API_TOKEN set — using authenticated requests (5000 req/hr limit).")
} else {
  message("No ZENODO_API_TOKEN — unauthenticated (100 req/hr limit). Consider --max-pages=2 or set ZENODO_API_TOKEN.")
}

# ---------------------------------------------------------------------------
# Phase 1: Search Zenodo using seed terms, score, checkpoint
# ---------------------------------------------------------------------------

dataset_checkpoint_path <- file.path(output_dir, "zenodo_search_checkpoint.csv")
dataset_rows  <- list()
seen_ids      <- character(0)       # provider_dataset_id values already seen
first_ds_write <- TRUE
completed_terms <- character(0)

if (resume && file.exists(dataset_checkpoint_path)) {
  existing_ds <- utils::read.csv(dataset_checkpoint_path,
                                 stringsAsFactors = FALSE, check.names = FALSE)
  if (nrow(existing_ds) && "provider_dataset_id" %in% names(existing_ds)) {
    seen_ids      <- unique(existing_ds$provider_dataset_id)
    dataset_rows  <- list(existing_ds)
    first_ds_write <- FALSE
    if ("query_term" %in% names(existing_ds)) {
      completed_terms <- unique(existing_ds$query_term[!is.na(existing_ds$query_term)])
    }
    message(sprintf(
      "Resuming: %d unique records from %d query terms already fetched.",
      length(seen_ids), length(completed_terms)
    ))
  }
}

# Build search term list from the shared seed terms
all_terms_df  <- dryad_search_seed_terms()
all_terms     <- unique(all_terms_df$query_term)
pending_terms <- all_terms[!all_terms %in% completed_terms]

message(sprintf(
  "Zenodo search terms: %d total, %d completed, %d pending.",
  length(all_terms), length(completed_terms), length(pending_terms)
))

for (term in pending_terms) {
  message(sprintf("Searching Zenodo for: %s", term))

  page      <- 1L
  term_new  <- 0L

  repeat {
    if (page > max_pages) {
      message(sprintf("  Reached max_pages=%d for term '%s'", max_pages, term))
      break
    }

    message(sprintf("  Page %d", page))

    parsed <- zenodo_search(query = term, type = "dataset", size = per_page, page = page)

    if (is.null(parsed)) {
      warning(sprintf("  No response for term '%s' page %d — rate limited or error; term will retry on next --resume=TRUE run.", term, page))
      term_new <- -1L   # sentinel: term failed, do not mark complete
      break
    }

    total_hits <- as.integer(parsed$hits$total %||% 0L)
    hits       <- parsed$hits$hits %||% list()

    if (!length(hits)) break

    rows <- zenodo_flatten_hits(parsed, query_term = term)

    if (nrow(rows) > 0L) {
      new_rows <- rows[!rows$provider_dataset_id %in% seen_ids, , drop = FALSE]

      if (nrow(new_rows) > 0L) {
        score_list <- lapply(seq_len(nrow(new_rows)), function(i) {
          zenodo_score_candidate(
            title    = new_rows$title[[i]],
            abstract = new_rows$abstract[[i]],
            subjects = new_rows$source_subjects[[i]]
          )
        })

        new_rows$candidate_score     <- vapply(score_list, function(s) as.numeric(s$candidate_score),  numeric(1))
        new_rows$candidate_keep      <- vapply(score_list, function(s) as.logical(s$candidate_keep),   logical(1))
        new_rows$candidate_rationale <- vapply(score_list, function(s) as.character(s$candidate_rationale), character(1))

        seen_ids  <- c(seen_ids, new_rows$provider_dataset_id)
        term_new  <- term_new + nrow(new_rows)
        dataset_rows[[length(dataset_rows) + 1L]] <- new_rows

        utils::write.table(
          new_rows, dataset_checkpoint_path,
          sep = ",", row.names = FALSE, na = "",
          append = !first_ds_write, col.names = first_ds_write,
          qmethod = "double"
        )
        first_ds_write <- FALSE
      }
    }

    # Zenodo paginates in pages; stop when we've seen all results
    fetched_so_far <- (page - 1L) * per_page + length(hits)
    if (fetched_so_far >= total_hits || length(hits) < per_page) break
    page <- page + 1L
  }

  if (term_new >= 0L) {
    message(sprintf("  Term '%s' done: %d new records (cumulative: %d)", term, term_new, length(seen_ids)))
    completed_terms <- c(completed_terms, term)
  } else {
    message(sprintf("  Term '%s' SKIPPED (rate limited) — will retry with --resume=TRUE.", term))
  }
}

# Always rebuild from checkpoint so that 429-aborted runs don't erase prior results
all_datasets <- if (file.exists(dataset_checkpoint_path)) {
  utils::read.csv(dataset_checkpoint_path, stringsAsFactors = FALSE, check.names = FALSE)
} else if (length(dataset_rows)) {
  do.call(rbind, dataset_rows)
} else {
  provider_dataset_schema(0L)
}

# Deduplicate by provider_dataset_id, keep highest score
if (nrow(all_datasets) > 0L) {
  all_datasets <- all_datasets[order(-all_datasets$candidate_score, all_datasets$title), , drop = FALSE]
  all_datasets <- all_datasets[!duplicated(all_datasets$provider_dataset_id), , drop = FALSE]
}

candidate_datasets <- all_datasets[
  !is.na(all_datasets$candidate_keep) & all_datasets$candidate_keep, , drop = FALSE
]

message(sprintf(
  "Zenodo search complete: %d total records, %d candidate datasets.",
  nrow(all_datasets), nrow(candidate_datasets)
))

# ---------------------------------------------------------------------------
# Phase 2: Fetch file lists for candidate datasets
# ---------------------------------------------------------------------------

files_checkpoint_path <- file.path(output_dir, "zenodo_files_checkpoint.csv")
file_rows       <- list()
resolved_ids    <- character(0)
first_file_write <- TRUE

if (resume && file.exists(files_checkpoint_path)) {
  existing_files <- utils::read.csv(files_checkpoint_path,
                                    stringsAsFactors = FALSE, check.names = FALSE)
  if (nrow(existing_files) && "provider_dataset_id" %in% names(existing_files)) {
    resolved_ids     <- unique(existing_files$provider_dataset_id)
    file_rows        <- list(existing_files)
    first_file_write <- FALSE
    message(sprintf("Resuming: %d already-resolved datasets from files checkpoint.", length(resolved_ids)))
  }
}

if (nrow(candidate_datasets) > 0L) {
  for (row_index in seq_len(nrow(candidate_datasets))) {
    ds_id     <- candidate_datasets$provider_dataset_id[[row_index]]
    record_id <- candidate_datasets$zenodo_record_id[[row_index]]

    if (ds_id %in% resolved_ids) next
    if (is.na(record_id) || !nzchar(trimws(record_id))) {
      resolved_ids <- c(resolved_ids, ds_id)
      next
    }

    message(sprintf("Fetching files for %s", ds_id))

    files_df <- tryCatch(
      zenodo_fetch_files(record_id),
      error = function(e) {
        warning(sprintf("discover_zenodo: error fetching files for %s: %s",
                        ds_id, conditionMessage(e)))
        zenodo_empty_file_table()
      }
    )

    if (is.null(files_df) || nrow(files_df) == 0L) {
      resolved_ids <- c(resolved_ids, ds_id)
      next
    }

    n_files    <- nrow(files_df)
    file_table <- provider_file_schema(n_files)

    file_table$source_provider     <- "zenodo"
    file_table$provider_dataset_id <- ds_id
    file_table$provider_file_id    <- paste(ds_id, files_df$file_name, sep = "::")
    file_table$file_path           <- files_df$file_name
    file_table$file_size           <- files_df$file_size
    file_table$mime_type           <- files_df$mime_type
    file_table$file_status         <- NA_character_
    file_table$download_href       <- files_df$download_url
    file_table$candidate_score     <- candidate_datasets$candidate_score[[row_index]]
    file_table$candidate_keep      <- candidate_datasets$candidate_keep[[row_index]]
    file_table$query_term          <- candidate_datasets$query_term[[row_index]]
    file_table$source_title        <- candidate_datasets$title[[row_index]]
    file_table$source_authors      <- candidate_datasets$authors[[row_index]]
    file_table$source_subjects     <- candidate_datasets$source_subjects[[row_index]]
    file_table$source_abstract     <- candidate_datasets$abstract[[row_index]]
    file_table$file_supported_tabular   <- vapply(files_df$file_name, zenodo_is_supported_tabular,  logical(1))
    file_table$file_supported_container <- vapply(files_df$file_name, zenodo_is_supported_archive, logical(1))

    file_rows[[length(file_rows) + 1L]] <- file_table
    utils::write.table(
      file_table, files_checkpoint_path,
      sep = ",", row.names = FALSE, na = "",
      append = !first_file_write, col.names = first_file_write,
      qmethod = "double"
    )
    first_file_write <- FALSE
    resolved_ids <- c(resolved_ids, ds_id)
  }
}

all_files <- if (length(file_rows)) {
  do.call(rbind, file_rows)
} else {
  provider_file_schema(0L)
}

# ---------------------------------------------------------------------------
# Write final outputs
# ---------------------------------------------------------------------------

utils::write.csv(
  all_datasets,
  file.path(output_dir, "candidate_datasets.csv"),
  row.names = FALSE, na = ""
)

utils::write.csv(
  all_files,
  file.path(output_dir, "candidate_files.csv"),
  row.names = FALSE, na = ""
)

n_supported <- if (nrow(all_files)) {
  sum(all_files$file_supported_tabular | all_files$file_supported_container, na.rm = TRUE)
} else 0L

message(sprintf(
  "Zenodo discovery complete: %d records searched, %d candidate datasets, %d files (%d tabular/archive).",
  nrow(all_datasets),
  nrow(candidate_datasets),
  nrow(all_files),
  n_supported
))
message(sprintf("Outputs written to: %s", output_dir))
