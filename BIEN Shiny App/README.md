# BIEN Species Shiny App

Interactive Shiny app for species-level biodiversity exploration using the BIEN R package, with linked views for occurrences, traits, and species range artifacts.

## Overview

`BIEN-SpeciesShinyApp` is designed for fast, transparent inspection of species-level evidence before downstream ecological analysis, niche modeling, conservation screening, or data triage.

Instead of jumping immediately into modeling workflows, the app helps answer basic but critical questions first:

- Do usable occurrence records exist for the focal species?
- Are records geographically concentrated, sparse, or inconsistent?
- Which types of BIEN records are being returned (plot, specimen, literature, checklist, etc.)?
- Which trait data are available, and how much evidence supports them?
- Does BIEN provide mapped range artifacts even when occurrence coordinates are incomplete?

This makes the app especially useful for exploratory biodiversity and ecology workflows where interpretation depends on understanding the data source and record structure, not just raw point counts.

## What the app shows

The app organizes BIEN output into several linked views:

### 1. Overview map
- Maps occurrence points when usable latitude/longitude coordinates are available.
- Colors points by BIEN `observation_type` so users can visually distinguish record source classes such as plot, specimen, literature, or checklist.
- Falls back to the BIEN range polygon when occurrence rows exist but BIEN does not provide usable coordinates in the current response.
- Reports whether the map is showing all points or a sampled subset for responsiveness.

### 2. Observation table
- Displays the returned occurrence records in searchable tabular form.
- Helps inspect provenance, taxonomic matching, and geographic structure directly.

### 3. Traits and trait summary
- Shows raw trait records returned by BIEN.
- Summarizes trait availability by trait name, units, and number of records.

### 4. Range tab
- Displays BIEN range outputs and maps downloaded shapefiles when available.
- Useful for species where BIEN range artifacts are more complete than occurrence coordinates.

### 5. Reconciliation and error logging
- Surfaces matching and query information so that missing points, API timeouts, or schema mismatches are visible rather than silent.

## Main features

- Query BIEN by scientific species name.
- Interactive occurrence map with scale controls.
- Point coloring by BIEN `observation_type`.
- Explicit toggles for BIEN cultivated and introduced/native filtering behavior.
- Coordinate QA filtering and duplicate thinning for mapped points.
- Configurable query timeout and record caps to keep the app responsive for common species.
- Clear notices when the map is showing a range polygon instead of occurrence points.
- Trait table and compact trait summary by trait name and unit.
- Range visualization when BIEN shapefiles are available.
- Reconciliation and error log tab for transparent debugging and interpretation.

## Filtering options

The sidebar includes controls to tailor the biological interpretation of returned records:

- **Use BIEN `is_cultivated` filter** — turn cultivated filtering on or off.
- **Include cultivated records** — when the cultivated filter is active, decide whether cultivated records should be included.
- **Use BIEN `is_introduced` filter** — turn native/introduced filtering on or off.
- **Native records only** — when introduced filtering is active, keep only native records.
- **Only geovalid coordinates** — restrict results to BIEN-flagged geovalid points.

These controls are useful because the “best” filtering choice depends on the study question. For example, conservation or native-range questions may prefer strict native filtering, while horticultural or broader occurrence reconnaissance may not.

## Requirements

R packages used by the app:

- `shiny`
- `BIEN`
- `dplyr`
- `stringr`
- `leaflet`
- `DT`
- `sf`

The app auto-installs missing CRAN packages on startup.

## Run the app

From the repository root:

```bash
PATH="/opt/homebrew/bin:$PATH" Rscript -e 'shiny::runApp(".")'
```

Alternative from an interactive R session:

```r
shiny::runApp(".")
```

If the shell shows a continuation prompt (`>`), press `Ctrl+C` and paste only the command itself, not Markdown code fences.

## Interpreting the map correctly

The Overview summary now tells you whether the map is showing:

- **all mappable occurrence points**, or
- **a sampled subset** of points for responsiveness, or
- **a BIEN range polygon instead of points** when occurrence rows are returned without usable coordinates.

This is important for species where BIEN supplies records but not mappable coordinates in the current response.

## Known data caveats

- BIEN occurrence and trait schemas can vary by query context.
- Some taxa return occurrence rows without usable coordinates.
- Some common or widespread species can still be slower because of upstream BIEN service load.
- The app is intended for exploratory evidence review, not publication-grade range modeling or formal taxonomic reconciliation.

## Intended use

This project is best viewed as an interpretation-first biodiversity exploration tool: a practical front end for checking what BIEN knows about a species before deeper analysis.

