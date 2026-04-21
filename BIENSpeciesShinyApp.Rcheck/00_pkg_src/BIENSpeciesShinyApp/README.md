# BIEN Species Shiny App

[![BIEN logo](bien.png)](https://biendata.org/)

Learn more about BIEN at **[biendata.org](https://biendata.org/)**.

Interactive Shiny app for species-level biodiversity exploration using the BIEN R package, with linked views for occurrences, traits, and species range artifacts.

## Try it live

> **You can use the app right now without installing anything:**
> **[https://benquist.shinyapps.io/bien-species-shinyapp/](https://benquist.shinyapps.io/bien-species-shinyapp/)**

To run it locally instead, see the [Install and run (R package)](#install-and-run-r-package) section below.

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
- Auto-prefetches BIEN count-only totals in the background (short timeout budget) so mapped-fraction denominators can appear without requiring an extra click when BIEN responds quickly.
- Can optionally fetch BIEN count-only totals and source-class fractions using the button **`Load BIEN total counts and source mix (slower)`**.
- Reports the active filter interpretation, the actual BIEN query strategy used, and key QA summaries.

### 3. Observation table

- Displays the returned occurrence records in searchable tabular form.
- Helps inspect provenance, taxonomic matching, and geographic structure directly.

### 4. Observation sources

- Summarizes the app-derived observation categories and provenance fields for source auditing.
- Helps users separate specimen, plot/survey, HumanObservation field records, and iNaturalist-heavy streams.

### 5. Traits and trait summary
- Shows raw trait records returned by BIEN.
- Summarizes trait availability by trait name, units, and number of records.

### 6. Range tab
- Displays BIEN range outputs and maps downloaded shapefiles when available.
- Useful for species where BIEN range artifacts are more complete than occurrence coordinates.

### 7. Reconciliation and error logging
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

## How observation types are parsed (citizen science, plot, GBIF, etc.)

The app creates a broad label called `observation_category` for each occurrence row so users can quickly understand where records are coming from.

### Fields used

The parser reads multiple BIEN provenance fields together:

- `observation_type`
- `datasource` / `data_source` / `collection` / `source`
- `dataset` / `dataset_name`
- `basisOfRecord` (Darwin Core, when present)

If one field is missing, the app still uses the others.

### Rule order (first match wins)

The app applies rules in a fixed order. This matters because one row can contain multiple keywords.

1. **Specimen / herbarium**
	Triggered by terms like specimen, herbarium, preserved, museum, or `PreservedSpecimen`.

2. **Plot / survey**
	Triggered by terms like plot, survey, inventory, monitoring.

3. **Citizen science (iNaturalist)**
	Triggered by iNaturalist-specific provenance text.

4. **Field observation (HumanObservation)**
	Triggered by Darwin Core `HumanObservation` (or equivalent text patterns with word boundaries).
	A specimen/museum guard is included to avoid mislabeling preserved collections as field observations.

5. **GBIF / other aggregator**
	Triggered by GBIF text when earlier rules do not match.

6. **Other / unknown**
	Used when none of the above patterns are detected.

### Why "GBIF" is separate from "citizen science"

GBIF is an aggregator that contains many source types (specimens, surveys, citizen science, and others).
So a row mentioning GBIF is not automatically treated as citizen science unless there is stronger evidence (for example, `HumanObservation` or iNaturalist provenance).

### Important interpretation notes

- These labels are practical interpretation categories, not formal taxonomic or occurrence standards.
- The logic is text-and-metadata based, so sparse provenance fields can still end up as `Other / unknown`.
- For methods-level detail, see `CODE_WORKFLOW_DOCUMENTATION.md`, which documents Darwin Core alignment and caveats.

## Filtering options

The sidebar includes controls to tailor the biological interpretation of returned records:

- **Use BIEN native vs introduced status** — if left on, BIEN native/introduced metadata is used in the current view; if turned off, records are shown regardless of introduced status.
- **Keep native records only and hide introduced records** — when enabled, the app requests the stricter native-only subset.
- **Use BIEN cultivated vs wild status** — if left on, BIEN cultivated metadata is used in the current view; if turned off, both cultivated and non-cultivated records can be shown.
- **Include cultivated records** — when enabled, cultivated records are allowed in the returned subset; when off, they are hidden.
- **Keep only BIEN geovalid coordinates** — restricts the view to BIEN-flagged geovalid points and hides flagged/non-geovalid coordinates.
- **Exclude field observation and citizen science records (HumanObservation + iNaturalist)** — when enabled, removes any occurrence rows whose derived `observation_category` is `Citizen science (iNaturalist)` or `Field observation (HumanObservation)` from the app sample before mapping. This gives a conservative view of specimen- and plot-based evidence only. **Caution**: the Darwin Core `HumanObservation` category encompasses not only crowdsourced observations but also expert naturalist field notes and other non-specimen field evidence. Turning this on removes all of them together.

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

When that warning appears, you can also click **`Retry BIEN connection (with backoff)`** in the sidebar. The app will retry the BIEN occurrence query with short exponential backoff delays before giving up.

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

## Install and run (R package)

The app is packaged so collaborators can install and launch it with two R commands:

```r
install.packages("BIENSpeciesShinyApp_0.1.0.tar.gz", repos = NULL, type = "source")
BIENSpeciesShinyApp::runApp()
```

### Build the source package tarball (maintainer step)

From the app root:

```bash
R CMD build .
```

This creates a file like `BIENSpeciesShinyApp_0.1.0.tar.gz`, which users install with `install.packages()`.

### First launch notes

- The app auto-installs missing CRAN dependencies it needs at runtime.
- First launch may take longer while those dependencies are installed.
- `BIENSpeciesShinyApp::runApp()` starts the bundled app directly from the installed package.

## Automated regression tests

This repo includes a deterministic regression suite that checks core app features against known baseline snapshots for three species with very different data volumes:

- `Abies bracteata` (low)
- `Pinus ponderosa` (medium)
- `Populus tremuloides` (high)

Run the suite from the app root:

```bash
Rscript tests/run_app_regression_tests.R
```

The suite verifies:

- baseline row counts for occurrence/trait/range snapshots
- occurrence categorization, source summaries, and coordinate QA outputs
- map-cap sampling behavior across strategies
- trait numeric parsing and trait summary generation
- range-table handling and downloaded shapefile loading
- reconciliation-table construction and helper-function behavior

If you intentionally refresh the `sample_data/*.csv` snapshots, regenerate the baseline manifest before re-running tests:

```bash
Rscript tests/update_species_baseline.R
```

### Copilot subagent

An explicit test subagent prompt is provided at `agents/test-agent.md`.
Persistent always-rule enforcement is provided at `agents/always-agent.md` with rules stored in `agents/always-rules.md`.

- Trigger it with `@test` to run `tests/run_app_regression_tests.R` and report pass/fail.
- Trigger `@always` to record new instructions flagged as always, enforce active always-rules on the current prompt, and rerun required checks when needed.
- If `Rscript: command not found` appears, install R and try the full path version above.
- If package installation for `sf` fails on macOS, install the Apple command line tools first and then retry.
- If BIEN returns a temporary connection-capacity error, use **`Retry BIEN connection (with backoff)`** to automatically retry a few times before running another manual query.

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

