# BIEN Flora Explora — Conservation Assessment Suite

[![BIEN logo](www/bien.png)](https://biendata.org/)

Learn more about BIEN at **[biendata.org](https://biendata.org/)**.

A rapid, polygon-based plant conservation assessment tool for remote and inaccessible regions of the Americas, powered by the [BIEN R package](https://bien.nceas.ucsb.edu) (Maitner et al. 2018).

## Try it live

> **[Launch the app on shinyapps.io](#)** *(link added after deployment)*

To run it locally, see [Installation](#installation) below.

---

## Overview

**BIEN Flora Explora** was conceived for conservation practitioners and field botanists who need rapid, data-driven plant species lists for remote regions — areas where no comprehensive floristic inventory exists and field access is difficult or impossible.

The app was developed in collaboration with Nigel Pitman (Field Museum) in support of the Alto Japurá conservation assessment commissioned by the Brazilian government. The Alto Japurá basin (~250,000 km², western Brazilian Amazon) served as the primary test case, but the app is designed to work across any polygon within the BIEN Americas domain.

**Core workflow:**
1. Upload or draw a polygon (GeoJSON, shapefile ZIP, KML/KMZ, or drawn on the map).
2. The app runs three concurrent BIEN data stages in the background.
3. Results appear progressively — a preliminary species list in seconds, occurrence-based confidence tiers in minutes, optional range overlap in longer runs.
4. Download a Darwin Core–compliant CSV or an HTML provenance report.

---

## Three-Stage Query Architecture

| Stage | BIEN Call | Speed | Purpose |
|-------|-----------|-------|---------|
| **1 — Country Checklist** | `BIEN_list_country()` | seconds | Political-unit species list (pre-indexed; country superset of AOI) |
| **2 — Occurrence Records** | `BIEN_occurrence_sf()` | minutes | Spatially precise polygon-intersection occurrences; drives confidence tiers and heatmap |
| **3 — Range Overlap** *(optional)* | `BIEN_ranges_sf()` | 20–60 min | SDM range polygon overlap; adds `overlap_pct_polygon` and `overlap_pct_range` columns |

Stages 1 and 2 always run concurrently. Stage 3 is activated only when the user checks **"Include range overlap analysis."**

**Key caveat:** Stage 1 returns a country-level *superset* — all species recorded anywhere in the overlapping country or countries, not just inside the drawn polygon. Stage 2 provides the spatially precise refinement.

---

## Confidence Tier System

Each species is assigned to one of four tiers based on the combined evidence from occurrence records (Stage 2) and range polygon overlap (Stage 3):

| Tier | Criteria | Interpretation |
|------|----------|----------------|
| **High** | n_occ ≥ 20 AND range overlap ≥ 25% | Strong dual evidence; well-documented in the AOI |
| **Moderate** | n_occ ≥ 5 AND range overlap ≥ 10% | Moderate dual evidence; credible presence |
| **Low** | n_occ ≥ 2 OR range overlap ≥ 2% | Any credible evidence; treat with caution |
| **Very Low** | All other | Checklist-only; no spatially validated occurrence or range overlap in the polygon |

Tiers are calculated after Stage 2 (occurrence-based) and updated after Stage 3 (range-overlap-refined). After Stage 1 only, all species are assigned Very Low pending Stage 2.

---

## App Tabs

### Map
- CartoDB Positron base map centered on the Alto Japurá basin (lon=-68, lat=-2, zoom=7).
- Draw a polygon with the toolbar, or upload a file.
- Occurrence heatmap rendered from up to 5,000 BIEN occurrence points (subsampled for Leaflet performance).
- Red polygon outline shows the validated AOI.

### Species List
- Sortable, searchable species table with confidence tier, data_support_n (occurrence count), overlap_pct_polygon, overlap_pct_range, family, native status, and IUCN status (Phase 2).
- Color-coded tier badges: High (green), Moderate (blue), Low (yellow), Very Low (gray).
- Download as Darwin Core CSV.

### Data Quality
- **Anchor species gate:** five western Amazonian indicator species checked for presence. A FAIL does not mean the species are absent — it may indicate a CRS issue, a BIEN coverage gap, or truly unsuitable habitat. See below.
- **Occurrence density histogram:** log₁₀(n_occurrences) across all species. Useful for diagnosing data sparsity or dominant single-species inflation.
- **Download HTML report:** rmarkdown-rendered provenance report with session metadata, polygon SHA-256 fingerprint, anchor check summary, and full species table.

### About & Caveats
- Key data limitations and citations.
- BIEN data use policy.

---

## Anchor Species (Plausibility Gate)

The following five western Amazonian species should be present in any correctly geocoded query of the Alto Japurá basin or similar western Amazonian AOI. Their absence is flagged as a warning in the Data Quality tab.

| Species | Common name | Ecological indicator |
|---------|-------------|----------------------|
| *Mauritia flexuosa* | Aguaje palm | Flooded várzea / wetlands |
| *Iriartea deltoidea* | Huacrapona | Terra firme canopy palm |
| *Euterpe precatoria* | Açaí | Widespread understory palm |
| *Cedrelinga cateniformis* | Tornillo | Common Amazonian timber tree |
| *Swietenia macrophylla* | Big-leaf mahogany | Flagship conservation species |

These species are defined in `app/global.R` under `CFG$ANCHOR_SPECIES` and can be customized for non-Amazonian AOIs.

---

## Key Data Limitations

- **SDM stacking overestimates richness.** BIEN range polygons are MaxEnt binary outputs (MTP threshold). Stacking them overestimates alpha-diversity because each model includes false positives (Calabrese et al. 2014; ter Steege et al. 2011). Treat Very Low tier range-only species with strong caution.
- **`native_status` is NA-heavy in Amazonia.** BIEN occurrence records often lack a `native_status` field for remote Amazonian sites. `status_unavailable` does not mean introduced — it means BIEN has no annotation for that record.
- **Stage 1 is a superset.** `BIEN_list_country()` returns all species recorded in the overlapping country. Stage 2 spatially refines this list; Very Low tier species from Stage 1 may not be present inside the polygon.
- **No model fit statistics available.** AUC, Boyce Index, and training record counts are not available via the BIEN API. `overlap_pct_polygon` reflects spatial overlap with the MaxEnt binary range, not model performance.
- **BIEN API latency.** Stage 2 queries take minutes; Stage 3 can take 20–60 minutes for large, species-rich polygons. The app displays progressive updates so results are never delayed until all stages finish.

---

## Accepted Polygon Formats

| Format | Notes |
|--------|-------|
| GeoJSON (`.geojson`, `.json`) | Recommended; most compatible |
| Shapefile (`.zip`) | Must be a ZIP containing `.shp`, `.dbf`, `.prj`, `.shx`; Zip Slip attack mitigation applied |
| KML / KMZ (`.kml`, `.kmz`) | Parsed via `sf::st_read()`; KMZ is unzipped first |
| Drawn on map | Freehand polygon via Leaflet draw toolbar |

Polygon size limits: 100 km² minimum, 50,000 km² maximum. Polygons must be within the BIEN Americas domain (lon -170 to -34, lat -55 to 55).

---

## Installation

```r
# Install required packages
install.packages(c(
  "shiny", "bslib", "BIEN", "sf", "leaflet", "leaflet.extras",
  "dplyr", "DT", "jsonlite", "digest", "promises", "future",
  "rnaturalearth", "rnaturalearthdata", "units", "rmarkdown", "R.utils"
))

# Clone the repository and run
shiny::runApp("app/")
```

---

## Repository Structure

```
app/
  app.R        — Shiny UI + server (three-stage async design)
  global.R     — Package loading, CFG config, async worker pool
  deploy.R     — rsconnect::deployApp() deployment script
modules/
  mod_map.R    — Leaflet map initialization and layer helpers
utils/
  bien_queries.R     — BIEN API calls (all three stages)
  confidence_utils.R — Confidence tier assignment and anchor species gate
  spatial_utils.R    — Polygon validation, session log, DwC CSV export
www/
  bien.png     — BIEN logo
  disclaimer.html — About & Caveats tab content
data/          — Local pilot polygons (excluded from Git)
```

---

## Citations

- Maitner BS et al. (2018). The bien r package: A tool to access the Botanical Information and Ecology Network (BIEN) database. *Methods in Ecology and Evolution*, 9(2), 373–379. https://doi.org/10.1111/2041-210X.12861
- ter Steege H et al. (2011). Hyperdominance in the Amazonian tree flora. *Science*, 333(6042), 1313–1316. https://doi.org/10.1126/science.1208106
- Calabrese JM, Certain G, Kraan C, Dormann CF (2014). Stacking species distribution models and adjusting bias by linking them to macroecological models. *Global Ecology and Biogeography*, 23(1), 99–112. https://doi.org/10.1111/geb.12102

**Data use policy:** [bien.nceas.ucsb.edu](https://bien.nceas.ucsb.edu)

---

## License

This app is released under the MIT License. BIEN data use is subject to the [BIEN data use policy](https://bien.nceas.ucsb.edu).
