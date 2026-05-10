# GlobalBodySize — Chat Provenance Log

## 2026-05-09 — Project initiation

**User prompt:** Start new project GlobalBodySize — crawl world data repositories (Dryad, Figshare, Scientific Data, public data repositories) for mammals, birds, insects, fish, reptiles body size information. Use team of agents (@biodiversity-informatics-checker, @ecology-user, @merow-ecology, @phylogenetics-comparative-agent, @taxonomy-reconciliation) to compile data sources and search strategy. Inspiration from DryadPlantTraits project. Also consider GBIF R package for body size in occurrence metadata. GitHub repo: GlobalBodySize.

**Actions:**
- Explored DryadPlantTraits/ pipeline for architecture inspiration (search_terms.R, dryad_api.R, candidate_filter.R, compile_downloaded_traits.R patterns)
- ecology-user agent: produced DATA_SOURCE_INVENTORY.md — 23 Tier 1 curated databases, 9 programmatic repositories, 83-term search vocabulary, GBIF MoF assessment, specialist sources, integration challenges, priority ranking
- merow-ecology agent: produced ECOLOGICAL_QUALITY_ADVISORY.md — Tier A/B/C quality ratings, critical schema requirements (mass_type non-nullable, LW-modeled flag for fish), priority harvest order, overlooked sources (NEON, ICES, Dunning handbook, Reptile-Trait Meiri group)
- taxonomy-reconciliation agent: produced TAXONOMY_RECONCILIATION_STRATEGY.md — backbone choices per group (MDD mammals, BirdLife birds, FishBase fish, AmphibiaWeb amphibians, Reptile Database, GBIF/CoL insects, WCVP/POWO plants), GBIF usageKey as cross-group harmonization key, 28-field schema, 9-step workflow, quality gates
- biodiversity-informatics-checker agent: produced BIODIVERSITY_INFORMATICS_AUDIT.md — 8 critical issues identified (MDD backbone missing, GBIF usageKey instability, DwC missing fields, NEON omission), DwC compliance gaps, GBIF MoF Tier C confirmed, 20 mandatory row-level provenance fields
- Built project scaffold: R/, scripts/, providers/, data/, output/, reports/ directories
- Implemented: R/search_terms.R, R/body_mass_schema.R, R/dryad_api.R, R/candidate_filter.R, R/taxon_reconciliation.R, R/qa_checks.R
- Implemented: scripts/discover_body_mass_datasets.R (Stage 1 discovery), scripts/run_tier1_intake.R (Stage 2 intake)
- Implemented: providers/pantheria/load_pantheria.R, providers/avonet/load_avonet.R, providers/fishbase/load_fishbase.R
- Created PROJECT_PLAN.md (full synthesis document with architecture, phases, critical warnings, next steps)

**Key decisions:**
- GBIF Backbone as cross-group super-backbone ID layer; group-specific primaries per taxonomy group
- mass_type is mandatory non-nullable — cannot mix wet/LW_modeled without flag
- Fish mass from FishBase is always LW_modeled — NOT direct measurement
- NEON DP1.10072.001 added as high-priority overlooked source
- TRY data request must be submitted manually (approval required)
- Zenodo and Figshare API stubs in discover script — implement next

---

## 2026-05-10 — Phase 1 Tier-1 intake completion (Session 2)

**User prompt:** Execute all 8 recommended actions: (1) debug AmphiBIO Figshare download, (2) investigate Zenodo API failure, (3) resolve AVONET download path, (4) run FishBase intake, (5) write NEON intake script, (6) merge completed providers into tier1_combined.csv, (7) run taxonomic reconciliation, (8) verify flagged citations.

**Actions completed:**

### 1. AmphiBIO — COMPLETE (prior session)
- `output/amphibio_compiled.csv`: 591 rows
- Root cause of 0-byte download: WAF block on article-level ndownloader URL; file-level URL (file ID 8828578) succeeds

### 2. Zenodo API — re-run launched
- Root cause of prior 100% failure: transient outage (not code bug)
- `R/zenodo_api.R` confirmed correct; `query_zenodo_term()` returns valid results
- Fixed bug: `globalsize_search_seed_terms()` returns data.frame; must use `terms$query_term[i]` not `terms[i]`
- Re-discovery launched via `scripts/run_zenodo_discovery.sh`

### 3. AVONET — COMPLETE
- Figshare article ID **16586228** verified via Figshare API; file ID 34480856
- DOI `10.1111/ele.13898` verified (HTTP 302 → Wiley OnlineLibrary)
- `providers/avonet/load_avonet.R` updated: UNVERIFIED flags removed, auto-download implemented
- `output/avonet_compiled.csv`: **11,009 rows** (BirdLife taxonomy)
- Download URL: `https://ndownloader.figshare.com/files/34480856` (verified, 20.5 MB)

### 4. FishBase — COMPLETE
- Fixed `providers/fishbase/load_fishbase.R`:
  - Use `load_taxa()` for species list (36,132 species)
  - Use `rfishbase::species(fields=c("Species","Weight","Length"))` for direct max weight
  - Priority logic: direct weight > LW-modeled; mass_type = "wet" vs "LW_modeled"
  - Correct column: `Length` (not `LMax`)
- `output/fishbase_compiled.csv`: **5,657 rows** (2,215 direct weight, 3,443 LW-modeled)

### 5. NEON intake script — WRITTEN (not yet run)
- Created `providers/neon/load_neon.R`
- Uses `neonUtilities::loadByProduct("DP1.10072.001")` for small mammal trapping
- Aggregates max weight per species × sex × lifeStage
- DOI: 10.48443/s4ph-2z37 (NEON data product DOI — verify before publication)
- Output schema: GlobalBodySize standard

### 6. Merge — COMPLETE
- Created `scripts/merge_tier1.R` with per-provider logging and column consistency check
- `data/compiled/tier1_combined.csv`: **25,810 rows**
  - PanTHERIA: 3,542 | EltonTraits birds: 9,993 | EltonTraits mammals: 5,400 | AnAge: 627 | AmphiBIO: 591 | FishBase: 5,657
  - Taxonomic groups: mammal 9,364 | bird 10,164 | fish 5,657 | amphibian 609 | reptile 16
  - 1,874 PanTHERIA rows dropped (no mass recorded — expected)

### 7. Taxonomic reconciliation — IN PROGRESS
- Created `scripts/run_taxon_reconciliation.R`
- Running: 21,696 unique names, 109 batches of 200, GBIF Backbone 2023-08-28
- Output will be `data/compiled/tier1_reconciled.csv` + `data/compiled/taxon_match_cache.csv`

### 8. Citations — VERIFIED
- **Peters 1983**: "The Ecological Implications of Body Size." Cambridge University Press, 1983. ISBN 0-521-28886-5. Book — no DOI applicable for 1983 CUP editions.
- **Brown & Maurer 1989**: Science 243(4895):1145–1150. DOI 10.1126/science.243.4895.1145 — VERIFIED (HTTP 302 → Science.org).
- `PROJECT_PLAN.md` updated: UNVERIFIED flags removed, verification notes added.

**Agents invoked:** @m (supervisor), @coder (script fixes), @code-checker (quality), @step-compliance-checker
**Files changed:** providers/fishbase/load_fishbase.R, providers/avonet/load_avonet.R, providers/neon/load_neon.R (new), scripts/merge_tier1.R (new), scripts/run_taxon_reconciliation.R (new), scripts/run_fishbase_intake.sh (new), data/compiled/tier1_combined.csv (new), output/avonet_compiled.csv (new), output/fishbase_compiled.csv (new), PROJECT_PLAN.md

---

## 2026-05-10 — Science summary and project log (Session 2, continued)

**User prompt:** Create a Project_Log_History covering major items done, dataset counts, and science opportunities. Create a science_summary .html and .rmd to summarize the data with statistics, plots of body size data, and content for enhanced-theory and BIODIVERSITY_INFORMATICS_AUDIT.

**Actions completed:**
- Created `PROJECT_LOG_HISTORY.md`: comprehensive project log with provider-by-provider breakdown, row counts, troubleshooting notes, known caveats (Telford-style honest uncertainty), 6 scientific opportunities with prerequisite data states, and reproducibility statement.
- Created `science_summary.Rmd`: 11-section analysis document covering data inventory, log₁₀ body mass distributions by group, violin/boxplot cross-group comparison, cross-provider density overlay, mass type composition, DwC compliance status table, scaling law theory section (Kleiber 3/4-power, WBE allometric exponents table), QQ-plot for log-normality assessment, cumulative ECDF by group, taxonomic coverage gap analysis, priority next steps.
- Rendered `science_summary.html` successfully from Rmd.

**Agents consulted:** ecology-user (ecological framing, 13-step reasoning), enhanced-theory (WBE scaling laws, allometric exponents, modes of mathematical analysis), biodiversity-informatics-audit (DwC compliance table, mass_type caveat), richard-telford (QQ-plots before interpretation, honest uncertainty, log-scale required).

**Files created:** PROJECT_LOG_HISTORY.md, science_summary.Rmd, science_summary.html
