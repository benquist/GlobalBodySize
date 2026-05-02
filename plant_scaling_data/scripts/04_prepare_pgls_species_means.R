# scripts/04_prepare_pgls_species_means.R
# ─────────────────────────────────────────────────────────────────────────────
# PURPOSE:  Step 4 of 6. Collapse individual-level records to species-level
#           means (on the log10 scale) for both the Niklas-Enquist and BAAD
#           datasets. Species means are the unit of analysis for PGLS, because
#           PGLS treats each species as a single tip in the phylogeny.
#
# INPUTS:   data/raw/niklas_enquist/niklas_enquist_biomass_20040122.csv
#             (re-ingested here directly; does not depend on script 01 output)
#           baad.data R package  (installed; call baad.data::baad_data())
#
# OUTPUTS:  data/processed/ne_species_means.rds  / .csv
#           data/processed/baad_species_means.rds / .csv
#
# KEY CONCEPTS:
#   • Why species means for PGLS?
#     Phylogenetic comparative methods model trait evolution across the tips of
#     a phylogeny. Each tip represents one species, so multiple observations
#     from the same species must be aggregated first. Using individual records
#     directly would pseudoreplicate within species and violate the PGLS
#     assumption of one data point per tip.
#
#   • Why log10 before averaging?
#     Allometric relationships are power laws: Y = a · X^b. In log space this
#     becomes log Y = log a + b · log X, which is linear. Because the log scale
#     is the appropriate measurement scale for allometric data (variance is
#     proportional to the mean on the raw scale), averaging within a species
#     should be done on log-transformed values. Averaging raw values and then
#     log-transforming (log of mean ≠ mean of log) would introduce Jensen's
#     inequality bias.
#
#   • Singleton flag: species represented by only one individual cannot
#     contribute meaningful within-species variance information. The flag is
#     retained for sensitivity analyses (e.g. re-run PGLS excluding singletons
#     to check if slopes change).
#
#   • BAAD diameter units: BAAD stores stem diameter at breast height in metres
#     (column d.bh). The analysis uses centimetres for DBH (the convention in
#     most forest allometry literature), so DBH_cm = d.bh × 100.
# ─────────────────────────────────────────────────────────────────────────────

library(readr)      # CSV parsing
library(dplyr)      # data wrangling
library(stringr)    # string operations (available for use)
library(baad.data)  # BAAD database R package (Falster et al. 2015 Ecology)

# proj_dir: the working directory where scripts/ and data/ are co-located.
# normalizePath(".") resolves symlinks and returns an absolute path, which
# avoids breakage when the script is run from different working directories.
proj_dir <- normalizePath(".")

# Ensure the output directory exists before any write calls.
dir.create(file.path(proj_dir, "data/processed"), showWarnings = FALSE, recursive = TRUE)

# ── SECTION A: Niklas-Enquist ─────────────────────────────────────────────────
# This section re-reads the raw Niklas-Enquist CSV rather than using the RDS
# produced in script 01. This makes script 04 self-contained and runnable
# independently, which is useful when only the species-means step needs to be
# re-executed (e.g. after adjusting filters).

ne_raw <- read_csv(
  file.path(proj_dir, "data/raw/niklas_enquist/niklas_enquist_biomass_20040122.csv"),
  skip = 2,
  # Column names match the semantic variables in the Niklas-Enquist dataset.
  # See script 01 for the full rationale for skip=2 and the name assignments.
  col_names = c(
    "taxa", "citation", "footnotes", "record_num",
    "age_yr", "log_age", "height_m", "log_height",
    "root_biomass_kg", "log_root", "stem_biomass_kg", "log_stem",
    "leaf_biomass_kg", "log_leaf", "shoot_biomass_kg", "log_shoot",
    "repro_biomass_kg", "log_repro", "total_biomass_kg", "log_total",
    "stem_growth_kgyr", "log_stem_growth", "leaf_growth_kgyr", "log_leaf_growth",
    "root_growth_kgyr", "log_root_growth", "total_growth_kgyr", "log_total_growth"
  ),
  # latin1 encoding handles any accented characters in taxon names or citations.
  locale = locale(encoding = "latin1"),
  show_col_types = FALSE
)

# Coerce all measurement columns to numeric, suppressing warnings for rows
# that contain non-numeric text (e.g. headers or footnote lines not caught
# by skip=2). suppressWarnings() prevents noise in batch runs; actual parsing
# failures become NA and are handled by the filter below.
# Replace sentinel -999 with NA. This sentinel is a legacy convention; treating
# it as a real value would introduce large negative log10 values and catastrophic
# slope distortion.
ne_raw <- ne_raw |>
  mutate(across(-c(taxa, citation, footnotes), ~ suppressWarnings(as.numeric(.x)))) |>
  mutate(across(where(is.numeric), ~ ifelse(. == -999, NA_real_, .)))

# ── Filter to valid, species-level records ────────────────────────────────────
# Filter criteria and their scientific rationale:
#   1. !is.na(taxa): removes blank rows and summary/aggregate rows.
#   2. grepl("^[A-Z][a-z]+ [a-z]", taxa): retains only binomial species names
#      (Genus species). Filters out family-level rows, aggregate groups like
#      "Angiosperms", and any header text. This is essential because PGLS
#      requires species-level phylogenetic matching.
#   3. height_m > 0 and total_biomass_kg > 0: required for log-transformation.
#      Zero or negative values cannot be log-transformed and indicate missing
#      or erroneous data.
#   4. The regex strip at the end removes footnote markers like "[a]" appended
#      to some taxon names. These prevent exact matching against tree tip labels.
ne_filtered <- ne_raw |>
  filter(
    !is.na(taxa),
    grepl("^[A-Z][a-z]+ [a-z]", taxa), # binomial check
    !is.na(height_m),         height_m > 0,
    !is.na(total_biomass_kg), total_biomass_kg > 0
  ) |>
  mutate(taxa = gsub("\\s*\\[[a-z]\\]$", "", trimws(taxa))) # strip footnote markers

# ── Compute species-level log10 means ─────────────────────────────────────────
# For each species (group_by taxa), compute the arithmetic mean of log10 values
# across all individual records. The inner positive guard (e.g. stem_biomass_kg > 0)
# is applied within the log10 call rather than in the filter above, because
# some biomass compartments may be NA for some individuals even when height and
# total biomass are valid. This avoids dropping records that are useful for
# height and total biomass regressions just because stem biomass was not measured.
ne_species_means <- ne_filtered |>
  group_by(taxa) |>
  summarise(
    # log10(height_m): used in H~AGB and H~DBH regressions.
    # WBE predicts H ~ DBH^(2/3); equivalently AGB ~ H^(8/3) if trunk is isometric.
    log_height_m         = mean(log10(height_m[height_m > 0]),                   na.rm = TRUE),
    # log10(total_biomass_kg): whole-plant above+below-ground biomass.
    # Used as proxy for M in the MST metabolic rate ~ M^(3/4) relationship.
    log_total_biomass_kg = mean(log10(total_biomass_kg[total_biomass_kg > 0]),   na.rm = TRUE),
    # log10 of individual biomass compartments: used to test organ-level
    # scaling (e.g. leaf mass ~ total mass^(3/4) under pipe model assumptions).
    log_stem_biomass_kg  = mean(log10(stem_biomass_kg[!is.na(stem_biomass_kg) & stem_biomass_kg > 0]), na.rm = TRUE),
    log_leaf_biomass_kg  = mean(log10(leaf_biomass_kg[!is.na(leaf_biomass_kg) & leaf_biomass_kg > 0]), na.rm = TRUE),
    log_root_biomass_kg  = mean(log10(root_biomass_kg[!is.na(root_biomass_kg) & root_biomass_kg > 0]), na.rm = TRUE),
    # log10(total_growth_kgyr): annual biomass increment.
    # MST predicts growth rate ~ M^(3/4); WBE predicts ΔAGB ~ AGB^(3/4).
    log_total_growth_kgyr = mean(log10(total_growth_kgyr[!is.na(total_growth_kgyr) & total_growth_kgyr > 0]), na.rm = TRUE),
    n_obs = n(),       # number of individual records contributing to this species mean
    .groups = "drop"
  ) |>
  mutate(
    # singleton: TRUE if only one individual was available for this species.
    # PGLS is robust to this, but slopes estimated from singleton-only species
    # should be interpreted with caution — the "mean" is just one observation.
    singleton = (n_obs == 1L),
    genus     = gsub("\\s.*", "", taxa)  # extract genus for tree-matching diagnostics
  ) |>
  select(taxa, genus, log_height_m, log_total_biomass_kg, log_stem_biomass_kg,
         log_leaf_biomass_kg, log_root_biomass_kg, log_total_growth_kgyr,
         n_obs, singleton)

# ── SECTION B: BAAD ───────────────────────────────────────────────────────────
# BAAD (Biomass And Allometry Database, Falster et al. 2015) provides curated,
# quality-checked plant structural measurements from >170 studies. Unlike the
# Niklas-Enquist dataset, BAAD records are predominantly woody plants measured
# in the field, so the size range and taxonomic composition differ.

# baad.data::baad_data() returns a list; $data is the main data frame.
# Column meanings relevant here:
#   speciesMatched — taxonomically reconciled species name (Genus species)
#   d.bh           — stem diameter at breast height [m] (note: metres, not cm)
#   h.t            — total plant height [m]
#   m.to           — total above-ground biomass [kg]
#   latitude, longitude — geographic coordinates (kept for potential spatial QA)
baad_raw <- baad.data::baad_data()$data

# Retain only the columns needed for this analysis and filter to records where
# DBH and height are both measured and positive. m.to (AGB) is optional at
# the record level — many BAAD entries lack measured AGB.
baad_filtered <- baad_raw |>
  select(speciesMatched, d.bh, h.t, m.to, latitude, longitude) |>
  filter(
    !is.na(speciesMatched),
    !is.na(d.bh), d.bh > 0,
    !is.na(h.t),  h.t  > 0
  ) |>
  # Convert BAAD's diameter in metres to centimetres. DBH in cm is the
  # convention in most forest allometry literature and matches the expected
  # units for the WBE H ~ DBH^(2/3) relationship.
  mutate(DBH_cm = d.bh * 100)

# Compute species-level log10 means.
# Note: AGB (m.to) is only averaged for records where it is positive; species
# with no AGB records will have log_AGB_kg = NaN (from mean of no values),
# which downstream regressions will correctly treat as missing.
baad_species_means <- baad_filtered |>
  group_by(speciesMatched) |>
  summarise(
    log_DBH_cm   = mean(log10(DBH_cm),                                       na.rm = TRUE),
    log_height_m = mean(log10(h.t),                                          na.rm = TRUE),
    # AGB guard: exclude zero/negative m.to before log — some BAAD records
    # have m.to = 0 as a placeholder rather than a true measurement.
    log_AGB_kg   = mean(log10(m.to[!is.na(m.to) & m.to > 0]),               na.rm = TRUE),
    n_obs_baad   = n(),
    .groups = "drop"
  ) |>
  mutate(genus = gsub("\\s.*", "", speciesMatched))

# ── SECTION C: Save ───────────────────────────────────────────────────────────
# Both RDS (type-safe, fast) and CSV (human-readable) are written.
# RDS is used by scripts 05 and 06; CSV is provided for inspection and
# potential use in other software (e.g. Excel, Python).

saveRDS(ne_species_means,   file.path(proj_dir, "data/processed/ne_species_means.rds"))
saveRDS(baad_species_means, file.path(proj_dir, "data/processed/baad_species_means.rds"))

write_csv(ne_species_means,   file.path(proj_dir, "data/processed/ne_species_means.csv"))
write_csv(baad_species_means, file.path(proj_dir, "data/processed/baad_species_means.csv"))

# Diagnostic counts: review these before running script 05.
# A high singleton count in NE (> ~30%) may inflate apparent R² in PGLS
# because singletons cannot contribute within-species variance information.
cat("NE species:", nrow(ne_species_means), "| NE singletons:", sum(ne_species_means$singleton), "\n")
cat("BAAD species:", nrow(baad_species_means), "\n")
