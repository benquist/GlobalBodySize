# Plant Scaling Data Project

This project is a reproducible R-based workflow for plant allometry scaling analysis.

## Scope

The project integrates multiple published allometry datasets to derive and compare scaling relationships for plant size and biomass. It is designed to support transparent, reproducible data ingestion, harmonization, and audit before statistical modeling.

## Data Sources

- BAAD (Biomass And Allometry Database)
- Dryad allometry datasets
- Niklas and Enquist ORNL allometry datasets

## High-level Plan

1. Ingest raw source data and metadata.
2. Normalize variable names and taxonomy.
3. Harmonize units and prepare merged trait tables.
4. Audit merged data for unit consistency, dimensional sanity, and outliers.
5. Document methods and retain source/citation provenance throughout.

## Project Structure

- `scripts/` - reproducible data workflow scripts.
- `METHODS.md` - narrative methods description.
- `PROJECT_PLAN.md` - objectives, milestones, and structure.
- `chat_provenance_log.md` - project provenance entries.
- `.gitignore` - excludes common R and data artifacts.
