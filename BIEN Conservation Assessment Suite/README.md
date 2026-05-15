# BIEN Conservation Assessment Suite

## Project Overview

A Shiny app toolkit for generating BIEN SDM-based plant species lists for user-defined study area polygons. Designed to support conservation assessments in remote or inaccessible regions where field surveys are not feasible.

## Origin

**Contact:** Nigel Pitman (npitman@fieldmuseum.org), Field Museum  
**Initial request:** April 28, 2026  
**Lead contact:** Brian Enquist (benquist@arizona.edu), University of Arizona / BIEN

**Context:** The Brazilian government commissioned the Field Museum rapid inventory team to characterize the flora of the Alto Japurá basin (~1.6M ha, western Brazilian Amazon), a region too remote and dangerous to survey on the ground. BIEN SDM range polygons offer a first-pass predicted species list.

**Study area pilot GeoJSON:** `data/Japura_AOI_Nov2025_mapshaper.json`  
- Polygon: Alto Rio Japurá (1,776,910 ha) + Alto Rio Içá (350,787 ha)  
- Approximate bbox: -69.0° to -68.0°W, -2.6° to -1.2°S

---

## Three App Designs (evaluated 2026-05-15)

### App 1 — BIEN Flora Scout *(Reliable Floor)*
- Upload GeoJSON → BIEN ranges + occurrences → confidence-tiered species list
- Automated plausibility anchor check (5 expected western Amazonian species)
- BIEN occurrence density heatmap displayed before results
- Downloadable Darwin Core CSV with mandatory disclaimers
- **Latency:** <2 min | **Target:** Non-R users, rapid first-pass

### App 2 — BIEN Conservation Assessment Suite *(Recommended for regulatory use)*
- All of App 1 plus:
- IUCN Red List status overlay (VU/EN/CR) via `rredlist`
- Habitat stratification: flooded (várzea/igapó) vs. upland (terra firme) via HAND layer
- Government-ready PDF provenance report via `rmarkdown::render()`
- Record-count histogram pre-gate (shows data void before species list renders)
- **Latency:** 2–5 min | **Target:** Field Museum, IBAMA/ICMBio, government assessors

### App 3 — BIEN Amazonia Trait & Diversity Explorer *(Research-grade)*
- All of App 2 plus:
- Functional diversity profile (CWM: wood density, SLA, height) vs. Amazonian benchmarks
- Stacked SDM richness estimate with explicit overestimation caveat (Calabrese et al. 2014)
- Field survey priority heatmap (10×10 km grid, exportable as GeoJSON for GPS)
- Comparative floristic analysis (upload existing inventory → Jaccard + omission audit)
- Future climate vulnerability sketch (CHELSA-CMIP6 SSP3-7.0 2070, optional)
- **Latency:** 3–10 min | **Target:** Research groups, macroecologists

---

## Key Technical Decisions

| Decision | Rationale |
|---|---|
| Use `st_intersects()` with actual polygon (not bbox) | Prevents Colombian/Peruvian range overflow |
| `natives.only = FALSE` in BIEN occurrence call | Amazonian `native_status` is largely `NA`; filtering drops real records |
| Coordinate QA: remove (0,0) and Brasília centroid artifacts | Known BIEN/GBIF artifact for Brazilian records |
| Filter `scrubbed_taxonomic_status == "Accepted"` with warning for Synonyms | Prevents duplicate names in output |
| Darwin Core-compliant CSV schema | Required for regulatory provenance |
| Access date + BIEN version in every export | Reproducibility and legal provenance |

## Known Data Limitations

1. **Severe sampling bias**: Alto Japurá is among the most botanically undersampled regions in BIEN. Records cluster along navigable rivers; interior upland terra firme is a botanical dark zone.
2. **WorldClim resolution (2.5 arc-min / ~4.5 km)**: Cannot distinguish terra firme from várzea from igapó — ecologically distinct floras conflated in the predicted list.
3. **BIEN range polygons are extrapolation in this region**: MaxEnt models trained on sparse records from adjacent regions; predictions are transfers into novel multivariate climate space.
4. **Trait data coverage**: <5% of predicted Amazonian species have BIEN trait records.
5. **Stacked SDM richness overestimates alpha diversity**: Calabrese et al. 2014 GEB 23(12):1365–1372. https://doi.org/10.1111/geb.12254

## Mandatory User-Facing Warnings (all apps)

> 1. This is not a survey — SDM ≠ confirmed presence.
> 2. Many species may be missing (especially range-restricted endemics and understory specialists).
> 3. Record density in this region is very low — see heatmap before interpreting results.
> 4. This list cannot replace field surveys for legal/regulatory use.
> 5. Model quality varies by species; record count is displayed as a quality proxy.

---

## BIEN R Functions Used

```r
BIEN_ranges_box(min.lat, max.lat, min.lon, max.lon)
BIEN_occurrence_box(min.lat, max.lat, min.lon, max.lon,
                    cultivated = FALSE, all.taxonomy = TRUE,
                    native.status = TRUE, natives.only = FALSE,
                    observation.type = TRUE, political.boundaries = TRUE)
BIEN_trait_species(species, trait.list = ...)
BIEN_list_all()
```

## Project Structure

```
BIEN Conservation Assessment Suite/
├── README.md                  — this file
├── chat_provenance_log.md     — running log of design decisions
├── data/
│   └── Japura_AOI_Nov2025_mapshaper.json   — pilot study area polygon
├── app/
│   └── app.R                  — App 2 (primary build target)
├── modules/
│   ├── mod_upload.R           — GeoJSON upload + validation
│   ├── mod_query.R            — BIEN API calls
│   ├── mod_species_table.R    — confidence scoring + table
│   ├── mod_traits.R           — optional trait fetch + CWM
│   ├── mod_map.R              — leaflet interactive map
│   └── mod_report.R           — downloadable Rmd report
├── utils/
│   ├── bien_queries.R         — wrapped, error-handled BIEN calls
│   ├── spatial_utils.R        — bbox, intersection, overlap helpers
│   └── confidence_utils.R     — tier assignment logic
├── report_template/
│   └── report.Rmd             — government PDF report template
├── www/
│   └── disclaimer.html        — mandatory warning text
└── docs/
    └── design_notes.md        — extended design notes from 2026-05-15 review
```

## References

- Calabrese JM et al. (2014). Stacking species distribution models and adjusting bias by linking them to macroecological models. *Global Ecology and Biogeography* 23(12):1365–1372. https://doi.org/10.1111/geb.12254
- Elith J et al. (2010). The art of modelling range-shifting species. *Methods in Ecology and Evolution* 1(4):330–342. https://doi.org/10.1111/j.2041-210X.2010.00036.x
- Fourcade Y et al. (2014). Mapping species distributions with MAXENT using a geographically biased sample of presence data. *PLoS ONE* 9(7):e99672. https://doi.org/10.1371/journal.pone.0099672
- Ter Steege H et al. (2013). Hyperdominance in the Amazonian tree flora. *Science* 342(6155):1243092. https://doi.org/10.1126/science.1243092
- Tuomisto H et al. (2003). Dispersal in a tropical rain forest. *Science* 299(5604):241–244. https://doi.org/10.1126/science.1078037
