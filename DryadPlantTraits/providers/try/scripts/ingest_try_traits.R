#!/usr/bin/env Rscript

root_candidates <- c(
  getwd(),
  dirname(getwd()),
  dirname(dirname(getwd())),
  file.path(getwd(), "DryadPlantTraits")
)
root_candidates <- unique(normalizePath(root_candidates[file.exists(root_candidates)], winslash = "/", mustWork = FALSE))
project_root <- root_candidates[basename(root_candidates) == "DryadPlantTraits"][1]
if (is.na(project_root) || !nzchar(project_root)) {
  stop("Cannot locate DryadPlantTraits project root from: ", getwd(), call. = FALSE)
}

source(file.path(project_root, "providers", "common", "R", "provider_common.R"), local = FALSE)
source(file.path(project_root, "providers", "try", "R", "ingest_try.R"), local = FALSE)

args <- provider_parse_named_args(commandArgs(trailingOnly = TRUE))
manifest_path <- args$manifest %||% args$`manifest-path`
if (is.null(manifest_path) || !nzchar(manifest_path)) {
  stop("Missing required argument --manifest=<path>", call. = FALSE)
}

output_dir <- args$`output-dir` %||% args$output_dir %||% file.path(project_root, "output")
result <- ingest_try_manifest(manifest_path = manifest_path, output_dir = output_dir)

message(sprintf(
  "TRY ingest complete: %s dataset rows, %s file rows.",
  result$dataset_rows,
  result$file_rows
))
