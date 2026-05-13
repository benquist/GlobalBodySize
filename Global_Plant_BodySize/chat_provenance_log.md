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

## 2026-05-13 — Stages A–E: habit expansion + unified body mass pipeline

**Prompt:** "Yes, stage A first, give a report and then also B-E in order"

**Stages implemented:**

### Stage A: Habit Integration (03b_habit_integration.R)
- Pulled BIEN `whole plant woodiness` (49,060 records, 45,815 species) and `whole plant growth form diversity` (67,413 records, 66,473 species)
- Added `"whole plant growth form diversity"` → `"gf_diversity"` to `providers/bien/load_bien_traits.R` measurement type map
- 3-source priority merge (primary GF > GF diversity > woodiness):
  - 77,603 species from primary GF (Stage 5)
  - 4,406 "unknown" upgraded via GF diversity
  - 8,525 added/upgraded via woodiness (8,359 new + 166 upgrades)
- **Result: 83,580 → 91,939 species with known growth form (98.5%)**
- Outputs: `output/species_growth_form_expanded.csv`, `output/habit_integration_report.csv`
- Caution: woodiness "woody" mapped to tree/shrub by family heuristic; families not in lookup remain "unknown"

### Stage B: Tier Bias Check (09c_tier_bias_check.R)
- Bland-Altman analysis on 1,958 allometric-ready species (H + DBH + rho)
- **T1 (height-only) vs Chave 2014: mean bias = −0.877 log₁₀ kg, LoA = [−3.94, +2.19]** — massive underestimate
- **T2 (DBH-only) vs Chave 2014: mean bias = +0.380 log₁₀ kg, LoA = [−0.40, +1.16]** — systematic overestimate
- Growth-form-specific: tree T1 bias = −0.911; shrub T1 = −0.493; vine T2 = +0.270
- Outputs: `output/tier_bias_summary.csv`, `output/tier_bias_corrections.csv`
- NOTE: Correction factors computed for significant biases (n ≥ 10). Review before applying. Calibration sample is biased toward tropical trees.

### Stages C + D: Uncertainty + GF Imputation (09d_add_biomass_uncertainty.R)
- `agb_log10_sd` column added per species:
  - T4: 0.104 log₁₀ kg (Chave 2014 RSE, UNVERIFIED)
  - T3: 0.200 log₁₀ kg (wider for imputed rho)
  - T2: 0.397 log₁₀ kg (from Bland-Altman LoA)
  - T1 trees: 1.526; T1 shrubs: 2.008 log₁₀ kg (from LoA — very wide)
  - T1 herbs/gram: 0.626 log₁₀ kg (within-GF empirical SD; flagged `herb_proxy_uncertain`)
- Tier 0 GF imputation: 60,552 existing + 6,358 new = **66,910 GF-imputed species**
  - Imputed from within-GF mean ± SD of calibration species (Tiers 1–4)
  - Root:shoot ratios from Mokany 2006 (UNVERIFIED)
- 95% CI columns added: `agb_ci_lower_kg`, `agb_ci_upper_kg` (asymmetric on natural scale)
- **Output: `output/plant_biomass_with_uncertainty.csv` (340,136 rows, 32 cols)**

### Stage E: Unified Visualization (plant_bodysize_summary.Rmd Section 11)
- New Section 11: "Unified Body Mass Axis: All Species"
- Horizontal violin plot per growth form (tree → parasite)
- Strip jitter points encoded by **shape** (T4: filled circle, T3: filled circle, T2: triangle, T1: square, T0: open diamond) **and alpha** (T4: 1.0 → T0: 0.4)
- 95% CI error bars on subsampled points (n ≤ 60 per GF)
- 1 kg reference line (log₁₀ = 0)
- Summary table: median log₁₀(total biomass) by GF × tier
- Bland-Altman bias table displayed for user reference
- All equations FLAGGED UNVERIFIED in figure caption
- Rmd rendered clean to HTML

**Key science caveats embedded in the visualization:**
1. T0 values are group means — within-GF variance spans 4–6 orders of magnitude
2. T1 underestimates by ~7.5× vs. Chave 2014 reference
3. T2 overestimates by ~2.4× vs. Chave 2014 reference
4. Herb proxy equation (AGB = 0.04 × H^1.5) not literature-derived — flagged
5. 261,405 species with no data remain explicit NA (not imputed phylogenetically)

---

## 2026-05-13 — Stage 10a bug fixes + coverage diagnosis + forward planning

### Bug fixes applied to Stage 10a (`10a_build_phylo_tree.R`)

**Bug 1 — Wrong V.PhyloMaker2 object names (CRITICAL, fixed):**
- V.PhyloMaker2 v0.1.0 does NOT export `GBMB` or `nodes.info.1` — these were incorrect object names from an earlier version.
- Fixed throughout: `GBMB` → `GBOTB.extended.WP` (72,570 tips, time-calibrated); `nodes.info.1` → `nodes.info.1.WP`.
- Backbone genera/families audit updated to use `tips.info.WP` (columns: group, species, genus, family) and `nodes.info.1.WP`.

**Bug 2 — `family` column all NA throughout pipeline (CRITICAL, fixed):**
- BIEN trait queries populate `genus` but not `family`. All output CSVs have `family` as logical NA.
- Fix: build `genus_to_family` lookup from `tips.info.WP` (10,583 genera → families) and join by genus before calling `phylo.maker()`.
- 286,882 / 340,136 species matched to families this way; 53,254 unmatched (non-vascular plants, algae, unrecognised genera).
- Fix applied to `10a_build_phylo_tree.R`. Same fix (loading `output/genus_family_lookup.csv`) propagated to `10b_pglmm_fit.R`, `10c_pglmm_predict.R`, `10d_pglmm_validate.R`.
- `output/genus_family_lookup.csv` written (10,583 rows) from `tips.info.WP`.

**Performance finding — full tree not feasible in one session:**
- `phylo.maker()` in Scenario 3 processes ~100 species / 24 sec → 287K species ≈ 19 hours.
- Redesigned 10a: `BUILD_FULL_TREE = FALSE` (default). Critical path builds only `tree_measured.nwk` (11,176 measured Tier 1–4 species, ~45 min). Full tree is an optional future overnight run.
- `tree_measured.nwk` successfully written (11,176 tips, 399 KB). `tree_placement_audit.csv` written (28.5 MB).

### Coverage diagnosis (as of this session)

| Category | N species | % of 340,136 |
|---|---|---|
| Tier 4 — Chave 2014 reference | 1,056 | 0.3% |
| Tier 3 — height + DBH allometry | 902 | 0.3% |
| Tier 2 — DBH only | 6,690 | 2.0% |
| Tier 1 — height only | 3,172 | 0.9% |
| **All measured T1–T4** | **11,820** | **3.5%** |
| GF-imputed (within-GF mean) | 66,907 | 19.7% |
| No estimate | 261,409 | 76.9% |

Of the 11,820 measured species: 8,256 flagged `ok`; 2,308 `herb_proxy_UNVALIDATED`; 1,135 `liana_PENDING`; 121 `graminoid_height_LOW`.

**Critical finding on the 261K no-estimate species:**
- 261,405 of 261,409 have `growth_form_canonical = "unknown"` — GF-constrained imputation cannot be applied directly.
- `higher_plant_group` is also NA for all 261K.
- However: 217,308 of these species share a genus with ≥1 measured/GF-imputed species → genus-mean proxy is available.
- Only 44,101 species have neither genus-level nor GF-level data.

### Forward plan (agreed between `phylogenetics-comparative-agent` and `biodiversity-science-guard` review framing)

**Immediate (unblocked — Stage 10b):**
- `tree_measured.nwk` is ready. Run `10b_pglmm_fit.R` (MCMCglmm, ~30–120 min). This requires family to be filled (now handled via `genus_family_lookup.csv`).

**Near-term: GF inference for the 261K (proposed Stage 09f)**
- For species with unknown GF but a known genus, infer a probable GF from the GF distribution of congeneric measured species.
- Approach: if ≥ 80% of measured congeners share one GF → assign that GF with flag `gf_inferred_from_genus`; if no consensus → leave unknown.
- This could unlock GF-constrained Tier 0 imputation for a substantial fraction of the 261K.
- Biodiversity-science-guard concern: inferred GF must be flagged explicitly; must not overwrite known GF; must carry a confidence score; cited norm for genus-level GF transfer needed before publication.
- Phylogenetics concern: GF inference from congeners assumes GF is phylogenetically conserved at genus level — reasonable for trees/shrubs (high conservatism), more suspect for herbs (polyphyletic across genera). Flag accordingly per GF.

**After PGLMM runs (Stages 10c → 10d):**
- 10c: BLUP prediction propagates family- and genus-level random effects to all 333K species regardless of GF knowledge. This is the primary imputation route for the 261K.
- 10d: Family-holdout CV quantifies prediction accuracy, especially for the GF-unknown species.

**Open science / provenance requirements flagged:**
- `genus_family_lookup.csv` source must be cited as V.PhyloMaker2 / tips.info.WP (Jin & Qian 2022 — UNVERIFIED exact ref; run `citation("V.PhyloMaker2")` before submission).
- GF inference step must carry an `imputation_basis` flag distinguishing: `measured`, `gf_imputed_direct`, `gf_inferred_genus`, `pglmm_blup`, `grand_mean_only`.
- All 261K no-estimate species must remain explicit in output with their imputation basis documented — do not silently drop or silently impute.


---
## 2026-05-13: Stage 10b pr=TRUE fix + Stage 10d three-mode CV redesign

**Session summary:**
Three specialist agents (phylogenetics-comparative-agent, merow-ecology, stats-specialist) reviewed the existing single-mode family-holdout CV design and recommended a three-mode system. Their findings were synthesized and implemented.

**Stage 10b fix:**
- Added `pr = TRUE` to the MCMCglmm call in `10b_pglmm_fit.R`
- Without this, `$Sol` contains only fixed effects, not per-level random effect posteriors
- Family and genus BLUP CSVs would have been empty without this fix
- Required for `genus_interp` CV mode and for Stage 10c BLUP prediction

**Stage 10d redesign — three CV modes:**

1. `CV_MODE=family` (default): Family-holdout, full MCMCglmm refit per fold, predict from fixed FE only (no family BLUP). Estimand: 44K species with no genus-level training data. Worst-case scenario.

2. `CV_MODE=genus_extrap`: Strict genus-holdout, approximate shortcut (no refit). Load Stage 1 family BLUPs + FE + VC; zero genus BLUP; predict from FE + family BLUP. Estimand: 44K species with no congeners in training. Labeled as approximate — VC from full-data fit.

3. `CV_MODE=genus_interp`: Within-genus holdout (~50% per eligible genus), full MCMCglmm refit with `pr=TRUE`, predict from FE + genus BLUP (from retained congeners) + family BLUP. Estimand: 217K species with congeners in training. This is the production prediction scenario.

**Key design decisions from specialist review:**
- `data_tier="T1"` for all held-out species — simulates production (261K target species have no allometric measurement)
- RMSE stratified separately for S1/2 (resolved placement) vs. S3 (polytomy) — S3 is labeled as lower bound
- Gelman-Rubin R-hat (via coda::gelman.diag) for N_CHAINS >= 3 (non-QUICK_CV runs)
- Empirical PI calibration table at 10 nominal levels written per mode
- Stratified fold assignment by genus size class and dominant growth form
- Blomberg K computed once on Stage 1 residuals, stratified by placement scenario

**Output files (5 per mode):**
- `output/pglmm_cv_{mode}_fold_results.csv`
- `output/pglmm_cv_{mode}_gf_summary.csv`
- `output/pglmm_cv_{mode}_sizeclass_summary.csv`
- `output/pglmm_cv_{mode}_scenario_summary.csv`
- `output/pglmm_cv_{mode}_calibration.csv`
- `output/pglmm_residual_blomberg_k.csv` (shared, computed once)

**Commit:** baee496
**Status:** Scripts updated; Stage 10b and 10d not yet run — requires full MCMCglmm fit (~30-120 min for 10b).

---

## 2026-05-13 — Stage 09e expanded: Option B non-seed plant flagging (sections 6–10)

**Prompt:** "Do option B now" — add genus-based `agb_method_flag` entries for five non-seed-plant groups in `scripts/09e_fix_allometry_methods.R`.

**Background:**
Dataset has `family = NA` for all rows; identification must use the `genus` column. Tree ferns (*Cyathea*, *Alsophila*, *Sphaeropteris*, *Dicksonia*, etc.) are incorrectly coded as `growth_form_canonical = "herb"` and receive the `0.04 * H^1.5` herb proxy — mechanistically indefensible. Bryophytes are in Tier 0 GF-imputed with `growth_form_canonical = "unknown"`; the correct metric for mosses/liverworts is shoot biomass per area (g m⁻²), not per-individual AGB. BIEN DOES include bryophytes (user-confirmed); they appear in the output with ~1400+ species.

**Changes made to `scripts/09e_fix_allometry_methods.R`:**
- Header updated: "five growth forms" → "ten growth forms (five vascular + five non-seed-plant groups)"
- Five new flag values added to header documentation table
- Sections 6–10 inserted before `## ---- Summary audit ---`:

| Section | Group | Genus list size | Flag | Action |
|---|---|---|---|---|
| 6 | Tree ferns | 9 genera | `tree_fern_stipe_PENDING` | `agb_log10_sd` × 2; CI recomputed |
| 7 | Ground ferns | 38 genera | `ground_fern_frond_PENDING` | Flag only |
| 8 | Lycophytes | 8 genera | `lycophyte_herb_proxy_LOW` | Flag only |
| 9 | Horsetails | 1 genus (*Equisetum*) | `horsetail_herb_proxy_LOW` | Flag only |
| 10 | Bryophytes | 34 genera | `bryophyte_area_basis` | Flag + `biomass_note` noting g m⁻² is correct unit |

**Verified flag counts (run against 340,136-row output):**
- Tree ferns: 785 species
- Ground ferns: 5,420 species
- Lycophytes: 1,244 species
- Horsetails: 35 species
- Bryophytes: 2,865 species

**Known issues (deferred):**
- `is_bryophyte <- FALSE` hardcoded in `scripts/05_reconcile_growth_form.R` is incorrect — separate fix needed
- `higher_plant_group` column is all NA in output — upstream stage issue, deferred
- Tree ferns received herb proxy due to incorrect `growth_form_canonical = "herb"` assignment; stipe-diameter allometry is the correct approach but not yet implemented

**Commit:** 9ee4953
**Status:** Script run and verified; output CSV updated.
