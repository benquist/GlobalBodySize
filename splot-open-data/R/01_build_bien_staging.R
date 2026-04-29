#!/usr/bin/env Rscript
# splot-open-data/R/01_build_bien_staging.R
#
# Reads sPlotOpen header + DT from the zip archive, applies QA filters and
# flags, maps to BIEN staging schema, and writes two output TSVs.
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
DT[, source_row_index := .I]
message("  DT rows loaded: ", format(nrow(DT), big.mark = ","))

# ── 2. Join DT to header ──────────────────────────────────────────────────────

message("[3/8] Joining DT to header on PlotObservationID...")
setkeyv(header, "PlotObservationID")
setkeyv(DT,     "PlotObservationID")
joined <- header[DT, nomatch = 0L]
joined[, Resample_1_consensus := as.logical(Resample_1_consensus)]
joined[, Resample_1 := as.logical(Resample_1)]
joined[, Resample_2 := as.logical(Resample_2)]
joined[, Resample_3 := as.logical(Resample_3)]
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

staging <- joined[, .(
  scrubbed_species_binomial        = Species,
  scrubbed_species_binomial_splot  = Species,
  tnrs_submitted_name              = Species,
  tnrs_matched_name                = NA_character_,
  tnrs_taxon_id                    = NA_character_,
  tnrs_authority                   = NA_character_,
  tnrs_match_score                 = NA_real_,
  tnrs_match_method                = NA_character_,
  tnrs_name_changed                = as.logical(NA),
  taxon_resolution_status          = "pending_tnrs",
  verbatim_scientific_name         = Original_species,
  latitude                         = Latitude,
  longitude                        = Longitude,
  date_collected                   = as.character(date_collected),
  verbatim_date_collected          = as.character(Date_of_recording),
  year_collected,
  country                          = Country,
  plot_observation_id              = as.character(PlotObservationID),
  source_row_index                 = source_row_index,
  source_archive                   = basename(ZIP),
  plot_name                        = as.character(PlotObservationID),
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

# Heuristic source matching for BIEN plot-source overlap triage.
# This is not definitive deduplication; expected false positives and false
# negatives remain, and flagged rows should be reviewed downstream.
normalize_source_text <- function(x) {
  tolower(trimws(gsub("[^[:alnum:]]+", " ", as.character(x))))
}

# Primary identifiers first (most specific source fields).
source_text_primary <- normalize_source_text(paste(
  staging$verbatim_collection_name,
  staging$collection_code,
  sep = " "
))

# Secondary context only for conservative BIEN-coverage fallback.
source_text_secondary <- normalize_source_text(paste(
  staging$dataset,
  staging$datasource,
  sep = " "
))

# BIEN plot sources from BIEN_plot_list_datasource:
# CTFS, CVS, FIA, gillespie, SALVIAS, TEAM, VegBank.
# Short acronyms require whole-token matches with optional common prefix tokens.
bien_plot_source_patterns <- list(
  CTFS = "\\b(?:usa\\s+)?ctfs\\b",
  CVS = "\\b(?:usa\\s+)?cvs\\b|\\b(?:usa\\s+)?c\\s+v\\s+s\\b",
  FIA = "\\b(?:usa\\s+)?fia\\b",
  gillespie = "\\bgillespie\\b",
  SALVIAS = "\\bsalvias\\b",
  TEAM = "\\b(?:usa\\s+)?team\\b",
  VegBank = "\\b(?:usa\\s+)?veg\\s*bank\\b|\\b(?:usa\\s+)?vegbank\\b"
)

match_on_source <- function(pattern) {
  primary_hit <- grepl(pattern, source_text_primary, perl = TRUE)
  secondary_hit <- grepl(pattern, source_text_secondary, perl = TRUE)
  primary_hit | (!primary_hit & secondary_hit)
}

match_ctfs <- match_on_source(bien_plot_source_patterns$CTFS)
match_cvs <- match_on_source(bien_plot_source_patterns$CVS)
match_fia <- match_on_source(bien_plot_source_patterns$FIA)
match_gillespie <- match_on_source(bien_plot_source_patterns$gillespie)
match_salvias <- match_on_source(bien_plot_source_patterns$SALVIAS)
match_team <- match_on_source(bien_plot_source_patterns$TEAM)
match_vegbank <- match_on_source(bien_plot_source_patterns$VegBank)

# Assign duplicate flags and one deterministic reason per row.
# Precedence is fixed and prioritized per request: SALVIAS, VegBank, CVS,
# then remaining BIEN sources in deterministic order (CTFS, FIA, gillespie, TEAM).
staging[, duplicate_source_in_bien :=
          match_ctfs |
          match_cvs |
          match_fia |
          match_gillespie |
          match_salvias |
          match_team |
          match_vegbank]

staging[, duplicate_source_reason := fifelse(
  match_salvias,
  "source in BIEN: SALVIAS",
  fifelse(
    match_vegbank,
    "source in BIEN: VegBank",
    fifelse(
      match_cvs,
      "source in BIEN: CVS",
      fifelse(
        match_ctfs,
        "source in BIEN: CTFS",
        fifelse(
          match_fia,
          "source in BIEN: FIA",
          fifelse(
            match_gillespie,
            "source in BIEN: gillespie",
            fifelse(
              match_team,
              "source in BIEN: TEAM",
              NA_character_
            )
          )
        )
      )
    )
  )
)]

staging[, occurrenceID := paste(
  plot_observation_id,
  gsub(" +", "_", trimws(scrubbed_species_binomial)),
  source_row_index,
  sep = "-"
)]

unique_names_path <- file.path(OUTPUT_DIR, "splot_unique_names_for_tnrs.tsv")
tnrs_queue <- staging[
  !is.na(scrubbed_species_binomial_splot) & trimws(scrubbed_species_binomial_splot) != "",
  .(n_records = .N),
  by = .(submitted_name = scrubbed_species_binomial_splot)
]
setorder(tnrs_queue, submitted_name)
tnrs_queue[, taxon_resolution_status := "pending_tnrs"]
fwrite(tnrs_queue, file = unique_names_path, sep = "\t", na = "")
message("  Wrote TNRS unique-name queue: ", unique_names_path,
        " (", format(nrow(tnrs_queue), big.mark = ","), " unique names)")

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

full_path     <- file.path(OUTPUT_DIR, "splot_bien_staging_full.tsv")
balanced_path <- file.path(OUTPUT_DIR, "splot_bien_staging_balanced.tsv")

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
message("  Rows pending TNRS resolution:       ", format(sum(staging$taxon_resolution_status == "pending_tnrs", na.rm = TRUE), big.mark = ","))
message("  TNRS queue file:                    ", unique_names_path)
message("  TNRS queue unique names:            ", format(nrow(tnrs_queue), big.mark = ","))
message("  coord_uncertainty_flag == TRUE:     ", format(sum(staging$coord_uncertainty_flag, na.rm = TRUE), big.mark = ","))
message("  null_island_flag == TRUE:           ", format(sum(staging$null_island_flag, na.rm = TRUE), big.mark = ","))
message("  Rows with NA date_collected:        ", format(sum(is.na(staging$date_collected)), big.mark = ","))
message("  Rows with NA latitude:              ", format(sum(is.na(staging$latitude)), big.mark = ","))
message("  Rows with NA longitude:             ", format(sum(is.na(staging$longitude)), big.mark = ","))

message("  Duplicate rows flagged (BIEN plot sources): ",
        format(sum(staging$duplicate_source_in_bien, na.rm = TRUE), big.mark = ","))
duplicate_reason_counts <- staging[duplicate_source_in_bien == TRUE,
                                   .N,
                                   by = duplicate_source_reason][order(duplicate_source_reason)]
if (nrow(duplicate_reason_counts) > 0L) {
  message("  Duplicate rows by reason:")
  for (i in seq_len(nrow(duplicate_reason_counts))) {
    message("    ", duplicate_reason_counts$duplicate_source_reason[i],
            ": ", format(duplicate_reason_counts$N[i], big.mark = ","))
  }
} else {
  message("  Duplicate rows by reason: none flagged")
}

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
