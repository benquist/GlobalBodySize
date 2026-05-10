# GlobalBodySize — Taxonomy Reconciliation Strategy

**Project:** GlobalBodySize — global multi-taxon body mass data integration  
**Document type:** Design and advisory document (not code implementation)  
**Author:** taxonomy-reconciliation specialist agent (GitHub Copilot, Claude Sonnet 4.6)  
**Date produced:** 2026-05-09  
**Provenance:** Produced in response to user design prompt. All package names, API endpoints, and function signatures marked UNVERIFIED where not independently confirmed.

> **NOTICE:** This is an advisory document, not a peer-reviewed synthesis. All backbone URLs, package names, function names, and record counts must be independently verified before use in production pipelines or publications. Items marked **UNVERIFIED** require manual confirmation.

---

## Section 1 — Backbone Strategy

### Overview principle

No single backbone covers all life with equal authority or stability. GlobalBodySize must therefore use **group-specific primary backbones** while maintaining a **cross-group harmonization layer** via GBIF Backbone or Catalogue of Life (CoL) to enable unified species IDs across animal and plant datasets.

All backbone versions and access dates must be recorded at query time. Backbone version pinning is mandatory for reproducibility.

---

### 1.1 Mammals

| Attribute | Recommendation |
|---|---|
| **Primary backbone** | **GBIF Backbone Taxonomy** (which incorporates MSW3 for mammals) |
| **Secondary backbone** | **MSW3** (Wilson & Reeder 2005) as authoritative mammal reference |
| **MSW4 note** | MSW4 (Illustrated Checklist of the Mammals of the World, Burgin et al. 2020) exists and revises ~1,000+ species concepts relative to MSW3 — UNVERIFIED whether GBIF Backbone has fully absorbed MSW4 at time of use. Check GBIF Backbone release notes. |
| **R package access** | `taxize::get_gbifid_()`, `taxize::get_uid()` (NCBI); `rgbif::name_backbone()` for GBIF match |
| **Known conflicts** | Rodent and bat taxonomy are highly unstable. Chiroptera in particular has large genus-level splits between MSW3 and more recent revisions. PanTHERIA is MSW3-anchored; newer GBIF records may reflect post-MSW3 splits. |
| **Version requirement** | Record GBIF Backbone doi and date at query time via `rgbif::gbif_version()` (UNVERIFIED — confirm function exists) |
| **Reproducibility note** | PanTHERIA names are MSW3 verbatim; map PanTHERIA names to GBIF Backbone IDs at ingest and preserve both |

---

### 1.2 Birds

| Attribute | Recommendation |
|---|---|
| **Primary backbone** | **BirdLife International Checklist** (used by AVONET; annually updated) |
| **Secondary backbone** | **eBird/Clements** for North American-focused sources; **BirdTree/Jetz** taxonomy for phylogenetic tree alignment |
| **GBIF Backbone note** | GBIF Backbone incorporates BirdLife taxonomy for birds but lags behind BirdLife annual releases. Record which BirdLife version year is targeted. |
| **R package access** | `taxize::get_gbifid_()`, `ritis::` (ITIS access) — UNVERIFIED; `auk` package (UNVERIFIED) provides eBird taxonomy reference |
| **Known conflicts** | AVONET ships three parallel taxonomy columns (BirdLife, eBird, BirdTree). EltonTraits and AVONET use different taxonomies for lumped/split species. Jetz BirdTree tips do not always match BirdLife accepted names 1:1 — phylogenetic mismatch is a documented problem in avian comparative analyses. |
| **Version requirement** | BirdLife checklist year must be pinned. AVONET was released with BirdLife 2021 taxonomy (UNVERIFIED — confirm). |
| **Reproducibility note** | Store all three AVONET taxonomy columns (BirdLife, eBird, BirdTree) in the reconciliation table for downstream phylogenetic flexibility |

---

### 1.3 Fish

| Attribute | Recommendation |
|---|---|
| **Primary backbone** | **FishBase taxonomy** (via rfishbase) — most complete fish species list for body size purposes |
| **Secondary backbone** | **GBIF Backbone** / **Catalogue of Life (CoL)** for cross-group harmonization |
| **R package access** | `rfishbase::` — CRAN-available, wraps FishBase API; `taxize::get_fishbaseid_()` — UNVERIFIED whether this function exists |
| **Known conflicts** | FishBase sometimes disagrees with CoL on accepted names, especially for recently revised families (e.g., Perciformes sensu lato, which CoL has extensively reclassified). FishBase name ≠ GBIF accepted name is common. Always store FishBase accepted name separately from GBIF accepted name. |
| **Version requirement** | FishBase releases new versions periodically. Record `rfishbase` version and FishBase data snapshot date. |
| **Reproducibility note** | FishBase is a living database with no versioned static release — this is a known reproducibility risk. Consider caching queried results locally with timestamp. |

---

### 1.4 Reptiles

| Attribute | Recommendation |
|---|---|
| **Primary backbone** | **The Reptile Database** (reptile-database.org) — most authoritative reptile-specific checklist |
| **Secondary backbone** | **GBIF Backbone** for cross-group ID alignment |
| **IUCN note** | IUCN taxonomy for reptiles is updated irregularly and lags Reptile Database splits/lumps; use IUCN only for conservation status, not as name authority |
| **R package access** | No dedicated R package wraps The Reptile Database directly — UNVERIFIED. `taxize::` may support ITIS for some reptile groups. `rredlist::` (UNVERIFIED) for IUCN IDs. Manual download or web scraping of Reptile Database likely required. |
| **Known conflicts** | Squamate (lizard and snake) taxonomy has undergone dramatic reclassification since 2010. Many GBIF Backbone reptile records lag Pyron/Uetz revisions. Expect high synonym rates from older sources (e.g., datasets citing Uetz 2012 vs. Uetz 2023). |
| **Version requirement** | Record Reptile Database version year; download static checklist if possible for pipeline reproducibility |
| **Reproducibility note** | Reptile Database does not provide stable versioned DOIs for the full checklist — UNVERIFIED. This is a reproducibility risk; snapshot locally. |

---

### 1.5 Amphibians

| Attribute | Recommendation |
|---|---|
| **Primary backbone** | **AmphibiaWeb** (amphibiaweb.org) — preferred for richest biological metadata |
| **Secondary backbone** | **Amphibian Species of the World (ASW)** (Frost, American Museum of Natural History) — preferred for strict nomenclatural authority |
| **Conflict between AmphibiaWeb and ASW** | These two authorities frequently disagree on generic placement and species boundaries, especially for frogs. Explicitly choose one as primary; record the other for cross-checking. |
| **R package access** | No dedicated CRAN R package for AmphibiaWeb or ASW as of 2024 — UNVERIFIED. `taxize::get_amphibiaweb_()` — UNVERIFIED. `taxize` has limited amphibian-specific support; GBIF Backbone via `rgbif` is the practical fallback. |
| **Known conflicts** | Plethodontid salamanders, dendrobatid frogs, and caecilians have frequent taxon concept instability. AmphiBIO dataset uses its own internal taxonomy that may not align with either ASW or AmphibiaWeb. |
| **Version requirement** | AmphibiaWeb and ASW are living databases. Record access date and ideally download a static species list at project start. |

---

### 1.6 Insects

| Attribute | Recommendation |
|---|---|
| **Primary backbone** | **GBIF Backbone Taxonomy** — pragmatic choice given no single authoritative insect checklist covers all orders |
| **Secondary backbone** | **Catalogue of Life (CoL)** checklist for specific well-covered orders (Lepidoptera, Coleoptera, Hymenoptera, Diptera) |
| **ION note** | Index of Organism Names (ION) — UNVERIFIED whether API access is current and free |
| **R package access** | `taxize::get_gbifid_()`, `taxize::get_colid_()` — UNVERIFIED function signatures; `rgbif::name_backbone()` |
| **Known conflicts** | Insect taxonomy is the most taxonomically unstable group in this project. Species-level records for most insect orders are poorly curated in global aggregators. Expect very high unresolved/ambiguous rates for insect body mass records. Body mass data for insects typically comes at family or genus level rather than species level — schema must support genus-level records explicitly. |
| **Version requirement** | GBIF Backbone and CoL release dates must be recorded |
| **Reproducibility note** | Insect body mass datasets (e.g., InsectBodySize, PREDICTS) may use internal taxonomies with no backbone mapping. Manual curation effort should be budgeted for insects. |

---

### 1.7 Plants

| Attribute | Recommendation |
|---|---|
| **Primary backbone** | **WCVP/POWO** (World Checklist of Vascular Plants / Plants of the World Online) — most current and authoritative vascular plant checklist with stable IPNI IDs |
| **Secondary backbone** | **GBIF Backbone** for cross-group harmonization |
| **TPL note** | The Plant List (TPL) is static as of 2013 and should not be used as primary backbone — it is superseded by WCVP/POWO |
| **R package access** | `TNRS` package — UNVERIFIED availability; `taxize::get_pow_()` — UNVERIFIED; `rgbif::name_backbone()`; `WorldFlora` package wraps World Flora Online — UNVERIFIED CRAN availability; `POWO` API accessible via `kewr` package — UNVERIFIED |
| **Known conflicts** | TRY database uses a mix of accepted and synonym names and does not align with a single backbone version. TPL-era names in older datasets will frequently be synonyms under WCVP. Genus-level body mass proxies for plants (e.g., stem-specific density from wood density databases) require genus-level backbone matching. |
| **Version requirement** | WCVP releases versioned datasets via Kew; record version number |
| **Reproducibility note** | POWO is a living database but WCVP releases periodic static downloads — prefer versioned WCVP static download for reproducibility |

---

### 1.8 Cross-Group Harmonization: Super-Backbone Decision

**Recommendation: use GBIF Backbone as the cross-group unifying layer, with CoL as supplementary audit.**

**Rationale:**
- GBIF Backbone assigns numeric `usageKey` IDs that are stable within a release and cover all kingdoms.
- `rgbif::name_backbone()` is the most reliable single API call available across all taxonomic groups in R.
- CoL provides a curated, annually-versioned checklist useful for audit but has lower API accessibility from R as of 2024.
- Neither GBIF Backbone nor CoL should be treated as the authoritative backbone for within-group matching; they serve only as the cross-group ID bridge.

**Practical implementation:**
- Each species record in the compiled GlobalBodySize table carries both a group-specific backbone ID (e.g., `fishbase_id`, `amphibiaweb_id`) AND a `gbif_usage_key` for cross-group queries.
- Cross-group joins and deduplication use `gbif_usage_key`.

---

## Section 2 — Reconciliation Table Schema

The following columns are mandatory for every row in the GlobalBodySize taxonomy reconciliation table. This extends the standard taxonomy-reconciliation agent output schema with fields specific to a multi-group body mass context.

### 2.1 Input provenance fields

| Column | Type | Controlled vocabulary / notes |
|---|---|---|
| `source_dataset` | character | Name of source database (e.g., `PanTHERIA`, `AVONET`, `rfishbase`, `AmphiBIO`, `TRY`). Required; no nulls. |
| `source_dataset_version` | character | Version or date of source dataset accessed. Required for reproducibility. |
| `source_taxon_id` | character | Internal taxon ID in the source dataset (e.g., PanTHERIA uses MSW3 species ID). NULL if source provides none. |
| `input_name_verbatim` | character | Exact species name string as it appears in the raw source data. NEVER modify this field after ingest. |
| `input_name_normalized` | character | Whitespace-normalized, Unicode-normalized canonical binomial without authorship. |
| `input_rank` | character | Rank of the input name: `species`, `subspecies`, `genus`, `family`, `higher`. |
| `input_authorship` | character | Authorship string as provided by source, if present. NULL if absent. |
| `input_taxonomic_group` | character | One of: `Mammalia`, `Aves`, `Actinopterygii`, `Chondrichthyes`, `Reptilia`, `Amphibia`, `Insecta`, `Arachnida`, `Plantae`, `other`. Required for backbone routing. |

**Why these matter for body mass databases specifically:** Body mass values often aggregate measurements across subspecies or broad taxonomic concepts. Recording input rank explicitly prevents silent inflation of species-level body mass estimates from subspecies-level measurements.

---

### 2.2 Backbone match fields

| Column | Type | Controlled vocabulary / notes |
|---|---|---|
| `matched_backbone` | character | Backbone used for this match: `GBIF`, `FishBase`, `BirdLife`, `AmphibiaWeb`, `ASW`, `ReptileDatabase`, `WCVP`, `CoL`, `MSW3`, `manual`. |
| `matched_backbone_version` | character | Version or release date of backbone at query time. |
| `matched_name` | character | Name string returned by backbone as matched entry. |
| `matched_authorship` | character | Authorship string returned by backbone for matched entry. |
| `matched_rank` | character | Rank of the matched entry. |
| `matched_taxon_id` | character | Stable ID in the matched backbone (e.g., GBIF `usageKey`, FishBase `SpecCode`). |
| `matched_status` | character | One of: `accepted`, `synonym`, `unresolved`, `ambiguous`, `no_match`. |
| `accepted_name` | character | Accepted name in the matched backbone. NULL if `matched_status = no_match`. |
| `accepted_taxon_id` | character | Accepted ID in the matched backbone. NULL if unresolved. |
| `gbif_usage_key` | integer | GBIF Backbone `usageKey` for the accepted concept — the cross-group harmonization ID. NULL if GBIF match failed. |
| `gbif_match_confidence` | integer | GBIF `confidence` score (0–100) returned by `name_backbone()`. NULL if not queried. |
| `synonym_type` | character | If `matched_status = synonym`: `homotypic`, `heterotypic`, `ambiguous_synonym`, `misapplied`, `unknown`. NULL otherwise. |
| `match_method` | character | One of: `exact_canonical_authorship`, `exact_canonical`, `synonym_remap`, `fuzzy`, `manual`, `genus_only`, `no_match`. |
| `match_confidence` | numeric | Normalized 0–1 confidence score. For GBIF matches, divide `gbif_match_confidence` by 100. For manual matches, assign 1.0. For fuzzy matches, record string similarity score. |
| `fuzzy_distance` | integer | Edit distance or string distance metric if `match_method = fuzzy`. NULL otherwise. |

---

### 2.3 Conflict and audit fields

| Column | Type | Controlled vocabulary / notes |
|---|---|---|
| `decision_note` | character | Free text explanation of any non-trivial match decision. Required when `match_method` is not `exact_canonical_authorship`. |
| `homonym_flag` | logical | TRUE if the input name is a known homonym (same name exists in another kingdom or phylum). |
| `cross_group_collision_flag` | logical | TRUE if `gbif_usage_key` is shared with a record from a different `input_taxonomic_group` — indicates likely homonym or pipeline error. |
| `subspecies_aggregation_flag` | logical | TRUE if input name is a subspecies that was remapped to a species-level accepted name. Body mass aggregation logic must account for this. |
| `genus_only_flag` | logical | TRUE if `input_rank = genus` and body mass record cannot be assigned to species level. |
| `requires_manual_review` | logical | TRUE if the record should be routed to human expert review before inclusion in final table. |
| `manual_review_reason` | character | Controlled reason code: `homonym`, `fuzzy_below_threshold`, `rank_mismatch`, `backbone_conflict`, `ambiguous_synonym`, `cross_group_collision`, `expert_disagreement`. NULL if not flagged. |

---

### 2.4 Temporal and provenance fields

| Column | Type | Controlled vocabulary / notes |
|---|---|---|
| `query_timestamp_utc` | character | ISO 8601 UTC timestamp of backbone query. Required. |
| `reconciliation_pipeline_version` | character | Version tag of the GlobalBodySize reconciliation script used to generate this row. |
| `reconciled_by` | character | One of: `automated`, `manual`, `semi_automated`. |

---

### 2.5 Body mass linkage fields

These fields link the taxonomy record to the body mass data and are populated after reconciliation:

| Column | Type | Notes |
|---|---|---|
| `body_mass_included` | logical | TRUE if at least one body mass value was successfully linked to this reconciled accepted name. |
| `body_mass_source_count` | integer | Number of distinct source datasets contributing body mass values to this accepted name. |
| `body_mass_n_records` | integer | Total number of individual body mass records linked. |

---

## Section 3 — Name Conflict Rules

### 3.1 Synonym handling

**Rule S1 — Synonyms must be remapped, not discarded.**
When a source database provides a name that the target backbone treats as a synonym of an accepted name, the synonym must be remapped to the accepted name. The original synonym name is preserved in `input_name_verbatim`. Both the synonym ID (if available) and the accepted ID must be stored.

**Rule S2 — Synonym type must be classified.**
Distinguish homotypic (nomenclatural; same type specimen, different circumscription) from heterotypic (taxonomic; different type specimens merged) synonyms where possible. Homotypic synonyms are generally safe remaps; heterotypic synonyms carry biological uncertainty and should trigger a decision note.

**Rule S3 — Misapplied names require special handling.**
If a backbone marks a name as `misapplied` (i.e., the name was used erroneously for a different taxon), do NOT remap to the accepted name automatically. Set `matched_status = ambiguous`, `requires_manual_review = TRUE`, `manual_review_reason = ambiguous_synonym`.

**Rule S4 — Record both pre- and post-remap body mass linkages.**
Body mass values from source datasets are linked to `input_name_verbatim` at ingest. After reconciliation, they must be linked to `accepted_name`. If multiple input synonyms remap to the same accepted name, body mass records must be explicitly aggregated with source tracking — do not silently average across synonym sources.

---

### 3.2 Homonym handling

**Rule H1 — Detect cross-kingdom and cross-phylum homonyms at ingest.**
A homonym is a name applied to different organisms. In a multi-group project spanning plants and animals, cross-kingdom homonyms are a real risk. Example: genus names shared between plants and animals are common. Query GBIF Backbone for all `usageKey` matches across kingdoms when `input_name_normalized` returns multiple results.

**Rule H2 — Use `input_taxonomic_group` as the primary disambiguation signal.**
Do not rely on the name alone to determine the correct match. Always filter backbone results by kingdom or phylum using `input_taxonomic_group`. Record the kingdom of the matched entry.

**Rule H3 — Flag, never silently resolve.**
If a homonym cannot be unambiguously resolved using `input_taxonomic_group`, set `matched_status = ambiguous`, `homonym_flag = TRUE`, `requires_manual_review = TRUE`. Never force a match.

**Rule H4 — Cross-group collision detection.**
After all records are reconciled, run a group-level collision check: identify any `gbif_usage_key` values that appear in more than one `input_taxonomic_group`. These are either true homonyms or pipeline errors. Set `cross_group_collision_flag = TRUE` on all affected rows and route to manual review.

---

### 3.3 Ambiguous records

**Rule A1 — Genus-only records are valid and must be preserved.**
Many insect body mass records are at genus or family level. Do not discard these. Set `input_rank = genus`, `genus_only_flag = TRUE`, link body mass values to genus-level taxon IDs, and exclude from species-level analyses unless explicitly aggregated.

**Rule A2 — cf. and aff. qualifiers must be stripped and flagged.**
Remove cf., aff., nr., and similar qualifiers from the normalized name before matching. Store the verbatim name with qualifier in `input_name_verbatim`. Set `decision_note` to record qualifier presence.

**Rule A3 — sp., spp., and sp. nov. are unresolvable at species level.**
Set `matched_status = unresolved`, `requires_manual_review = FALSE` (these are legitimately unresolvable). Include in count of unresolved records but do not route to human queue unless project scope requires it.

**Rule A4 — Subspecies and variety records.**
If a body mass record is linked to a subspecies name, attempt to map to the parent species via the backbone. Set `subspecies_aggregation_flag = TRUE`. Record both subspecies and species IDs. Do not aggregate body mass values across subspecies without explicit analytical justification.

---

### 3.4 Fish-specific name conflict rules

**Rule F1 — FishBase accepted name is not necessarily GBIF accepted name.**
Always store both `fishbase_accepted_name` (from `rfishbase`) and `gbif_accepted_name` (from `rgbif::name_backbone()`). Use FishBase as the within-fish authoritative name; use GBIF as the cross-group bridge.

**Rule F2 — Family-level reclassification in Perciformes.**
The order Perciformes has been extensively reclassified under recent phylogenetic frameworks (e.g., Betancur et al.). FishBase and GBIF may place the same species in different orders or families. Record `input_order` and `matched_order` separately and flag discrepancies.

**Rule F3 — Freshwater vs. marine species duplication.**
Some species occur in both freshwater and marine literature with slightly different names or subspecies concepts. Check for name duplicates within FishBase results that differ only in ecological context metadata.

**Rule F4 — FishBase has no stable versioned static release.**
Cache all `rfishbase` query results locally with a timestamp. Never re-query without versioning the cache. This is a mandatory reproducibility requirement for FishBase-sourced data.

---

### 3.5 Cross-group duplicate name detection

Run the following cross-group checks after reconciliation is complete:

1. **GBIF key collision check:** any `gbif_usage_key` appearing in more than one `input_taxonomic_group` → set `cross_group_collision_flag = TRUE`.
2. **Verbatim name collision check:** any `input_name_verbatim` string appearing in more than one `input_taxonomic_group` → log to a homonym candidate table for expert review.
3. **Accepted name collision check:** any `accepted_name` appearing in both plant and animal records → automatic `homonym_flag = TRUE`.
4. **Report:** generate a `cross_group_collision_report.csv` as part of QA output. This is mandatory before any cross-taxa comparative analysis.

---

## Section 4 — Reconciliation Workflow Steps

This workflow is designed for implementation in R using `taxize`, `rgbif`, `rfishbase`, and related packages.

---

### Step 1 — Ingest and standardize raw source data

```
For each source dataset:
  1a. Load raw data and assign source_dataset and source_dataset_version.
  1b. Extract species name column(s), source taxon ID column, and body mass column(s).
  1c. Assign input_taxonomic_group based on source dataset (e.g., all PanTHERIA records → Mammalia).
  1d. Store input_name_verbatim exactly as found.
  1e. Normalize input_name_normalized: trim whitespace, remove double spaces,
      standardize Unicode, strip cf./aff. qualifiers (record in decision_note),
      extract genus + specific epithet only (drop authorship from normalized name).
  1f. Infer input_rank from name structure (two-part binomial → species; one word → genus; etc.).
  1g. Write ingest table with all input fields. Row count must match raw source exactly.
```

---

### Step 2 — Route to group-specific backbone

```
For each input_taxonomic_group, apply the designated primary backbone:
  Mammalia    → GBIF Backbone (rgbif::name_backbone)
  Aves        → GBIF Backbone + BirdLife taxonomy column from AVONET if source = AVONET
  Actinopterygii / fish → rfishbase::validate_names() then rgbif::name_backbone()
  Reptilia    → GBIF Backbone (Reptile Database has no R API; manual download required)
  Amphibia    → GBIF Backbone (taxize amphibiaweb support if available — UNVERIFIED)
  Insecta     → GBIF Backbone
  Plantae     → rgbif::name_backbone() + WCVP if available
```

---

### Step 3 — Execute backbone queries with rate limiting

```
  3a. Batch names in chunks of ≤250 to avoid API timeouts (UNVERIFIED — confirm GBIF API limit).
  3b. For each query result, extract: matched_name, matched_authorship, matched_rank,
      matched_taxon_id, matched_status, accepted_name, accepted_taxon_id, gbif_usage_key,
      gbif_match_confidence.
  3c. Record query_timestamp_utc for every batch.
  3d. Cache all raw API responses to disk (RDS or JSON) before parsing.
      Cache files must be named with backbone + date + batch index.
  3e. For rfishbase calls, cache results locally immediately.
```

---

### Step 4 — Apply match method classification

```
For each returned match, classify match_method:
  - gbif_match_confidence = 100 AND matched_status = accepted → exact_canonical_authorship
  - gbif_match_confidence ≥ 95 AND matched_status = accepted → exact_canonical
  - matched_status = synonym → synonym_remap (remap to accepted, record synonym_type)
  - gbif_match_confidence 75–94 → fuzzy (record fuzzy_distance, flag for review)
  - gbif_match_confidence < 75 → no_match OR manual
  - GBIF returns multiple matches → ambiguous (requires_manual_review = TRUE)
```

**Threshold note:** The 75% and 95% thresholds above are starting recommendations. Calibrate against a validation set of known names before using in production. Document threshold choices explicitly in pipeline metadata.

---

### Step 5 — Apply name conflict rules

```
  5a. Run synonym handling rules S1–S4.
  5b. Run homonym detection rules H1–H4:
      - For any name returning GBIF matches in multiple kingdoms, apply H2 (filter by kingdom).
      - If ambiguous after filtering, apply H3 (flag for manual review).
  5c. Apply ambiguous record rules A1–A4.
  5d. Apply fish-specific rules F1–F4 for Actinopterygii records.
```

---

### Step 6 — Manual review pass

```
  6a. Extract all rows where requires_manual_review = TRUE.
  6b. Group by manual_review_reason for efficient expert triage.
  6c. Expert decisions are recorded in decision_note with reconciled_by = manual.
  6d. Re-run Step 5 logic on manually resolved records to update flags.
  6e. Any record not resolved by manual review remains in the reconciliation table
      with matched_status = unresolved and is excluded from final body mass table.
```

---

### Step 7 — Cross-group harmonization

```
  7a. Join all group-specific reconciliation tables on gbif_usage_key.
  7b. Run cross-group duplicate name detection (Section 3.5 checks 1–4).
  7c. Generate cross_group_collision_report.csv.
  7d. Assign a project-internal unique ID (gbsz_id) to each accepted concept:
      gbsz_id format: GBSZ_<gbif_usage_key> for matched records;
                      GBSZ_MANUAL_<sequential_int> for manually curated unmatched records.
```

---

### Step 8 — Link body mass values to reconciled names

```
  8a. Join body mass records from each source to reconciliation table via
      (source_dataset, input_name_verbatim) → accepted_taxon_id → gbsz_id.
  8b. Preserve source_dataset column in body mass linkage table.
  8c. Calculate body_mass_source_count and body_mass_n_records per gbsz_id.
  8d. Flag records where body_mass_included = FALSE (reconciled name has no body mass).
  8e. Flag records where body_mass_source_count > 1 (cross-source integration records).
```

---

### Step 9 — Generate reconciliation diagnostics report

At the end of every reconciliation run, generate `reconciliation_diagnostics_report.csv` containing:

- Total input names per source dataset
- Match rate (% exact_canonical_authorship)
- Synonym remap rate (% synonym_remap)
- Fuzzy match rate
- Unresolved rate
- Ambiguous rate
- Homonym flag count
- Cross-group collision count
- Manual review queue size
- Backbone version and query date

This report must be archived alongside the reconciliation output.

---

## Section 5 — Quality Gates

No body mass record from any source may be marked as `reconciled = TRUE` and included in the final compiled table unless ALL of the following gates pass:

### Gate Q1 — Match method gate
`match_method` must be one of: `exact_canonical_authorship`, `exact_canonical`, `synonym_remap`, or `manual`.
Records with `match_method = fuzzy` or `no_match` are excluded unless manually resolved.

### Gate Q2 — Status gate
`matched_status` must be `accepted`. Records with `matched_status = synonym` must have completed synonym remap to an accepted name (i.e., `accepted_name` is not NULL). Records with `matched_status = unresolved` or `ambiguous` are excluded from final table.

### Gate Q3 — Cross-group collision gate
`cross_group_collision_flag` must be FALSE. Any record with a confirmed cross-group collision is excluded pending manual resolution.

### Gate Q4 — Rank gate
`matched_rank` must be `species` or `subspecies` for species-level body mass analyses. Genus-only records (`genus_only_flag = TRUE`) are excluded from species-level analyses but retained in the reconciliation table for genus-level analyses.

### Gate Q5 — Backbone ID gate
`accepted_taxon_id` must not be NULL. `gbif_usage_key` must not be NULL for cross-group analyses (may be NULL for group-specific analyses only).

### Gate Q6 — Source provenance gate
`source_dataset`, `source_dataset_version`, and `query_timestamp_utc` must all be non-NULL.

### Gate Q7 — Pipeline version gate
`reconciliation_pipeline_version` must not be NULL. This prevents mixing records reconciled under different pipeline versions without explicit version tracking.

### Gate Q8 — Minimum match rate threshold
The overall exact-match rate (exact_canonical_authorship + exact_canonical) per source dataset must be ≥ 70% before that dataset is considered adequately reconciled. Datasets below 70% match rate require a manual audit of the unmatched fraction before inclusion.

**Note:** The 70% threshold is a starting recommendation. Calibrate against known-quality sources (e.g., PanTHERIA, AVONET) before applying to lower-quality datasets. Document threshold choices in project metadata.

### Gate Q9 — No-homonym gate (for cross-group analyses only)
For any analysis combining records across taxonomic groups, the cross-group collision report must show zero unresolved cross-group collisions. Analyses must not proceed with unresolved cross-group homonyms.

---

## Section 6 — Key R Packages for Reconciliation

### 6.1 Core reconciliation packages

| Package | CRAN | Primary use | Known limitations |
|---|---|---|---|
| `taxize` | Yes | Multi-backbone taxon lookup, synonym resolution, name parsing, GBIF/ITIS/NCBI/CoL/WoRMS queries | API rate limits require batching; some backbone-specific functions may be deprecated or renamed — UNVERIFIED current function signatures; ITIS can be slow |
| `rgbif` | Yes | GBIF Backbone name matching via `name_backbone()`, batch species lookup, GBIF occurrence download | GBIF Backbone lags some group-specific backbones; `name_backbone()` returns single best match, not all matches — confirm behavior for homonyms — UNVERIFIED |
| `rfishbase` | Yes | FishBase species list, body size data, taxonomic validation for fish | FishBase has no static versioned release; queries are live; cache required for reproducibility; API may change — UNVERIFIED current API stability |
| `rredlist` | Yes | IUCN Red List taxonomy and conservation status — useful for reptile/amphibian IDs | IUCN API key required; IUCN taxonomy lags group-specific authorities; do not use as primary backbone |

---

### 6.2 Plant-specific packages

| Package | CRAN | Primary use | Known limitations |
|---|---|---|---|
| `WorldFlora` | UNVERIFIED — confirm CRAN status | World Flora Online name matching and synonym resolution for plants | May require local download of WFO checklist file; UNVERIFIED current status |
| `TNRS` | UNVERIFIED — confirm CRAN status | Taxonomic Name Resolution Service — plant name harmonization | External API dependency; UNVERIFIED whether API is still actively maintained |
| `kewr` | UNVERIFIED — confirm CRAN status | Kew API access including POWO/WCVP plant taxonomy | Experimental package; UNVERIFIED stability |

---

### 6.3 Utility packages

| Package | CRAN | Primary use | Known limitations |
|---|---|---|---|
| `stringdist` | Yes | Fuzzy string matching for name normalization and distance calculation | Does not understand taxonomic conventions; purely string-level |
| `data.table` | Yes | Fast in-memory joins for large reconciliation tables | |
| `dplyr` | Yes | Tidy data manipulation for reconciliation pipeline | |
| `readr` | Yes | Consistent CSV/TSV ingest with type inference | |
| `jsonlite` | Yes | Parsing and caching API responses as JSON | |
| `httr` | Yes | Direct HTTP calls to backbone APIs where R packages are unavailable | Requires manual rate-limit management |
| `lubridate` | Yes | UTC timestamp generation and formatting | |

---

### 6.4 Packages requiring verification before use

The following packages were referenced in background research but require independent verification of CRAN availability, current API compatibility, and function signatures before inclusion in the production pipeline:

- `auk` — eBird data access; UNVERIFIED whether it provides a taxonomy reference object
- `taxize::get_amphibiaweb_()` — UNVERIFIED function name and availability
- `taxize::get_pow_()` — UNVERIFIED function name (POWO access via taxize)
- `taxize::get_fishbaseid_()` — UNVERIFIED function name
- `rgbif::gbif_version()` — UNVERIFIED function name for retrieving backbone release
- `kewr` — UNVERIFIED CRAN availability
- `TNRS` — UNVERIFIED CRAN availability and API status
- `WorldFlora` — UNVERIFIED CRAN availability

**Action required:** Before pipeline implementation, run `available.packages()` in R to confirm each package is on CRAN and check package documentation for current function signatures.

---

## Appendix A — Backbone Version Pinning Template

Every reconciliation run must produce a `backbone_versions.csv` with the following structure:

```
backbone_name, backbone_version_or_date, access_date_utc, r_package, r_package_version, notes
GBIF Backbone, <doi or release>, <date>, rgbif, <version>, Retrieved via name_backbone()
FishBase, <snapshot date>, <date>, rfishbase, <version>, Results cached locally
BirdLife International, <year>, <date>, manual, NA, Incorporated via AVONET supplementary data
WCVP, <version number>, <date>, NA, NA, Static download from Kew
```

This file must be archived alongside every reconciliation output table.

---

## Appendix B — Unresolved Name Retention Policy

Unresolved names must NEVER be silently dropped. They must be:

1. Retained in the reconciliation table with `matched_status = unresolved`.
2. Written to a separate `unresolved_names.csv` for each reconciliation run.
3. Counted in the `reconciliation_diagnostics_report.csv`.
4. Explicitly excluded (not silently absent) from the final body mass compiled table via a documented exclusion filter step.

This ensures that the final table's apparent species count can be reconciled against the input species count at any time.

---

*Document produced by taxonomy-reconciliation specialist agent, GlobalBodySize project, 2026-05-09. All UNVERIFIED items require independent confirmation before production use.*
