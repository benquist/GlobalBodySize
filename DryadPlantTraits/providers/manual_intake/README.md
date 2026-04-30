# Manual Intake Trait Sources

This provider directory contains manual ingestion support for user-supplied trait datasets that are not yet part of an automated provider workflow.

## Supported manual sources

- `manual_alltraits_phynames_csv`: `data/manual_ingestion/alltraits with phynames.csv`
- `manual_oztrait_data_joe_csv`: `data/manual_ingestion/oztrait data JoE.csv`
- `manual_ozark_trait_metadata2_xlsx`: `data/manual_ingestion/ozark trait metadata2.xlsx` (metadata companion workbook; staging only)

## Usage

1. Place the source files in `data/manual_ingestion/`.
2. Inspect available files and columns:
   - `Rscript providers/manual_intake/scripts/stage_manual_trait_sources.R`
3. Run a source-specific ingest mapping once the raw trait file structure is confirmed:
   - `Rscript providers/manual_intake/scripts/ingest_manual_trait_source.R --source=manual_oztrait_data_joe_csv`
   - `Rscript providers/manual_intake/scripts/ingest_manual_trait_source.R --source=manual_alltraits_phynames_csv`

Note: `manual_ozark_trait_metadata2_xlsx` is currently handled as a metadata-staging artifact and does not have a dedicated ingestion mapping stage yet.

## Output

- `output/providers/manual_intake/<source_id>/compiled_trait_observations.csv`

This pipeline is intentionally conservative: it first inspects the raw file, then maps recognized columns to the canonical Dryad trait schema.
