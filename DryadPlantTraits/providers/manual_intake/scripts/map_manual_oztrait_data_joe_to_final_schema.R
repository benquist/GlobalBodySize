#!/usr/bin/env Rscript
# providers/manual_intake/scripts/map_manual_oztrait_data_joe_to_final_schema.R
# Map the user-supplied OzTrait JoE source file to the DryadPlantTraits canonical trait schema.

suppressPackageStartupMessages({
  library(data.table)
})

script_file <- tryCatch(normalizePath(sys.frame(0)$ofile, winslash = "/", mustWork = FALSE),
                        error = function(e) "")
if (!nzchar(script_file)) {
  args0 <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args0, value = TRUE)
  if (length(file_arg)) {
    script_file <- normalizePath(sub("^--file=", "", file_arg[[1]]), winslash = "/", mustWork = FALSE)
  }
}
root_candidates <- c(getwd(), dirname(getwd()), dirname(dirname(getwd())))
if (nzchar(script_file)) {
  d1 <- dirname(script_file); d2 <- dirname(d1); d3 <- dirname(d2)
  root_candidates <- c(root_candidates, d1, d2, d3)
}
root_candidates <- unique(normalizePath(root_candidates[file.exists(root_candidates)], winslash = "/", mustWork = FALSE))
proj_hits <- root_candidates[basename(root_candidates) == "DryadPlantTraits"]
if (!length(proj_hits)) stop("Cannot locate DryadPlantTraits project root from: ", getwd(), call. = FALSE)
project_root <- proj_hits[[1]]
cat("Project root:", project_root, "\n")

source_file <- file.path(project_root, "data", "manual_ingestion", "oztrait data JoE.csv")
if (!file.exists(source_file)) {
  stop("Source file not found: ", source_file, call. = FALSE)
}

cat("Reading source file: ", source_file, "\n")
raw <- tryCatch(fread(source_file, showProgress = FALSE), error = function(e) NULL)
if (is.null(raw)) stop("Failed to read CSV source: ", source_file, call. = FALSE)
cat(sprintf("Read %d rows x %d cols\n", nrow(raw), ncol(raw)))
cat("Columns: ", paste(names(raw), collapse = ", "), "\n")

find_column <- function(candidates) {
  hits <- intersect(candidates, names(raw))
  if (length(hits)) hits[[1L]] else NA_character_
}

col_taxon <- find_column(c("species", "scientificName", "taxon", "ScientificName", "species_name", "Species", "Taxon", "taxon_name"))
col_trait <- find_column(c("trait", "trait_name", "Trait", "TraitName", "measurement_name", "measurement", "variable", "Variable"))
col_value <- find_column(c("value", "trait_value", "TraitValue", "measurement_value", "Value", "measurement_value"))
col_unit <- find_column(c("unit", "units", "Unit", "Units", "measurement_unit"))
col_lat <- find_column(c("latitude", "lat", "decimalLatitude", "Latitude", "LAT", "Lat"))
col_lon <- find_column(c("longitude", "lon", "decimalLongitude", "Longitude", "LON", "Lon"))
col_date <- find_column(c("date", "eventDate", "collectionDate", "Date", "year", "Year", "date_collected"))
col_locality <- find_column(c("locality", "location", "Location", "site", "Site"))
col_state <- find_column(c("stateProvince", "state", "province", "State", "Province"))
col_country <- find_column(c("country", "Country", "countryCode", "country_code", "CountryCode"))
col_elevation <- find_column(c("elevation", "elevation_m", "altitude", "Altitude", "elev"))

if (is.na(col_taxon) || is.na(col_trait) || is.na(col_value)) {
  stop("Unable to locate required taxon/trait/value columns in oztrait source. Available columns: ", paste(names(raw), collapse = ", "), call. = FALSE)
}

out <- data.table(
  scrubbed_species_binomial = as.character(raw[[col_taxon]]),
  latitude = if (!is.na(col_lat)) as.numeric(raw[[col_lat]]) else rep(NA_real_, nrow(raw)),
  longitude = if (!is.na(col_lon)) as.numeric(raw[[col_lon]]) else rep(NA_real_, nrow(raw)),
  date_collected = if (!is.na(col_date)) as.character(raw[[col_date]]) else rep(NA_character_, nrow(raw)),
  dataset = "dryad_manual_oztrait_data_joe_csv",
  datasource = "manual_intake",
  dataowner = NA_character_,
  collection_code = NA_character_,
  trait_name = as.character(raw[[col_trait]]),
  trait_value = as.character(raw[[col_value]]),
  unit = if (!is.na(col_unit)) as.character(raw[[col_unit]]) else rep(NA_character_, nrow(raw)),
  inferred_unit = NA_character_,
  method = NA_character_,
  country = if (!is.na(col_country)) as.character(raw[[col_country]]) else rep(NA_character_, nrow(raw)),
  stateProvince = if (!is.na(col_state)) as.character(raw[[col_state]]) else rep(NA_character_, nrow(raw)),
  county = NA_character_,
  locality = if (!is.na(col_locality)) as.character(raw[[col_locality]]) else rep(NA_character_, nrow(raw)),
  elevation_m = if (!is.na(col_elevation)) as.numeric(raw[[col_elevation]]) else rep(NA_real_, nrow(raw)),
  expected_unit_class = NA_character_,
  value_type = NA_character_,
  standard_unit = NA_character_,
  trait_dictionary_notes = NA_character_,
  dryad_dataset_doi = "doi:10.1111/1365-2745.12518",
  dryad_version_id = NA_character_,
  dryad_file_id = NA_character_,
  source_title = "Spasojevic et al. 2016, J. Ecology",
  source_authors = "Spasojevic et al. 2016",
  source_subjects = "plant functional traits; Ozark forest; intraspecific trait variation",
  source_abstract = "User-supplied OzTrait JoE data for Spasojevic et al. 2016, likely corresponding to the Ozark trait measurements related to functional beta-diversity.",
  download_timestamp_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  source_file_path = source_file,
  original_row_number = seq_len(nrow(raw)),
  raw_taxon = as.character(raw[[col_taxon]]),
  raw_trait_name = as.character(raw[[col_trait]]),
  raw_trait_value = as.character(raw[[col_value]]),
  raw_unit = if (!is.na(col_unit)) as.character(raw[[col_unit]]) else rep(NA_character_, nrow(raw)),
  raw_latitude = if (!is.na(col_lat)) as.character(raw[[col_lat]]) else rep(NA_character_, nrow(raw)),
  raw_longitude = if (!is.na(col_lon)) as.character(raw[[col_lon]]) else rep(NA_character_, nrow(raw)),
  raw_elevation = if (!is.na(col_elevation)) as.character(raw[[col_elevation]]) else rep(NA_character_, nrow(raw)),
  raw_country = if (!is.na(col_country)) as.character(raw[[col_country]]) else rep(NA_character_, nrow(raw)),
  raw_stateProvince = if (!is.na(col_state)) as.character(raw[[col_state]]) else rep(NA_character_, nrow(raw)),
  raw_county = NA_character_,
  raw_locality = if (!is.na(col_locality)) as.character(raw[[col_locality]]) else rep(NA_character_, nrow(raw)),
  raw_date_collected = if (!is.na(col_date)) as.character(raw[[col_date]]) else rep(NA_character_, nrow(raw)),
  input_name_verbatim = as.character(raw[[col_taxon]]),
  source_column_taxon = col_taxon,
  source_column_trait_name = col_trait,
  source_column_trait_value = col_value,
  source_column_unit = if (!is.na(col_unit)) col_unit else NA_character_,
  qa_flags = NA_character_,
  inferred_unit_value = NA_character_,
  inferred_unit_confidence = "none",
  inference_evidence = NA_character_,
  inference_citation_keys = "Spasojevic_2016_JoE_OzTrait",
  basis_type = NA_character_,
  unit_conversion_factor = NA_real_
)

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
  "input_name_verbatim", "source_column_taxon", "source_column_trait_name", "source_column_trait_value", "source_column_unit",
  "qa_flags", "inferred_unit_value", "inferred_unit_confidence",
  "inference_evidence", "inference_citation_keys",
  "basis_type", "unit_conversion_factor"
)

out <- out[, ..final_cols]

out_dir <- file.path(project_root, "output", "providers", "manual_intake", "manual_oztrait_data_joe_csv")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
out_path <- file.path(out_dir, "compiled_trait_observations.csv")
fwrite(out, out_path)

cat("Wrote compiled OzTrait JoE trait table to:\n")
cat("  ", out_path, "\n")
cat("Rows: ", nrow(out), "\n")
