# DryadPlantTraits

DryadPlantTraits is an R-based pipeline for harvesting plant functional trait data from the Dryad Digital Repository (datadryad.org), Zenodo, Scientific Data / AusTraits, TraitHub (tundra), and the Fine Root Ecology Database (FRED). It discovers candidate datasets through programmatic API search, downloads and compiles individual trait observations into a provenance-rich, BIEN-style row-level table, and applies a multi-stage quality assurance (QA) workflow including a decision-tree algorithm for inferring and validating trait measurement units against published global reference ranges.

Occurrence-only intake work has been migrated to Literature_Data_To_BIENdb and is tracked there under `scripts/occurrence_intake/`, `data/occurrences/`, and `data/occurrence_source_intake.csv`.

This project is intentionally a harvesting and triage pipeline, not a claim of full automatic harmonization across arbitrary study schemas. Expert scientific review of compiled outputs — particularly for traits where unit confidence is low or unresolved — is expected and required before use in downstream analyses.

---

## Pipeline Status (as of 2026-04-29)

### Trait observation data (compiled row counts)

| Provider | Rows |
|---|---|
| DataDryad | 414,226 |
| Zenodo | 4,630 |
| Scientific Data / AusTraits | 1,810,852 |
| TraitHub (tundra) | 91,970 |
| FRED (Fine Root Ecology Database, partial) | 16,926 |

> **FRED note:** 635 of 681 FRED dataset files are currently unavailable (ZIP archives not accessible via API). Fix is in progress; the 16,926 rows represent the 46 files that could be downloaded. Full FRED coverage will be added in a future run.

### Occurrence-only migration note

Occurrence-only ingestion sources and scripts were moved out of this project to `Literature_Data_To_BIENdb` to keep DryadPlantTraits focused on trait harvesting and QA.

### Interactive harvest summary report

- `reports/dryad_trait_harvest_summary.Rmd` / `reports/dryad_trait_harvest_summary.html`
- Includes: per-provider row counts, manual occurrence source table, georeferenced leaflet map, FRED download status, and intake registry classification by access path

---

## Workflow

The pipeline is organized into three sequential stages: dataset discovery, download and compilation, and post-compile QA. Each stage is implemented as a standalone R script that can be run independently, provided that the outputs of upstream stages are available.

### Stage 1 — Dataset Discovery

**Script:** `scripts/discover_dryad_plant_traits.R`

Candidate datasets are identified by querying the Dryad Digital Repository REST API (`datadryad.org/api/v2`) using a curated vocabulary of plant functional trait search terms defined in `R/search_terms.R`. The vocabulary encompasses traits commonly analyzed in global plant ecology, including leaf area, specific leaf area (SLA), wood density, seed mass, plant height, leaf nitrogen, leaf phosphorus, leaf dry matter content (LDMC), specific root length (SRL), root tissue density (RTD), xylem vulnerability parameters (p50, p88), and categorical traits (growth form, leaf phenology). This vocabulary is informed by international trait synthesis frameworks including TRY (Kattge et al. 2020), AusTraits (Falster et al. 2021), and the handbook of plant trait measurement protocols (Pérez-Harguindeguy et al. 2013).

Each API query is paginated, with configurable page depth (`--pages-per-term`) and page size (`--per-page`). Retrieved dataset records are deduplicated by Dryad DOI. Each candidate dataset is scored heuristically by `R/candidate_filter.R` using keyword matching against dataset titles, keywords, and abstracts, supplemented by data-type and file-type flags. Scores reflect the probability that a dataset contains primary plant trait measurements; they do not guarantee scientific suitability.

**Outputs:**
- `output/candidate_datasets.csv` — deduplicated, scored dataset-level inventory
- `output/candidate_files.csv` — file-level metadata for all files in candidate datasets

Authentication is not required for this stage.

---

### Stage 2 — Download and Compilation

**Script:** `scripts/compile_downloaded_traits.R`

Individual dataset files are downloaded from the Dryad API using a bearer authentication token supplied via the `DRYAD_API_TOKEN` environment variable. The script reads `candidate_files.csv` and applies user-configurable caps on the number of datasets (`--max-datasets`) and files (`--max-files`) processed per run, allowing incremental compilation. Compressed archives (ZIP, tar.gz) are extracted in memory; supported tabular formats (CSV, TSV, Excel) are parsed and inspected for likely trait content.

Candidate rows are mapped to a standardized BIEN-style schema via `R/standardize_records.R`, which applies the crosswalk defined in `data/trait_dictionary_starter.csv` to align source column names to canonical trait names (`trait_name`) and values (`trait_value`, `unit`). All raw mapped values and source column names are preserved in `raw_*` and `source_column_*` fields. Full Dryad provenance is retained at the row level, including dataset DOI, version ID, file ID, source file path, and original row number within the source file.

The compiled observation table includes the following key fields:

| Field | Description |
|---|---|
| `scrubbed_species_binomial` | Taxon name as parsed from source; not guaranteed to be validated |
| `trait_name` | Standardized trait name (canonical key) |
| `trait_value` | Value as mapped; string type (numeric or categorical) |
| `unit` | Unit string as mapped from source, or inferred |
| `raw_trait_value` | Original value before mapping |
| `source_column_name` | Original column header in source file |
| `dryad_dataset_doi` | Dryad DOI for full provenance |
| `dryad_version_id` | Dryad version identifier |
| `dryad_file_id` | Dryad file-level identifier |
| `source_file_path` | Path within archive or direct filename |
| `original_row_number` | 1-based row index within source file |
| `latitude`, `longitude` | Decimal degrees (WGS84); `NA` if not provided in source |
| `date_collected` | Collection date as character; `NA` if not provided |

Files that cannot be parsed or do not contain mappable trait content are logged and skipped without halting the run.

**Outputs:**
- `output/compiled_trait_observations.csv` — BIEN-style row-level observation table
- `output/processing_log.csv` — per-file status, skip reasons, and row counts

Current scale: approximately 613,263 total rows compiled from 164 datasets.

---

### Stage 3 — Post-Compile Quality Assurance

**Script:** `scripts/run_post_compile_qa.R`

The post-compile QA pipeline applies a sequence of filtering and scoring steps to the compiled observation table. Each sub-step is implemented in a dedicated R source file and produces its own output files for traceability.

#### 3a — Species Gate

Implemented in `R/post_compile_qa/species_gate.R`. Observations are filtered to retain only rows in which `scrubbed_species_binomial` conforms to a parseable binomial name pattern (genus + epithet, with optional infraspecific designation). Rows with abstract text, blank species fields, or non-binomial strings are excluded. This step removes rows that result from compilation mapping errors in which tabular metadata fields (e.g., dataset abstracts) were incorrectly aligned to taxon columns during standardization.

- Rows retained after gate: ~452,739
- Rows excluded: ~160,524

**Outputs:** `output/qa_post_compile/species_kept.csv`, `species_dropped.csv`, `species_gate_summary.csv`

#### 3b — Numeric Range Scoring

Implemented in `R/post_compile_qa/range_scoring.R`. For numeric traits, each observation is scored against published reference ranges derived from global plant trait syntheses. Reference sources include:

- Kattge et al. (2020) — TRY plant trait database, Global Change Biology 26:119–188
- Wright et al. (2004) — global leaf economics spectrum, Nature 428:821–827
- Pérez-Harguindeguy et al. (2013) — trait measurement handbook, Australian Journal of Botany 61:167–234
- Chave et al. (2009) — wood density database, Ecology Letters 12:351–366
- Bergmann et al. (2020) — root economics space, Science Advances 6:eaba3756
- Medlyn et al. (2017) — stomatal conductance, New Phytologist 216:10–16

Scores reflect whether each numeric value is within, near, or outside the established global range for the specified unit. Out-of-range values may indicate unit errors, data entry errors, or legitimate outliers.

**Output:** `output/qa_post_compile/observations_scored.csv`

#### 3c — Triage

Implemented in `R/post_compile_qa/triage.R`. Range scores are used to classify each observation into one of three disposition categories: `keep`, `review`, or `reject`. Classification rules are applied per trait and reflect the severity of range deviation. Observations assigned `review` require expert examination before use.

**Outputs:** `observations_keep.csv`, `observations_review.csv`, `observations_reject.csv`, `triage_summary.csv`, `trait_diagnostics.csv`

#### 3d — Pre-Decision-Tree Flag for Gas-Exchange Traits

Before the decision-tree loop, observations for `stomatal_conductance`, `photosynthetic_rate`, `transpiration`, and `leaf_hydraulic_conductance` that contain non-numeric values are flagged with `dt_reason = "DATA_COMPILATION_ERROR_ABSTRACT_TEXT"` and `dt_confidence = "none"`. These rows result from a known compilation mapping error in which dataset abstract text was aligned to gas-exchange trait columns during standardization. They are excluded from further unit inference and should not be interpreted as trait measurements.

#### 3e — Decision-Tree Unit Inference

Implemented in `R/infer_units_decision_tree.R` via the function `iu_infer_units_dt()`. Observations are grouped by Dryad DOI, canonical trait name, and source column name. Each group passes through the following prioritized decision logic:

1. **Categorical early-exit.** If the trait is classified as categorical (`growth_form`, `leaf_phenology`, `dispersal_syndrome`, `leaf_type`, `mycorrhizal_type`, `woodiness`), the value is immediately submitted to vocabulary normalization in `R/standardize_categorical_traits.R`. Normalization maps both TRY numeric codes (e.g., growth form codes 1–9) and text synonyms to a canonical vocabulary. Rows that normalize successfully are assigned `dt_confidence = "categorical"` and exit the tree.

2. **Trait alias resolution and unit string normalization.** `iu_resolve_trait()` in `R/infer_units.R` maps trait name aliases to a canonical key. The unit string associated with the observation is normalized to a canonical form via a variants map (e.g., `"m2/kg"`, `"m² kg⁻¹"`, and `"m2 kg-1"` all resolve to `m2/kg`).

3. **Reference range check.** The numeric trait value is compared to the published reference range for the resolved canonical unit. If the value falls within the established global range, the observation is assigned `dt_confidence = "high"`. Reference ranges are drawn from the sources listed in Step 3b and include, for example: SLA, 1–1000 m²/kg (Kattge et al. 2020; Wright et al. 2004); plant height, 0.01–150 m (Kattge et al. 2020); wood density, 0.1–1.3 g/cm³ (Chave et al. 2009); seed mass, 0.001–2.5×10⁷ mg (Kattge et al. 2020); SRL, 0.1–500 m/g (Bergmann et al. 2020); RTD, 0.01–2.0 g/cm³ (Bergmann et al. 2020); p50, −20 to 0 MPa (Choat et al. 2012); p88, −20 to 0 MPa (Maherali et al. 2004).

4. **Alternative unit check.** If the value falls outside the reference range for the stated unit, conversion factors are applied to evaluate whether the value is plausible under alternative units registered for that trait. If an alternative unit produces an in-range value, the observation is assigned `dt_confidence = "low"`, indicating that the value is likely usable but requires a unit conversion before analysis.

5. **No match.** If no unit assumption produces a plausible in-range value, the observation is assigned `dt_confidence = "none"`. These cases require manual investigation.

Each observation receives four annotation fields: `dt_confidence`, `dt_inferred_unit`, `dt_reason`, `dt_evidence`, and `dt_citation`.

**Outputs:**
- `output/qa_post_compile/observations_scored_with_dt.csv` — full scored observation table with decision-tree annotations (~1 GB)
- `output/qa_post_compile/dt_unit_reconciliation_summary.csv` — per-trait confidence counts

---

## Current QA Results

Results from the most recent full pipeline run over 452,739 observations passing the species gate (compiled from 164 Dryad datasets).

### Overall confidence distribution

| Confidence level | N observations | Percentage |
|---|---|---|
| High (in-range for stated unit) | 173,678 | 38.4% |
| Low (in-range after unit conversion) | 33,636 | 7.4% |
| Categorical (vocabulary-normalized) | 67,661 | 14.9% |
| None (unresolved) | 177,764 | 39.3% |

### Per-trait summary

| Trait | N observations | % High | % Low | % Categorical | % None |
|---|---|---|---|---|---|
| plant_height | 62,708 | 100 | 0 | 0 | 0 |
| seed_mass | 15,519 | 100 | 0 | 0 | 0 |
| leaf_area | 20,086 | 100 | 0 | 0 | 0 |
| wood_density | 3,249 | 100 | 0 | 0 | 0 |
| p50 | 1,163 | 100 | 0 | 0 | 0 |
| p88 | 738 | 100 | 0 | 0 | 0 |
| specific_leaf_area | 66,720 | 91 | — | 0 | 9 |
| specific_root_length | 4,458 | 91 | — | 0 | 9 |
| root_tissue_density | 3,896 | 89 | — | 0 | 11 |
| growth_form | 46,807 | 0 | 0 | 100 | 0 |
| leaf_phenology | 20,854 | 0 | 0 | 100 | 0 |
| stomatal_conductance | 97,350 | 0 | 0 | 0 | 100 |

> **Note:** `stomatal_conductance` observations are 100% unresolved due to a known compilation mapping error in which dataset abstract text was routed to this trait column. These rows are flagged as `DATA_COMPILATION_ERROR_ABSTRACT_TEXT` and must not be used as trait measurements.

---

## Project Layout

```
R/
  dryad_api.R                         # Dryad API request helpers, metadata retrieval, authenticated download
  search_terms.R                      # Curated plant functional trait search vocabulary
  candidate_filter.R                  # Heuristic scoring and filtering of candidate datasets
  trait_dictionary.R                  # Starter crosswalk: source column labels → standardized trait names
  standardize_records.R               # BIEN-style record compiler for tabular trait files
  io_helpers.R                        # Tabular file parsing and archive extraction
  qa_checks.R                         # QA utility functions
  infer_units.R                       # Trait alias resolution, unit normalization, IU_NEGATIVE_EXPECTED_TRAITS
  infer_units_decision_tree.R         # Decision-tree unit inference algorithm (iu_infer_units_dt)
  standardize_categorical_traits.R    # Vocabulary normalization for categorical traits (TRY codes + synonyms)
  post_compile_qa/
    helpers.R                         # Shared QA helpers and CSV I/O
    species_gate.R                    # Binomial name filtering
    range_scoring.R                   # Numeric range scoring against published reference ranges
    triage.R                          # Keep / review / reject classification

scripts/
  discover_dryad_plant_traits.R       # Stage 1: dataset discovery (no token required)
  compile_downloaded_traits.R         # Stage 2: authenticated download and compilation
  run_post_compile_qa.R               # Stage 3: QA pipeline and decision-tree scoring
  merge_multisource_candidates.R      # Merge candidate inventories across providers
  generate_audit_report.R             # Audit report generation

data/
  trait_dictionary_starter.csv        # Trait name crosswalk (source label → canonical name + unit)

providers/
  scientific_data/                    # Scientific Data (nature.com/sdata) provider — in development
    scripts/
      discover_scientific_data_traits.R   # CrossRef + Figshare/Zenodo/GitHub/Dryad dataset resolver

output/                               # Pipeline outputs (not committed to git)
  candidate_datasets.csv
  candidate_files.csv
  compiled_trait_observations.csv
  processing_log.csv
  qa_post_compile/
    species_kept.csv
    species_dropped.csv
    species_gate_summary.csv
    observations_scored.csv
    observations_keep.csv
    observations_review.csv
    observations_reject.csv
    triage_summary.csv
    trait_diagnostics.csv
    observations_scored_with_dt.csv
    dt_unit_reconciliation_summary.csv
  providers/
    scientific_data/
      candidate_files.csv
```

Manual or user-supplied external sources that are not yet part of an automated provider workflow are tracked in `data/manual_source_intake.csv`. This committed registry is separate from generated candidate manifests under `output/`, which remain ephemeral pipeline artifacts rather than the durable home for manual intake tracking.

---

## Authentication

Dryad exposes public metadata (dataset records, version records, file metadata) through its API without authentication. Dataset file downloads require a bearer token. Obtain a token from your Dryad account and set it in your shell environment before running the compile stage:

```bash
export DRYAD_API_TOKEN="your-token-here"
```

If the token is absent or invalid, `compile_downloaded_traits.R` will halt with an explicit authentication error after writing the processing log. The discovery script (`discover_dryad_plant_traits.R`) and the QA script (`run_post_compile_qa.R`) do not require a token.

---

## Quick Start

### Stage 1 — Discover candidate datasets

```bash
Rscript --vanilla DryadPlantTraits/scripts/discover_dryad_plant_traits.R \
  --pages-per-term=10 \
  --per-page=20 \
  --output-dir=DryadPlantTraits/output
```

### Stage 2 — Download and compile trait observations

```bash
export DRYAD_API_TOKEN="your-token-here"
Rscript --vanilla DryadPlantTraits/scripts/compile_downloaded_traits.R \
  --candidate-files=DryadPlantTraits/output/candidate_files.csv \
  --max-datasets=164 \
  --max-files=500 \
  --output-dir=DryadPlantTraits/output
```

### Stage 3 — Run post-compile QA and decision-tree scoring

```bash
Rscript --vanilla DryadPlantTraits/scripts/run_post_compile_qa.R \
  --input=DryadPlantTraits/output/compiled_trait_observations.csv \
  --output-dir=DryadPlantTraits/output/qa_post_compile
```

---

## Scientific Caveats and Limitations

- **Discovery is keyword-heuristic.** Not all Dryad datasets returned by the search queries are true plant functional trait datasets. Heuristic scores improve precision but do not eliminate false positives. Expert review of the candidate inventory is recommended before large-scale compilation runs.

- **Taxon names are not validated.** `scrubbed_species_binomial` is parsed from the source data as provided. It is not matched against a taxonomic backbone (e.g., TNRS, GBIF) within this pipeline. Names should be validated externally before taxonomic aggregation.

- **Unit inference is probabilistic, not authoritative.** A `dt_confidence = "high"` assignment indicates that the numeric value falls within the established global reference range for the stated unit. It is not a guarantee that the value is accurate or that the unit was correctly reported in the source study. Values assigned `dt_confidence = "low"` require a unit conversion before use. Values assigned `dt_confidence = "none"` require investigation before use.

- **Missing coordinates and taxon fields are preserved as `NA`.** They are not silently dropped or imputed. Downstream analyses that require complete spatial or taxonomic records must apply their own filters.

- **Output is observation-level, not species-mean.** The compiled table retains individual measurements. Species-level means, medians, and variance estimates must be computed by the analyst with appropriate consideration of pseudo-replication, study design, and intraspecific variation.

- **Raw values and source column names are always preserved.** The `raw_trait_value` and `source_column_name` fields allow the original data to be inspected and re-mapped without reprocessing the source files.

- **Traits with 100% `none` confidence should be investigated before use.** As demonstrated by `stomatal_conductance` in the current compilation, a 100% none rate is a strong indicator of a systematic compilation mapping error affecting the entire trait column, not simply outlier measurements.

- **The Scientific Data provider is in active development** and its outputs have not been subject to the same validation as the primary Dryad pipeline.

---

## Key References

- Kattge, J. et al. (2020). TRY plant trait database — enhanced coverage and open access. *Global Change Biology* 26:119–188. https://doi.org/10.1111/gcb.14904
- Wright, I.J. et al. (2004). The worldwide leaf economics spectrum. *Nature* 428:821–827. https://doi.org/10.1038/nature02403
- Pérez-Harguindeguy, N. et al. (2013). New handbook for standardised measurement of plant functional traits worldwide. *Australian Journal of Botany* 61:167–234. https://doi.org/10.1071/BT12225
- Chave, J. et al. (2009). Towards a worldwide wood economics spectrum. *Ecology Letters* 12:351–366. https://doi.org/10.1111/j.1461-0248.2009.01285.x
- Bergmann, J. et al. (2020). The fungal collaboration gradient dominates the root economics space in plants. *Science Advances* 6:eaba3756. https://doi.org/10.1126/sciadv.aba3756
- Medlyn, B.E. et al. (2017). Reconciling the optimal and empirical approaches to modelling stomatal conductance. *New Phytologist* 216:10–16. https://doi.org/10.1111/nph.14598
- Falster, D. et al. (2021). AusTraits, a curated plant trait database for the Australian flora. *Scientific Data* 8:254. https://doi.org/10.1038/s41597-021-01006-6
- Choat, B. et al. (2012). Global convergence in the vulnerability of forests to drought. *Nature* 491:752–755. https://doi.org/10.1038/nature11688
- Maherali, H., Pockman, W.T., & Jackson, R.B. (2004). Adaptive variation in the vulnerability of woody plants to xylem cavitation. *Ecology* 85:2184–2199. https://doi.org/10.1890/02-0538
