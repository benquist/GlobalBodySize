# Cacti Trait Data Pipeline

This folder contains a reproducible workflow to pull cacti trait data from BIEN and add supplementary internet data for the requested traits:

- body size (height, diameter, or mass)
- flower color

## How To Run

From the workspace root:

```bash
PATH="/opt/homebrew/bin:$PATH" Rscript cacti/scripts/fetch_cacti_traits.R
```

## Outputs

### Raw data

- `data_raw/bien_cactaceae_taxonomy.csv`
  - BIEN taxonomy backbone for family Cactaceae.
- `data_raw/bien_cactaceae_traits_all.csv`
  - All BIEN Cactaceae trait records returned by `BIEN_trait_family()`.
- `data_raw/wikidata_cacti_traits.csv`
  - Supplemental non-BIEN records from Wikidata SPARQL (target traits only).

### Processed data

- `data_processed/bien_cactaceae_species_accepted.csv`
  - BIEN accepted Cactaceae species list.
- `data_processed/bien_cacti_target_traits.csv`
  - BIEN records filtered to body size + flower color traits.
- `data_processed/cacti_traits_combined.csv`
  - Combined BIEN + Wikidata target-trait records.
- `data_processed/non_bien_sources_log.csv`
  - Provenance table for every non-BIEN source used.
- `data_processed/run_summary.csv`
  - Row counts from the current run.

## Provenance Rules

- BIEN records: `source_dataset = BIEN`, with BIEN URL and BIEN record ID where available.
- Non-BIEN records: source endpoint, source website, query properties, and query timestamp are written to:
  - `data_processed/non_bien_sources_log.csv`
- Non-BIEN trait rows include source URL and source record ID directly in row-level data.

## Notes

- BIEN taxonomy includes many accepted cacti species with no currently available target-trait records.
- Supplemental internet coverage (Wikidata) is currently sparse for these traits; provenance is fully recorded for each imported row.
