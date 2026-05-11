# Animal_scaling_data

Compile multi-trait animal scaling data — body mass, metabolic rate, life history, and growth — from curated public sources for macroecological and physiological scaling analyses.

This project is complementary to `GlobalBodySize` (body-mass focused) but broader in scope: it targets scaling relationships across physiology and life history, spanning vertebrates and key invertebrate groups.

---

## Directory structure

```
Animal_scaling_data/
  R/
    animal_scaling_schema.R      # Canonical output schema and helper functions
  providers/
    animaltraits/
      load_animaltraits.R        # AnimalTraits intake (Zenodo 6468938)
    pnas_2303764120/
      load_pnas_2303764120.R     # PNAS 2303764120 supplementary data intake
  scripts/
    merge_providers.R            # Merge all provider outputs
    run_all_intake.R             # Wrapper to run all intake scripts
  data/
    raw/                         # Raw downloaded files (not tracked by git)
    compiled/                    # Final merged dataset
  output/                        # Per-provider compiled CSVs and logs
  README.md
  chat_provenance_log.md
  .gitignore
```

---

## Data sources

### 1. AnimalTraits (Herberstein et al. 2022)

> Herberstein ME, McLean DJ, Lowe E, Wolff JO, Khan MK, Smith K, ... Carthey AJR.  
> 2022. AnimalTraits — a curated animal trait database for body mass, metabolic rate and brain size.  
> *Scientific Data* 9(1):265.  
> DOI: [10.1038/s41597-022-01364-9](https://doi.org/10.1038/s41597-022-01364-9)  
> Data DOI: [10.5281/zenodo.6468938](https://doi.org/10.5281/zenodo.6468938)

- Coverage: vertebrates (Mammalia, Aves, Reptilia, Amphibia) and invertebrates (Insecta, Arachnida, Malacostraca, Chilopoda, Diplopoda, Clitellata, Polychaeta, Gastropoda, Bivalvia)
- Traits: body mass (kg, converted to g), metabolic rate, brain mass
- License: public domain waiver (CC0)
- Download: automatic via `run_animaltraits_intake()`

### 2. PNAS 2303764120 supplementary data (2023)

> See article: [10.1073/pnas.2303764120](https://doi.org/10.1073/pnas.2303764120)  
> Supplementary datasets SD01 (main traits) and SD02 (metadata/secondary).

- Traits: body mass, metabolic rate, life history (check article for full scope)
- **Manual placement required** — see Quick Start below
- License: check the PNAS article's data availability statement

---

## Quick Start

### Run all providers (AnimalTraits auto-downloads; PNAS requires manual file placement)

```r
# From the project root: /Users/brianjenquist/VSCode/Animal_scaling_data
setwd("Animal_scaling_data")
Rscript scripts/run_all_intake.R
```

### Run AnimalTraits only

```r
setwd("Animal_scaling_data")
Rscript -e "source('providers/animaltraits/load_animaltraits.R'); run_animaltraits_intake()"
```

### PNAS 2303764120 — manual file placement

1. Download SD01 and SD02 Excel files from <https://doi.org/10.1073/pnas.2303764120>
2. Rename them:
   - `pnas_2303764120_sd01.xlsx`
   - `pnas_2303764120_sd02.xlsx`
3. Place both files in `providers/pnas_2303764120/data/raw/`
4. Run:

```r
setwd("Animal_scaling_data")
Rscript -e "source('providers/pnas_2303764120/load_pnas_2303764120.R'); run_pnas_intake()"
```

### Merge all available providers

```r
setwd("Animal_scaling_data")
Rscript scripts/merge_providers.R
```

The merged output is written to `data/compiled/animal_scaling_compiled.csv`.

---

## Output schema

The compiled table follows the canonical schema defined in `R/animal_scaling_schema.R`. Key columns:

| Column | Description |
|---|---|
| `source_id` | Stable provider identifier |
| `verbatim_taxon_name` | Species name as in source |
| `body_mass_g` | Body mass in grams |
| `metabolic_rate_value` | Metabolic rate (unit in `metabolic_rate_unit`) |
| `metabolic_rate_type` | "basal" / "standard" / "field" / "resting" / "active" / "unknown" |
| `lifespan_max_years` | Maximum recorded lifespan |
| `age_at_maturity_years` | Age at first reproduction |
| `qa_body_mass_range` | "ok" / "suspect_low" / "suspect_high" / "missing" |

See `R/animal_scaling_schema.R` for the full column list and definitions.

---

## Data use

These data are compiled for research use. Check the license of each individual dataset before redistribution or publication:

- AnimalTraits (Zenodo 6468938): CC0 public domain
- PNAS 2303764120: check the article's data availability statement

Cite both this pipeline and the original data sources in any publication.
