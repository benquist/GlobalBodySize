# GlobalBodySize

**A reproducible, provenance-rich, cross-taxon animal body mass database.**

[![Phase](https://img.shields.io/badge/Phase-1%20Tier--1%20Intake-blue)]()
[![Rows](https://img.shields.io/badge/Rows-47%2C108-green)]()
[![Groups](https://img.shields.io/badge/Taxa-mammals%20%7C%20birds%20%7C%20fish%20%7C%20amphibians%20%7C%20reptiles-orange)]()

Body mass is the central ecological trait — it determines metabolic rate, population density, home range, generation time, and extinction risk across all animal life. This project assembles a unified, Darwin Core-compatible body mass database from authoritative curated sources, designed for macroecological synthesis, scaling law tests, and trait-based biodiversity analyses.

---

## Contents

- [Ecological Rationale](#ecological-rationale-and-scientific-context)
- [Body Size Distributions and Evolution](#body-size-distributions-and-evolution)
- [Data Sources and Provenance](#data-sources-and-provenance)
- [Project Structure](#project-structure)
- [Quick Start](#quick-start)
- [Current Data Inventory](#current-data-inventory)
- [Summary Visualizations](#summary-visualizations)
- [Pipeline Architecture](#pipeline-architecture)
- [Key Documents](#key-documents)
- [References](#references)

---

## Ecological Rationale and Scientific Context

### Body Mass as the Master Trait

Body mass is among the most integrative and predictive traits in animal ecology (Peters 1983; Brown & Maurer 1989). Across more than ten orders of magnitude — from soil invertebrates to blue whales — mass integrates physiology, behavior, and life history into a common currency. It scales predictably with:

- **Metabolic rate**: basal metabolic rate ∝ M^b where b ≈ 0.75 (Kleiber 1932; West, Brown & Enquist 1997; though the precise exponent is debated: Dodds, Rothman & Weitz 2001), setting the pace of energy acquisition and allocation
- **Population density**: larger-bodied species maintain lower densities, constraining abundance and geographic range size (Brown & Maurer 1989)
- **Home range and space use**: territory and movement scale as power functions of mass, shaping trophic cascades and gene flow
- **Generation time and reproductive output**: smaller animals reproduce faster, buffering population dynamics against disturbance
- **Extinction risk**: large body size is consistently associated with elevated vulnerability to harvest, habitat loss, and demographic stochasticity

Because mass underpins these relationships, it is not merely a trait — it is a scaffold for mechanistic macroecology (Peters 1983).

### Macroecological Motivation

Scaling relationships emerge most clearly when analyzed across taxa and body-size ranges spanning multiple orders of magnitude. A cross-taxon database — integrating mammals, birds, ray-finned fishes, and amphibians — provides the breadth required to:

- Test whether metabolic and demographic scaling exponents are universal or clade-specific
- Partition variance in biodiversity gradients between climate, body size, and trophic position
- Benchmark trait-based species distribution models across vertebrate groups

### Scientific Gaps This Database Addresses

Despite decades of macroecological research, existing resources are fragmented across isolated repositories with inconsistent taxonomy, missing provenance, and limited interoperability:

- **Multi-source provenance**: records are annotated with primary source, access date, and data quality flags, enabling reproducible synthesis
- **Reptile coverage expanding**: Lizard Traits of the World (Meiri 2018) added 6,633 lizard species via allometric L-W equations (Feldman et al. 2016). ReptTraits (Meiri et al. 2024, Sci Data) with directly measured body masses is the next priority. Snake, amphisbaenian, and tuatara body mass data remain gaps. Body mass shapes life-history pace across squamates and other reptiles, motivating continued reptile coverage expansion.
- **Amphibian gap**: body mass drives the fast-slow life-history continuum in amphibians (Cejp & Griebeler 2024); AmphiBIO covers only ~591 of ~8,500 amphibian species — a critical coverage gap for macroecological analyses
- **Darwin Core compliance**: all records are harmonized to DwC fields, enabling direct submission to GBIF and integration with occurrence and phylogenetic data streams

---

## Body Size Distributions and Evolution

### The Shape of the Body Size Distribution

Across all animal groups, body size is not uniformly distributed — it is strongly right-skewed on a linear scale but approximately log-normal on a log₁₀ scale. This is not a sampling artifact: it reflects fundamental constraints on how life is organized energetically and developmentally. When plotted as log₁₀(number of species) vs. log₁₀(body mass), the distribution peaks at small-to-intermediate sizes and declines steeply toward large body sizes — a pattern first modelled by Hutchinson & MacArthur (1959) and documented empirically by May (1978, 1988), and replicated here across ~25,000 unique vertebrate records (species count provisional pending cross-source deduplication; see Known Limitations).

The log-normal form arises naturally from multiplicative growth processes: body size is the product of many semi-independent developmental, physiological, and life-history factors, and the central limit theorem applied to products of random variables converges to a log-normal distribution (May 1986). This prediction holds reasonably well within taxonomic groups, though each clade occupies a distinct mode: fish and amphibians cluster at smaller sizes, mammals span a broad intermediate range, and birds show a narrower, elevated mode.

### Why Are Most Species Small?

The steep decline in species richness at large body sizes is not simply a sampling bias — it reflects genuine biological constraints:

- **Energy availability:** Larger animals require more energy per individual. If the total energy available to a trophic level is roughly fixed, fewer large-bodied individuals — and therefore fewer large-bodied species — can be supported (Peters 1983; Brown & Maurer 1989). The number of sustainable species declines with body mass at approximately S ∝ M^(−3/4), consistent with metabolic energy partitioning.
- **Population size and extinction risk:** Large animals maintain smaller populations, making them more vulnerable to demographic and environmental stochasticity. This accelerates local extinction rates and reduces long-term diversification probabilities at large sizes (Gaston & Blackburn 2000).
- **Generation time and speciation rate:** Smaller animals have shorter generation times, higher reproductive rates, and faster evolutionary turnover — all of which accelerate the accumulation of genetic divergence and new species (Bromham & Cardillo 2003).
- **Geographic range and dispersal:** Many large-bodied species have wide ranges that reduce allopatric isolation, slowing cladogenesis (Gaston & Blackburn 2000).

The net result is a consistent macroecological pattern: small species are disproportionately species-rich, and this relationship holds across independently-evolved vertebrate lineages.

### Body Size and Evolutionary Diversification

Body size is not a static trait — it evolves under strong selection pressures that vary by clade, environment, and ecological context:

- **Cope's Rule:** Many vertebrate lineages show a directional trend toward larger body size through geological time (Cope 1887; Stanley 1973; Alroy 1998). Note: Cope (1887) described the empirical pattern; Stanley (1973) formalized it as a named evolutionary rule. Larger size is often associated with competitive dominance, reduced predation risk, and broader physiological tolerances. However, this trend is not universal — island dwarfism, resource limitation, and predator-prey dynamics can strongly reverse it.
- **Bergmann's Rule:** Within endotherm clades, larger body size is favored at higher latitudes, where greater thermal mass reduces heat loss (Bergmann 1847; Blackburn, Gaston & Loder 1999). This generates latitudinal body size gradients in mammals and birds that are partially visible in geographic range data.
- **Island and cave evolution:** Isolated environments — islands, caves, deep sea — produce predictable body size shifts. Large-bodied species tend to shrink (island dwarfism: reduced food, no predators); small-bodied species tend to grow (island gigantism: primarily driven by predator release and altered competitive landscape; Foster 1964; Lomolino 2005). These shifts can occur over timescales of thousands to tens of thousands of years.
- **Trophic position:** Body size and trophic level are tightly coupled. Predators are consistently larger than their prey within communities. As trophic level increases, mean body size increases by roughly one order of magnitude per trophic step in terrestrial systems (Peters 1983).
- **Macroevolutionary constraints:** Phylogenetic conservatism in body size is strong — closely related species are more similar in size than expected by chance. This means body size evolution is structured by ancestry, and cross-taxon analyses must account for phylogenetic non-independence (Harvey & Pagel 1991).

### May (1988) Re-evaluated with This Dataset

May (1988, *Science* 241:1441–1449) presented one of the first broad-scale empirical analyses of species richness as a function of body size, showing a log-log decline in species numbers with increasing body mass for terrestrial mammals and British insects. His Fig. 2 showed a slope broadly consistent with S ∝ M^(−2/3) to M^(−3/4).

The `science_summary.html` report in this repository replicates and extends this analysis to ~25,000 unique vertebrate records spanning fish, amphibians, birds, and mammals (Figs. 3e–3f; species count provisional pending deduplication). The empirical slope estimated from this dataset and the theoretical −0.75 prediction are shown together, allowing direct assessment of how well the energy-partitioning model predicts the observed diversity-size relationship across a broader taxonomic scope than May's original analysis.

> **Sampling caveat:** The current database over-represents birds (AVONET + EltonTraits) and fish (FishBase) relative to their true global richness, and severely under-represents reptiles and invertebrates. Slopes estimated from the combined dataset should be interpreted as provisional until the database achieves more uniform taxonomic coverage.

---

## Data Sources and Provenance

All Tier 1 sources were ingested programmatically with full field-level provenance retained. Each compiled output CSV includes `source_id`, `mass_type`, `backbone_version`, and a `gbif_match_type` column from GBIF Backbone reconciliation. Raw downloads are preserved unchanged under `providers/<source>/data/raw/`.

### Tier 1 Sources — Phase 1 Status

| Source | Taxonomic Group | Rows | Mass Type | DOI / Access | Status |
|---|---|---|---|---|---|
| PanTHERIA v1.0 (Jones et al. 2009) | Mammals | 3,542 | wet / literature mean | [10.1890/08-1494.1](https://doi.org/10.1890/08-1494.1) | ✅ COMPLETE |
| EltonTraits 1.0 — Birds (Wilman et al. 2014) | Birds | 9,993 | literature mean | [10.1890/13-1917.1](https://doi.org/10.1890/13-1917.1) | ✅ COMPLETE |
| EltonTraits 1.0 — Mammals (Wilman et al. 2014) | Mammals | 5,400 | literature mean | [10.1890/13-1917.1](https://doi.org/10.1890/13-1917.1) | ✅ COMPLETE |
| AVONET (Tobias et al. 2022) | Birds | 11,009 | morphology / literature | [10.1111/ele.13898](https://doi.org/10.1111/ele.13898) | ✅ COMPLETE |
| FishBase via rfishbase v5.0.3 | Fish | 5,657 | direct max weight + LW-modeled | Living database — no single DOI. Accessed 2026-05-10 | ✅ COMPLETE |
| AnAge Build 14 (de Magalhães & Costa 2009) | Multi-taxon | 627 | literature mean | [10.1111/j.1420-9101.2009.01783.x](https://doi.org/10.1111/j.1420-9101.2009.01783.x) | ✅ COMPLETE |
| AmphiBIO v1 (Oliveira et al. 2017) | Amphibians | 591 | literature mean | [10.1038/sdata.2017.123](https://doi.org/10.1038/sdata.2017.123) | ✅ COMPLETE |
| NEON DP1.10072.001 | Mammals | 800 | field trapping max weight | 10.48443/s4ph-2z37 **(UNVERIFIED)** | ✅ COMPLETE |
| AnimalTraits (Herberstein et al. 2022) | Vertebrates + Invertebrates | 2,856 | wet / literature mean | [10.1038/s41597-022-01364-9](https://doi.org/10.1038/s41597-022-01364-9); data [10.5281/zenodo.6468938](https://doi.org/10.5281/zenodo.6468938) | ✅ COMPLETE |
| Lizard Traits of the World (Meiri 2018) | Lizards (Squamata) | 6,633 | **LW-modeled** (allometric; Feldman et al. 2016) | [10.1111/geb.12773](https://doi.org/10.1111/geb.12773); data [10.5061/dryad.f6t39kj](https://doi.org/10.5061/dryad.f6t39kj) | ✅ COMPLETE |

> **Note:** The NEON DOI `10.48443/s4ph-2z37` is used internally but has not been independently verified. Confirm before citing in any publication.

> **AnimalTraits invertebrates:** AnimalTraits is the first provider to add invertebrate body mass to GlobalBodySize (Insecta 772 rows / 296 spp, Arachnida 131 / 65 spp, Malacostraca 28 / 2 spp, Myriapoda, Annelida, Gastropoda). AnimalTraits vertebrate rows (Mammalia, Aves, Reptilia, Amphibia) overlap with existing providers and will require deduplication. All body mass values converted from kg to g at intake.

> **LW-modeled mass (FishBase):** Mass estimated via FishBase length-weight regression W = a × L^b (species-specific a, b coefficients from FishBase literature). Input length = maximum recorded length. Not directly equivalent to mean adult mass; tends toward maximum adult mass. Never pool `wet` and `LW_modeled` without filtering on `mass_type`. See `providers/fishbase/load_fishbase.R` for exact fields used.

> **LW-modeled mass (Lizard Traits):** Mass computed from allometric equations: log₁₀(mass_g) = intercept + slope × log₁₀(SVL_mm), where intercept and slope are clade-specific regression coefficients from Feldman et al. (2016) and Meiri (2008). Input SVL = maximum SVL in mm. These values are flagged `mass_measurement_type = "lw_modeled"` and `data_quality_flag = "allometric_modeled"`. Do not pool with directly measured mass without filtering on `mass_measurement_type`.

**Phase 1 + AnimalTraits + LizardTraits total (as of 2026-05-11): 47,108 rows across 10 completed providers.**

### Taxonomic Group Breakdown

| Group | Rows | Sources |
|---|---|---|
| Birds | 22,058 | EltonTraits (Birds), AVONET, AnimalTraits |
| Mammals | 11,099 | PanTHERIA, EltonTraits (Mammals), AnAge, NEON, AnimalTraits |
| Reptiles (lizards) | 6,741 | Lizard Traits of the World (Meiri 2018), AnAge, AnimalTraits |
| Fish | 5,657 | FishBase |
| Insects | 772 | AnimalTraits |
| Arachnids | 131 | AnimalTraits |
| Amphibians | 619 | AmphiBIO, AnAge, AnimalTraits |
| Crustaceans | 28 | AnimalTraits |
| Myriapods / Annelids / Gastropods | 3 | AnimalTraits |

> **Reptile note:** 6,633 of the 6,741 reptile rows are lizard species from Meiri (2018) with allometric (LW-modeled) mass estimates; 108 rows from AnAge and AnimalTraits carry literature means. ReptTraits (Meiri et al. 2024) with directly measured maximum body masses for 12,060 reptile species is the next priority intake.

> **Deduplication note:** Mammals, birds, reptiles, and amphibians are now multi-provider and require GBIF-reconciled deduplication before species richness or coverage estimates are made. Invertebrate groups (insect, arachnid, crustacean, myriapod, annelid, gastropod) are sourced from AnimalTraits only — no deduplication required yet.

### GBIF Taxonomic Reconciliation

All rows reconciled against GBIF Backbone (version 2023-08-28, datasetKey `d7dddbf4-2cf0-4f39-9b2a-bb099caae36c`):

- **97.7% of input names matched EXACTLY** to a GBIF Backbone record (matchType = EXACT)
- **~7.8% of matched rows resolved to SYNONYM status** — `accepted_name` column carries the preferred accepted name
- **<0.1% returned NONE or error** — requires manual review

> *Note: matchType (EXACT/FUZZY/NONE) and taxonomic status (SYNONYM/ACCEPTED/DOUBTFUL) are orthogonal GBIF fields; these percentages are not additive.*

Output: `data/compiled/tier1_reconciled.csv`

### Known Limitations (read before citing)

1. **FishBase mass type is heterogeneous — never pool `wet` and `LW_modeled` silently.** Filter on `mass_type` before any cross-taxon or fish-specific analysis.
2. **Lizard mass values are allometric estimates, not direct measurements.** The 6,633 lizard rows from Meiri (2018) use log-log equations from Feldman et al. (2016). These are flagged `mass_measurement_type = "lw_modeled"`. Always stratify on `mass_measurement_type` before cross-taxon comparisons. Non-squamate reptiles (snakes, turtles, crocodilians) remain underrepresented.
3. **Mammals triple-counted** across PanTHERIA, EltonTraits Mammals, and AnAge. Species-level deduplication on GBIF `accepted_name` is required before reporting unique species counts.
4. **GBIF synonyms preserved verbatim** — rows with `SYNONYM`, `DOUBTFUL`, or `FUZZY` match types must not be silently promoted to accepted names.
5. **Darwin Core `measurementID` not populated** — GBIF MoF submission is blocked until unique stable identifiers are assigned.
6. **Zenodo discovery returned 0 candidates** due to API instability. Dryad + Figshare yielded 1,043 candidates. Zenodo must be re-run before the discovery is considered complete.

---

## Project Structure

```
GlobalBodySize/
├── R/                              # Core library functions
│   ├── body_mass_schema.R          # Standard output schema
│   ├── candidate_filter.R          # Dataset candidate scoring
│   ├── dryad_api.R                 # Dryad REST API client
│   ├── qa_checks.R                 # Mass range and unit QA
│   ├── search_terms.R              # 83-term body mass vocabulary
│   ├── taxon_reconciliation.R      # GBIF Backbone reconciliation
│   └── zenodo_api.R                # Zenodo REST API client
├── R/
│   ├── body_mass_schema.R          # Standard mass output schema
│   ├── body_size_schema.R          # Linear size / volume schema (NEW)
│   ├── candidate_filter.R
│   ├── dryad_api.R
│   ├── qa_checks.R
│   ├── search_terms.R
│   ├── taxon_reconciliation.R
│   └── zenodo_api.R
├── data/compiled/
│   ├── tier1_combined.csv          # Merged Tier 1 mass (47,108 rows)
│   ├── tier1_linear_size_combined.csv  # Merged linear size (183k+ rows, NEW)
│   ├── tier1_reconciled.csv        # + GBIF reconciliation columns
│   └── taxon_match_cache.csv       # GBIF match cache (21,696 rows)
├── output/                         # Per-provider compiled CSVs
│   ├── avonet_compiled.csv
│   ├── amphibio_compiled.csv
│   ├── anage_compiled.csv
│   ├── eltontraits_compiled.csv
│   ├── fishbase_compiled.csv
│   ├── lizardtraits_mass_compiled.csv      # NEW — 6,633 rows
│   ├── lizardtraits_linear_compiled.csv    # NEW — 13,111 rows
│   ├── mobs_linear_compiled.csv            # NEW — 183,175 rows
│   ├── pantheria_compiled.csv
│   └── candidate_datasets.csv      # 1,043 Dryad+Figshare candidates
├── providers/                      # One subfolder per data source
│   ├── avonet/load_avonet.R
│   ├── amphibio/load_amphibio.R
│   ├── anage/load_anage.R
│   ├── disperse/load_disperse.R        # NEW — aquatic macroinvertebrates
│   ├── eltontraits/load_eltontraits.R
│   ├── fishbase/load_fishbase.R
│   ├── lizardtraits/load_lizardtraits.R  # NEW — Meiri 2018
│   ├── mobs/load_mobs.R                # NEW — MOBS marine linear size
│   ├── neon/load_neon.R
│   ├── pantheria/load_pantheria.R
│   ├── repttraits/load_repttraits.R    # NEW — Meiri et al. 2024
│   └── sealifebase/load_sealifebase.R  # NEW — marine non-fish
├── scripts/                        # Pipeline orchestration
│   ├── discover_body_mass_datasets.R
│   ├── merge_tier1.R                   # Mass merge (10 providers)
│   ├── merge_linear_size.R             # Linear size merge (NEW)
│   ├── run_taxon_reconciliation.R
│   ├── run_fishbase_intake.sh
│   ├── run_neon_intake.sh
│   └── run_zenodo_discovery.sh
├── science_summary.Rmd             # Full analysis report (57 chunks)
├── science_summary.html            # Rendered HTML report (4.4 MB)
├── PROJECT_LOG_HISTORY.md          # Session-by-session change log
├── DATA_SOURCE_INVENTORY.md        # Annotated 23-source inventory
├── ECOLOGICAL_QUALITY_ADVISORY.md  # Tier quality ratings
├── TAXONOMY_RECONCILIATION_STRATEGY.md
├── BIODIVERSITY_INFORMATICS_AUDIT.md
└── chat_provenance_log.md          # Agent provenance log
```

---

## Quick Start

### Prerequisites

```r
install.packages(c("data.table", "dplyr", "ggplot2", "scales",
                   "rfishbase", "rgbif", "rmarkdown", "knitr",
                   "readxl", "httr", "jsonlite", "tidyr", "patchwork",
                   "neonUtilities"))
```

### Run the Tier 1 pipeline

```r
# 1. Run any individual provider:
source("providers/pantheria/load_pantheria.R")
run_pantheria_intake(dest_dir = "providers/pantheria/data/raw",
                     output_file = "output/pantheria_compiled.csv")

# FishBase (slow — ~10 min full run, use the shell wrapper):
# zsh scripts/run_fishbase_intake.sh

# 2. Merge all providers:
Rscript scripts/merge_tier1.R

# 3. GBIF reconciliation (~30 min for 36k rows):
Rscript scripts/run_taxon_reconciliation.R

# 4. Render the analysis report:
rmarkdown::render("science_summary.Rmd", output_file = "science_summary.html")
```

### Discover additional datasets

```bash
# Dryad + Figshare (Zenodo currently unstable):
Rscript scripts/discover_body_mass_datasets.R \
  --repos=dryad,figshare \
  --pages-per-term=3 \
  --per-page=100 \
  --min-score=6
```

---

## Current Data Inventory

As of 2026-05-11:

| Statistic | Value |
|---|---|
| Total rows — mass table (tier1_combined.csv) | 47,108 |
| Total rows — linear size table (tier1_linear_size_combined.csv) | 183,142+ (MOBS only; others pending) |
| Providers completed (mass) | 10 |
| Providers with scripts ready but not yet run | 3 (ReptTraits, SeaLifeBase, DISPERSE) |
| GBIF EXACT match rate | 97.7% |
| Body size range | ~0.07 g (amphibians) to ~150,000,000 g (blue whale) |
| Range in orders of magnitude | ~9.3 log₁₀ decades |
| Discovery candidates (Dryad + Figshare) | 1,043 |

---

## Summary Visualizations

Full interactive analysis is in [`science_summary.html`](science_summary.html) (render `science_summary.Rmd` to regenerate). Key figures:

| Figure | Description |
|---|---|
| Fig. 0a | Unique species per taxonomic group (total rows vs. deduplicated) |
| Fig. 0b | Species contributed per source database, broken down by group |
| Fig. 0c | Best-estimate unique species count after deduplication |
| Fig. 1 | Log₁₀ body mass distributions by taxonomic group |
| Fig. 2 | Violin + boxplot cross-group comparison (directly measured only) |
| Fig. 3a | Combined all-datasets frequency distribution (stacked by group) |
| Fig. 3b | Density-normalised all-datasets view with per-group curves |
| Fig. 3c | Number of unique species as a function of body size |
| Fig. 3d | Per-group unique species by body size (faceted) |
| Fig. 3e | **May (1988) re-evaluation:** log–log species richness vs. body size, all taxa combined, with empirical OLS slope and theoretical S ∝ M^(−3/4) reference |
| Fig. 3f | Per-group log–log species richness vs. body size (May 1988 style, faceted) |
| Fig. 4 | Cross-provider body mass density overlay |
| Fig. 5 | QQ-plots: log-normality assessment by group |
| Fig. 6 | Cumulative ECDF by group with reference body sizes |

```r
# Regenerate all figures:
rmarkdown::render("science_summary.Rmd", output_file = "science_summary.html")
```

---

## Pipeline Architecture

```
┌──────────────────────────────────────┐
│         Data Discovery               │
│  scripts/discover_body_mass_         │
│  datasets.R — Dryad, Figshare,       │
│  Zenodo (83 search terms)            │
│  → output/candidate_datasets.csv     │
└────────────────┬─────────────────────┘
                 │
┌────────────────▼─────────────────────┐
│       Tier 1 Direct Intake           │
│  providers/<source>/load_<source>.R  │
│  Standard schema: body_mass_schema.R │
│  → output/<source>_compiled.csv      │
└────────────────┬─────────────────────┘
                 │
┌────────────────▼─────────────────────┐
│         Merge & Stack                │
│  scripts/merge_tier1.R               │
│  → data/compiled/tier1_combined.csv  │
└────────────────┬─────────────────────┘
                 │
┌────────────────▼─────────────────────┐
│     Taxonomic Reconciliation         │
│  scripts/run_taxon_reconciliation.R  │
│  GBIF Backbone v2023-08-28           │
│  → data/compiled/tier1_reconciled    │
└────────────────┬─────────────────────┘
                 │
┌────────────────▼─────────────────────┐
│   QA, Deduplication, Analysis        │
│  scripts/deduplicate_species.R (TODO)│
│  science_summary.Rmd                 │
└──────────────────────────────────────┘
```

---

## Key Documents

| Document | Purpose |
|---|---|
| [PROJECT_LOG_HISTORY.md](PROJECT_LOG_HISTORY.md) | Session-by-session log: what was done, row counts, troubleshooting |
| [DATA_SOURCE_INVENTORY.md](DATA_SOURCE_INVENTORY.md) | Annotated inventory of all 23 Tier 1–3 sources |
| [ECOLOGICAL_QUALITY_ADVISORY.md](ECOLOGICAL_QUALITY_ADVISORY.md) | Tier quality ratings and intake priority |
| [TAXONOMY_RECONCILIATION_STRATEGY.md](TAXONOMY_RECONCILIATION_STRATEGY.md) | Backbone strategy per group, conflict rules |
| [BIODIVERSITY_INFORMATICS_AUDIT.md](BIODIVERSITY_INFORMATICS_AUDIT.md) | 8 critical DwC/QA issues; 13 recommended fixes |
| [science_summary.html](science_summary.html) | Rendered analysis report with all figures and tables |
| [science_summary.Rmd](science_summary.Rmd) | Reproducible source for the analysis report |
| [chat_provenance_log.md](chat_provenance_log.md) | Project-level agent provenance log |

---

## Priority Next Steps

| Priority | Action | Blocker |
|---|---|---|
| 0 | Add LICENSE file (CC BY 4.0 recommended) and CITATION.cff | None |
| 0 | Run `renv::snapshot()` to pin R package versions | None |
| 1 | ~~Complete NEON small mammal intake~~ | ✅ Done (800 rows, 2026-05-10) |
| 2 | ~~Add AnimalTraits (invertebrate scope expansion)~~ | ✅ Done (2,856 rows, 2026-05-11) |
| 3 | ~~Add Lizard Traits of the World (Meiri 2018)~~ | ✅ Done (6,633 spp, allometric LW-modeled, 2026-05-11) |
| 4 | ~~Add MOBS 1.0 marine linear size (McClain et al. 2025)~~ | ✅ Done (183,175 rows, 2026-05-11) |
| 5 | Run ReptTraits intake (Meiri et al. 2024, Sci Data, 12,060 reptile spp) | Script ready (`providers/repttraits/load_repttraits.R`) |
| 6 | Run SeaLifeBase intake (rfishbase) | Script ready (`providers/sealifebase/load_sealifebase.R`) |
| 7 | Run DISPERSE intake (Sarremejane et al. 2020, aquatic macroinvertebrates) | Script ready (`providers/disperse/load_disperse.R`) |
| 8 | Re-run GBIF reconciliation on full 47,108-row mass table | None |
| 9 | Deduplicate species across providers (mammals/birds multi-counted) | Requires reconciliation first |
| 10 | Retry Zenodo discovery with `--min-score=3` | API stability |
| 11 | Populate DwC `measurementID` | Design decision needed |
| 12 | Verify NEON DOI `10.48443/s4ph-2z37` on NEON Data Portal | Before publication |
| 13 | Submit to GBIF IPT or Zenodo for public archiving | After DwC compliance |

---

## License and Citation

A LICENSE file has not yet been added to this repository. **CC BY 4.0** is recommended for the compiled database. Raw data from third-party sources are subject to their original licenses (see individual provider DOIs in the source table above and in [DATA_SOURCE_INVENTORY.md](DATA_SOURCE_INVENTORY.md)).

To cite this database compilation once archived:
> [Author(s)]. (2026). *GlobalBodySize: A reproducible cross-taxon animal body mass database* (Phase 1). [Repository/Archive]. Accessed [date].

*A CITATION.cff file and Zenodo/Dryad DOI should be added before public release.*

---

## References

- Alroy, J. (1998). Cope's rule and the dynamics of body mass evolution in North American fossil mammals. *Science* 280(5364):731–734. DOI: 10.1126/science.280.5364.731
- Bergmann, C. (1847). Über die Verhältnisse der Wärmeökonomie der Thiere zu ihrer Grösse. *Göttinger Studien* 3:595–708.
- Blackburn, T. M., Gaston, K. J., & Loder, N. (1999). Geographic gradients in body size: a clarification of Bergmann's rule. *Diversity and Distributions* 5(4):165–174. DOI: 10.1046/j.1472-4642.1999.00046.x
- Bromham, L., & Cardillo, M. (2003). Testing the link between the latitudinal gradient in species richness and rates of molecular evolution. *Journal of Evolutionary Biology* 16(2):200–207. DOI: 10.1046/j.1420-9101.2003.00526.x
- Brown, J. H., & Maurer, B. A. (1989). Macroecology: The Division of Food and Space Among Species on Continents. *Science* 243(4895):1145–1150. DOI: 10.1126/science.243.4895.1145
- Cejp, B., & Griebeler, E. M. (2024). Body mass shapes most life history traits and a fast-slow continuum in amphibians. *Ecology and Evolution* 14(10):e70377. DOI: 10.1002/ece3.70377
- Cope, E. D. (1887). *The Origin of the Fittest*. Appleton, New York.
- de Magalhães, J. P., & Costa, J. (2009). A database of vertebrate longevity records and their relation to other life-history traits. *Journal of Evolutionary Biology* 22(8):1770–1774. DOI: 10.1111/j.1420-9101.2009.01783.x
- Dodds, P. S., Rothman, D. H., & Weitz, J. S. (2001). Re-examination of the "3/4-law" of metabolism. *Journal of Theoretical Biology* 209(1):9–27. DOI: 10.1006/jtbi.2000.2238
- Foster, J. B. (1964). Evolution of mammals on islands. *Nature* 202:234–235. DOI: 10.1038/202234a0
- Gaston, K. J., & Blackburn, T. M. (2000). *Pattern and Process in Macroecology*. Blackwell Science, Oxford.
- Harvey, P. H., & Pagel, M. D. (1991). *The Comparative Method in Evolutionary Biology*. Oxford University Press.
- Hutchinson, G. E., & MacArthur, R. H. (1959). A theoretical ecological model of size distributions among species of animals. *American Naturalist* 93(869):117–125. DOI: 10.1086/282063
- Jones, K. E., et al. (2009). PanTHERIA: a species-level database of life history, ecology, and geography of extant and recently extinct mammals. *Ecology* 90(9):2648. DOI: 10.1890/08-1494.1
- Feldman, A., et al. (2016). Body sizes and diversification rates of lizards, snakes, amphisbaenians and the tuatara. *Global Ecology and Biogeography* 25(2):187–197. DOI: 10.1111/geb.12398
- Kleiber, M. (1932). Body size and metabolism. *Hilgardia* 6(11):315–353.
- Lomolino, M. V. (2005). Body size evolution in insular vertebrates: generality of the island rule. *Journal of Biogeography* 32(10):1683–1699. DOI: 10.1111/j.1365-2699.2005.01314.x
- May, R. M. (1978). The dynamics and diversity of insect faunas. In L. A. Mound & N. Waloff (Eds.), *Diversity of Insect Faunas*, pp. 188–204. Blackwell, Oxford.
- May, R. M. (1986). The search for patterns in the balance of nature: advances and retreats. *Ecology* 67(5):1115–1126. DOI: 10.2307/1938668
- May, R. M. (1988). How many species are there on Earth? *Science* 241(4872):1441–1449. DOI: 10.1126/science.241.4872.1441
- Meiri, S. (2018). Traits of lizards of the world: Variation around a successful evolutionary design. *Global Ecology and Biogeography* 27(10):1144–1155. DOI: 10.1111/geb.12773. Data: https://doi.org/10.5061/dryad.f6t39kj
- Meiri, S., et al. (2024). ReptTraits: a comprehensive dataset of reptile traits. *Scientific Data* 11:386. DOI: 10.1038/s41597-024-03079-5
- Oliveira, B. F., et al. (2017). AmphiBIO, a global database for amphibian ecological traits. *Scientific Data* 4:170123. DOI: 10.1038/sdata.2017.123
- Peters, R. H. (1983). *The Ecological Implications of Body Size*. Cambridge University Press.
- Stanley, S. M. (1973). An explanation for Cope's Rule. *Evolution* 27(1):1–26. DOI: 10.1111/j.1558-5646.1973.tb05912.x
- Tobias, J. A., et al. (2022). AVONET: morphological, ecological and geographical data for all birds. *Ecology Letters* 25(3):581–597. DOI: 10.1111/ele.13898
- West, G. B., Brown, J. H., & Enquist, B. J. (1997). A general model for the origin of allometric scaling laws in biology. *Science* 276(5309):122–126. DOI: 10.1126/science.276.5309.122
- Wilman, H., et al. (2014). EltonTraits 1.0: Species-level foraging attributes of the world's birds and mammals. *Ecology* 95(7):2027. DOI: 10.1890/13-1917.1

---

*All UNVERIFIED items must be confirmed against primary literature before citation in publications or preprints.*

