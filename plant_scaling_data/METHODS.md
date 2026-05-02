# Methods

This project documents the reproducible workflow used to assemble and audit plant allometry scaling data.

## Data provenance

Source and citation metadata are preserved through each stage of the pipeline. Each imported dataset retains fields such as `source`, `source_citation`, and `original_source` so that downstream analyses can trace trait values back to the originating publication or repository.

## Workflow phases

- Exploratory phase: initial ingestion, name normalization, taxonomy reconciliation, and unit harmonization.
- Confirmatory phase: final audit of merged trait values, unit consistency checks, and outlier identification.

## Trait harmonization

Trait columns are standardized with consistent variable names and units before merging. Unit harmonization includes converting measurements such as mass and length to common base units and tagging any source-specific units for review.

## Audit strategy

The merged trait table is audited for:

- Unit consistency within each trait group.
- Dimensional sanity based on expected biological ranges.
- Outlier values and suspicious records.

## Reproducibility

All scripts are designed to run in sequence and to save intermediate processed objects. The workflow separates source ingestion, merge/normalization, and audit stages to support review and re-running with updated data.
