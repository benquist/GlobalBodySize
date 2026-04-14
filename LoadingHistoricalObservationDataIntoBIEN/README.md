# Loading Historical Observation Data into BIEN

This project provides an R + Shiny MVP to:

- load historical observation CSV files
- suggest mappings to Darwin Core fields
- let users override mappings
- generate a BIEN loading table
- export handoff tables for TNRS, GNRS, GVS, and NSR

## Quick start

1. Open this project in R.
2. Run the app:

```r
shiny::runApp(".")
```

3. Upload a CSV and click `Suggest Mapping`.
4. Optionally upload a mapping override CSV with columns:
   - `source_column`
   - `dwc_term`
5. Click `Build BIEN Outputs`.
6. Download outputs from the app.

## Project layout

- `R/`: core ingest, mapping, and handoff functions
- `inst/dictionaries/`: mapping dictionaries
- `inst/extdata/`: sample data
- `app.R`: Shiny workflow UI

## Notes

This is an MVP scaffold. TNRS, GNRS, GVS, and NSR calls are represented by handoff tables for downstream workflow integration.
