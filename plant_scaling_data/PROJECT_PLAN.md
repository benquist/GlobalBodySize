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

5. `scripts/04_prepare_pgls_species_means.R`
   - Aggregate Niklas-Enquist and BAAD to species means (log10-scale geometric means)
   - Filter to clean species binomials; recode -999 to NA
   - Output: `data/processed/ne_species_means.rds`, `data/processed/baad_species_means.rds`

6. `scripts/05_build_phylogeny_smith2018.R`
   - Build pruned seed plant phylogeny via V.PhyloMaker2 (Smith & Brown 2018 GBOTB backbone, Scenario 2)
   - set.seed(42) for reproducible polytomy resolution
   - Output: `data/processed/pgls_tree_smith2018_s2.rds`, `data/processed/pgls_tree_match_table.csv`

7. `scripts/06_pgls_allometry.R`
   - OLS, SMA (smatr), and PGLS (caper::pgls, lambda ML-estimated with bounds [1e-6, 1]) for 6 scaling relationships
   - Phylogenetic signal: Pagel's lambda and Blomberg's K via phytools::phylosig()
   - Lambda profile CI via pgls.profile()/pgls.confint()
   - Forest plot and scatter plots saved to `output/`
   - Output: `data/processed/pgls_results_table.rds`, `data/processed/phylosig_table.rds`

8. `pgls_allometry_report.Rmd`
   - Full reproducible report: methods, phylogeny summary, signal table, results tables, visualizations
   - WBE theoretical predictions vs empirical estimates
   - Compositional artifact and growth-rate measurement caveats

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
