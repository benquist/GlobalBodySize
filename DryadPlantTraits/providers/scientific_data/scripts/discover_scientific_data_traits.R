#!/usr/bin/env Rscript
# discover_scientific_data_traits.R
# CLI discovery pipeline for plant trait datasets published in Scientific Data.
# Uses CrossRef to find papers (ISSN 2052-4463) and resolves data repo links.
#
# Usage:
#   Rscript providers/scientific_data/scripts/discover_scientific_data_traits.R \
#     --output-dir=output/providers/scientific_data \
#     --pages-per-term=3 \
#     --per-page=20 \
#     --resume=TRUE

# ---------------------------------------------------------------------------
# Locate project root
# ---------------------------------------------------------------------------

sdata_find_project_root <- function() {
  cwd <- getwd()
  if (basename(cwd) == "DryadPlantTraits") return(cwd)
  if (basename(cwd) == "scripts" &&
      basename(dirname(cwd)) == "scientific_data" &&
      grepl("providers$", dirname(dirname(cwd)))) {
    return(dirname(dirname(dirname(cwd))))
  }
  probe <- file.path(cwd, "DryadPlantTraits")
  if (dir.exists(probe)) return(probe)
  stop("Cannot locate DryadPlantTraits project root from: ", cwd, call. = FALSE)
}

project_root <- sdata_find_project_root()

# ---------------------------------------------------------------------------
# Source dependencies
# ---------------------------------------------------------------------------

source(file.path(project_root, "providers", "common", "R", "provider_common.R"), local = FALSE)
source(file.path(project_root, "R", "search_terms.R"),                          local = FALSE)
source(file.path(project_root, "R", "candidate_filter.R"),                      local = FALSE)
source(file.path(project_root, "R", "dryad_api.R"),                             local = FALSE)
source(file.path(project_root, "providers", "scientific_data", "R", "scientific_data_api.R"), local = FALSE)
source(file.path(project_root, "providers", "scientific_data", "R", "repo_resolver.R"),       local = FALSE)

# ---------------------------------------------------------------------------
# File-support helpers (mirrors dryad_is_supported_* from io_helpers.R)
# ---------------------------------------------------------------------------

sdata_is_supported_tabular <- function(file_name) {
  if (is.na(file_name) || !nzchar(file_name)) return(FALSE)
  lower <- tolower(file_name)
  any(endsWith(lower, c(".csv", ".tsv", ".txt", ".tab", ".xlsx", ".xls")))
}

sdata_is_supported_archive <- function(file_name) {
  if (is.na(file_name) || !nzchar(file_name)) return(FALSE)
  lower <- tolower(file_name)
  any(endsWith(lower, c(".zip", ".tar", ".tar.gz", ".tgz", ".gz")))
}

# ---------------------------------------------------------------------------
# Parse CLI args
# ---------------------------------------------------------------------------

args           <- provider_parse_named_args(commandArgs(trailingOnly = TRUE))
output_dir     <- args$`output-dir`      %||% args$output_dir     %||%
                  file.path(project_root, "output", "providers", "scientific_data")
pages_per_term <- as.integer(args$`pages-per-term` %||% "3")
per_page       <- as.integer(args$`per-page`       %||% "20")
resume         <- identical(args$resume, "TRUE")

# ---------------------------------------------------------------------------
# Prepare output directory
# ---------------------------------------------------------------------------

if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# Load search terms
# ---------------------------------------------------------------------------

search_terms <- dryad_search_seed_terms()
query_terms  <- unique(search_terms$query_term)

# ---------------------------------------------------------------------------
# Phase 1: CrossRef search — collect candidate datasets
# ---------------------------------------------------------------------------

dataset_checkpoint_path <- file.path(output_dir, "sdata_search_checkpoint.csv")
dataset_rows    <- list()
fetched_combos  <- character(0)
first_ds_write  <- TRUE

if (resume && file.exists(dataset_checkpoint_path)) {
  existing_ds <- utils::read.csv(dataset_checkpoint_path, stringsAsFactors = FALSE, check.names = FALSE)
  if (nrow(existing_ds) && all(c("query_term", "fetch_page") %in% names(existing_ds))) {
    fetched_combos <- paste(existing_ds$query_term, existing_ds$fetch_page, sep = "\t")
    dataset_rows   <- list(existing_ds)
    first_ds_write <- FALSE
    message(sprintf("Resuming: loaded %d existing dataset rows from checkpoint.", nrow(existing_ds)))
  }
}

for (query_term in query_terms) {
  total_results <- Inf

  for (page_index in seq_len(pages_per_term)) {
    combo_key <- paste(query_term, page_index, sep = "\t")
    if (combo_key %in% fetched_combos) next

    offset <- (page_index - 1L) * per_page
    if (is.finite(total_results) && offset >= total_results) break

    message(sprintf("Searching CrossRef: '%s' page %d (offset %d)", query_term, page_index, offset))
    payload <- sdata_crossref_search(query_term, rows = per_page, offset = offset)

    # Update total results from first successful response
    if (!is.null(payload) && !is.null(payload[["message"]][["total-results"]])) {
      total_results <- as.integer(payload[["message"]][["total-results"]])
    }

    rows <- sdata_flatten_crossref_results(payload, query_term = query_term)
    if (is.null(rows) || nrow(rows) == 0L) next

    # Score candidates
    score_list <- lapply(seq_len(nrow(rows)), function(i) {
      sdata_score_candidate(rows$title[[i]], rows$abstract[[i]], rows$source_subjects[[i]])
    })
    rows$candidate_score    <- vapply(score_list, function(s) as.numeric(s$candidate_score), numeric(1))
    rows$candidate_keep     <- vapply(score_list, function(s) as.logical(s$candidate_keep),  logical(1))
    rows$candidate_rationale <- vapply(score_list, function(s) as.character(s$candidate_rationale), character(1))
    rows$fetch_page          <- page_index

    dataset_rows[[length(dataset_rows) + 1L]] <- rows
    utils::write.table(
      rows, dataset_checkpoint_path,
      sep = ",", row.names = FALSE, na = "",
      append = !first_ds_write, col.names = first_ds_write,
      qmethod = "double"
    )
    first_ds_write <- FALSE

    if (is.finite(total_results) && (offset + per_page) >= total_results) break
  }
}

all_datasets <- if (length(dataset_rows)) {
  do.call(rbind, dataset_rows)
} else {
  provider_dataset_schema(0L)
}

# Deduplicate by DOI — keep row with highest candidate_score
if (nrow(all_datasets) > 0L && "provider_dataset_id" %in% names(all_datasets)) {
  all_datasets <- all_datasets[order(-all_datasets$candidate_score, all_datasets$title), , drop = FALSE]
  all_datasets <- all_datasets[!duplicated(all_datasets$provider_dataset_id), , drop = FALSE]
}

candidate_datasets <- all_datasets[!is.na(all_datasets$candidate_keep) & all_datasets$candidate_keep, , drop = FALSE]

message(sprintf(
  "CrossRef search complete: %d total papers, %d candidate datasets.",
  nrow(all_datasets), nrow(candidate_datasets)
))

# ---------------------------------------------------------------------------
# Phase 2: Resolve data repository links for candidate datasets
# ---------------------------------------------------------------------------

files_checkpoint_path <- file.path(output_dir, "sdata_files_checkpoint.csv")
file_rows      <- list()
resolved_ids   <- character(0)
first_file_write <- TRUE

if (resume && file.exists(files_checkpoint_path)) {
  existing_files <- utils::read.csv(files_checkpoint_path, stringsAsFactors = FALSE, check.names = FALSE)
  if (nrow(existing_files) && "provider_dataset_id" %in% names(existing_files)) {
    resolved_ids     <- unique(existing_files$provider_dataset_id)
    file_rows        <- list(existing_files)
    first_file_write <- FALSE
    message(sprintf("Resuming: %d already-resolved dataset IDs from files checkpoint.", length(resolved_ids)))
  }
}

if (nrow(candidate_datasets) > 0L) {
  for (row_index in seq_len(nrow(candidate_datasets))) {
    dataset_doi  <- candidate_datasets$provider_dataset_id[[row_index]]
    data_links   <- candidate_datasets$data_links[[row_index]]

    if (dataset_doi %in% resolved_ids) next
    if (is.na(data_links) || !nzchar(trimws(data_links))) {
      resolved_ids <- c(resolved_ids, dataset_doi)
      next
    }

    message(sprintf("Resolving data links for %s", dataset_doi))

    resolved_files <- tryCatch(
      sdata_resolve_data_links(data_links),
      error = function(e) {
        warning(sprintf("discover_scientific_data: error resolving '%s': %s",
                        dataset_doi, conditionMessage(e)))
        sdata_empty_file_table()
      }
    )

    if (is.null(resolved_files) || nrow(resolved_files) == 0L) {
      resolved_ids <- c(resolved_ids, dataset_doi)
      next
    }

    # Build provider_file_schema-compliant rows
    file_table <- provider_file_schema(nrow(resolved_files))

    file_table$source_provider    <- "scientific_data"
    file_table$provider_dataset_id <- dataset_doi
    file_table$provider_file_id   <- paste(
      resolved_files$repo_type,
      resolved_files$repo_id,
      resolved_files$file_name,
      sep = "::"
    )
    file_table$file_path          <- resolved_files$file_name
    file_table$file_size          <- resolved_files$file_size
    file_table$mime_type          <- resolved_files$mime_type
    file_table$file_status        <- NA_character_
    file_table$download_href      <- resolved_files$download_url
    file_table$candidate_score    <- candidate_datasets$candidate_score[[row_index]]
    file_table$candidate_keep     <- candidate_datasets$candidate_keep[[row_index]]
    file_table$query_term         <- candidate_datasets$query_term[[row_index]]
    file_table$source_title       <- candidate_datasets$title[[row_index]]
    file_table$source_authors     <- candidate_datasets$authors[[row_index]]
    file_table$source_subjects    <- candidate_datasets$source_subjects[[row_index]]
    file_table$source_abstract    <- candidate_datasets$abstract[[row_index]]
    file_table$file_supported_tabular   <- vapply(
      resolved_files$file_name, sdata_is_supported_tabular, logical(1)
    )
    file_table$file_supported_container <- vapply(
      resolved_files$file_name, sdata_is_supported_archive, logical(1)
    )

    file_rows[[length(file_rows) + 1L]] <- file_table
    utils::write.table(
      file_table, files_checkpoint_path,
      sep = ",", row.names = FALSE, na = "",
      append = !first_file_write, col.names = first_file_write,
      qmethod = "double"
    )
    first_file_write <- FALSE
    resolved_ids <- c(resolved_ids, dataset_doi)
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

# Drop provider-specific extra columns before writing dataset schema output
dataset_out_cols <- c(
  "source_provider", "provider_dataset_id", "query_term", "title", "authors",
  "abstract", "source_subjects", "field_of_science", "storage_size",
  "candidate_score", "candidate_keep", "candidate_rationale"
)
extra_cols <- setdiff(names(all_datasets), dataset_out_cols)
dataset_output <- all_datasets[, c(dataset_out_cols, extra_cols), drop = FALSE]

utils::write.csv(
  dataset_output,
  file.path(output_dir, "candidate_datasets.csv"),
  row.names = FALSE, na = ""
)
utils::write.csv(
  all_files,
  file.path(output_dir, "candidate_files.csv"),
  row.names = FALSE, na = ""
)

message(sprintf(
  "Scientific Data discovery complete: %d papers, %d candidate datasets, %d files.",
  nrow(all_datasets),
  nrow(candidate_datasets),
  nrow(all_files)
))
