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

---

## 2026-05-15 — Block 1: RBIEN sf-polygon migration + silent-failure guards + science framing

**User:** Brian Enquist  
**Request:** "If our agent team thinks that the workflow user uses shiny app to upload or draw a polygon -> shiny app then queries BIEN database using RBIEN functions that take a polygon to then extract species list then yes we should go for this and develop. I think it would be more efficient." → approve and implement Block 1 of the previously-vetted 3-block plan (consensus APPROVE-WITH-CHANGES from merow-ecology, stats-specialist/Telford lens, bio-units-specialist, enhanced-theory).

**Workflow now in code:** user draws or uploads polygon (GeoJSON / shapefile-zip / **KML/KMZ — new**) → AOI validated → polygon handed directly to PostGIS-backed RBIEN sf functions → results into existing tier/SDM pipeline. No more bbox-fetch + client-side clip.

### Block A — RBIEN sf migration (`utils/bien_queries.R`, `app/app.R`)
- A1: `BIEN_ranges_box(bbox)` → `BIEN::BIEN_ranges_sf(sf=poly, species.names.only=TRUE, return.species.list=TRUE, crop.ranges=FALSE, include.gid=FALSE)` + `BIEN_ranges_load_species(species=...)`.
- A2: `BIEN_occurrence_box(bbox)` → `BIEN::BIEN_occurrence_sf(sf=poly, cultivated=FALSE, new.world=NULL, native.status=TRUE, natives.only=FALSE, only.geovalid=TRUE, ...)`. Removed client-side bbox-then-clip.
- A3: KML / KMZ upload added to UI (`fileInput("kml_file")` + conditionalPanel) and to `get_polygon()` reactive (KMZ unzipped with Zip Slip mitigation, first .kml taken, `sf::st_read()`).
- A4: Removed dead `session$sendCustomMessage("toggleRunBtn", ...)` calls in `run_analysis` (start, success, error paths).

### Block B — silent-failure guards (`utils/bien_queries.R`, `utils/spatial_utils.R`, `app/global.R`)
- B1: `sf::sf_use_s2(TRUE)` enforced at startup in `global.R`; re-asserted in `.prepare_aoi_for_bien()` helper.
- B2: `sf::st_make_valid()` before every BIEN call.
- B3: Antimeridian refusal — stops if longitude span > 180°.
- B4: 5,000-vertex cap; auto-simplify with `sf::st_simplify(dTolerance = sqrt(area_m2)/1000)` + `showNotification()`.
- B5: `units::set_units(sum(sf::st_area(poly)), "km^2")` for area math in `validate_polygon()` (replaces unitless arithmetic).
- B6: CRS reproject to EPSG:4326 only with explicit `showNotification("Transformed AOI from EPSG:N to EPSG:4326")`.
- B7: Multi-feature centroid-distance check; warning if disjoint pieces > 25 km apart before silent union.

### Block E — science framing (`www/disclaimer.html`)
- E1: New disclaimer item — "Range Overlap Is Geometric, Not Probabilistic" — names `BIEN_ranges_sf()` / `BIEN_occurrence_sf()` and cites Maitner et al. 2018, *Methods in Ecology and Evolution* 9:373–379, DOI 10.1111/2041-210X.12861.
- E2: New disclaimer item — "Amazonian Range Maps Are Coarse" — cites ter Steege et al. 2011 (*Ecography* 34:737–747) and ter Steege et al. 2020 (*Scientific Reports* 10:10130); frames the species list as a lower-bound expectation.

### Pre-existing bug fixed in passing
- `app/app.R:45` — `tags$style(HTML("..."))` contained a CSS comment with literal embedded double-quotes (`/* Visible "analysis running" indicators */`) that terminated the outer R string and broke `parse()`. Replaced inner `"` with `'`. Bug predated this session.

### Validation
- `parse()` clean on all four edited files: `utils/bien_queries.R`, `utils/spatial_utils.R`, `app/global.R`, `app/app.R`. → **PARSE OK**.
- Local Shiny instance still running on `:7780` is the **stale pre-edit process** (PID 13104, started 2:38 PM) — needs kill + relaunch to actually exercise Block 1. No shinyapps.io deploy yet.

### Why "more efficient" (per user's framing)
- PostGIS does `ST_Intersects` server-side; no oversize bbox payload over the wire.
- One round trip instead of bbox-fetch + client-clip.
- Lower Shiny-session memory; no large intermediate to discard.
- Returned species list now matches "ranges that intersect this polygon" exactly, not "ranges that intersect the bbox, then clipped."
- Caveat (already in disclaimer): server-side intersection does not improve the underlying coarse range-map resolution — Maitner 2018 + ter Steege 2011/2020.

### Deferred within Block 1
- E3 (`only.geovalid` as user toggle, default TRUE) — not yet wired to UI; currently hardcoded TRUE.
- E4 (native / introduced / cultivated / unknown count breakdown in `output$native_status_summary`) — current output still only surfaces `likely_introduced` and `status_unavailable`.

### Status
- Block 1 code edits complete and parse-clean.
- Pending: E3 + E4 finish, code-checker subagent review of diffs, kill-and-relaunch local smoke test (draw + GeoJSON + KML/KMZ + shapefile), then Block 2 (parity test, CSV header metadata, UCUM units) and Block 3 (debounce, cancel-prior, bounded queue, cost pre-flight), then provenance + commit + push + always gate.

## 2026-05-15 — Performance optimization: eliminate 80+ min query bottlenecks

**Prompt**: Review BIEN conservation app for performance bottlenecks causing 80+ min runtimes on large polygons (e.g., Alto Japurá ~250,000 km²).

**Changes made**:
- `app/global.R`: `MAX_POLYGON_AREA_KM2` raised 50,000 → 500,000 km²; `plan(multisession, workers=2)` now explicit.
- `utils/bien_queries.R` `query_bien_ranges`: Replaced two-step `BIEN_ranges_sf(species.names.only=TRUE)` + `BIEN_ranges_load_species(species_vec)` with single `BIEN_ranges_sf(species.names.only=FALSE)` call — eliminates per-species shapefile download loop (primary bottleneck).
- `utils/bien_queries.R` `query_bien_occurrences`: Deduplication changed from `!duplicated(data.frame(...))` to `!duplicated(paste(..., sep="\x1f"))` — avoids full N-row object allocation on 1M+ records. Modal family changed from `sort(table(fam_vals))[1]` to `fam_vals[1L]` — O(1) vs O(n) per species group.
- `app/app.R` `run_analysis` fast future: Eliminated `query_species_list_fast(poly)` (redundant `BIEN_list_sf` PostGIS scan). Worker 1 now runs only `fetch_bien_occurrences_raw`; species universe derived directly from `occ_raw`. `rv$occ_counts` cached so slow future callback reuses it without recomputing.
- `utils/spatial_utils.R`: Updated validation comment to reflect new area cap.

**Agent**: optimizer mode (GitHub Copilot / Claude Sonnet 4.6)

---

## 2026-05-15 — Spatial filtering audit: polygon clip correctness fix

**User prompt:** "For the shiny app http://127.0.0.1:7780/ are we sure that we are querying just occurrence records within the polygon? Large number of species are showing up even in sparse regions like Greenland."

**Agents involved:** @m (supervisor), direct file edits

**Root causes identified:**
1. **Stale comments** in `app.R` and `bien_queries.R` still described an obsolete country-level Stage 1 approach (`BIEN_list_country`), even though the actual `query_species_list_fast()` function already used `BIEN_list_sf()` (polygon-specific PostGIS intersection). These misleading comments could cause future developers to misjudge the filtering approach.
2. **No client-side polygon clip in Stage 2**: `fetch_bien_occurrences_raw()` relied entirely on BIEN server-side clipping via `BIEN_occurrence_sf()`. The BIEN API has historically returned bounding-box results in some versions, potentially including records outside the exact polygon boundary.

**Changes made:**
- `utils/bien_queries.R`: Added defensive client-side `st_within` polygon clip inside `fetch_bien_occurrences_raw()`. After `BIEN_occurrence_sf()` returns, occurrence lat/lon are converted to sf points and checked with `sf::st_within(pts, sf::st_union(polygon_sf))`. Drops records outside the polygon; NA-coord rows pass through unchanged. Logs the count of dropped records. On clip error, retains all records rather than silently discarding everything.
- `utils/bien_queries.R` line 7: Corrected file-header comment from "Stage 1: country-level checklist" to "Stage 1: polygon-specific checklist via BIEN_list_sf".
- `app/app.R` header: Corrected Stage 1/2 description lines to reflect actual approach.
- `app/app.R` lines 385–393: Corrected Stage 1 architecture comment block in `run_analysis()` to say "Uses BIEN_list_sf() — a PostGIS spatial intersection against the drawn polygon" and to mention the Stage 2 `st_within` safeguard.

**Greenland note:** True Greenland polygons (centroid ~72°N) are blocked by `validate_polygon()` in `spatial_utils.R` (Americas bbox ymax = 55°N). The validator raises a hard error modal before any BIEN query runs, so Greenland species inflation cannot originate from Greenland polygons specifically. The complaint about "sparse regions like Greenland" likely referred to high-latitude or BIEN-data-poor regions where bounding-box vs. exact-polygon clipping makes a material difference.

**Verification:** All 5 source files parsed clean (`global.R`, `app.R`, `bien_queries.R`, `spatial_utils.R`, `confidence_utils.R`).

**Agent:** @m mode (GitHub Copilot / Claude Sonnet 4.6)
