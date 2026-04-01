# BIEN Species Shiny App — Code and Workflow Documentation

This document explains the R/Shiny workflow in `BIEN Shiny App/app.R` in a form intended to be readable by biodiversity scientists, ecologists, taxonomists, and documentation/review agents.

---

## 1. Purpose and biological question

This app is an **interpretation-first species exploration tool** for BIEN data. Its goal is to help users inspect what evidence exists for a focal species **before** ecological modeling, conservation screening, or broader synthesis.

It is designed to answer questions such as:

- Are there usable occurrence records for the species?
- Are the mapped points mostly native, introduced, cultivated, or uncertain?
- Which observation record types are being returned (specimen, plot/survey, citizen science, etc.)?
- Are there trait measurements, and are those traits continuous or categorical?
- Does BIEN provide a range product even when the current occurrence response lacks mappable coordinates?

---

## 2. Taxon scope and taxonomic backbone

- The app takes a **verbatim scientific name** entered by the user.
- BIEN is the immediate taxonomic/data backbone used for retrieval.
- The app does **not** assume the submitted name is automatically accepted; it records the input and the BIEN-returned match in the reconciliation view.
- Taxonomic matching details are summarized by `build_reconciliation_table()`.

### Important interpretation note
A BIEN-returned match should be treated as the taxonomic concept returned by BIEN for the current query, **not** as a final nomenclatural judgment for all purposes.

### Recommended taxonomy/provenance fields for audit-ready use
For more formal biodiversity-informatics workflows, documentation should preserve:

- input name verbatim
- matched name returned by BIEN
- authorship string when available
- persistent taxon ID when available
- match method and confidence
- query/access date
- BIEN package version or backend release context

---

## 3. Data sources and provenance

The app retrieves three major evidence types:

| Evidence type | BIEN call | Purpose |
|---|---|---|
| Occurrence records | `BIEN_occurrence_species()` | Map points, provenance fields, native/introduced interpretation |
| Trait records | `BIEN_trait_species()` | Raw trait values and trait summaries |
| Range artifacts | `BIEN_ranges_species()` | Spatial range products when available |

Source/provenance fields preserved where available include:

- `datasource`
- `dataset`
- `observation_type`
- `native_status`
- `is_introduced`
- `family` / `scrubbed_family`

The reconciliation table also records query time and BIEN package version.

---

## 4. Query settings and filters applied

The sidebar exposes biologically important settings:

- **Use BIEN `is_introduced` filter**
- **When used, keep native records only**
- **Use BIEN `is_cultivated` filter**
- **When used, include cultivated records**
- **Only geovalid coordinates**
- occurrence and trait record caps
- random sampling for displayed records
- map-thinning behavior when there are many points

### Recommended interpretation presets

#### Highest-quality native screening
Use:
- `is_introduced` filter = on
- native only = on
- `is_cultivated` filter = on
- include cultivated = off
- geovalid = on

This gives the most conservative view for native-distribution reconnaissance.

#### Broader reconnaissance / all available evidence
Use:
- `is_introduced` filter = off or native only = off
- `is_cultivated` filter = off or include cultivated = on
- geovalid = on or off depending on whether you want to inspect suspect coordinates

This is useful for horticultural, invasion, or data-discovery questions.

---

## 5. Workflow overview

The main workflow in `app.R` is:

1. User enters a species name and clicks **Query BIEN**.
2. `query_occurrence_with_fallback()` attempts a strict occurrence query first, then relaxed fallback queries if needed.
3. `categorize_observation_records()` groups records into broad classes such as specimen/herbarium, plot/survey, and citizen science.
4. `prepare_occurrences()` performs coordinate QA, duplicate thinning, and optional map subsetting for responsiveness.
5. Trait records are retrieved and summarized in both tabular and graphical form.
6. Range products are queried and any downloaded shapefiles are loaded with `read_downloaded_range_sf()`.
7. The app reports reconciliation details, QA losses, map status, and range status in the Overview and Reconciliation tabs.

---

## 6. Key functions in `app.R`

| Function | Role in workflow |
|---|---|
| `safe_bien_call()` | Runs BIEN calls with elapsed-time limits and catches errors |
| `safe_bien_retry()` | Retries selected BIEN calls in a controlled way |
| `query_occurrence_with_fallback()` | Queries occurrence records using strict and fallback settings |
| `categorize_observation_records()` | Converts raw BIEN source fields into scientist-readable record categories |
| `prepare_occurrences()` | Filters invalid coordinates, removes duplicate point locations, and caps map load |
| `summarize_coordinate_quality()` | Reports coordinate validity and QA losses in the overview text |
| `prepare_trait_visual_data()` | Separates continuous from categorical trait values for graphical summaries |
| `read_downloaded_range_sf()` | Loads BIEN range shapefiles when they are available |
| `build_reconciliation_table()` | Records input name, matched name, query status, and timing metadata |

---

## 7. Occurrence data and coordinate QA

The app treats occurrence mapping as a QA-sensitive step.

### What happens
- non-numeric, missing, or out-of-range coordinates are removed
- duplicate point locations are thinned
- if too many valid points remain, only a subset is rendered for responsiveness
- if there are no usable coordinates but a BIEN range artifact exists, the range polygon is shown instead

### Important caveat
A missing point map does **not** necessarily mean there are no occurrence records. It may mean that BIEN returned rows without usable coordinates in the current response.

---

## 8. Native / introduced / cultivated interpretation

These fields are useful but should be interpreted cautiously:

- `native_status` and `is_introduced` are informative flags, not absolute truth for every geography or taxon.
- `is_cultivated` is useful for separating likely horticultural or planted records from wild/native interpretation.
- The best settings depend on the biological question, so the app reports the active settings and mapped-point summaries directly in the Overview.

---

## 9. Trait data, units, and harmonization

Trait records are kept separate from occurrence records.

### Trait handling rules
- If a trait has sufficiently numeric values, it is treated as **continuous** and summarized with a mean and range.
- Otherwise, it is treated as **categorical** and summarized using the modal value.
- Units are displayed when BIEN provides them.

### Caution
Trait values should not be compared across sources or merged analytically unless units and measurement context are compatible.

---

## 10. Range products and caveats

The Range tab shows BIEN-returned range information and maps downloaded shapefiles if present.

These products are useful for context, but they should **not** be interpreted as direct proof of:

- current occupancy
- abundance
- native-only distribution
- survey completeness

Range layers are supporting artifacts and must be interpreted alongside occurrence evidence and taxonomic context.

---

## 11. Reproducibility details

### Main run command
```bash
cd "/Users/brianjenquist/VSCode/BIEN Shiny App"
/usr/local/bin/Rscript -e 'shiny::runApp(".")'
```

### Core packages
- `shiny`
- `BIEN`
- `dplyr`
- `stringr`
- `leaflet`
- `DT`
- `sf`

### Reproducibility notes
- Query results depend on the live BIEN service and package version.
- If random sampling is enabled, the displayed subset of records may vary between runs.
- For fully reproducible sampling behavior, set a seed before launch in a controlled script or analysis context.

---

## 12. Known limitations and interpretation guardrails

- BIEN schemas can vary among species and query contexts.
- Common or widespread species may still be slow if upstream services are busy.
- Some returned rows lack usable coordinates even when occurrence evidence exists.
- Trait records may be sparse, categorical, or unit-inconsistent.
- Spatial, temporal, and collector sampling bias can strongly influence the apparent pattern of occurrences and traits.
- The app is meant for **exploratory evidence review**, not formal taxonomic revision or publication-ready range modeling.

---

## 13. Suggested agent roles for this project

Two custom agents support this documentation workflow:

- `r-code-documenter` — writes scientist-readable R code and workflow documentation
- `biodiversity-science-guard` — reviews code and documentation against biodiversity, ecology, and taxonomy norms

These agents are intended to keep future edits scientifically legible, provenance-aware, and ecologically cautious.
