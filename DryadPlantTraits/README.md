# DryadPlantTraits

DryadPlantTraits is a small R-first harvesting project for discovering plant functional trait studies on Dryad, inventorying downloadable assets, downloading files with Dryad bearer-token authentication, and compiling likely trait observations into a BIEN-style row-level table.

This project is intentionally a starter pipeline, not a claim of full automatic harmonization across arbitrary study schemas. Discovery is heuristic: many Dryad search hits will not be true plant functional trait datasets, and many downloadable files will still require manual review.

## Scope

- Discover candidate Dryad datasets with AusTraits-inspired plant functional trait vocabulary such as leaf area, SLA, wood density, seed mass, plant height, leaf nitrogen, and leaf phosphorus.
- Inventory public dataset, version, and file metadata without authentication.
- Download file content only when `DRYAD_API_TOKEN` is available.
- Standardize likely tabular trait records into a BIEN-style observation table while preserving Dryad provenance and raw mapped values.

## Relationship To BIEN And AusTraits Ideas

The compiled output is aligned to a BIEN-style observation model with fields such as `scrubbed_species_binomial`, `trait_name`, `trait_value`, `unit`, `latitude`, `longitude`, `date_collected`, and locality metadata. The search vocabulary and starter trait dictionary are informed by common AusTraits-style plant functional trait concepts, but this project does not claim AusTraits equivalence or full schema coverage.

## Authentication

Dryad exposes public metadata through its API, but actual dataset and file downloads require authentication. Set a bearer token before running the download-and-compile workflow:

```bash
export DRYAD_API_TOKEN="your-token-here"
```

If the token is missing or invalid, the compile script will stop with a clear authentication error after writing a processing log.

## Project Layout

- `R/dryad_api.R`: Dryad request helpers, metadata retrieval, and authenticated download support.
- `R/search_terms.R`: seeded search vocabulary for plant functional traits.
- `R/candidate_filter.R`: heuristic scoring and filtering of candidate datasets.
- `R/trait_dictionary.R`: starter crosswalk from common source trait labels to standardized names.
- `R/standardize_records.R`: starter BIEN-style record compiler for likely tabular trait files.
- `R/io_helpers.R`: tabular file reading and archive extraction helpers.
- `scripts/discover_dryad_plant_traits.R`: discovery-only workflow, no token required.
- `scripts/compile_downloaded_traits.R`: token-backed download and compile workflow.
- `scripts/smoke_test.R`: narrow executable check.

## Run Discovery Only

This mode searches Dryad, scores candidate datasets heuristically, inventories public file metadata, and writes CSV outputs under `DryadPlantTraits/output/`.

```bash
Rscript --vanilla DryadPlantTraits/scripts/discover_dryad_plant_traits.R
```

Optional arguments:

```bash
Rscript --vanilla DryadPlantTraits/scripts/discover_dryad_plant_traits.R \
  --pages-per-term=1 \
  --per-page=25 \
  --output-dir=DryadPlantTraits/output
```

Outputs:

- `candidate_datasets.csv`: deduplicated dataset-level candidate inventory with heuristic scores.
- `candidate_files.csv`: file-level metadata inventory for candidate datasets.

## Run Download And Compile

This mode reads the candidate inventory, downloads a user-limited subset of candidate files with `DRYAD_API_TOKEN`, extracts supported tabular files, standardizes likely trait observations, and writes compiled outputs.

```bash
export DRYAD_API_TOKEN="your-token-here"
Rscript --vanilla DryadPlantTraits/scripts/compile_downloaded_traits.R
```

Optional arguments:

```bash
Rscript --vanilla DryadPlantTraits/scripts/compile_downloaded_traits.R \
  --candidate-files=DryadPlantTraits/output/candidate_files.csv \
  --max-datasets=3 \
  --max-files=5 \
  --output-dir=DryadPlantTraits/output
```

Outputs:

- `compiled_trait_observations.csv`: starter BIEN-style observation table.
- `processing_log.csv`: per-file processing status, skip reasons, and row counts.

## Important Constraints

- Discovery is heuristic and not all returned Dryad hits are true plant trait datasets.
- Missing coordinates and missing taxon fields are preserved as `NA`; they are not silently dropped.
- Output is observation oriented rather than species-mean only.
- Raw mapped values and source column names are preserved with `raw_*` and `source_column_*` fields when possible.
- Unsupported or ambiguous files are logged and skipped rather than failing the full run.
