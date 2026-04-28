# =============================================================================
# R/utils.R
# Purpose : Shared utility functions used throughout the random_BIEN_species
#           pipeline. These are "infrastructure" helpers — they handle config
#           loading, logging, directory setup, and the fragile task of mapping
#           inconsistent column names from different data sources to a single
#           canonical schema.
#
# Ecological context (for coders learning this workflow):
#   Biodiversity databases — including BIEN — return occurrence data with
#   varying column name conventions (e.g., "decimalLatitude" in Darwin Core vs.
#   "latitude" in BIEN's native output). The normalization functions here ensure
#   the rest of the pipeline always sees consistent column names regardless of
#   which version of BIEN or which API endpoint returned the data.
#
# Data standard referenced:
#   Darwin Core (DwC) — the global standard for biodiversity occurrence data.
#   See: https://dwc.tdwg.org/terms/
# =============================================================================


# --------------------------------------------------------------------------- #
# Null-coalescing operator
#
# Usage : x %||% y
# Returns x if x is non-NULL and non-empty; otherwise returns y.
# This pattern is common in R pipelines when config values may be absent.
# Example: cfg$min_records %||% 50   # use 50 if the config key is missing
# --------------------------------------------------------------------------- #
`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) y else x
}


# --------------------------------------------------------------------------- #
# Timestamped console logger
#
# Usage : log_info("Querying BIEN for: ", species_name)
# Prints a message prefixed with UTC timestamp so you can track pipeline
# progress and benchmark slow steps (e.g., remote BIEN API calls).
# --------------------------------------------------------------------------- #
log_info <- function(...) {
  msg <- paste0(...)
  cat(sprintf("[%s] %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), msg))
}


# --------------------------------------------------------------------------- #
# Directory creation helper
#
# Usage : ensure_directory("outputs/worldclim_cache")
# Creates a directory (and any missing parent dirs) if it does not already
# exist. Returns the path invisibly so it can be piped or used inline.
# Using showWarnings = FALSE avoids noisy messages when the dir already exists.
# --------------------------------------------------------------------------- #
ensure_directory <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
  invisible(path)
}


# --------------------------------------------------------------------------- #
# Config reader
#
# Usage : cfg <- read_config("config.yml")
# Reads the YAML config file and fills in safe defaults for any missing keys.
# All pipeline parameters (seed, QA thresholds, WorldClim resolution, etc.)
# are centralized in config.yml so results are fully reproducible by others
# who receive only the config and this codebase.
#
# Key parameters and their ecological meaning:
#   seed              : Integer random seed — set this to reproduce the exact
#                       same random species draw on any machine.
#   min_records       : Minimum number of clean occurrence records required
#                       before a species is considered eligible for analysis.
#                       Too few records produce an unreliable climate niche
#                       estimate. A threshold of 50–100 is typical for coarse
#                       niche characterization (see Hernandez et al. 2006,
#                       Ecography 29:485-496, https://doi.org/10.1111/j.2006.0906-7590.04350.x).
#   max_random_attempts : How many species draws are tried before giving up.
#   candidate_pool_size : How many species are sampled from BIEN taxonomy to
#                         form the draw pool. A larger pool reduces the chance
#                         of exhausting all candidates.
#   occurrence_limit  : Cap on records downloaded per species from BIEN.
#                       Prevents very common species (e.g., Zea mays) from
#                       consuming excessive memory and API time.
#   worldclim_res     : WorldClim raster resolution in arc-minutes.
#                       Options: 10 (coarse, ~18 km), 5, 2.5, 0.5 (fine).
#                       10 arc-min is sufficient for continental-scale niche
#                       summaries but inappropriate for fine-scale local work.
#   bio_vars          : Which WorldClim BIO layers to use. BIO1 = annual mean
#                       temperature (°C × 10); BIO12 = annual precipitation
#                       (mm/year). These are the two most commonly used axes
#                       in climate-niche studies.
# --------------------------------------------------------------------------- #
read_config <- function(path = "config.yml") {
  if (!file.exists(path)) {
    stop("Config file not found: ", path)
  }
  cfg <- yaml::read_yaml(path)

  # Apply safe defaults so the pipeline never crashes on a missing key
  if (is.null(cfg$seed))                cfg$seed               <- 1
  if (is.null(cfg$min_records))         cfg$min_records        <- 50
  if (is.null(cfg$max_random_attempts)) cfg$max_random_attempts <- 10
  if (is.null(cfg$candidate_pool_size)) cfg$candidate_pool_size <- 200
  if (is.null(cfg$occurrence_limit))    cfg$occurrence_limit   <- 10000
  if (is.null(cfg$worldclim_res))       cfg$worldclim_res      <- 10
  if (is.null(cfg$bio_vars))            cfg$bio_vars           <- c(1, 12)
  if (is.null(cfg$plot))                cfg$plot               <- list(bins = 40, width = 8, height = 6, dpi = 300)
  cfg
}


# --------------------------------------------------------------------------- #
# Column name resolver (internal helper)
#
# Usage : col <- find_first_col(df, c("latitude", "decimalLatitude", "lat"))
# Returns the name of the first column in `df` whose name (case-insensitive)
# matches any entry in `candidates`. Returns NULL if no match is found.
#
# Why this is needed: BIEN, GBIF, iNaturalist, and legacy herbarium exports
# all use slightly different column names for the same concept. Rather than
# hard-coding one name, we check a ranked list of synonyms so the pipeline
# remains robust when the upstream API changes its output schema.
# --------------------------------------------------------------------------- #
find_first_col <- function(df, candidates) {
  idx <- which(tolower(names(df)) %in% tolower(candidates))
  if (length(idx) == 0) return(NULL)
  names(df)[idx[1]]   # return the first match (priority follows candidates order)
}


# --------------------------------------------------------------------------- #
# Occurrence column normalizer
#
# Usage : occ <- normalize_occurrence_columns(raw_bien_df)
#
# Converts whatever column names BIEN returned into the canonical three-column
# schema used by the rest of this pipeline:
#   accepted_binomial : scrubbed/accepted species name (binomial, Genus species)
#   latitude          : decimal degrees, WGS84, -90 to +90
#   longitude         : decimal degrees, WGS84, -180 to +180
#
# Any additional columns in the input are retained (they may be useful for
# provenance or downstream filtering).
#
# Coordinate system note:
#   All coordinates are assumed to be in WGS84 (EPSG:4326), which is the
#   default for BIEN, GBIF, and most biodiversity databases. Do not apply this
#   function to data in projected coordinate systems (UTM, etc.) without first
#   re-projecting to geographic coordinates.
# --------------------------------------------------------------------------- #
normalize_occurrence_columns <- function(df) {
  if (!is.data.frame(df)) {
    stop("Expected a data.frame for occurrence records")
  }

  # Search for species name column using ranked synonym list
  sp_col <- find_first_col(df, c(
    "scrubbed_species_binomial", "species", "species_name", "scientific_name",
    "scientificName", "accepted_binomial", "taxon"
  ))
  # Search for latitude using DwC and common variants
  lat_col <- find_first_col(df, c("latitude", "decimalLatitude", "lat", "scrubbed_latitude"))
  # Search for longitude using DwC and common variants
  lon_col <- find_first_col(df, c("longitude", "decimalLongitude", "lon", "long", "scrubbed_longitude"))

  if (is.null(sp_col) || is.null(lat_col) || is.null(lon_col)) {
    stop(
      "Could not identify required columns. Found names: ",
      paste(names(df), collapse = ", ")
    )
  }

  # Build the standardized output data frame with canonical column names
  out <- data.frame(
    accepted_binomial = as.character(df[[sp_col]]),
    latitude  = suppressWarnings(as.numeric(df[[lat_col]])),   # coerce to numeric; non-parseable → NA
    longitude = suppressWarnings(as.numeric(df[[lon_col]])),
    stringsAsFactors = FALSE
  )

  # Append all remaining original columns (drop the three we just renamed)
  keep <- setdiff(names(df), c(sp_col, lat_col, lon_col))
  if (length(keep) > 0) {
    out <- cbind(out, df[keep], stringsAsFactors = FALSE)
  }
  out
}


# --------------------------------------------------------------------------- #
# CSV writer wrapper
#
# Usage : write_csv(df, "outputs/my_file.csv")
# Writes a data frame to disk with row.names = FALSE (cleaner output) and
# na = "" (empty string for missing values, more readable than "NA" in CSV).
# Returns the path invisibly.
# --------------------------------------------------------------------------- #
write_csv <- function(df, path) {
  utils::write.csv(df, path, row.names = FALSE, na = "")
  invisible(path)
}
