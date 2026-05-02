# scripts/01_ingest_allometry_data.R

# Load packages
library(readr)
library(dplyr)

# Define data paths
raw_dir <- "../data/raw"

# Placeholder import functions for each source
load_baad_data <- function(path) {
  # read source files from BAAD
  tibble()
}

load_dryad_data <- function(path) {
  # read Dryad dataset files and metadata
  tibble()
}

load_niklas_enquist_data <- function(path) {
  # Row 1: semantic variable names (used as column header by the CSV)
  # Row 2: unit description text — skipped via skip=2
  # Sentinel value -999 encodes missing data throughout
  dat <- readr::read_csv(path, skip = 2,
    col_names = c(
      "taxa", "citation", "footnotes", "record_num",
      "age_yr", "log_age", "height_m", "log_height",
      "root_biomass_kg", "log_root", "stem_biomass_kg", "log_stem",
      "leaf_biomass_kg", "log_leaf", "shoot_biomass_kg", "log_shoot",
      "repro_biomass_kg", "log_repro", "total_biomass_kg", "log_total",
      "stem_growth_kgyr", "log_stem_growth", "leaf_growth_kgyr", "log_leaf_growth",
      "root_growth_kgyr", "log_root_growth", "total_growth_kgyr", "log_total_growth"
    ),
    show_col_types = FALSE, skip_empty_rows = TRUE)

  # Coerce numeric columns and replace -999 sentinel with NA
  dat <- dat |>
    dplyr::mutate(dplyr::across(-c(taxa, citation, footnotes), as.numeric)) |>
    dplyr::mutate(dplyr::across(where(is.numeric), ~ ifelse(. == -999, NA_real_, .)))

  dat
}

# Standardize names across sources
normalize_column_names <- function(df) {
  df %>% rename_with(~ tolower(gsub("[ .-]", "_", .x)))
}

# Ingest step
baad_raw <- load_baad_data(file.path(raw_dir, "baad")) %>% normalize_column_names()
dryad_raw <- load_dryad_data(file.path(raw_dir, "dryad")) %>% normalize_column_names()
orkl_raw <- load_niklas_enquist_data(
  file.path(raw_dir, "niklas_enquist", "niklas_enquist_biomass_20040122.csv")
) |> normalize_column_names()

# TODO: add source identification and initial cleaning

# Save prepared source-level data for downstream merge
saveRDS(baad_raw, "../data/processed/baad_raw.rds")
saveRDS(dryad_raw, "../data/processed/dryad_raw.rds")
saveRDS(orkl_raw, "../data/processed/niklas_enquist_raw.rds")
