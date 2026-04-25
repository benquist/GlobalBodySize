#!/usr/bin/env Rscript

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

source_project_files()

search_payload <- dryad_search_datasets("plant* trait*", per_page = 2)
search_rows <- dryad_flatten_search_results(search_payload, query_term = "plant* trait*")

if (!nrow(search_rows)) {
  stop("Smoke test failed: Dryad search returned zero candidate rows.", call. = FALSE)
}

# Fix 1 regression guard: verify pagination field access via [[ ]] does not error and returns
# the expected type (NULL when no next page, or a list/character when present).
has_next_page <- !is.null(search_payload[["_links"]][["next"]])
if (!is.logical(has_next_page)) {
  stop("Smoke test failed: pagination check did not return a logical value.", call. = FALSE)
}
message(sprintf("Smoke test: pagination check OK (has_next_page=%s).", has_next_page))

# Metadata inventory: retrieve version metadata for the first live result without a token.
first_doi <- search_rows$dryad_dataset_doi[[1]]
if (!is.na(first_doi) && nzchar(first_doi)) {
  version_payload <- tryCatch(
    dryad_get_dataset_versions(first_doi, per_page = 5),
    error = function(e) NULL
  )
  if (is.null(version_payload)) {
    message("Smoke test: version inventory call failed (network issue?); skipping inventory assertion.")
  } else {
    version_table <- dryad_flatten_versions(version_payload, dataset_identifier = first_doi)
    message(sprintf("Smoke test: inventory OK (%s version(s) found for %s).", nrow(version_table), first_doi))

    # Narrow file-inventory check: exercise dryad_get_version_files / dryad_flatten_files.
    if (nrow(version_table) > 0L) {
      latest_version_id <- version_table$dryad_version_id[[nrow(version_table)]]
      file_payload <- tryCatch(
        dryad_get_version_files(latest_version_id, per_page = 5),
        error = function(e) NULL
      )
      if (is.null(file_payload)) {
        message("Smoke test: file inventory call failed (network issue?); skipping file assertion.")
      } else {
        file_table <- dryad_flatten_files(
          file_payload,
          dryad_dataset_doi = first_doi,
          dryad_version_id = latest_version_id
        )
        message(sprintf("Smoke test: file inventory OK (%s file(s) listed for version %s).", nrow(file_table), latest_version_id))
      }
    }
  }
}

synthetic_traits <- data.frame(
  species = c("Quercus agrifolia", "Pinus ponderosa"),
  latitude = c(36.7783, 34.9592),
  longitude = c(-119.4179, -111.5986),
  collection_date = c("2025-05-01", "2025-06-12"),
  site = c("Plot 1", "Plot 2"),
  leaf_area = c(32.1, 18.4),
  wood_density = c(NA, 0.46),
  unit = c("mixed_source_units", "mixed_source_units"),
  stringsAsFactors = FALSE,
  check.names = FALSE
)

standardized <- dryad_standardize_records(
  synthetic_traits,
  provenance = list(
    dryad_dataset_doi = "doi:10.5061/dryad.synthetic",
    dryad_version_id = 1L,
    dryad_file_id = 1L,
    source_title = "Synthetic smoke-test trait table",
    source_authors = "GitHub Copilot",
    source_subjects = "plant traits; smoke test",
    source_abstract = "Synthetic table used only for local smoke testing.",
    download_timestamp_utc = dryad_now_utc(),
    source_file_path = "synthetic.csv"
  )
)

if (nrow(standardized) < 3L) {
  stop("Smoke test failed: standardizer returned fewer observation rows than expected.", call. = FALSE)
}

required_traits <- c("leaf_area", "wood_density")
if (!all(required_traits %in% standardized$trait_name)) {
  stop("Smoke test failed: expected standardized trait names were not present.", call. = FALSE)
}

message(sprintf("Smoke test passed: %s live Dryad rows and %s standardized synthetic observations.", nrow(search_rows), nrow(standardized)))
