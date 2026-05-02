# scripts/02_merge_normalize_units.R

library(dplyr)
library(stringr)

# Helper placeholders
reconcile_taxonomy <- function(df, taxon_column) {
  # map species names to a common taxonomic backbone
  df
}

normalize_trait_units <- function(df) {
  # convert trait values to common units, e.g. g to kg, mm to m
  df
}

load_processed_source <- function(path) {
  readRDS(path)
}

baad <- load_processed_source("../data/processed/baad_raw.rds")
dryad <- load_processed_source("../data/processed/dryad_raw.rds")
niklas_enquist <- load_processed_source("../data/processed/niklas_enquist_raw.rds")

# Taxonomy reconciliation
baad_tax <- reconcile_taxonomy(baad, "species")
dryad_tax <- reconcile_taxonomy(dryad, "species")
niklas_tax <- reconcile_taxonomy(niklas_enquist, "species")

# Unit harmonization
baad_units <- normalize_trait_units(baad_tax)
dryad_units <- normalize_trait_units(dryad_tax)
niklas_units <- normalize_trait_units(niklas_tax)

# Merge sources with provenance columns
merged_traits <- bind_rows(
  baad_units %>% mutate(source = "BAAD"),
  dryad_units %>% mutate(source = "Dryad"),
  niklas_units %>% mutate(source = "Niklas_Enquist_ORNL")
)

# Preserve citation/source metadata
merged_traits <- merged_traits %>%
  mutate(
    source_citation = coalesce(source_citation, source),
    original_source = source
  )

saveRDS(merged_traits, "../data/processed/merged_allometry_traits.rds")
