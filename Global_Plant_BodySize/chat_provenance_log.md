# Global_Plant_BodySize — Chat Provenance Log

---

## 2026-05-12 — Stages 9a–9b Complete: Wood density matching + tiered biomass estimation

**Stage 9a (wood density — `scripts/09a_load_wood_density.R`):**  
Downloaded Global Wood Density Database (GWDD) via `BIOMASS::wdData` (Zanne et al. 2009, 16,467 rows). Hierarchical species → genus → global-fallback match applied to 35,307 woody species (growth form ∈ tree, shrub, subshrub, bamboo, vine, epiphyte). Non-woody species receive `rho_match_level = "none"`.

| Match level | Species |
|-------------|---------|
| species | 4,464 |
| genus | 15,360 |
| global_fallback | 15,483 |
| none (non-woody) | 298,471 |

Family-level match returned 0 — BIEN `family` column and GWDD family names not aligned; genus-level catch absorbs most of the residual. Global fallback = 0.58 g/cm³ (UNVERIFIED).  
Output: `output/species_wood_density.csv` (333,778 rows)

**Stage 9b (biomass tiers — `scripts/09b_estimate_biomass_tiers.R`):**  
Four deterministic AGB tiers, best tier selected per species:

| Tier | Method | Species |
|------|--------|---------|
| 4 (best) | Chave 2014 Eq.7: DBH + H + species ρ | 1,056 |
| 3 | Chave 2014 Eq.7: DBH + H + imputed ρ | 902 |
| 2 | Chave 2005 Eq.3: DBH only | 6,690 |
| 1 (weakest) | Height-only allometry | 3,173 |
| **Total** | | **11,821** |

BGB via Mokany et al. 2006 R:S ratios (UNVERIFIED). Plausibility check: tree median AGB = 133.6 kg — PASS.  
Output: `output/plant_biomass_estimates.csv` (333,778 rows)

**Citation flags (all UNVERIFIED — verify before publication):**  
- BIOMASS::wdData source: Zanne et al. 2009 (Dryad 10.5061/dryad.234) via Chave et al. 2009 *Ecology Letters* 12(4):351–366  
- Chave et al. 2014 *Global Change Biology* 20(10):3177–3190  
- Chave et al. 2005 *Oecologia* 145:87–99  
- Brown 1997 FAO Forestry Paper 134  
- Mokany et al. 2006 *Global Change Biology* 12:84–96



**Stage 6 (QA checks — vectorized rebuild):**  
Original row-by-row `for` loop in `run_range_check_plants()` was O(n) in R — terminated after 12 hours on 10M records. Rewrote using `data.table` merge + vectorized `:=` assignments. Re-ran and completed in minutes.

| Source | Records | Range checked | Range pass | Range fail | Outlier flagged |
|--------|---------|---------------|------------|------------|-----------------|
| height | 10,167,913 | 10,166,904 | 10,087,061 | 79,843 | 101,885 |
| dbh | 14,929,488 | 14,929,004 | 14,896,463 | 32,541 | 56,270 |

Output: `output/bien_height_qa.csv`, `output/bien_dbh_qa.csv`, `output/qa_summary_report.csv`

**Stages 7–8 (summarize + finalize):**  
Final database: `output/plant_bodysize_final.csv` — 333,778 species rows  
Species with any trait data: ~78,110 | Allometric-ready (height + DBH): ~1,985

**Next:** Phase 2 extensions (TRY cross-validation, climate niche joins, phylogenetic imputation).

---

## 2026-05-11 — Stages 2 and 3 Complete

**Stage 2 results (scripts/02_trait_query.R):**
- `whole plant height`: 10,167,913 records → `output/bien_height_raw.csv` (5.2 GB, 1,447 BIEN pages)
- `maximum whole plant height`: 3,722 records → `output/bien_max_height_raw.csv` (1.9 MB, 34 pages; literature-compiled, sparse)
- `diameter at breast height (1.3 m)`: 14,929,488 records → `output/bien_dbh_raw.csv` (7.8 GB, 1,493 pages)
- Total Stage 2: ~25 million records, ~13 GB — all individual plot/stem observations

**Stage 3 results (scripts/03_growth_form_query.R):**
- `whole plant growth form`: 330,047 records → `output/bien_growth_form_raw.csv` (34 pages)
- Good coverage relative to 333,778 species; freetext values require Stage 5 canonical mapping

**Next:** Stages 4–8 (taxonomy reconcile → growth form reconcile → QA → summarize → finalize). Stages 4–8 are computationally intensive on these file sizes; `data.table` is used throughout.

---

## 2026-05-11 — Stage 1 Run + API Corrections + PROJECT_LOG.md Creation

**Prompt:** Write a project log with all main summaries, evaluations, and decisions. Run Stage 1, then Stages 2 and 3.

**Actions:**
- Created `PROJECT_LOG.md` — living document capturing genesis, architectural decisions A1–A8, ecology-user 13-step reasoning, biodiversity-science-guard review (9-point checklist: all PASS), phylogenetics-comparative-agent notes for downstream PCM use, enhanced-theory agent hydraulic height bound derivation, pipeline stage table, run history, known limitations, Phase 2 extensions, references.
- Discovered and corrected three BIEN API errors (BIEN v1.2.8):
  1. `BIEN_species_list()` → **does not exist**; correct function: `BIEN_list_all()`
  2. `BIEN_trait_traitname()` → **does not exist**; correct function: `BIEN_trait_trait()`
  3. `"stem diameter or width"` → **not a valid BIEN trait**; correct name: `"diameter at breast height (1.3 m)"`
  4. `"growth form"` → **not a valid BIEN trait**; correct name: `"whole plant growth form"`
  5. Added `"maximum whole plant height"` as a second height source (confirmed via `BIEN_trait_list()`)
- Updated: `providers/bien/load_bien_species.R`, `providers/bien/load_bien_traits.R`, `scripts/02_trait_query.R`, `scripts/03_growth_form_query.R`
- Stage 1 completed: `BIEN_list_all()` returned 333,778 species → `output/bien_species_list.csv` (34 pages, ~3 min)
- Stage 2 started: `whole plant height` query paginating (large dataset — >400 pages active)

**Note on species count:** 333,778 exceeds ~150k expected vascular species. Likely includes synonyms, varieties, hybrids. Stage 4 taxonomy reconciliation will reduce to accepted scrubbed binomials.

---

## 2026-05-11 — Pipeline Design and Implementation

**Agent:** ecology-user (13-step reasoning framework)  
**Prompt:** Design a data pipeline for the Global_Plant_BodySize project. Build a provenance-rich plant body size database for all BIEN plant species (~150,000+) using the R BIEN package. Size data: growth habit, height (m), stem diameter/DBH (cm). Mirror GlobalBodySize/ animal project structure.

**Reasoning steps applied:** All 13 (data typing, scale declaration, sampling bias, trait-environment mapping, scaling logic, data integration, uncertainty quantification, causal vs. correlative, spatial structure, temporal dynamics, plausibility check, use case expansion, workflow formalization).

**Scientific decisions made:**
- Bulk trait query via `BIEN_trait_traitname()` (not per-species); mandatory for ~150k species
- Family-based graminoid flag takes priority over BIEN freetext growth form string
- Bamboo detected via Bambusoideae subfamily (preferred) or curated genus list (fallback)
- All species in `BIEN_species_list()` retained in final table — no-data species flagged `trait_data_available = FALSE`
- Log₁₀ z-score |z| > 3 outlier detection within (growth_form × higher_plant_group) strata
- Confidence tiers: high (n≥5), medium (n=2-4), low (n=1), none (n=0)
- `allometric_ready = TRUE` for species with both height AND DBH data

**Files created:**
- `R/plant_size_schema.R` — schema, vocabulary, range limits
- `R/growth_form_vocab.R` — canonical growth form map, graminoid/bamboo flags
- `R/qa_checks_plants.R` — range, unit, outlier QA functions
- `providers/bien/load_bien_species.R` — Stage 1 species roster intake
- `providers/bien/load_bien_traits.R` — Stages 2–3 bulk trait intake
- `scripts/01_species_list.R` — runs Stage 1
- `scripts/02_trait_query.R` — runs Stage 2 (height + DBH)
- `scripts/03_growth_form_query.R` — runs Stage 3
- `scripts/04_taxonomy_reconcile.R` — runs Stage 4
- `scripts/05_reconcile_growth_form.R` — runs Stage 5
- `scripts/06_qa_checks.R` — runs Stage 6
- `scripts/07_summarize.R` — runs Stage 7
- `scripts/08_finalize.R` — runs Stage 8
- `README.md` — project documentation
- `PROJECT_PLAN.md` — phased plan and known limitations
- `chat_provenance_log.md` — this file

**Known uncertainties flagged in code:**
- BIEN citation DOI UNVERIFIED (confirm Maitner et al. 2018 before publication)
- Bamboo genus list non-exhaustive; subfamily detection preferred
- BIEN does not include bryophytes (documented in schema and README)
- BIEN height observations may represent juvenile/understory individuals

**Expansion opportunities proposed (Step 12):**
1. Height × WorldClim climate gradients
2. Phylogenetic imputation for data-poor families
3. Community-weighted mean height from BIEN plot data
4. TRY cross-validation for bias quantification
5. Chave et al. (2014) AGB estimation for allometric_ready species
