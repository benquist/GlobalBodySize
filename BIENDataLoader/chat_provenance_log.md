# BIENDataLoader Chat Provenance Log

## 2026-04-24 — Match top header styling to BIEN-TraitsShinyApp exactly

**Prompt:** Update `BIENDataLoader/app.R` so the top header matches `BIEN-TraitsShinyApp/app_gateway.R` exactly for color scheme, logo size, and header typography.

**Summary:**
- Updated header CSS rules to exact Traits values for `.page-header`, `.bien-header-brand`, `.bien-logo`, `.page-header h1`, and `.page-header p`.
- Set `.page-header` margin to `-20px 0 20px 0` to match Traits.
- Removed divergent header typography overrides (`font-size`, `font-weight`, `line-height`) and removed mobile header/logo size overrides that diverged from Traits behavior.
- Kept required header markup structure for logo + title + subtitle and left all non-header/server logic unchanged.
- Requested syntax check run: `Rscript -e "parse(file='app.R')"`.

## 2026-04-24 — Header branding aligned to BIEN Traits sizing/typography

**Prompt:** Edit `BIENDataLoader/app.R` so top branding header (logo + text) matches BIEN-Traits header sizing and hierarchy, while keeping all server and non-UI behavior unchanged.

**Summary:**
- Replaced `navbarPage` title container with plain text: `title = "BIEN Data Loader"`.
- Added dedicated UI header block inside `header = tagList(...)` after `tags$head(...)` using `.page-header > .bien-header-brand` with `bien.png`, `h1`, and subtitle paragraph.
- Removed old navbar-brand CSS selectors (`.bl-brand`, `.bl-logo`, `.bl-brand-text`, `.bl-brand-title`, `.bl-brand-subtitle`).
- Added BIEN Traits-style header rules: `.page-header`, `.bien-header-brand`, `.bien-logo` (62px), `.page-header h1`, `.page-header p`.
- Updated mobile media query to `.bien-logo { height: 44px; }` and `.page-header h1 { font-size: 1.35em; }`.
- Kept existing navbar gradient and non-conflicting style rules unchanged.
- Syntax check run: `Rscript -e "parse(file='app.R')"` with explicit `PARSE_OK` confirmation.

## 2026-04-24 — UI-only BIEN branding refresh (no server logic changes)

**Prompt:** Implement a UI-only style update in BIENDataLoader/app.R and add BIEN logo asset for navbar branding, with strict constraint to avoid any server/reactive/API/data/pipeline/performance logic edits.

**Summary:**
- Added static BIEN logo asset at `BIENDataLoader/www/bien.png` (copied from `BIEN-TraitsShinyApp/www/bien.png`).
- Updated `navbarPage(...)` title branding in `app.R` from plain text to a left-aligned brand container with logo image, app title, and short subtitle; kept `id = "tabs"` unchanged.
- Reworked only the existing `tags$style(HTML("..."))` CSS block with BIEN palette variables, BIEN-like body gradient, gradient navbar + active-tab state, enhanced `.bl-card` styling, preserved `.bl-card-warn/.bl-card-block/.bl-card-pass`, BIEN gradient skins for `.btn-primary/.btn-success`, keyboard-visible focus styles, and mobile brand/logo responsiveness.
- No server logic, reactives, API endpoints, data functions, validation/mapping logic, or performance code was changed.

---

## 2026-04-24 — Plan 3 Cloudflare Workers relay: bug fixes + CF proxy implementation

**Prompt:** @M review BIEN Data Loader AWS IP block issue and implement Plan 3 — four CF Workers + 4 URL constant changes in app.R + fixes for two CRITICAL bugs (C1 GVS JSON, C2 GNRS writeback).

**Summary:**
- Root cause confirmed by code-checker: shinyapps.io/AWS IPs are blocked at TCP level by tnrsapi.xyz/gnrsapi.xyz etc. Not a code bug — a firewall rule on the API server side. Solution: Cloudflare Workers relay (Plan 3) routes all 4 API calls through CF's non-AWS IP space.
- **8 CF Worker files created** in `BIENDataLoader/cf-workers/{tnrs,gnrs,gvs,nsr}/`: `index.js` + `wrangler.toml` per service. Workers forward raw `arrayBuffer` POST bodies verbatim to upstream BIEN APIs; return raw upstream responses with CORS headers. Try/catch wraps upstream fetch → 502 on outage. OPTIONS preflight handled.
- **BUG C1 fixed**: GVS body construction replaced hand-rolled `paste0('{"opts":...}')` with `jsonlite::toJSON(list(opts=..., data=...), auto_unbox=TRUE)` — eliminates malformed JSON risk.
- **BUG C2 fixed**: GNRS writeback now matches country-only records. Previous `&` join required both country AND state to match; records with `NA` state_province were silently dropped. New `state_match` logic accepts rows where either side is blank/NA.
- **GVS coords fixed**: `as.numeric(trimws(...))` instead of `c(trimws(...), trimws(...))` — GVS API expects numeric coordinates, not quoted strings.
- **4 URL constants** added to top of `app.R` (TNRS_URL, GNRS_URL, GVS_URL, NSR_URL) with placeholder validation `warning()` if `YOUR_SUBDOMAIN` not yet replaced.
- **connecttimeout** reduced from 60→10s in all 4 POST calls (TCP connection either completes in ms or is blocked; 60s just made users wait longer for the same failure).
- code-checker: initially FAIL (4 warnings found). All 4 resolved. code-verifier: **APPROVED**.

**Next step for user:** Run `wrangler login` then `wrangler deploy` in each of the 4 cf-workers subdirectories, then replace `YOUR_SUBDOMAIN` in the 4 URL constants at the top of `app.R` with the actual workers.dev account subdomain shown by Wrangler, then redeploy to shinyapps.io.

---

## 2026-04-22 — Initial build

**Prompt:** User scrapped LoadingHistoricalObservationDataIntoBIEN as too slow/hung. Requested a new lighter Shiny app from scratch.

**Summary:** Built BIENDataLoader as a flat-reactiveValues Shiny app: 4-tab workflow (Upload & Merge → Map Fields → Stage & Validate → Export), vectorized DWC mapping and QC, optional TNRS/GNRS buttons, demo data included, code-checker + code-verifier approved.

**Commits:** 8e62da5 (initial), cc1c177 (TNRS/GNRS endpoint fix)

---

## 2026-04-23 — TNRS/GNRS timeout diagnosis and connect-timeout fix

**Prompt:** TNRS and GNRS requests were failing with connection timeout errors.

**Summary:** (1) Incorrect diagnosis of shinyapps.io TCP blocking corrected — real bug was httr default CURLOPT_CONNECTTIMEOUT of 10s. Fixed by adding httr::config(connecttimeout=60) to both POST calls. (2) Intermediate workaround (local R script download buttons) added as commit 20eacfa, then superseded by the connecttimeout fix in commit 97f0414.

**Commits:** 20eacfa, 97f0414

---

## 2026-04-24 — Restore connecttimeout=60/timeout=120 for all 4 web services

**Prompt:** TNRS in-app button showing "Connection timeout after 15001 ms". Root-cause analysis requested via @M agent.

**Summary:** code-checker diagnosed root cause: commit f655323 had reduced connecttimeout from 60→15s to "prevent long hangs", breaking TNRS/GNRS/GVS/NSR for shinyapps.io→AWS deployments. The self-hosted APIs need up to 60s TCP handshake from AWS. The 15001ms error exactly confirmed connecttimeout=15 was active (stale deploy). Fix: restored connecttimeout=60, timeout=120 for all 4 POST calls (TNRS, GNRS, GVS, NSR) matching confirmed-working commit 97f0414.

**Commits:** 00a4fc2

---

## 2026-04-23 — Session crash fix and DT server-side rendering

**Prompt:** App crashes with 'Disconnected from Server' when uploading user files and clicking Apply Mapping.

**Summary:** (1) Wrapped btn_prepare and btn_apply_mapping observers in tryCatch with showNotification. (2) Switched large DT tables to server=TRUE to prevent WebSocket buffer exhaustion.

**Commit:** 77425c1

---

## 2026-04-23 — Tab 4 download button fix (renderUI)

**Prompt:** Tab 4 download buttons were not working (silent 0-byte browser downloads).

**Summary:** (1) Moved download buttons to renderUI (dl_buttons_ui) — rendered only after rv\$staged is populated; (2) DWC button hidden if no terms mapped; (3) All four CSV downloadHandlers write an informative error CSV instead of return() when data is missing.

**Commit:** 1722cce

---

## 2026-04-23 — Three bugs from user CSV file testing

**Prompt:** User tested BIENDataLoader with real CSV files (Survey_Test1.csv — M/D/YY dates, trailing blank row). Three bugs found and fixed.

**Fixes:**
1. **Date parsing crash**: `as.Date("1/14/24")` errored with no format string. Fixed with `tryFormats=c("%Y-%m-%d", "%m/%d/%y", "%m/%d/%Y", ...)` — `%m/%d/%y` before `%m/%d/%Y` so 2-digit years map to 2000s.
2. **Blank row filtering**: Trailing blank row from `read.csv` filtered in both demo data and user upload paths.
3. **Download button re-binding**: Static download buttons moved back to UI (always registered); only a status indicator uses `renderUI` to fix re-binding failures.
4. **Separate run_qc tryCatch**: `run_qc` has its own `tryCatch` so staging/DWC always saved even if QC errors.

**Commit:** c6a59d1  
**Deployed:** https://benquist.shinyapps.io/bien-data-loader/

---

## 2026-04-23 — TNRS/GNRS AWS IP block diagnosis and UI update

**Prompt:** User reported TNRS connection timeout error (60001 ms) from shinyapps.io. Root cause: tnrsapi.xyz and gnrsapi.xyz are unreachable from AWS IPs used by shinyapps.io.

**Summary:** (1) Reduced `connecttimeout` from 60s to 15s so failure feedback is faster; (2) moved local-script download buttons above in-app TNRS/GNRS buttons and styled them green as the primary recommended path; (3) added UI note explaining cloud hosting / IP block situation; (4) relabeled in-app buttons to "Try ... in app (may timeout from cloud)" to set expectations.

**Commit:** f655323  
**Deployed:** https://benquist.shinyapps.io/bien-data-loader/

---

## 2026-04-23 — Download "Site wasn't available" fix: tryCatch + UTF-8 connection

**Prompt:** User reported "Site wasn't available" browser error page when downloading the BIEN staging table. Root cause: any unhandled error inside a `downloadHandler` content function crashes the HTTP connection; shinyapps.io proxy then shows a browser-level error instead of an R error message.

**Summary:**
1. Wrapped all 5 download content functions (`dl_staged`, `dl_dwc`, `dl_mapping`, `dl_qc`, `dl_packet`) in `tryCatch` — errors now write an error CSV so the connection completes cleanly.
2. Replaced `write.csv(..., fileEncoding="UTF-8")` with explicit `file(path, open="w", encoding="UTF-8")` connection in `safe_write_csv` — more reliable on shinyapps.io Linux locale.

**Commit:** 90663c2
**Deployed:** https://benquist.shinyapps.io/bien-data-loader/

---

## 2026-04-23 — Regex bug in sanitize_csv_col (Linux TRE engine)

**Prompt:** User got error CSV "Download failed: invalid regular expression ^[=+\-@], reason Invalid character range" — the tryCatch from the previous download fix exposed the internal R error message. Root cause: `^[=+\-@]` is an invalid character range on Linux TRE regex engine (shinyapps.io) because `\-` is treated as a literal hyphen forming a range `@-` backwards. Fixed by moving the hyphen to the end of the character class: `^[=+@-]`.

**Summary:** Single-character fix in `sanitize_csv_col()`. All 5 download handlers now work on both macOS PCRE and Linux TRE. The escaping approach (`\-`) is not portable across regex engines; terminal placement is the correct POSIX form.

**Commit:** 7110f84  
**Deployed:** https://benquist.shinyapps.io/bien-data-loader/

---

## 2026-04-23 — Expanded alias mapping tables (DWC_ALIASES and BIEN_ALIASES)

**Prompt:** Expanded DWC_ALIASES and BIEN_ALIASES to cover more real-world column header synonyms that were previously unmapped.

**New mappings added:**
- `data_recorder`, `recorder`, `surveyor`, `field_crew`, `technician`, `investigator` → `recordedBy` / `dataowner`
- `transect`, `station`, `quadrat` → `locality` / `plot_name`
- `herbarium`, `herbarium_code` → `institutionCode`
- `voucher`, `voucher_number`, `specimen_id`, `accession` → `catalogNumber` / `collection_code`
- `project`, `study`, `survey` → `datasetName` / `dataset`
- `alt`, `altitude`, `elev`, `elev_m` → elevation fields
- `habitat_description` → `habitat`

**Commit:** f5ccf08  
**Deployed:** https://benquist.shinyapps.io/bien-data-loader/

---

## 2026-04-23 — Reduce in-app TNRS/GNRS total timeout 120s → 25s

**Prompt:** User reported slow hang on TNRS/GNRS in-app buttons (app frozen for up to 120s when servers are reachable but slow).

**Root cause:** `httr::connecttimeout` only covers TCP handshake; `httr::timeout` controls the total response time. Both TNRS and GNRS POST calls used `httr::timeout(120)`, causing long freezes when the server is reachable but slow.

**Fix:** Reduced `httr::timeout` from 120 to 25 for both in-app TNRS and GNRS calls. Local R script download paths (for users running outside shinyapps.io) retain `httr::timeout(120)`. Updated Tab 3 UI note to say "~25s" so the user knows the expected wait.

**Commit:** a69984f  
**Deployed:** https://benquist.shinyapps.io/bien-data-loader/

---

## 2026-04-23 — Three bugs: primary file selection, negative coord sanitization, TNRS/GNRS writeback

**Prompt:** User reported wrong row counts (Acer negundo missing, Pinus ponderosa only 1 row instead of 2, Cecropia only 3 of expected), negative longitude showing as '-105.78 with apostrophe, and all scrubbed_* fields NA after TNRS/GNRS calls.

**Root causes and fixes:**

1. **Primary file auto-selection** — `primary_file` was selected alphabetically (Plot_Test1 before Survey_Test1). When dedup ran, it operated on the observation file's rows but used the shorter Plot file as "primary", dropping Acer negundo and duplicate species rows. Fixed: `primary_file` now selected as the file with the most rows.

2. **Negative coordinate sanitization** — `sanitize_csv_col()` regex `^[=+@-]` matched the leading `-` of negative numbers like `-105.78`, prepending an apostrophe. Fixed: skip values that parse as numeric (`suppressWarnings(!is.na(as.numeric(x)))`).

3. **TNRS/GNRS writeback to staging** — After a successful TNRS call, `rv$staged` was not updated with the matched accepted names. Fixed: writeback loop updates `scrubbed_species_binomial`, `scrubbed_family`, `scrubbed_genus`, `scrubbed_author`, `scrubbed_taxonomic_status` from matched TNRS results. After successful GNRS call, `country`, `state_province`, `county` updated from matched values.

**Commit:** 992433f  
**Deployed:** https://benquist.shinyapps.io/bien-data-loader/

---

## 2026-04-24 — Add GVS + NSR as steps 3 and 4 in BIEN web services pipeline

**Prompt:** User requested GVS (Geocoordinate Validation Service) and NSR (Native Species Resolver) be added to the workflow as sequential steps after TNRS and GNRS.

**API endpoints confirmed from GitHub (ojalaquellueva):**
- **GVS**: `https://gvsapi.xyz/gvs_api.php` — POST with unkeyed 2-col coordinate array `[[lat,lon],...]`; `opts.mode="resolve"`
- **NSR**: `https://nsrapi.xyz/nsr_wsb.php` — POST with 5-col data frame (`taxon, country, state_province, county_parish, user_id`); `opts.mode="resolve"`; returns transposed JSON (column names in `$id`, rows by numeric key)

**Implementation:**
- `rv$gvs_result` and `rv$nsr_result` added to reactiveValues; both cleared on source-switch and btn_prepare
- GVS observer: builds unique lat/lon pairs from `rv$staged`, sends as unkeyed array, renders results in new "GVS Results" tab
- NSR observer: builds unique taxon+location rows, sends to NSR, decodes transposed JSON, writes `native_status` back to `rv$staged`, renders results in new "NSR Results" tab
- Green download-script buttons for both GVS and NSR (local execution path)
- Tab 3 web services card description updated to explain all 4 steps (TNRS→GNRS→GVS→NSR)
- Export summary shows GVS/NSR run status; zip packet includes gvs_results.csv and nsr_results.csv
- GVS has TLS issue on macOS (packet length error) but works on Linux (shinyapps.io); local script also works on macOS when connected to gvsapi.xyz

**Commit:** 3170b78
**Deployed:** https://benquist.shinyapps.io/bien-data-loader/

---

## 2026-04-25 — Align BIEN_STAGING_FIELDS to BIEN DB schema; complete GVS+NSR writebacks

**Prompt:** User reported GVS and NSR results do not appear in the staging table. Requested that staging field names match the BIEN R package field names (from `view_full_occurrence_individual`).

**Root causes:**
1. **GVS writeback was absent** — GVS stored results in `rv$gvs_result` but never wrote to `rv$staged`.
2. **NSR writeback was incomplete** — only `native_status` was written; 6 additional BIEN DB fields were missing; join was species-only (no location key).
3. **`BIEN_STAGING_FIELDS` mismatched BIEN DB** — `is_cultivated` (wrong name); `is_centroid`, `native_status_reason`, `native_status_country`, `native_status_state_province`, `native_status_county_parish`, `is_introduced` all missing.

**Schema source:** Inspected BIEN R package source (`BIEN_occurrence_species`, `.native_check`, `.cultivated_check`, `.political_check`).

**Fixes applied (commit 48f7601):**
1. `BIEN_STAGING_FIELDS` updated: `is_cultivated` → `is_cultivated_observation`; added `is_centroid`, `native_status_reason`, `native_status_country`, `native_status_state_province`, `native_status_county_parish`, `is_introduced`.
2. **GVS writeback** added: matches staging rows by lat/lon (preferring `latitude_verbatim`), sets `is_centroid = "1"` if any of `is_country_centroid`/`is_state_centroid`/`is_county_centroid` is truthy; isolated in separate `tryCatch` block so `rv$gvs_result` always gets assigned even if writeback errors.
3. **NSR writeback** expanded: 3-key join (species + country + state_province via `\u001f` separator); defensive `stateProvince`/`state_province` column fallback for the NSR response; writes all 7 BIEN DB fields: `native_status`, `native_status_reason`, `native_status_country`, `native_status_state_province`, `native_status_county_parish`, `is_introduced` (from `isIntroduced`), `is_cultivated_observation` (from `isCultivatedNSR`).
4. Export summary note updated: references `view_full_occurrence_individual`.

**GVS caveat:** GVS has TLS 1.3 mismatch on macOS; works on Linux (shinyapps.io). Local download script is primary path for macOS users.
**NSR caveat:** Capped to 20 unique taxon/location combinations for in-app button. Requires TNRS + GNRS to run first for accurate results.
**is_centroid semantics:** BIEN DB filters `WHERE is_centroid IS NULL OR is_centroid = 0`; records flagged `is_centroid = "1"` would be excluded from standard BIEN queries — this flag is informational for the submitter.

**Commit:** 48f7601
**Deployed:** https://benquist.shinyapps.io/bien-data-loader/

---

## 2026-04-23 — Fix silent TNRS/GNRS/GVS/NSR button failures + raise timeouts

**Prompt:** User reported TNRS button "does not happen" after redeploy — no spinner, no error.

**Root cause:** All 4 web service observers used `req(rv$staged)` as their first line. After a redeploy, all Shiny server state resets to NULL. Clicking TNRS before running Apply Mapping in the new session caused `req()` to silently cancel the observer with no feedback to the user.

**Fixes:**
1. Replaced `req(rv$staged)` with explicit `if (is.null(rv$staged)) { showNotification(..., type="error"); return() }` in all 4 observers (TNRS, GNRS, GVS, NSR). Users now see a clear red error: "No staging table found — complete Steps 1-3 before running TNRS/GNRS/GVS/NSR."
2. Raised TNRS and GNRS in-app `connecttimeout` 15s → 30s, total `timeout` 25s → 60s (separate commit 96c7a9e).

**Note:** The underlying AWS IP block on tnrsapi.xyz/gnrsapi.xyz from shinyapps.io is unchanged — the longer timeout does not fix that. The local R script download buttons remain the primary path. The silent-failure fix (c9083db) is the more important change.

**Commits:** 96c7a9e (timeout increase), c9083db (silent failure fix)
**Deployed:** https://benquist.shinyapps.io/bien-data-loader/

---

## 2026-04-23 — Add upload-back CSV inputs for all 4 web services

**Prompt:** TNRS/GNRS in-app buttons time out from shinyapps.io. Users need to be able to run local scripts and feed results back into the app.

**Summary:** Added `fileInput` widgets and `observeEvent` upload handlers for all 4 services (TNRS, GNRS, GVS, NSR). Each upload handler reads the CSV, sets `rv$<service>_result`, and runs the identical writeback logic to the in-app button observer. This makes the full pipeline completable from shinyapps.io via: download script → run locally → upload CSV → staging table updated.

**Commit:** f4d8d2b
**Deployed:** https://benquist.shinyapps.io/bien-data-loader/

---

## 2026-04-24 — Step 3 service guidance copy under TNRS/GNRS/GVS/NSR controls

**Prompt:** Add short, practical user guidance under each BIEN web service block in Tab 3 (Stage & Validate), keeping current control ordering and style.

**Summary:** Added four small `tags$p` guidance lines directly below each service's upload/status controls in the yellow "Optional: BIEN Web Services" card:
- TNRS: accepted-name matching (WCVP/WFO), spelling/authorship standardization, scrubbed taxonomy fields
- GNRS: country/state/county standardization and misspelling/inconsistency checks
- GVS: centroid-flag QA for coordinate precision (non-destructive)
- NSR: native/introduced/cultivated status estimation by taxon + region for downstream filtering

**Validation:** `Rscript -e "parse(file='app.R'); cat('SYNTAX OK\\n')"` returned `SYNTAX OK`.

---

## 2026-04-24 — Tab 3 BIEN Web Services card requirement wording update

**Prompt:** In BIENDataLoader Tab 3 yellow BIEN Web Services card, remove optional framing and make requirement explicit for BIEN schema mapping.

**Summary:** Updated only the heading and guidance text in the existing yellow card:
- Heading changed from "Optional: BIEN Web Services" to "BIEN Web Services (Required for BIEN Schema Mapping)"
- Guidance now explicitly requires sequential execution for BIEN-schema-ready outputs: TNRS -> GNRS -> GVS -> NSR
- Guidance now states these steps populate/standardize BIEN fields and should be completed before final export to the BIEN staging table
- Cloud-timeout context retained and reworded without optional framing
- Existing download buttons, in-app action buttons, upload inputs, and status outputs kept unchanged

**Validation:** `Rscript -e "parse(file='app.R'); cat('SYNTAX OK\\n')"` returned `SYNTAX OK`.

## 2026-04-29 — Guided step-flow UX refinement (Scandinavian direction)

**Prompt:** Improve user guidance through BIEN Data Loader tabs: explicit Step 1 handoff to Tab 2 with rationale, stronger Tab 2 mapping instructions, dropdown-only approved Darwin Core/BIEN mapping choices, Step 2 modal handoff to Tab 3, and continued next-step guidance to Tab 4 without changing core data logic.

**Summary:**
- Added Step 1 completion modal with rationale and CTA navigation to `2 • Map Fields`.
- Strengthened Tab 2 instruction copy and mapping caption to emphasize dropdown-only approved terms (no free-typed BIEN/DWC strings).
- Kept Step 2 completion modal and added direct CTA navigation to `3 • Stage & Validate`.
- Consolidated Step 3 completion path to a single canonical modal/observer flow and explicit export handoff to `4 • Export`.
- Preserved core processing behavior; parse checks passed.
