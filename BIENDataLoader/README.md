<p align="center">
  <img src="www/bien.png" alt="BIEN logo" height="80">
</p>

<h1 align="center">BIEN Data Loader</h1>
<p align="center">
  Upload, validate, and export plant occurrence records in BIEN-ready format<br>
  <a href="https://benquist.shinyapps.io/bien-data-loader/">▶ Launch the app</a>
</p>

---

## What is this?

The **BIEN Data Loader** is a browser-based tool that walks you through preparing plant occurrence data for submission to the [Botanical Information and Ecology Network (BIEN)](https://biendata.org) database. No R experience required — the app handles field mapping, taxonomy reconciliation, coordinate QA, native-status checks, and export.

It accepts any CSV file with species observations and guides you through four steps:

```
1 • Upload & Merge  →  2 • Map Fields  →  3 • Stage & Validate  →  4 • Export
```

---

## Quick Start

**No installation needed.** Open the app in your browser:

> **https://benquist.shinyapps.io/bien-data-loader/**

The first load may take ~15 seconds on the free hosting tier. A spinner will appear while the app warms up.

---

## Step-by-Step Tutorial

### Step 1 — Upload & Merge

<img src="https://img.shields.io/badge/Tab-1%20%E2%80%A2%20Upload%20%26%20Merge-2f79b7?style=flat-square" alt="Tab 1">

When the app loads, it starts with built-in demo data (12 historical California observations + 6 plot metadata records). This is a good way to explore the full workflow before using your own data.

**To use your own data:**

1. Uncheck **"Use built-in demo data"**
2. Click **Browse** and select one or more `.csv` files
   - To select multiple files: `Command-click` (macOS) or `Ctrl-click` (Windows/Linux)
3. If you uploaded more than one file, choose which file is the **primary observation table** and which key column (e.g., `Plot_Name`) to use for merging
4. Click **Prepare Dataset ▶**

The right panel shows a preview of the merged table. Check that your rows and columns look correct before proceeding.

**What your CSV should contain:**

| Column type | Examples |
|---|---|
| Species name | `scientificName`, `species`, `taxon` |
| Coordinates | `decimalLatitude`, `lat`, `longitude`, `lon` |
| Collection date | `eventDate`, `date_collected`, `Date` |
| Geography | `country`, `stateProvince`, `county`, `locality` |
| Record identifier | `occurrenceID`, `catalogNumber` |
| Observer / collector | `recordedBy`, `observer`, `collector` |

Column names do not need to be exact — the app recognizes dozens of common synonyms and abbreviations automatically.

---

### Step 2 — Map Fields

<img src="https://img.shields.io/badge/Tab-2%20%E2%80%A2%20Map%20Fields-2f79b7?style=flat-square" alt="Tab 2">

The app suggests two mappings for each of your columns:

| Column | What it is |
|---|---|
| **DWC Term** | Darwin Core standard term (international biodiversity exchange format) |
| **BIEN Field** | The BIEN database staging field this maps to |

**How to review and adjust:**

1. The mapping table shows all your source columns with suggested targets
2. Click any cell in the `DWC Term` or `BIEN Field` column to edit it
3. Clear a cell to exclude a column from the output
4. When satisfied, click **Apply Mapping ▶**

The app will accept partial mappings — you do not need every field filled in. At minimum, map your species name, latitude, and longitude columns.

---

### Step 3 — Stage & Validate

<img src="https://img.shields.io/badge/Tab-3%20%E2%80%A2%20Stage%20%26%20Validate-2f79b7?style=flat-square" alt="Tab 3">

This tab runs quality checks and optional BIEN web services to standardize your data.

#### QC Summary

The left panel shows automatic checks on your staged records:

| Severity | Meaning |
|---|---|
| ✅ **PASS** | All records clear this check |
| ⚠️ **WARN** | Some records have issues but export is not blocked |
| 🔴 **BLOCK** | Critical issues that should be resolved before export |

Checks include: coordinate range validation, required field population, and date parseability across common formats.

#### BIEN Web Services

Four services standardize your data against BIEN reference databases. **Run them in order: TNRS → GNRS → GVS → NSR.**

| Service | What it does |
|---|---|
| **TNRS** — Taxonomic Name Resolution | Matches submitted species names to accepted names (WCVP/WFO), standardizes spelling and authorship, populates `scrubbed_*` taxonomy fields |
| **GNRS** — Geographic Name Resolution | Standardizes country, state/province, and county strings against reference geographies |
| **GVS** — Geo Validation Service | Flags records whose point coordinates appear to fall in an administrative centroid (`is_centroid`) |
| **NSR** — Native Status Resolution | Determines whether each species is native, introduced, or cultivated for the given country/state/county |

> **Cloud hosting note:** The in-app buttons contact external servers that may be blocked from cloud IPs (shinyapps.io runs on AWS). If a service times out after ~25 seconds, use the **Download validation script** button instead. Run the downloaded `.R` script locally in R, then upload the results CSV back into the app using the upload button beneath each service.

**Local script workflow (recommended for large datasets):**

```r
# Example for TNRS — the downloaded script follows this pattern
library(TNRS)
dat <- read.csv("my_staged_data.csv")
results <- TNRS(taxonomic_names = dat$scrubbed_species_binomial)
write.csv(results, "tnrs_results.csv", row.names = FALSE)
```

Then upload `tnrs_results.csv` in the app using **Upload TNRS results CSV**.

---

### Step 4 — Export

<img src="https://img.shields.io/badge/Tab-4%20%E2%80%A2%20Export-2f79b7?style=flat-square" alt="Tab 4">

Download your cleaned, validated data in one or more formats:

| Export | Contents |
|---|---|
| **BIEN Staging CSV** | All BIEN schema fields, populated by your data + web service results |
| **Darwin Core CSV** | DWC-standard fields only, suitable for GBIF or iDigBio submission |
| **QC Report CSV** | Per-field quality check results with pass/warn/block status |

Review the QC report and web service outputs (especially TNRS ambiguous matches and NSR native/introduced flags) before submitting to BIEN.

---

## BIEN Field Reference

The app maps your data to these BIEN staging schema fields:

### Taxonomy (populated by TNRS)
`scrubbed_species_binomial`, `scrubbed_family`, `scrubbed_genus`, `scrubbed_author`, `scrubbed_taxonomic_status`

### Coordinates
`latitude`, `longitude`, `is_centroid` (from GVS)

### Temporal
`date_collected`

### Dataset Provenance
`dataset`, `datasource`, `dataowner`, `collection_code`

### Geography (populated by GNRS)
`locality`, `country`, `state_province`, `county`, `plot_name`

### Record Identifiers
`occurrenceID`, `basisOfRecord`

### Native Status (populated by NSR)
`native_status`, `native_status_reason`, `native_status_country`, `native_status_state_province`, `native_status_county_parish`, `is_introduced`, `is_cultivated_observation`

### Verbatim / Elevation
`verbatimLocality`, `verbatimElevation`, `elevation_min`, `elevation_max`

---

## Demo Data

The app ships with two demo CSV files under `demo_data/` that illustrate a two-table workflow:

**`observations.csv`** — 12 historical California plant records (H.L. Mason field collections, 1910–1912):

```
occurrenceID, Plot_Name, scientificName, Date_Collected, Observer,
decimalLatitude, decimalLongitude, Family, Notes
```

**`plot_metadata.csv`** — Plot-level geography for joining:

```
Plot_Name, Country, State, County, Locality, Elevation_m
```

The join key is `Plot_Name`. This pattern — observations in one file, site/plot metadata in another — is typical of vegetation plot databases and field survey exports.

---

## Running Locally

If you prefer to run the app on your own machine:

```r
# Install dependencies (once)
install.packages(c("shiny", "DT", "httr", "jsonlite"))

# Run
shiny::runApp("path/to/BIENDataLoader")
```

The app requires no database connection or authentication to run locally. Web service buttons call Cloudflare Worker relay endpoints and will work from any IP.

---

## Repository Structure

```
BIENDataLoader/
├── app.R                  # Single-file Shiny app (UI + server)
├── demo_data/
│   ├── observations.csv   # Demo species occurrence records
│   └── plot_metadata.csv  # Demo plot geography metadata
├── www/
│   └── bien.png           # BIEN logo (served statically)
├── cf-workers/            # Cloudflare Worker relay source (TNRS/GNRS/GVS/NSR)
│   ├── tnrs/
│   ├── gnrs/
│   ├── gvs/
│   └── nsr/
└── deploy.R               # shinyapps.io deployment script
```

---

## Scientific Caveats

- **TNRS ambiguous matches** — When a name matches multiple accepted taxa, TNRS returns the best candidate with a score. Review low-score matches before submission.
- **NSR native/introduced status** — Native status is context-dependent and reflects current reference data. Cultivated records (`is_cultivated_observation = 1`) should be clearly distinguished from wild occurrences.
- **GVS centroid flags** — `is_centroid = 1` indicates a coordinate that appears to be an administrative centroid rather than a precise location. These records have reduced spatial precision.
- **BIEN staging fields** — Fields prefixed `scrubbed_*` are populated by TNRS and should not be hand-edited after reconciliation.

---

## About BIEN

The [Botanical Information and Ecology Network](https://biendata.org) integrates plant occurrence, trait, and range data for the Western Hemisphere. BIEN data are used for conservation assessments, biodiversity modeling, and macroecological research.

- BIEN R package: [`BIEN`](https://cran.r-project.org/package=BIEN)
- BIEN data portal: [biendata.org](https://biendata.org)
- Enquist Lab: [enquistlab.org](https://enquistlab.org)

---

## License

MIT License. See `LICENSE` if present, or contact the repository owner.
