<p align="center">
	<img src="www/bien.png" alt="BIEN logo" height="72">
</p>

<h2 align="center">BIEN Traits Shiny App</h2>

<p align="center">
	Query · Map · Cite · Export BIEN trait observations<br><br>
	<a href="https://benquist.shinyapps.io/bien-traits-shinyapp/"><strong>▶ Launch App</strong></a>
	&nbsp;|&nbsp;
	<a href="#step-by-step-tutorial">Tutorial</a>
	&nbsp;|&nbsp;
	<a href="#features">Features</a>
	&nbsp;|&nbsp;
	<a href="https://github.com/benquist/BIEN_Trait_Shiny_App">GitHub</a>
	&nbsp;|&nbsp;
	<a href="https://github.com/benquist">Author</a>
</p>

---

## About BIEN

The [Botanical Information and Ecology Network](https://biendata.org) (BIEN) is a large, collaborative biodiversity data infrastructure that integrates plant observations, taxonomy, geography, and traits across the Western Hemisphere. BIEN links information from herbaria, plot surveys, experiments, checklists, and trait databases into a unified, queryable system designed for ecological, biogeographic, and conservation research. Its taxonomic backbone applies name reconciliation across sources, so records from different databases can be compared and combined in a consistent framework.

Plant trait data are central to functional ecology. Attributes such as leaf area, wood density, plant height, seed mass, and stem conduit diameter capture how species acquire resources, tolerate stress, and compete with neighbors. These measurements underpin community assembly analyses, macroecological scaling relationships, trait-climate models, and biodiversity assessments. Trait data also feed directly into biogeographic and conservation workflows where functional identity — not just species occurrence — is the relevant currency.

The BIEN Traits Shiny App provides a focused, interactive interface for extracting and evaluating trait observations from the BIEN database. The app is designed to support the full workflow from initial coverage assessment through data extraction, geographic inspection, provenance review, and reproducible export — without requiring users to write R code from scratch.

---

## What This App Does

The **BIEN Traits Shiny App** lets you query plant trait observations from BIEN by species, genus, or family, then inspect, map, and export the results.

**Capabilities:**

- Query trait records for a single species, a pasted or uploaded list of species, an entire genus, or a plant family
- Select specific BIEN trait variables and preview record counts before committing to a large query
- Inspect an observation-level records table with taxonomic, trait, geographic, and provenance fields
- View georeferenced trait observations on an interactive Leaflet map
- Review source-level provenance and citation fields for methods transparency
- Download results as raw CSV, a JSON query manifest, and a reproducible R script that replicates the exact query

---

## Who Is This For

| User type | Typical need |
|---|---|
| **Ecologist** | Build a species-level trait matrix for community or functional diversity analyses |
| **Macroecologist** | Screen trait coverage across a clade before committing to model runs |
| **Conservation practitioner** | Review trait information for focal taxa quickly, without writing code |
| **R programmer** | Prototype a BIEN query interactively, then export the R script for integration into a pipeline |
| **Instructor / student** | Explore real plant trait data with a point-and-click interface in classroom or lab settings |

---

## Step-by-Step Tutorial

### Step 1 — Choose Your Query Mode

The app supports four query modes, selectable from the input panel:

| Mode | When to use | Example input |
|---|---|---|
| **Single species** | One focal taxon | `Pinus ponderosa` |
| **Multiple species** | A known species list (paste or upload) | `Abies concolor`, `Quercus agrifolia`, `Populus tremuloides`, `Pinus ponderosa` |
| **Genus** | Coverage screening across an entire genus | `Quercus` |
| **Family** | Broad feasibility check before narrowing | `Pinaceae` |

For **multiple species**, you can paste names one per line into the text area or upload a CSV file with one species name per row. If the first row looks like a header (contains no spaces in the typical name pattern), it is treated as a header and skipped.

---

### Step 2 — Select Traits to Query

After choosing your taxon scope, use the trait selector to choose which BIEN trait variables to include. You can select one or several traits.

**Example BIEN trait names:**

- `whole plant height`
- `leaf area`
- `wood density`
- `seed mass`
- `stem conduit diameter`

Leaving the trait selector empty (if the mode supports it) returns all available traits for the queried taxon scope, which may produce a large result set.

---

### Step 3 — Review Scope and Coverage Before Querying

Before running the query, the app displays a **scope preview** that shows:

- Estimated record count for the current taxon + trait combination
- Number of contributing data sources
- Unit consistency notes where applicable

Use this preview to assess whether the query scope is manageable. If estimated counts are very large (tens of thousands of records), consider narrowing to fewer traits, a single species, or a more specific taxonomic scope before proceeding.

---

### Step 4 — Run the Query

Click the **"Query BIEN"** button to submit the query.

- A spinner indicates that the query is running against the BIEN database.
- **Single species queries** typically complete in a few seconds.
- **Large genus or family queries** may take up to a minute or more depending on record volume and database load.

Do not navigate away or resubmit while the spinner is active.

---

### Step 5 — Inspect the Records Table

After the query completes, the **Records** tab shows an observation-level table. Each row is one trait measurement from one individual or plot record.

**Key columns:**

| Column | Description | Example |
|---|---|---|
| `scrubbed_species_binomial` | BIEN-reconciled taxon name | `Pinus ponderosa` |
| `trait` | BIEN trait variable label | `whole plant height` |
| `trait_value` | Reported measurement | `22.5` |
| `unit` | Measurement unit | `m` |
| `latitude` | Decimal latitude (if available) | `36.74` |
| `longitude` | Decimal longitude (if available) | `-119.82` |
| `datasource_id` | BIEN data source identifier | `TRY` |
| `source_citation` | Citation string for the originating source | `Kattge et al. 2020` |

**Example rows (illustrative):**

| scrubbed_species_binomial | trait | trait_value | unit | latitude | longitude | datasource_id |
|---|---|---|---|---|---|---|
| Pinus ponderosa | whole plant height | 22.5 | m | 36.74 | -119.82 | TRY |
| Pinus ponderosa | wood density | 0.51 | g/cm³ | NA | NA | TRY |
| Pinus ponderosa | leaf area | 18.2 | cm² | 39.10 | -120.45 | BIEN |

---

### Step 6 — View the Map

The **Map** tab shows all records that have both latitude and longitude coordinates plotted on an interactive Leaflet map.

- Click any marker to open a popup with the species name, trait, and trait value for that record.
- Use the map to check the geographic distribution of observations and identify potential spatial outliers before downstream analyses.
- Records without coordinates are excluded from the map but remain in the records table.

---

### Step 7 — Review Provenance

The **Provenance** tab shows source-level citation fields for the records returned by the query.

- Fields include `datasource_id`, `source_citation`, and where available, `url_source`.
- Use these fields when writing methods sections or data appendices in manuscripts — they identify the original databases and publications that contributed each record.
- Plot-based records may link to additional plot metadata via the `url_source` field.

---

### Step 8 — Download Outputs

After reviewing results, download the outputs using the buttons in the app:

| Download | Format | Contents |
|---|---|---|
| **Download Data as CSV** | `.csv` | Full observation-level records table |
| **Download Manifest** | `.json` | JSON manifest describing the query parameters and metadata |
| **Download R Script** | `.R` | Reproducible R code that replicates the exact BIEN query |

The **R script** contains the BIEN package function call that matches your query mode, taxon, traits, and record limit. For example, a single-species query for *Pinus ponderosa* produces a script like:

```r
# Reproducible BIEN query — generated by BIEN Traits Shiny App
# Generated: 2026-04-26 14:30:00 UTC

library(BIEN)
library(dplyr)

dat <- BIEN::BIEN_trait_species(
  species    = "Pinus ponderosa",
  all.taxonomy  = TRUE,
  source.citation = TRUE,
  limit      = 5000
)
```

A genus-level query uses `BIEN::BIEN_trait_genus(genus = "Quercus", ...)`, and a family query uses `BIEN::BIEN_trait_family(family = "Pinaceae", ...)`.

---

## Search Examples

### Single species

**Type:** `Pinus ponderosa`
**Returns:** Records for all selected traits (e.g., wood density, whole plant height, leaf area) for that species only.
**Use when:** You have one focal taxon and want a clean, focused pull.

---

### Multiple species list

**Paste or upload:**

```text
Abies concolor
Pinus ponderosa
Quercus agrifolia
Populus tremuloides
```

**Returns:** Records for all four species combined, filtered by selected traits.
**Use when:** You are building a trait matrix for a known species set, e.g., from a community survey.

---

### Genus query

**Type:** `Quercus`
**Returns:** Records across all oak species present in BIEN for the selected traits.
**Use when:** You want to evaluate trait coverage across an entire clade before deciding which species to include in an analysis.

---

### Family query

**Type:** `Pinaceae`
**Returns:** Records spanning all BIEN-covered species in the pine family.
**Use when:** You need a broad feasibility screen — how much data exists for a family across selected traits — before narrowing scope to a genus or species list.

---

## Expected Output Examples

### Records table (3 illustrative rows)

| scrubbed_species_binomial | trait | trait_value | unit |
|---|---|---|---|
| Pinus ponderosa | whole plant height | 22.5 | m |
| Pinus ponderosa | wood density | 0.51 | g/cm³ |
| Pinus ponderosa | leaf area | 18.2 | cm² |

### Summary table (columns defined)

| Column | Description |
|---|---|
| `taxon` | Species (or taxon scope) included in the summary |
| `trait` | Trait variable summarized |
| `n_records` | Count of records in the group |
| `n_sources` | Number of distinct contributing data sources |
| `min_value` | Minimum observed trait value |
| `max_value` | Maximum observed trait value |

---

## Scientific Caveats

- **Measurement protocols vary.** Trait values in BIEN come from multiple databases (e.g., TRY, BIEN field plots) that may differ in measurement protocol, life stage sampled, and reporting standard. Do not assume values are directly comparable without checking source metadata.
- **Coordinate availability varies.** Not all records include geographic coordinates. Map coverage reflects only the georeferenced subset. The records table contains all returned observations including those without coordinates.
- **BIEN is updated periodically.** Query results may differ from values reported in older publications that used earlier BIEN versions. Record the query date when citing results.
- **`scrubbed_species_binomial` reflects BIEN taxonomy.** Names are reconciled against the BIEN taxonomic backbone. If you are working with taxon names from another taxonomy, verify alignment before merging with BIEN outputs.

---

## Features

- Species input by single name, pasted list, or uploaded CSV
- Genus and family query modes for clade-level coverage screening
- Trait selector with scope preview before running large queries
- Observation-level records table with taxonomic, trait, geographic, and provenance fields
- Interactive Leaflet map for georeferenced records
- Provenance tab with source-level citation fields
- Export bundle: raw CSV, JSON query manifest, reproducible R script

---

## Run Locally

1. **Install R and RStudio** if not already installed: [r-project.org](https://www.r-project.org) · [posit.co/rstudio](https://posit.co/downloads/)

2. **Clone or download the repository:**

   ```bash
   git clone https://github.com/benquist/BIEN_Trait_Shiny_App.git
   ```

3. **Open RStudio** and set the working directory to the cloned folder:

   ```r
   setwd("path/to/BIEN_Trait_Shiny_App")
   ```

4. **Install required packages:**

   ```r
   install.packages(c("shiny", "BIEN", "dplyr", "tidyr", "stringr", "DT", "jsonlite", "leaflet"))
   ```

5. **Run the app:**

   ```r
   shiny::runApp(".")
   ```

---

## Repository

- App repository: [github.com/benquist/BIEN_Trait_Shiny_App](https://github.com/benquist/BIEN_Trait_Shiny_App)
- Author profile: [github.com/benquist](https://github.com/benquist)

---

## Deploy

Use `deploy.R` in the project folder after configuring your `rsconnect` account credentials. The production app is hosted at:

> **[https://benquist.shinyapps.io/bien-traits-shinyapp/](https://benquist.shinyapps.io/bien-traits-shinyapp/)**

<p align="center">
	Query · Map · Cite · Export BIEN trait observations<br><br>
	<a href="https://benquist.shinyapps.io/bien-traits-shinyapp/"><strong>▶ Launch the App</strong></a>
	&nbsp;|&nbsp;
	<a href="#features">Features</a>
	&nbsp;|&nbsp;
	<a href="#run-locally">Run Locally</a>
	&nbsp;|&nbsp;
	<a href="#deploy-to-shinyappsio">Deploy</a>
</p>

---

## About BIEN

The [Botanical Information and Ecology Network](https://biendata.org) (BIEN) is a large, collaborative biodiversity data infrastructure that integrates plant observations, taxonomy, geography, and traits across the Western Hemisphere. BIEN links information from herbaria, plots, experiments, checklists, and trait sources into a queryable system designed for ecological, biogeographic, and conservation research.

The BIEN Traits Shiny App provides an interface focused on **trait observations** and **reproducible extraction**. Instead of requiring users to write R code first, the app supports a practical workflow where users can find records, evaluate data coverage, inspect provenance, and export analysis-ready tables.

Trait data matters because plant function is often inferred from measurable attributes such as height, wood density, SLA, seed mass, or leaf chemistry. These data support:

- Comparative ecology across taxa and regions
- Macroecological and biogeographic modeling
- Community assembly and functional diversity analyses
- Trait-environment and trait-climate workflows
- Transparent evidence trails for synthesis and publication

The app is designed to keep those workflows transparent by exposing record-level metadata, source fields, and citation outputs alongside the trait values.

---

## What Is This?

The **BIEN Traits Shiny App** is an interactive tool for trait lookup and synthesis. It supports:

- Querying one species or many species at once
- Choosing BIEN trait variables and reviewing coverage
- Exploring mapped trait observations when coordinates are available
- Inspecting observation-level provenance and citation fields
- Downloading raw observations, summary tables, citation tables, and reproducible R query code

Primary deployment URL:

> ### [▶ https://benquist.shinyapps.io/bien-traits-shinyapp/](https://benquist.shinyapps.io/bien-traits-shinyapp/)

---

## Practical Use Cases

The app is intended for multiple user types and real workflows:

- Ecologists building species-level trait matrices for community analyses
- Macroecology researchers screening trait coverage before larger data pulls
- Conservation practitioners reviewing trait information for focal taxa
- Instructors and students using reproducible examples in classroom settings
- Data curators validating provenance and citation traceability for downstream repositories

Common workflow patterns include:

- Rapid exploratory pull: query a small species list, inspect fields, export CSV
- Coverage-first planning: test target clades and trait variables before committing to model runs
- Provenance-first review: filter candidate records using source and citation metadata
- Reporting pipeline support: export tables plus query script for reproducible appendices

---

## Search Patterns And Examples

The app supports taxonomic input and trait-oriented filtering workflows. The examples below describe typical usage patterns.

### 1) Single species

Use when you need a focused pull for one taxon.

- Example query: `Pinus ponderosa`
- Typical workflow: enter species name -> choose trait variables -> run query -> inspect records and map -> export

### 2) Multiple species list

Use when assembling a trait matrix for a known species set.

- Example list:

```text
Abies concolor
Pinus ponderosa
Quercus agrifolia
Populus tremuloides
```

- Input methods: paste list directly or upload a CSV of names

### 3) Genus-level exploration

Use when evaluating coverage for a clade before narrowing to species.

- Example genus: `Quercus`
- Typical goal: identify which species in the genus return trait records for selected variables

### 4) Family-level exploration

Use for broad screening and planning analyses.

- Example family: `Asteraceae`
- Typical goal: estimate whether enough observations exist for the chosen trait set

### 5) Trait-focused workflow

Use when the trait variables drive species choice, rather than the reverse.

- Example intent: retrieve records emphasizing traits such as wood density and plant height
- Typical workflow: start with target taxa scope -> choose focal traits -> inspect completeness in returned records -> export raw + summary outputs

---

## Features

- Species input by text list, pasted names, or uploaded CSV
- Trait selection and coverage preview before running larger pulls
- Observation table with key metadata fields used for provenance review
- Leaflet-based map of trait points for records with coordinates
- Export bundle for downstream workflows (data tables + query script)
- In-app help content for interpretation and workflow guidance

---

## What You Can Expect In App Outputs

The app returns both observation-level and synthesized outputs so users can move from inspection to analysis without losing provenance.

### Records table (observation-level)

The main records table is designed for traceable data review. Exact columns may vary by query and source availability, but users should expect fields like the following:

| Column | Meaning |
|---|---|
| `scrubbed_species_binomial` | Standardized taxon name used in BIEN outputs |
| `trait` | Trait variable label for the observation |
| `value` | Reported trait value |
| `unit` | Measurement unit where available |
| `latitude` / `longitude` | Coordinates for mappable records |
| `country` | Country associated with the record |
| `datasource_id` | BIEN data source identifier |
| `source_citation` | Citation text for provenance tracing |

### Summary outputs

Summary tables support quick diagnostics and reporting. Depending on the query scope, users may see fields such as:

| Summary field | Description |
|---|---|
| `taxon` | Species (or other taxon scope) included in the summary |
| `trait` | Trait summarized |
| `n_records` | Count of records in the summarized group |
| `n_distinct_sources` | Number of distinct contributing sources |
| `min_value` / `max_value` | Range of observed trait values |
| `mean_value` | Arithmetic mean where appropriate |

### Map view

- Shows records with coordinate information
- Supports geographic inspection of where trait observations are available
- Helps identify obvious spatial outliers before downstream analysis

### Provenance and citation outputs

- Record-level source and citation fields are preserved in exported outputs when available
- Citation tables can be used directly in methods supplements or data appendices
- Query script export supports reproducible reruns of the same pull logic

### Downloadable artifacts

Export bundle includes:

- Raw data CSV
- JSON manifest
- Reproducible R query script

---

## Run Locally

```r
shiny::runApp(".")
```

Required R packages:

- shiny
- BIEN
- dplyr
- stringr
- tidyr
- leaflet
- DT
- jsonlite

---

## Deploy to shinyapps.io

Use `deploy.R` in this folder after configuring your `rsconnect` account.

Production URL:

> ### [▶ https://benquist.shinyapps.io/bien-traits-shinyapp/](https://benquist.shinyapps.io/bien-traits-shinyapp/)
