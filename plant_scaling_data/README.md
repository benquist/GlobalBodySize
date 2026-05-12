# plant_scaling_data

A reproducible, ecology-first allometry workflow for testing plant scaling relationships with explicit attention to taxonomy, unit integrity, phylogenetic non-independence, and interpretation risk.

This README is intentionally tutorial-style: it explains not only what to run, but why each step exists and how to avoid common conceptual mistakes (especially around unit harmonization, compositional artifacts, and over-interpretation of theory tests).

## Scientific Scope

This project asks three linked questions:

1. What allometric exponents are observed across merged plant datasets for relationships such as biomass-height, growth-biomass, and height-diameter?
2. How sensitive are these exponents to regression method (OLS vs SMA vs PGLS)?
3. How much does phylogenetic structure alter slope estimates and inference?

The active workflow is centered on these files:

- scripts/01_ingest_allometry_data.R
- scripts/02_merge_normalize_units.R
- scripts/03_audit_units_and_values.R
- scripts/04_prepare_pgls_species_means.R
- scripts/05_build_phylogeny_smith2018.R
- scripts/06_pgls_allometry.R
- pgls_allometry_report.Rmd
- sapfluxnet_water_use_scaling.Rmd
- grand_cross_study_allometry.Rmd
- chat_provenance_log.md

### Standalone Analysis Reports

These Rmd files are self-contained analyses for individual datasets:

- `kurosawa_respiration_scaling.Rmd` — Kurosawa et al. leaf/stem/root respiration ~ mass scaling; OLS, SMA, PGLS
- `baad_agb_leaf_allometry.Rmd` — BAAD AGB ~ leaf mass and leaf area; SMA by clade, family, intraspecific
- `baad_leaf_biomass_diameter_scaling.Rmd` — BAAD leaf biomass ~ stem diameter; OLS, SMA, PGLS
- `niklas_enquist_organ_scaling.Rmd` — Niklas-Enquist organ-mass allometry (17 relationships); WBE scorecard

## Theoretical Background

### Core allometric form

Most relationships in this repo use the power-law form:

$$
Y = aX^b
$$

Log-transforming gives a linear model:

$$
\log_{10}(Y) = \log_{10}(a) + b\log_{10}(X)
$$

where $b$ is the scaling exponent of biological interest.

### Common predictions used in this project

- Biomass-height: $M \propto H^{8/3}$
- Growth-biomass: $dM/dt \propto M^{3/4}$
- Height-diameter: $H \propto DBH^{2/3}$

These are used as hypothesis anchors in parts of the workflow, not as guaranteed truths. The project is explicit about this: agreement with a predicted exponent is supportive but not uniquely confirmatory.

### Why multiple regression methods?

- OLS is familiar and easy to compare with legacy literature.
- SMA is often preferred for allometry when both axes have measurement error.
- PGLS adjusts for phylogenetic covariance among species.

Method choice is not cosmetic. It can change slope estimates, uncertainty, and conclusions.

## Data, Provenance, and Uncertainty Caveats

### Provenance discipline

- Keep project-level analysis provenance in chat_provenance_log.md.
- Keep agent prompt provenance in agents/prompt_log.md (repository-level policy).
- Keep agent-change provenance in agents/agent_chat_provenance_log.txt when agent files/policies are modified.

### Current pipeline maturity

- scripts/01_ingest_allometry_data.R: ingest scaffolding with source-specific parsers; some sources currently placeholders.
- scripts/02_merge_normalize_units.R: merge + reconciliation hooks; taxonomy and unit normalization are currently stubs to be implemented in full.
- scripts/03_audit_units_and_values.R: audit structure is present; unit/dimension/outlier functions are currently TODO stubs.
- scripts/04_prepare_pgls_species_means.R through scripts/06_pgls_allometry.R: operational comparative workflow for species means, phylogeny build, and OLS/SMA/PGLS fits.

### Ecological and statistical caveats

- Unit mismatch can silently bias slopes and intercepts.
- Species-mean analyses reduce within-species information and can hide ecological heterogeneity.
- Cross-study compilations may have clade, biome, and methodology imbalance.
- Component-vs-total biomass regressions can create mathematical coupling artifacts.
- Net growth proxies are not always equivalent to instantaneous metabolic flux.

## Quick Start

Run from the project root:

1. cd plant_scaling_data  # adjust to your local path
2. Ensure R is available: Rscript --version
3. Install required packages (one-time):

```r
install.packages(c(
	"readr", "dplyr", "stringr", "ggplot2", "tibble", "tidyr",
	"ape", "caper", "smatr", "phytools", "baad.data", "V.PhyloMaker2",
	"knitr", "rmarkdown", "purrr", "lme4", "performance", "quantreg", "leaflet",
	"data.table", "sf", "geodata", "ggrepel", "gridExtra", "metafor"
))
```

4. Confirm expected raw inputs exist under data/raw (especially Niklas-Enquist CSV and any optional datasets for Rmd analyses).

## Step-by-Step Tutorial Run

### A. Core scripted pipeline (01-06)

Run scripts in order:

```bash
Rscript scripts/01_ingest_allometry_data.R
Rscript scripts/02_merge_normalize_units.R
Rscript scripts/03_audit_units_and_values.R
Rscript scripts/04_prepare_pgls_species_means.R
Rscript scripts/05_build_phylogeny_smith2018.R
Rscript scripts/06_pgls_allometry.R
```

What to inspect before moving on:

1. After 01: confirm source-level RDS files were written.
2. After 02: inspect merged_allometry_traits.rds fields and provenance columns.
3. After 03: review audit CSVs; do not proceed blindly if implausible values are flagged.
4. After 04: check singleton frequency and species counts.
5. After 05: inspect pgls_tree_match_table.csv for species dropped during tree matching.
6. After 06: inspect pgls_results_table.csv and phylosig_table.csv plus generated plots.

### B. Render the PGLS report

```bash
Rscript -e "rmarkdown::render('pgls_allometry_report.Rmd', quiet=FALSE)"
```

This report is the narrative companion to scripts/04-06 and should be treated as the first check for model and interpretation consistency.

### C. Optional companion analyses

Render the additional analyses when needed:

```bash
Rscript -e "rmarkdown::render('sapfluxnet_water_use_scaling.Rmd', quiet=FALSE)"
Rscript -e "rmarkdown::render('grand_cross_study_allometry.Rmd', quiet=FALSE)"
Rscript -e "rmarkdown::render('kurosawa_respiration_scaling.Rmd')"
Rscript -e "rmarkdown::render('baad_agb_leaf_allometry.Rmd')"
Rscript -e "rmarkdown::render('baad_leaf_biomass_diameter_scaling.Rmd')"
Rscript -e "rmarkdown::render('niklas_enquist_organ_scaling.Rmd')"
```

These are broader syntheses and should be interpreted with dataset-specific caveats documented inside each Rmd.

## Expected Outputs

| Stage | Primary outputs | Notes |
|---|---|---|
| scripts/01 | data/processed/baad_raw.rds, data/processed/dryad_raw.rds, data/processed/niklas_enquist_raw.rds | Initial source parsing |
| scripts/02 | data/processed/merged_allometry_traits.rds | Includes source provenance columns |
| scripts/03 | data/processed/audit_unit_consistency.csv, data/processed/audit_dimension_sanity.csv, data/processed/audit_outliers.csv | QA audit summaries |
| scripts/04 | data/processed/ne_species_means.rds, data/processed/ne_species_means.csv, data/processed/baad_species_means.rds, data/processed/baad_species_means.csv | Species-level PGLS inputs |
| scripts/05 | data/processed/pgls_tree_smith2018_s2.rds, data/processed/pgls_tree_smith2018_s2.tre, data/processed/pgls_tree_match_table.csv | Tree + matching diagnostics |
| scripts/06 | data/processed/pgls_results_table.rds, data/processed/pgls_results_table.csv, data/processed/phylosig_table.rds, data/processed/phylosig_table.csv, output/forest_plot_slopes.png, output/scatter_ne_biomass_height.png | Core model outputs |
| Report render | pgls_allometry_report.html | Narrative interpretation |
| Companion render | sapfluxnet_water_use_scaling.html, grand_cross_study_allometry.html | Extended analyses |

## Interpretation Guardrails

Use these guardrails when reading results tables and figures:

1. Do not treat agreement with a target exponent as proof of a single mechanism.
2. Compare OLS, SMA, and PGLS jointly before drawing biological conclusions.
3. Check whether phylogenetic signal is non-trivial before preferring non-phylogenetic fits.
4. Distinguish descriptive scaling from mechanistic confirmation.
5. Do not report numeric claims from stale outputs without re-running the pipeline.
6. Do not infer universality from clade- or biome-skewed samples.
- The constant `STRESS_H_DBH = 1/2` in `grand_cross_study_allometry.Rmd` is flagged UNVERIFIED in source. Do not interpret empirical results against this theoretical value until the source citation is confirmed.

## Phylogeny and Taxonomy Caveats

1. PGLS requires exact name matching between data and tree tips.
2. Unresolved synonyms and spelling variants can silently reduce sample size.
3. Scenario S2 grafting in V.PhyloMaker2 is practical, but placement assumptions can influence covariance structure.
4. Species absent from the backbone are dropped and should be reported transparently.
5. Reconciliation quality should be audited before interpretation, not after.

Recommended minimum practice:

- Always review data/processed/pgls_tree_match_table.csv before reporting PGLS sample sizes.
- Preserve a reconciliation table whenever taxonomy mapping logic is updated.

## Reproducibility Checklist

Before sharing results, verify all boxes:

- [ ] Ran scripts/01 through scripts/06 in order in a clean R session.
- [ ] Reviewed audit outputs from scripts/03 and documented any exclusions.
- [ ] Checked species-to-tree match coverage in pgls_tree_match_table.csv.
- [ ] Re-rendered pgls_allometry_report.Rmd from current outputs.
- [ ] Logged key workflow actions in chat_provenance_log.md.
- [ ] Confirmed package availability and versions used in the run.
- [ ] Avoided manual edits to generated result files.

## Troubleshooting

### Missing package errors

- Symptom: script fails at library(...)
- Fix: install missing packages listed in Quick Start.

### V.PhyloMaker2 / tree build failure

- Symptom: script/05 stops with phylo.maker failure
- Fix: install V.PhyloMaker2; verify species/genus columns are non-empty and binomial.

### Low species match to tree

- Symptom: many FALSE rows in pgls_tree_match_table.csv
- Fix: improve taxonomy reconciliation logic (script/02 hook) and rerun scripts/04-06.

### NA-heavy slope tables

- Symptom: missing slopes/CIs in pgls_results_table.csv
- Fix: check positive-value filtering, trait availability, and minimum complete-pair sample size.

### Rmd render fails

- Symptom: rmarkdown::render aborts
- Fix: rerun the upstream scripts, then render again; inspect missing file paths and package loading blocks.

## Citation and Source Notes

Use and verify citations from the scripts and Rmd files before manuscript submission.

Suggested core references:

1. Falster et al. 2015 BAAD description. Needs verification.
2. Niklas and Enquist allometric synthesis papers. Needs verification.
3. Smith and Brown 2018 seed plant phylogeny. Needs verification.
4. Jin and Qian / V.PhyloMaker2 backbone and implementation references. Needs verification.
5. Warton et al. SMA methodology (smatr). Needs verification.
6. Forrester et al. 2022 SAPFLUXNET water-use scaling. Needs verification.
7. SAPFLUXNET data descriptor and Zenodo release references. Needs verification.

If a citation is used in external reporting, validate DOI, year, journal, and title against authoritative sources first.

## Where to Start Reading in This Repo

If you are new to this project, start in this order:

1. scripts/04_prepare_pgls_species_means.R
2. scripts/05_build_phylogeny_smith2018.R
3. scripts/06_pgls_allometry.R
4. pgls_allometry_report.Rmd
5. chat_provenance_log.md

Then move to sapfluxnet_water_use_scaling.Rmd and grand_cross_study_allometry.Rmd for broader synthesis analyses.
