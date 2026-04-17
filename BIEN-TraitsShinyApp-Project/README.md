# BIEN Traits Shiny App Project

This project now contains the full BIEN Traits production app implementation.

## Structure

- app.R
- R/helpers.R (scaffold helper module)
- R/ui.R (scaffold UI module)
- R/server.R (scaffold server module)
- www/
- data/
- docs/
- deploy.R

Note: `app.R` is currently the active production entrypoint.

## Run locally

R:

```r
shiny::runApp("BIEN-TraitsShinyApp-Project")
```

## Deploy

R:

```r
source("BIEN-TraitsShinyApp-Project/deploy.R")
```
