# Global_Plant_BodySize — Project Plan

## Project Goal
Build a provenance-rich plant body size database for all BIEN vascular plant species (~150,000 species) using the R BIEN package. Mirrors the `GlobalBodySize/` animal project in architecture and schema conventions.

## Phase 1: BIEN Intake (Current)

### Stage 1 — Species roster
- Script: `scripts/01_species_list.R`
- Function: `run_bien_species_intake()`
- Input: BIEN server via `BIEN_species_list()`
- Output: `output/bien_species_list.csv`
- Completeness criterion: every species in BIEN is in this file

### Stage 2 — Numeric size traits
- Script: `scripts/02_trait_query.R`
- Function: `run_bien_trait_intake()`
- Traits queried:
  - `"whole plant height"` → `output/bien_height_raw.csv`
  - `"stem diameter or width"` → `output/bien_dbh_raw.csv`
- Note: BIEN_trait_list() should be run first to confirm exact trait name strings

### Stage 3 — Growth form
- Script: `scripts/03_growth_form_query.R`
- Trait: `"growth form"` → `output/bien_growth_form_raw.csv`

### Stage 4 — Taxonomy reconciliation
- Script: `scripts/04_taxonomy_reconcile.R`
- Cross-check species names between trait files and species list
- Fill taxonomy gaps (family, higher_plant_group, genus) from species list

### Stage 5 — Growth form reconciliation
- Script: `scripts/05_reconcile_growth_form.R`
- Map BIEN freetext → canonical growth form
- Apply family-based graminoid flag (Poaceae, Cyperaceae, Juncaceae)
- Apply bamboo sub-flag (Bambusoideae / bamboo genus list)
- Output: `output/species_growth_form.csv` (one row per species)

### Stage 6 — QA checks
- Script: `scripts/06_qa_checks.R`
- Range check by growth form (limits in `plant_size_schema.R`)
- Unit check (height → m, DBH → cm)
- Log₁₀ z-score outlier detection within (growth form × higher_plant_group)
- Output: `output/bien_height_qa.csv`, `output/bien_dbh_qa.csv`

### Stage 7 — Species-level aggregation
- Script: `scripts/07_summarize.R`
- Per species: n, mean, median, sd, min, max, CV, confidence tier
- QA filter: range_check_pass = TRUE AND unit_check_pass = TRUE
- Outlier records included by default (EXCLUDE_OUTLIERS flag)
- Output: `output/plant_size_summary.csv`

### Stage 8 — Finalize
- Script: `scripts/08_finalize.R`
- Left-join all BIEN species onto summary → no-data species retained
- `trait_data_available = FALSE` for species with no BIEN trait records
- Enforce column schema from `plantsize_summary_schema_columns()`
- Output: `output/plant_bodysize_final.csv` (FINAL)

## Phase 2: Planned Extensions (Future)

| Extension | Source | Notes |
|-----------|--------|-------|
| TRY cross-validation | TRY database (Kattge et al. 2020) | Requires data access agreement |
| Phylogenetic imputation | Open Tree of Life | For height-poor families |
| Bryophyte intake | GBIF / literature | Separate provider; no size via BIEN |
| Global coverage extension | TRY, GIFT, LEDA | For non-New-World species |
| AGB estimation | Chave et al. (2014) equations | For allometric_ready species |

## Known Limitations

1. BIEN covers New World only; global coverage requires TRY or GIFT integration.
2. BIEN does not consistently return subfamily; bamboo detection relies on genus list.
3. BIEN height observations may represent juvenile or understory individuals; species-level means may underestimate maximum heights.
4. Growth form coverage in BIEN is sparser than height; many species will have growth_form_canonical = "unknown".
5. BIEN citation DOI is UNVERIFIED — confirm before publication.

## Plausibility Range Limits (from plant_size_schema.R)

| Growth form | Min height (m) | Max height (m) | Min DBH (cm) | Max DBH (cm) |
|-------------|---------------|---------------|-------------|-------------|
| tree        | 0.5           | 120           | 0.1         | 2000        |
| shrub       | 0.1           | 15            | NA          | 200         |
| herb        | 0.01          | 5             | NA          | 50          |
| graminoid   | 0.01          | 8             | NA          | 30          |
| bamboo      | 0.3           | 40            | 0.1         | 40          |
| vine        | 0.1           | 60            | NA          | 20          |
| aquatic     | 0.001         | 5             | NA          | 30          |

## QA Confidence Tiers

| Tier   | n records |
|--------|-----------|
| high   | ≥ 5       |
| medium | 2–4       |
| low    | 1         |
| none   | 0         |

## Provenance

- Pipeline designed: 2026-05-11 (ecology-user agent, 13-step reasoning framework)
- BIEN package version: confirm with `packageVersion("BIEN")` at run time
- All BIEN queries cache to CSV; re-run with `--overwrite` to refresh
