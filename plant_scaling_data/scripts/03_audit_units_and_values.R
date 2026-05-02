# scripts/03_audit_units_and_values.R
# ─────────────────────────────────────────────────────────────────────────────
# PURPOSE:  Step 3 of 6. Run three QA audits on the merged trait file and
#           write structured audit summaries for human review. This step must
#           be examined before proceeding to PGLS; bad values and unit
#           mismatches here become undetectable slope biases in script 06.
#
# INPUTS:   data/processed/merged_allometry_traits.rds
#
# OUTPUTS:  data/processed/audit_unit_consistency.csv
#           data/processed/audit_dimension_sanity.csv
#           data/processed/audit_outliers.csv
#
# KEY CONCEPTS:
#   • Unit consistency: allometric scaling is multiplicative in log-log space.
#     A biomass column measured in grams for one source and kilograms for
#     another shifts the intercept by log10(1000) = 3 and can alter the
#     effective slope if sources span different size ranges. This audit
#     identifies trait columns with multimodal distributions or within-column
#     ranges that are implausible for a single unit.
#
#   • Dimensional sanity: known biological ranges constrain plausible values:
#       - Plant height: ~0.001 m (seedling) to ~115 m (Sequoia)
#       - DBH: ~0.01 cm to ~1000 cm (baobab)
#       - Above-ground biomass: ~0.001 kg to ~500 000 kg
#       - Annual growth rate: positive and typically < 10× initial biomass/yr
#     Any record outside these ranges warrants investigation before inclusion
#     in an allometric regression — extreme values have outsized leverage on
#     log-log slopes.
#
#   • Outlier detection: in log-log allometric datasets, a standard approach is
#     to flag records whose residuals from a preliminary OLS fit exceed 3 SD.
#     These may represent data entry errors, measurement outliers, or genuinely
#     extreme individuals (which may be scientifically interesting but should
#     be documented rather than silently included).
# ─────────────────────────────────────────────────────────────────────────────

library(dplyr)    # data wrangling
library(ggplot2)  # diagnostic plots (available for use within audit functions)

# ── Load merged trait data ────────────────────────────────────────────────────
# This is the output of script 02. It spans all three sources with provenance
# columns intact.
load_merged_traits <- function(path) {
  readRDS(path)
}

# ── Audit 1: Unit consistency ─────────────────────────────────────────────────
# Checks whether values within each numeric trait column are consistent with
# a single unit across all sources. A practical implementation would:
#   - Compute per-source median and IQR for each trait
#   - Flag trait × source combinations where median differs by > 2 orders of
#     magnitude from the cross-source median (suggesting a unit mismatch)
# Caveat: this audit cannot distinguish a genuine cross-taxon size range from
# a unit error when both are plausible. Always cross-check against source
# metadata and the unit notes in script 02.
audit_unit_consistency <- function(df) {
  # TODO: implement per-source summary statistics for each trait column;
  # return a data frame with columns: trait, source, median, iqr, flag_mismatch
  df
}

# ── Audit 2: Dimensional sanity ───────────────────────────────────────────────
# Verifies that each measurement falls within a physically plausible range for
# its type. Biologically implausible values (e.g. height_m = 500 or
# total_biomass_kg = -5) are almost certainly data entry errors and must be
# removed before log-transformation (log of negative or zero is undefined).
# The function should return a data frame flagging records that fail any
# range check, with columns: row_id, taxa, trait, value, flag_reason.
audit_dimension_sanity <- function(df) {
  # TODO: implement range checks based on known biological limits; see header
  # for suggested thresholds. Reference: Falster et al. 2015 Ecology 96:1445
  # (BAAD data dictionary) and Niklas & Enquist 2004 PNAS for value ranges.
  df
}

# ── Audit 3: Statistical outlier detection ────────────────────────────────────
# Flags individual records whose trait values deviate strongly from the
# overall distribution. In log-scale, ± 3 SD from the mean is a common
# threshold. These are not necessarily errors — giant trees or dwarf herbs
# can legitimately exceed typical ranges — but they should be explicitly
# documented and their influence on slopes tested (e.g., run analysis with
# and without flagged records as a sensitivity check).
audit_outliers <- function(df) {
  # TODO: compute per-trait log10 mean and SD; flag records > 3 SD from mean;
  # return a data frame with trait, taxa, value, z_score, flag_outlier
  df
}

# ── Run audits ────────────────────────────────────────────────────────────────
traits          <- load_merged_traits("../data/processed/merged_allometry_traits.rds")
unit_check      <- audit_unit_consistency(traits)
dimension_check <- audit_dimension_sanity(traits)
outlier_check   <- audit_outliers(traits)

# ── Export audit summaries ────────────────────────────────────────────────────
# Written as CSV so they can be reviewed in a spreadsheet without running R.
# Any records flagged in these files should be resolved (corrected, filtered,
# or documented) before proceeding to script 04.
write_csv(unit_check,      "../data/processed/audit_unit_consistency.csv")
write_csv(dimension_check, "../data/processed/audit_dimension_sanity.csv")
write_csv(outlier_check,   "../data/processed/audit_outliers.csv")
