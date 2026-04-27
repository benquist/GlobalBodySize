#!/usr/bin/env Rscript
# discover_scientific_data_multipronged.R
# Multi-pronged discovery pipeline for plant trait datasets in Scientific Data.
#
# Runs four independent discovery strategies in sequence, merges by DOI, then
# resolves downloadable files. Each strategy addresses a different gap:
#
#   Phase 1A — CrossRef month-chunked scan (existing baseline)
#     Fetches all ~2,400 Scientific Data papers via CrossRef; robust pagination.
#     Weakness: ~50% abstract coverage; misses non-standard phrasing.
#
#   Phase 1B — OpenAlex semantic search
#     Uses OpenAlex ML-indexed keywords, concepts, and full-text BM25.
#     Catches papers described as "hydraulic traits", "ecophysiology", etc.
#     that substring-matching misses. Cursor pagination, no offset limit.
#
#   Phase 1C — Europe PMC section-aware boolean queries
#     Searches title, abstract, and keywords using Europe PMC field prefixes.
#     Recovers papers where CrossRef abstract is missing/absent.
#
#   Phase 1D — Figshare reverse search (files → papers)
#     Searches Figshare datasets for plant trait terms, then traces each result
#     back to its citing Scientific Data paper via resource_doi / references.
#     Bypasses paper-level scoring; discovers downloadable files directly.
#
# Usage:
#   Rscript providers/scientific_data/scripts/discover_scientific_data_multipronged.R \
#     --output-dir=output/providers/scientific_data \
#     --per-page=100 \
#     --skip-crossref=FALSE \
#     --skip-openalex=FALSE \
#     --skip-epmc=FALSE \
#     --skip-figshare=FALSE \
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
# Source all dependencies
# ---------------------------------------------------------------------------

source(file.path(project_root, "providers", "common", "R", "provider_common.R"),  local = FALSE)
source(file.path(project_root, "R", "search_terms.R"),                            local = FALSE)
source(file.path(project_root, "R", "candidate_filter.R"),                        local = FALSE)
source(file.path(project_root, "R", "dryad_api.R"),                               local = FALSE)
source(file.path(project_root, "providers", "scientific_data", "R", "scientific_data_api.R"), local = FALSE)
source(file.path(project_root, "providers", "scientific_data", "R", "repo_resolver.R"),       local = FALSE)
source(file.path(project_root, "providers", "scientific_data", "R", "openalex_api.R"),        local = FALSE)
source(file.path(project_root, "providers", "scientific_data", "R", "europepmc_api.R"),       local = FALSE)
source(file.path(project_root, "providers", "scientific_data", "R", "figshare_group_api.R"), local = FALSE)

# ---------------------------------------------------------------------------
# File-support helpers
# ---------------------------------------------------------------------------

sdata_is_supported_tabular <- function(file_name) {
  if (is.na(file_name) || !nzchar(file_name)) return(FALSE)
  any(endsWith(tolower(file_name), c(".csv", ".tsv", ".txt", ".tab", ".xlsx", ".xls")))
}

sdata_is_supported_archive <- function(file_name) {
  if (is.na(file_name) || !nzchar(file_name)) return(FALSE)
  any(endsWith(tolower(file_name), c(".zip", ".tar", ".tar.gz", ".tgz", ".gz")))
}

# ---------------------------------------------------------------------------
# Parse CLI args
# ---------------------------------------------------------------------------

args            <- provider_parse_named_args(commandArgs(trailingOnly = TRUE))
base_output_dir <- args$`output-dir`     %||% args$output_dir %||% file.path(project_root, "output")
output_dir      <- file.path(base_output_dir, "providers", "scientific_data")
per_page        <- as.integer(args$`per-page`      %||% "100")
resume          <- identical(args$resume,           "TRUE")
skip_crossref   <- identical(args$`skip-crossref`,  "TRUE")
skip_openalex   <- identical(args$`skip-openalex`,  "TRUE")
skip_epmc       <- identical(args$`skip-epmc`,      "TRUE")
skip_figshare   <- identical(args$`skip-figshare`,  "TRUE")

if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

message("=== Multi-pronged Scientific Data discovery ===")
message(sprintf("Output dir: %s", output_dir))
message(sprintf("Phases: CrossRef=%s OpenAlex=%s EuropePMC=%s Figshare=%s",
                if (!skip_crossref) "ON" else "skip",
                if (!skip_openalex) "ON" else "skip",
                if (!skip_epmc)     "ON" else "skip",
                if (!skip_figshare) "ON" else "skip"))

# ---------------------------------------------------------------------------
# Phase 1A: CrossRef month-chunked scan (adapted from discover_scientific_data_traits.R)
# ---------------------------------------------------------------------------

crossref_datasets <- {
  empty <- provider_dataset_schema(0L)
  empty$doi <- empty$paper_url <- empty$data_links <- empty$query_source <- character(0)
  empty
}

if (!skip_crossref) {
  message("\n--- Phase 1A: CrossRef ---")

  dataset_checkpoint_path <- file.path(output_dir, "sdata_search_checkpoint.csv")
  dataset_rows    <- list()
  seen_dois       <- character(0)
  first_ds_write  <- TRUE
  completed_chunks <- character(0)

  if (resume && file.exists(dataset_checkpoint_path)) {
    existing_ds <- tryCatch(
      utils::read.csv(dataset_checkpoint_path, stringsAsFactors = FALSE, check.names = FALSE),
      error = function(e) NULL
    )
    if (!is.null(existing_ds) && nrow(existing_ds) && "doi" %in% names(existing_ds)) {
      seen_dois        <- unique(existing_ds$doi)
      dataset_rows     <- list(existing_ds)
      first_ds_write   <- FALSE
      if ("fetch_chunk" %in% names(existing_ds)) {
        completed_chunks <- unique(existing_ds$fetch_chunk)
      }
      message(sprintf("CrossRef: resuming — %d DOIs, %d chunks done.",
                      length(seen_dois), length(completed_chunks)))
    }
  }

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
  message(sprintf("CrossRef: %d pending month-chunks.", length(pending_chunks)))

  for (chunk in pending_chunks) {
    yr_mo_filter <- paste0("issn:", SDATA_ISSN, ",from-pub-date:", chunk, ",until-pub-date:", chunk)
    chunk_offset <- 0L; chunk_page <- 1L; chunk_total <- NA_integer_; chunk_new <- 0L

    repeat {
      if (!is.na(chunk_total) && chunk_offset >= chunk_total) break
      message(sprintf("  Chunk %s page %d (offset %d)", chunk, chunk_page, chunk_offset))

      page_url <- paste0(
        SDATA_CROSSREF_BASE,
        "?filter=", utils::URLencode(yr_mo_filter, reserved = TRUE),
        "&rows=",   as.integer(per_page),
        "&offset=", as.integer(chunk_offset),
        "&select=", utils::URLencode(
          "DOI,title,abstract,author,published,link,relation,subject", reserved = TRUE),
        "&mailto=", utils::URLencode(SDATA_CROSSREF_MAILTO, reserved = TRUE)
      )

      Sys.sleep(1)
      result <- tryCatch(dryad_run_curl(page_url), error = function(e) NULL)
      if (is.null(result) || result$http_code != 200L) {
        warning(sprintf("CrossRef: fetch failed chunk %s offset %d", chunk, chunk_offset))
        break
      }
      parsed <- tryCatch(jsonlite::fromJSON(result$body, simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(parsed)) break
      if (is.na(chunk_total)) chunk_total <- as.integer(parsed$message[["total-results"]] %||% 0L)
      items <- parsed$message$items
      if (is.null(items) || length(items) == 0L) break

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
          new_rows$query_source        <- "crossref"
          seen_dois      <- c(seen_dois, new_rows$doi)
          chunk_new      <- chunk_new + nrow(new_rows)
          dataset_rows[[length(dataset_rows) + 1L]] <- new_rows
          utils::write.table(new_rows, dataset_checkpoint_path,
                             sep = ",", row.names = FALSE, na = "",
                             append = !first_ds_write, col.names = first_ds_write, qmethod = "double")
          first_ds_write <- FALSE
        }
      }
      chunk_offset <- chunk_offset + length(items)
      chunk_page   <- chunk_page + 1L
      if (chunk_offset >= 10000L) break
    }
    if (!is.na(chunk_total)) {
      message(sprintf("  Chunk %s done: total=%d, new=%d (cumulative: %d)",
                      chunk, chunk_total, chunk_new, length(seen_dois)))
    }
    completed_chunks <- c(completed_chunks, chunk)
  }

  if (length(dataset_rows)) {
    crossref_datasets <- do.call(rbind, dataset_rows)
    message(sprintf("CrossRef: %d papers, %d candidate_keep=TRUE.",
                    nrow(crossref_datasets), sum(crossref_datasets$candidate_keep, na.rm = TRUE)))
  }
}

# ---------------------------------------------------------------------------
# Phase 1B: OpenAlex semantic search
# ---------------------------------------------------------------------------

openalex_datasets <- {
  empty <- provider_dataset_schema(0L)
  empty$doi <- empty$paper_url <- empty$data_links <- empty$query_source <- character(0)
  empty
}

if (!skip_openalex) {
  message("\n--- Phase 1B: OpenAlex ---")
  openalex_datasets <- tryCatch(
    openalex_discover_plant_traits(output_dir, per_page = min(200L, per_page * 2L)),
    error = function(e) {
      warning(sprintf("OpenAlex phase failed: %s", conditionMessage(e)))
      openalex_datasets
    }
  )
}

# ---------------------------------------------------------------------------
# Phase 1C: Europe PMC section-aware search
# ---------------------------------------------------------------------------

epmc_datasets <- {
  empty <- provider_dataset_schema(0L)
  empty$doi <- empty$paper_url <- empty$data_links <- empty$query_source <- character(0)
  empty
}

if (!skip_epmc) {
  message("\n--- Phase 1C: Europe PMC ---")
  epmc_datasets <- tryCatch(
    europepmc_discover_plant_traits(output_dir),
    error = function(e) {
      warning(sprintf("Europe PMC phase failed: %s", conditionMessage(e)))
      epmc_datasets
    }
  )
}

# ---------------------------------------------------------------------------
# Phase 1D: Figshare reverse search (files → papers)
# ---------------------------------------------------------------------------

figshare_result <- list(
  datasets = {
    e <- provider_dataset_schema(0L)
    e$doi <- e$paper_url <- e$data_links <- e$query_source <- character(0)
    e
  },
  files = {
    e <- provider_file_schema(0L)
    e$query_source <- character(0)
    e
  }
)

if (!skip_figshare) {
  message("\n--- Phase 1D: Figshare reverse ---")
  figshare_result <- tryCatch(
    figshare_reverse_discover(output_dir),
    error = function(e) {
      warning(sprintf("Figshare reverse phase failed: %s", conditionMessage(e)))
      figshare_result
    }
  )
}

# ---------------------------------------------------------------------------
# Merge all dataset sources — dedup by DOI, keep row with highest score
# ---------------------------------------------------------------------------

message("\n--- Merging sources ---")

# Ensure query_source column exists on all frames
for (df_name in c("crossref_datasets", "openalex_datasets", "epmc_datasets")) {
  df <- get(df_name)
  if (nrow(df) > 0L && !"query_source" %in% names(df)) df$query_source <- df_name
  assign(df_name, df)
}

# Align columns before rbind: add missing columns with NA
align_columns <- function(target_df, reference_df) {
  for (col in setdiff(names(reference_df), names(target_df))) {
    target_df[[col]] <- NA
  }
  target_df[, union(names(target_df), names(reference_df)), drop = FALSE]
}

ds_list <- Filter(function(d) nrow(d) > 0L,
                  list(crossref_datasets, openalex_datasets, epmc_datasets,
                       figshare_result$datasets))

all_datasets <- if (length(ds_list) == 0L) {
  provider_dataset_schema(0L)
} else if (length(ds_list) == 1L) {
  ds_list[[1L]]
} else {
  # Align all to the union of columns
  all_cols <- unique(unlist(lapply(ds_list, names)))
  ds_aligned <- lapply(ds_list, function(df) {
    for (col in setdiff(all_cols, names(df))) df[[col]] <- NA
    df[, all_cols, drop = FALSE]
  })
  do.call(rbind, ds_aligned)
}

# Dedup by provider_dataset_id (DOI), keep highest candidate_score
if (nrow(all_datasets) > 0L && "provider_dataset_id" %in% names(all_datasets)) {
  all_datasets$candidate_score <- suppressWarnings(as.numeric(all_datasets$candidate_score))
  all_datasets <- all_datasets[order(-all_datasets$candidate_score, all_datasets$title %||% ""), , drop = FALSE]
  all_datasets <- all_datasets[!duplicated(all_datasets$provider_dataset_id), , drop = FALSE]
}

candidate_datasets <- all_datasets[
  !is.na(all_datasets$candidate_keep) & (all_datasets$candidate_keep == TRUE | all_datasets$candidate_keep == "TRUE"),
  , drop = FALSE
]

message(sprintf(
  "Merged: %d unique papers across all sources, %d candidate_keep=TRUE.",
  nrow(all_datasets), nrow(candidate_datasets)
))

# Source breakdown
if (nrow(all_datasets) > 0L && "query_source" %in% names(all_datasets)) {
  tbl <- table(all_datasets$query_source[all_datasets$candidate_keep == TRUE | all_datasets$candidate_keep == "TRUE"])
  message("Candidates by source:")
  for (src in names(tbl)) message(sprintf("  %s: %d", src, tbl[[src]]))
}

# ---------------------------------------------------------------------------
# Phase 2: Resolve data repository links for dataset candidates
# ---------------------------------------------------------------------------

message("\n--- Phase 2: Resolving files ---")

files_checkpoint_path <- file.path(output_dir, "sdata_files_checkpoint.csv")
file_rows      <- list()
resolved_ids   <- character(0)
first_file_write <- TRUE

if (resume && file.exists(files_checkpoint_path)) {
  existing_files <- tryCatch(
    utils::read.csv(files_checkpoint_path, stringsAsFactors = FALSE, check.names = FALSE),
    error = function(e) NULL
  )
  if (!is.null(existing_files) && nrow(existing_files) && "provider_dataset_id" %in% names(existing_files)) {
    resolved_ids     <- unique(existing_files$provider_dataset_id)
    file_rows        <- list(existing_files)
    first_file_write <- FALSE
    message(sprintf("Phase 2: resuming — %d already-resolved dataset IDs.", length(resolved_ids)))
  }
}

if (nrow(candidate_datasets) > 0L) {
  for (row_index in seq_len(nrow(candidate_datasets))) {
    dataset_doi <- candidate_datasets$provider_dataset_id[[row_index]]
    data_links  <- candidate_datasets$data_links[[row_index]]

    if (is.na(dataset_doi) || !nzchar(dataset_doi)) next
    if (dataset_doi %in% resolved_ids) next

    if (is.na(data_links) || !nzchar(trimws(data_links %||% ""))) {
      # Try to extract from abstract text (CrossRef sometimes embeds figshare links there)
      abstract_text <- candidate_datasets$abstract[[row_index]] %||% ""
      extracted <- sdata_extract_repo_links_from_text(abstract_text)
      data_links <- sdata_repo_links_to_string(extracted)
    }

    if (is.na(data_links) || !nzchar(trimws(data_links %||% ""))) {
      resolved_ids <- c(resolved_ids, dataset_doi)
      next
    }

    message(sprintf("Resolving data links for %s", dataset_doi))

    resolved_files <- tryCatch(
      sdata_resolve_data_links(data_links),
      error = function(e) {
        warning(sprintf("Phase 2: error resolving '%s': %s", dataset_doi, conditionMessage(e)))
        sdata_empty_file_table()
      }
    )

    if (is.null(resolved_files) || nrow(resolved_files) == 0L) {
      resolved_ids <- c(resolved_ids, dataset_doi)
      next
    }

    file_table <- provider_file_schema(nrow(resolved_files))
    file_table$source_provider      <- "scientific_data"
    file_table$provider_dataset_id  <- dataset_doi
    file_table$provider_file_id     <- paste(
      resolved_files$repo_type, resolved_files$repo_id, resolved_files$file_name, sep = "::"
    )
    file_table$file_path            <- resolved_files$file_name
    file_table$file_size            <- resolved_files$file_size
    file_table$mime_type            <- resolved_files$mime_type
    file_table$file_status          <- NA_character_
    file_table$download_href        <- resolved_files$download_url
    file_table$candidate_score      <- candidate_datasets$candidate_score[[row_index]]
    file_table$candidate_keep       <- candidate_datasets$candidate_keep[[row_index]]
    file_table$query_term           <- candidate_datasets$query_term[[row_index]]
    file_table$source_title         <- candidate_datasets$title[[row_index]]
    file_table$source_authors       <- candidate_datasets$authors[[row_index]]
    file_table$source_subjects      <- candidate_datasets$source_subjects[[row_index]]
    file_table$source_abstract      <- candidate_datasets$abstract[[row_index]]
    file_table$file_supported_tabular   <- vapply(resolved_files$file_name, sdata_is_supported_tabular, logical(1))
    file_table$file_supported_container <- vapply(resolved_files$file_name, sdata_is_supported_archive, logical(1))
    file_table$query_source         <- candidate_datasets$query_source[[row_index]] %||% "crossref"

    file_rows[[length(file_rows) + 1L]] <- file_table
    utils::write.table(file_table, files_checkpoint_path,
                       sep = ",", row.names = FALSE, na = "",
                       append = !first_file_write, col.names = first_file_write, qmethod = "double")
    first_file_write <- FALSE
    resolved_ids <- c(resolved_ids, dataset_doi)
  }
}

# Merge Phase 2 resolved files with Figshare reverse files
all_files_list <- Filter(function(d) nrow(d) > 0L,
                         c(file_rows, list(figshare_result$files)))

all_files <- if (length(all_files_list) == 0L) {
  provider_file_schema(0L)
} else {
  all_cols <- unique(unlist(lapply(all_files_list, names)))
  aligned  <- lapply(all_files_list, function(df) {
    for (col in setdiff(all_cols, names(df))) df[[col]] <- NA
    df[, all_cols, drop = FALSE]
  })
  do.call(rbind, aligned)
}

# ---------------------------------------------------------------------------
# Write final outputs
# ---------------------------------------------------------------------------

message("\n--- Writing outputs ---")

dataset_out_cols <- c(
  "source_provider", "provider_dataset_id", "query_term", "title", "authors",
  "abstract", "source_subjects", "field_of_science", "storage_size",
  "candidate_score", "candidate_keep", "candidate_rationale"
)
extra_cols   <- setdiff(names(all_datasets), dataset_out_cols)
dataset_output <- if (nrow(all_datasets)) {
  all_datasets[, c(dataset_out_cols, intersect(extra_cols, names(all_datasets))), drop = FALSE]
} else {
  provider_dataset_schema(0L)
}

utils::write.csv(dataset_output, file.path(output_dir, "candidate_datasets.csv"),
                 row.names = FALSE, na = "")
utils::write.csv(all_files,      file.path(output_dir, "candidate_files.csv"),
                 row.names = FALSE, na = "")

n_tabular <- if (nrow(all_files)) sum(all_files$file_supported_tabular == TRUE, na.rm = TRUE) else 0L
message(sprintf(
  "\nDone: %d papers searched, %d kept, %d files, %d tabular.",
  nrow(all_datasets), nrow(candidate_datasets), nrow(all_files), n_tabular
))
