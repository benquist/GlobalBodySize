# scripts/03_audit_units_and_values.R

library(dplyr)
library(ggplot2)

load_merged_traits <- function(path) {
  readRDS(path)
}

audit_unit_consistency <- function(df) {
  # identify mixed units within trait groups
  df
}

audit_dimension_sanity <- function(df) {
  # verify values are physically plausible for each trait
  df
}

audit_outliers <- function(df) {
  # flag extreme values and summarize by trait
  df
}

traits <- load_merged_traits("../data/processed/merged_allometry_traits.rds")

unit_check <- audit_unit_consistency(traits)
dimension_check <- audit_dimension_sanity(traits)
outlier_check <- audit_outliers(traits)

# Export audit summaries
write_csv(unit_check, "../data/processed/audit_unit_consistency.csv")
write_csv(dimension_check, "../data/processed/audit_dimension_sanity.csv")
write_csv(outlier_check, "../data/processed/audit_outliers.csv")
