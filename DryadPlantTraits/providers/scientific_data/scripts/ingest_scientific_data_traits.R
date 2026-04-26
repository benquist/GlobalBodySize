#!/usr/bin/env Rscript
# ingest_scientific_data_traits.R
# CLI wrapper to ingest a Scientific Data provider manifest into the unified
# trait observation schema.
#
# Usage:
#   Rscript providers/scientific_data/scripts/ingest_scientific_data_traits.R \
#     --manifest=output/providers/scientific_data/candidate_files.csv \
#     --output-dir=output

root_candidates <- c(
  getwd(),
  dirname(getwd()),
  dirname(dirname(getwd())),
  file.path(getwd(), "DryadPlantTraits")
)
root_candidates <- unique(normalizePath(
  root_candidates[file.exists(root_candidates)],
  winslash = "/",
  mustWork = FALSE
))
project_root <- root_candidates[basename(root_candidates) == "DryadPlantTraits"][1]
if (is.na(project_root) || !nzchar(project_root)) {
  stop("Cannot locate DryadPlantTraits project root from: ", getwd(), call. = FALSE)
}

source(file.path(project_root, "providers", "common", "R", "provider_common.R"),                      local = FALSE)
source(file.path(project_root, "providers", "scientific_data", "R", "ingest_scientific_data.R"),      local = FALSE)

args          <- provider_parse_named_args(commandArgs(trailingOnly = TRUE))
manifest_path <- args$manifest %||% args$`manifest-path`
if (is.null(manifest_path) || !nzchar(manifest_path)) {
  stop("Missing required argument --manifest=<path>", call. = FALSE)
}

output_dir <- args$`output-dir` %||% args$output_dir %||% file.path(project_root, "output")

result <- sdata_ingest_manifest(
  manifest_path = manifest_path,
  output_dir    = output_dir
)

message(sprintf(
  "Scientific Data ingest complete: %s dataset rows, %s file rows.",
  result$dataset_rows,
  result$file_rows
))
