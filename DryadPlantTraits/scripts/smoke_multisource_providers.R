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
rscript_bin <- file.path(R.home("bin"), "Rscript")

assert_missing_manifest_error <- function(script_path) {
  result <- suppressWarnings(system2(
    rscript_bin,
    c("--vanilla", script_path),
    stdout = TRUE,
    stderr = TRUE
  ))

  status <- attr(result, "status")
  output <- paste(result, collapse = "\n")

  if (is.null(status) || identical(status, 0L)) {
    stop("Expected non-zero exit status for missing --manifest in: ", script_path, call. = FALSE)
  }
  if (!grepl("--manifest", output, fixed = TRUE)) {
    stop("Expected missing --manifest message in output for: ", script_path, call. = FALSE)
  }
}

assert_missing_manifest_error(file.path(project_root, "providers", "try", "scripts", "ingest_try_traits.R"))
assert_missing_manifest_error(file.path(project_root, "providers", "fred", "scripts", "ingest_fred_traits.R"))
assert_missing_manifest_error(file.path(project_root, "providers", "leda", "scripts", "ingest_leda_traits.R"))

# Verify merge can run with only legacy Dryad files by staging a temp output folder.
stage_dir <- tempfile("multisource_smoke_")
dir.create(stage_dir, recursive = TRUE, showWarnings = FALSE)

legacy_dataset <- file.path(project_root, "output", "candidate_datasets.csv")
legacy_file <- file.path(project_root, "output", "candidate_files.csv")
if (!file.exists(legacy_dataset) || !file.exists(legacy_file)) {
  stop("Smoke test requires legacy Dryad candidate outputs in output/", call. = FALSE)
}

file.copy(legacy_dataset, file.path(stage_dir, "candidate_datasets.csv"), overwrite = TRUE)
file.copy(legacy_file, file.path(stage_dir, "candidate_files.csv"), overwrite = TRUE)

merge_script <- file.path(project_root, "scripts", "merge_multisource_candidates.R")
merge_result <- system2(
  rscript_bin,
  c("--vanilla", merge_script, sprintf("--output-dir=%s", stage_dir)),
  stdout = TRUE,
  stderr = TRUE
)

if (!is.null(attr(merge_result, "status")) && attr(merge_result, "status") != 0L) {
  stop("Merge smoke test failed: ", paste(merge_result, collapse = "\n"), call. = FALSE)
}
if (!file.exists(file.path(stage_dir, "multisource_candidate_datasets.csv"))) {
  stop("Merge smoke test failed: missing multisource_candidate_datasets.csv", call. = FALSE)
}
if (!file.exists(file.path(stage_dir, "multisource_candidate_files.csv"))) {
  stop("Merge smoke test failed: missing multisource_candidate_files.csv", call. = FALSE)
}

message("Smoke test passed: provider CLIs fail clearly without --manifest, and merge runs from legacy Dryad outputs.")
