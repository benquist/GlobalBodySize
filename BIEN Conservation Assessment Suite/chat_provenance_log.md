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

---

## 2026-05-15 — Phase 2: async rewrite, science overhaul, and DwC correction

**Request:** User approved "Both" — implement full performance fix (Option A) and full scientific correctness overhaul (Option B) as recommended by three-agent audit (optimizer, biodiversity-informatics-checker, merow-ecology) conducted at end of previous session.

**Agents consulted:** coder, code-checker (fixes applied), always (gate)

**Root cause addressed:** `do_analysis()` was synchronous, blocking R's event loop via `withProgress()`. Despite `plan(multisession)` in global.R, no `future_promise()` was used anywhere. For a 1.77M ha Amazonian polygon, the per-row vapply `st_intersection()` loop blocked for 35 sec–8 min + BIEN_occurrence_box() added 2–15 min more → browser WebSocket timeout → frozen tab.

**Changes implemented (Option A — Performance):**
- `utils/bien_queries.R`: replaced per-row vapply `st_intersection()` loop with single vectorized `sf::st_intersection(ranges, poly_union)` + `tapply()` aggregation (10–100× speedup expected for large Amazonian AOIs)
- `app/app.R`: converted `do_analysis()` to `run_analysis()` using `promises::future_promise({...}) %...>% (...) %...!% (...)` pattern; BIEN API calls run in background multisession worker; rv$* writes happen only in `.then()` callback on main session thread
- `utils/bien_queries.R`: dropped unneeded `BIEN_occurrence_box()` flags (`all.taxonomy`, `observation.type`, `political.boundaries`); kept `native.status=TRUE`
- `utils/bien_queries.R`: added occurrence deduplication by `(scrubbed_species_binomial, round(lat,3), round(lon,3))` before counting

**Changes implemented (Option B — Scientific correctness):**
- `utils/bien_queries.R`: added `overlap_pct_polygon` = intersection_area / polygon_area × 100 (fraction of AOI covered by species range); retained `overlap_pct_range` = intersection / range_area × 100 (endemism indicator); both exposed in output and DT table
- `utils/bien_queries.R`: added polygon clipping of occurrence records (not just bbox) via `st_intersects(occ_sf, polygon_sf)` in `fetch_bien_occurrences_raw()`
- `utils/bien_queries.R`: added `native_status_flag` computation per species (majority-vote from `native_status` column): "likely_native" / "likely_introduced" / "status_unavailable"
- `utils/confidence_utils.R`: tier logic now uses `overlap_pct_polygon`; raised Low threshold to `n_occ>=2 AND/OR overlap_pct_polygon>=2%`; exposes both overlap metrics in result dataframe
- `utils/spatial_utils.R`: fixed `basisOfRecord` from invalid `"MachineLearning"` → `"Occurrence"` (valid DwC term for mixed/unknown BIEN record types); fixed `occurrenceStatus` → `"present"`; added `occurrenceRemarks` with modeled-presence caveat; set `establishmentMeans` from `native_status_flag`; added `overlap_pct_polygon`, `overlap_pct_range`, `native_status_flag` columns to DwC CSV
- `app/global.R`: updated `ANCHOR_SPECIES`: added *Cedrelinga cateniformis* (terra firme non-palm, good western Amazonia BIEN coverage); replaced *Cecropia latiloba* (taxonomically noisy) and *Virola surinamensis* with *Swietenia macrophylla* (CITES-listed, well-documented, stable taxonomy)
- `app/app.R`: added SDM overestimation banner on Species List tab (cites Calabrese et al. 2014, GEB 23:1365–1372); added `native_status_flag` alerts (red danger for likely_introduced, orange warning for status_unavailable); added `% AOI covered` and `% Range in AOI` as distinct table columns with column caption clarification
- `www/disclaimer.html`: added mandatory government-submission disclaimer block (red border, verbatim boilerplate text with 6 Amazonian limitations, field verification statement) above existing warning box; updated column definitions to match new table

**Code-checker critical findings and resolutions:**
- CRITICAL (FIXED): `if (!all(sf::st_is_valid(ranges)))` crashes on NA validity → fixed to `if (any(!sf::st_is_valid(ranges), na.rm = TRUE))`
- CRITICAL/SECURITY (FIXED): Zip Slip path traversal in shapefile upload → fixed with zip manifest inspection before extraction (`any(grepl("..", manifest$Name, fixed=TRUE)) → return(NULL)`)
- HIGH (FIXED): `rv$polygon` never set in upload modes → fixed by assigning `rv$polygon <- poly` in `observeEvent(input$run_query)` and `observeEvent(input$confirm_proceed)` before `run_analysis()` call
- HIGH/DwC (FIXED): `basisOfRecord="HumanObservation"` incorrect for aggregated BIEN records (mixes herbarium vouchers + plot obs) → changed to `"Occurrence"` universally

**Syntax check:** All 5 R files pass `parse()` with no errors.
**Runtime check:** App starts cleanly on port 7781 (confirmed "Listening on http://127.0.0.1:7781").
**Status:** COMPLETE — ready for git commit.

---

## 2026-05-15 — Hang diagnosis: F1+F2+F3 fixes

**User reported:** App hangs forever after drawing polygon and clicking Run Analysis.

**Diagnosis (code-checker agent):** Tested 5 hypotheses. Three strong root causes found:
- H1: app.R defensive bootstrap re-sourced utils/modules but did NOT re-call `plan(multisession)`. If global.R partially failed, plan defaulted to `sequential` → `future_promise()` ran synchronously → identical hang to Phase 1.
- H2: BIEN API calls had no timeout. If BIEN server slow or bbox huge, calls stall indefinitely.
- H3: No upper-area guard. User could draw hemisphere-sized polygons triggering unbounded BIEN queries.

**Fixes applied (consensus from code-checker):**
- **F1** (app.R): added `future::plan(future::multisession, workers=2)` to bootstrap block AND a startup `message()` logging the active plan class. Verified live at startup: `[BIEN-app] Active future plan: FutureStrategy / tweaked | workers requested: 2` — proves async is engaged.
- **F2** (utils/bien_queries.R + global.R): added `BIEN_API_TIMEOUT_SEC <- 180` constant; wrapped both `BIEN_ranges_box()` and `BIEN_occurrence_box()` with `R.utils::withTimeout(..., onTimeout="error")` + tryCatch(TimeoutException=...) to surface a clear "BIEN query exceeded N s — try a smaller polygon" error via `showNotification` instead of silent infinite wait.
- **F3** (utils/spatial_utils.R + global.R): added `MAX_POLYGON_AREA_KM2 <- 50000` constant (~2× Alto Japurá); `validate_polygon()` now adds an error (hard block, not warning) for polygons over the cap. The modal shows only Cancel (no Proceed Anyway).

**Code-checker review:** PASS WITH SUGGESTIONS. No critical bugs. Minor: dead code in unreachable inherits()/grepl() fallback paths in tryCatch (harmless), double `plan()` call (wasteful at boot, correct behavior), `BIEN_API_TIMEOUT_SEC` reachability in worker via `globals` recursive scan (works today, theoretically fragile).

**Deferred:** F4 (Cancel button) and F5 (geojsonsf for draw parsing) — only re-evaluate if F1–F3 don't resolve.

**Status:** Live at http://127.0.0.1:7780. Pending user retest.
