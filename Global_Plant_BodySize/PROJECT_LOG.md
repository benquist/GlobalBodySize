# Global_Plant_BodySize — Project Log

**Living document.** Records all major decisions, evaluations, run history, and scientific rationale for the Global_Plant_BodySize pipeline. Append entries as the project evolves; never overwrite existing entries.

---

## PROJECT GENESIS

**Date:** 2026-05-11  
**Origin prompt:** Design a new project `Global_Plant_BodySize` using R BIEN to compile plant body size data for all BIEN plant species. Size traits: growth form (tree, shrub, herb, liana, epiphyte, etc.), height, DBH. Special handling for graminoids (family-based), bamboo (Bambusoideae subfamily / genus list), and bryophytes (not in BIEN; placeholder flagged).  
**Agents invoked:** ecology-user (workflow design, 13 reasoning steps), biodiversity-science-guard (data standards review), coder (implementation), optimizer (pipeline efficiency).

**Motivation:** Plant body size — particularly height and stem diameter — is a primary axis of the plant economics spectrum (Wright et al. 2004; Díaz et al. 2016). Across six orders of magnitude (Wolffia, 1 mm → Sequoia sempervirens, 116 m), height integrates competitive ability, life history strategy, above-ground biomass, and hydraulic architecture. No single provenance-rich plant body size database exists for the full New World flora covered by BIEN (~150,000 vascular plant species). This project builds that database, mirroring the architecture of the companion `GlobalBodySize/` animal project.

---

## ARCHITECTURAL DECISIONS

### A1 — Bulk query over per-species query
**Decision:** Use `BIEN_trait_traitname()` for all traits rather than iterating `BIEN_trait_species()` per species.  
**Rationale:** With ~150,000 species, per-species queries would require ~150,000 API calls (days of run time, high risk of rate-limit failures). `BIEN_trait_traitname()` fetches all records for a trait in one call. Expected single-call cost: 5–30 minutes per trait.  
**Tradeoff acknowledged:** Single-call approach pulls all records into memory at once — may require partitioning if memory pressure is encountered (added note in `load_bien_traits.R`).

### A2 — Family-based graminoid flag as authority
**Decision:** The `is_graminoid` flag is set by family membership (Poaceae, Cyperaceae, Juncaceae), not by BIEN's freetext growth form string.  
**Rationale:** BIEN growth form values are inconsistently recorded; freetext "grass" may be missing for many Poaceae. Family membership is taxonomically authoritative and stable.  
**Implementation:** `flag_graminoid()` in `R/growth_form_vocab.R`.

### A3 — Bamboo: subfamily preferred, genus list fallback
**Decision:** Bamboo is identified first by subfamily == "Bambusoideae" (when BIEN returns it), then by genus membership in a curated list.  
**Rationale:** BIEN rarely returns subfamily; the genus list is non-exhaustive but covers the major bamboo genera (~1,400 bamboo species globally, ~500+ in the New World).  
**Caveats:** Bamboo genus list is based on Kelchner & Bamboo Phylogeny Group (2013) — DOI UNVERIFIED. A bamboo species not in the genus list will be classified as `graminoid`, not `bamboo`. This is conservative and ecologically defensible: bamboos *are* graminoids.  
**Implementation:** `flag_bamboo()` in `R/growth_form_vocab.R`.

### A4 — All species retained; no-data species flagged
**Decision:** Every species returned by `BIEN_species_list()` is present in the final output (`output/plant_bodysize_final.csv`), even species with zero BIEN trait records.  
**Rationale:** Absence of data is scientifically meaningful. Downstream analyses (e.g., trait imputation, phylogenetic comparative methods) need to distinguish "no size data" from "species not queried."  
**Flag:** `trait_data_available = FALSE` for no-data species. `allometric_ready = TRUE` only for species with both height AND DBH records.

### A5 — Species-level aggregation: QA-passing records only
**Decision:** Species-level summaries (`height_m_mean`, `dbh_cm_mean`, etc.) are computed from records where `range_check_pass = TRUE` AND `unit_check_pass = TRUE`.  
**Rationale:** Including out-of-range values or unit-ambiguous records in means would propagate errors silently.  
**Outlier policy:** Outlier-flagged records (`outlier_flag = TRUE`) are **included** by default in means but tracked separately. Users can re-summarize excluding outliers using the `EXCLUDE_OUTLIERS` flag in `scripts/07_summarize.R`.

### A6 — Confidence tiers
**Decision:** Assign confidence tier based on number of QA-passing records per species per trait:  
- `high`: n ≥ 5  
- `medium`: n = 2–4  
- `low`: n = 1  
- `none`: n = 0  
**Rationale:** Single-observation species-level means are unreliable, especially if that observation represents a juvenile. Tiers allow downstream analysts to filter by reliability.

### A7 — Growth form conflict detection
**Decision:** Flag species where multiple distinct canonical growth forms are recorded in BIEN (`growth_form_conflict = TRUE`).  
**Rationale:** A species recorded as both "tree" and "herb" indicates either misidentification, taxonomic lumping, or data entry error. Conflicts should be reviewed before ecological assignment. Plurality rule (most frequent canonical form) is used to assign `growth_form_canonical` when conflicts exist.

### A8 — BIEN does not contain bryophytes
**Decision:** `is_bryophyte = FALSE` for all BIEN species. The flag is retained as a schema placeholder for future integration of a bryophyte-specific data source (GBIF, literature).  
**Implications:** The project is explicitly scoped to BIEN vascular plants. Mosses, liverworts, and hornworts require a separate provider.

---

## ECOLOGICAL RATIONALE (from ecology-user agent, 13-step reasoning)

**Data type:** Trait data — continuous (height, DBH) and categorical (growth form). Observation-level records mapped to species-level summaries.  
**Biological scale:** Species level; spatial grain = plot-based observations (variable); spatial extent = New World (BIEN coverage).  
**Sampling bias acknowledged:** BIEN has strong sampling bias toward accessible sites, roadsides, and well-botanized regions (US, Costa Rica, Brazil). Under-representation of remote Amazon, Andes, and Caribbean flora is expected. This bias affects which species have size records, not which species are on the roster.  
**Uncertainty quantification:** Confidence tiers, n per species, CV, min/max all exported. Outlier flags preserved.  
**Causal vs. correlative:** This is a data compilation project; no causal claims are made. Height is a trait measurement, not a causal predictor, in this pipeline.  
**Ecological plausibility bounds:**

| Growth form | Min height (m) | Max height (m) | Min DBH (cm) | Max DBH (cm) |
|-------------|---------------|---------------|-------------|-------------|
| tree        | 0.5           | 120           | 0.1         | 2000        |
| shrub       | 0.1           | 15            | —           | 200         |
| herb        | 0.01          | 5             | —           | 50          |
| graminoid   | 0.01          | 8             | —           | 30          |
| bamboo      | 0.3           | 40            | 0.1         | 40          |
| vine        | 0.1           | 60            | —           | 20          |
| aquatic     | 0.001         | 5             | —           | 30          |

**Note on tree height maximum:** The physiological maximum tree height is ~130 m (hydraulic path-length limit; Koch et al. 2004). The range limit of 120 m is conservative; *Sequoia sempervirens* reaches ~116 m. Any BIEN value >120 m is flagged as out-of-range.

---

## BIODIVERSITY SCIENCE GUARD REVIEW (2026-05-11)

Reviewed by `biodiversity-science-guard` agent against 9-point checklist.

| Check | Status | Notes |
|-------|--------|-------|
| Biological unit stated | PASS | Species-level plant body size |
| Taxonomic backbone named | PASS | BIEN internal scrubbed taxonomy; cross-checked via `BIEN_species_list()` |
| Taxonomic reconciliation explicit | PASS | Stage 4 reconciles trait files against species roster |
| Occurrence QA documented | PASS | Coordinate fields retained but not primary QA focus (trait pipeline, not occurrence) |
| Native/introduced/cultivated | N/A | Growth form not an introduction-status field |
| Trait units harmonized | PASS | Height → m, DBH → cm; ambiguous units → NA + flagged |
| Range products described with caveats | PASS | BIEN New World scope caveat in README and schema |
| Sampling bias acknowledged | PASS | BIEN bias documented in PROJECT_PLAN.md and chat_provenance_log.md |
| Reproducibility visible | PASS | All BIEN queries cache to CSV; re-run via `--overwrite` |

**Critical finding:** BIEN citation DOI is UNVERIFIED. Do not publish or share this database without confirming the Maitner et al. (2018) citation via CrossRef. Flagged in all source files.

---

## PHYLOGENETICS NOTE (from phylogenetics-comparative-agent)

Growth form and height data from this project are suitable as trait vectors for phylogenetic comparative methods (PGLS, phylogenetic signal, ancestral state reconstruction) when joined to a BIEN-derived or Open Tree of Life backbone. Notes for downstream PCM use:
- Height is a continuous trait; use log₁₀ transformation before phylogenetic analysis.
- Growth form is categorical; treat as ordered (herb < shrub < tree) with caution — the ordering is ecologically motivated but not universal.
- Species with `confidence_tier = "none"` should be excluded from PCM analyses or imputed via Rphylopars or BAMP.
- Bamboo height data should be analyzed separately; bamboo maximum heights (up to ~40 m) exceed herb/shrub ranges but are morphologically and physiologically distinct from dicot trees.

---

## SCALING THEORY NOTE (from enhanced-theory agent)

Plant height scales with above-ground biomass following $M_{AGB} \propto H^{2.67}$ (approximately; Chave et al. 2014, though with stem diameter the Chave equation uses $H \cdot D^2 \cdot \rho$). The `allometric_ready = TRUE` flag marks species for which both $H$ and $D$ are available, enabling AGB estimation as a Phase 2 extension. The theoretical maximum height from hydraulic path-length constraints gives:

$$H_{max} \approx \frac{\Psi_{leaf} - \Psi_{stem}}{\rho_w g} \approx 130 \text{ m}$$

where the numerator is the water potential difference (~1.3 MPa) and the denominator is the hydrostatic pressure gradient. This mechanistic bound informs the range check upper limit of 120 m used in QA.

---

## PIPELINE STAGES

| Stage | Script | Function | Output | Status |
|-------|--------|----------|--------|--------|
| 1 | `scripts/01_species_list.R` | `BIEN_list_all()` | `output/bien_species_list.csv` | **COMPLETE** — 333,778 species |
| 2a | `scripts/02_trait_query.R` | `BIEN_trait_trait("whole plant height")` | `output/bien_height_raw.csv` | **IN PROGRESS** |
| 2b | `scripts/02_trait_query.R` | `BIEN_trait_trait("maximum whole plant height")` | `output/bien_max_height_raw.csv` | pending 2a |
| 2c | `scripts/02_trait_query.R` | `BIEN_trait_trait("diameter at breast height (1.3 m)")` | `output/bien_dbh_raw.csv` | pending 2b |
| 3 | `scripts/03_growth_form_query.R` | `BIEN_trait_trait("whole plant growth form")` | `output/bien_growth_form_raw.csv` | NOT RUN |
| 4 | `scripts/04_taxonomy_reconcile.R` | `run_taxonomy_reconcile()` | `output/bien_taxonomy_reconciled.csv` | NOT RUN |
| 5 | `scripts/05_reconcile_growth_form.R` | `run_growth_form_reconcile()` | `output/species_growth_form.csv` | NOT RUN |
| 6 | `scripts/06_qa_checks.R` | `run_qa_checks()` | `output/bien_height_qa.csv`, `output/bien_dbh_qa.csv` | NOT RUN |
| 7 | `scripts/07_summarize.R` | `run_summarize()` | `output/plant_size_summary.csv` | NOT RUN |
| 8 | `scripts/08_finalize.R` | `run_finalize()` | `output/plant_bodysize_final.csv` | NOT RUN |

---

## RUN HISTORY

---

### Stage 1 — 2026-05-11

**Script:** `scripts/01_species_list.R`  
**Function:** `BIEN_list_all()` (corrected from `BIEN_species_list()` — not exported in BIEN v1.2.8)  
**BIEN version:** 1.2.8  
**Result:** 333,778 species written to `output/bien_species_list.csv`  
**Pages fetched:** 34  
**Duration:** ~3 minutes  
**Log:** `output/stage1_run_log.txt`

**Corrections made during run:**
- `BIEN_species_list()` does not exist in BIEN v1.2.8. The correct function is `BIEN_list_all()`. Updated `providers/bien/load_bien_species.R`.
- Also confirmed: `BIEN_trait_traitname()` does not exist; correct function is `BIEN_trait_trait()`. Updated `providers/bien/load_bien_traits.R`.
- Confirmed: correct BIEN trait name for DBH is `"diameter at breast height (1.3 m)"` (not `"stem diameter or width"`).
- Confirmed: correct growth form trait is `"whole plant growth form"` (not `"growth form"`).
- Added `"maximum whole plant height"` as an additional height source (also exists in BIEN).
- Updated `scripts/02_trait_query.R` and `scripts/03_growth_form_query.R` with corrected trait name strings.

**Note on species count:** 333,778 species exceeds the expected ~150,000 vascular plants. BIEN_list_all() likely includes all distinct name strings in the BIEN database, including synonyms, varieties, hybrids, and non-vascular occurrences. Stage 4 (taxonomy reconciliation) will filter to accepted species names and scrubbed binomials.

---

### Stage 2 — 2026-05-11 (IN PROGRESS)

**Script:** `scripts/02_trait_query.R`  
**Queries running:** `whole plant height` → `output/bien_height_raw.csv` (paginating — large dataset)  
**Then:** `maximum whole plant height` → `output/bien_max_height_raw.csv`  
**Then:** `diameter at breast height (1.3 m)` → `output/bien_dbh_raw.csv`  
**Status:** Stage 2a actively paginating (>400 pages as of start); Stages 2b and 2c pending completion of 2a.

---

## KNOWN LIMITATIONS AND OPEN ISSUES

1. **BIEN New World scope**: No Old World coverage. Global extension requires TRY (Kattge et al. 2020), GIFT, or LEDA databases (Phase 2).
2. **BIEN citation DOI UNVERIFIED**: Confirm Maitner et al. (2018) DOI: 10.1111/mee3.12373 via CrossRef before publication.
3. **Bamboo genus list non-exhaustive**: ~1,400 bamboo species globally; the curated genus list covers major genera but is not complete. Subfamily detection preferred but often missing from BIEN.
4. **Height may represent juveniles**: BIEN plot-based height observations are collected in the field and may reflect non-maximal heights (understory, juvenile growth stages). Species-mean heights may underestimate maximum heights, especially for long-lived trees.
5. **Growth form coverage sparse in BIEN**: Many species will have `growth_form_canonical = "unknown"` because BIEN has limited growth form records relative to height/DBH. Family-based graminoid flag partially compensates.
6. **Bryophytes absent**: BIEN does not include bryophytes. The `is_bryophyte` flag is a schema placeholder only.
7. **No intraspecific variation**: Species-level means collapse individual variation. Downstream allometric analyses should note that within-species size variation can span an order of magnitude.
8. **No wood density**: AGB estimation via Chave et al. (2014) requires wood density (ρ), which is not available from BIEN traits. A wood density provider (Global Wood Density Database; Zanne et al. 2009) would be needed for Phase 2 AGB calculations.

---

## PLANNED PHASE 2 EXTENSIONS

| Extension | Source | Status |
|-----------|--------|--------|
| TRY cross-validation | TRY database (Kattge et al. 2020) | Requires data access agreement |
| Phylogenetic imputation for height-poor families | Open Tree of Life + Rphylopars | Phase 2 |
| Bryophyte intake | GBIF / literature | Separate provider |
| Global coverage extension | TRY, GIFT, LEDA | Phase 2 |
| AGB estimation | Chave et al. (2014) allometric equations | Requires wood density; Phase 2 |
| Community-weighted mean height | BIEN plot data | Requires BIEN plot access |
| Height × climate gradient analysis | WorldClim v2 | Phase 2 analytical layer |

---

## REFERENCES (project-specific; all DOIs should be verified before publication)

- Chave J, et al. (2014). Improved allometric models to estimate the aboveground biomass of tropical trees. *Global Change Biology* 20:3177–3190.
- Díaz S, et al. (2016). The global spectrum of plant form and function. *Nature* 529:167–171.
- Kattge J, et al. (2020). TRY plant trait database — enhanced coverage and open access. *Global Change Biology* 26:119–188.
- Koch GW, Sillett SC, Jennings GM, Davis SD (2004). The limits to tree height. *Nature* 428:851–854.
- Maitner BS, et al. (2018). The BIEN package: A tool to access the Botanical Information and Ecology Network (BIEN) database. *Methods in Ecology and Evolution* 9(2):373–379. DOI: 10.1111/mee3.12373 — **UNVERIFIED**
- Moles AT, et al. (2009). Global patterns in plant height. *Journal of Ecology* 97:923–932.
- Wright IJ, et al. (2004). The worldwide leaf economics spectrum. *Nature* 428:821–827.
- Zanne AE, et al. (2009). Global wood density database. *Dryad*. DOI: 10.5061/dryad.234 — **UNVERIFIED**
