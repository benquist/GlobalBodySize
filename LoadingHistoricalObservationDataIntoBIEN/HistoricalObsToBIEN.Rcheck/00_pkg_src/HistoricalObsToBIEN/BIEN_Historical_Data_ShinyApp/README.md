# BIEN Historical Data Shiny App

This app helps ecologists take historical observation data in flat files and turn it into draft BIEN handoff tables.

It is designed for common real-world data situations:

- Species observations in one file
- Plot or site metadata in another file
- Coordinates, locality, or admin fields in another file
- Field names that do not already match Darwin Core terms

The app guides you through six stages:

1. Upload files
2. Link files by join keys
3. Map columns to Darwin Core
4. Triage likely taxonomy issues
5. Run QC checks
6. Export draft BIEN handoff tables

Important:

- Exports are draft handoff files.
- The app does not replace full taxonomic, georeferencing, or native-range validation.

## Who this is for

This README is written for basic ecology users who may not be programmers.

You can use this tool if you have CSV files and need to prepare data for BIEN workflows.

## What the app produces

The app can export:

- Combined source table after joins
- Join audit report
- Active mapping table
- QC report
- BIEN loading draft
- TNRS handoff
- GNRS handoff
- GVS handoff
- NSR handoff

## Quick start

1. Open this repository in RStudio.
2. In the Console, run:

```r
shiny::runApp(".")
```

3. Use tutorial mode first to learn the workflow safely.

## Recommended first run (tutorial mode)

Use built-in fake data before trying your own files.

1. Check Use built-in tutorial fake data.
2. In Step 1 Upload:
   - Primary file: tutorial_observations.csv
   - Primary key: plot_id
   - Metadata file: sample_plot_metadata.csv
   - Metadata key: plot_id
3. Click Step 2: Prepare Linked Table.
4. Review Join Audit.
5. Click Step 3: Suggest Mapping.
6. Click Step 5: Build BIEN Draft Tables.
7. Review taxonomy triage and QC table.
8. Download outputs.

## Real-data tutorial with examples

### Example input files

Example 1: observations.csv

```csv
record_id,species_name,plot_id,observed_on,observer,abundance
OBS-001,Quercus agrifolia,PLOT-001,1901-06-15,Walker,3
OBS-002,Pinus ponderosa,PLOT-002,1898-11-03,Singh,7
OBS-003,Populus tremuloides,PLOT-003,1912-03-01,Garcia,2
```

Example 2: plots.csv

```csv
plot_id,latitude,longitude,locality,country,stateProvince,county
PLOT-001,34.42,-119.70,Coastal oak woodland site,United States,California,Santa Barbara
PLOT-002,39.32,-120.35,Montane pine site,United States,California,Nevada
PLOT-003,39.55,-105.78,High-elevation meadow site,United States,Colorado,Park
```

Example 3: traits.csv (optional)

```csv
plot_id,canopy_cover,soil_type,elevation_m
PLOT-001,55,sandy_loam,210
PLOT-002,40,loam,1420
PLOT-003,25,rocky_loam,2890
```

### Step-by-step workflow

#### Step 1 Upload

- Upload one or more CSV files.
- Select primary observation file and key.
- Select optional metadata files and keys.

Tip: The primary file should usually be your occurrence-level table.

#### Step 2 Link

- Click Step 2: Prepare Linked Table.
- Review Join Audit carefully.

How to read Join Audit:

- PASS: No obvious key-structure issue detected.
- WARN: Possible coverage issue or one-to-many risk.
- BLOCK: Serious join risk, often many-to-many inflation.

If you see duplicate metadata key collapse warnings:

- The app collapses duplicate metadata keys by taking first non-empty values.
- Treat this as a manual cleanup flag, not a final solution.

#### Step 3 Map

- Click Step 3: Suggest Mapping.
- Review active mapping table.
- This step does not change your raw data; it tells the app which columns to treat as Darwin Core terms.

At minimum, ensure these terms are mapped correctly:

- scientificName
- eventDate
- locality
- occurrenceStatus
- basisOfRecord

If available, also map:

- decimalLatitude
- decimalLongitude
- country
- stateProvince
- county

For your two-file pattern (survey + plot metadata), the expected result is:

- Join by plot key in Step 2 so each survey row gets plot metadata fields.
- Map Species -> scientificName.
- Map Lat -> decimalLatitude.
- Map Long or Lon -> decimalLongitude.

#### Optional mapping override file

You can upload a CSV named however you like, with this structure:

```csv
source_column,dwc_term
species_name,scientificName
observed_on,eventDate
observer,recordedBy
abundance,individualCount
latitude,decimalLatitude
longitude,decimalLongitude
```

#### Step 4 Taxonomy

- Step 4 is a review checkpoint, not a data-editing step.
- The app runs a local triage of scientific names.
- It flags uncertain names such as sp., cf., aff., or blank values.
- If names look acceptable, continue to Step 5.

What TNRS handoff means:

- TNRS = Taxonomic Name Resolution Service.
- The exported tnrs_handoff.csv is a compact file with occurrenceID and scientificName.
- You run this file through a TNRS process to standardize names (accepted names, spelling, synonyms).
- Then match TNRS results back to your records using occurrenceID.

#### Step 5 Validate

- Click Step 5: Build BIEN Draft Tables.
- Review QC table:

QC severity levels:

- BLOCK: Must fix before BIEN loading export.
- WARN: Should be reviewed and usually corrected.
- PASS: No issue detected in current checks.

Common QC issues and fixes:

- scientificName missing or blank: fill or remove row.
- eventDate not parseable: use YYYY-MM-DD format.
- invalid coordinates: verify decimal degrees and lat/lon ranges.
- basisOfRecord outside vocabulary: use Darwin Core values.

#### Step 6 Export

When no BLOCK issues remain, download:

- bien_loading_table.csv
- tnrs_handoff.csv
- gnrs_handoff.csv
- gvs_handoff.csv
- nsr_handoff.csv

Also download and keep with your project notes:

- join_audit_report.csv
- dwc_qc_report.csv
- active_mapping.csv

## Troubleshooting

### I do not see my metadata columns after joining

- Check that join key names are correct.
- Ensure key values match exactly (case, spaces, formatting).
- Look at unmatched_primary_rows in Join Audit.

### I get BLOCK for scientificName blank

- Ensure your mapped source column has real species names.
- Remove empty rows if they are not true occurrences.

### eventDate warnings are high

- Convert dates to a consistent format.
- Preferred format is YYYY-MM-DD.

### Coordinates are flagged as invalid

- Latitude must be between -90 and 90.
- Longitude must be between -180 and 180.
- Verify you did not swap lat and lon.

## Practical ecology checklist before BIEN handoff

Before sharing outputs downstream:

- Confirm no QC BLOCK issues.
- Review all WARN issues.
- Review taxonomy triage table for uncertain names.
- Confirm coordinate plausibility on known species ranges.
- Confirm date precision is appropriate for intended analyses.
- Keep audit and mapping files for provenance.

## Project structure

- app.R: main Shiny app
- R/io_ingest.R: CSV reading helpers
- R/multi_file_merge.R: join and join audit logic
- R/dwc_mapping.R: Darwin Core mapping suggestions and application
- R/qc_checks.R: QC rules and blocker logic
- R/bien_handoff.R: BIEN and handoff table builders
- inst/extdata: tutorial and sample files
- inst/dictionaries: header synonym dictionary
- tests/smoke_join_qc.R: basic smoke test

## Disclaimer

This app is a preparation and QA tool.

Successful export does not guarantee final acceptance by BIEN or scientific validity for ecological inference.
