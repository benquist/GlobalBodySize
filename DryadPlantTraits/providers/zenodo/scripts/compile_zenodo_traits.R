#!/usr/bin/env Rscript
# compile_zenodo_traits.R
# Download and compile plant trait observations from Zenodo candidate files.
# Mirrors compile_downloaded_traits.R but uses direct per-file download URLs
# from the Zenodo Files API instead of Dryad version ZIPs.
#
# Usage:
#   Rscript providers/zenodo/scripts/compile_zenodo_traits.R \
#     --candidate-files=output/providers/zenodo/candidate_files.csv \
#     --max-datasets=50 \
#     --max-files=200 \
#     --output-dir=output/providers/zenodo \
#     --resume=TRUE

# ---------------------------------------------------------------------------
# Locate project root and source shared helpers
# ---------------------------------------------------------------------------

zenodo_compile_find_root <- function() {
  cwd <- getwd()
  if (basename(cwd) == "DryadPlantTraits") return(cwd)
  probe <- file.path(cwd, "DryadPlantTraits")
  if (dir.exists(probe)) return(probe)
  if (basename(cwd) == "scripts" &&
      basename(dirname(cwd)) == "zenodo" &&
      grepl("providers$", dirname(dirname(cwd)))) {
    return(dirname(dirname(dirname(cwd))))
  }
  stop("Cannot locate DryadPlantTraits project root from: ", cwd, call. = FALSE)
}

project_root <- zenodo_compile_find_root()

source(file.path(project_root, "providers", "common", "R", "provider_common.R"), local = FALSE)
source(file.path(project_root, "R", "search_terms.R"),         local = FALSE)
source(file.path(project_root, "R", "trait_dictionary.R"),     local = FALSE)
source(file.path(project_root, "R", "io_helpers.R"),           local = FALSE)
source(file.path(project_root, "R", "dryad_api.R"),            local = FALSE)
source(file.path(project_root, "R", "candidate_filter.R"),     local = FALSE)
source(file.path(project_root, "R", "standardize_records.R"),  local = FALSE)
source(file.path(project_root, "R", "qa_checks.R"),            local = FALSE)
source(file.path(project_root, "providers", "zenodo", "R", "zenodo_api.R"), local = FALSE)
source(file.path(project_root, "providers", "zenodo", "R", "zenodo_parser_registry.R"), local = FALSE)

# ---------------------------------------------------------------------------
# CLI args
# ---------------------------------------------------------------------------

args               <- provider_parse_named_args(commandArgs(trailingOnly = TRUE))
output_dir         <- args$`output-dir`       %||% args$output_dir %||%
                      file.path(project_root, "output", "providers", "zenodo")
candidate_path     <- args$`candidate-files`  %||%
                      file.path(output_dir, "candidate_files.csv")
max_datasets       <- as.integer(args$`max-datasets` %||% "50")
max_files          <- as.integer(args$`max-files`    %||% "200")
resume             <- identical(args$resume, "TRUE")

dryad_make_dir(output_dir)
download_dir <- file.path(output_dir, "downloads")
dryad_make_dir(download_dir)

# ---------------------------------------------------------------------------
# Load candidate files
# ---------------------------------------------------------------------------

if (!file.exists(candidate_path)) {
  stop(sprintf(
    "Candidate file inventory not found: %s\nRun discover_zenodo_traits.R first.",
    candidate_path
  ), call. = FALSE)
}

candidate_files <- utils::read.csv(candidate_path, stringsAsFactors = FALSE, check.names = FALSE)
message(sprintf("Loaded %d candidate file rows.", nrow(candidate_files)))

# Filter to supported files that scored as plant trait candidates
supported <- candidate_files[
  !is.na(candidate_files$candidate_keep) & candidate_files$candidate_keep &
  (candidate_files$file_supported_tabular | candidate_files$file_supported_container),
  , drop = FALSE
]
supported <- supported[order(-supported$candidate_score, supported$provider_dataset_id, supported$file_path), , drop = FALSE]

# Cap by datasets then files
if (is.finite(max_datasets)) {
  keep_ds <- unique(supported$provider_dataset_id)[seq_len(min(max_datasets, length(unique(supported$provider_dataset_id))))]
  supported <- supported[supported$provider_dataset_id %in% keep_ds, , drop = FALSE]
}
if (is.finite(max_files)) {
  supported <- supported[seq_len(min(max_files, nrow(supported))), , drop = FALSE]
}

message(sprintf("Selected %d files from %d datasets for ingest.",
                nrow(supported), length(unique(supported$provider_dataset_id))))

# ---------------------------------------------------------------------------
# Resume: find already-processed file IDs
# ---------------------------------------------------------------------------

compiled_path <- file.path(output_dir, "compiled_trait_observations.csv")
log_path      <- file.path(output_dir, "processing_log.csv")

processed_ids  <- character(0)
first_compiled <- TRUE
first_log      <- TRUE

if (resume && file.exists(log_path)) {
  existing_log <- utils::read.csv(log_path, stringsAsFactors = FALSE, check.names = FALSE)
  if ("provider_file_id" %in% names(existing_log)) {
    processed_ids <- unique(existing_log$provider_file_id[
      !is.na(existing_log$status) & existing_log$status %in% c("compiled", "skipped", "failed", "error")
    ])
    message(sprintf("Resuming: %d files already processed.", length(processed_ids)))
  }
  if (nrow(existing_log)) first_log <- FALSE
}
if (resume && file.exists(compiled_path)) {
  first_compiled <- FALSE
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

zenodo_now_utc <- function() {
  format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

append_log_row <- function(row_list, first_flag) {
  df <- as.data.frame(row_list, stringsAsFactors = FALSE)
  utils::write.table(
    df, log_path,
    sep = ",", row.names = FALSE, na = "",
    append = !first_flag, col.names = first_flag,
    qmethod = "double"
  )
  invisible(FALSE)
}

zenodo_log_path <- function(table_entry) {
  table_entry$display_path %||% table_entry$path
}

zenodo_truncate_error <- function(message_text, width = 120L) {
  if (is.null(message_text) || !length(message_text) || is.na(message_text)) {
    return(NA_character_)
  }

  text <- trimws(as.character(message_text)[[1]])
  if (!nzchar(text)) return(NA_character_)
  if (nchar(text, type = "chars") <= width) return(text)
  paste0(substr(text, 1L, max(1L, width - 3L)), "...")
}

zenodo_no_trait_message <- function(registry_error = NA_character_, fallback_error = NA_character_) {
  registry_error <- zenodo_truncate_error(registry_error)
  fallback_error <- zenodo_truncate_error(fallback_error)

  if (all(is.na(c(registry_error, fallback_error)))) {
    return("no_trait_observation_fields")
  }

  parts <- c("no_trait_observation_fields")
  if (!is.na(registry_error)) {
    parts <- c(parts, paste0("registry_error=", registry_error))
  }
  if (!is.na(fallback_error)) {
    parts <- c(parts, paste0("fallback_error=", fallback_error))
  }

  paste(parts, collapse = "; ")
}

# Download a single file by URL into download_dir.
# Returns the local file path, or NULL on failure.
zenodo_download_file <- function(url, dest_path) {
  if (is.na(url) || !nzchar(trimws(url))) return(NULL)

  auth_header <- zenodo_auth_header()
  headers     <- if (!is.null(auth_header)) auth_header else NULL

  result <- tryCatch(
    dryad_run_curl(url, headers = headers, destfile = dest_path),
    error = function(e) {
      warning(sprintf("zenodo_download_file: curl error: %s", conditionMessage(e)))
      NULL
    }
  )
  if (is.null(result)) return(NULL)

  # Handle 429 with backoff
  if (identical(result$http_code, 429L)) {
    message("Zenodo rate limit on download, waiting 60s...")
    Sys.sleep(60)
    result <- tryCatch(
      dryad_run_curl(url, headers = headers, destfile = dest_path),
      error = function(e) NULL
    )
    if (is.null(result)) return(NULL)
  }

  if (!result$http_code %in% c(200L, 206L)) {
    warning(sprintf("zenodo_download_file: HTTP %d for %s", result$http_code, url))
    return(NULL)
  }
  if (!file.exists(dest_path) || file.size(dest_path) == 0L) return(NULL)
  dest_path
}

# ---------------------------------------------------------------------------
# Main ingest loop
# ---------------------------------------------------------------------------

n_compiled_rows <- 0L
n_files_done    <- 0L

for (row_index in seq_len(nrow(supported))) {
  row <- supported[row_index, , drop = FALSE]

  file_id   <- row$provider_file_id[[1]]
  ds_id     <- row$provider_dataset_id[[1]]
  file_name <- basename(row$file_path[[1]])
  dl_url    <- row$download_href[[1]]
  ts        <- zenodo_now_utc()

  if (!is.na(file_id) && file_id %in% processed_ids) {
    message(sprintf("[%d/%d] Skip (already done): %s", row_index, nrow(supported), file_name))
    next
  }

  message(sprintf("[%d/%d] %s — %s", row_index, nrow(supported), ds_id, file_name))

  # Build a safe local filename: replace special chars in file_id
  safe_id   <- gsub("[^A-Za-z0-9._-]", "_", file_id)
  dest_path <- file.path(download_dir, paste0(safe_id, "_", file_name))

  # Download
  if (!file.exists(dest_path)) {
    Sys.sleep(ZENODO_POLITE_SLEEP_SEC)
    local_path <- zenodo_download_file(dl_url, dest_path)
    if (is.null(local_path)) {
      first_log <- append_log_row(list(
        provider_dataset_id = ds_id, provider_file_id = file_id,
        file_path = file_name, action = "download", status = "failed",
        message = "Download returned NULL or non-200", rows_in = 0L, rows_out = 0L,
        timestamp_utc = ts
      ), first_log)
      processed_ids <- c(processed_ids, file_id)
      next
    }
  } else {
    local_path <- dest_path
    message("  (cached)")
  }

  # Extract if archive
  work_dir    <- file.path(download_dir, paste0("extract_", safe_id))
  extract_res <- tryCatch(
    dryad_extract_supported_files(local_path, work_dir = work_dir),
    error = function(e) list(paths = character(0), message = conditionMessage(e))
  )

  tabular_paths <- extract_res$paths
  filter_res    <- dryad_filter_trait_archive_paths(tabular_paths)
  tabular_paths <- filter_res$kept
  if (length(filter_res$filtered) > 0L) {
    message("  Filtered ", length(filter_res$filtered), " archive noise file(s).")
  }
  if (!length(tabular_paths)) {
    skip_msg <- if (length(filter_res$filtered) > 0L && !length(filter_res$kept)) {
      paste0("all_", length(filter_res$filtered), "_paths_filtered_as_archive_noise")
    } else {
      extract_res$message %||% "no_tabular_files_found"
    }
    first_log <- append_log_row(list(
      provider_dataset_id = ds_id, provider_file_id = file_id,
      file_path = file_name, action = "extract", status = "skipped",
      message = skip_msg,
      rows_in = 0L, rows_out = 0L, timestamp_utc = ts
    ), first_log)
    processed_ids <- c(processed_ids, file_id)
    next
  }

  for (tab_path in tabular_paths) {
    read_result <- tryCatch(
      dryad_read_supported_inputs(tab_path),
      error = function(e) list(tables = list(), log = data.frame())
    )

    if (!length(read_result$tables)) {
      first_log <- append_log_row(list(
        provider_dataset_id = ds_id, provider_file_id = file_id,
        file_path = tab_path, action = "read", status = "failed",
        message = "no_tables_parsed", rows_in = 0L, rows_out = 0L,
        timestamp_utc = ts
      ), first_log)
      next
    }

    for (table_entry in read_result$tables) {
      log_file_path <- zenodo_log_path(table_entry)
      provenance <- list(
        dryad_dataset_doi        = ds_id,
        dryad_version_id         = NA_integer_,
        dryad_file_id            = file_id,
        source_title             = row$source_title[[1]],
        source_authors           = row$source_authors[[1]],
        source_subjects          = row$source_subjects[[1]],
        source_abstract          = row$source_abstract[[1]],
        download_timestamp_utc   = ts,
        source_file_path         = table_entry$path
      )

      registry_error <- NA_character_
      registry_standardized <- tryCatch(
        zenodo_apply_parser_registry(
          table_entry$data,
          provenance = provenance
        ),
        error = function(e) {
          registry_error <<- conditionMessage(e)
          NULL
        }
      )

      if (!is.null(registry_standardized) && nrow(registry_standardized)) {
        standardized <- registry_standardized
      } else {
        fallback_error <- NA_character_
        standardized <- tryCatch(
          dryad_standardize_records(
            table_entry$data,
            provenance = provenance
          ),
          error = function(e) {
            fallback_error <<- conditionMessage(e)
            NULL
          }
        )
      }

      if (is.null(standardized) || !nrow(standardized)) {
        first_log <- append_log_row(list(
          provider_dataset_id = ds_id, provider_file_id = file_id,
          file_path = log_file_path, action = "standardize", status = "skipped",
          message = zenodo_no_trait_message(registry_error, fallback_error), rows_in = nrow(table_entry$data),
          rows_out = 0L, timestamp_utc = ts
        ), first_log)
        next
      }

      # QA checks
      standardized <- tryCatch(
        dryad_qa_check(standardized),
        error = function(e) standardized
      )

      n_flagged <- sum(nzchar(standardized$qa_flags), na.rm = TRUE)
      qa_msg <- if (n_flagged > 0L) {
        flag_types <- sort(table(unlist(strsplit(
          standardized$qa_flags[nzchar(standardized$qa_flags)], "\\|"
        ))))
        paste(names(flag_types), flag_types, sep = "=", collapse = "; ")
      } else "PASS"

      first_log <- append_log_row(list(
        provider_dataset_id = ds_id, provider_file_id = file_id,
        file_path = log_file_path, action = "qa",
        status = if (n_flagged == 0L) "PASS" else "FLAGS",
        message = qa_msg, rows_in = nrow(standardized),
        rows_out = nrow(standardized) - n_flagged,
        timestamp_utc = zenodo_now_utc()
      ), first_log)

      # Spot check log
      spot <- tryCatch(dryad_spot_check(standardized, n = 5L), error = function(e) NULL)
      if (!is.null(spot) && nrow(spot)) {
        spot_path <- file.path(output_dir, "spot_check_log.csv")
        utils::write.table(spot, spot_path, sep = ",", row.names = FALSE, na = "",
                           append = file.exists(spot_path), col.names = !file.exists(spot_path),
                           qmethod = "double")
      }

      # Write compiled rows
      utils::write.table(
        standardized, compiled_path,
        sep = ",", row.names = FALSE, na = "",
        append = !first_compiled, col.names = first_compiled,
        qmethod = "double"
      )
      first_compiled     <- FALSE
      n_compiled_rows    <- n_compiled_rows + nrow(standardized)

      first_log <- append_log_row(list(
        provider_dataset_id = ds_id, provider_file_id = file_id,
        file_path = log_file_path, action = "standardize", status = "compiled",
        message = "Compiled BIEN-style observation rows.",
        rows_in = nrow(table_entry$data), rows_out = nrow(standardized),
        timestamp_utc = zenodo_now_utc()
      ), first_log)
    }
  }

  processed_ids <- c(processed_ids, file_id)
  n_files_done  <- n_files_done + 1L
}

message(sprintf(
  "Zenodo compile complete: %d observation rows from %d files processed (%d selected).",
  n_compiled_rows, n_files_done, nrow(supported)
))
message(sprintf("Outputs in: %s", output_dir))
