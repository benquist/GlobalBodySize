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
