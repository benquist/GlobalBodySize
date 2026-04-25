#!/usr/bin/env Rscript

parse_named_args <- function(args) {
  values <- list()
  if (!length(args)) {
    return(values)
  }

  for (arg in args) {
    if (!startsWith(arg, "--")) {
      next
    }
    parts <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1]]
    key <- parts[[1]]
    value <- if (length(parts) > 1L) paste(parts[-1L], collapse = "=") else "TRUE"
    values[[key]] <- value
  }

  values
}

find_project_root <- function() {
  cwd <- getwd()
  if (basename(cwd) == "DryadPlantTraits") return(cwd)
  if (basename(cwd) == "scripts" && basename(dirname(cwd)) == "DryadPlantTraits") return(dirname(cwd))
  proj <- file.path(cwd, "DryadPlantTraits")
  if (dir.exists(proj)) return(proj)
  stop("Cannot locate DryadPlantTraits project root from: ", cwd, call. = FALSE)
}

source_project_files <- function() {
  root <- find_project_root()
  files <- c(
    file.path(root, "R", "search_terms.R"),
    file.path(root, "R", "trait_dictionary.R"),
    file.path(root, "R", "io_helpers.R"),
    file.path(root, "R", "dryad_api.R"),
    file.path(root, "R", "candidate_filter.R"),
    file.path(root, "R", "standardize_records.R")
  )
  invisible(lapply(files, source, local = FALSE))
}

empty_processing_log <- function() {
  data.frame(
    dryad_dataset_doi = character(0),
    dryad_version_id = integer(0),
    dryad_file_id = integer(0),
    file_path = character(0),
    action = character(0),
    status = character(0),
    message = character(0),
    rows_in = integer(0),
    rows_out = integer(0),
    timestamp_utc = character(0),
    stringsAsFactors = FALSE
  )
}

append_log <- function(log_table, row) {
  rbind(log_table, as.data.frame(row, stringsAsFactors = FALSE))
}

select_candidate_files <- function(file_table, max_datasets, max_files) {
  if (!nrow(file_table)) {
    return(file_table)
  }

  filtered <- file_table[file_table$candidate_keep & (file_table$file_supported_tabular | file_table$file_supported_container), , drop = FALSE]
  if (!nrow(filtered)) {
    return(filtered)
  }

  filtered <- filtered[order(-filtered$candidate_score, filtered$dryad_dataset_doi, filtered$file_path), , drop = FALSE]
  if (is.finite(max_datasets)) {
    keep_datasets <- unique(filtered$dryad_dataset_doi)[seq_len(min(max_datasets, length(unique(filtered$dryad_dataset_doi))))]
    filtered <- filtered[filtered$dryad_dataset_doi %in% keep_datasets, , drop = FALSE]
  }
  if (is.finite(max_files)) {
    filtered <- filtered[seq_len(min(max_files, nrow(filtered))), , drop = FALSE]
  }
  filtered
}

source_project_files()

args <- parse_named_args(commandArgs(trailingOnly = TRUE))
output_dir <- args$`output-dir` %||% args$output_dir %||% file.path(find_project_root(), "output")
candidate_files_path <- args$`candidate-files` %||% file.path(output_dir, "candidate_files.csv")
max_datasets <- as.integer(args$`max-datasets` %||% "3")
max_files <- as.integer(args$`max-files` %||% "5")

dryad_make_dir(output_dir)

if (!file.exists(candidate_files_path)) {
  stop(sprintf("Candidate file inventory not found at %s. Run the discovery script first.", candidate_files_path), call. = FALSE)
}

candidate_files <- utils::read.csv(candidate_files_path, stringsAsFactors = FALSE, check.names = FALSE)
selected_files <- select_candidate_files(candidate_files, max_datasets = max_datasets, max_files = max_files)
processing_log_list <- list()
compiled_rows <- list()
first_compiled_write <- TRUE

download_dir <- file.path(output_dir, "downloads")
dryad_make_dir(download_dir)

for (row_index in seq_len(nrow(selected_files))) {
  row <- selected_files[row_index, , drop = FALSE]
  local_name <- sprintf("%s_%s_%s", row$dryad_file_id[[1]], row$dryad_version_id[[1]], basename(row$file_path[[1]]))
  destfile <- file.path(download_dir, local_name)
  download_timestamp <- dryad_now_utc()
  download_result <- dryad_download_file(
    file_id = row$dryad_file_id[[1]],
    filename = row$file_path[[1]],
    destfile = destfile
  )

  if (!isTRUE(download_result$success)) {
    processing_log_list[[length(processing_log_list) + 1L]] <- list(
      dryad_dataset_doi = row$dryad_dataset_doi[[1]],
      dryad_version_id = row$dryad_version_id[[1]],
      dryad_file_id = row$dryad_file_id[[1]],
      file_path = row$file_path[[1]],
      action = "download",
      status = "failed",
      message = download_result$message,
      rows_in = 0L,
      rows_out = 0L,
      timestamp_utc = download_timestamp
    )

    utils::write.csv(do.call(rbind, lapply(processing_log_list, as.data.frame, stringsAsFactors = FALSE)), file.path(output_dir, "processing_log.csv"), row.names = FALSE, na = "")

    next
  }

  read_result <- dryad_read_supported_inputs(destfile)
  if (!nrow(read_result$log)) {
    next
  }

  for (log_index in seq_len(nrow(read_result$log))) {
    log_row <- read_result$log[log_index, , drop = FALSE]
    processing_log_list[[length(processing_log_list) + 1L]] <- list(
      dryad_dataset_doi = row$dryad_dataset_doi[[1]],
      dryad_version_id = row$dryad_version_id[[1]],
      dryad_file_id = row$dryad_file_id[[1]],
      file_path = log_row$extracted_path[[1]] %||% row$file_path[[1]],
      action = "read",
      status = log_row$status[[1]],
      message = log_row$message[[1]],
      rows_in = 0L,
      rows_out = 0L,
      timestamp_utc = download_timestamp
    )
  }

  if (!length(read_result$tables)) {
    next
  }

  for (table_entry in read_result$tables) {
    standardized <- dryad_standardize_records(
      table_entry$data,
      provenance = list(
        dryad_dataset_doi = row$dryad_dataset_doi[[1]],
        dryad_version_id = row$dryad_version_id[[1]],
        dryad_file_id = row$dryad_file_id[[1]],
        source_title = row$source_title[[1]],
        source_authors = row$source_authors[[1]],
        source_subjects = row$source_subjects[[1]],
        source_abstract = row$source_abstract[[1]],
        download_timestamp_utc = download_timestamp,
        source_file_path = table_entry$path
      )
    )

    processing_log_list[[length(processing_log_list) + 1L]] <- list(
      dryad_dataset_doi = row$dryad_dataset_doi[[1]],
      dryad_version_id = row$dryad_version_id[[1]],
      dryad_file_id = row$dryad_file_id[[1]],
      file_path = table_entry$path,
      action = "standardize",
      status = if (nrow(standardized)) "compiled" else "skipped",
      message = if (nrow(standardized)) "Compiled BIEN-style observation rows." else "No likely trait observation fields detected.",
      rows_in = nrow(table_entry$data),
      rows_out = nrow(standardized),
      timestamp_utc = dryad_now_utc()
    )

    if (nrow(standardized)) {
      compiled_rows[[length(compiled_rows) + 1L]] <- standardized
      utils::write.table(standardized, file.path(output_dir, "compiled_trait_observations.csv"),
        sep = ",", row.names = FALSE, na = "",
        append = !first_compiled_write, col.names = first_compiled_write, qmethod = "double")
      first_compiled_write <- FALSE
    }
  }

  utils::write.csv(do.call(rbind, lapply(processing_log_list, as.data.frame, stringsAsFactors = FALSE)), file.path(output_dir, "processing_log.csv"), row.names = FALSE, na = "")
}

utils::write.csv(do.call(rbind, lapply(processing_log_list, as.data.frame, stringsAsFactors = FALSE)), file.path(output_dir, "processing_log.csv"), row.names = FALSE, na = "")

message(sprintf("Compiled %s observation rows from %s selected files.", sum(vapply(compiled_rows, nrow, integer(1L))), nrow(selected_files)))
