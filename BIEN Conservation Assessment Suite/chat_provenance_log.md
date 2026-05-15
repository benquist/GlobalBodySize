# Chat Provenance Log — BIEN Conservation Assessment Suite

## 2026-05-15 — Project inception: three app design concepts

**User:** Brian Enquist (benquist@arizona.edu)  
**Request:** Design new Shiny app(s) for BIEN SDM-based conservation polygon assessment based on email from Nigel Pitman (Field Museum) requesting a predicted species list for the Alto Japurá basin, Brazilian Amazon (~1.6M ha), for submission to the Brazilian government. User asked @m to consult merow-ecology, coder, biodiversity-informatics-checker, and ecology-user agents to draft three potential app designs.

**Pilot GeoJSON:** `Japura_AOI_Nov2025_mapshaper.json` (attached in original request)  
**Study area:** Alto Rio Japurá (1,776,910 ha) + Alto Rio Içá (350,787 ha), western Brazilian Amazon, approx. -69° to -68°W, -2.6° to -1.2°S.

**Agents consulted:**
- `merow-ecology` — SDM methodology, assumptions, risks, transferability
- `ecology-user` (13-step framework) — data typing, scale, bias, integration, uncertainty, workflow architecture
- `biodiversity-science-guard` — taxonomy, Darwin Core, coordinate QA, BIEN-specific data quality

**Key findings:**
- BIEN SDM range polygons are binary MaxEnt-threshold outputs; no per-species AUC or uncertainty envelope is accessible via API.
- Western Amazonia is among the most botanically undersampled regions in BIEN. Records cluster along navigable rivers; interior terra firme is a botanical dark zone.
- `BIEN_ranges_box()` returns bounding-box results — mandatory `st_intersects()` with the actual polygon required to prevent Colombian/Peruvian range overflow.
- `native_status` is largely `NA` for Amazonian records; `natives.only = FALSE` is mandatory.
- WorldClim 2.5 arc-min cannot distinguish terra firme from várzea from igapó — ecologically distinct floras conflated.
- Automated plausibility gate using 5 anchor species (*Mauritia flexuosa*, *Iriartea deltoidea*, *Virola surinamensis*, *Cecropia latiloba*, *Euterpe precatoria*) recommended.

**Three app designs proposed:**
1. **BIEN Flora Scout** — upload polygon → tiered species list, plausibility anchor check, occurrence density heatmap, DwC CSV download. <2 min latency. Target: non-R users.
2. **BIEN Conservation Assessment Suite** (recommended) — adds IUCN Red List overlay, habitat stratification (várzea vs. terra firme via HAND), government PDF provenance report, record-count histogram pre-gate. 2–5 min latency.
3. **BIEN Amazonia Trait & Diversity Explorer** — adds functional diversity profile (CWM), stacked SDM richness estimate (with Calabrese et al. 2014 overestimation caveat), field survey priority heatmap (exportable GeoJSON), comparative floristic analysis (Jaccard vs. existing inventory), future climate vulnerability sketch. 3–10 min. Research grade.

**Recommendation:** Build App 2 first. App 1 deployable faster but lacks IUCN + provenance report for regulatory use. App 3 as follow-on after App 2 validated.

---

## 2026-05-15 — Phase 1 build: polygon modes, agent consensus, code review, and bug fixes

**Request:** User approved App 2 design. Requested two polygon input modes: (A) file upload/pilot polygon, (B) draw on map. User then said "Yes, begin phase 1. Go ahead and deploy to create the shiny app."

**Agents consulted:** stats-specialist, r-code-documenter, coder, code-checker, code-verifier

**Architecture decisions:**
- Two input modes: upload/pilot (`leaflet.extras::addDrawToolbar`) and freehand draw (`input$main_map_draw_new_feature`)
- Single BIEN API call pattern: `fetch_bien_occurrences_raw(polygon_sf)` → results passed to `query_bien_occurrences(occ_raw)` and `get_bien_occurrence_points(occ_raw)` to avoid duplicate API calls
- Confidence tiers: High / Moderate / Low / Very Low based on joint (n_occ, overlap_pct) thresholds
- Darwin Core CSV output with `basisOfRecord = "MachineLearning"`, `occurrenceStatus = "present (modeled — not field-verified)"`
- PDF via `pagedown::chrome_print()` (no LaTeX/tinytex on shinyapps.io)
- `natives.only = FALSE` mandatory for Amazonian records (native_status is largely NA)
- `sf::st_intersects()` with actual polygon applied after bbox query — never bbox-only filtering

**Files written (9 total):**
- `app/app.R`, `app/global.R`, `app/deploy.R`
- `utils/bien_queries.R`, `utils/spatial_utils.R`, `utils/confidence_utils.R`
- `modules/mod_map.R`
- `report_template/report.Rmd`
- `www/disclaimer.html`

**Code-checker findings and resolutions:**
- CRITICAL 1 (FIXED): `vapply` crash on multi-segment range intersections — fixed with `sum(as.numeric(sf::st_area(intersection))) / range_area * 100`
- CRITICAL 2 (FIXED): `get(family_col)` in dplyr summarise — fixed with `.data[[family_col]]`
- WARNING 1 (FIXED): `as.numeric(sf::st_area(polygon_sf)/1e6)` returns vector for multi-polygon; fixed with `sum(as.numeric(sf::st_area(polygon_sf)))/1e6` in `validate_polygon()`, `build_session_log()`, `map_info_box`, and `report.Rmd`
- WARNING 2 (FIXED): Removed `showNotification()` side effects from `get_polygon()` reactive; errors now return NULL silently and are handled by observer
- WARNING 4 (FIXED): Eliminated duplicate `BIEN_occurrence_box()` API call via new `fetch_bien_occurrences_raw()` refactor
- New WARNING from code-verifier (FIXED): Same `sum()` pattern missed in `app.R` map_info_box area display and `report_template/report.Rmd`

**Code-verifier verdict:** APPROVED WITH NOTES (all CRITICALs resolved; WARNINGs fixed; one minor inconsistency — pilot polygon error path still uses showNotification in reactive, low severity)

**Remaining Phase 2 items (not in Phase 1):**
- IUCN Red List pre-built lookup RDS (Phase 2)
- HAND raster integration for habitat stratification (Phase 2; too large to bundle — plan: COG on S3 via /vsicurl/ or pre-classified HydroSHEDS basin vector RDS)
- `plan(multisession)` dead code cleanup (future/promises loaded but unused)

**Action:** Project folder `BIEN Conservation Assessment Suite/` created with README, chat_provenance_log, data/, app/, modules/, utils/, report_template/, www/, docs/ scaffold.

**Status:** Design phase — no code written yet. Awaiting user direction on which app to build first.
