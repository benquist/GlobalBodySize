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

collapse_unique_values <- function(values) {
  values <- unique(values[!is.na(values) & nzchar(values)])
  if (!length(values)) NA_character_ else paste(values, collapse = "; ")
}

merge_query_terms <- function(dataset_table) {
  if (!nrow(dataset_table)) {
    return(dataset_table)
  }

  split_rows <- split(dataset_table, dataset_table$dryad_dataset_doi)
  merged <- lapply(split_rows, function(chunk) {
    best_row <- chunk[order(-chunk$candidate_score, chunk$title), , drop = FALSE][1, , drop = FALSE]
    best_row$query_term <- collapse_unique_values(chunk$query_term)
    best_row
  })

  do.call(rbind, merged)
}

source_project_files()

args <- parse_named_args(commandArgs(trailingOnly = TRUE))
output_dir <- args$output_dir %||% {
  if (basename(getwd()) == "DryadPlantTraits") file.path("output") else file.path("DryadPlantTraits", "output")
}
pages_per_term <- as.integer(args$`pages-per-term` %||% "1")
per_page <- as.integer(args$`per-page` %||% "25")

dryad_make_dir(output_dir)

search_terms <- dryad_search_seed_terms()
search_rows <- list()

for (term_index in seq_len(nrow(search_terms))) {
  query_term <- search_terms$query_term[[term_index]]
  for (page_index in seq_len(pages_per_term)) {
    payload <- dryad_search_datasets(query_term, page = page_index, per_page = per_page)
    rows <- dryad_flatten_search_results(payload, query_term = query_term)
    if (nrow(rows)) {
      search_rows[[length(search_rows) + 1L]] <- rows
    }
    if (is.null(payload[["_links"]][["next"]])) {
      break
    }
  }
}

dataset_table <- if (length(search_rows)) do.call(rbind, search_rows) else data.frame(stringsAsFactors = FALSE)
dataset_table <- dryad_score_candidate_table(dataset_table)
dataset_table <- merge_query_terms(dataset_table)
dataset_table <- dataset_table[order(-dataset_table$candidate_score, dataset_table$title), , drop = FALSE]

candidate_rows <- dataset_table[dataset_table$candidate_keep, , drop = FALSE]
file_rows <- list()

if (nrow(candidate_rows)) {
  for (row_index in seq_len(nrow(candidate_rows))) {
    dataset_identifier <- candidate_rows$dryad_dataset_doi[[row_index]]
    version_payload <- dryad_get_dataset_versions(dataset_identifier, per_page = 5)
    version_table <- dryad_flatten_versions(version_payload, dataset_identifier = dataset_identifier)
    if (!nrow(version_table)) {
      next
    }

    version_table <- version_table[order(-version_table$dryad_version_id), , drop = FALSE]
    latest_version <- version_table[1, , drop = FALSE]
    file_payload <- dryad_get_version_files(latest_version$dryad_version_id[[1]], per_page = 100)
    file_table <- dryad_flatten_files(
      file_payload,
      dryad_dataset_doi = dataset_identifier,
      dryad_version_id = latest_version$dryad_version_id[[1]]
    )

    if (!nrow(file_table)) {
      next
    }

    file_table$candidate_score <- candidate_rows$candidate_score[[row_index]]
    file_table$candidate_keep <- candidate_rows$candidate_keep[[row_index]]
    file_table$query_term <- candidate_rows$query_term[[row_index]]
    file_table$source_title <- latest_version$title[[1]]
    file_table$source_authors <- latest_version$authors[[1]]
    file_table$source_subjects <- latest_version$source_subjects[[1]]
    file_table$source_abstract <- latest_version$abstract[[1]]
    file_table$file_supported_tabular <- vapply(file_table$file_path, dryad_is_supported_tabular_path, logical(1))
    file_table$file_supported_container <- vapply(file_table$file_path, dryad_is_supported_archive_path, logical(1))
    file_rows[[length(file_rows) + 1L]] <- file_table
  }
}

file_table <- if (length(file_rows)) do.call(rbind, file_rows) else data.frame(stringsAsFactors = FALSE)

utils::write.csv(dataset_table, file.path(output_dir, "candidate_datasets.csv"), row.names = FALSE, na = "")
utils::write.csv(file_table, file.path(output_dir, "candidate_files.csv"), row.names = FALSE, na = "")

message(sprintf("Wrote %s dataset candidates and %s candidate files to %s", nrow(dataset_table), nrow(file_table), output_dir))
