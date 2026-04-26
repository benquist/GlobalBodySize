#!/usr/bin/env Rscript
# compile_scientific_data_traits.R
# Download and compile plant trait observations from Scientific Data candidate files.
# All output is written strictly under output/providers/scientific_data/ — never the
# top-level Dryad output directory.
#
# Usage (from workspace root or DryadPlantTraits/):
#   Rscript providers/scientific_data/scripts/compile_scientific_data_traits.R \
#     --candidate-files=output/providers/scientific_data/candidate_files.csv \
#     --output-dir=output/providers/scientific_data \
#     --max-datasets=50 \
#     --max-files=200
#
# Re-downloads are skipped if the local file already exists.

# ---------------------------------------------------------------------------
# Locate project root
# ---------------------------------------------------------------------------

sdata_compile_find_root <- function() {
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

project_root <- sdata_compile_find_root()

# ---------------------------------------------------------------------------
# Source shared R modules
# ---------------------------------------------------------------------------

source(file.path(project_root, "providers", "common", "R", "provider_common.R"), local = FALSE)
source(file.path(project_root, "R", "trait_dictionary.R"),                        local = FALSE)
source(file.path(project_root, "R", "io_helpers.R"),                              local = FALSE)
source(file.path(project_root, "R", "dryad_api.R"),                               local = FALSE)
source(file.path(project_root, "R", "standardize_records.R"),                     local = FALSE)
source(file.path(project_root, "R", "qa_checks.R"),                               local = FALSE)

# ---------------------------------------------------------------------------
# Parse CLI args
# ---------------------------------------------------------------------------

args <- provider_parse_named_args(commandArgs(trailingOnly = TRUE))

output_dir <- args$`output-dir` %||% args$output_dir %||%
  file.path(project_root, "output", "providers", "scientific_data")

candidate_files_path <- args$`candidate-files` %||% args$candidate_files %||%
  file.path(output_dir, "candidate_files.csv")

max_datasets <- suppressWarnings(as.integer(args$`max-datasets` %||% "Inf"))
if (is.na(max_datasets)) max_datasets <- Inf

max_files <- suppressWarnings(as.integer(args$`max-files` %||% "Inf"))
if (is.na(max_files)) max_files <- Inf

# ---------------------------------------------------------------------------
# Helper: timestamp
# ---------------------------------------------------------------------------

sdata_now_utc <- function() {
  format(Sys.time(), tz = "UTC", format = "%Y-%m-%dT%H:%M:%SZ")
}

# ---------------------------------------------------------------------------
# Helper: download a single file using curl
# ---------------------------------------------------------------------------

sdata_download_file <- function(url, destfile) {
  if (is.na(url) || !nzchar(trimws(url))) {
    return(list(success = FALSE, message = "download_href is missing"))
  }
  dir.create(dirname(destfile), recursive = TRUE, showWarnings = FALSE)
  result <- dryad_run_curl(url, destfile = destfile)
  if (!is.null(result$curl_status) && result$curl_status != 0L) {
    return(list(success = FALSE,
                message = sprintf("curl exit code %d for URL: %s", result$curl_status, url)))
  }
  if (!is.null(result$http_code) && result$http_code >= 400L) {
    return(list(success = FALSE,
                message = sprintf("HTTP %d for URL: %s", result$http_code, url)))
  }
  if (!file.exists(destfile) || file.info(destfile)$size == 0L) {
    return(list(success = FALSE,
                message = sprintf("Downloaded file empty or missing: %s", destfile)))
  }
  list(success = TRUE, message = "OK")
}

# ---------------------------------------------------------------------------
# Helper: build a safe local filename from provider_file_id
# ---------------------------------------------------------------------------

sdata_safe_filename <- function(provider_file_id, file_path_col, row_idx = 0L) {
  # Use the file_path column (basename of original file) when available
  fn <- if (!is.na(file_path_col) && nzchar(file_path_col)) basename(file_path_col) else NA_character_
  if (!is.na(fn) && nzchar(fn)) return(fn)
  # Fall back to last segment of provider_file_id (guard NA)
  if (is.na(provider_file_id) || !nzchar(trimws(as.character(provider_file_id)))) {
    return(sprintf("file_%04d", as.integer(row_idx)))
  }
  parts <- strsplit(as.character(provider_file_id), "::", fixed = TRUE)[[1]]
  fn <- parts[[length(parts)]]
  gsub("[^A-Za-z0-9._-]", "_", fn)
}

# ---------------------------------------------------------------------------
# Helper: sanitize paper DOI to a filesystem-safe directory name
# ---------------------------------------------------------------------------

sdata_doi_to_slug <- function(doi) {
  # Replace all non-alphanumeric (except hyphen) including dots to prevent path traversal
  gsub("[^A-Za-z0-9-]", "_", as.character(doi))
}

# ---------------------------------------------------------------------------
# Select candidate files (mirror Dryad helper)
# ---------------------------------------------------------------------------

# Coerce boolean columns that may be read as character "TRUE"/"FALSE" from CSV
sdata_coerce_logical <- function(x) {
  if (is.logical(x)) return(x)
  tolower(trimws(as.character(x))) %in% c("true", "1", "yes")
}

sdata_select_candidate_files <- function(file_table, max_datasets, max_files) {
  if (!nrow(file_table)) return(file_table)
  keep_tabular   <- sdata_coerce_logical(file_table$file_supported_tabular)
  keep_container <- sdata_coerce_logical(file_table$file_supported_container)
  has_url        <- !is.na(file_table$download_href) & nzchar(trimws(file_table$download_href))
  keep_candidate <- sdata_coerce_logical(file_table$candidate_keep)
  filtered <- file_table[keep_candidate & (keep_tabular | keep_container) & has_url, , drop = FALSE]
  if (!nrow(filtered)) return(filtered)
  score_col <- if ("candidate_score" %in% names(filtered)) -suppressWarnings(as.numeric(filtered$candidate_score)) else rep(0, nrow(filtered))
  score_col[is.na(score_col)] <- 0
  doi_col   <- if ("provider_dataset_id" %in% names(filtered)) filtered$provider_dataset_id else rep("", nrow(filtered))
  filtered  <- filtered[order(score_col, doi_col), , drop = FALSE]
  if (is.finite(max_datasets)) {
    keep_dois <- unique(doi_col[order(score_col)])[seq_len(min(max_datasets, length(unique(doi_col))))]
    filtered  <- filtered[filtered$provider_dataset_id %in% keep_dois, , drop = FALSE]
  }
  if (is.finite(max_files)) {
    filtered <- filtered[seq_len(min(max_files, nrow(filtered))), , drop = FALSE]
  }
  filtered
}

# ---------------------------------------------------------------------------
# Empty processing log row
# ---------------------------------------------------------------------------

empty_sdata_log_row <- function() {
  list(
    provider_dataset_id = NA_character_,
    provider_file_id    = NA_character_,
    file_path           = NA_character_,
    action              = NA_character_,
    status              = NA_character_,
    message             = NA_character_,
    rows_in             = 0L,
    rows_out            = 0L,
    timestamp_utc       = sdata_now_utc()
  )
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

dryad_make_dir(output_dir)
download_dir <- file.path(output_dir, "downloads")
dryad_make_dir(download_dir)

if (!file.exists(candidate_files_path)) {
  stop(sprintf(
    "Candidate files not found at: %s\nRun discover_scientific_data_traits.R first.",
    candidate_files_path
  ), call. = FALSE)
}

candidate_files <- utils::read.csv(candidate_files_path, stringsAsFactors = FALSE, check.names = FALSE)
selected_files  <- sdata_select_candidate_files(candidate_files, max_datasets, max_files)

message(sprintf(
  "Scientific Data compile: %d candidate files selected from %d total.",
  nrow(selected_files), nrow(candidate_files)
))

if (!nrow(selected_files)) {
  message("No files selected — nothing to compile.")
  quit(status = 0L, save = "no")
}

processing_log_list <- list()
compiled_rows       <- list()
first_compiled_write <- TRUE

compiled_path    <- file.path(output_dir, "compiled_trait_observations.csv")
process_log_path <- file.path(output_dir, "processing_log.csv")
spot_check_path  <- file.path(output_dir, "spot_check_log.csv")

# ---------------------------------------------------------------------------
# Main loop: download → parse → standardize → QA → append
# ---------------------------------------------------------------------------

for (row_index in seq_len(nrow(selected_files))) {
  row <- selected_files[row_index, , drop = FALSE]

  paper_doi      <- row$provider_dataset_id[[1]]
  file_id        <- row$provider_file_id[[1]]
  download_url   <- row$download_href[[1]]
  file_name      <- sdata_safe_filename(file_id, row$file_path[[1]], row_idx = row_index)
  doi_slug       <- sdata_doi_to_slug(paper_doi)

  dest_dir  <- file.path(download_dir, doi_slug)
  dest_file <- file.path(dest_dir, file_name)

  download_timestamp <- sdata_now_utc()

  message(sprintf("[%d/%d] %s  →  %s", row_index, nrow(selected_files), paper_doi, file_name))

  # ---------- Download ----------
  if (!file.exists(dest_file)) {
    dl <- sdata_download_file(download_url, dest_file)
    if (!isTRUE(dl$success)) {
      log_row          <- empty_sdata_log_row()
      log_row$provider_dataset_id <- paper_doi
      log_row$provider_file_id    <- file_id
      log_row$file_path           <- file_name
      log_row$action              <- "download"
      log_row$status              <- "failed"
      log_row$message             <- dl$message
      log_row$timestamp_utc       <- download_timestamp
      processing_log_list[[length(processing_log_list) + 1L]] <- log_row
      utils::write.csv(
        do.call(rbind, lapply(processing_log_list, as.data.frame, stringsAsFactors = FALSE)),
        process_log_path, row.names = FALSE, na = ""
      )
      next
    }
  } else {
    message("  (cached)")
  }

  # ---------- Read ----------
  file_result <- tryCatch({
    read_result <- dryad_read_supported_inputs(dest_file)

    if (!length(read_result$tables)) {
      log_row          <- empty_sdata_log_row()
      log_row$provider_dataset_id <- paper_doi
      log_row$provider_file_id    <- file_id
      log_row$file_path           <- dest_file
      log_row$action              <- "read"
      log_row$status              <- "no_tables"
      log_row$message             <- "No readable tables found in file."
      log_row$timestamp_utc       <- download_timestamp
      processing_log_list[[length(processing_log_list) + 1L]] <- log_row
    }

    # Log each read sub-result (guard against NULL log)
    for (log_index in seq_len(if (!is.null(read_result$log) && nrow(read_result$log) > 0L) nrow(read_result$log) else 0L)) {
      lr                           <- read_result$log[log_index, , drop = FALSE]
      log_row                      <- empty_sdata_log_row()
      log_row$provider_dataset_id  <- paper_doi
      log_row$provider_file_id     <- file_id
      log_row$file_path            <- lr$extracted_path[[1]] %||% dest_file
      log_row$action               <- "read"
      log_row$status               <- lr$status[[1]]
      log_row$message              <- lr$message[[1]]
      log_row$timestamp_utc        <- download_timestamp
      processing_log_list[[length(processing_log_list) + 1L]] <- log_row
    }

    # ---------- Standardize + QA each table ----------
    for (table_entry in read_result$tables) {
      provenance <- list(
        dryad_dataset_doi      = paper_doi,    # paper DOI (Scientific Data)
        dryad_version_id       = NA_integer_,  # not applicable
        dryad_file_id          = NA_integer_,  # not a numeric Dryad file ID
        source_title           = row$source_title[[1]],
        source_authors         = row$source_authors[[1]],
        source_subjects        = row$source_subjects[[1]],
        source_abstract        = row$source_abstract[[1]],
        download_timestamp_utc = download_timestamp,
        source_file_path       = table_entry$path
      )

      standardized <- dryad_standardize_records(table_entry$data, provenance = provenance)

      if (!nrow(standardized)) {
        log_row                     <- empty_sdata_log_row()
        log_row$provider_dataset_id <- paper_doi
        log_row$provider_file_id    <- file_id
        log_row$file_path           <- table_entry$path
        log_row$action              <- "standardize"
        log_row$status              <- "skipped"
        log_row$message             <- "No trait observation fields detected."
        log_row$rows_in             <- nrow(table_entry$data)
        log_row$rows_out            <- 0L
        log_row$timestamp_utc       <- sdata_now_utc()
        processing_log_list[[length(processing_log_list) + 1L]] <- log_row
        next
      }

      # QA
      standardized <- tryCatch(
        dryad_qa_check(standardized),
        error = function(e) {
          message("  QA error: ", conditionMessage(e))
          standardized
        }
      )

      n_flagged  <- sum(nzchar(standardized$qa_flags), na.rm = TRUE)
      flag_types <- sort(table(unlist(strsplit(
        standardized$qa_flags[nzchar(standardized$qa_flags)], "\\|"
      ))))
      qa_summary <- if (n_flagged > 0L) {
        paste(names(flag_types), flag_types, sep = "=", collapse = "; ")
      } else {
        "PASS"
      }

      log_row                     <- empty_sdata_log_row()
      log_row$provider_dataset_id <- paper_doi
      log_row$provider_file_id    <- file_id
      log_row$file_path           <- table_entry$path
      log_row$action              <- "qa"
      log_row$status              <- if (n_flagged == 0L) "PASS" else "FLAGS"
      log_row$message             <- qa_summary
      log_row$rows_in             <- nrow(standardized)
      log_row$rows_out            <- nrow(standardized) - n_flagged
      log_row$timestamp_utc       <- sdata_now_utc()
      processing_log_list[[length(processing_log_list) + 1L]] <- log_row

      # Spot check: sample up to 5 rows
      spot <- tryCatch(dryad_spot_check(standardized, n = 5L), error = function(e) NULL)
      if (!is.null(spot) && nrow(spot)) {
        write_spot_header <- !file.exists(spot_check_path)
        utils::write.table(spot, spot_check_path,
          sep = ",", row.names = FALSE, na = "",
          append = !write_spot_header, col.names = write_spot_header,
          qmethod = "double"
        )
      }

      log_row                     <- empty_sdata_log_row()
      log_row$provider_dataset_id <- paper_doi
      log_row$provider_file_id    <- file_id
      log_row$file_path           <- table_entry$path
      log_row$action              <- "standardize"
      log_row$status              <- "compiled"
      log_row$message             <- "Compiled BIEN-style observation rows."
      log_row$rows_in             <- nrow(table_entry$data)
      log_row$rows_out            <- nrow(standardized)
      log_row$timestamp_utc       <- sdata_now_utc()
      processing_log_list[[length(processing_log_list) + 1L]] <- log_row

      compiled_rows[[length(compiled_rows) + 1L]] <- standardized
      utils::write.table(standardized, compiled_path,
        sep = ",", row.names = FALSE, na = "",
        append = !first_compiled_write, col.names = first_compiled_write,
        qmethod = "double"
      )
      first_compiled_write <- FALSE
    }

    utils::write.csv(
      do.call(rbind, lapply(processing_log_list, as.data.frame, stringsAsFactors = FALSE)),
      process_log_path, row.names = FALSE, na = ""
    )
    NULL
  }, error = function(e) e)

  if (inherits(file_result, "error")) {
    log_row                     <- empty_sdata_log_row()
    log_row$provider_dataset_id <- paper_doi
    log_row$provider_file_id    <- file_id
    log_row$file_path           <- dest_file
    log_row$action              <- "process"
    log_row$status              <- "error"
    log_row$message             <- conditionMessage(file_result)
    log_row$timestamp_utc       <- sdata_now_utc()
    processing_log_list[[length(processing_log_list) + 1L]] <- log_row
    utils::write.csv(
      do.call(rbind, lapply(processing_log_list, as.data.frame, stringsAsFactors = FALSE)),
      process_log_path, row.names = FALSE, na = ""
    )
  }
}

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------

utils::write.csv(
  do.call(rbind, lapply(processing_log_list, as.data.frame, stringsAsFactors = FALSE)),
  process_log_path, row.names = FALSE, na = ""
)

total_obs  <- sum(vapply(compiled_rows, nrow, integer(1L)))
message(sprintf(
  "Scientific Data compile complete: %d observation rows from %d selected files.",
  total_obs, nrow(selected_files)
))
if (total_obs > 0L) {
  message(sprintf("  → %s", compiled_path))
}
