#!/usr/bin/env Rscript
# providers/manual_intake/scripts/ingest_manual_trait_source.R
# Map a manual trait ingestion source to the DryadPlantTraits canonical trait schema.

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

args <- commandArgs(trailingOnly = TRUE)
source_arg <- grep("^--source=", args, value = TRUE)
if (!length(source_arg)) {
  cat("Usage: ingest_manual_trait_source.R --source=<source_id>\n")
  cat("Available source_ids:\n")
  cat("  manual_alltraits_phynames_csv\n")
  cat("  manual_oztrait_data_joe_csv\n")
  quit(status = 1)
}
source_id <- sub("^--source=", "", source_arg[[1]])

manifest <- list(
  manual_alltraits_phynames_csv = list(
    file_name = "alltraits with phynames.csv",
    file_type = "csv",
    display_name = "alltraits with phynames.csv",
    source_title = "Spasojevic et al. 2016 Ozark trait data",
    source_authors = "Spasojevic et al. 2016",
    source_abstract = "User-supplied Ozark trait dataset for Spasojevic et al. 2016; may duplicate Dryad doi:10.5061/dryad.rr4pm"
  ),
  manual_oztrait_data_joe_csv = list(
    file_name = "oztrait data JoE.csv",
    file_type = "csv",
    display_name = "oztrait data JoE.csv",
    source_title = "Spasojevic et al. 2016 Ozark trait data",
    source_authors = "Spasojevic et al. 2016",
    source_abstract = "User-supplied Ozark trait dataset for Spasojevic et al. 2016; may duplicate Dryad doi:10.5061/dryad.rr4pm"
  )
)

if (!source_id %in% names(manifest)) {
  stop("Unknown source_id: ", source_id, ". Use --source=manual_alltraits_phynames_csv or --source=manual_oztrait_data_joe_csv")
}

source_spec <- manifest[[source_id]]
source_path <- file.path(project_root, "data", "manual_ingestion", source_spec$file_name)
if (!file.exists(source_path)) {
  stop("Source file not found: ", source_path, call. = FALSE)
}

if (source_spec$file_type == "csv") {
  raw <- tryCatch(fread(source_path, showProgress = FALSE), error = function(e) NULL)
  if (is.null(raw)) stop("Failed to read CSV file: ", source_path, call. = FALSE)
} else {
  stop("Unsupported file type: ", source_spec$file_type)
}

cat("Read raw file:\n")
cat("  source_id: ", source_id, "\n")
cat("  rows: ", nrow(raw), " cols: ", ncol(raw), "\n")
cat("  columns: ", paste(names(raw), collapse = ", "), "\n")

source_column_candidates <- list(
  raw_taxon = c("species", "scientificName", "taxon", "ScientificName", "species_name", "Species"),
  raw_trait_name = c("trait", "trait_name", "Trait", "TraitName", "measurement_name"),
  raw_trait_value = c("value", "trait_value", "TraitValue", "measurement_value", "Value"),
  raw_unit = c("unit", "units", "Unit", "Units"),
  raw_latitude = c("latitude", "lat", "decimalLatitude", "Latitude"),
  raw_longitude = c("longitude", "lon", "decimalLongitude", "Longitude"),
  raw_date_collected = c("date", "eventDate", "collectionDate", "Date", "year", "Year"),
  raw_locality = c("locality", "location", "Location"),
  raw_stateProvince = c("stateProvince", "state", "province", "State"),
  raw_country = c("country", "Country", "countryCode", "country_code")
)

find_column <- function(candidates) {
  for (name in candidates) {
    if (name %in% names(raw)) return(name)
  }
  NA_character_
}

mapped <- data.table(
  scrubbed_species_binomial = NA_character_,
  latitude = NA_real_,
  longitude = NA_real_,
  date_collected = NA_character_,
  dataset = NA_character_,
  datasource = "manual_intake",
  dataowner = NA_character_,
  collection_code = NA_character_,
  trait_name = NA_character_,
  trait_value = NA_character_,
  unit = NA_character_,
  inferred_unit = NA_character_,
  method = NA_character_,
  country = NA_character_,
  stateProvince = NA_character_,
  county = NA_character_,
  locality = NA_character_,
  elevation_m = NA_real_,
  expected_unit_class = NA_character_,
  value_type = NA_character_,
  standard_unit = NA_character_,
  trait_dictionary_notes = NA_character_,
  dryad_dataset_doi = NA_character_,
  dryad_version_id = NA_character_,
  dryad_file_id = NA_character_,
  source_title = source_spec$source_title,
  source_authors = source_spec$source_authors,
  source_subjects = NA_character_,
  source_abstract = source_spec$source_abstract,
  download_timestamp_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  source_file_path = source_path,
  original_row_number = seq_len(nrow(raw)),
  raw_taxon = NA_character_,
  raw_trait_name = NA_character_,
  raw_trait_value = NA_character_,
  raw_unit = NA_character_,
  raw_latitude = NA_character_,
  raw_longitude = NA_character_,
  raw_elevation = NA_character_,
  raw_country = NA_character_,
  raw_stateProvince = NA_character_,
  raw_county = NA_character_,
  raw_locality = NA_character_,
  raw_date_collected = NA_character_,
  input_name_verbatim = NA_character_,
  infraspecific_rank = NA_character_,
  infraspecific_epithet = NA_character_,
  source_column_taxon = NA_character_,
  source_column_trait_name = NA_character_,
  source_column_trait_value = NA_character_,
  source_column_unit = NA_character_,
  qa_flags = NA_character_,
  inferred_unit_value = NA_character_,
  inferred_unit_confidence = "none",
  inference_evidence = NA_character_,
  inference_citation_keys = NA_character_,
  basis_type = NA_character_,
  unit_conversion_factor = NA_real_
)

found_columns <- list()
for (field in names(source_column_candidates)) {
  found_columns[[field]] <- find_column(source_column_candidates[[field]])
}

if (!is.na(found_columns$raw_taxon)) mapped[, scrubbed_species_binomial := as.character(raw[[found_columns$raw_taxon]])]
if (!is.na(found_columns$raw_trait_name)) mapped[, trait_name := as.character(raw[[found_columns$raw_trait_name]])]
if (!is.na(found_columns$raw_trait_value)) mapped[, trait_value := as.character(raw[[found_columns$raw_trait_value]])]
if (!is.na(found_columns$raw_unit)) mapped[, unit := as.character(raw[[found_columns$raw_unit]])]
if (!is.na(found_columns$raw_latitude)) mapped[, latitude := as.numeric(raw[[found_columns$raw_latitude]])]
if (!is.na(found_columns$raw_longitude)) mapped[, longitude := as.numeric(raw[[found_columns$raw_longitude]])]
if (!is.na(found_columns$raw_locality)) mapped[, locality := as.character(raw[[found_columns$raw_locality]])]
if (!is.na(found_columns$raw_stateProvince)) mapped[, stateProvince := as.character(raw[[found_columns$raw_stateProvince]])]
if (!is.na(found_columns$raw_country)) mapped[, country := as.character(raw[[found_columns$raw_country]])]
if (!is.na(found_columns$raw_date_collected)) {
  mapped[, date_collected := as.character(raw[[found_columns$raw_date_collected]])]
}

mapped[, raw_taxon := if (!is.na(found_columns$raw_taxon)) as.character(raw[[found_columns$raw_taxon]]) else NA_character_]
mapped[, raw_trait_name := if (!is.na(found_columns$raw_trait_name)) as.character(raw[[found_columns$raw_trait_name]]) else NA_character_]
mapped[, raw_trait_value := if (!is.na(found_columns$raw_trait_value)) as.character(raw[[found_columns$raw_trait_value]]) else NA_character_]
mapped[, raw_unit := if (!is.na(found_columns$raw_unit)) as.character(raw[[found_columns$raw_unit]]) else NA_character_]
mapped[, raw_latitude := if (!is.na(found_columns$raw_latitude)) as.character(raw[[found_columns$raw_latitude]]) else NA_character_]
mapped[, raw_longitude := if (!is.na(found_columns$raw_longitude)) as.character(raw[[found_columns$raw_longitude]]) else NA_character_]
mapped[, raw_locality := if (!is.na(found_columns$raw_locality)) as.character(raw[[found_columns$raw_locality]]) else NA_character_]
mapped[, raw_stateProvince := if (!is.na(found_columns$raw_stateProvince)) as.character(raw[[found_columns$raw_stateProvince]]) else NA_character_]
mapped[, raw_country := if (!is.na(found_columns$raw_country)) as.character(raw[[found_columns$raw_country]]) else NA_character_]
mapped[, raw_date_collected := if (!is.na(found_columns$raw_date_collected)) as.character(raw[[found_columns$raw_date_collected]]) else NA_character_]

mapped[, input_name_verbatim := scrubbed_species_binomial]

if (all(is.na(mapped$scrubbed_species_binomial))) {
  stop("No taxon column was detected in the source file. Columns found: ", paste(names(raw), collapse = ", "), call. = FALSE)
}
if (all(is.na(mapped$trait_name)) || all(is.na(mapped$trait_value))) {
  stop("No trait name/value columns were detected in the source file. Columns found: ", paste(names(raw), collapse = ", "), call. = FALSE)
}

mapped[, dataset := paste0("dryad_manual_", source_id)]

out_dir <- file.path(project_root, "output", "providers", "manual_intake", source_id)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
out_path <- file.path(out_dir, "compiled_trait_observations.csv")
fwrite(mapped, out_path)

cat("Written compiled trait table:\n")
cat("  ", out_path, "\n")
cat("Rows written: ", nrow(mapped), "\n")
