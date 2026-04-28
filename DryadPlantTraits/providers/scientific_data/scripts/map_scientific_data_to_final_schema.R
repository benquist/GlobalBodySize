#!/usr/bin/env Rscript
# map_scientific_data_to_final_schema.R
# Map Scientific Data simple-schema compiled observations to the Dryad final reconciled schema.
# Reads the 9-column compiled_sdata_traits.csv, reshapes to 52-column base schema,
# runs infer_units_batch(), and writes the 58-column unified final file.
#
# Usage:
#   Rscript providers/scientific_data/scripts/map_scientific_data_to_final_schema.R \
#     --input=output/providers/scientific_data/compiled_sdata_traits.csv \
#     --output=output/providers/scientific_data/compiled_trait_observations_with_unit_inference.csv \
#     --schema-reference=output/compiled_trait_observations_with_unit_inference.csv

sdata_map_find_root <- function() {
  cwd <- getwd()
  if (basename(cwd) == "DryadPlantTraits") return(cwd)
  probe <- file.path(cwd, "DryadPlantTraits")
  if (dir.exists(probe)) return(probe)
  if (basename(cwd) == "scientific_data" && basename(dirname(cwd)) == "providers") {
    return(dirname(dirname(cwd)))
  }
  if (basename(cwd) == "scripts" &&
      basename(dirname(cwd)) == "scientific_data" &&
      grepl("providers$", dirname(dirname(cwd)))) {
    return(dirname(dirname(dirname(cwd))))
  }
  stop("Cannot locate DryadPlantTraits project root from: ", cwd, call. = FALSE)
}

project_root <- sdata_map_find_root()

source(file.path(project_root, "providers", "common", "R", "provider_common.R"), local = FALSE)
source(file.path(project_root, "R", "infer_units.R"), local = FALSE)
source(file.path(project_root, "R", "infer_units_decision_tree.R"), local = FALSE)

args <- provider_parse_named_args(commandArgs(trailingOnly = TRUE))

input_path <- args$input %||%
  file.path(project_root, "output", "providers", "scientific_data", "compiled_sdata_traits.csv")
output_path <- args$output %||%
  file.path(project_root, "output", "providers", "scientific_data", "compiled_trait_observations_with_unit_inference.csv")
schema_reference_path <- args$`schema-reference` %||%
  file.path(project_root, "output", "compiled_trait_observations_with_unit_inference.csv")

if (!file.exists(input_path)) {
  stop("Input file not found: ", input_path, call. = FALSE)
}

if (requireNamespace("data.table", quietly = TRUE)) {
  raw <- as.data.frame(data.table::fread(input_path, data.table = FALSE), stringsAsFactors = FALSE)
} else {
  message("data.table not available; falling back to utils::read.csv (may be slow for large files)")
  raw <- utils::read.csv(input_path, stringsAsFactors = FALSE, check.names = FALSE)
}
message(sprintf("Loaded %d Scientific Data compiled rows from %s", nrow(raw), input_path))

sdata_map_to_base_schema <- function(df, input_path) {
  n <- nrow(df)
  out <- data.frame(
    scrubbed_species_binomial  = as.character(df$taxon_name),
    latitude                   = NA_character_,
    longitude                  = NA_character_,
    date_collected             = NA_character_,
    dataset                    = as.character(df$source_doi),
    datasource                 = as.character(df$source_provider),
    dataowner                  = NA_character_,
    collection_code            = NA_character_,
    trait_name                 = as.character(df$trait_name),
    trait_value                = as.character(df$value),
    unit                       = as.character(df$unit),
    inferred_unit              = NA_character_,
    method                     = NA_character_,
    country                    = NA_character_,
    stateProvince              = NA_character_,
    county                     = NA_character_,
    locality                   = NA_character_,
    elevation_m                = NA_character_,
    expected_unit_class        = NA_character_,
    value_type                 = NA_character_,
    standard_unit              = NA_character_,
    trait_dictionary_notes     = NA_character_,
    dryad_dataset_doi          = as.character(df$source_doi),
    dryad_version_id           = NA_character_,
    dryad_file_id              = NA_character_,
    source_title               = as.character(df$source_paper),
    source_authors             = NA_character_,
    source_subjects            = NA_character_,
    source_abstract            = NA_character_,
    download_timestamp_utc     = as.character(df$compiled_timestamp),
    source_file_path           = input_path,
    original_row_number        = as.character(seq_len(n)),
    raw_taxon                  = as.character(df$taxon_name),
    raw_trait_name             = as.character(df$trait_name),
    raw_trait_value            = as.character(df$value),
    raw_unit                   = as.character(df$unit),
    raw_latitude               = NA_character_,
    raw_longitude              = NA_character_,
    raw_elevation              = NA_character_,
    raw_country                = NA_character_,
    raw_stateProvince          = NA_character_,
    raw_county                 = NA_character_,
    raw_locality               = NA_character_,
    raw_date_collected         = NA_character_,
    input_name_verbatim        = as.character(df$taxon_name),
    infraspecific_rank         = NA_character_,
    infraspecific_epithet      = NA_character_,
    source_column_taxon        = "taxon_name",
    source_column_trait_name   = "trait_name",
    source_column_trait_value  = "value",
    source_column_unit         = "unit",
    qa_flags                   = NA_character_,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  out
}

base_schema <- sdata_map_to_base_schema(raw, input_path)
message(sprintf("Reshaped to base schema: %d rows x %d columns", nrow(base_schema), ncol(base_schema)))
rm(raw)

mapped <- infer_units_batch(base_schema)
rm(base_schema)

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

dryad_cols <- final_columns
sdata_cols <- names(mapped)
header_parity <- identical(dryad_cols, sdata_cols)
message(sprintf("HEADER_PARITY: %s (Dryad cols: %d, SData cols: %d)", header_parity, length(dryad_cols), length(sdata_cols)))

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
