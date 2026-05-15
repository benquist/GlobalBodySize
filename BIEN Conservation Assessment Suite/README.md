# BIEN Flora Explora — Conservation Assessment Suite

<img src="www/bien.png" align="right" height="80" alt="BIEN logo"/>

**Version 1.0.0** | [biendata.org](https://biendata.org/) | License: MIT

A rapid, polygon-based plant conservation assessment tool for remote and inaccessible regions of the Americas, powered by the [BIEN R package](https://doi.org/10.1111/2041-210X.12861) (Maitner et al. 2018).

> **[Launch the app on shinyapps.io — link added after deployment]**
>
> To run locally, see [Installation](#installation).

---

## Overview

**BIEN Flora Explora** provides rapid, data-driven plant species inventories for any user-defined polygon within the BIEN Americas domain. It is designed for situations where comprehensive field inventories are not feasible: remote watersheds, inaccessible frontier forests, large-scale government-commission conservation assessments, and rapid biodiversity surveys ahead of infrastructure or land-use decisions.

The app was developed in collaboration with **Nigel Pitman** (Field Museum of Natural History, Chicago) in support of a Brazilian government conservation commission for the **Alto Japurá basin** (~250,000 km², western Brazilian Amazon, Amazonas state), one of the most botanically undersampled regions of the Neotropics. The Alto Japurá pilot case tests the app's ability to characterize predicted plant diversity in a ~1.6 million hectare protected-area complex where field access is extremely difficult.

The app is not a substitute for field surveys. It produces **data-supported predictions** from the BIEN database, with transparent evidence tiers and mandatory interpretive caveats. Users must read the [About & Caveats tab](#app-tabs) before drawing regulatory or conservation conclusions.

---

## Scientific Context and Motivation

The Botanical Information and Ecology Network (BIEN; Maitner et al. 2018) aggregates occurrence records, plot-based inventories, and species distribution model (SDM) range outputs for vascular plant species of the Western Hemisphere. BIEN currently holds over 200 million georeferenced occurrence records and SDM-derived range polygons for thousands of plant species, making it one of the most comprehensive continental botanical databases in existence.

For ecologically data-deficient regions — including much of the western Amazon — no published floristic inventory covers the full flora. Field surveys of such regions require substantial logistics, time, and safety planning. Yet conservation policy decisions often require species-level data on short timescales. BIEN Flora Explora bridges this gap by:

1. Querying BIEN's pre-indexed occurrence and range databases for any user-drawn or uploaded polygon.
2. Combining occurrence density and spatial range overlap into transparent evidence tiers.
3. Applying a quality gate using indicator species expected to be present in any correctly geocoded query.
4. Exporting results with full data provenance for regulatory or collaborative use.

The app does not produce novel species distribution models. It queries BIEN's existing SDM-derived range polygons and occurrence records, applies spatial intersection, and presents results with explicit uncertainty documentation.

---

## Use Cases

### 1. Rapid conservation assessment for inaccessible regions
A government agency or conservation NGO needs a preliminary plant species list for a proposed protected area in a remote watershed. A GeoJSON boundary polygon is uploaded; BIEN Flora Explora returns a tiered species list in 5–30 minutes, graded by evidence quality, with a Darwin Core-inspired CSV for submission to a biodiversity registry.

### 2. Pre-survey planning for botanical expeditions
Field botanists planning an expedition to an understudied region use the app to identify which taxonomic groups and families are expected based on BIEN range and occurrence data. The occurrence heatmap highlights where botanical records cluster (often roads and rivers), guiding targeted survey design to fill gaps.

### 3. Policy brief preparation for government commissions
Conservation practitioners preparing a brief for an agency such as IBAMA or ICMBio use the app to generate a rapid first-pass species list with confidence tiers and provenance metadata. The HTML provenance report (downloadable from the Data Quality tab) provides a SHA-256-fingerprinted, timestamped, and BIEN-version-stamped record suitable for submission as supporting evidence.

### 4. Biodiversity assessment for infrastructure environmental impact review
Environmental consultants assessing likely plant diversity impacts for a proposed road, dam, or mining concession can upload the project footprint polygon and receive a tiered species list. The tool explicitly flags data gaps and model quality limitations, supporting responsible uncertainty communication to reviewers.

### 5. Cross-regional floristic comparison for macroecology research
Researchers comparing plant diversity across multiple Amazonian watersheds can upload a series of polygons, download the CSV outputs, and integrate them into downstream analysis. The polygon SHA-256 fingerprint and BIEN package version stamp in every export enable reproducible identification of the exact query version used in a published analysis.

### 6. Education and demonstration of BIEN data coverage
For courses in tropical ecology or conservation biology, instructors can use the app to demonstrate BIEN occurrence density, geographic coverage gaps, and the contrast between SDM-predicted and occurrence-supported diversity — all interactively, without requiring R programming skills.

---

## Three-Stage Query Architecture

The app uses three BIEN API functions in a concurrent async design. Stages 1 and 2 always run; Stage 3 is optional.

| Stage | BIEN Function | Typical speed | Purpose |
|-------|--------------|---------------|---------|
| **1 — Country Checklist** | `BIEN_list_country()` | 5–30 seconds | Pre-indexed political-unit species list; fast initial result |
| **2 — Occurrence Records** | `BIEN_occurrence_sf()` | 2–15 minutes | Server-side polygon-intersection occurrences; drives evidence tiers and heatmap |
| **3 — Range Overlap** *(optional)* | `BIEN_ranges_sf()` | 20–60 minutes | SDM-derived range polygon overlap; adds `overlap_pct_polygon` and `overlap_pct_range` columns |

**Stage 1 note:** `BIEN_list_country()` queries BIEN's pre-indexed political-unit tables and returns in seconds regardless of polygon size. It returns a country-level *superset* — all species recorded anywhere in the overlapping country, not only inside the AOI. Stage 2 provides the spatially precise polygon-intersection refinement. Stage 1 provides an immediate preliminary result while Stage 2 runs in the background.

**Stage 3 note:** Range polygons in BIEN are binary-thresholded MaxEnt outputs (threshold type not publicly documented via the API). Stacking binary SDM outputs tends to overestimate local species richness (Calabrese et al. 2014) because each model can contain false positives. Treat Stage 3 range-overlap results with caution and refer to Stage 2 occurrence counts as the primary evidence.

---

## Data Support Tier System

Each species is assigned to one of four **data support tiers** based on the combined evidence from occurrence records (Stage 2) and range polygon overlap (Stage 3). These tiers are heuristic — they summarize evidence density, not statistically validated probability of presence. See [Key Limitations](#key-limitations) for required caveats.

| Tier | Criteria | Interpretation |
|------|----------|----------------|
| **High** | n_occ ≥ 20 AND range overlap ≥ 25% | Strong dual evidence: many occurrence records plus substantial range overlap in AOI |
| **Moderate** | n_occ ≥ 5 AND range overlap ≥ 10% | Moderate dual evidence: credible, spatially consistent presence |
| **Low** | n_occ ≥ 2 OR range overlap ≥ 2% | Any direct evidence: treat with interpretive caution |
| **Very Low** | All other | Checklist-only (Stage 1) or single evidence only; high uncertainty |

> **Important:** These thresholds are heuristic, calibrated informally against the Alto Japurá pilot dataset. They are not cross-validated against ground-truth field surveys. "High" tier does not mean *confirmed presence*. "Very Low" tier does not mean *confirmed absence*.

Tiers are calculated after Stage 2 completes (occurrence-based), and can be updated after Stage 3 (range-overlap-refined). After Stage 1 only, all species receive Very Low pending Stage 2.

---

## App Tabs

### Map
- CartoDB Positron base map, centered on the Alto Japurá basin (lon = −68°, lat = −2°, zoom = 7) as the pilot study region.
- Draw a freehand polygon with the toolbar, or upload a file.
- Occurrence heatmap from up to 5,000 subsampled BIEN occurrence points (subsample for Leaflet rendering performance).
- Red polygon outline shows the validated area of interest (AOI).

### Species List
- Sortable, searchable species table with: accepted name, family, data support tier, data_support_n (occurrence count), overlap_pct_polygon (% of AOI predicted suitable), overlap_pct_range (% of species global range inside AOI), native status, and IUCN status (Phase 2 — not currently queried).
- Color-coded tier badges.
- Download button for Darwin Core–inspired CSV with provenance metadata.

### Data Quality
- **Anchor species gate:** five western Amazonian indicator species (see below) are checked for presence. A FAIL is a quality signal, not a confirmed absence. See interpretation guidance below.
- **Occurrence density histogram:** log₁₀(n_occurrences) across all returned species. Aids diagnosis of data sparsity, single-species record inflation, or unexpectedly low return counts.
- **Download HTML report:** rmarkdown-rendered provenance report containing session metadata, polygon SHA-256 fingerprint, BIEN package version, anchor check results, and full species table.

### About & Caveats
Contains required interpretive disclaimers. Users submitting outputs for regulatory purposes are required to read this section.

---

## Anchor Species and Quality Gate

The Data Quality tab checks for five western Amazonian plant species that should appear in BIEN data for any correctly geocoded polygon in the upper Amazon basin. Their absence triggers a visible warning.

| Species | Ecological role | Geographic range |
|---------|----------------|-----------------|
| *Mauritia flexuosa* L.f. | Dominant aguaje palm of flooded várzea and igapó | Widespread across tropical South America; abundant in Amazonian wetlands |
| *Iriartea deltoidea* Ruiz & Pav. | Dominant terra firme canopy palm | Western Amazonia, especially Colombia, Peru, Ecuador, western Brazil |
| *Euterpe precatoria* Mart. | Widespread understory palm; açaí | Humid tropical forests, western and central Amazonia |
| *Cedrelinga cateniformis* (Ducke) Ducke | Canopy timber tree (tornillo) | Western Amazonia, especially Peru, Ecuador, Colombia, western Brazil |
| *Swietenia macrophylla* King | Big-leaf mahogany; flagship conservation species | Widespread Neotropical, heavily targeted by conservation policy |

**Interpreting an anchor FAIL:** A FAIL does not mean those species are absent from the study area. Common causes include: (1) CRS mismatch between the uploaded polygon and BIEN coordinates; (2) polygon outside the known range of these species; (3) BIEN coverage gap for a poorly sampled subregion; (4) API error silently returning an incomplete record set. Always cross-check a FAIL against the heatmap and known regional floristics before drawing conclusions.

Anchor species can be customized for non-Amazonian AOIs in `app/global.R` under `CFG$ANCHOR_SPECIES`.

---

## Key Limitations

Users must acknowledge all of the following before using app outputs for regulatory, governmental, or published scientific purposes:

1. **This is not a field survey.** All outputs are predictions derived from BIEN occurrence records and SDM range models. No result constitutes confirmed species presence.

2. **SDM binary stacking overestimates local species richness.** BIEN range polygons are binary-thresholded MaxEnt outputs. Stacking binary thresholded SDMs tends to overestimate alpha diversity because each model can include false-positive predictions (Calabrese et al. 2014). Stage 3 range overlap results are subject to this bias. Tier thresholds partially mitigate it (requiring occurrence evidence for High and Moderate tiers) but do not eliminate it.

3. **Occurrence records in remote Amazonian regions are severely biased.** Records in BIEN and its source databases (including GBIF, speciesLink, BIEN plot data) cluster along navigable rivers and roads in western Amazonia. Interior upland terra firme is among the most botanically undersampled biomes on Earth. This spatial bias means that Very Low tier species in data-deficient regions may simply reflect lack of sampling, not lack of presence.

4. **`native_status` is NA-heavy for remote Neotropical sites.** The BIEN occurrence schema includes a `native_status` field, but it is frequently `NA` for records from poorly surveyed regions. A `status_unavailable` flag in the app output does not mean a species is introduced — it means BIEN has no annotation for that record.

5. **Stage 1 is a political-unit superset.** `BIEN_list_country()` returns all species recorded anywhere in overlapping countries. For large, species-rich countries such as Brazil or Colombia, the Stage 1 list may contain thousands of species that do not occur in the specific AOI. Stage 2 spatially refines this list. Before Stage 2 completes, all Stage 1 species receive Very Low tier.

6. **SDM model quality is not available via the API.** AUC, True Skill Statistic (TSS), Boyce Index, and training record counts for BIEN MaxEnt range models are not returned by `BIEN_ranges_sf()`. `overlap_pct_polygon` reflects spatial overlap with a binary range output, not modeled habitat suitability probability or validated model accuracy.

7. **Data support tiers are heuristic, not statistically calibrated.** The tier thresholds (e.g., n_occ ≥ 20 AND overlap ≥ 25% = High) were not cross-validated against independent field surveys. They summarize evidence quantity and consistency, not probability of presence.

8. **The app covers the BIEN Americas domain only.** Polygons outside the Western Hemisphere (lon −170 to −34, lat −55 to 55) will be rejected.

---

## Accepted Polygon Formats

| Format | Notes |
|--------|-------|
| GeoJSON (`.geojson`, `.json`) | Recommended; most compatible with BIEN spatial queries |
| Shapefile ZIP (`.zip`) | Must contain `.shp`, `.dbf`, `.prj`, `.shx`. Zip Slip path-traversal mitigation is applied before extraction |
| KML / KMZ (`.kml`, `.kmz`) | Parsed via `sf::st_read()`; KMZ is unzipped before parsing |
| Drawn on map | Freehand polygon via Leaflet draw toolbar (single polygon only) |

**Size limits:** 100 km² minimum, 50,000 km² maximum. Polygons approaching the upper limit may cause Stage 2 and Stage 3 queries to take 15–60 minutes. Larger polygons should be split into sub-regions.

---

## Installation

```r
# Install required R packages
install.packages(c(
  "shiny", "bslib", "BIEN", "sf", "leaflet", "leaflet.extras",
  "dplyr", "DT", "jsonlite", "digest", "promises", "future",
  "rnaturalearth", "rnaturalearthdata", "units", "rmarkdown", "R.utils"
))

# Clone the repository
# git clone https://github.com/benquist/BIEN_Flora_Explora.git

# Run the app from the repo root
shiny::runApp("app/")
```

**R version:** Developed and tested on R 4.3+. Recommend R ≥ 4.2.

**Dependency pinning:** An `renv.lock` file will be added in a future release. Until then, use the package versions current at the time of the BIEN package version you are querying against, and record the BIEN package version from the downloaded HTML provenance report.

---

## Repository Structure

```
app/
  app.R          — Shiny UI + server; three-stage async query design
  global.R       — Package loading, CFG configuration, async worker pool
  deploy.R       — rsconnect::deployApp() for shinyapps.io deployment
modules/
  mod_map.R      — Leaflet map initialization and layer helpers
utils/
  bien_queries.R     — All BIEN API calls (Stages 1–3) with error handling
  confidence_utils.R — Data support tier assignment and anchor species gate
  spatial_utils.R    — Polygon validation, session provenance log, DwC-inspired CSV export
www/
  bien.png           — BIEN logo
  disclaimer.html    — About & Caveats tab content with mandatory user warnings
data/                — Local pilot polygons (excluded from Git via .gitignore)
```

---

## Data Availability

All plant occurrence data and SDM range polygons queried by this app are derived from the **Botanical Information and Ecology Network (BIEN)** database, accessible at [biendata.org](https://biendata.org/). Data use is subject to the [BIEN data use policy](https://bien.nceas.ucsb.edu).

BIEN aggregates records from multiple source databases including GBIF, speciesLink, iDigBio, and BIEN's own field plot network. Users should cite both BIEN and the original data sources when publishing results derived from this app.

No proprietary or restricted data are bundled with this repository. The pilot GeoJSON polygon (`data/Japura_AOI_Nov2025_mapshaper.json`) is excluded from the public repository; contact the maintainers if needed for replication of Alto Japurá analyses.

---

## Suggested Citation

If you use BIEN Flora Explora in published work, please cite:

> Enquist BJ, Pitman N (2026). *BIEN Flora Explora: Conservation Assessment Suite v1.0.0*. University of Arizona / Field Museum of Natural History. GitHub: https://github.com/benquist/BIEN_Flora_Explora

And cite the underlying BIEN R package:

> Maitner BS, Boyle B, Casler N, Condit R, Donoghue J, Durán SM, Guaderrama D, Hinchliff CE, Jørgensen PM, Kraft NJB, McGill B, Merow C, Morueta-Holme N, Peet RK, Sandel B, Schildhauer M, Smith SA, Svenning J-C, Thiers B, Violle C, Wiser S, Enquist BJ (2018). The bien r package: A tool to access the Botanical Information and Ecology Network (BIEN) database. *Methods in Ecology and Evolution*, 9(2), 373–379. https://doi.org/10.1111/2041-210X.12861

---

## Acknowledgments

This app was developed with support from **Nigel Pitman** (Field Museum of Natural History) whose Alto Japurá conservation commission motivated the initial design, and the **BIEN network** (bien.nceas.ucsb.edu). BIEN data infrastructure is supported by the National Center for Ecological Analysis and Synthesis (NCEAS) and the iPlant Collaborative.

---

## Contact

**Brian J. Enquist** — benquist@arizona.edu  
Department of Ecology and Evolutionary Biology, University of Arizona  
[enquistlab.org](https://enquistlab.org/)

**Nigel Pitman** — npitman@fieldmuseum.org  
Science and Education, Field Museum of Natural History, Chicago

---

## References

Calabrese JM, Certain G, Kraan C, Dormann CF (2014). Stacking species distribution models and adjusting bias by linking them to macroecological models. *Global Ecology and Biogeography*, 23(1), 99–112. https://doi.org/10.1111/geb.12102

Maitner BS, Boyle B, Casler N, Condit R, Donoghue J, Durán SM, Guaderrama D, Hinchliff CE, Jørgensen PM, Kraft NJB, McGill B, Merow C, Morueta-Holme N, Peet RK, Sandel B, Schildhauer M, Smith SA, Svenning J-C, Thiers B, Violle C, Wiser S, Enquist BJ (2018). The bien r package: A tool to access the Botanical Information and Ecology Network (BIEN) database. *Methods in Ecology and Evolution*, 9(2), 373–379. https://doi.org/10.1111/2041-210X.12861

ter Steege H, Pitman NCA, Sabatier D, Baraloto C, Salomão RP, Guevara JE, Phillips OL, Castilho CV, Magnusson WE, Molino J-F et al. (2013). Hyperdominance in the Amazonian tree flora. *Science*, 342(6156), 1243092. https://doi.org/10.1126/science.1243092

---

## License

MIT License. See `LICENSE` file. BIEN data use is subject to the [BIEN data use policy](https://bien.nceas.ucsb.edu).
