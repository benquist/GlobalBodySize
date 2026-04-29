#!/usr/bin/env Rscript
# map_traithub_to_final_schema.R
# Maps TraitHub (Bjorkman et al. 2018) to the 58-column final schema.
#
# Usage (from DryadPlantTraits root):
#   Rscript providers/traithub/scripts/map_traithub_to_final_schema.R

library(data.table)

input_path  <- file.path("data", "manual_ingestion", "TraitHub", "data_final", "TTT_cleaned_dataset_v1.csv")
output_dir  <- file.path("output", "providers", "traithub")
output_path <- file.path(output_dir, "compiled_trait_observations.csv")

if (!file.exists(input_path)) {
  stop("TraitHub source file not found: ", input_path, call. = FALSE)
}

dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

raw <- fread(input_path, data.table = TRUE)

# The first column is an unnamed row index; rename for clarity.
setnames(raw, 1L, "row_index")

# Build date_collected from Year + optional DayOfYear
raw[, date_collected_col := paste0(
  as.character(Year),
  ifelse(!is.na(DayOfYear) & DayOfYear != "", paste0("-", DayOfYear), "")
)]

out <- raw[, .(
  scrubbed_species_binomial  = AccSpeciesName,
  latitude                   = Latitude,
  longitude                  = Longitude,
  date_collected             = date_collected_col,
  dataset                    = "ShrubHub_TraitHub_v1",
  datasource                 = "traithub",
  dataowner                  = DataContributor,
  collection_code            = NA_character_,
  trait_name                 = Trait,
  trait_value                = as.character(Value),
  unit                       = Units,
  inferred_unit              = NA_character_,
  method                     = ValueKindName,
  country                    = NA_character_,
  stateProvince              = SiteName,
  county                     = SubsiteName,
  locality                   = NA_character_,
  elevation_m                = Elevation,
  expected_unit_class        = NA_character_,
  value_type                 = NA_character_,
  standard_unit              = NA_character_,
  trait_dictionary_notes     = NA_character_,
  dryad_dataset_doi          = NA_character_,
  dryad_version_id           = NA_character_,
  dryad_file_id              = NA_character_,
  source_title               = "Plant functional trait change across a warming tundra biome",
  source_authors             = "Bjorkman et al. 2018",
  source_subjects            = "tundra; plant functional traits; arctic; alpine; warming",
  source_abstract            = "The TraitHub dataset (Bjorkman et al. 2018, Nature, doi:10.1038/s41586-018-0563-7) compiles plant functional trait measurements from tundra sites worldwide.",
  download_timestamp_utc     = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
  source_file_path           = "data/manual_ingestion/TraitHub/data_final/TTT_cleaned_dataset_v1.csv",
  original_row_number        = as.integer(row_index),
  raw_taxon                  = OriginalName,
  raw_trait_name             = Trait,
  raw_trait_value            = as.character(Value),
  raw_unit                   = Units,
  raw_latitude               = as.character(Latitude),
  raw_longitude              = as.character(Longitude),
  raw_elevation              = as.character(Elevation),
  raw_country                = NA_character_,
  raw_stateProvince          = SiteName,
  raw_county                 = SubsiteName,
  raw_locality               = NA_character_,
  raw_date_collected         = as.character(Year),
  input_name_verbatim        = AccSpeciesName,
  infraspecific_rank         = NA_character_,
  infraspecific_epithet      = NA_character_,
  source_column_taxon        = "AccSpeciesName",
  source_column_trait_name   = "Trait",
  source_column_trait_value  = "Value",
  source_column_unit         = "Units",
  qa_flags                   = ifelse(!is.na(ErrorRisk) & ErrorRisk > 0.5, "high_error_risk", NA_character_),
  inferred_unit_value        = NA_character_,
  inferred_unit_confidence   = "none",
  inference_evidence         = NA_character_,
  inference_citation_keys    = "Bjorkman_2018_Nature_TraitHub",
  basis_type                 = NA_character_,
  unit_conversion_factor     = NA_real_
)]

# Enforce exact 58-column schema order
final_cols <- c(
  "scrubbed_species_binomial", "latitude", "longitude", "date_collected",
  "dataset", "datasource", "dataowner", "collection_code",
  "trait_name", "trait_value", "unit", "inferred_unit", "method",
  "country", "stateProvince", "county", "locality", "elevation_m",
  "expected_unit_class", "value_type", "standard_unit", "trait_dictionary_notes",
  "dryad_dataset_doi", "dryad_version_id", "dryad_file_id",
  "source_title", "source_authors", "source_subjects", "source_abstract",
  "download_timestamp_utc", "source_file_path", "original_row_number",
  "raw_taxon", "raw_trait_name", "raw_trait_value", "raw_unit",
  "raw_latitude", "raw_longitude", "raw_elevation",
  "raw_country", "raw_stateProvince", "raw_county", "raw_locality", "raw_date_collected",
  "input_name_verbatim", "infraspecific_rank", "infraspecific_epithet",
  "source_column_taxon", "source_column_trait_name", "source_column_trait_value", "source_column_unit",
  "qa_flags", "inferred_unit_value", "inferred_unit_confidence",
  "inference_evidence", "inference_citation_keys",
  "basis_type", "unit_conversion_factor"
)

stopifnot(length(final_cols) == 58L)
out <- out[, ..final_cols]

fwrite(out, output_path)

n_rows    <- nrow(out)
n_species <- length(unique(out$scrubbed_species_binomial))
n_traits  <- length(unique(out$trait_name))

message(sprintf("TraitHub mapper complete."))
message(sprintf("  Rows written : %d", n_rows))
message(sprintf("  Unique species: %d", n_species))
message(sprintf("  Unique traits : %d", n_traits))
message(sprintf("  Output        : %s", output_path))
