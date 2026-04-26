<p align="center">
  <img src="www/bien.png" alt="BIEN logo" height="72">
</p>

<h2 align="center">BIEN Data Loader</h2>

<p align="center">
  Upload · Validate · Export plant occurrence data for BIEN submission<br><br>
  <a href="https://benquist.shinyapps.io/bien-data-loader/"><strong>▶ Launch the App</strong></a>
  &nbsp;|&nbsp;
  <a href="#step-by-step-tutorial">Tutorial</a>
  &nbsp;|&nbsp;
  <a href="#-scientific-caveats">Scientific Caveats</a>
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

## What Is This?

The **BIEN Data Loader** is a browser-based tool that prepares plant occurrence data for submission to BIEN. It is designed for:

- **Herbarium curators** digitizing historical voucher collections
- **Vegetation ecologists** contributing plot-based presence or abundance records
- **Field botanists** submitting georeferenced observation datasets
- **Citizen science curators** cleaning iNaturalist or similar exports before formal archiving
- **Long-term resurvey programs** integrating historical and modern collection records

No R experience required. The app handles field mapping, taxonomy reconciliation (TNRS), coordinate QA (GVS), native/introduced status checking (NSR), and export in BIEN staging or Darwin Core format.

---

## Quick Start

**No installation needed.** Open the app in your browser:

> ### [▶ https://benquist.shinyapps.io/bien-data-loader/](https://benquist.shinyapps.io/bien-data-loader/)

The first load may take ~15 seconds on the free hosting tier. A spinner will appear while the app warms up.

---

## How It Works

**① Upload & Merge** → **② Map Fields** → **③ Stage & Validate** → **④ Export**

The app guides each step interactively. BIEN web services (TNRS, GNRS, GVS, NSR) can run in the browser or via downloadable R scripts for large datasets.

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

**To use your own data:**

1. Uncheck **"Use built-in demo data"**
2. Click **Browse** and select one or more `.csv` files
   - Multiple files: `Command-click` (macOS) or `Ctrl-click` (Windows/Linux)
3. If you uploaded more than one file, choose the **primary observation table** and the **join key column** (e.g., `Plot_Name`) for merging
4. Click **Prepare Dataset ▶**

The right panel shows a preview of the merged table.

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

> **Coordinate requirement:** Coordinates must be in **WGS84 decimal degrees (EPSG:4326)**. Other projections and degree-minute-second formats are not accepted and will produce silent spatial errors.

**About the demo data:**
The demo observations are drawn from H.L. Mason's 1910–1912 California field surveys — among the earliest systematic botanical collections of California's coastal ranges (Santa Lucia Range, San Rafael Mountains). This two-table structure (observations joined to plot metadata on `Plot_Name`) is typical of vegetation plot databases, NEON plot exports, VegBank submissions, and long-term resurvey programs.

---

### 🔗 Step 2 — Map Fields

The app suggests two mappings for each of your columns:

| Column | What it means |
|---|---|
| **DWC Term** | Darwin Core standard term (international biodiversity exchange standard used by GBIF, iDigBio) |
| **BIEN Field** | The BIEN database staging schema field |

**How to review and adjust:**

1. Click any cell in `DWC Term` or `BIEN Field` to edit it
2. Clear a cell to exclude a column from the output
3. Click **Apply Mapping ▶**

Partial mappings are accepted. At minimum, map your **species name**, **latitude**, and **longitude** columns. Genus-only names, morphospecies labels, and names with embedded authority strings (e.g., `Quercus agrifolia Née`) are all accepted by TNRS but should be checked after reconciliation. Strip author strings from submitted names before running TNRS for best results.

---

### 🔬 Step 3 — Stage & Validate

#### QC Summary

| Severity | Meaning |
|---|---|
| ✅ **PASS** | All records clear this check |
| ⚠️ **WARN** | Some records have issues; export is not blocked |
| 🔴 **BLOCK** | Critical issues to resolve before export |

Checks include: coordinate range validation, required field population, and date parseability across common formats.

#### BIEN Web Services

Run these in order — each service feeds the next: **TNRS → GNRS → GVS → NSR**

> **GNRS must complete before NSR.** NSR uses GNRS-standardized political geography to look up native status. Records with unresolved country/state will receive no NSR output.

| Service | What it does |
|---|---|
| **TNRS** — Taxonomic Name Resolution | Matches submitted names to accepted names (Tropicos/WCVP/WFO backbone), standardizes spelling and authorship, populates `scrubbed_*` taxonomy fields. Match scores range 0–1. |
| **GNRS** — Geographic Name Resolution | Standardizes country, state/province, and county strings against reference geographies; populates `scrubbed_country`, `scrubbed_state_province`, `scrubbed_county_parish`. |
| **GVS** — Geo Validation Service | Validates that point coordinates fall within the stated country/state/county; also flags administrative centroids (`is_centroid = 1`), which indicate reduced spatial precision. |
| **NSR** — Native Status Resolution | Determines whether each species is native, introduced, or cultivated for the given political unit (country/state/county). Requires GNRS-standardized geography. |

> **Cloud hosting note:** In-app buttons contact external servers that may be blocked from cloud IPs (shinyapps.io runs on AWS). If a service times out after ~25 seconds, use the **Download validation script** button and run locally.

**Local script workflow (recommended for datasets > 500 records):**

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

---

### 📦 Step 4 — Export

| Export | Contents |
|---|---|
| **BIEN Staging CSV** | All BIEN schema fields, populated by your data + web service results |
| **Darwin Core CSV** | DWC-standard fields only, suitable for GBIF or iDigBio submission |
| **QC Report CSV** | Per-field quality check results with pass/warn/block status |

Review TNRS ambiguous matches and NSR native/introduced flags before submitting to BIEN. Record the API version and run date in your export metadata — reconciliation results are reference-data-dependent and may change as backbone databases are updated.

---

## ⚠️ Scientific Caveats

> **TNRS ambiguous matches** — TNRS reconciles against Tropicos, USDA Plants, WCVP, and WFO. Match scores range 0–1. Scores ≥ 0.9 are generally reliable. Scores < 0.9 often reflect synonym chains, spelling variants, or names not yet in the backbone — review these manually, especially for taxonomically difficult groups (*Carex*, *Eriogonum*, recently split genera). Infraspecific epithets (subsp., var., f.) are supported; strip embedded author strings before submission. Do not submit records with scores < 0.5 without curator verification.

> **NSR native/introduced status** — Native status is assigned relative to a **political unit** (country or state/province), not a biogeographic region. A taxon native to California may be flagged as introduced in Baja California Sur. Status reflects current NSR reference data and changes as checklists are updated. Treat native status as a data-quality flag, not an ecological verdict, particularly for range-edge records and cross-border studies.

> **`is_cultivated_observation`** — This is a **user-supplied field** indicating whether the record represents a cultivated plant. NSR uses this value but does not infer it from occurrence data. Populate it explicitly before running NSR.

> **GVS centroid flags** — `is_centroid = 1` indicates a coordinate matching an administrative centroid rather than a precise locality. Centroid-flagged records inflate apparent range area, bias species distribution models toward administrative boundaries, and are typically excluded from SDM training sets. Treat these as spatially imprecise.

> **`scrubbed_*` fields** — Taxonomic `scrubbed_*` fields are populated by TNRS; geographic `scrubbed_*` fields are populated by GNRS. Do not hand-edit these fields after reconciliation. Record the TNRS/GNRS API version and backbone (e.g., WCVP 2024) with each export for reproducibility.

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
| `country` | Submitted country |
| `state_province` | Submitted state/province |
| `county` | Submitted county |
| `plot_name` | Plot or site identifier |
| `scrubbed_country` | GNRS-standardized country |
| `scrubbed_state_province` | GNRS-standardized state/province |
| `scrubbed_county_parish` | GNRS-standardized county |

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
| `is_cultivated_observation` | 1 = user-flagged as cultivated (user-supplied) |

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
