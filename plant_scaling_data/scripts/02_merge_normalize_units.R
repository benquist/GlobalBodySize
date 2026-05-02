# scripts/02_merge_normalize_units.R
# ─────────────────────────────────────────────────────────────────────────────
# PURPOSE:  Step 2 of 6. Load the three parsed source files, reconcile species
#           names to a shared taxonomic backbone, harmonise measurement units,
#           tag provenance, and write a single merged traits file for QA and
#           analysis.
#
# INPUTS:   data/processed/baad_raw.rds
#           data/processed/dryad_raw.rds
#           data/processed/niklas_enquist_raw.rds
#
# OUTPUTS:  data/processed/merged_allometry_traits.rds
#
# KEY CONCEPTS:
#   • Taxonomy reconciliation: the three sources may name the same species
#     differently (synonyms, outdated names, transcription variants). Until a
#     common backbone (e.g. TPL, TNRS, or BIEN's backbone) is applied, each
#     source uses its own names. Any downstream species-mean calculation or
#     PGLS analysis will conflate or miss species if names are not reconciled.
#     reconcile_taxonomy() is the designated hook for this step.
#
#   • Unit harmonisation: allometric scaling tests require all measurements in
#     the same physical units before log-transformation. Common mismatches are:
#       - stem diameter: mm vs cm vs m  → standardise to cm (matches BAAD d.bh × 100)
#       - biomass: g vs kg             → standardise to kg
#       - growth rate: g/yr vs kg/yr   → standardise to kg/yr
#     Mixing units shifts the intercept and can alter the estimated slope in
#     multi-source pooled regressions. normalize_trait_units() is the
#     designated hook for these conversions.
#
#   • Provenance columns (source, source_citation, original_source) are
#     mandatory for any published analysis. They allow reviewers to trace each
#     data point back to its origin, and allow filtering by source for
#     sensitivity checks.
# ─────────────────────────────────────────────────────────────────────────────

library(dplyr)   # data manipulation
library(stringr) # string cleaning (available for use within the helper functions)

# ── Taxonomy reconciliation stub ──────────────────────────────────────────────
# This function should apply a taxonomic name-matching service to map all
# species name variants in 'taxon_column' to a single accepted name. Until
# implemented, the function is a pass-through and names remain as ingested.
# Caveat: downstream PGLS will match species to the phylogeny by exact string.
# Any name not reconciled here that does not match a tree tip label will be
# silently dropped in script 06. Check the match table output of script 05
# before interpreting PGLS sample sizes.
reconcile_taxonomy <- function(df, taxon_column) {
  # TODO: call TNRS, BIEN, or TPL here to map taxon_column to accepted names.
  # Suggested package: taxize::tnrs() or BIEN::BIEN_taxonomy_species()
  df
}

# ── Unit harmonisation stub ───────────────────────────────────────────────────
# This function should detect and convert non-standard measurement units within
# each trait column before sources are row-bound. Key checks to implement:
#   1. Identify any biomass columns in grams (typical BAAD column m.to is in kg).
#   2. Identify any diameter columns in mm (BAAD d.bh is in m; script 04
#      converts d.bh × 100 to cm — verify no double-conversion occurs).
#   3. Check growth rate units against expected kg/yr.
# Caveat: if BAAD and Niklas-Enquist are ever combined in a pooled regression,
# verify that the same trait name maps to the same units in both sources.
normalize_trait_units <- function(df) {
  # TODO: implement per-column unit detection and conversion
  df
}

# ── Helper to load RDS files ──────────────────────────────────────────────────
# Centralised in a function so the file path logic is easy to audit.
load_processed_source <- function(path) {
  readRDS(path)
}

# ── Load source-level data ────────────────────────────────────────────────────
# These are the outputs of script 01. Loading by path (rather than from a
# global environment object) ensures the pipeline is reproducible when run
# non-interactively (e.g. Rscript or Make).
baad          <- load_processed_source("../data/processed/baad_raw.rds")
dryad         <- load_processed_source("../data/processed/dryad_raw.rds")
niklas_enquist <- load_processed_source("../data/processed/niklas_enquist_raw.rds")

# ── Apply taxonomy reconciliation ─────────────────────────────────────────────
# Pass the species column name as a string so the function works generically
# across sources whose taxon column may be named differently (e.g. "species"
# vs "taxa" vs "speciesMatched").
baad_tax    <- reconcile_taxonomy(baad,          "species")
dryad_tax   <- reconcile_taxonomy(dryad,         "species")
niklas_tax  <- reconcile_taxonomy(niklas_enquist, "species")

# ── Normalise measurement units ───────────────────────────────────────────────
# Applied after taxonomy reconciliation so that any filtering done inside
# reconcile_taxonomy (e.g. removing records with ambiguous names) reduces the
# data volume before the more expensive unit-conversion logic runs.
baad_units   <- normalize_trait_units(baad_tax)
dryad_units  <- normalize_trait_units(dryad_tax)
niklas_units <- normalize_trait_units(niklas_tax)

# ── Merge all sources with provenance tag ────────────────────────────────────
# bind_rows() requires matching column names; mismatched names from different
# sources will appear as NA in the combined frame (correct behaviour — they are
# genuinely missing, not zero). The 'source' column is the key provenance field
# for all downstream filtering and sensitivity analyses.
merged_traits <- bind_rows(
  baad_units   %>% mutate(source = "BAAD"),
  dryad_units  %>% mutate(source = "Dryad"),
  niklas_units %>% mutate(source = "Niklas_Enquist_ORNL")
)

# ── Preserve citation and source metadata ─────────────────────────────────────
# source_citation: use the value already in the data if present; fall back to
#   the source label. This enables proper citation attribution per-record in
#   any publication or supplementary table.
# original_source: a stable copy of 'source' that survives any later
#   re-labelling (e.g. if records are re-assigned to sub-datasets).
merged_traits <- merged_traits %>%
  mutate(
    source_citation = coalesce(source_citation, source),
    original_source = source
  )

# ── Save merged file ──────────────────────────────────────────────────────────
# Script 03 reads this file for QA audits; scripts 04–06 read it for analysis.
# Saving as RDS preserves column types; a parallel CSV could be added for
# human inspection but is not currently written here.
saveRDS(merged_traits, "../data/processed/merged_allometry_traits.rds")
