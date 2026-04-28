#!/usr/bin/env Rscript
# splot-open-data/R/01_build_bien_staging.R
#
# Reads sPlotOpen header + DT from the zip archive, applies QA filters and
# flags, maps to BIEN staging schema, and writes two output CSVs.
#
# Reference: Sabatini et al. 2021, Global Ecology and Biogeography,
#            doi:10.1111/geb.13346

suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
})

# ── Paths ─────────────────────────────────────────────────────────────────────

ZIP        <- "/Users/brianjenquist/VSCode/splot-open-data/data/iDiv Data Repository_3474_v55__20260429.zip"
OUTPUT_DIR <- "/Users/brianjenquist/VSCode/splot-open-data/output"
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

# ── 1. Load data ──────────────────────────────────────────────────────────────

HEADER_COLS <- c(
  "PlotObservationID", "GIVD_ID", "Dataset", "Continent", "Country",
  "Biome", "Date_of_recording", "Latitude", "Longitude",
  "Location_uncertainty", "Elevation", "Plant_recorded",
  "Resample_1", "Resample_2", "Resample_3", "Resample_1_consensus"
)

DT_COLS <- c(
  "PlotObservationID", "Species", "Original_species",
  "Original_abundance", "Abundance_scale", "Relative_cover"
)

message("[1/8] Loading header file from zip...")
header <- fread(
  cmd        = paste0("unzip -p '", ZIP, "' 'sPlotOpen_header(2).txt'"),
  sep        = "\t",
  na.strings = c("", "NA", "N/A"),
  select     = HEADER_COLS
)
message("  Header rows loaded: ", format(nrow(header), big.mark = ","))

message("[2/8] Loading DT (species×plot) file from zip...")
DT <- fread(
  cmd        = paste0("unzip -p '", ZIP, "' 'sPlotOpen_DT(1).txt'"),
  sep        = "\t",
  na.strings = c("", "NA", "N/A"),
  select     = DT_COLS
)
message("  DT rows loaded: ", format(nrow(DT), big.mark = ","))

# ── 2. Join DT to header ──────────────────────────────────────────────────────

message("[3/8] Joining DT to header on PlotObservationID...")
setkeyv(header, "PlotObservationID")
setkeyv(DT,     "PlotObservationID")
joined <- header[DT, nomatch = 0L]
message("  Rows after inner join: ", format(nrow(joined), big.mark = ","))

# ── 3. Filters and flags ──────────────────────────────────────────────────────

message("[4/8] Applying filters and deriving flags...")

n0 <- nrow(joined)

# Remove rows where Species is NA, blank, or not a binomial (no space)
joined <- joined[!is.na(Species) & Species != "" & grepl(" ", Species, fixed = TRUE)]
message("  After Species filter (must be binomial): ",
        format(nrow(joined), big.mark = ","),
        "  (removed ", format(n0 - nrow(joined), big.mark = ","), ")")

n1 <- nrow(joined)

# Remove rows where Latitude or Longitude is NA
joined <- joined[!is.na(Latitude) & !is.na(Longitude)]
message("  After NA coordinate filter: ",
        format(nrow(joined), big.mark = ","),
        "  (removed ", format(n1 - nrow(joined), big.mark = ","), ")")

# Flag: location uncertainty > 1000 m
joined[, coord_uncertainty_flag := (!is.na(Location_uncertainty) & Location_uncertainty > 1000)]

# Flag: null island (both lat and lon within 0.1° of origin)
joined[, null_island_flag := (abs(Latitude) < 0.1 & abs(Longitude) < 0.1)]

message("  coord_uncertainty_flag == TRUE: ",
        format(sum(joined$coord_uncertainty_flag, na.rm = TRUE), big.mark = ","))
message("  null_island_flag == TRUE:       ",
        format(sum(joined$null_island_flag, na.rm = TRUE), big.mark = ","))

# ── 4. Map to BIEN staging schema ─────────────────────────────────────────────

message("[5/8] Mapping to BIEN staging schema...")

# Parse date
joined[, date_collected := suppressWarnings(ymd(Date_of_recording))]

# Year: prefer parsed date; fall back to leading 4-digit substring
joined[, year_collected := year(date_collected)]
joined[is.na(year_collected),
       year_collected := suppressWarnings(as.integer(substr(as.character(Date_of_recording), 1, 4)))]

# occurrenceID: unique across all rows
joined[, occurrenceID := paste(PlotObservationID, Species, seq_len(.N), sep = "-")]

staging <- joined[, .(
  scrubbed_species_binomial        = Species,
  scrubbed_species_binomial_splot  = Species,
  verbatim_scientific_name         = Original_species,
  latitude                         = Latitude,
  longitude                        = Longitude,
  date_collected                   = as.character(date_collected),
  verbatim_date_collected          = as.character(Date_of_recording),
  year_collected,
  country                          = Country,
  plot_name                        = as.character(PlotObservationID),
  occurrenceID,
  basisOfRecord                    = "HumanObservation",
  dataset                          = "sPlotOpen",
  datasource                       = "iDiv sPlotOpen v2.0",
  dataowner                        = "Sabatini et al. 2021 (GEB)",
  collection_code                  = GIVD_ID,
  verbatim_collection_name         = Dataset,
  verbatimElevation                = as.character(Elevation),
  elevation_min                    = Elevation,
  elevation_max                    = Elevation,
  continent                        = Continent,
  biome                            = Biome,
  plant_recorded                   = Plant_recorded,
  resample_1                       = Resample_1,
  resample_2                       = Resample_2,
  resample_3                       = Resample_3,
  resample_1_consensus             = Resample_1_consensus,
  original_abundance               = Original_abundance,
  abundance_scale                  = Abundance_scale,
  relative_cover                   = Relative_cover,
  coord_uncertainty_flag,
  null_island_flag,
  location_uncertainty_m           = Location_uncertainty
)]

# ── 5. Verify occurrenceID uniqueness ─────────────────────────────────────────

message("[6/8] Verifying occurrenceID uniqueness...")
n_dup <- anyDuplicated(staging$occurrenceID)
if (n_dup != 0L) {
  stop("Duplicate occurrenceID detected at position ", n_dup,
       ". Aborting before writing output.")
}
message("  occurrenceID uniqueness check: PASS")

# ── 6. Write outputs ──────────────────────────────────────────────────────────

message("[7/8] Writing output files...")

full_path     <- file.path(OUTPUT_DIR, "splot_bien_staging_full.csv")
balanced_path <- file.path(OUTPUT_DIR, "splot_bien_staging_balanced.csv")

fwrite(staging, file = full_path, sep = "\t", na = "")
message("  Wrote full staging table: ", full_path)

staging_balanced <- staging[resample_1_consensus == TRUE]
fwrite(staging_balanced, file = balanced_path, sep = "\t", na = "")
message("  Wrote balanced subset:    ", balanced_path)

# ── 7. Summary report ─────────────────────────────────────────────────────────

message("[8/8] Summary report")
message("  Rows — full staging table:          ", format(nrow(staging),          big.mark = ","))
message("  Rows — balanced subset:             ", format(nrow(staging_balanced), big.mark = ","))
message("  Unique species:                     ", format(uniqueN(staging$scrubbed_species_binomial), big.mark = ","))
message("  Unique plots:                       ", format(uniqueN(staging$plot_name), big.mark = ","))
message("  coord_uncertainty_flag == TRUE:     ", format(sum(staging$coord_uncertainty_flag, na.rm = TRUE), big.mark = ","))
message("  null_island_flag == TRUE:           ", format(sum(staging$null_island_flag, na.rm = TRUE), big.mark = ","))
message("  Rows with NA date_collected:        ", format(sum(is.na(staging$date_collected)), big.mark = ","))
message("  Rows with NA latitude:              ", format(sum(is.na(staging$latitude)), big.mark = ","))
message("  Rows with NA longitude:             ", format(sum(is.na(staging$longitude)), big.mark = ","))

# ── Batch chunking note ────────────────────────────────────────────────────────
#
# TNRS / GNRS / NSR taxonomic reconciliation should be run in batches of
# 500–1000 unique species names at a time.  Both TNRS and GNRS enforce strict
# API rate limits; submitting all ~30 000+ unique names in a single request will
# result in timeouts or HTTP 429 errors.
#
# Recommended workflow:
#   1. Extract unique names:
#        names_vec <- unique(staging$scrubbed_species_binomial)
#   2. Split into batches:
#        batches <- split(names_vec, ceiling(seq_along(names_vec) / 500))
#   3. Loop over batches with a polite pause between calls (e.g. Sys.sleep(5)).
#   4. Bind results and join back to the staging table on scrubbed_species_binomial.
#
# For interactive QA, name resolution, and native-status lookup, use the
# BIEN Data Loader app:
#   https://benquist.shinyapps.io/bien-data-loader/
#
# ─────────────────────────────────────────────────────────────────────────────
