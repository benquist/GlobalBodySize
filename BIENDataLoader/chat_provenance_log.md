# BIENDataLoader Chat Provenance Log

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
