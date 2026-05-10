# GlobalBodySize — Project Plan

**GitHub repo:** GlobalBodySize  
**Date created:** 2026-05-09  
**Modeled after:** DryadPlantTraits (this workspace)  
**Status:** Phase 0 — Planning and scaffold complete; Phase 1 — Tier 1 intake ready to run  
**Agent contributions:** ecology-user synthesis, merow-ecology quality advisory, taxonomy-reconciliation strategy, biodiversity-informatics-checker audit

---

## Scientific Objective

Construct a programmatically assembled, provenance-rich, DwC-compliant global body mass / body size database spanning all major animal groups (mammals, birds, fish, reptiles, amphibians, insects/arthropods) and plants. The primary deliverable is a species-level table of adult body mass in grams with full metadata for mass type, measurement method, life stage, sex, and taxonomic provenance.

Body mass is the single most important ecological trait because it enters ~8 causal ecological pathways: metabolic rate, home range, population density, generation time, extinction risk, trophic position, biogeography, and physiology (Peters 1983; Brown & Maurer 1989).

> **Citations verified 2026-05-10:**
> - Peters RH. 1983. *The Ecological Implications of Body Size*. Cambridge University Press, Cambridge, UK. ISBN: 0-521-28886-5. (Book — no DOI applicable for 1983 CUP editions; widely held in university libraries.)
> - Brown JH, Maurer BA. 1989. Macroecology: The Division of Food and Space Among Species on Continents. *Science* 243(4895):1145–1150. DOI: 10.1126/science.243.4895.1145 — VERIFIED (resolves to Science.org).

---

## Architecture (Modeled on DryadPlantTraits)

```
GlobalBodySize/
├── R/                          # Shared library functions
│   ├── search_terms.R          # 83-term API search vocabulary (by taxon theme)
│   ├── body_mass_schema.R      # Schema, controlled vocabularies, plausible ranges
│   ├── dryad_api.R             # Dryad REST API client
│   ├── candidate_filter.R      # Dataset scoring heuristic
│   ├── taxon_reconciliation.R  # GBIF backbone + cross-group collision detection
│   └── qa_checks.R             # Range, unit, mandatory field, outlier QA
│
├── scripts/                    # Executable pipeline stages
│   ├── discover_body_mass_datasets.R   # Stage 1: API discovery (Dryad/Zenodo/Figshare)
│   ├── run_tier1_intake.R              # Stage 2: Tier 1 database intake
│   └── [Stage 3: compile + reconcile + QA — to implement]
│
├── providers/                  # Per-source intake scripts
│   ├── pantheria/              # PanTHERIA mammals
│   ├── avonet/                 # AVONET birds
│   ├── fishbase/               # FishBase via rfishbase
│   ├── amphibio/               # AmphiBIO amphibians [stub]
│   ├── eltontraits/            # EltonTraits 1.0 [stub]
│   ├── try_plants/             # TRY plant traits [stub — requires manual request]
│   ├── anage/                  # AnAge vertebrates [stub]
│   ├── vertnet/                # VertNet museum specimens [Phase 2]
│   ├── neon/                   # NEON small mammal mass [stub]
│   ├── dryad/                  # Dryad harvested datasets [from discovery]
│   ├── zenodo/                 # Zenodo harvested datasets [from discovery]
│   ├── figshare/               # Figshare harvested datasets [from discovery]
│   └── manual_intake/          # Manually curated sources
│
├── data/
│   ├── raw/                    # Downloaded source files (not committed to git)
│   └── compiled/               # Compiled CSV per provider + tier1_combined.csv
│
├── output/                     # candidate_datasets.csv, candidate_files.csv
├── reports/                    # Rmd harvest summary reports
│
├── DATA_SOURCE_INVENTORY.md    # Full annotated source inventory
├── ECOLOGICAL_QUALITY_ADVISORY.md  # merow-ecology advisory
├── TAXONOMY_RECONCILIATION_STRATEGY.md
├── BIODIVERSITY_INFORMATICS_AUDIT.md
├── PROJECT_PLAN.md             # This file
└── chat_provenance_log.md
```

---

## Phase 1 — Tier 1 Database Intake (Priority Order)

Per merow-ecology advisory. Run `scripts/run_tier1_intake.R`.

| Priority | Source | Group | Access | Tier | Status |
|---|---|---|---|---|---|
| 1 | **PanTHERIA** | Mammals | Direct download | A | Script ready |
| 2 | **AVONET** | Birds | Figshare (manual download required) | A | Script ready |
| 3 | **rfishbase** | Fish | R package | B (LW-modeled) | Script ready |
| 4 | **AmphiBIO** | Amphibians | Figshare | A/B | Stub — implement `providers/amphibio/` |
| 5 | **TRY** | Plants | Registration required — start now | A | Submit request at https://www.try-db.org |
| 6 | **Ernest 2003** | Mammals | ESA Archives | A | Stub — implement `providers/eltontraits/` |
| 7 | **EltonTraits** | Birds + Mammals | ESA Archives | A/B | Stub — cross-check only |
| 8 | **AnAge** | Vertebrates | Direct download | B | Stub — gap-fill |
| 9 | **Meiri Squamate datasets** | Reptiles | Dryad/Figshare | B | Discover via Stage 1 search |
| 10 | **NEON small mammal** | Mammals | neonUtilities R pkg | A | CRIT-8 gap per informatics audit |

### Action required before Phase 1 can run:
1. Download AVONET manually from Figshare (URL UNVERIFIED — search "AVONET Tobias 2022")
2. Confirm PanTHERIA URL at ESA Ecological Archives
3. Verify `rfishbase` column names match script expectations
4. Submit TRY data request (approval typically takes 2-4 weeks)

---

## Phase 2 — Programmatic Repository Discovery

Run `scripts/discover_body_mass_datasets.R` to search Dryad, Zenodo, and Figshare using the 83-term vocabulary in `R/search_terms.R`.

Estimated candidate yield (based on DryadPlantTraits experience): ~500-2,000 scored datasets before filtering.

API endpoints:
- Dryad: `https://datadryad.org/api/v2/search` (same as DryadPlantTraits — working code)
- Zenodo: `https://zenodo.org/api/records?q=...&type=dataset` — implement in `providers/zenodo/`
- Figshare: `https://api.figshare.com/v2/articles/search` — implement in `providers/figshare/`
- OSF: `https://api.osf.io/v2/search/?q=...` — lower priority

### Zenodo and Figshare API implementation:
The `discover_body_mass_datasets.R` script has stubs (`query_zenodo_term`, `query_figshare_term`). These must be implemented by adapting the Dryad client pattern.

---

## Phase 3 — Taxonomic Reconciliation

After compilation, run GBIF backbone reconciliation using `R/taxon_reconciliation.R`.

Key rules (from TAXONOMY_RECONCILIATION_STRATEGY.md):
- Group routing: mammal → MDD, bird → BirdLife, fish → FishBase, reptile → Reptile Database, amphibian → AmphibiaWeb, insect → GBIF/CoL, plant → WCVP/POWO
- Cross-group ID: GBIF `usageKey` as super-backbone key
- Cross-group collision detection: run after all groups reconciled
- Minimum match rate: ≥70% per dataset before merging

Critical fixes required (from BIODIVERSITY_INFORMATICS_AUDIT.md):
- CRIT-1: Implement GBIF backbone version capture via registry API (not a nonexistent `gbif_version()` function)
- CRIT-2: Add MDD (Mammal Diversity Database) as primary mammal backbone instead of MSW3
- CRIT-3: Store GBIF `usageKey` snapshot date — keys are not stable across backbone releases

---

## Phase 4 — Quality Assurance

Run `R/qa_checks.R` suite:
- Range check: group-specific plausible mass ranges
- Unit check: all values in grams, `mass_type` in controlled vocabulary
- Mandatory field check: 13 non-nullable fields
- Statistical outlier detection: log-scale IQR × 3 per group
- Cross-group collision flag

Target QA pass rates by phase:
- Phase 1 Tier 1 databases: >90% pass
- Phase 2 harvested datasets: >70% pass (heterogeneous sources expected)

---

## Critical Data Integration Warnings

These are non-negotiable schema requirements per merow-ecology and biodiversity-informatics-checker:

1. **`mass_type` is mandatory non-nullable.** Never mix `wet` and `LW_modeled` mass in cross-group analyses without flagging. FishBase mass is always `LW_modeled`.

2. **LW-modeled fish mass must store parameters.** Store `a`, `b`, `n`, and `reference_length_cm` in `qa_note`. These are unrecoverable post-hoc without this field.

3. **Sexual dimorphism warning.** Many analyses should be done separately by sex. Elephant seals: ~8-10× dimorphism. Raptors: 1.5-2× (reversed). Insect parasitoids: up to 100×. Pooled-sex means are directionally biased, not random error.

4. **GBIF `usageKey` is not stable across backbone versions.** Always snapshot the backbone version date alongside the key. Never use `usageKey` as a primary join key across pipeline runs without verifying backbone version match.

5. **DwC compliance requires `measurementID`, `basisOfRecord`, and full higher taxonomy chain.** These were identified as missing in the initial schema — all are now included in `body_mass_schema.R`.

---

## Specialist Sources for Manual Intake

Per merow-ecology advisory + biodiversity-informatics-checker, these high-value sources cannot be reached via standard API and require manual intake scripts:

| Source | Group | Access | Priority |
|---|---|---|---|
| Dunning 2008 CRC Handbook of Avian Body Masses | Birds | Purchase/library | High |
| ICES/AFSC trawl surveys (weight-at-age) | Fish | ICES Data Portal | High |
| NEON DP1.10072.001 small mammal trapping | Mammals | `neonUtilities` R pkg | High |
| iDigBio + NHM London Data Portal | All vertebrates | API + download | Medium |
| ATLANTIC-BATS (Neotropical bat capture data) | Mammals | Dryad/Ecology journal | High |
| Reptile-Trait (Meiri group latest) | Reptiles | Dryad/Figshare — search | High |
| European insect biomass (Krefeld/Hallmann) | Insects | Journal supplement | Medium |
| SVL-to-mass allometric equations (herpetofauna) | Reptiles/Amphibians | Literature compilation | Medium |
| FishLife (Thorson et al.) — Bayesian fish gap-fill | Fish | CRAN `FishLife` | Medium |

---

## GBIF MeasurementOrFact Assessment

Per biodiversity-informatics-checker audit: **Tier C — supplemental only for Phase 1.**

Reason: Most GBIF occurrence records do not include MeasurementOrFact extension data. Body mass coverage is extremely sparse outside a few specific datasets.

More efficient approach for Phase 2: query GBIF dataset registry to enumerate MoF-using datasets first, then download only those. Avoids multi-hundred-GB blind download.

R approach when ready:
```r
# Enumerate GBIF datasets using MeasurementOrFact
# rgbif::dataset_search(type = "OCCURRENCE", ...) -- confirm parameters
```

---

## R Package Dependencies

```r
## Core
install.packages(c(
  "data.table",    # fast tabular I/O
  "jsonlite",      # API response parsing
  "httr",          # HTTP requests (alternative to curl CLI)
  "readxl"         # AVONET Excel parsing
))

## Taxonomy reconciliation
install.packages(c(
  "rgbif",         # GBIF backbone queries
  "taxize",        # Multi-backbone queries (ITIS, CoL, etc.)
  "rfishbase"      # FishBase L-W parameters
))

## Optional (confirm CRAN availability before use)
## "rredlist"     # IUCN Red List API
## "rvertnet"     # VertNet museum specimens
## "neonUtilities"# NEON ecological monitoring data
## "WorldFlora"   # WCVP/POWO plant taxonomy (UNVERIFIED CRAN name)
## "FishLife"     # Bayesian fish trait imputation (UNVERIFIED)
```

---

## Provenance and Citation Policy

Every row in the compiled table MUST carry:
1. `source_id` — stable identifier for the contributing database
2. `bibliographic_citation` — full citation string
3. `source_doi` — DOI of source dataset
4. `source_access_date` — when we accessed it
5. `verbatim_taxon_name` — name as-received from source
6. `backbone_version` — which backbone version was used for reconciliation
7. `query_timestamp_utc` — when reconciliation was run
8. `measurement_id` — unique ID for each measurement row (DwC MoF compliance)
9. `mass_type` — ontological type of mass value
10. `basis_of_record` — DwC basisOfRecord

The compiled table is NOT suitable for direct publication without expert review. The BIODIVERSITY_INFORMATICS_AUDIT.md documents all current gaps.

---

## Next Steps (in order)

1. [ ] **Manual action:** Download AVONET from Figshare; confirm URL
2. [ ] **Manual action:** Confirm PanTHERIA URL at ESA archives; download
3. [ ] **Manual action:** Submit TRY data request at https://www.try-db.org
4. [ ] Run `scripts/run_tier1_intake.R` with PanTHERIA + rfishbase first (AVONET after download)
5. [ ] Implement `providers/amphibio/load_amphibio.R`
6. [ ] Implement `providers/zenodo/` and `providers/figshare/` API clients for Stage 1 discovery
7. [ ] Run `scripts/discover_body_mass_datasets.R --repos=dryad` (Dryad client is working)
8. [ ] Add NEON small mammal intake (high priority per informatics audit)
9. [ ] Implement taxonomic reconciliation pipeline after ≥3 providers are compiled
10. [ ] Create harvest summary Rmd report in `reports/`
11. [ ] Initialize git repo at GitHub: GlobalBodySize

---

## Files in This Project

| File | Purpose |
|---|---|
| `DATA_SOURCE_INVENTORY.md` | Full annotated source inventory (23 Tier 1 + 9 repositories) |
| `ECOLOGICAL_QUALITY_ADVISORY.md` | merow-ecology tier ratings and schema warnings |
| `TAXONOMY_RECONCILIATION_STRATEGY.md` | Backbone choices and reconciliation workflow |
| `BIODIVERSITY_INFORMATICS_AUDIT.md` | Critical issues and DwC compliance gaps |
| `PROJECT_PLAN.md` | This file |
| `R/search_terms.R` | 83-term API search vocabulary |
| `R/body_mass_schema.R` | Schema + controlled vocabularies + plausible ranges |
| `R/dryad_api.R` | Dryad REST API client |
| `R/candidate_filter.R` | Candidate dataset scoring heuristic |
| `R/taxon_reconciliation.R` | GBIF backbone reconciliation helpers |
| `R/qa_checks.R` | QA suite (range, unit, mandatory field, outlier) |
| `scripts/discover_body_mass_datasets.R` | Stage 1: API discovery |
| `scripts/run_tier1_intake.R` | Stage 2: Tier 1 intake |
| `providers/pantheria/load_pantheria.R` | PanTHERIA intake |
| `providers/avonet/load_avonet.R` | AVONET intake |
| `providers/fishbase/load_fishbase.R` | FishBase rfishbase intake |
