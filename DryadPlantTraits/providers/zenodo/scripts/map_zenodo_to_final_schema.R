#!/usr/bin/env Rscript
# map_zenodo_to_final_schema.R
# Map Zenodo compiled observations to the Dryad final reconciled schema.
# This script does not modify Dryad outputs and writes a Zenodo-only final file.
#
# Usage:
#   Rscript providers/zenodo/scripts/map_zenodo_to_final_schema.R \
#     --input=output/providers/zenodo/compiled_trait_observations.csv \
#     --output=output/providers/zenodo/compiled_trait_observations_with_unit_inference.csv \
#     --schema-reference=output/compiled_trait_observations_with_unit_inference.csv

zenodo_map_find_root <- function() {
  cwd <- getwd()
  if (basename(cwd) == "DryadPlantTraits") return(cwd)
  probe <- file.path(cwd, "DryadPlantTraits")
  if (dir.exists(probe)) return(probe)
  if (basename(cwd) == "zenodo" && basename(dirname(cwd)) == "providers") {
    return(dirname(dirname(cwd)))
  }
  if (basename(cwd) == "scripts" &&
      basename(dirname(cwd)) == "zenodo" &&
      grepl("providers$", dirname(dirname(cwd)))) {
    return(dirname(dirname(dirname(cwd))))
  }
  stop("Cannot locate DryadPlantTraits project root from: ", cwd, call. = FALSE)
}

project_root <- zenodo_map_find_root()

source(file.path(project_root, "providers", "common", "R", "provider_common.R"), local = FALSE)
source(file.path(project_root, "R", "infer_units.R"), local = FALSE)
source(file.path(project_root, "R", "infer_units_decision_tree.R"), local = FALSE)

args <- provider_parse_named_args(commandArgs(trailingOnly = TRUE))

input_path <- args$input %||%
  file.path(project_root, "output", "providers", "zenodo", "compiled_trait_observations.csv")
output_path <- args$output %||%
  file.path(project_root, "output", "providers", "zenodo", "compiled_trait_observations_with_unit_inference.csv")
schema_reference_path <- args$`schema-reference` %||%
  file.path(project_root, "output", "compiled_trait_observations_with_unit_inference.csv")

if (!file.exists(input_path)) {
  stop("Input file not found: ", input_path, call. = FALSE)
}

obs <- utils::read.csv(input_path, stringsAsFactors = FALSE, check.names = FALSE)
message(sprintf("Loaded %d Zenodo compiled rows from %s", nrow(obs), input_path))

mapped <- infer_units_batch(obs)

required_reconciliation_cols <- c(
  "inferred_unit_value",
  "inferred_unit_confidence",
  "inference_evidence",
  "inference_citation_keys",
  "basis_type",
  "unit_conversion_factor"
)
missing_from_infer <- setdiff(required_reconciliation_cols, names(mapped))
if (length(missing_from_infer) > 0) {
  stop(
    "infer_units_batch() output is missing required reconciliation columns: ",
    paste(missing_from_infer, collapse = ", "),
    call. = FALSE
  )
}

if (!file.exists(schema_reference_path)) {
  stop(
    "Schema reference file not found: ",
    schema_reference_path,
    ". Provide a valid --schema-reference path to enforce Dryad final schema parity.",
    call. = FALSE
  )
}
schema_header <- utils::read.csv(schema_reference_path, stringsAsFactors = FALSE, check.names = FALSE, nrows = 1)
final_columns <- names(schema_header)

missing_from_schema <- setdiff(required_reconciliation_cols, final_columns)
if (length(missing_from_schema) > 0) {
  stop(
    "Schema reference file is missing required reconciliation columns: ",
    paste(missing_from_schema, collapse = ", "),
    ". Check --schema-reference points to the correct Dryad final output.",
    call. = FALSE
  )
}

for (col_name in setdiff(final_columns, names(mapped))) {
  mapped[[col_name]] <- NA
}

mapped <- mapped[, final_columns, drop = FALSE]

out_dir <- dirname(output_path)
if (!dir.exists(out_dir)) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
}

utils::write.table(
  mapped,
  output_path,
  sep = ",",
  row.names = FALSE,
  na = "",
  quote = TRUE,
  col.names = TRUE,
  qmethod = "double"
)

message(sprintf("Wrote %d rows with %d columns to %s", nrow(mapped), ncol(mapped), output_path))
