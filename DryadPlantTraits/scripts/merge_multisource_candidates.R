#!/usr/bin/env Rscript

find_project_root <- function() {
  cwd <- getwd()
  if (basename(cwd) == "DryadPlantTraits") return(cwd)
  if (basename(cwd) == "scripts" && basename(dirname(cwd)) == "DryadPlantTraits") return(dirname(cwd))
  probe <- file.path(cwd, "DryadPlantTraits")
  if (dir.exists(probe)) return(probe)
  stop("Cannot locate DryadPlantTraits project root from: ", cwd, call. = FALSE)
}

project_root <- find_project_root()
source(file.path(project_root, "providers", "common", "R", "provider_common.R"), local = FALSE)
source(file.path(project_root, "providers", "common", "R", "dryad_adapter.R"), local = FALSE)

resolve_provider_dataset_schema <- function() {
  fn <- get0("provider_dataset_schema", mode = "function")
  if (is.null(fn)) {
    stop("provider_dataset_schema is not available. Source providers/common/R/provider_common.R first.", call. = FALSE)
  }
  fn
}

resolve_provider_complete_dataset_schema <- function() {
  fn <- get0("provider_complete_dataset_schema", mode = "function")
  if (is.null(fn)) {
    stop("provider_complete_dataset_schema is not available. Source providers/common/R/provider_common.R first.", call. = FALSE)
  }
  fn
}

resolve_provider_file_schema <- function() {
  fn <- get0("provider_file_schema", mode = "function")
  if (is.null(fn)) {
    stop("provider_file_schema is not available. Source providers/common/R/provider_common.R first.", call. = FALSE)
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

args <- provider_parse_named_args(commandArgs(trailingOnly = TRUE))
output_dir <- args$`output-dir` %||% args$output_dir %||% file.path(project_root, "output")

sync_legacy_dryad_provider_outputs(output_dir)

providers <- c("dryad", "try", "fred", "leda")

dataset_schema <- resolve_provider_dataset_schema()
complete_dataset_schema <- resolve_provider_complete_dataset_schema()
file_schema <- resolve_provider_file_schema()
complete_file_schema <- resolve_provider_complete_file_schema()

read_provider_dataset_table <- function(provider_name) {
  path <- file.path(output_dir, "providers", provider_name, "candidate_datasets.csv")
  if (!file.exists(path)) {
    return(dataset_schema(0))
  }
  table <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  if (!"source_provider" %in% names(table)) {
    table$source_provider <- provider_name
  }
  if (!"provider_dataset_id" %in% names(table)) {
    table$provider_dataset_id <- sprintf("%s_dataset_%s", provider_name, seq_len(nrow(table)))
  }
  complete_dataset_schema(table)
}

read_provider_file_table <- function(provider_name) {
  path <- file.path(output_dir, "providers", provider_name, "candidate_files.csv")
  if (!file.exists(path)) {
    return(file_schema(0))
  }
  table <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  if (!"source_provider" %in% names(table)) {
    table$source_provider <- provider_name
  }
  if (!"provider_dataset_id" %in% names(table)) {
    table$provider_dataset_id <- sprintf("%s_dataset_%s", provider_name, seq_len(nrow(table)))
  }
  if (!"provider_file_id" %in% names(table)) {
    table$provider_file_id <- sprintf("%s_file_%s", provider_name, seq_len(nrow(table)))
  }
  complete_file_schema(table)
}

dataset_tables <- lapply(providers, read_provider_dataset_table)
file_tables <- lapply(providers, read_provider_file_table)

all_datasets <- do.call(rbind, dataset_tables)
all_files <- do.call(rbind, file_tables)

if (nrow(all_datasets)) {
  split_rows <- split(all_datasets, paste(all_datasets$source_provider, all_datasets$provider_dataset_id, sep = "::"), drop = TRUE)
  deduped <- lapply(split_rows, function(chunk) {
    score <- ifelse(is.na(chunk$candidate_score), -Inf, chunk$candidate_score)
    idx <- order(-score)[[1]]
    chunk[idx, , drop = FALSE]
  })
  all_datasets <- do.call(rbind, deduped)
}

if (nrow(all_files)) {
  dataset_keys <- paste(all_datasets$source_provider, all_datasets$provider_dataset_id, sep = "::")
  dataset_scores <- all_datasets$candidate_score
  names(dataset_scores) <- dataset_keys
  dataset_keep <- all_datasets$candidate_keep
  names(dataset_keep) <- dataset_keys

  file_keys <- paste(all_files$source_provider, all_files$provider_dataset_id, sep = "::")
  missing_score <- is.na(all_files$candidate_score)
  if (any(missing_score)) {
    mapped <- dataset_scores[file_keys[missing_score]]
    all_files$candidate_score[missing_score] <- ifelse(is.na(mapped), 0.5, mapped)
  }
  missing_keep <- is.na(all_files$candidate_keep)
  if (any(missing_keep)) {
    mapped <- dataset_keep[file_keys[missing_keep]]
    all_files$candidate_keep[missing_keep] <- ifelse(is.na(mapped), TRUE, mapped)
  }
}

multisource_dataset_path <- file.path(output_dir, "multisource_candidate_datasets.csv")
multisource_file_path <- file.path(output_dir, "multisource_candidate_files.csv")

utils::write.csv(complete_dataset_schema(all_datasets), multisource_dataset_path, row.names = FALSE, na = "")
utils::write.csv(complete_file_schema(all_files), multisource_file_path, row.names = FALSE, na = "")

message(sprintf(
  "Merged provider candidates written: %s datasets, %s files.",
  nrow(all_datasets),
  nrow(all_files)
))
