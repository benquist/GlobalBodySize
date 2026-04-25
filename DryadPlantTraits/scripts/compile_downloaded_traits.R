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

# Group candidate files by version so we download each version zip only once
version_groups <- split(seq_len(nrow(selected_files)), selected_files$dryad_version_id)

for (version_id in names(version_groups)) {
  row_indices <- version_groups[[version_id]]

  zip_path <- file.path(download_dir, sprintf("version_%s.zip", version_id))
  download_timestamp <- dryad_now_utc()

  # Download entire version zip (no auth required for public datasets)
  if (!file.exists(zip_path)) {
    dl_result <- dryad_download_version_zip(as.integer(version_id), zip_path)
    if (!isTRUE(dl_result$success)) {
      # Log failure for every file in this version
      for (ri in row_indices) {
        row_i <- selected_files[ri, , drop = FALSE]
        processing_log_list[[length(processing_log_list) + 1L]] <- list(
          dryad_dataset_doi = row_i$dryad_dataset_doi[[1]],
          dryad_version_id = as.integer(version_id),
          dryad_file_id = row_i$dryad_file_id[[1]],
          file_path = row_i$file_path[[1]],
          action = "download_version_zip",
          status = "failed",
          message = dl_result$message,
          rows_in = 0L,
          rows_out = 0L,
          timestamp_utc = download_timestamp
        )
      }
      utils::write.csv(do.call(rbind, lapply(processing_log_list, as.data.frame, stringsAsFactors = FALSE)), file.path(output_dir, "processing_log.csv"), row.names = FALSE, na = "")
      next
    }
  }

  # Process each candidate file extracted from this version zip
  for (row_index in row_indices) {
    row <- selected_files[row_index, , drop = FALSE]
    target_filename <- basename(row$file_path[[1]])

    # Extract just the target file from the zip into the downloads directory
    extract_dir <- file.path(download_dir, sprintf("v%s", version_id))
    dryad_make_dir(extract_dir)
    target_destfile <- file.path(extract_dir, target_filename)

    if (!file.exists(target_destfile)) {
      extract_status <- tryCatch(
        utils::unzip(zip_path, files = target_filename, exdir = extract_dir),
        error = function(e) {
          # Try unzipping without path prefix
          all_files <- utils::unzip(zip_path, list = TRUE)$Name
          match_file <- all_files[basename(all_files) == target_filename]
          if (length(match_file)) {
            utils::unzip(zip_path, files = match_file[[1]], exdir = extract_dir, junkpaths = TRUE)
          } else {
            character(0)
          }
        }
      )

      if (!file.exists(target_destfile)) {
        processing_log_list[[length(processing_log_list) + 1L]] <- list(
          dryad_dataset_doi = row$dryad_dataset_doi[[1]],
          dryad_version_id = as.integer(version_id),
          dryad_file_id = row$dryad_file_id[[1]],
          file_path = row$file_path[[1]],
          action = "extract",
          status = "failed",
          message = sprintf("File %s not found in zip.", target_filename),
          rows_in = 0L,
          rows_out = 0L,
          timestamp_utc = download_timestamp
        )
        utils::write.csv(do.call(rbind, lapply(processing_log_list, as.data.frame, stringsAsFactors = FALSE)), file.path(output_dir, "processing_log.csv"), row.names = FALSE, na = "")
        next
      }
    }

    read_result <- dryad_read_supported_inputs(target_destfile)

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
}

utils::write.csv(do.call(rbind, lapply(processing_log_list, as.data.frame, stringsAsFactors = FALSE)), file.path(output_dir, "processing_log.csv"), row.names = FALSE, na = "")

message(sprintf("Compiled %s observation rows from %s selected files.", sum(vapply(compiled_rows, nrow, integer(1L))), nrow(selected_files)))
