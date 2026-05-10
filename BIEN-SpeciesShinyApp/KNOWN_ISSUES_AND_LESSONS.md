# BIEN Species Shiny App — Known Issues and Lessons Learned

A running record of significant bugs, root causes, and lessons learned during
development of the BIEN Species Shiny App (https://benquist.shinyapps.io/bien-species-shinyapp/).

Each entry documents: the symptom, the diagnosis journey, the root cause, the fix,
and what it teaches for future development.

---

## Issue 1 — Species with zero mapped occurrence points despite thousands of BIEN records

**Date diagnosed:** 2026-05-09  
**Species confirmed affected:** *Pouteria reticulata* (Sapotaceae)  
**Likely broader impact:** Any species where BIEN's ingestion pipeline populated only the `geom` PostGIS column and left the float `latitude`/`longitude` columns NULL  
**Commits:** fdbc24f (v1), f670207 (v2), bef6b74 (v3), 769ea09 (v4), d3adcf6 (v5)

---

### Symptom

The app returned 2,000–3,800 occurrence records for the species in the statistics
panel but showed **0 mapped points** on the observation map. The coordinate quality
summary read: `valid coordinates: 0 | missing/out-of-range: 1000`. The app
reported `Occurrence strategy: strict` (no fallback triggered a map result).

---

### Diagnosis journey

Five rounds of investigation were required before the root cause was found.

**v1 hypothesis — biased row sampling**  
Suspected that BIEN's natural table order returned trait/plot rows first under
`LIMIT N` without `ORDER BY`, and those rows had null float coordinates while
specimen rows (which come later in the table) had valid coordinates.  
Fix: prioritize coord-valid rows in the R-level `sample_occurrence_rows()`
downsample before QA.  
Result: no improvement. The app still showed 0 mapped points.

**v2 hypothesis — SQL-level table-order problem**  
Added a `fallback_coord_bearing` plan with `AND latitude IS NOT NULL` in the
WHERE clause to force BIEN to return only coordinate-bearing rows.  
Result: made things **worse** — the SQL filter excluded ALL rows (because all
`latitude` values were NULL), returning 0 rows, and the previously returned
2,000-row result was discarded. Users saw a completely empty app.

**v3 — damage control + new fallback**  
Added `best_nonempty_result` tracking: if all coord-bearing plans return 0 rows,
return the first non-empty result anyway so the statistics table is populated.
Also added a `"no_coord_bearing_records_in_bien_view"` query_errors note to drive
a user-facing amber banner explaining the situation.  
Result: statistics table was restored, but map was still empty. Coordinates were
genuinely absent from the float columns for this species.

**v4 hypothesis — county-centroid exclusion filter**  
Suspected that `AND (georef_protocol IS NULL OR georef_protocol <> 'county centroid')`
and `AND (is_centroid IS NULL OR is_centroid = 0)` were excluding the only
coordinate-bearing records for this species.  
Added a `fallback_allow_centroids` plan that drops those two clauses.  
Result: still 0 mapped points. County centroid records also stored coords only in
`geom`, not the float columns.

**v5 — root cause found**  
Extracted the BIEN package binary source using `lazyLoad()` on
`/Library/Frameworks/.../BIEN/R/BIEN.rdb` and read the body of `BIEN_occurrence_sf()`.
That function revealed the view has **a PostGIS geography column `geom`** in
addition to the float `latitude`/`longitude` columns. `BIEN_occurrence_sf()` uses
`ST_Y(geom)` / `ST_X(geom)` for spatial intersection queries. The standard
`BIEN_occurrence_species()` function — and the app's custom SQL — select only the
float columns and never touch `geom`.

---

### Root Cause

`view_full_occurrence_individual` stores coordinates in **two parallel structures**:

| Column | Type | Populated by |
|--------|------|-------------|
| `latitude` | float8 | Older ingestion pipelines; not always back-filled |
| `longitude` | float8 | Same |
| `geom` | geography(Point, 4326) | Newer PostGIS-aware ingestion pipelines |

For *Pouteria reticulata* and potentially many other species, BIEN's data
ingestion wrote coordinates **only to `geom`** and left `latitude`/`longitude` as
NULL. `BIEN_occurrence_species()` itself has this same limitation — it would also
return NULL float coordinates for these species.

A secondary compounding issue: the app's SQL included custom filters not present
in BIEN's own API:

```sql
AND lower(coalesce(observation_type, '')) NOT LIKE '%trait%'
AND lower(coalesce(observation_type, '')) NOT LIKE '%measurement%'
```

These could exclude coordinate-bearing records where `observation_type` contains
those substrings (e.g. `'trait_observation'`, `'measurement_observation'`). Since
BIEN's own `BIEN_occurrence_species()` does not apply these filters, they were
unjustified and removed in v5.

---

### Fix (v5)

Replace the plain `latitude, longitude` SELECT with a COALESCE that falls back to
`ST_Y(geom::geometry)` / `ST_X(geom::geometry)` when the float columns are absent
or out-of-range:

```sql
COALESCE(
  CASE WHEN latitude BETWEEN -90 AND 90 THEN latitude ELSE NULL END,
  ST_Y(geom::geometry)
) AS latitude,
COALESCE(
  CASE WHEN longitude BETWEEN -180 AND 180 THEN longitude ELSE NULL END,
  ST_X(geom::geometry)
) AS longitude
```

The `CASE WHEN` range guard ensures that out-of-range non-null float values
(e.g. `latitude = 999`) fall through to `geom` rather than being returned
as-is. `ST_Y(NULL::geometry)` = NULL (safe, no exception).

The coord-bearing WHERE filter was also updated to accept either source:

```sql
AND (geom IS NOT NULL
     OR (latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180))
```

---

### Lessons learned

1. **Always extract the source of upstream library functions before writing custom SQL.**  
   Reading `BIEN_occurrence_sf()` source in five minutes would have revealed the
   `geom` column on day one. The pattern of using `lazyLoad()` on compiled `.rdb`
   files is the correct way to inspect BIEN internals when the package can't be
   loaded (due to the `RPostgreSQL` stub issue in local development).

2. **Don't add SQL filters that the upstream API doesn't use.**  
   The `NOT LIKE '%trait%'` filters were added defensively but were not in BIEN's
   own function. Any filter divergence from the official API is a risk surface —
   it can exclude records the API considers valid.

3. **Negative evidence (0 rows after a filter) is not the same as "no data exists."**  
   `AND latitude IS NOT NULL` returning 0 rows means "no rows with non-null float
   latitude" — not "no rows with coordinates." The distinction between the float
   columns and the geometry column was invisible without reading the view schema.

4. **When a fallback makes things worse (v2), preserve the original result.**  
   The `best_nonempty_result` pattern added in v3 — save the first non-empty
   result and return it if all coord-forcing plans exhaust — is a correct defensive
   pattern for any multi-plan cascade query system.

5. **ST_Y/ST_X geography→geometry casting is safe in PostgreSQL.**  
   `NULL::geometry` → NULL. Functions applied to NULL return NULL. The cast
   `geom::geometry` from a geography type is well-defined in PostGIS and does not
   throw. This is safe to use broadly in fallback COALESCE expressions.

6. **The `geom` column likely affects a non-trivial fraction of BIEN species.**  
   Species with heavy herbarium specimen coverage from institutions using newer
   GBIF-style ingestion workflows are the most likely to have coordinates stored
   only in `geom`. Neotropical tree species are disproportionately represented in
   this category.

---

## Issue 2 — App frozen / blank on startup: synchronous HTTP photo fetch blocking the Shiny event loop

**Date diagnosed:** 2026-05-09  
**Commits:** 0bc1ec7, 757da51

---

### Symptom

After a species photo feature was added, the app began timing out and disconnecting sessions on startup at https://benquist.shinyapps.io/bien-species-shinyapp/. Users saw a blank or frozen app within seconds of opening it, even before entering a species name.

---

### Diagnosis journey

Code-checker and optimizer agents reviewed `app.R` and found two CRITICALs.

**CRITICAL 1 — Synchronous HTTP inside `renderUI`**  
The species photo fetch (`fetch_species_photo()`) was called directly inside a `renderUI({...})` block. Because `bien_results()` immediately returns `startup_preloaded_result` at session start, the `renderUI` fired during the initial render flush — before the session was fully established — and made synchronous HTTP calls to iNaturalist (up to 5 s) and Wikipedia (up to 5 s). On shinyapps.io's free tier this blocked the Shiny event loop for up to 10 seconds, causing startup timeouts and session disconnects.

**CRITICAL 2 — `return(NULL)` inside `tryCatch` exiting the wrong scope**  
Both `tryCatch({...})` blocks inside `fetch_species_photo()` used `return(NULL)` as an error guard. In R, `return()` inside a `tryCatch` expression exits the **enclosing function**, not the tryCatch block. This made the Wikipedia fallback unreachable for every failure mode except a thrown R exception — the function returned NULL immediately on any HTTP failure without ever trying Wikipedia.

---

### Root Cause

Two independent bugs in the photo feature:
1. Network I/O placed in a reactive render path that runs at session startup.
2. Misuse of `return()` inside `tryCatch` — a subtle R scoping issue.

---

### Fix

1. Photo fetch moved into `observeEvent(bien_results(), ..., ignoreNULL=TRUE)` with an `is_startup_preloaded` guard that returns immediately at startup. `renderUI` now reads only from `species_photo_rv <- reactiveVal(NULL)` — no network I/O in the render path.
2. All `return(NULL)` guards inside `tryCatch` replaced with `stop("reason")` so the `error = function(e) NULL` handler returns NULL from the block and execution continues to the Wikipedia fallback.
3. NULL photo results no longer cached permanently — only non-NULL photos assigned to `query_cache` so transient network failures are retried on the next query.

---

### Lessons learned

1. **Never put network I/O inside `renderUI`, `renderPlot`, or any reactive render function.** These fire synchronously during the event loop. All external fetches belong in `observe()`, `observeEvent()`, or `reactive()` with appropriate guards.
2. **`return()` inside `tryCatch({...})` exits the enclosing function, not the tryCatch block.** Use `stop("reason")` inside the `try` expression to trigger the `error = function(e)` handler. This is one of R's most commonly misunderstood scoping rules.
3. **Startup preloaded results trigger reactive chains immediately.** Any reactive that depends on `bien_results()` will fire at session start if `bien_results()` returns a non-NULL value — guard all side-effectful observeEvents with `ignoreNULL=TRUE` and startup-state checks.

---

## Issue 3 — App frozen: BIEN COUNT queries blocking the event loop

**Date diagnosed:** 2026-04-01  
**Provenance log entries:** 5, 7

---

### Symptom

The app hung and became unresponsive after the Summary Statistics tab was opened, or sometimes immediately on load. Shinyapps.io logs showed the session timing out during BIEN database queries.

---

### Diagnosis journey

Initial investigation (entry 5): BIEN count-only summary queries (`COUNT(*)`) were placed in the first-load critical path — they ran synchronously before the occurrence map rendered, blocking the entire app until BIEN's backend responded. For species with large record sets, this could take 30–60 seconds.

Second occurrence (entry 7): After moving counts to the Summary Statistics tab, opening that tab still triggered synchronous BIEN queries that froze the UI.

---

### Root Cause

Shiny's single-threaded R process means any long-running synchronous call — including BIEN database queries — blocks all UI updates for the duration. COUNT queries on BIEN's `view_full_occurrence_individual` for large species (e.g. *Solidago canadensis*, *Pinus ponderosa*) can take 30–90 seconds. Placing these in reactive render paths or the session startup sequence makes the app appear frozen.

---

### Fix

COUNT queries moved behind a manual button trigger in the Summary Statistics tab. Users click "Get summary statistics" to initiate the query rather than having it fire automatically. This keeps the app responsive and gives users explicit control over when to incur the query cost.

---

### Lessons learned

1. **BIEN COUNT queries on large species are slow — do not run them automatically.** Any `COUNT(*)` against `view_full_occurrence_individual` without a tight LIMIT can take minutes for widespread species. They belong behind explicit user actions, not in render paths.
2. **Shiny's event loop is single-threaded.** There is no background execution by default. Any blocking call (BIEN query, HTTP request, file I/O) freezes all UI updates for all users sharing the process on shinyapps.io free tier.
3. **Progressive disclosure is the right pattern for expensive secondary data.** The occurrence map is the primary value; statistics, traits, and range are secondary. Load them on demand, not on startup.

---

## Issue 4 — FIA/plot sampling bias: large species dominated by plot records in occurrence map

**Date diagnosed:** 2026-04-01  
**Provenance log entry:** 9  
**Species confirmed affected:** *Juniperus communis*, *Pinus ponderosa*

---

### Symptom

For widespread North American tree species, the occurrence map was dominated almost entirely by FIA forest inventory plot points arranged in a grid-like pattern. Herbarium specimens and iNaturalist records — which have different geographic signatures — were nearly invisible even though they existed in BIEN.

---

### Root Cause

BIEN's `view_full_occurrence_individual` returns rows in natural PostgreSQL table order when no `ORDER BY` clause is used. FIA plot records are ingested in bulk and occupy a contiguous block of rows in the table. Under `LIMIT N` without randomization, the app retrieved the first N rows — which were overwhelmingly FIA rows — ignoring the full diversity of data sources.

---

### Fix

Added `ORDER BY random()` to the BIEN occurrence SQL query so that the returned sample is randomized across all matching rows regardless of table order. Added stratified display-sampling by datasource/observation type so each source class is represented proportionally in the displayed map sample.

**Important caveat added later (v5):** `ORDER BY random()` was subsequently restricted to queries with `500 < limit <= 10000` because it forces a full-table sort on BIEN's 100M+ row view for large species, which can take minutes. For small limits (≤500), natural order + R-side stratified sampling is sufficient. For very large limits (>10000), the query is too expensive to randomize server-side.

---

### Lessons learned

1. **`LIMIT N` without `ORDER BY` on a large PostgreSQL view returns whatever rows come first in table storage order.** For BIEN this means whichever datasource was ingested first dominates the result. Always randomize or stratify when the goal is a representative sample.
2. **`ORDER BY random()` has a hidden cost: it forces a full sequential scan of all matching rows before sampling.** For a view returning millions of rows this can take minutes. Restrict randomization to moderate limit sizes and use R-side stratification for small fast queries.
3. **Stratified sampling by datasource is scientifically more defensible than pure random sampling** for occurrence data, because datasource coverage is geographically non-uniform. A random sample of 1000 from a pool of 900,000 FIA + 1,000 specimens will return ~999 FIA rows; stratification ensures specimens are represented.

---

## Issue 5 — Tooltip double-popup: two tooltip systems rendering simultaneously

**Date diagnosed:** 2026-04-09  
**Provenance log entries:** 13, 15, 17

---

### Symptom

Filter info icons in the Settings/Filters sidebar showed two tooltip popups on hover — one white (custom) and one black (Bootstrap). The black Bootstrap tooltip did not disappear on mouse leave, leaving a persistent floating label on screen.

---

### Diagnosis journey

Entry 13: Added Bootstrap `data-toggle="tooltip"` attributes and called `$(function() { $('[data-toggle="tooltip"]').tooltip(); })` to initialize. This activated Bootstrap's tooltip plugin but the custom hover CSS was still active — two systems rendered simultaneously.

Entry 15: Added a framework-independent JavaScript fallback tooltip to handle cases where Bootstrap's plugin was unavailable. This created a third potential tooltip layer.

Entry 17: Removed Bootstrap attributes and Bootstrap tooltip initialization entirely, leaving only one tooltip system.

---

### Root Cause

Two independent tooltip implementations were active at the same time: Bootstrap's jQuery plugin (triggered by `data-toggle="tooltip"`) and a custom CSS/JS tooltip. Each rendered its own popup on hover.

---

### Fix

Removed all Bootstrap `data-toggle="tooltip"` attributes and the Bootstrap `.tooltip()` initialization call. Kept only one custom tooltip implementation.

---

### Lessons learned

1. **Pick one tooltip system and use it consistently.** Bootstrap, custom CSS, and Shiny's built-in `title=` attribute each activate different rendering paths — mixing them produces duplicate popups.
2. **Shiny apps on shinyapps.io may load Bootstrap versions that conflict with app-level jQuery plugin calls.** Test tooltip behavior in the deployed environment, not just locally, since the Bootstrap version may differ.

---

## Issue 6 — `Lucky` / random species selection freezing the app

**Date diagnosed:** 2026-04-09  
**Provenance log entry:** 16

---

### Symptom

Clicking the random species ("Lucky") button caused the app to freeze for 30–90 seconds or time out entirely, even though the intent was a fast "surprise me" species selection.

---

### Root Cause

The Lucky workflow ran sequential BIEN COUNT prechecks for each candidate species to verify it had mappable records before selecting it. Each COUNT query against `view_full_occurrence_individual` could take 30+ seconds for large species. Verifying even 2–3 candidates before finding one with mappable points could exhaust the query budget and cause a session timeout.

---

### Fix

Replaced the sequential precheck loop with an immediate return from a curated starter pool (`starter_pool_fast_pick`). No BIEN prechecks are run — a species is selected instantly and the normal occurrence query runs after selection. If the species turns out to have no mappable points, the standard zero-mappable UI message is shown. The Lucky UI notification text was updated to reflect whether the pick was range-verified or a fast starter pick.

---

### Lessons learned

1. **Never use synchronous BIEN COUNT queries in an interactive button handler.** The user expects a fast response; BIEN queries are not fast.
2. **"Optimistic" UX is often better than "verified" UX for exploratory features.** Select the species immediately and let the normal query path handle failures, rather than pre-validating before showing anything.
3. **The cost of verification is often higher than the cost of a failed query.** Showing "no results found" after 2 seconds beats freezing for 60 seconds to guarantee a result.

---

## Issue 7 — `sprintf("%,d")` format crashing Temporal Distribution tab

**Date diagnosed:** 2026-04-13  
**Provenance log entries:** 22, 23

---

### Symptom

The Temporal Distribution tab displayed: *"Temporal stats — An error has occurred. Check your logs or contact the app author for clarification."* The error appeared immediately on opening the tab for any species.

---

### Diagnosis journey

Entry 22: Added `req(bien_results())` to prevent the handler from running before results were available. Error persisted.

Entry 23: Checked shinyapps.io logs. The actual error was `unsupported format '%,d'` in `sprintf()` — R's `sprintf` does not support the C-style `%,d` thousands-separator format (which is a Python/Java convention). The fix worked.

---

### Root Cause

`sprintf("%,d", n)` was used to format a count with a thousands separator. R's `sprintf` does not implement `%,d` — this format string is valid in some other languages but throws in R.

---

### Fix

Replaced `sprintf("%,d", n)` with `format(n, big.mark = ",")`, which is the correct R idiom for thousands-separated integer formatting.

---

### Lessons learned

1. **R's `sprintf` does not support `%,d` for thousands separators.** Use `format(n, big.mark = ",")` or `formatC(n, format = "d", big.mark = ",")` instead.
2. **Always test tab-level render handlers with a NULL-results state.** A `req()` guard is necessary but not sufficient — errors inside the render body still crash the tab even when results are available.
3. **Check shinyapps.io logs for the actual R error message, not just the user-facing "an error has occurred."** The log shows the exact line and call stack; the UI message is useless for diagnosis.

---

## Issue 8 — Selectize autocomplete: typed text disappearing / free-form names not submitting

**Date diagnosed:** 2026-04-21  
**Provenance log entries:** 28, 30

---

### Symptom

After replacing the species name free-text input with a selectize autocomplete backed by BIEN taxonomy:
- Typed characters disappeared as the user typed, resetting the input to empty.
- Misspelled names (e.g. "Pinus pinderosa") submitted nothing — no fuzzy match was attempted.
- The startup species (*Pinus ponderosa*) did not appear in the input box even though the map loaded correctly.

---

### Diagnosis journey

**Text disappearing:** The accepted species name list was being reloaded on every keystroke inside an `observe()` that watched `input$species`. Each reload called `updateSelectizeInput()` which reset the choices and cleared the current input value.

**Misspellings not submitted:** `selectize` was initialized with `create = FALSE`, meaning free-form text that didn't exactly match a choice was silently discarded. The fuzzy-match logic (`find_best_species_spelling()`) never received the misspelled name because it was never submitted to the server.

**Startup species not shown:** `selectizeInput` was initialized with `choices = NULL` (empty), so the startup value had no matching choice and was not displayed.

---

### Fix

1. Move the accepted-name list load to a `once = TRUE` `observeEvent(TRUE, ...)` that runs once at session start, not on every keystroke.
2. Set `create = TRUE, createOnBlur = TRUE` in selectize options so free-form typed text is submitted as-is. The existing fuzzy-match logic then handles misspellings server-side.
3. Initialize `selectizeInput` with `choices = list(STARTUP_SPECIES)` so the startup value has a matching choice and displays immediately.

---

### Lessons learned

1. **Do not reload selectize choices inside a reactive that watches the same input.** This creates a feedback loop: input changes → reload → reset → input changes again.
2. **`create = FALSE` in selectize silently discards unmatched input.** If fuzzy matching or free-form names matter, use `create = TRUE` and handle validation server-side.
3. **Selectize `choices` must include the initial value** or the startup value will not render even if `selected` is set correctly.

---

## Issue 9 — BIEN connection-slot exhaustion: live species returning 0 records

**Date diagnosed:** 2026-04-01  
**Provenance log entry:** 10  
**Species confirmed affected:** *Juniperus communis* (during live session)

---

### Symptom

A species known to have thousands of BIEN records (*Juniperus communis*) returned 0 observations during a live demo session. No error message was shown — the app simply displayed an empty map as if the species had no data. Re-querying the same species minutes later returned results normally.

---

### Root Cause

BIEN's public PostgreSQL database at `vegbiendev.nceas.ucsb.edu` has a fixed connection-slot limit. When multiple concurrent app users or background processes exhaust the available slots, new connections are refused. The `BIEN` R package raised a connection error that the app silently caught and returned an empty result as if the query succeeded with zero rows.

---

### Fix

Added a backend-capacity warning message that appears when a connection error is detected. The message distinguishes between "species not found in BIEN" (a real absence) and "BIEN connection refused" (a backend capacity issue), and provides explicit retry guidance including a `Retry BIEN connection (with backoff)` button with exponential-backoff logic.

---

### Lessons learned

1. **A zero-result response and a connection-refused error look identical to the user if both result in an empty map.** Always distinguish backend failures from true data absences in the UI.
2. **Public shared databases have connection limits.** Design retry logic and user communication for connection exhaustion, not just query errors.
3. **Exponential backoff with a visible retry button is better than silent automatic retry** for a UI context where the user wants to know what happened.

---

## Issue 10 — "Keep native only" label misleading: includes unknown-status records

**Date diagnosed:** 2026-04-21  
**Provenance log entry:** 27 (SC-1)

---

### Symptom

The filter checkbox labeled "Keep native only" implied it returned strictly native BIEN records. In reality, the underlying query function `natives_check_with_null_fallback()` returned records where `is_introduced IS NULL OR is_introduced = FALSE` — meaning records with unknown nativity status were included alongside confirmed native records.

---

### Root Cause

The BIEN database `is_introduced` column is NULL for the majority of records (nativity status is unknown or unpublished). Filtering to `is_introduced = FALSE` alone would exclude the bulk of BIEN's data. The app's query function therefore includes NULL-status records as a fallback, but the UI label did not communicate this.

---

### Fix

Relabeled the checkbox to "Keep native / unknown-status only" to accurately describe the filter behavior. Tooltip text updated to explain that many BIEN records lack explicit nativity determination and are included as unknown-status.

---

### Lessons learned

1. **BIEN `is_introduced` is NULL for most records.** A strict `is_introduced = FALSE` filter will return far fewer records than expected. Plan for NULL as a valid "unclassified" state.
2. **UI label language must match the actual query semantics.** "Native only" implies a strict filter; "native / unknown-status" correctly sets expectations.
3. **Document NULL-handling behavior in filter tooltips.** Ecological users will interpret "native" differently depending on their field — be explicit about what the filter actually does.

---

## Issue 11 — Per-session blocking operations: autocomplete load and startup preload running per user

**Date diagnosed:** 2026-04-21 / 2026-05-08  
**Provenance log entries:** 27 (H1), 28

---

### Symptom

After the species autocomplete was added, every new user session experienced a 30–60 second stall before the species name box became usable. The first user to open the app each deploy cycle also experienced a slow map load for the default startup species (*Pinus ponderosa*).

---

### Root Cause

Two functions that produced session-invariant data were called inside `session`-scoped reactive contexts, meaning they re-ran for every new user:

1. `load_accepted_species_suggestions()` — fetched all accepted species binomials from BIEN taxonomy (~75,000 names). This was called inside an `observe()` that ran once per session at startup, taking 30–60 seconds per session instead of 30–60 seconds once at app startup.
2. `build_preloaded_startup_result()` — ran the full occurrence query for the startup species. Same problem: called per session instead of once globally.

---

### Fix

Both functions moved to **global scope** — executed once when the Shiny app process starts, shared across all sessions:
- `startup_species_suggestions` — global variable holding the accepted-name list; sessions call `updateSelectizeInput()` using this pre-loaded vector.
- `startup_preloaded_result` — global variable holding the pre-queried startup species result; sessions read from it directly without re-querying BIEN.

---

### Lessons learned

1. **Session-invariant data should live in global scope in Shiny, not inside reactive session contexts.** Global scope runs once at process start and is shared across all concurrent sessions.
2. **The cost of a per-session load at 100 users/day is 100× the cost of a once-at-startup load.** For data that doesn't change (taxonomy list, curated starter pool), global scope is almost always correct.
3. **`observe()` and `observeEvent()` inside `server <- function(input, output, session)` run once per session, not once per app.** Only code in the global scope (outside the `server` function) runs once per app process.

---

## Issue 12 — `ORDER BY random()` query timeout on large BIEN tables

**Date diagnosed:** 2026-04-21  
**Provenance log entry:** 27 (H2)

---

### Symptom

The `fetch_random_bien_species_pool()` function timed out for large species with many BIEN records. The random pool fetch was intended to be fast, but caused the app to hang for widespread species.

---

### Root Cause

The SQL query used `ORDER BY random()` with `LIMIT N` against `view_full_occurrence_individual`. PostgreSQL cannot use an index for `ORDER BY random()` — it must scan all matching rows, assign a random number to each, then sort the full set before applying the LIMIT. For a species with 500,000 records, this means sorting 500,000 rows for a 100-row LIMIT.

---

### Fix

Removed `ORDER BY random()` from the SQL query. The app now retrieves rows in natural table order (fast) and shuffles with `sample.int()` in R after retrieval. For the pool-fetch use case (selecting a random display sample from returned rows), R-side shuffling is equivalent and eliminates the full-table sort cost.

---

### Lessons learned

1. **`ORDER BY random()` in PostgreSQL forces a full sequential scan of all matching rows before sampling.** For large tables this is O(n log n) — never use it for interactive queries without a tight LIMIT on the filtered set, not the full table.
2. **For random sampling from a query result, retrieve in natural order and shuffle in R.** R's `sample.int()` or `dplyr::slice_sample()` are fast in-memory operations.
3. **The exception:** `ORDER BY random()` is acceptable when the filtered result set is small (< ~5,000 rows) and server-side randomization is required for reproducibility. For BIEN, most species exceed this threshold.

---

## Issue 13 — Download tab reproducibility gaps: scripts labelled "reproducible" that cannot actually reproduce the same result

**Date diagnosed:** 2026-05-09  
**Implemented:** 2026-05-09  
**Review agents:** coder (code analysis), biodiversity-informatics-checker, biodiversity-science-guard, Richard Telford statistical-ecology framework  
**Implementation agents:** m (supervisor), coder, always  
**Commits:** `73ec262` (app.R, BIEN-SpeciesShinyApp repo), `82f58a0` (prompt_log.md, parent workspace)  
**Deployed:** shinyapps.io `bien-species-shinyapp` (same session)  
**Status:** RESOLVED — all agreed fixes implemented and deployed

---

### Symptom

The Download tab presents three R script files and three CSV downloads under the heading "reproducible R code." A multi-agent review of the download logic found that the scripts contain at least four independent ways in which the output would differ from the app result shown to the user, and several additional ways in which the scripts would fail silently or produce errors when run by a new user.

---

### Diagnosis

**1. CSV provenance header breaks `read.csv()`**  
`downloadHandler` for all three CSVs prepends `#`-prefixed comment lines (species, date, filters) using `writeLines()`, then appends actual CSV rows with `write.table(..., append = TRUE)`. The resulting file is not valid CSV. A user running `read.csv("file.csv")` will either import the `#` lines as data rows or crash with a parse error. No `skip=` instruction is documented anywhere.

**2. No `set.seed()` — sampling is stochastic**  
The occurrence repro script calls `sample.int()` and `dplyr::slice_sample()` inside `sample_occurrence_rows()`. No seed is set anywhere in the generated code. The Download tab UI states *"This script reproduces the exact occurrence dataset currently shown in the Observations tab."* This is false: every run of the script produces a different random sample of rows. The species, query flags, and filters are reproducible; the specific rows are not.

**3. Private BIEN internal functions in user-facing scripts**  
The occurrence script calls `BIEN:::.cultivated_check()`, `BIEN:::.BIEN_sql()`, `BIEN:::.native_check()`, `BIEN:::.geovalid_check()`, etc. These are unexported internal functions (prefix `.`). They can be renamed, removed, or changed in any BIEN release without a deprecation notice. A user who upgrades BIEN and reruns the script may get a silent error or wrong results with no diagnostic message.

**4. Plot/community script depends on an intermediate file**  
`build_plot_repro_script()` embeds the entire occurrence script, runs it to write a CSV, then reads that CSV back with `read.csv(out_file)` and filters to `observation_category == "Plot / survey"`. If the working directory already contains a same-named file from a different species or filter run, the read-back silently uses stale data. This is a latent data-leakage bug.

**5. Missing citation block in all scripts and CSVs**  
Neither the scripts nor the CSV provenance headers include the BIEN publication:  
*Enquist et al. (2026). BIEN: Botanical Information and Ecology Network. Methods in Ecology and Evolution. DOI: 10.1111/2041-210x.70274.*  
Users who publish with this data and copy the script header have incomplete attribution.

**6. No `sessionInfo()` — environment is not captured**  
Nothing records the R version, OS, or package versions at run time. A collaborator running the same script two years later has no record of what environment produced the original data.

**7. Trait script has no plain-language header**  
The occurrence and plot scripts have a multi-line comment header (species, strategy, effective flags, sampling mode). The trait script has only `# Reproducible BIEN trait dataset script` and immediately calls `library(BIEN)`. The `limit=` parameter truncation is also not disclosed: if BIEN holds more trait records than `trait_limit`, the returned table is a silent subset.

**8. No ZIP README, no install instructions, no data dictionary**  
The ZIP bundle contains six files with no explanation of contents, no required citation, no instructions for loading CSVs (with or without the `skip=` fix), and no description of the BIEN column schema.

---

### Root Cause

The Download tab was built incrementally alongside the query and map features; reproducibility properties of the generated scripts were not systematically validated. The scripts expose the app's internal query logic (including the private BIEN SQL helpers) rather than being rewritten from scratch to use the public BIEN R API.

---

### Agreed Fix Plan — Implementation Status

All items were implemented in `app.R` commit `73ec262` and deployed to shinyapps.io on 2026-05-09.

| Rank | Issue | Severity | Status |
|------|-------|----------|--------|
| 1 | Fix CSV provenance header — make files valid CSV; move metadata to README.txt sidecar in ZIP | CRITICAL | ✅ Done |
| 2 | Add `set.seed(42)` to occurrence and plot scripts with explanation | CRITICAL | ✅ Done |
| T-A | Change script language from "reproduces the **exact** dataset" to an honest statement | HIGH | ✅ Done |
| 3 | Replace `BIEN:::.*` private calls with public `BIEN_occurrence_species()` API | HIGH | ✅ Done |
| 4 | Add citation block (Enquist et al. 2026, DOI 10.1111/2041-210x.70274) to all three scripts | HIGH | ✅ Done |
| 5 | Add `sessionInfo()` at end of all three scripts | HIGH | ✅ Done |
| T-B | Disclose `trait_limit` truncation in trait script with runtime `warning()` if limit reached | HIGH | ✅ Done |
| 6 | Expand trait script plain-language header to match occurrence script | MEDIUM | ✅ Done |
| 7 | Add README.txt to ZIP bundle (citation, file list with row counts, filter settings, notes) | MEDIUM | ✅ Done |
| 8 | Add commented `install.packages()` block to top of all scripts | MEDIUM | ✅ Done |
| T-C | Add comment noting that `observation_category` is a heuristic classification | MEDIUM | ✅ Done |
| 9 | Refactor plot script to be self-contained — no intermediate file, no `read.csv(out_file)` | MEDIUM | ✅ Done |
| 10 | Translate `occ_strategy` codes to plain English in Download banner and script header | LOW–MEDIUM | ✅ Done |
| 11 | Increase code preview box from 180px → 450px | UX | ✅ Done |
| 12 | Show pre-download row counts (occ / plot / trait) above download buttons | UX | ✅ Done |
| 13 | Add data dictionary comment block to occurrence script | LOW | ✅ Done |
| 14 | Add Darwin Core column mapping comment to occurrence script | LOW | ✅ Done |

---

### Lessons Learned

1. **"Reproducible" is a falsifiable claim — test it before publishing it.**  
   A script that calls stochastic functions without a seed, depends on private library internals, and produces CSV files that crash `read.csv()` is not reproducible. Labelling it reproducible misleads users and undermines trust in the data. Before adding a "Download reproducible R code" feature, run the generated script on a clean machine and verify it produces the same output.

2. **Private library functions are not part of the API contract.**  
   `BIEN:::.*` functions are implementation details. Using them in user-facing generated code creates a hidden dependency on an internal contract that can break silently. Always prefer the documented public API, even if it means the generated script has less control over query parameters.

3. **CSV files with comment headers require explicit documentation.**  
   The pattern of prepending `#`-prefixed provenance lines before CSV content is common in scientific computing but breaks default CSV parsers. Every file that uses this pattern must document the `skip=` argument needed to parse it, or use an alternative format (sidecar README, separate metadata JSON, or embedded columns).

4. **Honest uncertainty is a feature, not a limitation.**  
   Stating "this script fetches the same query parameters but may return a different random sample each run" is more useful to a researcher than claiming exact reproducibility that does not exist. Users building analyses on top of these downloads need to know what is stable (species, filters, query logic) and what varies (specific rows selected when BIEN returns more than the app limit).

5. **Trait data limits must be disclosed at the point of download.**  
   Returning a `limit=`-truncated subset of trait records without disclosure is equivalent to analysing a biased sample without reporting the sampling frame. For any data download with a row cap, state the cap, report how many rows BIEN holds versus how many were downloaded, and warn users not to compute aggregate statistics (mean, range, N) without accounting for possible truncation.

6. **Apply the Telford test before shipping any "reproducible" feature.**  
   The Telford framework asks: *can someone run this from a clean R session and get a result that is honest about what it does and does not reproduce?* Apply that test to generated scripts before release, not after.

---

## Issue 14 — "Conservative default profile" silently returned non-native records for Old-World taxa (Markhamia lutea case)

**Status:** RESOLVED 2026-05-10 (commit pending)

### Symptom
A user querying *Markhamia lutea* (Bignoniaceae, native to tropical Africa per POWO/Kew) with the **"Conservative default profile"** checkbox enabled (the default state) received occurrence records from India, Australia, and Mexico — the species' horticultural/cultivated footprint, not its native range. Unchecking the box and re-querying with the default granular controls returned only African records, matching POWO. The two paths used semantically identical SQL filters, so the user-visible difference was *non-deterministic* and the "Conservative" label was actively misleading.

### Diagnosis journey
- Subagents `biodiversity-informatics-checker`, `taxonomy-reconciliation`, and `coder` were run against [BIEN-SpeciesShinyApp/app.R](app.R) lines 440–700, 2670–2700, 4220–4280, 5370–5670, and 6140–6175.
- Two compounding root causes were confirmed (see below). The "non-deterministic" Africa-only vs India-Australia-Mexico difference between checked/unchecked runs was traced to BIEN backend timing — strict returned 0 mappable rows on one run (triggering the silent fallback) and not on the other.

### Root cause(s)

**(a) Silent auto-relaxation of the "conservative" filters.**  
`query_occurrence_with_fallback` ran a 5-step plan ladder (`strict` → `fallback_relaxed_native` → `fallback_relaxed_geo` → `fallback_coord_bearing` → `fallback_allow_centroids`). Plans 2–5 unconditionally set `natives.only = FALSE` and (from plan 3) `only.geovalid = FALSE`, **even when the conservative profile was checked**. When BIEN's strict pass returned 0 mappable rows for an Old-World species (the common case for any taxon outside BIEN's NSR coverage), the chain advanced to `fallback_relaxed_native` and returned introduced/cultivated records labeled as if they were the conservative result. The only warning was a transient `showNotification`; exports carried no strategy provenance.

**(b) `is_introduced IS NULL` was treated as "native" outside BIEN's NSR coverage.**  
`natives_check_with_null_fallback(TRUE)` emitted SQL `AND (is_introduced=0 OR is_introduced IS NULL)`. BIEN's Native Species Resolver is New-World–centric. African records of *M. lutea* (and any Old-World native) are typically `is_introduced IS NULL` because **NSR has no checklist evidence** for those regions, *not* because the species is native there. The same NULL-permissive clause re-admitted horticultural/escaped New-World records. This was the inverse of "conservative" semantics for any taxon outside NSR's coverage footprint.

**(c) The checkbox label and tooltip did not disclose either behavior.**  
The label "Conservative default profile" with tooltip "keeps native and non-introduced records, excludes cultivated records, and keeps only BIEN geovalid coordinates" described only the strict plan. The conservative checkbox provided **no semantic guarantee distinct from the granular defaults** — both paths fed the same auto-fallback ladder.

### Fix (applied 2026-05-10)

1. **Renamed the checkbox** from "Conservative default profile" → **"Strict-only BIEN profile (no auto-relaxation)"** with a rewritten tooltip that explicitly documents the NSR coverage caveat and Markhamia lutea as an example. ([app.R](app.R#L2701))
2. **Flipped the default value to `FALSE`** so the granular filter toggles are visible by default and users see exactly what filters are applied. ([app.R](app.R#L2701))
3. **Restricted the plan ladder to `strict` only when the profile is checked.** Added `if (isTRUE(filter_cfg$use_default_profile)) plans <- plans[1]` so silent fallback is impossible under strict-only. ([app.R](app.R#L588-L596))
4. **Added a persistent yellow banner above the occurrence map** (`output$occ_strategy_banner_ui`) that fires whenever the effective `occ_strategy` is anything other than `"strict"`. The banner names the strategy and the dropped constraints; this is now the source-of-truth for filter provenance, replacing the easily missed transient toast. ([app.R](app.R#L2948), [app.R](app.R#L5086))
5. **Added a `bien_query_strategy` column** to every returned occurrence row in both return paths of `query_occurrence_with_fallback` so exports carry the per-row provenance of which plan produced the record. ([app.R](app.R#L666-L675), [app.R](app.R#L740-L750))
6. **Added an opt-in "Strict native (exclude unevaluated)" checkbox** under `natives_only`. When enabled it threads `strict_native_no_unknown = TRUE` through `query_occurrence_randomized` to `natives_check_with_null_fallback`, which then emits SQL `AND is_introduced = 0` (no NULL fallback). This is the recommended setting for Old-World taxa where NSR has no coverage. ([app.R](app.R#L445-L460), [app.R](app.R#L468), [app.R](app.R#L548), [app.R](app.R#L2710-L2713))

### Lessons learned

1. **A "default" must mean what it says.** A checkbox labelled "Conservative" cannot legally hand off to a relaxed plan ladder without telling the user — and certainly cannot do so silently. If recall-tolerant fallback is desired, give it its own opt-in label and surface the effective strategy alongside every record.

2. **Establishment-status backbones have geographic scope.** BIEN's NSR is dense in the Americas and sparse-to-absent across Africa, Asia, Australia, and most of the Old World. Any biodiversity app that surfaces a "native" filter must either (a) restrict use to the backbone's coverage footprint, or (b) offer a strict variant that excludes unevaluated records. Conflating `IS NULL` with `native` is correct only inside the backbone's coverage.

3. **Per-row provenance is mandatory for filtered/fallback queries.** A single result-level `strategy` field is not enough — once a CSV is exported, the per-row provenance of which plan produced each record is lost. A `bien_query_strategy` column on the data frame makes the trade-off auditable downstream.

4. **Persistent UI banners > transient `showNotification`.** Toast notifications are dismissed (intentionally or not) and never appear in screenshots, exports, or downstream reports. Anything that changes the meaning of the displayed data must persist on the UI surface alongside the data.

5. **Old-World species are the canary for any New-World–trained pipeline.** When stress-testing biodiversity defaults, include taxa whose accepted distribution lies entirely outside the training/coverage domain. *Markhamia lutea*, *Eucalyptus globulus*, and *Encephalartos altensteinii* are useful diagnostic species — if the app silently returns New-World introductions for any of them, the default is wrong.

6. **The `is_cultivated` column has the same NULL-permissiveness trap.** `is_cultivated = 0` does not catch escapes flagged `IS NULL`. A future issue should consider applying the same strict/permissive split to the cultivated filter.

---

## Issue 15 — [Future issues documented here]

*New issues should be appended below using the same format: Symptom → Diagnosis journey → Root cause → Fix → Lessons learned.*
