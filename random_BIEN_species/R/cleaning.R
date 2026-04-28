# =============================================================================
# R/cleaning.R
# Purpose : Quality-assurance (QA) filtering of raw BIEN occurrence records.
#           This is the most ecologically critical step in the pipeline: every
#           filter decision affects which records are retained and therefore
#           which part of the realized climate niche is characterized.
#
# Ecological context (ecology-user Steps 3 & 7):
#   Occurrence records from biodiversity databases contain many error types:
#     - Missing or non-parseable coordinates (coordinates stored as text, NA)
#     - Out-of-bounds coordinates (typos producing lat > 90 or lon > 180)
#     - Exact duplicates (same species + coordinates from repeated imports)
#     - Missing species names (genus-level or unidentified records)
#   These errors, if unchecked, produce erroneous climate extractions (e.g.,
#   a record at lat = 999 would return NA from the raster; a duplicate inflates
#   apparent occurrence density in one climate region).
#
# What this pipeline does NOT filter (known limitations):
#   - Coordinate precision: low-precision herbarium points (county centroids)
#     are retained. They contribute noise to the climate-niche plot.
#   - Institutional coordinates: records georeferenced to museum/herbarium
#     locations are NOT flagged. Use CoordinateCleaner for this in production
#     workflows (Zizka et al. 2019, https://doi.org/10.1111/2041-210X.13152).
#   - Temporal outliers: records from very early collection years (pre-1900)
#     may reflect pre-anthropogenic distributions; no temporal filter applied.
#   - Cultivated records: if `cultivated = TRUE` was used in fetch_occurrences(),
#     garden and plantation records are included, which can extend the apparent
#     climate niche beyond the species' native range.
#
# Audit trail:
#   The function returns a qa_summary data frame that logs how many records
#   were dropped at each step. This is essential for transparency — reviewers
#   and collaborators can see exactly where record loss occurred. The summary
#   is written to outputs/qa_summary.csv by run_pipeline.R.
# =============================================================================


# --------------------------------------------------------------------------- #
# QA occurrence cleaner
#
# Usage  : result <- qa_clean_occurrences(raw_occurrences)
# Input  : raw_occurrences — data.frame as returned by fetch_occurrences()
#          (any column name schema; normalize_occurrence_columns() is called
#          internally to standardize names)
# Output : a named list with two elements:
#            $data       — filtered data.frame ready for climate extraction
#            $qa_summary — data.frame with one row per filter step showing
#                          how many records remained after each filter
#
# Filter steps applied in order:
#   1. drop_missing_binomial
#      Removes rows where the species name is NA or blank. We cannot assign
#      an occurrence to a species without a name.
#
#   2. drop_missing_invalid_coordinates
#      Removes rows where latitude or longitude is NA, Inf, or NaN.
#      suppressWarnings() in normalize_occurrence_columns() coerces text
#      coordinates to NA, so this step catches those.
#
#   3. drop_out_of_bounds_coordinates
#      Removes rows where latitude is outside [-90, 90] or longitude is
#      outside [-180, 180]. These are physically impossible geographic
#      coordinates and indicate data entry errors.
#
#   4. drop_exact_species_lat_lon_duplicates
#      Removes rows with identical (species, lat, lon) combinations. Exact
#      duplicates arise from multiple BIEN imports of the same herbarium
#      specimen or from repeated API calls with overlapping date ranges.
#      Note: near-duplicates (same location ± 0.0001°) are NOT removed.
# --------------------------------------------------------------------------- #
qa_clean_occurrences <- function(raw_occurrences) {

  # Standardize column names to accepted_binomial / latitude / longitude
  occ <- normalize_occurrence_columns(raw_occurrences)

  n0 <- nrow(occ)   # baseline count before any filtering

  # Step 1: Remove records with missing or empty species name
  keep_name <- !is.na(occ$accepted_binomial) & nzchar(trimws(occ$accepted_binomial))
  occ1 <- occ[keep_name, , drop = FALSE]

  # Step 2: Remove records where lat or lon is not a finite number
  # is.finite() returns FALSE for NA, Inf, NaN — all invalid for spatial use
  keep_coord <- is.finite(occ1$latitude) & is.finite(occ1$longitude)
  occ2 <- occ1[keep_coord, , drop = FALSE]

  # Step 3: Remove physically impossible coordinates
  # WGS84 bounds: latitude in [-90, 90], longitude in [-180, 180]
  keep_range <- occ2$latitude  >= -90  & occ2$latitude  <= 90 &
                occ2$longitude >= -180 & occ2$longitude <= 180
  occ3 <- occ2[keep_range, , drop = FALSE]

  # Step 4: Remove exact (species × lat × lon) duplicates
  # paste() creates a composite key; duplicated() returns TRUE for all
  # occurrences of a key after the first
  dup_idx <- duplicated(paste(occ3$accepted_binomial, occ3$latitude, occ3$longitude, sep = "|"))
  occ4 <- occ3[!dup_idx, , drop = FALSE]

  # Build the audit trail — one row per filter step
  # n_dropped is computed as the difference between consecutive n_remaining
  # values (negative diff = records lost, so multiply by -1)
  qa_summary <- data.frame(
    step = c(
      "raw_input",
      "drop_missing_binomial",
      "drop_missing_invalid_coordinates",
      "drop_out_of_bounds_coordinates",
      "drop_exact_species_lat_lon_duplicates"
    ),
    n_remaining = c(n0, nrow(occ1), nrow(occ2), nrow(occ3), nrow(occ4)),
    stringsAsFactors = FALSE
  )
  qa_summary$n_dropped <- c(0, diff(c(n0, qa_summary$n_remaining[-1])) * -1)

  list(
    data       = occ4,
    qa_summary = qa_summary
  )
}
