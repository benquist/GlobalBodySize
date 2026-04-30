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
base_output_dir <- args$`output-dir`      %||% args$output_dir     %||%
                  file.path(project_root, "output")
output_dir <- file.path(base_output_dir, "providers", "scientific_data")
per_page       <- as.integer(args$`per-page` %||% "100")
resume         <- identical(args$resume, "TRUE")

# CrossRef's offset pagination for ISSN-filtered queries is broken — it returns
# the same ~34 papers regardless of what offset you request. The fix is
# month-scoped date-range chunking: each request uses from-pub-date/until-pub-date
# for one calendar month. CrossRef correctly returns different papers for different
# date windows, and each month has ≤ ~100 papers so can be fully paginated.

# ---------------------------------------------------------------------------
# Prepare output directory
# ---------------------------------------------------------------------------

if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# Phase 1: Fetch ALL Scientific Data papers via month-scoped date-range chunks,
#           score locally. Scientific Data started in 2014.
# ---------------------------------------------------------------------------

dataset_checkpoint_path <- file.path(output_dir, "sdata_search_checkpoint.csv")
dataset_rows    <- list()
seen_dois       <- character(0)
first_ds_write  <- TRUE
completed_chunks <- character(0)   # "YYYY-MM" strings already fully fetched

if (resume && file.exists(dataset_checkpoint_path)) {
  existing_ds <- utils::read.csv(dataset_checkpoint_path, stringsAsFactors = FALSE, check.names = FALSE)
  if (nrow(existing_ds) && "doi" %in% names(existing_ds)) {
    seen_dois      <- unique(existing_ds$doi)
    dataset_rows   <- list(existing_ds)
    first_ds_write <- FALSE
    if ("fetch_chunk" %in% names(existing_ds)) {
      completed_chunks <- unique(existing_ds$fetch_chunk)
    }
    message(sprintf("Resuming: %d unique DOIs from %d month-chunks already fetched.",
                    length(seen_dois), length(completed_chunks)))
  }
}

# Build list of month-chunks: 2014-01 through current month
current_year  <- as.integer(format(Sys.Date(), "%Y"))
current_month <- as.integer(format(Sys.Date(), "%m"))
month_chunks  <- character(0)
for (yr in 2014:current_year) {
  max_mo <- if (yr == current_year) current_month else 12L
  for (mo in seq_len(max_mo)) {
    month_chunks <- c(month_chunks, sprintf("%04d-%02d", yr, mo))
  }
}
pending_chunks <- month_chunks[!month_chunks %in% completed_chunks]

message(sprintf(
  "Scientific Data month-chunks: %d total, %d completed, %d pending.",
  length(month_chunks), length(completed_chunks), length(pending_chunks)
))

for (chunk in pending_chunks) {
  yr_mo_filter <- paste0(
    "issn:", SDATA_ISSN,
    ",from-pub-date:", chunk,
    ",until-pub-date:", chunk
  )

  chunk_offset <- 0L
  chunk_page   <- 1L
  chunk_total  <- NA_integer_
  chunk_new    <- 0L

  repeat {
    if (!is.na(chunk_total) && chunk_offset >= chunk_total) break

    message(sprintf("  Chunk %s page %d (offset %d)", chunk, chunk_page, chunk_offset))

    page_url <- paste0(
      SDATA_CROSSREF_BASE,
      "?filter=", utils::URLencode(yr_mo_filter, reserved = TRUE),
      "&rows=", as.integer(per_page),
      "&offset=", as.integer(chunk_offset),
      "&select=", utils::URLencode(
        "DOI,title,abstract,author,published,link,relation,subject", reserved = TRUE),
      "&mailto=", utils::URLencode(SDATA_CROSSREF_MAILTO, reserved = TRUE)
    )

    Sys.sleep(1)
    result <- tryCatch(dryad_run_curl(page_url), error = function(e) NULL)

    if (is.null(result) || result$http_code != 200L) {
      warning(sprintf("Fetch failed (HTTP %s) for chunk %s offset %d — skipping chunk.",
                      if (!is.null(result)) result$http_code else "NULL",
                      chunk, chunk_offset))
      break
    }

    parsed <- tryCatch(
      jsonlite::fromJSON(result$body, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(parsed)) break

    if (is.na(chunk_total)) {
      chunk_total <- as.integer(parsed$message[["total-results"]] %||% 0L)
    }

    items  <- parsed$message$items
    actual_n <- length(items %||% list())
    if (actual_n == 0L) break

    rows <- sdata_flatten_crossref_results(parsed, query_term = chunk)
    if (!is.null(rows) && nrow(rows) > 0L) {
      new_rows <- rows[!rows$doi %in% seen_dois, , drop = FALSE]
      if (nrow(new_rows) > 0L) {
        score_list <- lapply(seq_len(nrow(new_rows)), function(i) {
          sdata_score_candidate(new_rows$title[[i]], new_rows$abstract[[i]], new_rows$source_subjects[[i]])
        })
        new_rows$candidate_score     <- vapply(score_list, function(s) as.numeric(s$candidate_score), numeric(1))
        new_rows$candidate_keep      <- vapply(score_list, function(s) as.logical(s$candidate_keep),  logical(1))
        new_rows$candidate_rationale <- vapply(score_list, function(s) as.character(s$candidate_rationale), character(1))
        new_rows$fetch_chunk         <- chunk

        seen_dois <- c(seen_dois, new_rows$doi)
        chunk_new <- chunk_new + nrow(new_rows)
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

    chunk_offset <- chunk_offset + actual_n
    chunk_page   <- chunk_page + 1L
    if (chunk_offset >= 10000L) break   # CrossRef hard cap
  }

  if (!is.na(chunk_total)) {
    message(sprintf("  Chunk %s done: total=%d, new DOIs=%d (cumulative: %d)",
                    chunk, chunk_total, chunk_new, length(seen_dois)))
  }
  completed_chunks <- c(completed_chunks, chunk)
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
