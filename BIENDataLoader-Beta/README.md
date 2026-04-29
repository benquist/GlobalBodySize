<p align="center">
  <img src="www/bien.png" alt="BIEN logo" height="72">
</p>

<h2 align="center">BIEN Data Loader</h2>

<p align="center">
  Upload · Validate · Export plant occurrence data for BIEN submission<br><br>
  <a href="https://benquist.shinyapps.io/bien-data-loader/"><strong>▶ Launch the App</strong></a>
  &nbsp;|&nbsp;
  <a href="https://github.com/benquist/BIEN_Data_Loader"><strong>GitHub Repo</strong></a>
  &nbsp;|&nbsp;
  <a href="https://github.com/benquist"><strong>@benquist</strong></a>
  &nbsp;|&nbsp;
  <a href="#step-by-step-tutorial">Tutorial</a>
  &nbsp;|&nbsp;
  <a href="#what-output-looks-like">Output Examples</a>
  &nbsp;|&nbsp;
  <a href="#operational-caveats">Operational Caveats</a>
  &nbsp;|&nbsp;
  <a href="#about-bien">About BIEN</a>
</p>

---

## About BIEN

The [Botanical Information and Ecology Network](https://biendata.org) (BIEN) integrates plant occurrence, trait, and range data across the Western Hemisphere. As of 2024, BIEN holds approximately **160 million georeferenced plant occurrence records** spanning herbarium specimens, vegetation plots, and field surveys.

BIEN data power:
- **IUCN range assessments** — modeled range maps for thousands of Western Hemisphere plant species
- **Species distribution models** — climate-change vulnerability and habitat-suitability analyses
- **Macroecological research** — range-size distributions, latitudinal diversity gradients, trait–climate relationships
- **Conservation gap analyses** — identifying taxonomically or spatially undersampled regions

Submitting your data to BIEN makes it part of a curated, citable community resource with persistent dataset identifiers. For the BIEN data infrastructure, see [Maitner et al. 2018 (Global Ecology & Biogeography)](https://doi.org/10.1111/geb.12861).

| Resource | Link |
|---|---|
| BIEN data portal | [biendata.org](https://biendata.org) |
| BIEN R package | [`BIEN` on CRAN](https://cran.r-project.org/package=BIEN) |
| Enquist Lab | [enquistlab.org](https://enquistlab.org) |

---

## Repo And Author

| Item | Link |
|---|---|
| BIEN Data Loader repository | [github.com/benquist/BIEN_Data_Loader](https://github.com/benquist/BIEN_Data_Loader) |
| Author profile | [github.com/benquist](https://github.com/benquist) |

---

## What Is This?

The **BIEN Data Loader** is a browser-based tool that prepares plant occurrence data for submission to BIEN. It is designed for:

- **Herbarium curators** digitizing historical voucher collections
- **Vegetation ecologists** contributing plot-based presence or abundance records
- **Field botanists** submitting georeferenced observation datasets
- **Citizen science curators** cleaning iNaturalist or similar exports before formal archiving
- **Long-term resurvey programs** integrating historical and modern collection records

No R experience required. The app handles field mapping, taxonomy reconciliation (TNRS), coordinate QA (GVS), native/introduced status checking (NSR), and export in BIEN staging or Darwin Core format.

---

## Who This Is For

- **Herbarium teams** migrating specimen spreadsheets into BIEN-compatible tables
- **Vegetation plot programs** joining observation and plot metadata files before staging
- **Field ecology labs** running taxonomic and geospatial QA prior to archival submission
- **Data curators** preparing dual-output exports (BIEN staging + Darwin Core)
- **Collaborative projects** that need reproducible TNRS/GNRS/GVS/NSR processing records

---

## Quick Start

**No installation needed.** Open the app in your browser:

> ### [▶ https://benquist.shinyapps.io/bien-data-loader/](https://benquist.shinyapps.io/bien-data-loader/)

The first load may take ~15 seconds on the free hosting tier. A spinner will appear while the app warms up.

---

## How It Works

**① Upload & Merge** → **② Map Fields** → **③ Stage & Validate** → **④ Export**

The app guides each step interactively. BIEN web services (TNRS, GNRS, GVS, NSR) can run in the browser or via downloadable R scripts for large datasets. In hosted/in-app mode, TNRS and NSR are intentionally capped to the first 20 unique inputs, so use the local scripts for larger runs.

---

## Running Locally

If the hosted app is slow or you have a large dataset, run the app on your own machine — it is faster and the web service scripts work from any IP:

```r
# Install dependencies (once)
install.packages(c("shiny", "DT", "httr", "jsonlite"))

# Run
shiny::runApp("path/to/BIENDataLoader")
```

The app requires no database connection or authentication. Web service buttons call Cloudflare Worker relay endpoints.

---

## Step-by-Step Tutorial

### 🗂 Step 1 — Upload & Merge

When the app loads it starts with **built-in demo data** (12 historical California observations + 6 plot metadata records) — a good way to explore the full workflow before loading your own files.

**Do this exactly:**

1. Uncheck **Use built-in demo data**.
2. Click **Browse** and select one or more `.csv` files.
3. If uploading multiple files:
  1. Pick the **primary observation table**.
  2. Pick a **join key** that exists in both files (for example `Plot_Name`).
4. Click **Prepare Dataset ▶**.
5. Confirm row count and key columns in preview before moving on.

**Troubleshooting:**

- If row count is unexpectedly low after merge, verify join key spelling, case, and whitespace consistency.
- If all geography columns become blank after merge, you likely selected the wrong primary table.
- If upload appears stalled in hosted mode, wait for warm-up and retry once; local run is more stable for large files.

#### Example A: Single-file upload

Input file (`field_obs.csv`):

| occurrenceID | scientificName | decimalLatitude | decimalLongitude | eventDate | country | stateProvince |
|---|---|---:|---:|---|---|---|
| obs-001 | Quercus agrifolia | 34.1212 | -118.3321 | 2021-04-18 | United States | California |

Expected Step 1 output:

- One prepared table with same row count as input.
- Columns preserved for mapping in Step 2.

#### Example B: Multi-file merge with join key

`observations.csv`:

| occurrenceID | scientificName | Plot_Name | decimalLatitude | decimalLongitude |
|---|---|---|---:|---:|
| obs-100 | Pinus ponderosa | Plot_A | 39.5001 | -121.2004 |
| obs-101 | Abies bracteata | Plot_B | 35.3210 | -120.1230 |

`plot_metadata.csv`:

| Plot_Name | Country | State | County | Locality |
|---|---|---|---|---|
| Plot_A | United States | California | Butte | Ridge plot A |
| Plot_B | United States | California | San Luis Obispo | Santa Lucia Range |

Merge settings:

- Primary table: `observations.csv`
- Join key: `Plot_Name`

Expected Step 1 output:

- 2 merged rows
- Geography columns attached from metadata file

**What your CSV should contain:**

| Column type | Recognized names (any of these work) |
|---|---|
| Species name | `scientificName`, `species`, `taxon`, `name` |
| Coordinates | `decimalLatitude`, `lat`, `longitude`, `lon` |
| Collection date | `eventDate`, `date_collected`, `Date`, `collection_date` |
| Geography | `country`, `stateProvince`, `state`, `county`, `locality` |
| Record identifier | `occurrenceID`, `catalogNumber`, `voucher` |
| Observer / collector | `recordedBy`, `observer`, `collector`, `field_crew` |

Column names do not need to be exact — the app recognizes dozens of common synonyms.

> **Coordinate requirement:** The app expects coordinates in **WGS84 decimal degrees (EPSG:4326)** and only validates numeric latitude/longitude ranges. Convert projected coordinates or degree-minute-second values to WGS84 decimal degrees before upload.

**About the demo data:**
The demo observations are drawn from H.L. Mason's 1910–1912 California field surveys — among the earliest systematic botanical collections of California's coastal ranges (Santa Lucia Range, San Rafael Mountains). This two-table structure (observations joined to plot metadata on `Plot_Name`) is typical of vegetation plot databases, NEON plot exports, VegBank submissions, and long-term resurvey programs.

---

### 🔗 Step 2 — Map Fields

The app suggests two mappings for each of your columns:

| Column | What it means |
|---|---|
| **DWC Term** | Darwin Core standard term (international biodiversity exchange standard used by GBIF, iDigBio) |
| **BIEN Field** | The BIEN database staging schema field |

**Do this exactly:**

1. Review auto-suggested mappings.
2. Edit `DWC Term` and/or `BIEN Field` cells where needed.
3. Clear mapping cells for columns you do not want exported.
4. Click **Apply Mapping ▶**.

**Troubleshooting:**

- If a species column is not recognized, map it manually to a species name field before running TNRS.
- If date parsing warnings appear later, remap date column to `eventDate` or `date_collected` and inspect format consistency.
- If no Darwin Core file appears in Step 4, verify at least some columns were assigned DWC terms.

#### Step 2 mapping example

| Input column | DWC Term | BIEN Field |
|---|---|---|
| scientificName | scientificName | name_submitted |
| decimalLatitude | decimalLatitude | latitude |
| decimalLongitude | decimalLongitude | longitude |
| eventDate | eventDate | date_collected |
| Plot_Name | locationID | plot_name |

Expected Step 2 output:

- Mapping table saved in app state.
- Staging build in Step 3 uses these mapped fields.

Partial mappings are accepted. At minimum, map your **species name**, **latitude**, and **longitude** columns. Genus-only names, morphospecies labels, and names with embedded authority strings (e.g., `Quercus agrifolia Née`) are all accepted by TNRS but should be checked after reconciliation. Strip author strings from submitted names before running TNRS for best results.

---

### 🔬 Step 3 — Stage & Validate

**Do this exactly:**

1. In Step 2, click **Apply Mapping ▶** to generate the staging table and QC summary.
2. In Step 3, inspect QC summary for PASS/WARN/BLOCK.
3. Run BIEN services in recommended order: **TNRS → GNRS → GVS → NSR**.
4. Review flags and ambiguous records before export.
5. If hosted execution fails, download local scripts and upload result CSVs back.

#### QC Summary

| Severity | Meaning |
|---|---|
| ✅ **PASS** | All records clear this check |
| ⚠️ **WARN** | Some records have issues; export is not blocked |
| 🔴 **BLOCK** | Strong warning to stop and fix critical issues before export (the app does not hard-enforce export blocking) |

Checks include: coordinate range validation, required field population, and date parseability across common formats.

#### BIEN Web Services

Recommended execution order is: **TNRS → GNRS → GVS → NSR**

> **NSR can run without GNRS, but GNRS-first is strongly recommended.** NSR uses the staging geography fields (`country`, `state_province`, `county`), so unresolved or inconsistent geography can still return sparse or less interpretable native-status output.

| Service | What it does |
|---|---|
| **TNRS** — Taxonomic Name Resolution | Matches submitted names to accepted names (WCVP/WFO backbone), standardizes spelling and authorship, populates `scrubbed_*` taxonomy fields. Match scores range 0–1. |
| **GNRS** — Geographic Name Resolution | Standardizes country, state/province, and county strings against reference geographies; in this app, matched values are written back into `country`, `state_province`, and `county`. |
| **GVS** — Geo Validation Service | Performs coordinate-level checks on submitted lat/lon pairs and flags administrative centroids (`is_centroid = 1`), which indicate reduced spatial precision. |
| **NSR** — Native Status Resolution | Determines whether each species is native, introduced, or cultivated for the given political unit (country/state/county). Most interpretable after GNRS-standardized geography. |

#### Interpreting common flags and fields

- **TNRS match score (`Overall_score`)**:
  - `>= 0.90`: usually acceptable for automated carry-through
  - `< 0.90`: review likely synonym/spelling/authority mismatch
  - `< 0.50`: hold for curator review before BIEN submission
- **GNRS geography standardization**:
  - App writeback updates `country`, `state_province`, `county`
  - Unresolved geography limits downstream NSR interpretation
- **GVS centroid flag**:
  - `is_centroid = 1` indicates an administrative centroid, not a precise locality
- **NSR status fields**:
  - `native_status`, `is_introduced`, plus political-unit context fields

#### Step 3 mini example (execution order and expected outputs)

Input staged row (pre-services):

| name_submitted | country | state_province | county | latitude | longitude |
|---|---|---|---|---:|---:|
| Quercus agrifolia Nee | USA | CA | Los Angeles County | 34.1212 | -118.3321 |

Expected after TNRS:

- `scrubbed_species_binomial` populated (for example `Quercus agrifolia`)
- TNRS score available for review

Expected after GNRS:

- `country/state_province/county` standardized directly in staging fields

Expected after GVS:

- Coordinate-level QA returned for submitted lat/lon pairs
- `is_centroid` set where applicable

Expected after NSR:

- `native_status` and related status fields populated where geography resolves

> **Cloud hosting note:** In-app buttons contact external servers that may be blocked from cloud IPs (shinyapps.io runs on AWS). If a service times out after ~25 seconds, use the **Download validation script** button and run locally.

> **In-app service scale note:** Hosted/in-app execution is intentionally limited to first 20 unique names (TNRS) and first 20 unique taxon/location combinations (NSR). For larger jobs, use local scripts and upload results.

**Local script workflow (recommended for larger runs):**

```r
# TNRS example — use your raw submitted name column, NOT scrubbed_species_binomial
library(TNRS)
dat <- read.csv("my_staged_data.csv")

# Input must be the pre-reconciliation verbatim name column
results <- TNRS(taxonomic_names = dat$name_submitted)

# Records with Overall_score < 0.9 should be manually reviewed
# Records with Overall_score < 0.5 require curator attention before submission
write.csv(results, "tnrs_results.csv", row.names = FALSE)
```

Then upload `tnrs_results.csv` using **Upload TNRS results CSV** in the app.

**Troubleshooting:**

- If TNRS succeeds but NSR is empty, check GNRS completion and the `country/state_province/county` staging fields first.
- If GVS reports many centroid points, verify source coordinate precision and locality capture quality.
- If services intermittently timeout in hosted mode, run scripts locally and upload results.

---

### 📦 Step 4 — Export

| Export | Contents |
|---|---|
| **BIEN Staging CSV** | Fixed BIEN staging subset used by this app, populated by your data + web service results |
| **Darwin Core CSV** | DWC-standard fields only, suitable for GBIF or iDigBio submission |
| **QC Report CSV** | Per-field quality check results with pass/warn/block status |

#### Export example: BIEN staging vs Darwin Core

Same record, two outputs:

- **BIEN staging CSV** includes BIEN-specific and reconciliation fields (for example `scrubbed_species_binomial`, `is_centroid`, `native_status`, `native_status_reason`).
- **Darwin Core CSV** includes standard DWC terms only (for example `scientificName`, `decimalLatitude`, `decimalLongitude`, `eventDate`, `country`, `stateProvince`, `county`).

Expected use:

- Send **BIEN staging CSV** for BIEN ingestion workflow.
- Use **Darwin Core CSV** for GBIF/iDigBio-aligned interchange.

Review TNRS ambiguous matches and NSR native/introduced flags before submitting to BIEN. Record the API version and run date in your export metadata — reconciliation results are reference-data-dependent and may change as backbone databases are updated.

---

## What Output Looks Like

Compact example row from a BIEN staging-style export:

| occurrenceID | name_submitted | scrubbed_species_binomial | latitude | longitude | country | is_centroid | native_status |
|---|---|---|---:|---:|---|---:|---|
| obs-001 | Quercus agrifolia Nee | Quercus agrifolia | 34.1212 | -118.3321 | United States | 0 | native |

How to read this quickly:

- `name_submitted` is your original verbatim name input.
- `scrubbed_species_binomial` is TNRS standardized taxonomy.
- `is_centroid` communicates coordinate precision risk from GVS.
- `native_status` is NSR context-dependent by political geography.

---

## Operational Caveats

- **Hosted timeout behavior:** App-side service calls may timeout on cloud-hosted infrastructure; local script execution is the fallback path for bigger jobs.
- **Cloud IP blocks:** Some upstream services can block or intermittently refuse cloud IP ranges; this can produce service-specific failures even when your data are valid.
- **GNRS dependency for NSR:** If GNRS does not resolve political geography, NSR may return blank or non-actionable status fields.
- **Coordinate precision leakage:** Low-precision or rounded coordinates can trigger centroid-like behavior and weaken range/SDM suitability.
- **Projection mismatch risk:** Coordinates not in WGS84 decimal degrees can appear valid numerically but fail geospatial checks semantically.
- **Taxonomy ambiguity is normal:** Lower TNRS scores are often synonym or spelling issues, not always true data errors; review instead of auto-dropping.

---

## ⚠️ Scientific Caveats

> **TNRS ambiguous matches** — TNRS reconciles against WCVP and WFO in this app implementation. Match scores range 0–1. Scores ≥ 0.9 are generally reliable. Scores < 0.9 often reflect synonym chains, spelling variants, or names not yet in the backbone — review these manually, especially for taxonomically difficult groups (*Carex*, *Eriogonum*, recently split genera). Infraspecific epithets (subsp., var., f.) are supported; strip embedded author strings before submission. Do not submit records with scores < 0.5 without curator verification.

> **NSR native/introduced status** — Native status is assigned relative to a **political unit** (country or state/province), not a biogeographic region. A taxon native to California may be flagged as introduced in Baja California Sur. Status reflects current NSR reference data and changes as checklists are updated. Treat native status as a data-quality flag, not an ecological verdict, particularly for range-edge records and cross-border studies.

> **`is_cultivated_observation`** — In this implementation, this field is populated in staging output from NSR response values (`isCultivatedNSR` writeback), alongside other NSR status fields.

> **GVS centroid flags** — `is_centroid = 1` indicates a coordinate matching an administrative centroid rather than a precise locality. Centroid-flagged records inflate apparent range area, bias species distribution models toward administrative boundaries, and are typically excluded from SDM training sets. Treat these as spatially imprecise.

> **`scrubbed_*` fields** — Taxonomic `scrubbed_*` fields are populated by TNRS. GNRS standardization is written into `country`, `state_province`, and `county` in staging. Record the TNRS/GNRS API version and backbone (e.g., WCVP 2024) with each export for reproducibility.

---

## BIEN Field Reference

### Taxonomy — populated by TNRS
| Field | Description |
|---|---|
| `scrubbed_species_binomial` | Accepted binomial from TNRS backbone |
| `scrubbed_family` | Accepted family name |
| `scrubbed_genus` | Accepted genus |
| `scrubbed_author` | Author string for accepted name |
| `scrubbed_taxonomic_status` | Accepted / Synonym / No match |

### Geography — populated by GNRS
| Field | Description |
|---|---|
| `locality` | Verbatim locality string |
| `country` | Staging country (submitted, then standardized by GNRS writeback) |
| `state_province` | Staging state/province (submitted, then standardized by GNRS writeback) |
| `county` | Staging county (submitted, then standardized by GNRS writeback) |
| `plot_name` | Plot or site identifier |

### Coordinates
| Field | Description |
|---|---|
| `latitude` | Decimal latitude (WGS84) |
| `longitude` | Decimal longitude (WGS84) |
| `is_centroid` | 1 = coordinate is an administrative centroid (from GVS) |

### Native Status — populated by NSR
| Field | Description |
|---|---|
| `native_status` | Native / Introduced / Cultivated |
| `native_status_reason` | Basis for status assignment |
| `native_status_country` | Political unit used for assessment (country) |
| `native_status_state_province` | Political unit (state/province) |
| `native_status_county_parish` | Political unit (county/parish) |
| `is_introduced` | 1 = introduced in assessed political unit |
| `is_cultivated_observation` | 1 = cultivated flag returned by NSR and written to staging |

### Other
| Field | Description |
|---|---|
| `date_collected` | Collection date |
| `dataset`, `datasource`, `dataowner`, `collection_code` | Dataset provenance |
| `occurrenceID`, `basisOfRecord` | Record identifiers |
| `verbatimLocality`, `verbatimElevation` | Original verbatim strings |
| `elevation_min`, `elevation_max` | Elevation range (m) |

---

## Demo Data

The app ships with two CSV files under `demo_data/` illustrating a two-table join workflow:

**`observations.csv`** — 12 plant records from H.L. Mason's 1910–1912 California surveys:

| Field | Example |
|---|---|
| `occurrenceID` | `hist-001` |
| `scientificName` | `Abies bracteata` |
| `decimalLatitude` | `35.321` |
| `decimalLongitude` | `-120.123` |
| `Date_Collected` | `1912-06-10` |
| `Plot_Name` | `Plot_A` |

**`plot_metadata.csv`** — Site geography joined on `Plot_Name`:

| Field | Example |
|---|---|
| `Country` | `United States` |
| `State` | `California` |
| `County` | `San Luis Obispo` |
| `Locality` | `Santa Lucia Range - upper ridge` |
| `Elevation_m` | `1240` |

This two-table pattern is standard for vegetation plot databases, NEON exports, VegBank submissions, and long-term resurvey programs.

---

## Repository Structure

```
BIENDataLoader/
├── app.R                  # Single-file Shiny app (UI + server)
├── demo_data/
│   ├── observations.csv   # Demo species occurrence records
│   └── plot_metadata.csv  # Demo plot geography metadata
├── www/
│   └── bien.png           # BIEN logo (served statically by Shiny)
├── cf-workers/            # Cloudflare Worker relay source (TNRS/GNRS/GVS/NSR)
│   ├── tnrs/
│   ├── gnrs/
│   ├── gvs/
│   └── nsr/
└── deploy.R               # shinyapps.io deployment script
```

---

## License

MIT License. See `LICENSE` if present, or contact the repository owner.
