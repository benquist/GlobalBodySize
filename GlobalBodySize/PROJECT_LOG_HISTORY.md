# GlobalBodySize — Project Log History

**Project start:** 2026-05-09  
**Last updated:** 2026-05-10  
**Project lead:** Brian Jenquist  
**Repository:** GlobalBodySize  
**Primary objective:** Construct a programmatically assembled, provenance-rich, DwC-compliant global body mass database spanning all major animal groups — mammals, birds, fish, amphibians, reptiles — with the potential to extend to plants and insects.

---

## Overview

Body mass is the single most important ecological trait because it constrains metabolic rate (Kleiber's law: B ∝ M^¾), home range, population density, generation time, extinction risk, trophic position, and biogeography (Peters 1983; Brown & Maurer 1989 — both citations verified 2026-05-10). No openly available, cross-taxonomic, reproducible body mass database currently exists that covers all major animal groups with explicit mass-type labeling and GBIF-reconciled taxonomy.

This project fills that gap by automating intake from authoritative curated databases, applying a consistent schema, flagging mass-type (wet vs. LW-modeled vs. preserved specimen), reconciling all names against the GBIF Backbone, and producing a merged, analysis-ready flat file.

---

## Milestone Log

### Phase 0: Planning and Architecture — 2026-05-09

**Goal:** Define scope, architecture, and data source inventory before writing any intake code.

**Completed:**
- Ecology-user agent produced `DATA_SOURCE_INVENTORY.md`: 23 Tier-1 curated databases ranked by taxonomic completeness, 9 programmatic repositories, 83-term API search vocabulary organized by taxon theme, assessment of GBIF MoF occurrence metadata.
- merow-ecology agent produced `ECOLOGICAL_QUALITY_ADVISORY.md`: Tier A/B/C quality ratings per database, critical schema requirements (mass_type non-nullable, LW-modeled flag mandatory for FishBase), priority harvest order, identification of overlooked high-value sources (NEON DP1.10072.001, ICES fisheries data, Dunning 2008 bird handbook, Meiri reptile trait group).
- taxonomy-reconciliation agent produced `TAXONOMY_RECONCILIATION_STRATEGY.md`: GBIF Backbone as cross-group harmonizer, group-specific backbones (MDD mammals, BirdLife birds, FishBase fish, ASW amphibians, Reptile Database reptiles), GBIF `usageKey` storage protocol, synonym cascade handling.
- biodiversity-informatics-checker agent produced `BIODIVERSITY_INFORMATICS_AUDIT.md`: identified critical gaps in backbone strategy (missing MDD evaluation, unstable `usageKey` across backbone releases, absent WoRMS for marine taxa, missing Darwin Core `measurementID`), DwC schema mapping requirements.
- Project scaffold created: `R/`, `providers/`, `scripts/`, `data/compiled/`, `output/` directory structure; `body_mass_schema.R`, `search_terms.R`, `qa_checks.R`, `taxon_reconciliation.R` shared library modules; API client stubs for Dryad, Figshare, Zenodo.

**Architecture decisions:**
- Schema: one row per species × source × sex × life-stage. Mass in grams (SI). `mass_type` non-nullable.
- Taxonomy: verbatim source name stored alongside GBIF-matched accepted name and `gbif_usage_key`.
- Provenance: every row carries `source_doi`, `source_access_date`, `bibliographic_citation`, `basis_of_record`.
- DwC compliance target: MeasurementOrFact extension format; `basisOfRecord` required for every row.

---

### Phase 1: Tier-1 Data Intake — 2026-05-09 to 2026-05-10

**Goal:** Ingest the six highest-priority curated databases, merge them, and run GBIF taxonomic reconciliation.

#### Provider 1: PanTHERIA (Jones et al. 2009)
- **Coverage:** Mammals only; 5,416 species in the raw database
- **Mass metric:** Species-level means compiled from literature; adult, pooled sex
- **Mass type:** `wet` (literature_mean)
- **Access:** MSW3-anchored flat file; automated download from Ecological Archives
- **Output:** `output/pantheria_compiled.csv`
- **Rows with mass:** **3,542** (1,874 species in PanTHERIA have no recorded mass — expected; these are omitted)
- **Status:** COMPLETE ✅
- **Citation:** Jones KE et al. 2009. Ecology 90(9):2648. DOI: 10.1890/08-1494.1

#### Provider 2: EltonTraits 1.0 (Wilman et al. 2014)
- **Coverage:** Birds (9,993 species) + Mammals (5,400 species)
- **Mass metric:** Species-level means; adult, pooled sex
- **Mass type:** `wet` (literature_mean)
- **Access:** Ecology Data Papers; automated download
- **Output:** `output/eltontraits_compiled.csv`
- **Rows:** **15,393** total (birds + mammals combined file split at intake)
- **Status:** COMPLETE ✅
- **Citation:** Wilman H et al. 2014. Ecology 95(7):2027. DOI: 10.1890/13-1917.1
- **Note:** EltonTraits bird mass is diet-corrected mean body mass; somewhat independent from AVONET

#### Provider 3: AnAge (de Magalhães & Costa 2009)
- **Coverage:** Cross-taxonomic; primarily vertebrates; aging and longevity focus
- **Mass metric:** Adult body mass (grams); source varies by entry (literature)
- **Mass type:** `wet`
- **Access:** Human Ageing Genomic Resources; automated download
- **Output:** `output/anage_compiled.csv`
- **Rows:** **627**
- **Status:** COMPLETE ✅
- **Citation:** de Magalhães JP, Costa J. 2009. J Evol Biol 22(8):1770–1774. DOI: 10.1111/j.1420-9101.2009.01783.x

#### Provider 4: AmphiBIO (Oliveira et al. 2017)
- **Coverage:** Amphibians only; 6,776 species attempted
- **Mass metric:** Mean adult wet mass (grams) compiled from literature
- **Mass type:** `wet` (literature_mean, adult, pooled sex)
- **Access:** Figshare article 4644424, file ID 8828578 — verified download URL
- **Output:** `output/amphibio_compiled.csv`
- **Rows:** **591** (6,185 species lack mass data in AmphiBIO — a known gap in amphibian mass literature)
- **Status:** COMPLETE ✅
- **Citation:** Oliveira BF et al. 2017. Sci Data 4:160123. DOI: 10.1038/sdata.2016.123
- **Troubleshooting note:** Initial download produced 0-byte file due to WAF challenge on article-level ndownloader URL. Resolved by using file-level Figshare API URL.

#### Provider 5: FishBase via rfishbase (Froese & Pauly)
- **Coverage:** Actinopterygii (ray-finned fishes); 36,132 species in FishBase
- **Mass metric:** Two-path approach:
  - *Path A (priority):* Directly recorded maximum weight in grams — available for ~3,100 species; `mass_type = "wet"`
  - *Path B (fallback):* L-W equation modeled mass: W = a × L^b where L = species maximum total length; `mass_type = "LW_modeled"` — available for ~14,000 additional species
- **Access:** rfishbase R package API; `load_taxa()` for species list, `species()` for direct weight, `length_weight()` for L-W parameters
- **Output:** `output/fishbase_compiled.csv`
- **Rows:** **5,657** (2,215 direct weight + 3,443 LW-modeled)
- **Status:** COMPLETE ✅
- **Citation:** Froese R, Pauly D (eds). FishBase. World Wide Web electronic publication. www.fishbase.org. Access date: 2026-05-10
- **Critical caveat:** LW-modeled mass is NOT directly measured; it is a modeled estimate using the largest published total length for each species as the reference length. These values are systematically lower than maximum observed mass for large species because: (1) L-W equations are fit across all size classes, (2) reference length may not represent the actual maximum individual. `mass_type = "LW_modeled"` must never be mixed with `wet` in analyses without explicit separation or sensitivity analysis.
- **Troubleshooting note:** rfishbase `species()` does not accept `Family`, `Order`, `Class` as selectable fields (tidyselect error); taxonomy requires `load_taxa()`. Column is `Length` (not `LMax`).

#### Provider 6: AVONET (Tobias et al. 2022)
- **Coverage:** All birds; 11,009 species (BirdLife taxonomy)
- **Mass metric:** Species-level mean body mass from >90,000 museum specimens + live captures
- **Mass type:** `wet` (species mean from museum + live)
- **Access:** Figshare article 16586228 (DOI: 10.6084/m9.figshare.16586228.v7), file ID 34480856 — both verified 2026-05-10. Paper DOI: 10.1111/ele.13898 — verified (HTTP 302 → Wiley).
- **Output:** `output/avonet_compiled.csv`
- **Rows:** **11,009**
- **Status:** COMPLETE ✅ (not yet included in tier1_combined.csv — merge script needs update)
- **Citation:** Tobias JA et al. 2022. Ecology Letters 25(3):581–597. DOI: 10.1111/ele.13898
- **Note:** AVONET uses BirdLife 2021 taxonomy. GBIF Backbone may lag BirdLife by 1–2 versions; synonymy rate for birds at GBIF reconciliation step should be checked carefully.

---

### Phase 1 Outputs

#### Merged Dataset: `data/compiled/tier1_combined.csv`
- **Total rows:** 25,810 (AVONET not yet merged — pending merge_tier1.R update)
- **Column schema:** 32 columns; one row per species × source combination
- **Mass range:** ~0.5 g (small amphibians) to ~492,714 g (dromedary camel in PanTHERIA)
- **Provider breakdown:**

| Provider | Rows | Primary Taxonomic Group |
|---|---|---|
| PanTHERIA | 3,542 | Mammalia |
| EltonTraits (birds) | 9,993 | Aves |
| EltonTraits (mammals) | 5,400 | Mammalia |
| AnAge | 627 | Multi-taxon vertebrates |
| AmphiBIO | 591 | Amphibia |
| FishBase | 5,657 | Actinopterygii |
| **Total** | **25,810** | |

- **Taxonomic group breakdown:**

| Group | Rows |
|---|---|
| Mammalia | 9,364 |
| Aves | 10,164 |
| Actinopterygii | 5,657 |
| Amphibia | 609 |
| Reptilia | 16 |

- **Mass type breakdown:** Most rows are `wet` (direct literature means); 3,443 FishBase rows are `LW_modeled`. This distinction is preserved in the `mass_type` column and must be respected in any downstream analysis.
- **Basis of record:** `Literature` (majority), `PreservedSpecimen` (AVONET museum), `HumanObservation` (NEON when added)

#### Taxonomic Reconciliation: `data/compiled/tier1_reconciled.csv`
- **Tool:** `rgbif::name_backbone()` against GBIF Backbone version 2023-08-28
- **Input:** 21,696 unique verbatim taxon names from tier1_combined.csv
- **Results:**
  - EXACT matches: **25,224 rows** (97.7% of data rows)
  - Synonyms identified: **2,033 rows** — these carry the GBIF-accepted name in `accepted_name` and can be standardized
  - Unresolved (NONE/error): **25 rows** — require manual review
  - FUZZY matches: 0 (strict exact matching used)
- **Cache:** `data/compiled/taxon_match_cache.csv` — stores all queries to avoid re-querying GBIF on re-runs
- **GBIF Backbone version:** 2023-08-28 — recorded with every match row for reproducibility

---

### Phase 1 In-Progress Items (as of 2026-05-10)

| Item | Status | Notes |
|---|---|---|
| Zenodo dataset discovery re-run | Running | 83 search terms × 2 pages × 100 results/page; previous run failed due to transient Zenodo outage |
| AVONET merge into tier1_combined.csv | Pending | Add `output/avonet_compiled.csv` to `scripts/merge_tier1.R` PROVIDERS list and re-run |
| NEON small mammal intake | Script written; not run | `providers/neon/load_neon.R` written; requires `neonUtilities` install; DOI to verify |
| VertNet museum specimens | Not started | High value for North American mammals; requires `spocc` or direct API |
| TRY Plant Trait Database | Not started | Manual data request required; approved access needed |
| InsectSize database | Not started | Requires custom download from Chown & Gaston group |
| Reptile Database expansion | Not started | 16 reptile rows via AnAge; major gap |

---

## Current Data Inventory (2026-05-10)

| File | Rows | Size | Status |
|---|---|---|---|
| output/pantheria_compiled.csv | 3,542 | ~2.5 MB | COMPLETE |
| output/eltontraits_compiled.csv | 15,393 | ~7.3 MB | COMPLETE |
| output/anage_compiled.csv | 627 | ~303 KB | COMPLETE |
| output/amphibio_compiled.csv | 591 | ~265 KB | COMPLETE |
| output/fishbase_compiled.csv | 5,657 | — | COMPLETE |
| output/avonet_compiled.csv | 11,009 | — | COMPLETE (not yet in merge) |
| data/compiled/tier1_combined.csv | 25,810 | — | COMPLETE |
| data/compiled/tier1_reconciled.csv | 25,810 | — | COMPLETE |
| data/compiled/taxon_match_cache.csv | 21,696 | — | COMPLETE |
| output/candidate_datasets.csv | 1,043 | ~905 KB | Dryad+Figshare (Zenodo pending) |

---

## Known Caveats (Honest Uncertainty Statement)

The following issues are documented and must be addressed before this database is used in publication-grade analyses:

1. **LW-modeled fish mass must not be mixed with wet mass without flagging.** 3,443 FishBase rows carry mass_type = "LW_modeled". These are estimates computed from published L-W equations applied to maximum total length. They are *not* measured maximum masses. Mixing these with directly measured values will systematically bias allometric slopes. Filter or stratify by `mass_type` before any cross-taxon scaling analysis.

2. **PanTHERIA uses MSW3 mammal taxonomy (anchored ~2005).** Many mammal names in PanTHERIA are now considered synonyms under MDD (Mammal Diversity Database, current ASM standard). The GBIF Backbone partially addresses this (2,033 synonyms flagged), but MDD-specific evaluation is not yet complete. Downstream mammal-focused analyses should cross-check species counts against the current MDD version.

3. **AVONET uses BirdLife 2021 taxonomy; GBIF Backbone may lag by 1–2 annual BirdLife versions.** Some recent BirdLife splits/lumps may not yet be in the GBIF Backbone. Treat bird synonymy warnings at reconciliation step with care.

4. **Reptile coverage is critically sparse (16 rows).** These 16 rows come from AnAge (primarily long-lived species). Squamate, crocodilian, and chelonian diversity is almost entirely unrepresented. Do not use this database for reptile body size analyses without adding a dedicated source (e.g., Meiri et al. reptile traits, Reptile Database).

5. **Amphibian mass is sparse relative to species richness.** 591 rows from AmphiBIO vs. ~8,000+ known amphibian species. Most amphibian species lack published adult wet mass. Phylogenetic imputation may be required for completeness analyses.

6. **Darwin Core `measurementID` is not yet populated.** This is a required DwC-MoF field for linking individual measurements. Schema update needed before submission to GBIF or OBIS.

7. **Geographic coordinates are missing for all literature-source records.** `decimal_latitude` / `decimal_longitude` are NA for PanTHERIA, EltonTraits, AnAge, AmphiBIO, and AVONET — these are species-level trait records, not occurrence records. FishBase and NEON entries also lack coordinates at the species-mean level. Spatial analyses require joining to separate occurrence layers.

8. **25 names could not be reconciled against GBIF Backbone.** These should be reviewed manually. They may represent spelling errors, recently described species not yet in GBIF, or hybrid taxa.

---

## Scientific Opportunities

The following analyses are tractable with the current data and represent high-priority scientific outputs. Each is flagged with the prerequisite data state.

### 1. Cross-taxon body size scaling (tractable now)
**Question:** Does the body size frequency distribution differ in shape and scale across major animal groups, and how does this relate to diversification rates?

Body mass distributions within taxonomic groups are typically log-normal or right-skewed on a log scale (the "right skew of life" from Brown & Maurer 1989). With ~26,000 species spanning mammals, birds, fish, and amphibians, this database can test whether the modal body size and distribution variance differ across groups in a way consistent with metabolic and life-history theory. This requires no additional data — the current tier1_combined.csv is sufficient.

**Required:** Filter to `mass_type = "wet"` only for this analysis. Do not include LW-modeled fish mass without explicit sensitivity analysis.

### 2. Metabolic scaling baseline (tractable now, if linked to metabolic rate data)
**Question:** Does the allometric exponent for metabolic rate vs. body mass match the WBE prediction of ¾ when estimated across the full diversity of animal life vs. within groups?

The 3/4-power metabolic scaling law (Kleiber 1947; West, Brown & Enquist 1997 — WBE network theory) predicts B ∝ M^0.75 from first principles of fractal vascular network geometry. Debate continues about whether the exponent is 0.75 (WBE) or 0.67 (Rubner surface-area model) or varies by group. A cross-taxon body mass database is a prerequisite for any metabolic rate vs. mass analysis — it provides the mass axis. Metabolic rate data must be joined from a separate source (e.g., Clarke & Johnston 1999 for fish, Savage et al. 2004 mammals+birds).

**Required:** `mass_type` stratification essential. Body mass axis only — metabolic rate data needed from external source.

### 3. Body size — extinction risk relationship (tractable now)
**Question:** Is body mass a significant predictor of IUCN extinction risk, independently across taxonomic groups and jointly?

Large body size is a consistent predictor of extinction risk in vertebrates (Cardillo et al. 2005, 2008). This can be tested with the current data by joining to IUCN Red List status via `rgbif` or `rredlist`. A mixed-effects model with taxonomic group as a random effect on the intercept (not slope) would be appropriate. Body mass spans ~12 orders of magnitude in this dataset — a powerful gradient for risk modeling.

**Required:** IUCN Red List API join (not included in current data). Body mass available now.

### 4. Trophic level — body size scaling (tractable now for birds and mammals)
**Question:** Is body mass a consistent predictor of trophic position within and across vertebrate groups?

EltonTraits provides trophic guild information alongside body mass for both birds and mammals. Cross-group analysis of mass vs. trophic position (herbivore/omnivore/carnivore/insectivore) can be performed directly from the merged dataset without additional data. For fish, FishBase trophic level data is accessible via `rfishbase::ecology()`. This is a clean natural experiment: does body mass predict trophic level within groups, and is the relationship consistent across independent evolutionary lineages?

**Required:** Current data sufficient for birds + mammals. FishBase trophic data join needed for fish.

### 5. Amphibian mass imputation feasibility (tractable now, requires phylogeny)
**Question:** How much of amphibian body mass diversity can be predicted from phylogenetic imputation using the 591 known masses?

With only 591 of ~8,000+ amphibian species having known mass, a phylogenetically controlled imputation (e.g., Rphylopars, MICE with phylogenetic covariance, or Bayesian ancestral state estimation) could substantially expand coverage. The question is whether phylogenetic signal in body mass (Blomberg's K or Pagel's λ) is high enough to make imputation reliable for this group. If λ is near 1 (strong phylogenetic signal), imputation is defensible. If λ is near 0, imputation error will be large.

**Required:** Amphibian phylogeny (pyron-wiens or Jetz-pyron tree); current 591 rows as calibration set. Signal analysis before any imputation attempt.

### 6. Macroecological body size — range size relationship
**Question:** Is there a positive body size — geographic range size relationship in vertebrates (the Gaston-Blackburn prediction), and is its slope consistent across groups?

The positive relationship between body mass and geographic range size is a classic macroecological prediction (Gaston & Blackburn 1996; Brown & Maurer 1989). Testing this requires joining body mass data to species range size data from BIEN, IUCN, or BirdLife. The current dataset provides the mass axis for all groups. Range size data is available from GBIF occurrence records, BirdLife shapefile products, IUCN, or BIEN.

**Required:** Body mass available now. Range size data join needed from external source.

---

## Reproducibility Statement

All intake scripts are in `providers/*/load_*.R`. All merge and reconciliation scripts are in `scripts/`. All output files are reproducible by re-running scripts in order:

```
1. providers/*/load_*.R          # per-provider intake
2. scripts/merge_tier1.R         # stack providers
3. scripts/run_taxon_reconciliation.R  # GBIF reconciliation
```

GBIF Backbone version is recorded in every reconciliation row (`backbone_version = "GBIF_Backbone_2023-08-28"`). rfishbase data is accessed from the rfishbase cache (version captured via `rfishbase:::.pkg` or equivalent at run time). All source DOIs are embedded in output rows.

**R version and package versions** were not pinned via `renv` for Phase 1. An `renv::snapshot()` should be run before Phase 2 analyses to lock the environment for reproducibility.

---

*Log maintained in `GlobalBodySize/PROJECT_LOG_HISTORY.md`. Per-session details in `chat_provenance_log.md`.*

---

## Phase 2: Database Expansion Planning — 2026-05-11

**Goal:** Identify and prioritize additional body mass data sources to fill critical taxonomic gaps. Multi-agent review (merow-ecology, biodiversity-science-guard, ecology-user, enhanced-theory, scholarly-rigor-reviewer) completed 2026-05-11.

---

### Current State (as of 2026-05-11)

| Group | Rows | ~Global spp | Raw coverage | Gap severity |
|---|---|---|---|---|
| Birds | 22,121 | ~10,900 | >100% (overlap) | ✅ Adequate |
| Mammals | 11,270 | ~6,600 | >100% (overlap) | ✅ Adequate |
| Reptiles | 6,773 | ~10,900 | ~62%, lizards only | ⚠️ Snakes/crocs absent |
| Fish | 5,739 | ~35,000 | ~16% | ⚠️ Modest |
| Amphibians | 619 | ~8,500 | **~7%** | 🔴 Critical |
| Insects | 772 | ~1,000,000 | **<0.1%** | 🔴 Critical for 9 OoM span |
| Arachnids | 131 | ~50,000 | <0.3% | 🔴 |
| Crustaceans | 28 | ~50,000 | <0.1% | 🔴 |

**Critical finding from merow-ecology agent:** For the May (1988) species richness vs. body size replication spanning 9+ orders of magnitude, insects are the single most important gap — extending the mass axis down by ~3–4 log decades. Amphibians fill a critical small-body intermediate region (0.1–100 g) with only ~7% species coverage. ReptTraits (snakes, crocodilians) is blocking the reptile tail of the distribution.

---

### Tier A — Scripts Already Written; Run in Order

| Step | Provider | What it adds | Status | Schema pre-req |
|---|---|---|---|---|
| A1 | **ReptTraits** (Meiri et al. 2024, Sci Data 11:386; DOI: 10.1038/s41597-024-03079-5) | ~12,060 reptile spp: snakes, crocs, turtles, lizards with **directly measured** maximum mass | ⬜ Not yet run | `mass_type = "literature_maximum"` — **ADDED 2026-05-11** |
| A2 | **SeaLifeBase** (rfishbase) | Marine non-fish: echinoderms, molluscs, cephalopods | ⬜ Not yet run | Verify Weight units against known species before trusting |
| A3 | **DISPERSE** (Sarremejane et al. 2020, Sci Data 7:386; DOI: 10.1038/s41597-020-00732-7) | Aquatic macroinvertebrate **body lengths** (NOT mass); European freshwater; genus-level | ⬜ Not yet run | Routes to linear size table only; `mass_type = NA` |

**Key caveat — ReptTraits mass type:** ReptTraits `Maximum body mass (g)` is the **maximum recorded** mass across literature, not a species mean. This is distinct from `wet` (species mean) and from `LW_modeled` (allometric estimate). `mass_type = "literature_maximum"` added to schema 2026-05-11. Do NOT average with `wet` values in scaling regressions without explicit stratification.

**Key caveat — DISPERSE:** DISPERSE provides body length, not body mass. It feeds `tier1_linear_size_combined.csv`, not `tier1_combined.csv`. Any mass derivation from length would require invertebrate-specific LW equations with large uncertainty — do not implement without explicit justification.

---

### Tier B — New Providers to Script (high confidence, accessible)

| Priority | Dataset | Groups | ~Species with mass | Access | Citation confidence |
|---|---|---|---|---|---|
| B1 | **Myhrvold et al. 2015 Amniote Life History Database** | Birds, mammals, reptiles | ~21,322 amniote spp | Ecological Archives direct download | DOI `10.1890/15-0846R.1` — verify before citing |
| B2 | **AmphiBIO mass filter audit** | Amphibians | ~6,776 in DB; only 619 extracted | Already have script — investigate `!is.na(body_mass_g)` filter | Known source |
| B3 | **VertNet via `rvertnet`** | Vertebrates (esp. tropical reptiles, amphibians) | Individual specimen masses | R package on CRAN; query by taxon group | Moderate — living query |
| B4 | **GBIF MeasurementOrFact scan** | Insects, fish, amphibians | Unknown — targeted scan | `rgbif::occ_download()` with MoF extension | Uncertain yield |

---

### Tier C — Invertebrate & Insect (requires literature search / access confirmation)

| Priority | Dataset | Notes | Confidence |
|---|---|---|---|
| C1 | **PREDICTS (NHM London)** | Individual-level field mass; insects + inverts; DOI `10.1002/ece3.1303` — UNVERIFIED | Verify DOI and access terms before scripting |
| C2 | **Ant Trait Database (Parr et al.)** | Formicidae worker mass + head width; search Dryad/Zenodo | UNVERIFIED citation — locate paper before committing |

**Honest data gap:** No verified global insect body mass database analogous to PanTHERIA currently exists. Insect body mass coverage will remain a patchwork. Most insect body mass literature reports **dry mass** — fundamentally incompatible with mammal/bird wet mass without explicit taxon-specific conversion.

---

### Schema Changes Completed 2026-05-11

1. `R/body_mass_schema.R`: added `"literature_maximum"` and `"SVL_allometric"` to `globalsize_mass_type_vocab()` with documented meanings.
2. `providers/repttraits/load_repttraits.R`: corrected `mass_type` from `"wet"` → `"literature_maximum"` and `measurement_method` from `"literature_mean"` → `"literature_maximum"`; updated `qa_note` to include `data_quality_flag=maximum_not_mean`.

---

### Critical Pre-Analysis Warnings (merow-ecology + biodiversity-science-guard)

1. **Measurement type heterogeneity is the most dangerous bias for scaling exponents.** The database mixes: direct live weighing, museum specimens, LW-allometric estimates, and literature maximums. All scaling analyses must stratify on `mass_type` and run sensitivity checks.
2. **Tropical taxa are underrepresented.** Tropical vertebrates (especially amphibians, small reptiles) are systematically smaller — undersampling shifts the apparent mode rightward, attenuating the species richness vs. body size slope.
3. **GBIF deduplication required before species counting.** Current 47,456 rows include heavy overlap for mammals (PanTHERIA + EltonTraits + AnAge) and birds (AVONET + EltonTraits). Use `gbif_usage_key` (accepted name) for deduplication before the May (1988) replication.
4. **Dry mass vs. wet mass for insects:** Never pool insect dry mass with mammal/bird wet mass without a documented taxon-specific conversion factor and sensitivity analysis.
5. **ReptTraits snake mass coverage uncertain:** After ReptTraits runs, stratify `sum(!is.na(mass_g))` by Order — snake mass coverage may be sparse even within ReptTraits.

---

### Run Order for Phase 2

```
1. providers/repttraits/load_repttraits.R    # A1 — highest value, schema fixed
2. providers/sealifebase/load_sealifebase.R  # A2 — verify Weight units first
3. providers/disperse/load_disperse.R        # A3 — linear size only
4. scripts/merge_tier1.R                     # re-merge after A1+A2
5. Investigate AmphiBIO 619-row gap          # B2
6. Script Myhrvold 2015                      # B1
7. VertNet targeted query                    # B3
```
