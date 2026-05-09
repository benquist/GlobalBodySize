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

## Issue 2 — [Future issues documented here]

*New issues should be appended below using the same format: Symptom → Diagnosis journey → Root cause → Fix → Lessons learned.*
