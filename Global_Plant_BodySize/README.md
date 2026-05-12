# Global_Plant_BodySize

**A reproducible, provenance-rich plant body size database for all BIEN vascular plant species (~150,000 species).**

[![Phase](https://img.shields.io/badge/Phase-1%20Pipeline%20Design-blue)]()
[![Source](https://img.shields.io/badge/Source-BIEN%20v4.x-green)]()
[![Coverage](https://img.shields.io/badge/Coverage-New%20World%20Vascular%20Plants-orange)]()

Plant body size — height, stem diameter, growth form — determines light capture, above-ground biomass, hydraulic architecture, and competitive outcomes across all terrestrial biomes. This project assembles a unified, Darwin Core-compatible plant body size database from the Botanical Information and Ecology Network (BIEN), designed for macroecological scaling analyses, trait-based species distribution models, and community-weighted mean calculations.

---

## Ecological Rationale

Plant height is a primary axis of the plant economics spectrum (Wright et al. 2004; Díaz et al. 2016). Across six orders of magnitude — from *Wolffia* (1 mm) to *Sequoia sempervirens* (116 m) — height integrates competitive ability, life history strategy, and ecosystem function:

- **Light capture**: taller plants preempt light for shorter neighbors, driving successional dynamics
- **Above-ground biomass**: height + DBH enable allometric AGB estimation (Chave et al. 2014)
- **Hydraulic limits**: maximum tree height is mechanistically constrained by hydraulic path length (~130 m; Koch et al. 2004)
- **Community structure**: community-weighted mean height predicts canopy carbon storage and albedo
- **Macroecological gradients**: plant height increases toward the equator and in high-rainfall biomes (Moles et al. 2009)

---

## Data Source

**BIEN (Botanical Information and Ecology Network)**  
- Coverage: New World (North, Central, South America + Caribbean)  
- Species: ~150,000 vascular plant species  
- Traits used: `whole plant height`, `stem diameter or width`, `growth form`  
- Access: R package `BIEN` — `BIEN_trait_traitname()`  
- Citation: Maitner et al. (2018) Methods Ecol Evol — **UNVERIFIED DOI: confirm before publication**

**BIEN does NOT contain bryophytes.** The `is_bryophyte` flag is a placeholder for future integration.

---

## Special Group Handling

| Group | Detection Method | Notes |
|-------|-----------------|-------|
| Graminoid | Family ∈ {Poaceae, Cyperaceae, Juncaceae} | Family-based flag takes priority over BIEN growth form string |
| Bamboo | Subfamily == Bambusoideae OR genus ∈ curated list | BIEN rarely returns subfamily; genus list in `R/growth_form_vocab.R` |
| Herb | BIEN growth form string → mapped | Includes ferns, succulents, cacti |
| Bryophyte | Always `FALSE` for BIEN | Mosses, liverworts, hornworts absent from BIEN |

---

## Project Structure

```
Global_Plant_BodySize/
├── R/
│   ├── plant_size_schema.R         # Schema, vocabulary, range limits
│   ├── growth_form_vocab.R         # Growth form map, graminoid/bamboo flags
│   └── qa_checks_plants.R          # Range, unit, outlier QA functions
├── providers/
│   └── bien/
│       ├── load_bien_species.R     # Stage 1: species list
│       └── load_bien_traits.R      # Stages 2–3: trait queries
├── scripts/
│   ├── 01_species_list.R           # BIEN species roster
│   ├── 02_trait_query.R            # Height + DBH bulk queries
│   ├── 03_growth_form_query.R      # Growth form bulk query
│   ├── 04_taxonomy_reconcile.R     # Taxonomy cross-check + enrichment
│   ├── 05_reconcile_growth_form.R  # Canonical GF + graminoid/bamboo flags
│   ├── 06_qa_checks.R              # Range, unit, outlier checks
│   ├── 07_summarize.R              # Species-level statistics
│   └── 08_finalize.R               # Full roster join + coverage report
└── output/
    ├── bien_species_list.csv        # All BIEN species (Stage 1)
    ├── bien_height_raw.csv          # Raw height records (Stage 2)
    ├── bien_dbh_raw.csv             # Raw DBH records (Stage 2)
    ├── bien_growth_form_raw.csv     # Raw growth form records (Stage 3)
    ├── bien_species_roster.csv      # Taxonomy-enriched species list (Stage 4)
    ├── taxonomy_reconciliation_report.csv
    ├── bien_growth_form_reconciled.csv  # Mapped growth forms (Stage 5)
    ├── species_growth_form.csv          # Modal GF per species (Stage 5)
    ├── bien_height_qa.csv           # QA-flagged height records (Stage 6)
    ├── bien_dbh_qa.csv              # QA-flagged DBH records (Stage 6)
    ├── qa_summary_report.csv        # QA pass rates (Stage 6)
    ├── plant_size_summary.csv       # Species-level statistics (Stage 7)
    ├── plant_bodysize_final.csv     # FINAL DATABASE — all species (Stage 8)
    ├── coverage_by_group.csv        # Coverage by higher_plant_group (Stage 8)
    └── coverage_by_family.csv       # Coverage by family top-50 (Stage 8)
```

---

## Quick Start

```r
# Install BIEN if needed
install.packages("BIEN")
install.packages(c("data.table", "dplyr"))

# Run from project root (Global_Plant_BodySize/)
Rscript scripts/01_species_list.R
Rscript scripts/02_trait_query.R      # ~30–90 min total BIEN query time
Rscript scripts/03_growth_form_query.R
Rscript scripts/04_taxonomy_reconcile.R
Rscript scripts/05_reconcile_growth_form.R
Rscript scripts/06_qa_checks.R
Rscript scripts/07_summarize.R
Rscript scripts/08_finalize.R
```

All scripts cache intermediate files — re-runs skip completed stages unless `--overwrite` is passed.

---

## Pipeline Architecture

```
Stage 1  BIEN_species_list()
           │
           ▼ bien_species_list.csv (all ~150k spp)
Stage 2  BIEN_trait_traitname("whole plant height")
         BIEN_trait_traitname("stem diameter or width")
           │
           ▼ bien_height_raw.csv, bien_dbh_raw.csv
Stage 3  BIEN_trait_traitname("growth form")
           │
           ▼ bien_growth_form_raw.csv
Stage 4  Taxonomy cross-check + enrichment
           │
           ▼ bien_species_roster.csv
Stage 5  Growth form reconciliation + graminoid/bamboo flags
           │
           ▼ species_growth_form.csv
Stage 6  QA: range check + unit check + outlier detection
           │
           ▼ bien_height_qa.csv, bien_dbh_qa.csv
Stage 7  Species-level aggregation (n, mean, sd, CV, confidence tier)
           │
           ▼ plant_size_summary.csv
Stage 8  Full roster left-join → ALL species retained (no-data = NA)
           │
           ▼ plant_bodysize_final.csv  ← FINAL OUTPUT
```

---

## QA Framework

| Check | Method | Action on Fail |
|-------|--------|----------------|
| Range check | Growth-form-specific height/DBH limits | `range_check_pass = FALSE`; record retained |
| Unit check | Canonical unit must match measurement type | `unit_check_pass = FALSE`; record retained |
| Outlier detection | Log₁₀-scale z-score \|z\| > 3 within (growth form × higher_plant_group) | `outlier_flag = TRUE`; included in summary by default |

Species-level confidence tiers: **high** (n ≥ 5), **medium** (n = 2–4), **low** (n = 1), **none** (n = 0).

---

## Key Scientific Caveats

1. **BIEN coverage is uneven**: well-studied tropical trees are over-represented relative to pteridophytes, gymnosperms, and graminoids.
2. **Height ≠ maximum height**: BIEN records are population-level observations, often from juvenile or subcanopy individuals. Mean height may underestimate species maximum.
3. **Bamboo genus list is not exhaustive**: ~1,400 bamboo species exist; the curated genus list in `growth_form_vocab.R` covers major genera but confirm before publication.
4. **BIEN citation DOI is UNVERIFIED**: confirm Maitner et al. (2018) DOI via CrossRef before citing.
5. **No bryophytes**: BIEN is vascular plants only; `is_bryophyte = FALSE` for all records.

---

## Expansion Opportunities

1. **Height × climate gradients**: join `plant_bodysize_final.csv` with WorldClim/CHELSA → test Moles et al. (2009) global height gradient predictions
2. **Phylogenetic imputation**: impute missing heights using PGLS on Open Tree of Life phylogeny for data-poor families
3. **Community-weighted mean height**: combine BIEN plot data with species height summaries to map CWM across New World biomes
4. **TRY cross-validation**: compare BIEN heights against TRY database (Kattge et al. 2020) for overlapping species — quantify source bias
5. **Allometric AGB estimation**: for `allometric_ready = TRUE` species, apply Chave et al. (2014) equations to estimate above-ground biomass from height + DBH

---

## References

- Chave J, et al. (2014). Improved allometric models to estimate the aboveground biomass of tropical trees. Global Change Biology 20(10):3177-3190.
- Díaz S, et al. (2016). The global spectrum of plant form and function. Nature 529:167-171.
- Koch GW, et al. (2004). The limits to tree height. Nature 428:851-854.
- Maitner BS, et al. (2018). The BIEN package. Methods Ecol Evol. [UNVERIFIED DOI]
- Moles AT, et al. (2009). Global patterns in plant height. Journal of Ecology 97(5):923-932.
- Wright IJ, et al. (2004). The worldwide leaf economics spectrum. Nature 428:821-827.

**All citations should be verified against CrossRef before publication.**
