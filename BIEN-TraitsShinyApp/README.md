# BIEN Traits Shiny App

[![BIEN logo](www/bien.png)](https://biendata.org/)

Learn more about BIEN at **[biendata.org](https://biendata.org/)**.

Interactive Shiny app for querying BIEN trait observations, visualizing trait points on a map, reviewing observation-level provenance and citations, and exporting reproducible BIEN query code.

## Target deployment URL

https://benquist.shinyapps.io/bien-traits-shinyapp/

## Features

- Query BIEN trait data for one species or many species
- Upload a CSV or paste species names directly
- View available BIEN traits and trait coverage counts
- Inspect raw trait observations and species-trait-unit summaries
- Map trait observations when coordinates are available
- Review provenance and citation fields for each observation
- Download trait observations, summaries, citations, and R query script
- Help page with ecological caveats and workflow guidance

## Run locally

```r
shiny::runApp("BIEN-TraitsShinyApp")
```

## Required R packages

- shiny
- BIEN
- dplyr
- stringr
- leaflet
- DT
- jsonlite

## Deploy to shinyapps.io

Use `deploy.R` in this folder after configuring your rsconnect account.
