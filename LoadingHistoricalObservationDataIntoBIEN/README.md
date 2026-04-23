# BIEN Observation Ingest and Reconciliation Tool

This project provides an R + Shiny workflow tool to:

- load one or more historical observation CSV files
- join species records with plot/location metadata tables
- audit join quality (cardinality, unmatched keys, potential row inflation)
- suggest mappings to Darwin Core fields
- auto-detect DBH-like measurements and set measurementType/measurementUnit defaults
- run QC checks before BIEN handoff export
- let users override mappings
- generate a BIEN loading table draft
- export draft handoff tables for TNRS, GNRS, GVS, and NSR
- include richer GNRS-ready fields and explicit staging status columns in BIEN loading draft
- provide a persistent global help button plus workflow-stage status messaging

## Quick start

1. Open this project in R.
2. Run the app:

```r
shiny::runApp(".")
```

3. Upload one or more CSV files.
4. Choose the primary observation file, select the join key, choose optional metadata files, and click `1) Prepare Linked Table`.
5. Review the Join Audit table to confirm match coverage and join cardinality.
   Join suggestion scoring now prefers plot/site/event-style key names and de-prioritizes trait/measurement columns.
   If join cardinality blockers are detected, build and service stages are blocked until resolved.
   If metadata files contain duplicate join keys, the app will warn that those rows are being collapsed by key using first non-empty values. Treat that as a manual review point, not an automatic success.
   Review the Duplicate Key Conflict Report to see which key values and columns have conflicting duplicate metadata values.
6. Click `2) Suggest Mapping` and manually review key mapped fields.
7. Optionally upload a mapping override CSV with columns:
   - `source_column`
   - `dwc_term`
8. Click `3) Build BIEN Draft Tables` and review QC Dashboard results.
9. If QC `BLOCK` issues are present, resolve mappings/data and rebuild.
10. Download combined table, join audit report, QC report, and draft BIEN handoff outputs for downstream validation.
   Include the Join Conflict Report in handoff packages when duplicate metadata keys are detected.
11. Optionally click `4) Run BIEN Service Checks` for service-state summaries; this does not by itself certify final authoritative reconciliation.

## Help and About

- Click the persistent `Help` button in the app header for a quick workflow checklist.
- Use the `Help` tab for the full step-by-step explanation of the current workflow stages.
- Help/About text explicitly notes that this app prepares draft handoff tables and does not itself confirm taxonomic, geographic, or ecological validity.
- Taxonomy stage warns when unique-name volume exceeds the lookup cap so truncation is visible before export.
- The download section includes a persistent export limitations note so users see the main caveats at export time.

## Worked example (tutorial fake data)

1. In the sidebar, check `Use built-in tutorial fake data`.
2. Set primary file to `tutorial_observations.csv` and key to `plot_id`.
3. Select `sample_plot_metadata.csv` as metadata and choose key `plot_id`.
4. Click `1) Prepare Linked Table` and inspect all Step 2 Link Join Audit `WARN` and `BLOCK` rows.
5. Click `2) Suggest Mapping` and manually verify `scientificName`, `eventDate`, `locality`, `country`, `decimalLatitude`, and `decimalLongitude` in Step 3 Map.
6. Click `3) Build BIEN Draft Tables`.
7. Review Step 5 Validate `QC Dashboard`, then use Step 6 Export for draft outputs and optional `4) Run BIEN Service Checks` summaries.

The `Tutorial` tab displays previews of both fake input files so users can follow the workflow without uploading their own data.
The tutorial records are synthetic training data. They are biogeographically plausible, but they are not validated occurrence records and should not be used for ecological interpretation.

## Project layout

- `R/`: core ingest, mapping, and handoff functions
- `inst/dictionaries/`: mapping dictionaries
- `inst/extdata/`: sample data
- `app.R`: Shiny workflow UI

## BIEN Web Services (optional external validation)

After Step 3 (Build BIEN Draft Tables), you can optionally submit your data to external BIEN web services for authoritative reconciliation:

- **TNRS** (Taxonomic Name Resolution Service): Reconciles scientific names against the BIEN taxonomic backbone.
- **GNRS** (Geographic Name Resolution Service): Reconciles place/locality names to coordinates.
- **GVS** (Geospatial Validation Service): Validates coordinates and flags geographic impossibilities.
- **NSR** (Native Status Reference): Identifies and flags introduced, invasive, or cultivated species.

To use, click **"4) Run BIEN Service Checks"** in the sidebar (available after building BIEN draft tables). Results appear in **Step 6 Export** as service-state summaries. These messages are intentionally conservative: they indicate request/preview state and returned rows, but they do not claim final authoritative completion. **Review and reconcile downstream** before final BIEN submission.

## Notes

This is an MVP scaffold. TNRS, GNRS, GVS, and NSR calls are represented by handoff tables for downstream workflow integration. Successful export from this app is not evidence that names, places, coordinates, or native-status fields have been fully validated.

GNRS and staging note: the app now emits GNRS-ready query identifiers and normalized location input columns in exports, plus explicit staging status fields in the BIEN loading draft. External GNRS/TNRS services are still required for authoritative reconciliation.
