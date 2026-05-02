# scripts/01_ingest_allometry_data.R
# ─────────────────────────────────────────────────────────────────────────────
# PURPOSE:  Step 1 of 6. Read raw allometric data files from three primary
#           sources, apply source-specific parsing logic, standardise column
#           names, and write source-level RDS files for downstream processing.
#
# INPUTS:   data/raw/baad/                      — BAAD directory (placeholder)
#           data/raw/dryad/                     — Dryad files (placeholder)
#           data/raw/niklas_enquist/
#             niklas_enquist_biomass_20040122.csv
#
# OUTPUTS:  data/processed/baad_raw.rds
#           data/processed/dryad_raw.rds
#           data/processed/niklas_enquist_raw.rds
#
# KEY CONCEPTS:
#   • BAAD (Biomass And Allometry Database, Falster et al. 2015 Ecology 96:1445)
#     is a curated multi-study compilation of plant structural measurements
#     (DBH, height, above-ground biomass) drawn from published studies globally.
#   • The Niklas-Enquist ORNL dataset (Niklas & Enquist 2004 PNAS) compiles
#     cross-taxa individual-level measurements of biomass compartments and
#     growth rates spanning multiple plant functional types and size classes.
#     It is one of the broadest empirical bases for WBE / MST allometry tests.
#   • Allometric scaling analyses require measurements in consistent physical
#     units (kg, m, kg/yr). Any unit mismatch propagates as a systematic slope
#     bias; unit normalisation is therefore a mandatory early step.
# ─────────────────────────────────────────────────────────────────────────────

# Load packages
library(readr)  # fast, type-safe CSV parsing
library(dplyr)  # tidy data wrangling

# ── File-path constants ───────────────────────────────────────────────────────
# All raw source data lives under data/raw/. Using a single variable keeps
# paths consistent if the directory is ever relocated.
raw_dir <- "../data/raw"

# ── Source-specific ingest functions ─────────────────────────────────────────
# Each function encapsulates the quirks of a single data source. Keeping them
# separate makes it easy to swap in a real reader when new raw files arrive
# without touching the rest of the pipeline.

load_baad_data <- function(path) {
  # Placeholder: the live pipeline will call baad.data::baad_data() or read
  # pre-downloaded CSV files from the BAAD repository. Returns an empty tibble
  # until source files are confirmed present, so the pipeline does not fail
  # during initial setup. See script 04 for the production BAAD ingest.
  tibble()
}

load_dryad_data <- function(path) {
  # Placeholder for one or more Dryad-hosted datasets. Multiple Dryad deposits
  # may contribute — each may have different column structures and units,
  # requiring individual parsing rules before they can be row-bound.
  tibble()
}

load_niklas_enquist_data <- function(path) {
  # ── Parsing logic for the Niklas-Enquist ORNL CSV ──
  # The file has a two-row header:
  #   Row 1: semantic variable names (e.g. "Height (m)")
  #   Row 2: unit descriptions (e.g. "metres") — not data, must be skipped
  # skip = 2 tells readr to discard both header rows; col_names then provides
  # clean, R-safe names that the rest of the pipeline depends on.
  dat <- readr::read_csv(path, skip = 2,
    col_names = c(
      "taxa", "citation", "footnotes", "record_num",
      "age_yr", "log_age",                              # plant age
      "height_m", "log_height",                         # total plant height (m)
      "root_biomass_kg", "log_root",                    # below-ground biomass (kg)
      "stem_biomass_kg", "log_stem",                    # stem/trunk biomass (kg)
      "leaf_biomass_kg", "log_leaf",                    # leaf biomass (kg)
      "shoot_biomass_kg", "log_shoot",                  # shoot = stem + leaf
      "repro_biomass_kg", "log_repro",                  # reproductive tissue (kg)
      "total_biomass_kg", "log_total",                  # whole-plant biomass (kg)
      "stem_growth_kgyr", "log_stem_growth",            # annual stem biomass increment
      "leaf_growth_kgyr", "log_leaf_growth",            # annual leaf biomass increment
      "root_growth_kgyr", "log_root_growth",            # annual root biomass increment
      "total_growth_kgyr", "log_total_growth"           # total annual biomass increment
    ),
    show_col_types = FALSE, skip_empty_rows = TRUE)

  # The file encodes missing data with the sentinel value -999 (a common
  # convention in legacy ecological databases). Replace -999 with NA_real_
  # AFTER coercing to numeric, so that downstream statistics ignore them
  # cleanly. Non-numeric text columns (taxa, citation, footnotes) are excluded
  # from coercion to avoid corrupting species names.
  dat <- dat |>
    dplyr::mutate(dplyr::across(-c(taxa, citation, footnotes), as.numeric)) |>
    dplyr::mutate(dplyr::across(where(is.numeric), ~ ifelse(. == -999, NA_real_, .)))

  # Caveat: the log10 columns provided in the original file are retained here
  # as a cross-check but are not used as the primary values in later scripts.
  # All log-transformations in the analysis are recomputed from raw values to
  # ensure consistency with unit normalisation applied in script 02.
  dat
}

# ── Column-name standardisation ───────────────────────────────────────────────
# Different sources use different naming conventions (spaces, dots, mixed case).
# Converting all names to lowercase_with_underscores ensures that bind_rows()
# in script 02 aligns matching variables correctly.
normalize_column_names <- function(df) {
  df %>% rename_with(~ tolower(gsub("[ .-]", "_", .x)))
}

# ── Ingest and normalise all sources ─────────────────────────────────────────
# Each call reads from raw_dir, applies source-specific parsing, then
# standardises names before saving. The saved RDS files are the canonical
# entry point for all downstream scripts; raw files should not be read again.
baad_raw  <- load_baad_data(file.path(raw_dir, "baad"))       %>% normalize_column_names()
dryad_raw <- load_dryad_data(file.path(raw_dir, "dryad"))     %>% normalize_column_names()
orkl_raw  <- load_niklas_enquist_data(
  file.path(raw_dir, "niklas_enquist", "niklas_enquist_biomass_20040122.csv")
) |> normalize_column_names()

# ── Save source-level parsed data ─────────────────────────────────────────────
# RDS format preserves column types (especially factor levels and NA types)
# without the ambiguity inherent in CSV round-trips. These files are inputs
# to script 02 (merge and unit normalisation).
saveRDS(baad_raw,  "../data/processed/baad_raw.rds")
saveRDS(dryad_raw, "../data/processed/dryad_raw.rds")
saveRDS(orkl_raw,  "../data/processed/niklas_enquist_raw.rds")
