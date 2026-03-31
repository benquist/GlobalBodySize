# BIEN Shiny App

This project is a Shiny app for exploring species-level BIEN data from the BIEN R package.

## Project description

The app is intended for biodiversity and ecology workflows where users need to quickly inspect
species-level evidence from BIEN across three linked views:

- occurrence points (map + table)
- trait records (raw + summarized)
- range artifacts (status table + mapped polygons when BIEN shapefiles are available)

It is designed for exploratory analysis and data triage before formal downstream modeling.

## Main features

- Query a species by scientific name.
- Plot occurrence records on an interactive map.
- Change the geographic map scale.
- Set query timeout to avoid long-running species calls hanging the UI.
- Toggle whether BIEN range queries are executed (range calls can be slower).
- Inspect occurrence records in a searchable table.
- Inspect trait records and a summarized trait table.
- Visualize BIEN range maps directly when shapefiles are downloaded.
- Display returned range metadata and tabular range outputs.
- Highlight useful ecological and biodiversity questions to explore for each species.

## Run the app

Most reliable (avoids path issues with spaces):

```bash
cd "/Users/brianjenquist/VSCode/BIEN Shiny App"
Rscript -e 'shiny::runApp(".")'
```

Alternative from workspace root:

```bash
PATH="/opt/homebrew/bin:$PATH" Rscript -e 'shiny::runApp("BIEN Shiny App")'
```

## Dependencies

The app installs missing CRAN dependencies automatically:

- shiny
- BIEN
- dplyr
- stringr
- leaflet
- DT
- sf

## Notes

- BIEN occurrence and trait schemas can vary by query context, so the app detects key columns dynamically where possible.
- BIEN range queries may return different object types depending on the species and matched range availability.
- When BIEN returns only a range status table but downloads `.shp` files, the app reads and maps those polygons automatically.
- The app is designed first for species-level observation exploration rather than publication-quality range modeling.
