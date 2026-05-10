#!/usr/bin/env Rscript
## GlobalBodySize/scripts/discover_body_mass_datasets.R
## Stage 1: Dataset Discovery
## Searches Dryad, Zenodo, and Figshare APIs for datasets containing body mass data
## Modeled after DryadPlantTraits/scripts/discover_dryad_plant_traits.R
##
## Usage:
##   Rscript scripts/discover_body_mass_datasets.R
##   Rscript scripts/discover_body_mass_datasets.R --pages-per-term=5 --per-page=100 --repos=dryad,zenodo
##   Rscript scripts/discover_body_mass_datasets.R --min-score=10
##
## Outputs:
##   output/candidate_datasets.csv  — scored dataset-level inventory
##   output/candidate_files.csv     — file-level metadata (Dryad only in Stage 1)

## ---- Parse CLI args ---------------------------------------------------------

parse_named_args <- function(args) {
  values <- list()
  for (arg in args) {
    if (!startsWith(arg, "--")) next
    parts <- strsplit(sub("^--", "", arg), "=", fixed = TRUE)[[1]]
    key   <- parts[[1]]
    value <- if (length(parts) > 1L) paste(parts[-1L], collapse = "=") else "TRUE"
    values[[key]] <- value
  }
  values
}

find_project_root <- function() {
  cwd <- getwd()
  if (basename(cwd) == "GlobalBodySize") return(cwd)
  if (basename(cwd) == "scripts" && basename(dirname(cwd)) == "GlobalBodySize") return(dirname(cwd))
  proj <- file.path(cwd, "GlobalBodySize")
  if (dir.exists(proj)) return(proj)
  stop("Cannot locate GlobalBodySize project root from: ", cwd)
}

source_project_files <- function(root) {
  files <- c(
    file.path(root, "R", "search_terms.R"),
    file.path(root, "R", "candidate_filter.R"),
    file.path(root, "R", "dryad_api.R"),
    file.path(root, "R", "zenodo_api.R"),
    file.path(root, "R", "figshare_api.R"),
    file.path(root, "R", "body_mass_schema.R")
  )
  invisible(lapply(files, source, local = FALSE))
}

## ---- Main -------------------------------------------------------------------

main <- function() {
  args    <- parse_named_args(commandArgs(trailingOnly = TRUE))
  root    <- find_project_root()
  source_project_files(root)

  max_pages <- as.integer(args[["pages-per-term"]] %||% "5")
  per_page  <- as.integer(args[["per-page"]]       %||% "100")
  min_score <- as.integer(args[["min-score"]]       %||% "6")
  repos     <- strsplit(args[["repos"]] %||% "dryad,zenodo,figshare", ",")[[1]]

  out_dir   <- file.path(root, "output")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  terms <- globalsize_search_seed_terms()
  message("=== GlobalBodySize — Dataset Discovery ===")
  message("Search terms:    ", nrow(terms))
  message("Max pages/term:  ", max_pages)
  message("Per page:        ", per_page)
  message("Min score:       ", min_score)
  message("Repositories:    ", paste(repos, collapse = ", "))

  all_candidates <- list()

  ## ---- Dryad ---------------------------------------------------------------
  if ("dryad" %in% repos) {
    message("\n--- Querying Dryad ---")
    dryad_rows <- list()
    for (i in seq_len(nrow(terms))) {
      term <- terms$query_term[i]
      theme <- terms$theme[i]
      message(sprintf("[%d/%d] theme=%-20s term='%s'", i, nrow(terms), theme, term))

      datasets <- dryad_paginate_term(term, max_pages = max_pages,
                                      per_page = per_page, verbose = FALSE)
      if (!length(datasets)) next

      flat <- dryad_flatten_datasets(datasets, term)
      flat$theme  <- theme
      flat$source <- "dryad"
      dryad_rows[[i]] <- flat
      Sys.sleep(0.5)
    }
    dryad_combined <- do.call(rbind, Filter(Negate(is.null), dryad_rows))
    if (!is.null(dryad_combined) && nrow(dryad_combined) > 0) {
      dryad_combined <- score_candidates(dryad_combined)
      dryad_combined <- dryad_combined[dryad_combined$candidate_score >= min_score, ]
      all_candidates[["dryad"]] <- dryad_combined
      message("Dryad candidates above score ", min_score, ": ", nrow(dryad_combined))
    }
  }

  ## ---- Zenodo --------------------------------------------------------------
  if ("zenodo" %in% repos) {
    message("\n--- Querying Zenodo ---")
    zenodo_rows <- list()
    for (i in seq_len(nrow(terms))) {
      term  <- terms$query_term[i]
      theme <- terms$theme[i]
      message(sprintf("[%d/%d] Zenodo | '%s'", i, nrow(terms), term))

      rows <- query_zenodo_term(term, max_pages = max_pages, per_page = min(per_page, 100))
      if (is.null(rows) || !nrow(rows)) next
      rows$theme  <- theme
      rows$source <- "zenodo"
      zenodo_rows[[i]] <- rows
      Sys.sleep(1.0)
    }
    zenodo_combined <- do.call(rbind, Filter(Negate(is.null), zenodo_rows))
    if (!is.null(zenodo_combined) && nrow(zenodo_combined) > 0) {
      zenodo_combined <- score_candidates(zenodo_combined)
      zenodo_combined <- zenodo_combined[zenodo_combined$candidate_score >= min_score, ]
      all_candidates[["zenodo"]] <- zenodo_combined
      message("Zenodo candidates above score ", min_score, ": ", nrow(zenodo_combined))
    }
  }

  ## ---- Figshare ------------------------------------------------------------
  if ("figshare" %in% repos) {
    message("\n--- Querying Figshare ---")
    figshare_rows <- list()
    for (i in seq_len(nrow(terms))) {
      term  <- terms$query_term[i]
      theme <- terms$theme[i]
      message(sprintf("[%d/%d] Figshare | '%s'", i, nrow(terms), term))

      rows <- query_figshare_term(term, max_pages = max_pages)
      if (is.null(rows) || !nrow(rows)) next
      rows$theme  <- theme
      rows$source <- "figshare"
      figshare_rows[[i]] <- rows
      Sys.sleep(1.0)
    }
    figshare_combined <- do.call(rbind, Filter(Negate(is.null), figshare_rows))
    if (!is.null(figshare_combined) && nrow(figshare_combined) > 0) {
      figshare_combined <- score_candidates(figshare_combined)
      figshare_combined <- figshare_combined[figshare_combined$candidate_score >= min_score, ]
      all_candidates[["figshare"]] <- figshare_combined
      message("Figshare candidates above score ", min_score, ": ", nrow(figshare_combined))
    }
  }

  ## ---- Combine and write ---------------------------------------------------
  all_df <- do.call(rbind, all_candidates)
  if (is.null(all_df) || !nrow(all_df)) {
    message("No candidates found above score threshold. Try lowering --min-score.")
    return(invisible(NULL))
  }

  ## Deduplicate: within each source by DOI/id; then cross-source by DOI
  all_df <- all_df[!duplicated(paste(all_df$source, all_df$dryad_dataset_doi)), ]
  ## Cross-source dedup: keep first occurrence of any DOI seen in multiple repos
  has_doi <- !is.na(all_df$dryad_dataset_doi) & nchar(trimws(all_df$dryad_dataset_doi)) > 0
  all_df <- all_df[!has_doi | !duplicated(all_df$dryad_dataset_doi), ]
  all_df <- all_df[order(-all_df$candidate_score), ]

  out_file <- file.path(out_dir, "candidate_datasets.csv")
  data.table::fwrite(all_df, out_file)
  message("\nTotal candidates written: ", nrow(all_df), " -> ", out_file)
}

`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x

if (!interactive()) main()
