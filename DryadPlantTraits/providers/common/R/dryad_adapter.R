resolve_provider_complete_dataset_schema <- function() {
  fn <- get0("provider_complete_dataset_schema", mode = "function")
  if (is.null(fn)) {
    stop("provider_complete_dataset_schema is not available. Source providers/common/R/provider_common.R first.", call. = FALSE)
  }
  fn
}

resolve_provider_complete_file_schema <- function() {
  fn <- get0("provider_complete_file_schema", mode = "function")
  if (is.null(fn)) {
    stop("provider_complete_file_schema is not available. Source providers/common/R/provider_common.R first.", call. = FALSE)
  }
  fn
}

sync_legacy_dryad_provider_outputs <- function(output_dir) {
  source_provider <- "dryad"
  legacy_dataset_path <- file.path(output_dir, "candidate_datasets.csv")
  legacy_file_path <- file.path(output_dir, "candidate_files.csv")

  provider_dir <- file.path(output_dir, "providers", source_provider)
  provider_dataset_path <- file.path(provider_dir, "candidate_datasets.csv")
  provider_file_path <- file.path(provider_dir, "candidate_files.csv")

  has_provider_files <- file.exists(provider_dataset_path) && file.exists(provider_file_path)
  has_legacy_files <- file.exists(legacy_dataset_path) && file.exists(legacy_file_path)

  if (has_provider_files || !has_legacy_files) {
    return(list(synced = FALSE, provider_dataset_path = provider_dataset_path, provider_file_path = provider_file_path))
  }

  legacy_datasets <- utils::read.csv(legacy_dataset_path, stringsAsFactors = FALSE, check.names = FALSE)
  legacy_files <- utils::read.csv(legacy_file_path, stringsAsFactors = FALSE, check.names = FALSE)

  if (!"source_provider" %in% names(legacy_datasets)) {
    legacy_datasets$source_provider <- source_provider
  }
  if (!"provider_dataset_id" %in% names(legacy_datasets)) {
    if ("dryad_dataset_doi" %in% names(legacy_datasets)) {
      legacy_datasets$provider_dataset_id <- legacy_datasets$dryad_dataset_doi
    } else if ("dryad_dataset_id" %in% names(legacy_datasets)) {
      legacy_datasets$provider_dataset_id <- as.character(legacy_datasets$dryad_dataset_id)
    } else {
      legacy_datasets$provider_dataset_id <- sprintf("dryad_dataset_%s", seq_len(nrow(legacy_datasets)))
    }
  }

  if (!"source_provider" %in% names(legacy_files)) {
    legacy_files$source_provider <- source_provider
  }
  if (!"provider_dataset_id" %in% names(legacy_files)) {
    if ("dryad_dataset_doi" %in% names(legacy_files)) {
      legacy_files$provider_dataset_id <- legacy_files$dryad_dataset_doi
    } else {
      legacy_files$provider_dataset_id <- sprintf("dryad_dataset_%s", seq_len(nrow(legacy_files)))
    }
  }
  if (!"provider_file_id" %in% names(legacy_files)) {
    if ("dryad_file_id" %in% names(legacy_files)) {
      legacy_files$provider_file_id <- as.character(legacy_files$dryad_file_id)
    } else {
      legacy_files$provider_file_id <- sprintf("dryad_file_%s", seq_len(nrow(legacy_files)))
    }
  }

  complete_dataset_schema <- resolve_provider_complete_dataset_schema()
  complete_file_schema <- resolve_provider_complete_file_schema()

  legacy_datasets <- complete_dataset_schema(legacy_datasets)
  legacy_files <- complete_file_schema(legacy_files)

  dir.create(provider_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(legacy_datasets, provider_dataset_path, row.names = FALSE, na = "")
  utils::write.csv(legacy_files, provider_file_path, row.names = FALSE, na = "")

  list(synced = TRUE, provider_dataset_path = provider_dataset_path, provider_file_path = provider_file_path)
}
