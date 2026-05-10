# GlobalBodySize — Biodiversity Informatics Audit

**Agent:** biodiversity-informatics-checker (GitHub Copilot / Claude Sonnet 4.6)  
**Date:** 2026-05-09  
**Requested by:** Brian Jenquist  
**Documents audited:**
- `GlobalBodySize/DATA_SOURCE_INVENTORY.md`
- `GlobalBodySize/ECOLOGICAL_QUALITY_ADVISORY.md`
- `GlobalBodySize/TAXONOMY_RECONCILIATION_STRATEGY.md`

> **SCHOLARLY RIGOR NOTICE:** Items marked **UNVERIFIED** require independent confirmation before use in publications, grant proposals, or production pipelines. This is an informatics advisory document, not a peer-reviewed synthesis. Function names, package names, database coverage claims, and record counts must be verified before implementation.

---

## SECTION A — Taxonomic Backbone Choices

### Critical Issues

**A-CRIT-1: `rgbif::gbif_version()` does not exist.**  
The taxonomy strategy (Section 1.1) recommends `rgbif::gbif_version()` to record the GBIF Backbone version at query time. This function does not exist in the `rgbif` package (UNVERIFIED — confirm by checking `?rgbif::gbif_version` in R). The correct approach is to query the GBIF API registry or inspect the `datasetKey` for the GBIF Backbone Taxonomy dataset (`d7dddbf4-2cf0-4f39-9b2a-bb099caae36c` — UNVERIFIED) and record its `modified` timestamp. Alternatively, the GBIF Backbone version is embedded in the `verbatimScientificName` match metadata returned by `rgbif::name_backbone()`. The pipeline must implement a concrete version-capture mechanism; the current strategy leaves this unresolved.  
**Risk:** Backbone version not captured → not reproducible.  
**Priority:** HIGH — fix before pipeline implementation.

**A-CRIT-2: Mammal Diversity Database (MDD) is missing from the backbone strategy.**  
The strategy recommends MSW3 as the authoritative mammal taxonomy, with a note about MSW4. However, the **Mammal Diversity Database (MDD)**, maintained by the American Society of Mammalogists (ASM), is now the primary living mammal taxonomy and has superseded both MSW3 and the informal MSW4 (Burgin et al. 2020) for active mammalian research (UNVERIFIED — confirm MDD's current status as ASM standard). MDD is versioned, regularly updated, has stable MDD IDs, and is accessible at mammaldiversity.org (UNVERIFIED — confirm API availability). Critically, PanTHERIA names are MSW3-anchored, but many research groups are now using MDD-anchored names. This creates a silent mismatch layer that is not addressed in the current strategy.  
**Risk:** Mammal backbone version mismatch between PanTHERIA (MSW3), MDD, and GBIF Backbone → synonym cascade errors.  
**Priority:** HIGH — add MDD evaluation before mammal backbone is finalized.

**A-CRIT-3: GBIF `usageKey` is not stable across backbone releases.**  
The strategy uses `gbif_usage_key` as the primary cross-group harmonization ID. GBIF `usageKey` values can change between backbone releases when GBIF re-ingests sources. This is documented GBIF behavior (UNVERIFIED — confirm in GBIF backbone release notes). The more stable within-GBIF identifier is `speciesKey`, but even `speciesKey` can change. The strategy must explicitly document: (1) what to do when a `usageKey` becomes invalid in a future backbone version, and (2) whether the pipeline stores the backbone version alongside the key to enable future remapping.  
**Risk:** Cross-group joins break silently if backbone is updated mid-project or at re-run.  
**Priority:** HIGH — must be addressed in schema design before pipeline runs.

**A-CRIT-4: Reptile Database has no stable versioned DOI for the full checklist.**  
The strategy correctly notes this but does not treat it as a blocker. For a publish-grade pipeline, "we downloaded on date X" is insufficient without a citable, stable dataset version. The Reptile Database periodically produces data releases but these are not consistently archived with DOIs (UNVERIFIED — check Reptile Database website for any archived releases). If no DOI is obtainable, the pipeline must: (1) snapshot the checklist locally at project start, (2) compute and store a SHA-256 hash of the downloaded file, (3) archive the snapshot in the project repository or an institutional repository with a DOI. Without this, the reptile taxonomic backbone is not reproducible.  
**Priority:** HIGH for publication readiness.

---

### Likely Issues

**A-LIKE-1: WoRMS (World Register of Marine Species) is absent from the taxonomy strategy.**  
For marine fish, marine mammals, marine invertebrates, and zooplankton — all of which will appear in FishBase, SeaLifeBase, and PANGAEA data — WoRMS AphiaIDs are the de facto standard marine taxonomic identifier. WoRMS is not mentioned in the taxonomy reconciliation strategy despite being the authoritative backbone for a large fraction of the species this pipeline will encounter. The `worrms` R package (UNVERIFIED on CRAN availability) provides API access. Marine species records should carry `worms_aphia_id` alongside `gbif_usage_key`. Without this, any downstream join to marine occurrence databases (OBIS, PANGAEA, SeaLifeBase) will lack a standard identifier bridge.  
**Priority:** MEDIUM-HIGH — add before marine species are ingested.

**A-LIKE-2: GBIF Backbone lags BirdLife annual releases by an uncertain margin.**  
The strategy acknowledges that GBIF Backbone lags BirdLife but does not quantify the lag or specify how to detect it. In practice, GBIF Backbone for birds may be 1–2 BirdLife annual versions behind (UNVERIFIED — confirm by comparing GBIF bird species count vs. current BirdLife checklist species count). AVONET was produced using BirdLife 2021 taxonomy (UNVERIFIED). If the pipeline uses GBIF Backbone as the cross-group harmonizer for birds while AVONET uses BirdLife 2021, species split/lumped differently between these versions will produce undetectable systematic errors. The pipeline needs an explicit version-reconciliation step for birds, checking AVONET taxonomy columns against the GBIF-matched name.  
**Priority:** MEDIUM.

**A-LIKE-3: Open Tree of Life (OTL) is not evaluated.**  
The Open Tree Taxonomy (OTT) synthesizes NCBI, GBIF, and multiple group-specific authorities into a cross-life-tree-aligned taxonomy. For GlobalBodySize, which will likely feed downstream phylogenetic comparative analyses, OTL tip labels and OTT IDs are highly relevant. The `rotl` R package (UNVERIFIED on CRAN status — likely still active) provides API access. OTL should be evaluated as a supplementary cross-group resolver and as the recommended phylogenetic anchor layer, particularly for analyses that use VertLife or TimeTree trees.  
**Priority:** MEDIUM — relevant for phylogenetic downstream use.

**A-LIKE-4: AmphibiaWeb vs. ASW conflict lacks a tie-breaking rule.**  
The strategy correctly identifies the AmphibiaWeb/ASW conflict for amphibians but does not provide a concrete rule for when they disagree on generic placement or species boundaries. This must be specified before amphibian data are ingested. Recommended rule: use ASW (Frost, AMNH) as the primary nomenclatural authority (it is the official ICZN-anchored authority), and treat AmphibiaWeb as a source of biological metadata but not as the name authority. Record the ASW version date.  
**Priority:** MEDIUM.

**A-LIKE-5: ITIS is mentioned but not formally evaluated.**  
The Integrated Taxonomic Information System (ITIS) is the official U.S. federal taxonomic standard and is especially relevant for VertNet specimen data, which often carries ITIS-era names. `taxize::get_tsn()` provides stable ITIS Taxonomic Serial Numbers. ITIS TSNs should be considered as an additional ID field for North American species, particularly for museum specimens. ITIS coverage of non-North-American taxa is weaker (UNVERIFIED — confirm ITIS global vs. North American coverage scope).  
**Priority:** LOW-MEDIUM.

---

### Backbone Validation Priority Ranking

| Backbone | Validation Urgency | Primary Risk |
|---|---|---|
| GBIF Backbone (cross-group) | **URGENT** | usageKey instability; missing version capture function |
| MDD (mammals) | **URGENT** | MSW3 anchor of PanTHERIA creates silent mismatch with current taxonomy |
| Reptile Database | **URGENT** | No DOI; reproducibility blocker |
| FishBase (rfishbase) | HIGH | Living database; version capture via rfishbase cache version |
| BirdLife (birds) | HIGH | Lag vs. GBIF Backbone creates version skew in AVONET joins |
| WCVP/POWO (plants) | MEDIUM | Static versioned releases available; version pinning needed |
| WoRMS (marine) | MEDIUM | Absent; needed before marine data ingested |
| AmphibiaWeb / ASW (amphibians) | MEDIUM | Conflict rule needed |
| CoL (insects) | MEDIUM | API coverage for insects is uneven |

---

## SECTION B — Darwin Core Compliance

### Missing Darwin Core Terms

The strategy's schema covers many DwC fields but is missing the following terms that are required or strongly recommended for Darwin Core compliance:

#### B1 — Missing Mandatory DwC Fields

| Missing DwC Term | DwC Class | Why Critical |
|---|---|---|
| `measurementID` | MeasurementOrFact | **Required** for MoF extension records; provides the unique identifier for each measurement row; without this, records are not individually citable or linkable |
| `basisOfRecord` | Occurrence | One of the most critical DwC required terms; must be one of: `PreservedSpecimen`, `HumanObservation`, `LivingSpecimen`, `MachineObservation`, `MaterialSample`, `Literature` — different for each source |
| `occurrenceID` | Occurrence | Required when measurement derives from a specimen occurrence (VertNet, museum records); links body mass to the occurrence record that produced it |

#### B2 — Missing Strongly Recommended DwC Fields

| Missing DwC Term | DwC Class | Recommendation |
|---|---|---|
| `kingdom` | Taxon | Explicit DwC Taxon class term; `input_taxonomic_group` is not a DwC field — map to DwC `kingdom` |
| `phylum` | Taxon | Required for unambiguous cross-kingdom identification; especially important for homonym detection |
| `class` | Taxon | Standard DwC higher taxonomy |
| `order` | Taxon | Standard DwC higher taxonomy |
| `family` | Taxon | Standard DwC higher taxonomy |
| `genus` | Taxon | Standard DwC higher taxonomy |
| `nameAccordingTo` | Taxon | The taxonomic authority (e.g., "GBIF Backbone v2024-01"); not the same as `matched_backbone` — this is a formal DwC field |
| `institutionCode` | Record | Required for museum specimen records from VertNet |
| `collectionCode` | Record | Required for museum specimen records from VertNet |
| `catalogNumber` | Record | Required for museum specimen records; enables deduplication across VertNet harvests |
| `measurementDeterminedDate` | MeasurementOrFact | Date measurement was taken; distinct from `query_timestamp_utc` which is the harvest date |
| `measurementAccuracy` | MeasurementOrFact | Quantified uncertainty (e.g., ±5 g or CV); optional but standard DwC-MoF term |
| `measurementRemarks` | MeasurementOrFact | Free-text notes specific to the measurement; standard DwC-MoF term |
| `bibliographicCitation` | Record | DwC term for the full citation; already in strategy as a concept but should be mapped to DwC term name explicitly |
| `datasetID` | Record | DwC term for DOI or stable dataset identifier; already in strategy but needs DwC mapping |

#### B3 — Schema Naming Mismatch

The strategy uses snake_case internal field names (e.g., `measurement_method`, `body_mass_included`) but Darwin Core terms are camelCase (e.g., `measurementMethod`, `basisOfRecord`). The pipeline must maintain an explicit mapping table from internal schema names to DwC terms. Without this, DwC compliance is claimed but not technically achieved.

**Recommended addition to schema:** A `dwc_term_mapping` reference table documenting the correspondence between every internal field name and its DwC equivalent (or `NULL` if no DwC equivalent exists).

---

## SECTION C — Body Mass Data Quality Checks

### C1 — Plausible Range Checks by Taxonomic Group

These ranges are broad safety guards for obviously wrong values. Records outside these ranges should be flagged for review, not auto-deleted.

> **IMPORTANT:** All range bounds below are UNVERIFIED — they are biologically motivated but must be confirmed against primary literature (Peters 1983; Calder 1984) before use as hard filters in code.

| Taxonomic Group | Minimum plausible (g) | Maximum plausible (g) | Notes |
|---|---|---|---|
| Mammalia | 0.001 | 200,000,000 | Min: Etruscan shrew (~2g actual; allow factor 1000 below); Max: blue whale (~150M g; allow headroom) |
| Aves | 1.0 | 200,000 | Min: bee hummingbird (~1.6g); Max: ostrich (~130,000 g) |
| Reptilia | 0.1 | 2,000,000 | Min: dwarf geckos; Max: saltwater crocodile |
| Amphibia | 0.01 | 10,000 | Min: Paedophryne (~0.1 g); Max: Goliath frog (~3,250 g); allow headroom |
| Actinopterygii / Chondrichthyes | 0.0001 | 50,000,000 | Min: smallest minnows; Max: whale shark (~34M g — UNVERIFIED) |
| Insecta | 0.00001 | 200 | Min: fairyflies/mymaridae; Max: Goliath beetles (~100 g — UNVERIFIED) |
| Arachnida | 0.0001 | 200 | Min: mites; Max: Goliath birdeater spider (~170 g — UNVERIFIED) |
| Plantae (height, m) | 0.005 | 130 | Min: some alpine cushion plants <1 cm; Max: Sequoia sempervirens ~115 m (UNVERIFIED) |
| Plantae (seed mass, mg) | 0.001 | 25,000,000 | Min: orchid seeds; Max: Lodoicea maldivica double coconut (UNVERIFIED) |

**Implementation rule:** Flag (`mass_range_flag = TRUE`) rather than delete. Store the flag alongside the record. Log the count of flagged records per source and per taxonomic group in a QA report file.

---

### C2 — Unit Consistency Checks

1. **Canonical unit:** All body mass values must be converted to **grams (g)** at ingest. Store original value and original unit alongside converted value.
2. **Conversion factors required:** g, kg (×1000), mg (÷1000), lbs (×453.592), oz (×28.3495), metric tonnes (×1,000,000).
3. **Unit parsing for VertNet:** VertNet mass fields are free text. Regex-based unit extraction is required. Known patterns: `"12.5 g"`, `"12.5g"`, `"125 g/ ~4.4 oz"`, `"0.012 kg"`. Any record where unit cannot be unambiguously parsed → `mass_unit_raw = "UNPARSEABLE"`, `mass_value_g = NA`, `requires_manual_review = TRUE`.
4. **FishBase LW units:** Confirm that rfishbase `length_weight()` returns `a` and `b` where W (g) = a × L (cm)^b. This is the standard FishBase convention but must be verified (UNVERIFIED — check rfishbase documentation). Different sources may use TL (total length), SL (standard length), or FL (fork length) as L — store `length_type` alongside parameters.
5. **Plant mass units:** TRY trait records mix mg, g, and kg, and some plant biomass values are per-unit-area (g/m²) rather than per-individual (g). These are not interchangeable. Require `mass_grain` field: `individual`, `per_m2`, `per_leaf`, `seed`.

---

### C3 — Outlier Detection Strategy

**Approach:** Hierarchical — apply in order; do not auto-delete at any stage.

**Step 1 — Within-group range check** (Section C1): Flag values outside the biological plausibility bounds.

**Step 2 — Within-species z-score check:**
- For species with ≥5 records: compute z-score of log10(mass) per species; flag records with |z| > 3.
- For species with 2–4 records: flag if any record differs from the median by >1 order of magnitude.
- For singleton species records: no within-species outlier check possible; cross-source check applies.

**Step 3 — Cross-source consistency check:**
- For species appearing in ≥2 sources: compute log10 ratio of values between sources.
- Flag pairs where |log10(mass_A / mass_B)| > 1 (i.e., values differ by more than 10×).
- A ratio of 10× between sources is biologically implausible for a single species mean unless mass_type differs (e.g., wet vs. dry).

**Step 4 — Within-genus rank check:**
- For species without within-species checks possible: verify that mass is within the 10th/90th percentile range of congeners in the same source.
- Flag species whose mass is an order of magnitude above or below all congeners.

**Step 5 — LW model validation for fish:**
- After computing mass from LW parameters, verify that computed mass is within the 1st/99th percentile of directly measured masses for the same family (if available from AnAge or VertNet).
- Flag species where LW-derived mass deviates by >2 orders of magnitude from family expectation.

---

### C4 — Cross-Source Duplicate Detection

**Define "duplicate":** Two records are potential duplicates if they share the same `accepted_name`, `source_dataset`, and `measurement_grain`. Within a single source, two species-mean records for the same accepted name are always duplicates.

**Cross-source duplicate detection** (different source, same accepted name):
- Not duplicates per se — multiple sources for the same species are expected and desired.
- However: if `input_name_verbatim` is identical across two different `source_dataset` entries and both have `measurement_grain = "literature_mean"`, investigate whether the two datasets share a common underlying literature source (this is common — e.g., PanTHERIA and EltonTraits both cite Wilson & Reeder for many mammal mass values).
- Implement `shared_source_risk_flag` for known overlapping source pairs:
  - PanTHERIA ↔ EltonTraits mammals: HIGH overlap
  - EltonTraits birds ↔ AVONET: MODERATE overlap
  - AnAge vertebrates ↔ PanTHERIA mammals: MODERATE overlap

**For individual-level records (VertNet):**
- Deduplication key: `institutionCode` + `collectionCode` + `catalogNumber`.
- Records with identical deduplication keys but different mass values indicate a data entry error or unit mismatch.

---

### C5 — Life Stage and Sex Flag Validation

**Controlled vocabularies (mandatory):**

`life_stage`: `adult`, `subadult`, `juvenile`, `larval`, `metamorph`, `neonate`, `egg`, `unknown`  
`sex`: `male`, `female`, `pooled`, `unknown`

**Validation rules:**
1. If `life_stage = "unknown"` and source is a published species-mean database (PanTHERIA, AVONET, EltonTraits), set `life_stage = "adult"` — these databases report adult means. **Document this imputation explicitly** in the field notes.
2. If `life_stage` and `sex` are both `"unknown"` AND `source_dataset = "VertNet"`, set `requires_manual_review = TRUE` — VertNet records without life stage or sex are potentially juvenile-contaminated.
3. For fish (FishBase LW-derived mass): `life_stage = "adult"` is only valid if the mass was computed at an adult reference length. Document the reference length used (e.g., L∞ × 0.95 — UNVERIFIED convention). If mass is computed at maximum reported length, set `life_stage = "adult_maximum"`.
4. For insects: `life_stage = "adult"` should be mandatory for body mass records; larval or pupal mass is a fundamentally different variable and must be stored separately.
5. If `sex` differs between records for the same species from the same source: do NOT average across sexes if dimorphism ratio for the taxonomic group typically exceeds 1.3× — store sex-specific means separately.

---

## SECTION D — GBIF MeasurementOrFact Assessment

### Agreement with Tier C Rating

**Yes — Tier C (supplemental only) is correct.** The reasoning is sound:

1. **Actual body mass coverage in GBIF MoF is sparse.** The MeasurementOrFact extension is structurally available in GBIF but has very low adoption for body mass specifically. Most GBIF occurrence records come from herbarium specimens, eBird observations, and citizen science platforms — none of which routinely include mass measurements. Based on available evidence (UNVERIFIED — no formal survey of GBIF MoF body mass coverage found), fewer than 1% of GBIF occurrence records contain any MeasurementOrFact extension data, and the fraction with `measurementType` = body mass is likely far smaller.

2. **`measurementType` values for body mass are not standardized in GBIF.** Publishers use: `"body mass"`, `"weight"`, `"live weight"`, `"wet weight"`, `"dry weight"`, `"mass"`, `"bodyMass"`, and many others. A systematic harvest requires fuzzy text matching against all of these variants, which introduces noise.

3. **More efficient query approach:** Rather than a full global occurrence download with MoF extension, query the GBIF dataset registry to identify specific datasets (by `datasetKey`) that are known to use the MoF extension AND contain mass-related measurements. Then download only those targeted datasets. This reduces data volume from hundreds of GB to manageable size.

### Known GBIF Datasets Likely to Contain Body Mass in MoF

The following are plausible candidates (all UNVERIFIED — must confirm by checking GBIF dataset pages):

| Dataset / Publisher | Likely measurementType | Rationale |
|---|---|---|
| PANGAEA datasets re-archived in GBIF | `"wet weight"`, `"body mass"`, `"dry weight"` | PANGAEA is marine-focused; many datasets include biomass measurements |
| Natural History Museum London (NHM) specimen datasets | `"mass"`, `"weight"` | NHM sometimes includes specimen mass in structured fields |
| NEON-integrated datasets on GBIF | `"body mass"` | NEON protocols include mass; some NEON datasets are deposited in GBIF (UNVERIFIED — confirm which NEON data products are in GBIF) |
| eBird | None | Occurrence only; no mass data |
| iNaturalist | None | Occurrence only; no mass data |
| Observation.org | Unknown | UNVERIFIED |

**Practical recommendation:** Use the GBIF dataset search API (`https://api.gbif.org/v1/dataset?type=OCCURRENCE&q=measurementorfact`) or the GBIF registry (UNVERIFIED on exact endpoint) to enumerate datasets that have submitted MoF extensions. Cross-reference against body-mass-related keyword search. This targeted approach is far more efficient than a blind global download.

---

## SECTION E — Missing Data Sources

### E1 — NEON (National Ecological Observatory Network) — SIGNIFICANT OMISSION

NEON is not in the inventory and represents a significant gap. NEON protocols include **structured, quality-controlled body mass measurements** for:

- **Small mammals:** Data product DP1.10072.001 — individual mass in grams measured at trap; sex, age class, and reproductive condition recorded per individual. This is individual-level mass data with explicit sex and life stage — rarer than species means and highly valuable.
- **Macroinvertebrates:** Biomass estimates (UNVERIFIED on whether individual mass vs. bulk biomass).
- **Ground beetles:** Body size metrics (UNVERIFIED on specifics).
- **Plant biomass:** Aboveground biomass measured at NEON plots.

**R access:** `neonUtilities` package (UNVERIFIED — confirm package name and CRAN status). NEON uses a DOI-per-data-product citation system.  
**Why this matters:** NEON provides individual-level, sex-and-stage-resolved mass data for North American mammals — exactly the intraspecific variation data that Tier A compiled databases lack. This should be Phase 2 priority.

---

### E2 — Mammal Diversity Database (MDD) — PRESENT IN AUDIT SECTION A; NOT IN INVENTORY

The MDD (mammaldiversity.org — UNVERIFIED) is not listed as a data source. While MDD is primarily a taxonomic backbone (addressed in Section A), it also contains body mass data for many mammal species as species attributes (UNVERIFIED — confirm MDD includes mass). If confirmed, MDD body mass would be a Tier B source providing an independent cross-check against PanTHERIA.

---

### E3 — WoRMS / OBIS (Marine Species) — SIGNIFICANT OMISSION

**WoRMS** (World Register of Marine Species): Not in the inventory or taxonomy strategy. For marine fish, marine mammals, marine invertebrates, and zooplankton, WoRMS AphiaIDs are the standard taxonomic identifiers used by OBIS, PANGAEA, and EMODnet. The `worrms` R package (UNVERIFIED on CRAN status) provides API access.

**OBIS** (Ocean Biodiversity Information System): Has occurrence data for marine organisms with extended measurement data for some groups including zooplankton body size (UNVERIFIED on extent of body size coverage). The `robis` R package (UNVERIFIED on CRAN status) provides access.

**Impact:** Without WoRMS integration, marine species records from FishBase, SeaLifeBase, and PANGAEA will lack a standard cross-linking identifier to marine occurrence databases. Add `worms_aphia_id` as a schema field for marine taxa.

---

### E4 — European Insect Biomass Data — PARTIALLY MISSING

The inventory covers insect body size generally but misses two specific European monitoring datasets:

1. **Krefeld Entomological Society long-term insect biomass data:** The Hallmann et al. (2017) study on insect biomass decline in Germany was based on 27 years of malaise trap data from the Krefeld Entomological Society (UNVERIFIED — confirm data availability on Dryad/Zenodo; the study is in *PLOS ONE*). If the raw trap biomass data are publicly archived, they represent bulk arthropod biomass time-series — distinct from individual species mass but relevant for community-level analyses.

2. **PREDICTS database (already in inventory, 1.20):** PREDICTS contains body mass as a species attribute for some taxa but this utility is underemphasized in the inventory's description. Confirm whether PREDICTS body mass values are sourced from PanTHERIA/EltonTraits (in which case they are redundant) or from independent curation.

3. **UK Rothamsted Insect Survey:** Long-term suction trap data for flying insects; bulk biomass estimates (UNVERIFIED on data availability and mass measurement specifics).

---

### E5 — SVL-to-Mass Allometric Conversion Equations for Herpetofauna

There is no single formal "SVL-to-mass database" — this is correct. However, the audit reveals a gap: the strategy does not specify **which published allometric equations will be used** to impute body mass from SVL in the amphibian and reptile pipelines.

Published resources that should be explicitly incorporated as imputation tools (UNVERIFIED — all citations require confirmation):

| Group | Source | Notes |
|---|---|---|
| Lizards | Meiri S. 2010. *Journal of Zoology* 281:218–226 | Family-level LW equations for lizards; UNVERIFIED on exact content |
| Squamates (lizards + snakes) | Feldman A, et al. 2016. *Global Ecology and Biogeography* | UNVERIFIED on DOI and exact equation scope |
| Snakes (Australian) | Shine et al. (multiple papers, UNVERIFIED) | Regional LW relationships for snakes |
| Amphibians (frogs) | Navas et al. (UNVERIFIED — confirm authorship, journal, year) | SVL-mass regression for anurans |
| Salamanders | Unreferenced in inventory — search required | UNVERIFIED |

**Recommended action:** Create a `HERPETOFAUNA_SVL_MASS_EQUATIONS.md` document that compiles verified SVL-to-mass regression parameters (intercept, slope, R², sample size, taxonomic scope, equation form) for each group. All imputed mass values derived from these equations must carry `measurement_method = "allometric_imputation"` and the source equation reference.

---

### E6 — FishLife (Thorson et al.) — Missing Fish Gap-Fill Tool

**FishLife** is a Bayesian life history trait prediction model for all fish species that uses phylogenetic imputation to estimate body size (including mass) for species with no direct observations (UNVERIFIED — confirm package name, availability, and exact traits predicted). This is directly relevant for FishBase gap-filling. R package may be available on GitHub (UNVERIFIED — search thorsonmiller/FishLife or similar). This should be flagged as a potential Tier C source for fish species with no direct LW parameters in FishBase.

---

### E7 — Assessment of Specifically Queried Sources

| Source | Relevant? | Assessment |
|---|---|---|
| ITIS taxonomy | YES — for taxonomy | ITIS TSNs are valuable for North American VertNet specimen linkage; not a body mass source but relevant as a name authority for `taxize` workflows; add `itis_tsn` as an optional schema field |
| Open Tree of Life | YES — for downstream phylogenetics | OTL OTT IDs are the standard for phylogenetically-anchored analyses; add `ott_id` as optional schema field; `rotl` R package (UNVERIFIED on CRAN status) |
| Marine invertebrate body mass (OBIS-linked) | PARTIALLY YES | OBIS has size data for some zooplankton groups; PANGAEA is better for structured body size; both are missing from inventory's marine coverage |
| European insect biomass monitoring | PARTIALLY YES | Krefeld data exists but availability uncertain; PREDICTS captures some European insect data |
| SVL-to-mass conversion database | NO dedicated database exists | Use published allometric equations — see E5 above |
| NEON body mass data | YES — significant | Small mammal mass at individual level; see E1 above |
| eBird body mass | NO | Occurrence platform only; no mass data |
| iNaturalist body mass | NO | Occurrence platform only; no mass data |

---

## SECTION F — Provenance Minimum Requirements

For the GlobalBodySize pipeline to be **publish-ready and citable**, every row in the compiled table must carry the following fields. These are non-negotiable minimums. Rows missing any of these fields are not publication-quality.

### F1 — Mandatory Row-Level Provenance Fields

| Field | DwC equivalent | Required value | Notes |
|---|---|---|---|
| `source_dataset` | `datasetName` | Non-null string | Name of contributing database (PanTHERIA, AVONET, rfishbase, AmphiBIO, TRY, etc.) |
| `source_dataset_version` | (no DwC equivalent) | Non-null string | Version or ISO date of dataset accessed; "unknown" is not acceptable |
| `source_record_id` | `occurrenceID` / `measurementID` | String or NA | Source-internal record identifier if provided; NULL permitted only if source has no record IDs |
| `input_name_verbatim` | `verbatimScientificName` | Non-null; immutable | Exact name string as it appears in raw source data; must never be modified after ingest |
| `accepted_name` | `acceptedNameUsage` | Non-null string | Backbone-resolved accepted species name |
| `accepted_taxon_id` | `taxonID` | Non-null string | Stable backbone-assigned identifier (e.g., GBIF `usageKey`, FishBase `SpecCode`) |
| `matched_backbone` | `nameAccordingTo` (partial) | Non-null controlled vocab | Which backbone resolved the name |
| `matched_backbone_version` | (no DwC equivalent) | Non-null string | Version or access date of backbone |
| `bibliographicCitation` | `bibliographicCitation` | Non-null string | Full citable reference for the source dataset (author, year, title, DOI if available) |
| `datasetID` | `datasetID` | Non-null string | DOI or stable URL of source dataset |
| `mass_value_g` | `measurementValue` | Numeric or NA | Body mass in grams (canonical unit); NA if mass not available for this record |
| `mass_unit_raw` | `measurementUnit` (source) | Non-null string | Unit as recorded in source (g, kg, mg, lbs, etc.); "unspecified" if not documented |
| `mass_type` | (no standard DwC equivalent) | Non-null controlled vocab | `wet`, `dry`, `fat_free`, `lean`, `ash_free_dry`, `LW_modeled`, `unspecified` |
| `measurement_method` | `measurementMethod` | Non-null controlled vocab | `direct_scale`, `LW_equation`, `literature_mean`, `allometric_imputation`, `text_mining`, `expert_estimate` |
| `life_stage` | `lifeStage` | Non-null controlled vocab | `adult`, `subadult`, `juvenile`, `larval`, `metamorph`, `neonate`, `egg`, `unknown` |
| `sex` | `sex` | Non-null controlled vocab | `male`, `female`, `pooled`, `unknown` |
| `measurement_grain` | (no standard DwC equivalent) | Non-null controlled vocab | `species_mean`, `population_mean`, `individual`, `derived_from_allometry` |
| `query_timestamp_utc` | (no standard DwC equivalent) | ISO 8601 UTC | Timestamp of data harvest from source |
| `reconciliation_pipeline_version` | (no standard DwC equivalent) | Non-null string | Version tag of reconciliation script that produced this row |
| `basisOfRecord` | `basisOfRecord` | Non-null controlled vocab | DwC required field: `PreservedSpecimen`, `HumanObservation`, `LivingSpecimen`, `Literature` |

### F2 — Conditional Mandatory Fields

| Field | Condition | Why mandatory when condition met |
|---|---|---|
| `worms_aphia_id` | Marine species | Cross-linking standard for marine occurrence databases |
| `fishbase_speccode` | Fish taxa | FishBase internal ID; required for LW parameter trace-back |
| `lw_param_a` | FishBase-derived mass | Required for mass reconstruction audit |
| `lw_param_b` | FishBase-derived mass | Required for mass reconstruction audit |
| `lw_reference_length_cm` | FishBase-derived mass | The body length at which mass was computed |
| `lw_length_type` | FishBase-derived mass | TL / SL / FL — required to interpret computed mass |
| `institutionCode` | VertNet / museum specimen records | DwC required for specimen records |
| `catalogNumber` | VertNet / museum specimen records | Required for deduplication |
| `mass_range_flag` | Any record | TRUE if value falls outside group plausibility range (Section C1) |
| `mass_outlier_flag` | Any record | TRUE if flagged by within-species outlier check (Section C3) |

---

## Summary: Critical Issues / Likely Issues / Assumptions Detected / Recommended Fixes / Validation Plan

---

### Critical Issues (must resolve before pipeline implementation)

| ID | Issue | Section | Immediate action |
|---|---|---|---|
| CRIT-1 | `rgbif::gbif_version()` does not exist — backbone version capture is unimplemented | A | Implement GBIF Backbone version capture via registry API before first backbone query |
| CRIT-2 | MDD (Mammal Diversity Database) missing from backbone strategy | A | Evaluate MDD as primary mammal backbone; assess MSW3-to-MDD synonym map |
| CRIT-3 | GBIF `usageKey` instability across backbone releases not mitigated | A | Store backbone version alongside every usageKey; document remapping protocol |
| CRIT-4 | Reptile Database has no DOI; no archiving plan | A | Snapshot checklist locally at project start; compute SHA-256 hash; deposit snapshot with DOI |
| CRIT-5 | `measurementID` missing from schema | B | Add `measurementID` as mandatory field; populate with UUID at ingest |
| CRIT-6 | `basisOfRecord` missing from schema | B | Add `basisOfRecord` as mandatory non-null field |
| CRIT-7 | Higher taxonomy DwC fields missing (kingdom, phylum, class, order, family, genus) | B | Add to schema; populate from backbone match |
| CRIT-8 | NEON small mammal mass data not in inventory | E | Add to Phase 2 harvest plan; evaluate neonUtilities package access |

---

### Likely Issues (address before first major publication from this pipeline)

| ID | Issue | Section |
|---|---|---|
| LIKE-1 | WoRMS AphiaID missing from schema and taxonomy strategy | A, E |
| LIKE-2 | GBIF Backbone lag vs. BirdLife creates AVONET version skew | A |
| LIKE-3 | Open Tree of Life not evaluated for phylogenetic downstream use | A |
| LIKE-4 | AmphibiaWeb vs. ASW conflict lacks tie-breaking rule | A |
| LIKE-5 | SVL-to-mass allometric equations not specified for amphibians/reptiles | E |
| LIKE-6 | Unit parsing strategy for VertNet free-text mass fields not specified | C |
| LIKE-7 | Cross-source duplicate detection between PanTHERIA and EltonTraits not planned | C |
| LIKE-8 | FishLife trait prediction model not evaluated as fish gap-fill | E |
| LIKE-9 | `measurementDeterminedDate` missing — harvest date ≠ measurement date | B |
| LIKE-10 | Plant mass grain ambiguity (per-individual vs. per-area vs. per-leaf) | C |

---

### Assumptions Detected

| ID | Assumption | Location | Risk if wrong |
|---|---|---|---|
| ASSM-1 | AVONET used BirdLife 2021 taxonomy | Taxonomy strategy S1.2 | AVONET-GBIF mismatch if wrong version assumed |
| ASSM-2 | rfishbase LW parameters use W(g) = a × L(cm)^b convention | Advisory Section 1.6 | Mass computed in wrong units if convention differs |
| ASSM-3 | PanTHERIA body mass values are adult wet mass | Advisory Section 1.1 | Mass type confounding if not verified per entry |
| ASSM-4 | >80% of records will be matchable across backbones | Advisory Assumption 4 | No fallback plan specified if match rate is lower |
| ASSM-5 | `taxize::get_amphibiaweb_()` exists as a function | Taxonomy strategy S1.5 | UNVERIFIED — taxize may not have this function |
| ASSM-6 | `taxize::get_fishbaseid_()` exists as a function | Taxonomy strategy S1.3 | UNVERIFIED — confirm function signature in taxize |
| ASSM-7 | `rsealifebase` is a CRAN package | Data inventory S1.08 | May not exist or may be unmaintained |
| ASSM-8 | NEON body mass data is not worth including | (implicit omission) | Significant individual-level data missed for North American mammals |

---

### Recommended Fixes (prioritized)

**Immediate (before pipeline implementation):**
1. Implement GBIF Backbone version capture. Query the GBIF registry for the Backbone Taxonomy dataset and extract the `modified` date at pipeline start. Store as `gbif_backbone_query_date` in pipeline metadata.
2. Add `measurementID` (UUID), `basisOfRecord`, `kingdom`, `phylum`, `class`, `order`, `family`, `genus` to schema.
3. Add `worms_aphia_id` as a conditional mandatory field for marine taxa.
4. Replace the `rgbif::gbif_version()` call in documentation with the correct implementation pattern.
5. Add NEON to the data source inventory as a Phase 2 target for individual-level mammal mass.
6. Snapshot and hash the Reptile Database checklist at project start; deposit with an institutional DOI.

**Before first harvest run:**
7. Specify which SVL-to-mass allometric equations will be used for amphibians and reptiles; document in a separate `HERPETOFAUNA_SVL_MASS_EQUATIONS.md`.
8. Evaluate and formally assess MDD as the mammal backbone; document the MSW3-MDD synonym overlap rate.
9. Add AmphibiaWeb vs. ASW tie-breaking rule to taxonomy strategy.
10. Create a DwC field mapping table (internal snake_case name → DwC camelCase term).

**Before publication:**
11. Evaluate FishLife for fish gap-fill; assess `worrms` and `robis` packages for marine integration.
12. Evaluate OTL (`rotl`) for phylogenetic anchor layer.
13. Run cross-source duplicate detection for PanTHERIA/EltonTraits mammal mass overlap; document overlap rate.

---

### Validation Plan

**Step 1 — Backbone version capture test:** Before any backbone query, confirm that the pipeline records backbone version information. Run a test query with `rgbif::name_backbone("Homo sapiens")` and verify that the backbone date is captured in pipeline metadata.

**Step 2 — Schema completeness check:** Create a test CSV with 10 synthetic records and verify that all mandatory fields (Section F1) are present and non-null. Use R's `stopifnot()` or `assertthat` to enforce field presence at pipeline build time.

**Step 3 — Range check calibration:** For each taxonomic group, run the range checks (Section C1) against a known-good dataset (PanTHERIA for mammals, AVONET for birds) before applying to unknown sources. Confirm that 0 records in the known-good dataset are flagged as out-of-range. If flags occur, adjust range bounds with justification.

**Step 4 — Unit harmonization validation:** For VertNet, manually inspect 50 randomly sampled mass field values and verify that the unit parser correctly extracts units and values from each. Target: ≥95% parse success rate. Document failure patterns.

**Step 5 — Cross-source consistency spot-check:** After ingesting PanTHERIA and AVONET mammals, compute log10 ratios for the ~5,400 species in both datasets. The distribution should be centered near 0 with SD < 0.1 (within 26%). Species with |log10 ratio| > 0.5 (>3× difference) should be manually investigated. Document the count.

**Step 6 — Darwin Core compliance test:** Export 100 randomly sampled rows in Darwin Core Archive format. Validate against the GBIF Darwin Core Archive validator (UNVERIFIED on current validator URL — check https://www.gbif.org/tools/data-validator) to confirm structural compliance.

**Step 7 — Provenance completeness audit:** Run `sum(is.na(compiled_table[, mandatory_fields]))` for all mandatory fields (Section F1). Target: zero NAs in mandatory fields. Document any sources that cannot supply mandatory fields and specify the fallback value (e.g., `mass_type = "unspecified"`).

---

*Audit complete. All items marked UNVERIFIED require independent validation before pipeline implementation or publication.*
