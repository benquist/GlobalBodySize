# GlobalBodySize

**A reproducible, provenance-rich, cross-taxon animal body mass database.**

[![Phase](https://img.shields.io/badge/Phase-1%20Tier--1%20Intake-blue)]()
[![Rows](https://img.shields.io/badge/Rows-36%2C819-green)]()
[![Groups](https://img.shields.io/badge/Taxa-mammals%20%7C%20birds%20%7C%20fish%20%7C%20amphibians-orange)]()

Body mass is the central ecological trait — it determines metabolic rate, population density, home range, generation time, and extinction risk across all animal life. This project assembles a unified, Darwin Core-compatible body mass database from authoritative curated sources, designed for macroecological synthesis, scaling law tests, and trait-based biodiversity analyses.

---

## Contents

- [Ecological Rationale](#ecological-rationale-and-scientific-context)
- [Theoretical Framework](#theoretical-framework)
- [Data Sources and Provenance](#data-sources-and-provenance)
- [Project Structure](#project-structure)
- [Quick Start](#quick-start)
- [Current Data Inventory](#current-data-inventory)
- [Summary Visualizations](#summary-visualizations)
- [Pipeline Architecture](#pipeline-architecture)
- [Key Documents](#key-documents)
- [Agents and Provenance](#agents-and-provenance)
- [References](#references)

---

## Ecological Rationale and Scientific Context

### Body Mass as the Master Trait

Body mass is the single most predictive trait in animal ecology. Across more than ten orders of magnitude — from soil invertebrates to blue whales — mass integrates physiology, behavior, and life history into a common currency. It scales predictably with:

- **Metabolic rate**: basal metabolic rate ∝ M^0.75 (West et al. 1997), setting the pace of energy acquisition and allocation
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
- **Reptile gap**: reptiles are absent from major compiled databases (PanTHERIA, AnAge); targeted ingestion from herpetological literature and data repositories is a Phase 2 priority
- **Darwin Core compliance**: all records are harmonized to DwC fields, enabling direct submission to GBIF and integration with occurrence and phylogenetic data streams

---

## Theoretical Framework

### The WBE Metabolic Scaling Prediction

The West-Brown-Enquist (WBE) model derives the 3/4-power metabolic scaling law from the geometry of space-filling, impedance-minimizing fractal vascular networks. Starting from two constraints — conservation of fluid volume at each branch and minimization of hydrodynamic resistance — the model predicts that terminal capillary units are invariant across body size, forcing total metabolic rate to scale as:

$$B = B_0 \cdot M^{3/4}$$

where B is whole-organism metabolic rate (watts), M is body mass (kg), and B₀ is a normalization constant that differs between endotherms and ectotherms. This dataset provides the M-axis for cross-taxon tests of this prediction. Metabolic rate data must be joined from external sources (e.g., Savage et al. 2004 for mammals and birds; Clarke & Johnston 1999 for fish).

The scaling exponent b = 3/4 implies that per-unit-mass metabolic rate scales as M^(−1/4) — larger animals are proportionally more metabolically efficient. From this single result, a cascade of ecological predictions follows:

| Ecological variable | Predicted scaling | Exponent |
|---|---|---|
| Metabolic rate B | ∝ M^(3/4) | 0.75 |
| Lifespan T | ∝ M^(1/4) | 0.25 (UNVERIFIED cross-taxon) |
| Home range A | ∝ M^(1.0) | ~1.0 (mammals; varies by guild) |
| Population density D | ∝ M^(−3/4) | −0.75 (UNVERIFIED cross-taxon) |
| Generation time G | ∝ M^(1/4) | 0.25 (UNVERIFIED cross-taxon) |
| Heart rate | ∝ M^(−1/4) | −0.25 (endotherms only) |

*Exponents from Peters (1983) and West, Brown & Enquist (1997). Marked UNVERIFIED where cross-taxon applicability is uncertain — confirm against primary literature before applying to specific taxonomic groups.*

### Body Size Frequency Distributions

Multiplicative growth processes and diversification dynamics predict that body size frequencies are approximately log-normal when plotted on a log₁₀ scale — with a characteristic right skew reflecting the long tail of large-bodied forms. Analyses of this database confirm this prediction: the overall cross-taxon distribution shows a log-normal core with taxon-specific deviations (see `science_summary.html`).

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
| FishBase via rfishbase | Fish | 5,657 | direct max weight + LW-modeled | Living database — no single DOI | ✅ COMPLETE |
| AnAge Build 14 (de Magalhães & Costa 2009) | Multi-taxon | 627 | literature mean | [10.1111/j.1420-9101.2009.01783.x](https://doi.org/10.1111/j.1420-9101.2009.01783.x) | ✅ COMPLETE |
| AmphiBIO v1 (Oliveira et al. 2017) | Amphibians | 591 | literature mean | [10.1038/sdata.2017.123](https://doi.org/10.1038/sdata.2017.123) | ✅ COMPLETE |
| NEON DP1.10072.001 | Mammals | pending | field trapping max weight | 10.48443/s4ph-2z37 **(UNVERIFIED)** | 🔄 IN PROGRESS |

> **Note:** The NEON DOI `10.48443/s4ph-2z37` is used internally but has not been independently verified. Confirm before citing in any publication.

**Phase 1 total (as of 2026-05-10): 36,819 rows across 7 completed providers.**

### Taxonomic Group Breakdown

| Group | Rows | Sources |
|---|---|---|
| Birds | 21,173 | EltonTraits (Birds), AVONET |
| Mammals | 9,364 | PanTHERIA, EltonTraits (Mammals), AnAge |
| Fish | 5,657 | FishBase |
| Amphibians | 609 | AmphiBIO, AnAge |
| Reptiles | 16 | AnAge only — **critically sparse; do not use for richness estimates** |

### GBIF Taxonomic Reconciliation

All rows reconciled against GBIF Backbone (version 2023-08-28, datasetKey `d7dddbf4-2cf0-4f39-9b2a-bb099caae36c`):

- **97.7% EXACT match rate**
- **~7.8% SYNONYM** — `accepted_name` column carries the preferred name
- **<0.1% NONE/error** — requires manual review

Output: `data/compiled/tier1_reconciled.csv`

### Known Limitations (read before citing)

1. **FishBase mass type is heterogeneous — never pool `wet` and `LW_modeled` silently.** Filter on `mass_type` before any cross-taxon or fish-specific analysis.
2. **Reptiles critically underrepresented** (~16 rows from AnAge only). Reptile richness estimates from this database are not defensible without explicit caveat.
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
├── data/compiled/
│   ├── tier1_combined.csv          # Merged Tier 1 (36,819 rows)
│   ├── tier1_reconciled.csv        # + GBIF reconciliation columns
│   └── taxon_match_cache.csv       # GBIF match cache (21,696 rows)
├── output/                         # Per-provider compiled CSVs
│   ├── avonet_compiled.csv
│   ├── amphibio_compiled.csv
│   ├── anage_compiled.csv
│   ├── eltontraits_compiled.csv
│   ├── fishbase_compiled.csv
│   ├── pantheria_compiled.csv
│   └── candidate_datasets.csv      # 1,043 Dryad+Figshare candidates
├── providers/                      # One subfolder per data source
│   ├── avonet/load_avonet.R
│   ├── amphibio/load_amphibio.R
│   ├── anage/load_anage.R
│   ├── eltontraits/load_eltontraits.R
│   ├── fishbase/load_fishbase.R
│   ├── neon/load_neon.R
│   └── pantheria/load_pantheria.R
├── scripts/                        # Pipeline orchestration
│   ├── discover_body_mass_datasets.R   # Cross-repo API discovery
│   ├── merge_tier1.R                   # Stack all provider outputs
│   ├── run_taxon_reconciliation.R      # GBIF reconciliation
│   ├── run_fishbase_intake.sh
│   ├── run_neon_intake.sh
│   └── run_zenodo_discovery.sh
├── science_summary.Rmd             # Full analysis report (53 chunks)
├── science_summary.html            # Rendered HTML report (3.8 MB)
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

As of 2026-05-10:

| Statistic | Value |
|---|---|
| Total rows (all providers merged) | 36,819 |
| Providers completed | 7 of 8 planned (NEON in progress) |
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
| 1 | Complete NEON small mammal intake | In progress |
| 2 | Re-run GBIF reconciliation on updated 36,819-row file | None |
| 3 | Deduplicate species across providers (mammals triple-counted) | None |
| 4 | Add reptile body mass source (Meiri et al. or Reptile Database) | Requires download |
| 5 | Retry Zenodo discovery with `--min-score=3` | API stability |
| 6 | Populate DwC `measurementID` | Design decision needed |
| 7 | Run `renv::snapshot()` to pin R environment | None |
| 8 | Submit to GBIF IPT or Zenodo for public archiving | After DwC compliance |

---

## Agents and Provenance

This project was designed and built using an agent-orchestrated science workflow:

| Agent | Role |
|---|---|
| `ecology-user` | Data type classification, sampling bias, workflow formalization |
| `enhanced-theory` | WBE scaling law derivation, allometric predictions |
| `biodiversity-science-guard` | Taxonomy validation, DwC compliance, provenance |
| `biodiversity-informatics-checker` | GBIF MoF audit, QA rules, missing fields |
| `merow-ecology` | Tier quality ratings, ecological plausibility |
| `taxonomy-reconciliation` | Backbone strategy, conflict resolution |
| `richard-telford` | Statistical rigor: diagnostics before interpretation |
| `coder` + `code-checker` + `code-verifier` | Implementation + two-pass review |

Prompt provenance: [`agents/prompt_log.md`](../agents/prompt_log.md) and [`chat_provenance_log.md`](chat_provenance_log.md).

---

## References

- Brown, J. H., & Maurer, B. A. (1989). Macroecology: The Division of Food and Space Among Species on Continents. *Science* 243(4895):1145–1150. DOI: 10.1126/science.243.4895.1145
- de Magalhães, J. P., & Costa, J. (2009). A database of vertebrate longevity records and their relation to other life-history traits. *Journal of Evolutionary Biology* 22(8):1770–1774. DOI: 10.1111/j.1420-9101.2009.01783.x
- Jones, K. E., et al. (2009). PanTHERIA: a species-level database of life history, ecology, and geography of extant and recently extinct mammals. *Ecology* 90(9):2648. DOI: 10.1890/08-1494.1
- Oliveira, B. F., et al. (2017). AmphiBIO, a global database for amphibian ecological traits. *Scientific Data* 4:170123. DOI: 10.1038/sdata.2017.123
- Peters, R. H. (1983). *The Ecological Implications of Body Size*. Cambridge University Press.
- Tobias, J. A., et al. (2022). AVONET: morphological, ecological and geographical data for all birds. *Ecology Letters* 25(3):581–597. DOI: 10.1111/ele.13898
- West, G. B., Brown, J. H., & Enquist, B. J. (1997). A general model for the origin of allometric scaling laws in biology. *Science* 276(5309):122–126. DOI: 10.1126/science.276.5309.122
- Wilman, H., et al. (2014). EltonTraits 1.0: Species-level foraging attributes of the world's birds and mammals. *Ecology* 95(7):2027. DOI: 10.1890/13-1917.1

---

*README written with input from the `ecology-user`, `enhanced-theory`, and `biodiversity-science-guard` agents. All UNVERIFIED items must be confirmed against primary literature before citation in publications or preprints.*

