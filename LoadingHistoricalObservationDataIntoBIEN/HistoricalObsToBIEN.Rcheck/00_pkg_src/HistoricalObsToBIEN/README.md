# Loading Historical Observation Data into BIEN

This project provides an R + Shiny MVP to:

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
- provide in-app help, about steps, and a tutorial walkthrough with fake data

## Quick start

1. Open this project in R.
2. Run the app:

```r
shiny::runApp(".")
```

3. Upload one or more CSV files.
4. Choose the primary observation file, select the join key, choose optional metadata files, and click `Prepare Combined Table`.
5. Review the Join Audit table to confirm match coverage and join cardinality.
   Join suggestion scoring now prefers plot/site/event-style key names and de-prioritizes trait/measurement columns.
   If metadata files contain duplicate join keys, the app will warn that those rows are being collapsed by key using first non-empty values. Treat that as a manual review point, not an automatic success.
   Review the Duplicate Key Conflict Report to see which key values and columns have conflicting duplicate metadata values.
6. Click `Suggest Darwin Core Mapping` and manually review key mapped fields.
7. Optionally upload a mapping override CSV with columns:
   - `source_column`
   - `dwc_term`
8. Click `Build BIEN Handoff Tables` and review QC Dashboard results.
9. If QC `BLOCK` issues are present, resolve mappings/data and rebuild.
10. Download combined table, join audit report, QC report, and draft BIEN handoff outputs for downstream validation.
   Include the Join Conflict Report in handoff packages when duplicate metadata keys are detected.

## Help and About

- Click `Help` in the app header for a quick workflow checklist.
- Use the `About` tab for a full step-by-step explanation of the process.
- Help/About text explicitly notes that this app prepares draft handoff tables and does not itself confirm taxonomic, geographic, or ecological validity.
- The download section includes a persistent export limitations note so users see the main caveats at export time.

## Worked example (tutorial fake data)

1. In the sidebar, check `Use built-in tutorial fake data`.
2. Set primary file to `tutorial_observations.csv` and key to `plot_id`.
3. Select `sample_plot_metadata.csv` as metadata and choose key `plot_id`.
4. Click `Prepare Combined Table` and inspect all Join Audit `WARN` and `BLOCK` rows.
5. Click `Suggest Darwin Core Mapping` and manually verify `scientificName`, `eventDate`, `locality`, `country`, `decimalLatitude`, and `decimalLongitude`.
6. Click `Build BIEN Handoff Tables`.
7. Review `QC Dashboard` and export draft outputs for downstream validation.

The `Tutorial` tab displays previews of both fake input files so users can follow the workflow without uploading their own data.
The tutorial records are synthetic training data. They are biogeographically plausible, but they are not validated occurrence records and should not be used for ecological interpretation.

## Project layout

- `R/`: core ingest, mapping, and handoff functions
- `inst/dictionaries/`: mapping dictionaries
- `inst/extdata/`: sample data
- `app.R`: Shiny workflow UI

## Notes

This is an MVP scaffold. TNRS, GNRS, GVS, and NSR calls are represented by handoff tables for downstream workflow integration. Successful export from this app is not evidence that names, places, coordinates, or native-status fields have been fully validated.

GNRS and staging note: the app now emits GNRS-ready query identifiers and normalized location input columns in exports, plus explicit staging status fields in the BIEN loading draft. External GNRS/TNRS services are still required for authoritative reconciliation.
