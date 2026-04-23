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
