# BIEN-TraitsShinyApp Implementation Plan

Derived from REVIEW_2026-04-24.md.
Phases are ordered by impact-to-effort ratio. Work within a phase can be parallelized; phases should be sequential.

---

## Phase 1 — Speed: Quick Wins (Low Risk, High ROI)

### P1-A: Move records DT to server-side rendering

**File:** `app_gateway.R` — `recordsServer()`
**Change:** Add `server = TRUE` to the `renderDT` call plus `deferRender = TRUE` and a reduced default `pageLength`.
```r
datatable(dat, server = TRUE, options = list(
  scrollX = TRUE,
  pageLength = 10,
  deferRender = TRUE,
  dom = "frtip"
), rownames = FALSE)
```
**Expected impact:** 5–20× faster initial table load for large queries; major browser memory reduction.

---

### P1-B: Decouple total-count query from critical rendering path

**File:** `app_gateway.R` — `queryServer()` observeEvent for `input$query_btn`
**Change:** Return rows to the UI immediately after `query_bien_traits()` resolves. Then fire the total-count call in a second reactive pass that updates `rv$diagnostics` when it completes. Use a `reactiveVal` to hold preliminary vs. complete diagnostics state.
**Expected impact:** 25–50% faster time-to-first-results on typical BIEN latency.

---

### P1-C: Memoize BIEN_trait_list at process level

**File:** `app_gateway.R` — `load_trait_suggestions()` and `expand_trait_name()`
**Change:** Add a process-level cache variable above the function definitions:
```r
.bien_trait_catalog_cache <- NULL

load_trait_suggestions <- function(timeout_sec = 120) {
  if (!is.null(.bien_trait_catalog_cache)) {
    # use cached result
  }
  ...
  .bien_trait_catalog_cache <<- trait_catalog
}
```
Both `load_trait_suggestions` and `expand_trait_name` can share the same cache object.
**Expected impact:** Eliminates repeat BIEN catalog round-trips across rank/mode switches and trait-only query expansion.

---

### P1-D: Reduce suggestion payload and debounce typing

**File:** `app_gateway.R` — `observeEvent(list(input$suggest_mode, input$rank), ...)`
**Change:**
- Lower species suggestion cap from 15,000 → 8,000.
- Add `minChars = 2` to selectize options for species/genus/family modes.
- Server-side = TRUE for all taxon suggestion lists (already the case for species; enforce for genus/family).
**Expected impact:** Noticeably faster rank-switch responsiveness; reduced startup cost per user session.

---

## Phase 2 — Correctness Fixes (Important Before Heavy Use)

### P2-A: Fix trait-only total-count messaging

**File:** `app_gateway.R` — `query_bien_total_records()`
**Problem:** When a partial trait term expands to multiple exact BIEN trait names, the count query still uses the original token. The displayed total can therefore be wrong.
**Change:** For `rank == "trait-only"`, expand the term first with `expand_trait_name()`, run a count query per expanded name, and sum. Store that as the total.

---

### P2-B: Gate mixed-unit histogram with a hard unit filter

**File:** `app_gateway.R` — `distributionsServer()` histogram and summary stats
**Problem:** Mixed units produce analytically invalid pooled summaries.
**Change:** When `length(sel$unique_units) > 1`, add a `selectInput` for unit filter above the histogram; default to the most common unit; filter values to that unit before computing statistics and rendering the plot. The existing alert about mixed units stays; the filter makes it actionable.

---

### P2-C: Fix timestamp UTC labeling

**File:** `app_gateway.R` — every use of `format(Sys.time(), "... UTC")`
**Change:** Replace all `format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC")` with:
```r
format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%d %H:%M:%S UTC")
```
Affects provenance manifest generation (~4 callsites) and the footer timestamp.

---

### P2-D: Fix provenance citation messaging

**File:** `app_gateway.R` — `downloadGateServer()` acknowledgement text
**Problem:** Text tells users to cite sources using the manifest from "Step 6" but provenance is Step 7 and the manifest contains only query metadata, not source citations.
**Change:**
1. Correct the step reference from "Step 6" to "Step 7".
2. Rephrase: "Use the source_citation and url_source columns in your downloaded CSV to trace each observation back to its original data source."

---

## Phase 3 — Performance: Medium Refactors

### P3-A: Replace dense species-by-trait matrix construction

**File:** `app_gateway.R` — `species_trait_matrix_tbl()` reactive
**Problem:** `table(sp, tr)` materializes full cardinality matrix; expensive for broad queries.
**Change:** Replace with grouped aggregation + pivot:
```r
counts <- data.frame(sp = sp, tr = tr) |>
  dplyr::count(sp, tr) |>
  dplyr::group_by(sp) |>
  dplyr::mutate(sp_total = sum(n)) |>
  dplyr::ungroup()

top_sp <- counts |>
  dplyr::distinct(sp, sp_total) |>
  dplyr::slice_max(sp_total, n = 50) |>
  dplyr::pull(sp)

counts |>
  dplyr::filter(sp %in% top_sp) |>
  tidyr::pivot_wider(names_from = tr, values_from = n, values_fill = 0) |>
  dplyr::rename(species = sp, total_records = sp_total)
```
**Note:** Requires `tidyr` in dependencies. `tidyr` is not currently listed; add to `required_packages`.
**Expected impact:** 60–95% reduction in memory for high-cardinality genus/family queries.

---

### P3-B: Isolate diagnostics recomputation from trait-selection changes

**File:** `app_gateway.R` — `traitSelectServer()` reactive return value
**Problem:** `compute_diagnostics()` is called whenever trait selection changes, including group-by summarization.
**Change:** Cache diagnostics from the query result; recompute only when the underlying `query_result()` data changes, not on `input$selected_traits` or `input$download_all` changes. The diagnostics returned from trait selection should refer to base query data, not the filtered subset.

---

## Phase 4 — Use-Case Coverage

### P4-A: Multi-species batch input

**Scope:** Add a second input mode toggle on Step 1 that switches between "Single taxon" (current) and "Batch species list" (CSV upload or paste).
**Behavior:** In batch mode, accept newline/comma-separated species names or a CSV with one species per row; iterate `BIEN_trait_species()` per species with progress reporting; bind rows; show aggregate diagnostics.
**UX note:** Batch queries can be slow; show per-species progress indicator.

---

### P4-B: Trait map view

**Scope:** New tab "Map" between Distributions and Diagnostics.
**Behavior:** Filter observations to those with non-NA latitude/longitude; render a leaflet map with circle markers; marker color = trait value quantile; click popup shows species, trait, value, unit, and source_citation.
**Requires:** `leaflet` package (already listed in README as required but not loaded in current app).

---

### P4-C: Help and caveats page

**Scope:** New "Help" tab appended after Step 8.
**Content:**
- App workflow summary (one paragraph).
- Key ecological caveats (availability ≠ abundance; sampling bias; taxonomic scope).
- Guidance on interpreting BIEN coverage and truncation.
- How to cite: BIEN package citation + original source_citation instructions.
- Link to biendata.org.

---

### P4-D: Trait-only scope confirmation panel

**Scope:** Before the query fires in trait-only mode, show users the list of exact BIEN trait names that will be queried.
**Behavior:** When rank is "trait-only" and a value is selected, expand the term immediately (on selectize change, not on query button) and display the expanded list in a small info panel beneath the selectize input. Query button remains the execution trigger.

---

### P4-E: Insights panel after query

**Scope:** New "Insights" section in Step 2 Scope.
**Content:**
- Top 3 traits by record count.
- Source concentration: which single source accounts for the most records and its %.
- Unit heterogeneity: number of traits with mixed units.
- Truncation risk: fraction of available records not returned.

---

## Acceptance Criteria

| Phase | Criterion |
|-------|-----------|
| P1    | Time from Query button click to visible data (Step 2, 3) drops by ≥ 25% for a Prunus genus query |
| P1    | Records table (Step 6) renders without browser freeze for a 5,000-row query |
| P2    | Mixed-unit traits show a unit filter before histogram; summary stats match filtered unit |
| P2    | Manifest timestamps are valid UTC |
| P3    | Species-trait matrix renders in < 1s for a 5,000-row Fabaceae query |
| P4    | Multi-species batch accepts a 10-species paste; all results bind and show correct scope |
| P4    | Map renders coordinate-bearing observations for a typical species query |

---

## Dependency Notes

- `tidyr` must be added for Phase 3-A pivot. No other new packages required for Phases 1–2.
- `leaflet` must be loaded from the existing `required_packages` check for Phase 4-B.
- Phases 1 and 2 can be implemented without introducing any new dependencies.
- Phase 4 items are independent of each other and can be shipped incrementally.
