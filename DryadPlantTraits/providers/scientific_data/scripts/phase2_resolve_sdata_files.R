#!/usr/bin/env Rscript
# phase2_resolve_sdata_files.R
# Runs Phase 2 (file resolution) on existing candidate_datasets.csv.
# Uses pre-populated data_links to extract downloadable files.

# ---------------------------------------------------------------------------
# Locate project root and source dependencies
# ---------------------------------------------------------------------------

cwd <- getwd()
if (basename(cwd) == "DryadPlantTraits") {
  project_root <- cwd
} else if (dir.exists(file.path(cwd, "DryadPlantTraits"))) {
  project_root <- file.path(cwd, "DryadPlantTraits")
} else {
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

# Source dependencies
source(file.path(project_root, "R", "dryad_api.R"), local = FALSE)
source(file.path(project_root, "providers", "scientific_data", "R", "repo_resolver.R"), local = FALSE)
source(file.path(project_root, "providers", "common", "R", "provider_common.R"), local = FALSE)

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
output_dir <- "DryadPlantTraits/output/providers/scientific_data"

for (arg in args) {
  if (grepl("^--output-dir", arg)) {
    output_dir <- sub("^--output-dir=", "", arg)
  }
}

candidate_csv_path <- file.path(output_dir, "providers", "scientific_data", "candidate_datasets.csv")
if (!file.exists(candidate_csv_path)) {
  stop("candidate_datasets.csv not found at: ", candidate_csv_path, call. = FALSE)
}

message("Output dir: ", output_dir)
message("Candidate CSV: ", candidate_csv_path)

# ---------------------------------------------------------------------------
# Load candidate datasets
# ---------------------------------------------------------------------------

candidate_datasets <- tryCatch(
  utils::read.csv(candidate_csv_path, stringsAsFactors = FALSE, check.names = FALSE),
  error = function(e) {
    stop("Failed to read candidate_datasets: ", conditionMessage(e), call. = FALSE)
  }
)

message(sprintf("Loaded %d papers.", nrow(candidate_datasets)))

# Filter to kept papers
if ("candidate_keep" %in% names(candidate_datasets)) {
  candidate_datasets <- candidate_datasets[candidate_datasets$candidate_keep == TRUE | candidate_datasets$candidate_keep == "TRUE", , drop = FALSE]
  message(sprintf("Filtered to %d kept papers.", nrow(candidate_datasets)))
}

# ---------------------------------------------------------------------------
# Phase 2: Resolve files
# ---------------------------------------------------------------------------

message("\n--- Phase 2: Resolving files ---")

files_checkpoint_path <- file.path(output_dir, "sdata_files_checkpoint.csv")
file_rows <- list()
resolved_ids <- character(0)
first_file_write <- TRUE

if (file.exists(files_checkpoint_path)) {
  existing_files <- tryCatch(
    utils::read.csv(files_checkpoint_path, stringsAsFactors = FALSE, check.names = FALSE),
    error = function(e) NULL
  )
  if (!is.null(existing_files) && nrow(existing_files) && "provider_dataset_id" %in% names(existing_files)) {
    resolved_ids <- unique(existing_files$provider_dataset_id)
    file_rows <- list(existing_files)
    first_file_write <- FALSE
    message(sprintf("Resuming — %d already-resolved dataset IDs.", length(resolved_ids)))
  }
}

if (nrow(candidate_datasets) > 0L) {
  for (row_index in seq_len(nrow(candidate_datasets))) {
    dataset_doi <- candidate_datasets$provider_dataset_id[[row_index]] %||% candidate_datasets$doi[[row_index]]
    data_links  <- candidate_datasets$data_links[[row_index]]

    if (is.na(dataset_doi) || !nzchar(trimws(dataset_doi))) next
    if (dataset_doi %in% resolved_ids) next

    # Try to extract from abstract if data_links is empty
    if (is.na(data_links) || !nzchar(trimws(data_links %||% ""))) {
      message(sprintf("  [%d/%d] %s — no data_links, skipping", row_index, nrow(candidate_datasets), dataset_doi))
      resolved_ids <- c(resolved_ids, dataset_doi)
      next
    }

    message(sprintf("  [%d/%d] Resolving data links for %s", row_index, nrow(candidate_datasets), dataset_doi))

    resolved_files <- tryCatch(
      sdata_resolve_data_links(data_links),
      error = function(e) {
        warning(sprintf("Error resolving '%s': %s", dataset_doi, conditionMessage(e)))
        sdata_empty_file_table()
      }
    )

    if (is.null(resolved_files) || nrow(resolved_files) == 0L) {
      message(sprintf("    → No files resolved."))
      resolved_ids <- c(resolved_ids, dataset_doi)
      next
    }

    message(sprintf("    → Resolved %d files", nrow(resolved_files)))

    file_table <- provider_file_schema(nrow(resolved_files))
    file_table$source_provider      <- "scientific_data"
    file_table$provider_dataset_id  <- dataset_doi
    file_table$provider_file_id     <- paste(
      resolved_files$repo_type, resolved_files$repo_id, resolved_files$file_name, sep = "::"
    )
    file_table$file_name            <- resolved_files$file_name
    file_table$download_url         <- resolved_files$download_url
    file_table$file_size_bytes      <- resolved_files$file_size
    file_table$mime_type            <- resolved_files$mime_type
    file_table$source_file_path     <- paste0(resolved_files$repo_type, "/", resolved_files$repo_id)

    file_rows[[length(file_rows) + 1L]] <- file_table
    resolved_ids <- c(resolved_ids, dataset_doi)

    if (length(file_rows) %% 5L == 0L || row_index == nrow(candidate_datasets)) {
      all_files <- do.call(rbind, file_rows)
      utils::write.csv(all_files, files_checkpoint_path, row.names = FALSE)
      message(sprintf("    Checkpoint: %d total files written.", nrow(all_files)))
    }
  }
}

# ---------------------------------------------------------------------------
# Write final outputs
# ---------------------------------------------------------------------------

if (length(file_rows) > 0L) {
  all_files <- do.call(rbind, file_rows)
  output_files_path <- file.path(output_dir, "sdata_files_resolved.csv")
  utils::write.csv(all_files, output_files_path, row.names = FALSE)
  message(sprintf("\n✓ Resolved %d files from %d papers.", nrow(all_files), length(unique(all_files$provider_dataset_id))))
  message(sprintf("  Output: %s", output_files_path))
} else {
  message("\n✓ No files resolved.")
}
