# BIEN Species Shiny App

Interactive Shiny app for species-level exploration of BIEN data, including occurrences, traits, and BIEN range artifacts.

## Project Description

This app supports biodiversity and ecology workflows where you want quick, transparent species-level evidence checks before downstream modeling.

It provides three linked evidence views:

- occurrence points (map and table)
- trait records (raw table and summarized table)
- range artifacts (status output and mapped polygons when BIEN shapefiles are available)

## Features

- Query BIEN by scientific species name.
- Interactive occurrence map with scale controls.
- Coordinate QA filtering and duplicate thinning for mapped points.
- Trait table and compact trait summary by trait name and unit.
- Optional BIEN range query with mapped polygons when available.
- Configurable query timeout and record limits.
- Reconciliation and error log tab for transparent failure reporting.

## Requirements

R packages used by the app:

- shiny
- BIEN
- dplyr
- stringr
- leaflet
- DT
- sf

The app auto-installs missing CRAN packages on startup.

## Run the App

From the repository root:

```bash
PATH="/opt/homebrew/bin:$PATH" Rscript -e 'shiny::runApp(".")'
```

Alternative (interactive R session):

```r
shiny::runApp(".")
```

If your shell shows a continuation prompt (`>`), cancel with `Ctrl+C` and paste only the command line, not Markdown code fences.

## Usage Notes

- BIEN occurrence and trait schemas can vary by query context; the app detects key columns dynamically where possible.
- BIEN range queries may return different object types depending on species and matched range availability.
- Some broad or very common taxa may still produce slower BIEN responses depending on upstream service load.

## Scope

This app is designed for exploratory species-level data triage and interpretation support, not publication-grade range modeling.
