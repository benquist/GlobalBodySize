# Project Plan

## Objectives

- Assemble a reproducible pipeline for plant allometry scaling data.
- Integrate BAAD, Dryad, and Niklas/Enquist ORNL sources with clear provenance.
- Harmonize taxonomy, traits, and units across datasets.
- Audit merged data for consistency and outlier detection.

## Data Sources

- BAAD raw and metadata files
- Dryad project datasets for plant biomass and structural traits
- Niklas / Enquist ORNL allometry compilations

## Analysis Milestones

1. `scripts/01_ingest_allometry_data.R`
   - Load raw source files
   - Standardize column names
   - Prepare source-specific data frames

2. `scripts/02_merge_normalize_units.R`
   - Reconcile taxonomy across datasets
   - Harmonize trait units
   - Create merged trait catalog with source fields

3. `scripts/03_audit_units_and_values.R`
   - Audit unit consistency and dimensions
   - Check trait value ranges and outliers
   - Generate summaries for quality assurance

4. `METHODS.md`
   - Document methods and provenance tracking
   - Separate exploratory and confirmatory phases

## Folder Structure

- `plant_scaling_data/`
  - `README.md`
  - `PROJECT_PLAN.md`
  - `METHODS.md`
  - `.gitignore`
  - `chat_provenance_log.md`
  - `scripts/`
    - `01_ingest_allometry_data.R`
    - `02_merge_normalize_units.R`
    - `03_audit_units_and_values.R`
