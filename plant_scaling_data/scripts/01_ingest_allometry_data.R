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
  # read ORNL/Niklas-Enquist source files
  tibble()
}

# Standardize names across sources
normalize_column_names <- function(df) {
  df %>% rename_with(~ tolower(gsub("[ .-]", "_", .x)))
}

# Ingest step
baad_raw <- load_baad_data(file.path(raw_dir, "baad")) %>% normalize_column_names()
dryad_raw <- load_dryad_data(file.path(raw_dir, "dryad")) %>% normalize_column_names()
orkl_raw <- load_niklas_enquist_data(file.path(raw_dir, "niklas_enquist")) %>% normalize_column_names()

# TODO: add source identification and initial cleaning

# Save prepared source-level data for downstream merge
saveRDS(baad_raw, "../data/processed/baad_raw.rds")
saveRDS(dryad_raw, "../data/processed/dryad_raw.rds")
saveRDS(orkl_raw, "../data/processed/niklas_enquist_raw.rds")
