# GlobalBodySize — Ecological Quality Advisory

**Agent:** merow-ecology (GitHub Copilot / Claude Sonnet 4.6 in merow-ecology mode)  
**Date:** 2026-05-09  
**Requested by:** Brian Jenquist  
**Purpose:** Scientific data quality prioritization for the GlobalBodySize programmatic harvest project.

> **SCHOLARLY RIGOR NOTICE:** All citations below are marked with confidence levels. UNVERIFIED = must be independently confirmed before use in publications, grant proposals, or READMEs. This document is advisory, not peer-reviewed.

---

## Standard Format Headers (merow-ecology mode)

### Modeling Objective
Construct a globally harmonized, programmatically harvestable database of species body mass / body size measurements across all major animal groups (mammals, birds, fish, reptiles, amphibians, arthropods) and plants, suitable for macroecological allometric analyses, trophic modeling, and cross-taxon comparative ecology. The inference target is the **species-level mean adult body mass** in grams, with metadata sufficient to assess measurement type, life stage, sex, and intraspecific variability.

### Assumptions
1. Species-level mean adult body mass is a scientifically defensible target for macroecological analyses, even though it compresses intraspecific variation.
2. Published literature-derived means (from PanTHERIA, AVONET, etc.) are assumed to reflect adult wet mass unless explicitly stated otherwise.
3. FishBase length-weight parameters are assumed to yield reasonable mass estimates for species-average adults when applied at median reported body length.
4. Taxonomic harmonization (e.g., via `taxize`, TNRS, or COL Checklist of Life) is a prerequisite — we assume name matching is possible for >80% of records.
5. Integration across measurement types (wet, dry, museum-preserved, LW-modeled) is possible IF each record carries unambiguous mass_type metadata.

### Risks
- **Measurement type confounding:** Mixing wet, dry, and LW-modeled masses without metadata flags will introduce systematic errors that are impossible to untangle post hoc.
- **Life stage bias:** Museum specimens include juveniles; database means often preferentially reflect adult males.
- **Geographic sampling bias:** Most curated databases oversample North America, Europe, and Australia; tropical diversity (which dominates global species richness) is underrepresented.
- **Taxonomic non-stationarity:** Species circumscriptions change over time; records linked to old names become orphaned.
- **Intraspecific signal loss:** Mean-only databases cannot support questions about body size variation, Bergmann's rule, or temporal change — flag this as a scope limitation.

### Decision
**Proceed** — the scientific value is high and the data sources are sufficiently mature. However, adopt a strict schema with mandatory `mass_type`, `life_stage`, `sex`, and `measurement_method` fields from the start. Retrofitting these fields later will be costly.

---

## TASK 1 — Ecological Quality Audit of Tier 1 Data Sources

Ratings:
- **Tier A:** Publish-grade; can be used directly with appropriate citation and standard QA.
- **Tier B:** Requires QA steps before publication-quality inference.
- **Tier C:** Supplemental only; use for gap-filling with heavy caveats.

---

### 1.1 PanTHERIA (Mammals)

| Criterion | Assessment |
|---|---|
| **Body mass definition** | Adult body mass in grams; literature-compiled means; wet mass assumed but not always confirmed per record |
| **Sex distinguished?** | No — species means collapse sexes; sexual dimorphism in mammals can be substantial (e.g., elephant seals: ~8× male:female ratio) |
| **Age/life stage** | Adult only (as reported by sources) — but source studies vary in how "adult" was defined |
| **Intraspecific variation** | NOT captured — species mean only; no SD, range, or sample size for most entries |
| **Sampling bias documented?** | Partially — known bias toward North American and European species; small tropical mammals (shrews, rodents) have higher gap rates |
| **Scientific quality** | **Tier A** — gold standard for mammal body mass; widely validated; ~6,500 citations |
| **Key use caveat** | Do not use for questions requiring intraspecific variation or sex-specific mass; always pair with PanTHERIA's own NA reporting |
| **Priority flag** | HARVEST FIRST among mammal sources |

---

### 1.2 EltonTraits 1.0 (Birds + Mammals)

| Criterion | Assessment |
|---|---|
| **Body mass definition** | Adult body mass (g); compiled from published references; wet mass assumed |
| **Sex distinguished?** | No — species means only |
| **Age/life stage** | Adult only |
| **Intraspecific variation** | Not captured |
| **Sampling bias** | Global coverage is good for birds; mammal coverage overlaps heavily with PanTHERIA — these two sources are largely redundant for mammals |
| **Scientific quality** | **Tier A** for birds as a standalone mass source; **Tier B** for mammals (use PanTHERIA instead — more records, more explicit documentation) |
| **Key use caveat** | EltonTraits' primary contribution is foraging guild and diet data, not body mass. For mass, prefer AVONET (birds) and PanTHERIA (mammals). EltonTraits mass should be used as a cross-check or gap-filler only. |
| **Priority flag** | Cross-check only; do not treat as primary mass source |

---

### 1.3 AVONET (Birds)

| Criterion | Assessment |
|---|---|
| **Body mass definition** | Adult body mass (g); directly measured from museum specimens and field measurements; one of the few databases with explicit specimen-level origins |
| **Sex distinguished?** | Partially — AVONET includes sex-specific morphological measurements for many species, but published summary statistics may aggregate; check raw data |
| **Age/life stage** | Adults — museum specimens; some institutions have mixed-age collections; AVONET curators applied exclusion criteria but this varies |
| **Intraspecific variation** | Sample sizes per species are available in the full dataset (>90,000 individual specimens); this is AVONET's primary advantage |
| **Sampling bias** | Geographic bias toward well-collected regions; some island endemics and rare species have n=1 or n=2 specimens |
| **Scientific quality** | **Tier A** — highest quality bird morphological database available; explicit measurement protocols |
| **Key use caveat** | Museum mass ≠ live mass for many specimens; check whether mass was recorded at time of specimen preparation (which can include gut content and fluid variation). For live mass, cross-check with CRC Handbook (UNVERIFIED as source) or regional field guides. |
| **Priority flag** | HARVEST FIRST for birds; use raw specimen data if possible to recover uncertainty estimates |

---

### 1.4 AnAge (Vertebrates)

| Criterion | Assessment |
|---|---|
| **Body mass definition** | Adult body mass; primarily from published handbooks and studies; wet mass assumed; some entries explicitly cite source |
| **Sex distinguished?** | No — species means; designed for longevity research where body mass is a covariate |
| **Age/life stage** | Adult only; but "adult" definition varies by taxon group |
| **Intraspecific variation** | Not captured |
| **Sampling bias** | Strong bias toward model organisms and vertebrate taxa studied for aging; invertebrate coverage is sparse and opportunistic |
| **Scientific quality** | **Tier B** — valuable as cross-check and for longevity-mass correlations; not designed as a mass database; quality of mass entries varies substantially |
| **Key use caveat** | Body mass in AnAge exists to enable metabolic rate and aging-rate comparisons, not as a standalone size measure. Use as gap-filler for taxa not covered by primary sources, not as primary. |
| **Priority flag** | Gap-fill only; harvest after Tier A sources are complete |

---

### 1.5 AmphiBIO (Amphibians)

| Criterion | Assessment |
|---|---|
| **Body mass definition** | Body mass (g) and body length (SVL in mm); literature-compiled |
| **Sex distinguished?** | No — species means; sexual size dimorphism in frogs can be moderate to large (females larger in most anurans) |
| **Age/life stage** | Adult; maximum size also recorded |
| **Intraspecific variation** | Not captured |
| **Sampling bias** | IMPORTANT: SVL is far more complete than body mass — many species have SVL but no mass. Geographic bias toward Neotropical and North American amphibians; significant gaps in Southeast Asia, Sub-Saharan Africa, Madagascar. |
| **Scientific quality** | **Tier A for SVL; Tier B for body mass** — mass records exist for only a fraction of species; treat mass availability as a data gap to document explicitly |
| **Key use caveat** | If using amphibian mass, you will need mass-SVL allometric models to impute missing mass from SVL. Document imputation explicitly and propagate uncertainty. This is a research design decision, not just a data cleaning step. |
| **Priority flag** | Harvest SVL universally; mass where available; flag mass-imputation cases |

---

### 1.6 FishBase / rfishbase (Fish — LW-derived mass)

| Criterion | Assessment |
|---|---|
| **Body mass definition** | DERIVED — not directly measured. Mass (W in grams) calculated from length-weight equation: W = a × L^b, where a and b are taxon-specific parameters from published studies. This is the most important distinction for fish data. |
| **Sex distinguished?** | LW parameters sometimes sex-specific; often not — pooled across sexes |
| **Age/life stage** | CRITICAL ISSUE: LW parameters apply across the full size range of a species; "adult mass" requires knowing adult body length, which must be specified separately. Most macroecological studies use maximum or mean adult length as the L input. |
| **Intraspecific variation** | Multiple LW parameter sets often exist per species from different populations and regions; rfishbase returns all available sets — you MUST choose or average |
| **Sampling bias** | Strong bias toward commercially important fish; many deep-sea, freshwater tropical, and small-bodied species have very few or no LW records |
| **Scientific quality** | **Tier B for mass** — comprehensive in taxonomic breadth but mass is modeled, not measured. For length alone, Tier A. |
| **Key use caveat** | **This is the most critical methodological distinction in the entire inventory.** Fish body mass from FishBase is a model output, not an observation. The LW parameters themselves have uncertainty (sample size for parameter fitting varies from n=10 to n=10,000+). You must: (1) extract the LW parameters with their source-level sample sizes, (2) select or average parameters with explicit justification, (3) apply at a biologically defensible body length (e.g., L∞ × 0.95 for maximum adult), (4) propagate LW parameter uncertainty through to mass uncertainty. Do NOT treat fish mass from FishBase equivalently to directly measured mass. |
| **Priority flag** | HARVEST — but store `mass_type = "LW_modeled"` and include a and b parameters with sample sizes in the schema |

---

### 1.7 VertNet (Museum Specimens)

| Criterion | Assessment |
|---|---|
| **Body mass definition** | Mass recorded at time of specimen preparation; field-measured mass (typically wet, live or recently dead) when noted; tissue sample mass otherwise. Highly heterogeneous. |
| **Sex distinguished?** | Often YES — museum specimen records commonly include sex as a field; this is VertNet's key advantage over compiled databases |
| **Age/life stage** | Often YES — age class or reproductive condition recorded for many specimens |
| **Intraspecific variation** | YES — individual-level records; this is VertNet's primary scientific value for body mass research |
| **Sampling bias** | SUBSTANTIAL — geographic bias toward North America, Europe, major natural history museums. Temporal bias: pre-1950 specimens dominate some collections. Body mass field coverage is inconsistent across institutions. |
| **Scientific quality** | **Tier B overall; Tier A for intraspecific variation studies** — the data are scientifically valuable but require heavy parsing, unit harmonization, and outlier detection |
| **Key use caveat** | Mass field in VertNet is a free-text field containing values in grams, ounces, pounds, kilograms, and occasionally milligrams with no enforced units. Require unit parsing and range-based plausibility checks per taxon. Sexual dimorphism and seasonal mass variation are resolvable here — use them. |
| **Priority flag** | Harvest in Phase 2 when individual-level variation is needed; Phase 1 use as gap-filler for species not in Tier A sources |

---

### 1.8 EOL TraitBank (Cross-taxonomic aggregation)

| Criterion | Assessment |
|---|---|
| **Body mass definition** | Heterogeneous — aggregated from multiple sources without harmonization; units may be mixed; source databases have different mass type conventions |
| **Sex distinguished?** | Inconsistent — depends on source |
| **Age/life stage** | Inconsistent |
| **Intraspecific variation** | Sometimes — but not systematically |
| **Sampling bias** | Mirrors biases of contributing databases; no independent bias assessment |
| **Scientific quality** | **Tier C** — use as a discovery tool to find uncatalogued species or identify source databases not yet in the inventory. Do NOT use as a primary mass source. Conflicts between sources within EOL are common and unresolved. |
| **Key use caveat** | EOL TraitBank has undergone infrastructure changes and data availability may be inconsistent. Treat any mass value obtained here as requiring source-level verification before use. |
| **Priority flag** | Harvest LAST and only for species with zero coverage elsewhere |

---

### 1.9 GBIF MeasurementOrFact

| Criterion | Assessment |
|---|---|
| **Body mass definition** | Completely heterogeneous — each data publisher defines measurementType differently (e.g., "body mass", "weight", "live weight", "mass"); no controlled vocabulary enforced |
| **Sex distinguished?** | Inconsistent |
| **Age/life stage** | Inconsistent |
| **Intraspecific variation** | Present at individual level — but only for publishers who use the MoF extension |
| **Sampling bias** | Coverage of body mass via MoF is sparse — the majority of GBIF occurrence records have no mass measurement. The assessment in DATA_SOURCE_INVENTORY.md (Section 4) is correct: supplemental only. |
| **Scientific quality** | **Tier C for body mass** — the Darwin Core MeasurementOrFact extension is structurally sound but adoption for body mass is low. |
| **Key use caveat** | Do not assume that `measurementType = "body mass"` is consistently interpreted. Text matching of measurementType is required and will produce noise. Reserve for gap-filling only. |
| **Priority flag** | Not worth systematic harvest in Phase 1; revisit if specific taxonomic gaps require it |

---

### 1.10 Ernest 2003 (Mammal Life History)

| Criterion | Assessment |
|---|---|
| **Body mass definition** | Adult body mass (g); literature-compiled; wet mass assumed |
| **Sex distinguished?** | No — species means |
| **Age/life stage** | Adult only; includes neonate mass and weaning mass — this is a key advantage over PanTHERIA for mass ontogeny studies |
| **Intraspecific variation** | Not captured |
| **Sampling bias** | Non-volant placentals only — bats, marsupials, and monotremes excluded. ~1,500 species. |
| **Scientific quality** | **Tier A** — frequently cited; well-validated; curated with ecological context |
| **Key use caveat** | Superseded in coverage by PanTHERIA; primary added value is neonate and weaning mass, which PanTHERIA partially includes but Ernest 2003 documents more explicitly. Useful for life-history allometry studies. |
| **Priority flag** | Merge with PanTHERIA records; prioritize for life stage mass ontogeny |

---

## TASK 2 — Body Mass as an Ecological Variable: Scientific Framework

### Why Body Mass Is THE Primary Ecological Trait

Body mass is functionally unique among biological traits because it is both a cause and correlate of nearly every major ecological rate and pattern. The key references establishing this framework (confidence level noted):

| Reference | Claim | Confidence |
|---|---|---|
| Peters RH. 1983. *The Ecological Implications of Body Size.* Cambridge University Press. | Established the empirical foundation for body size scaling across metabolism, home range, lifespan, population density | HIGH — this is a canonical text; DOI not applicable for books |
| Calder WA. 1984. *Size, Function, and Life History.* Harvard University Press. | Complementary treatment of allometric scaling | HIGH — canonical text |
| Brown JH, Maurer BA. 1989. Macroecology: the division of food and space among species on continents. *Science* 243:1145–1150. DOI: UNVERIFIED | Body size and macroecological abundance-range relationships | MODERATELY CONFIDENT — confirm DOI |
| Brown JH, et al. 2004. Toward a metabolic theory of ecology. *Ecology* 85(7):1771–1789. DOI: 10.1890/03-9000 | Body mass as the primary input to metabolic scaling | HIGH CONFIDENCE — widely reproduced |
| Damuth J. 1981. Population density and body size in mammals. *Nature* 290:699–700. DOI: UNVERIFIED | -3/4 scaling of abundance with mass | MODERATELY CONFIDENT |
| Gaston KJ, Blackburn TM. 2000. *Pattern and Process in Macroecology.* Blackwell Science. | Body size as a structuring variable in macroecology | HIGH — canonical text |
| Pawar S, Dell AI, Savage VM. 2012. Dimensionality of consumer search space drives trophic interaction strengths. *Nature* 486:485–489. DOI: UNVERIFIED | Body mass in foraging theory and predator-prey interactions | MODERATELY CONFIDENT — confirm |

### Primary Ecological Uses of Body Mass (in order of how mass enters the model)

1. **Metabolic rate prediction:** Basal metabolic rate scales with mass^(3/4) in endotherms (the "Kleiber law"); field metabolic rate adds environmental terms. This is the foundational use.
2. **Home range and territory size:** Home range scales approximately with mass^1.0 in mammals (McNab 1963 — UNVERIFIED on exact citation); steeper for carnivores.
3. **Population density:** Scales inversely with mass (Damuth 1981 — see above); critical for estimating biomass and energy flux.
4. **Generation time and lifespan:** Scales approximately with mass^(1/4) across vertebrates; governs evolutionary rate predictions.
5. **Extinction risk modeling:** Body mass is one of the strongest predictors of IUCN extinction risk (Cardillo et al. 2005 — UNVERIFIED); large body size correlates with slow reproduction and high harvest pressure.
6. **Trophic position and food web structure:** Predator-prey mass ratios determine interaction strength; metabolic rates determine energy throughput.
7. **Biogeographic and climate responses:** Bergmann's rule (larger body size at higher latitudes) is well documented in endotherms; seasonal mass dynamics link to climate.
8. **Allometric scaling of physiological rates:** Drug dosing in veterinary ecology, pollutant burden, respiration — all scale predictably with mass.

### Key Ontological Distinctions That Matter for Global Databases

These distinctions are **non-negotiable** for data schema design:

| Distinction | Why it matters | Recommended schema field |
|---|---|---|
| **Wet vs dry vs fat-free mass** | Fat-free mass scales differently from total mass; seasonal fat deposition in hibernators, migratory birds can be 20-50% of total mass | `mass_type` (values: wet, dry, fat_free, lean, ash_free_dry) |
| **Live vs preserved** | Museum preservation can cause mass loss (desiccation) or gain (fluid fixation); alcoholic preservation typically causes 5-20% mass change | `preservation_status` (values: live, fresh_dead, alcohol_preserved, dry_pinned, formalin_fixed) |
| **Adult vs juvenile vs larval** | Mass can differ by 3-5 orders of magnitude across ontogeny in insects; 10-100× in fish; 10-50× in mammals | `life_stage` (values: adult, subadult, juvenile, larval, neonate, egg, unknown) |
| **Sex** | See sexual dimorphism table below | `sex` (values: male, female, pooled, unknown) |
| **Species mean vs population estimate vs individual measurement** | These require different statistical treatment; mixing them creates pseudo-replication | `measurement_grain` (values: species_mean, population_mean, individual, derived_from_allometry) |
| **LW-modeled vs directly measured** | Fish mass from FishBase is a model output; treat differently from directly measured mass | `measurement_method` (values: direct_scale, LW_equation, literature_mean, text_mining, expert_estimate) |

### Sexual Dimorphism Magnitude by Taxon Group

Sexual dimorphism is larger than most global database users assume. The following ranges are ORDER-OF-MAGNITUDE guidance:

| Taxon group | Typical female:male mass ratio | Extreme cases | Notes |
|---|---|---|---|
| Mammals (polygynous) | Males 1.5–8× female | Elephant seals: males ~8–10× females (UNVERIFIED — confirm for Mirounga angustirostris); gorillas ~2× | Dimorphism directionally consistent (males larger) in most polygynous mammals |
| Mammals (monogamous) | Near 1:1 (0.9–1.1) | Gibbons, most canids | |
| Birds | Near 1:1 for most; raptors reversed | Female raptors up to 1.5–2× male (UNVERIFIED — confirm order of magnitude) | Raptors show reversed dimorphism; females larger |
| Reptiles | Variable; females often larger in oviparous taxa | Boa constrictors: females ~2× male body mass (UNVERIFIED) | Lizards: males often larger in territorial taxa |
| Amphibians | Females typically 1.1–1.5× males (most anurans) | Some frogs show 2× (UNVERIFIED) | Females larger is the modal pattern in frogs |
| Fish | Highly variable; females often larger in oviparous species | Some anglerfish: females 100× male (UNVERIFIED — parasitic males) | LW parameters should ideally be sex-specific |
| Insects | Females commonly 2–10× males in many orders | Some spiders (related): females 50× males (UNVERIFIED) | Body mass sex ratio is a critical ontological issue for arthropods |

**Practical implication:** For any taxon group where sexual dimorphism exceeds ~1.3×, a database that does not record sex is introducing a systematic bias of that magnitude in one direction. This is NOT random error — it is directional if sampling is sex-biased (e.g., males more often caught in traps for some taxa, females more often in museum collections due to nesting behavior in others).

---

## TASK 3 — Priority Data Source Ranking for Phase 1 Harvest

The following priority order is based on: (A) scientific quality, (B) programmatic R access, (C) complementarity (minimizing redundancy), (D) filling the most important taxonomic gaps.

### Priority Rankings

| Rank | Database | Taxon | Rationale |
|---|---|---|---|
| **1** | PanTHERIA | Mammals | Tier A; direct download; foundational; minimal QA needed; covers ~5,400 species |
| **2** | AVONET | Birds | Tier A; specimen-level data with uncertainty; covers all ~10,000 bird species; best bird morphology dataset |
| **3** | rfishbase (LW parameters) | Fish | Tier B but broadest taxonomic reach (~33,000 species); `rfishbase` package on CRAN; harvest LW parameters WITH a, b, n, reference, and then compute mass at standard length — do NOT harvest pre-computed mass values if avoidable |
| **4** | AmphiBIO | Amphibians | Tier A for SVL; best amphibian database; Figshare direct download; critical gap-fill since no other comparable source exists |
| **5** | TRY Plant Trait Database | Plants | Tier A; largest plant trait dataset globally; registration required but data are available; plant "body size" needs explicit operationalization (see below) |
| **6** | Ernest 2003 | Mammals | Tier A; harvest for neonate/weaning mass to complement PanTHERIA adult mass; small incremental coding cost |
| **7** | EltonTraits | Birds + Mammals | Tier A cross-check only; harvest mass column to cross-validate AVONET (birds) and PanTHERIA (mammals); do not treat as primary |
| **8** | AnAge | Vertebrates | Tier B; harvest as cross-check and gap-filler for rare taxa not in Tier A sources; useful for reptiles where no single Tier A source exists |
| **9** | VertNet (rvertnet) | Vertebrates | Tier B for individual-level variation; defer to Phase 2 unless sex-specific or intraspecific variation is a Phase 1 deliverable |
| **10** | Meiri lizard/squamate databases | Reptiles | Tier B; the largest gap in Tier A coverage; search Dryad/Figshare for Meiri and Feldman squamate datasets specifically |
| **Defer** | EOL TraitBank | All | Tier C; too heterogeneous for Phase 1; revisit only for taxa with zero coverage |
| **Defer** | GBIF MoF | All | Tier C; sparse mass coverage; not worth Phase 1 effort |

### Special Note on Plants

Plant "body mass" is fundamentally different from animal body mass and requires explicit operationalization:

- **Preferred plant size metrics in order of macroecological utility:**
  1. Plant height (continuous; available in TRY, BIEN traits, BiolFlor)
  2. Stem diameter / basal area (for trees)
  3. Above-ground biomass (destructive; measurement-method-specific)
  4. Seed mass (scales with dispersal and establishment ecology; highly curated in TRY)
  5. Leaf mass per area (LMA) — not body mass but closely related to growth strategy
- **Do NOT conflate plant biomass with animal body mass** in cross-kingdom analyses without explicit scaling conversion and separate analysis tracks.
- For cross-kingdom allometric comparisons (e.g., metabolic scaling), use above-ground biomass for plants and wet mass for animals, with explicit justification of the comparison.

### Phase 1 Implementation Order (concrete steps)

1. Harvest PanTHERIA + Ernest 2003 → mammals baseline
2. Harvest AVONET → birds baseline
3. Harvest AmphiBIO → amphibians baseline
4. Programmatic harvest of rfishbase LW parameters → fish mass pipeline
5. Submit TRY data request → plants queue (may take days for approval)
6. Cross-check with EltonTraits → flag conflicts
7. Search Dryad for Meiri squamate datasets → reptiles gap-fill
8. Harvest AnAge → remaining vertebrate gap-fill

---

## TASK 4 — Key Scientific Risks and Data Integration Warnings

### Risk 1: Mass Type Confounding (HIGHEST PRIORITY)

Mixing wet live mass, museum dry mass, LW-modeled mass, and literature-means without explicit flags will produce errors that are **undetectable after the fact**. This is not a theoretical concern — it has caused retractions and corrections in comparative ecology datasets.

**Concrete recommendation:** The `mass_type` and `measurement_method` fields must be **mandatory, non-nullable** in the schema. If a source does not document mass type, assign `mass_type = "unspecified"` — never impute or assume wet mass.

### Risk 2: Taxonomic Scope Conflation

"Body mass" for a fish species measured in a Norwegian fjord population, a tropically-distributed relative measured in Southeast Asia, and a museum specimen from 1890 are **not the same measurement** in a scientific sense. Geographic provenance of mass measurements is underreported in compiled databases.

**Concrete recommendation:** Store `measurement_country` or `measurement_region` when recoverable from source. For FishBase LW parameters, the geographic context of parameter estimation is available — extract and store it.

### Risk 3: Life Stage Contamination

Mass records for non-adults embedded in adult species means are common in museum specimen databases and some compiled databases. Juveniles will systematically downward-bias species means.

**Concrete recommendation:** For VertNet harvest, apply minimum body length filters calibrated per taxon (e.g., >50% of reported maximum length) to filter probable juveniles when age field is absent. Document the filter explicitly.

### Risk 4: Sexual Dimorphism Bias Direction

If a database's underlying samples are sex-biased (which most are, to varying degrees), species means are directionally biased. The bias direction is taxon-specific (males larger: most mammals; females larger: most raptors, many frogs).

**Concrete recommendation:** Store `sex_of_mass_sample` as a metadata field. For species with known large dimorphism, consider storing sex-specific means separately rather than collapsing to a single species mean. Provide a `dimorphism_ratio` derived field where both sexes are available.

### Risk 5: Length-Weight Model Uncertainty Propagation (Fish-Specific)

Using a single LW parameter set from FishBase without uncertainty will understate the true mass uncertainty for fish by potentially an order of magnitude for poorly studied species.

**Concrete recommendation:**
- Extract all LW parameter sets per species from rfishbase
- Compute mass estimates from each parameter set at a standardized reference length
- Report `mass_mean`, `mass_sd`, `mass_n_param_sets` per species
- Flag species where LW parameter CV > 50% as `mass_confidence = "low"`

### Risk 6: Taxonomic Non-Stationarity

Species are split and lumped; old names become synonyms; geographic subspecies are elevated to species. A mass record linked to _Rana temporaria_ in 1985 may map to a different taxon circumscription today.

**Concrete recommendation:** Store the `verbatim_taxon_name` as received from source alongside the `resolved_taxon_name` and `taxon_authority` (e.g., ITIS, COL, GBIF backbone). Run taxonomic reconciliation as a separate pipeline step and log the match type (`exact`, `synonym`, `fuzzy`, `no_match`).

### Risk 7: Non-Independence in Phylogenetic Analyses

If body mass from this database will be used in phylogenetic comparative analyses (PGLS, BAMM, ancestral state reconstruction), species means from the same genus from the same source database are not phylogenetically independent.

**Concrete recommendation:** Note in data documentation that phylogenetic correction is required for comparative analyses. Consider including GBIF `speciesKey` and a resolvable taxonomy backbone to enable straightforward integration with phylogenetic trees (e.g., VertLife, TimeTree).

### Schema Recommendation: Mandatory Risk Fields

```
mass_g               # numeric; the value
mass_type            # wet | dry | fat_free | lean | ash_free_dry | LW_modeled | unspecified
measurement_method   # direct_scale | LW_equation | literature_mean | text_mining | expert_estimate
life_stage           # adult | subadult | juvenile | larval | neonate | unknown
sex                  # male | female | pooled | unknown
sex_of_mass_sample   # (free text or controlled vocab) describes sample composition when sex=pooled
verbatim_taxon_name  # as received from source
resolved_taxon_name  # post-taxonomic reconciliation
taxon_match_type     # exact | synonym | fuzzy | no_match
source_database      # PanTHERIA | AVONET | rfishbase | AmphiBIO | ...
source_record_id     # primary key from source database when available
measurement_country  # ISO country code when recoverable
measurement_year     # year of measurement when recoverable
mass_confidence      # high | medium | low | unassessable (based on source quality + measurement_method)
```

---

## TASK 5 — Overlooked Body Mass Data Sources

The following are commonly used in ecological research but underrepresented in database compilations:

### 5.1 National Wildlife Monitoring Programs

| Source | Taxon | Coverage | Access |
|---|---|---|---|
| **North American Breeding Bird Survey (BBS)** | Birds | North America | Body mass not directly measured but species-level mass linkable from AVONET; count data; not a mass source per se |
| **Christmas Bird Count / Project FeederWatch** | Birds | North America | Same as BBS — not mass |
| **USGS bird banding lab records** | Birds | North America | Band resight records include mass for some species (passerines during banding); mass records exist but not systematically published; contact USGS for data access (UNVERIFIED — confirm accessibility) |
| **North American Bat Monitoring Program (NABat)** | Bats | North America | Roost surveys record mass at capture; not aggregated into public mass database; contact program office (UNVERIFIED) |
| **AFSC (Alaska Fisheries Science Center) trawl surveys** | Fish | North Pacific | Weight-at-age data for commercially important species; available via AKFIN Answers portal (UNVERIFIED — confirm portal name) |

### 5.2 Fisheries Stock Assessment Databases with Weight-at-Age Data

These are among the most overlooked sources for fish body mass — they contain thousands of individual-level mass measurements, often sex-stratified and age-validated:

| Source | Taxon | Coverage | Notes |
|---|---|---|---|
| **RAM Legacy Stock Assessment Database** | Marine fish | Global commercially fished stocks | Contains biomass estimates; not individual-level mass but stock-level; UNVERIFIED on individual mass availability |
| **ICES (International Council for the Exploration of the Sea) trawl surveys** | North Atlantic fish | North Atlantic | Weight-at-age for major commercial stocks; access via ICES data portals; requires account (UNVERIFIED — confirm current access) |
| **FAO Fisheries and Aquaculture global production statistics** | Fish + invertebrates | Global | Landings data; not individual mass but can cross-check expected mass ranges |
| **FishSeries database (NOAA AFSC)** | Pacific fish | North Pacific | Specimen-level length and weight from trawl surveys; UNVERIFIED on external accessibility |
| **SEAMAP Gulf of Mexico trawl surveys** | Gulf of Mexico fish | Gulf of Mexico | Length-weight records from bottom trawl surveys (UNVERIFIED — confirm accessibility) |

### 5.3 Museum Collections with Digitized Specimen Mass Beyond VertNet

| Source | Taxon | Notes |
|---|---|---|
| **Smithsonian National Museum of Natural History (NMNH) — EMu records** | All vertebrates | Not all mass records are in VertNet; some are in EMu but not yet published to aggregators; direct contact may be needed (UNVERIFIED) |
| **Natural History Museum London (NHM) Data Portal** | Vertebrates + invertebrates | https://data.nhm.ac.uk (UNVERIFIED — confirm URL); some specimen mass records available; Darwin Core; accessible via API |
| **iDigBio** | Vertebrates + plants | https://idigbio.org (UNVERIFIED — confirm URL); aggregates US natural history collections; overlaps with VertNet but not identical; R package `ridigbio` (UNVERIFIED — confirm CRAN status) |
| **GBIF specimen records (not MoF)** | All taxa | Species occurrence records sometimes include dynamicProperties field with mass; parseable via rgbif but very sparse |

### 5.4 Regional or Taxon-Specific Databases Not Widely Known Globally

| Source | Taxon | Notes |
|---|---|---|
| **Reptile-Trait database** | Reptiles | Meiri S and collaborators — most complete reptile trait database; may be available via Dryad or directly; UNVERIFIED on current version and access |
| **GloNAF (Global Naturalized Alien Flora)** | Plants | Includes plant height — relevant for plant size but not body mass per se (UNVERIFIED DOI) |
| **ATLANTIC-BATS** | Neotropical bats | Part of ATLANTIC series; includes body mass from capture records; published as Ecology data paper (UNVERIFIED — search "ATLANTIC BATS" in Ecology journal) |
| **BioTIME** | Cross-taxonomic | Community time series; includes body size in some records; primarily diversity data (UNVERIFIED URL: http://biotime.st-andrews.ac.uk) |
| **Global Arthropod Database (GADB)** | Arthropods | Less well known; Gossner et al. and related; UNVERIFIED on current availability and canonical citation |
| **Crop Wild Relatives databases** | Plants | FAO and Bioversity International; seed mass and plant size data for wild relatives of crops (UNVERIFIED on specific databases) |
| **Entomological Society databases** | Insects | Body mass data for insects are scattered across local entomological society repositories; no global aggregation currently exists (a genuine scientific gap) |
| **Pan-European Common Bird Monitoring Scheme (PECBMS)** | Birds | European bird population trends; does not directly measure mass but supports linkage to AVONET |

### 5.5 Grey Literature and Semi-Published Sources

| Source | Notes |
|---|---|
| **IUCN narrative assessments** | Text mining of narratives for body mass mentions; tedious but covers many vertebrate species; requires NLP pipeline |
| **FAO Species Identification Sheets** | Contain typical body size ranges for commercially important fish and invertebrates; not machine-readable but valuable for cross-check |
| **CRC Handbook of Avian Body Masses (Dunning 2008)** | MODERATELY CONFIDENT — a standard reference for bird body mass; not freely downloadable but widely used; check if institutional access permits scanning for specific species; DOI UNVERIFIED |
| **Walker's Mammals of the World** | Classic reference for mammal mass; largely superseded by PanTHERIA for programmatic use but useful for rare taxa |
| **Handbook of the Mammals of the World (HMW, Lynx Edicions)** | Modern species accounts with mass data; not machine-readable; useful for new species described after PanTHERIA cutoff (UNVERIFIED on accessibility) |

---

## Recommended Workflow Summary

1. **Define schema first** — implement all mandatory risk fields listed in Task 4 before writing any harvest code.
2. **Harvest Tier A sources** (PanTHERIA, AVONET, AmphiBIO) as flat files — these are the scientific backbone.
3. **Build fish mass pipeline** with rfishbase LW parameters — store parameters, not just derived mass.
4. **Submit TRY plant trait data request** — this takes calendar time; submit early.
5. **Search Dryad/Figshare for Meiri squamate datasets** — fills the largest Tier A gap (reptiles).
6. **Taxonomic reconciliation** — run all names through `taxize` or COL after harvest; log match types.
7. **Cross-check pass** — compare PanTHERIA vs EltonTraits, AVONET vs EltonTraits for mammals/birds; flag conflicts > 50%.
8. **Phase 2 harvest** — VertNet individual-level records for intraspecific variation studies.
9. **Gap audit** — document which taxonomic groups remain below threshold coverage (suggest <100 species = "critical gap").

---

## Diagnostics and Evidence to Produce

- Coverage table: N species per taxonomic group × source database (matrix)
- Mass type flag distribution: what % of records are `mass_type = "unspecified"` (target: <10%)
- Conflict rate between cross-checked sources (target: flag any conflict >50%)
- Geographic coverage map of source localities when recoverable
- Sexual dimorphism flag rate: what % of species have sex-specific mass (target: produce this as a quality indicator)
- LW parameter uncertainty distribution for fish: histogram of CV(mass) across species

---

*End of advisory document. All UNVERIFIED markers require independent validation before use in publications.*
