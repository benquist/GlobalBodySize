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

## Detailed code and workflow documentation

For a scientist-readable description of the R code, BIEN query workflow, provenance expectations, QA steps, and interpretation caveats, see:

- [`CODE_WORKFLOW_DOCUMENTATION.md`](./CODE_WORKFLOW_DOCUMENTATION.md)

This companion document is written to be understandable by biodiversity-focused review agents as well as human collaborators in ecology and taxonomy.

## What the app shows

The app organizes BIEN output into several linked views:

### 1. Occurrence Map
- Maps occurrence points when usable latitude/longitude coordinates are available.
- Colors points by BIEN `observation_type` or broader observation category so users can visually distinguish record source classes such as plot, specimen, literature, or checklist.
- Falls back to the BIEN range polygon when occurrence rows exist but BIEN does not provide usable coordinates in the current response.
- Reports whether the map is showing all points or a sampled subset for responsiveness.
- If one source class dominates a widespread species, the display can now be balanced by `datasource`, raw BIEN `observation_type`, or a broader observation category to make the map/table view more representative.

### 2. Summary Statistics
- Shows the main returned-record summary immediately after a species query.
- Can optionally fetch BIEN count-only totals and source-class fractions using the button **`Load BIEN total counts and source mix (slower)`**.
- Reports the active filter interpretation, the actual BIEN query strategy used, and key QA summaries.

### 3. Observation table

- Displays the returned occurrence records in searchable tabular form.
- Helps inspect provenance, taxonomic matching, and geographic structure directly.

### 4. Traits and trait summary
- Shows raw trait records returned by BIEN.
- Summarizes trait availability by trait name, units, and number of records.

### 5. Range tab
- Displays BIEN range outputs and maps downloaded shapefiles when available.
- Useful for species where BIEN range artifacts are more complete than occurrence coordinates.

### 6. Reconciliation and error logging
- Surfaces matching and query information so that missing points, API timeouts, or schema mismatches are visible rather than silent.

## Main features

- Query BIEN by scientific species name.
- Interactive occurrence map with scale controls.
- Point coloring by BIEN `observation_type`.
- Explicit toggles for BIEN cultivated and introduced/native filtering behavior.
- Coordinate QA filtering and duplicate thinning for mapped points.
- Configurable query timeout and record caps to keep the app responsive for common species.
- Clear notices when the map is showing a range polygon instead of occurrence points.
- Count-only BIEN occurrence totals and source-class fractions so users can compare the full matching record pool with the returned app sample.
- Trait table and compact trait summary by trait name and unit.
- Range visualization when BIEN shapefiles are available.
- Reconciliation and error log tab for transparent debugging and interpretation.

## Filtering options

The sidebar includes controls to tailor the biological interpretation of returned records:

- **Use BIEN native vs introduced status** — if left on, BIEN native/introduced metadata is used in the current view; if turned off, records are shown regardless of introduced status.
- **Keep native records only and hide introduced records** — when enabled, the app requests the stricter native-only subset.
- **Use BIEN cultivated vs wild status** — if left on, BIEN cultivated metadata is used in the current view; if turned off, both cultivated and non-cultivated records can be shown.
- **Include cultivated records** — when enabled, cultivated records are allowed in the returned subset; when off, they are hidden.
- **Keep only BIEN geovalid coordinates** — restricts the view to BIEN-flagged geovalid points and hides flagged/non-geovalid coordinates.

These controls are useful because the “best” filtering choice depends on the study question. For example, conservation or native-range questions may prefer strict native filtering, while horticultural or broader occurrence reconnaissance may not.

The app now also shows a short **plain-language filter summary** directly under these controls so users can see, at a glance, what kind of records they are currently requesting.

> **Important:** changing any of these toggles does not automatically rerun the BIEN query. After adjusting them, click **`Query BIEN`** again to refresh the results.

### Default filter profile

The default starting view is a **conservative ecological default**:

- BIEN native / not introduced records only
- cultivated records excluded
- BIEN geovalid coordinates only

This default is useful for biodiversity screening, native-range interpretation, and general occurrence QA. If the current species has no records under those strict settings, the app may broaden the actual query strategy to recover some BIEN evidence, and that behavior is reported in the `Summary Statistics` tab.

### On-demand loading behavior

To keep the first query responsive, the app now loads content in stages:

- **Occurrence Map** and occurrence evidence load first
- **Summary Statistics** shows fast returned-record summaries immediately and can fetch optional BIEN count-only totals and source fractions when you click the load button in that tab
- **Traits** load when a Traits tab is opened
- **Range** loads only when the Range tab is opened and the optional range toggle is enabled

To reduce over-representation of large datasource blocks (for example FIA plot rows appearing first in the backend table), the occurrence sample is now drawn from a **randomized BIEN occurrence query** rather than simply taking the first matching rows returned by BIEN.

If a widespread species is still visually dominated by one record stream, the sidebar now lets you balance the displayed subset by **datasource**, **BIEN observation type**, or a broader **observation category** instead of using only simple random thinning.

If BIEN is temporarily overloaded and refuses new public connections, the app now shows a clear warning that the backend is at capacity and suggests rerunning the query shortly, rather than implying the species truly has no observations.

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

## Install and run from GitHub

These steps are written for a collaborator who receives the GitHub repo link and wants to run the app locally.

### 1. Install prerequisites

Make sure the following are installed first:

- **Git** — check with `git --version`
- **R** — download from [CRAN](https://cran.r-project.org/)
- **Optional:** RStudio for a point-and-click way to run the app

On macOS, if package installation later fails for `sf`, it can help to run:

```bash
xcode-select --install
```

### 2. Clone the GitHub repository

```bash
git clone https://github.com/benquist/BIEN-SpeciesShinyApp.git
cd BIEN-SpeciesShinyApp
```

### 3. Run the app from Terminal

From the cloned repo folder, run:

```bash
Rscript -e 'shiny::runApp(".")'
```

If `Rscript` is not found on your system, try one of these macOS variants:

```bash
/usr/local/bin/Rscript -e 'shiny::runApp(".")'
```

or

```bash
/opt/homebrew/bin/Rscript -e 'shiny::runApp(".")'
```

### 4. Run the app from R or RStudio

```r
setwd("BIEN-SpeciesShinyApp")
shiny::runApp(".")
```

### 5. What to expect on first launch

- The app will automatically install any missing CRAN packages it needs.
- The first launch may take a little longer while packages are installed.
- Once running, Shiny will print a local address such as `http://127.0.0.1:xxxx` in the console.
- Open that address in a browser if it does not open automatically.
- Stop the app at any time with `Ctrl+C` in Terminal.

### 6. If you are running it from this larger monorepo instead

If the app is being run from the broader `biodiversity-agents-lab` workspace rather than the dedicated app repo, use:

```bash
Rscript -e 'shiny::runApp("BIEN Shiny App")'
```

### Troubleshooting

- If the shell shows a continuation prompt (`>`), press `Ctrl+C` and re-paste only the command itself.
- If `Rscript: command not found` appears, install R and try the full path version above.
- If package installation for `sf` fails on macOS, install the Apple command line tools first and then retry.

## Interpreting the map correctly

The Overview summary now tells you whether the map is showing:

- **all mappable occurrence points**, or
- **a sampled subset** of points for responsiveness, or
- **a BIEN range polygon instead of points** when occurrence rows are returned without usable coordinates.

This is important for species where BIEN supplies records but not mappable coordinates in the current response.

## Notes for biodiversity users

The biodiversity review agents flagged a few interpretation points that are worth keeping in mind when using the app:

- **Observation categories are heuristic summaries** derived from BIEN provenance text fields. They are meant to be scientist-friendly labels, not formal controlled-vocabulary assignments.
- **The Reconciliation tab is provisional** and shows BIEN-returned candidate names and query outcomes. It is useful for auditing, but it is not a formal synonym or accepted-name resolver.
- **Trait Graphics are deliberately conservative**: the app only plots continuous values that can be parsed as a single numeric measurement within one unit. Categorical traits and mixed-format strings such as ranges or date-like values remain in the tables instead of being forced into histograms.
- **The Overview distinguishes BIEN totals from the returned sample** by showing a count-only total of matching occurrence records without downloading all of them into the app, along with heuristic source-class fractions for specimens, iNaturalist, plots, traits, and other records.
- **Fallback query strategies matter biologically**. If the app relaxes native-only or geovalid filters to recover data, the Overview reports the strategy that was used.

## Known data caveats

- BIEN occurrence and trait schemas can vary by query context.
- Some taxa return occurrence rows without usable coordinates.
- Some common or widespread species can still be slower because of upstream BIEN service load.
- The app is intended for exploratory evidence review, not publication-grade range modeling or formal taxonomic reconciliation.

## Intended use

This project is best viewed as an interpretation-first biodiversity exploration tool: a practical front end for checking what BIEN knows about a species before deeper analysis.

