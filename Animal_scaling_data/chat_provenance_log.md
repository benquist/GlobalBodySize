# Chat Provenance Log — Animal_scaling_data

---

## 2026-05-11

**Prompt:** Create Animal_scaling_data project with intake scripts for AnimalTraits (zenodo 6468938), PNAS 2303764120 supplementary data. Project focuses on body mass, metabolic rate, life history, and growth data for animal scaling analyses.

**Changes:** Created project scaffold, R/animal_scaling_schema.R, providers/animaltraits/load_animaltraits.R, providers/pnas_2303764120/load_pnas_2303764120.R, scripts/merge_providers.R, scripts/run_all_intake.R, README.md.

---

## 2026-05-11 (continued)

**Prompt:** Add Hatton et al. 2019 "Linking scaling laws across eukaryotes" (PNAS 116:21616; Zenodo 3145281) as a new provider. Also add Hatton et al. 2015 "The predator-prey power law" (Science 349:aac6284; user-provided database_s1.xls) and Hatton et al. 2021 ocean size spectrum (Sci Adv 7:eabh3732 — data not yet publicly resolved). Create animal_scaling_summary.Rmd/.html scientific summary of scaling relationships.

**Changes:**
- `providers/hatton2019/load_hatton2019.R` — new intake for Hatton 2019 (8,098 metabolic + lifespan + growth rows); downloads Link-scaling.zip from Zenodo 3145281; produces `output/hatton2019_compiled.csv`
- `providers/hatton2015/load_hatton2015.R` — new intake for Hatton 2015 predator-prey body mass pairs (1,705 rows, user-provided XLS); produces `output/hatton2015_compiled.csv` with extra column `predator_mass_g_paired`
- `scripts/run_all_intake.R` — updated to include Hatton 2019 and Hatton 2015 providers (5 total)
- `scripts/merge_providers.R` — updated OPTIONAL_PROVIDERS to include hatton2019 and hatton2015 outputs
- `animal_scaling_summary.Rmd` + `animal_scaling_summary.html` — 8-section scientific summary: WBE theory background, data coverage QA, metabolic scaling (B ∝ M^3/4), lifespan scaling (L ∝ M^1/4), growth rate scaling, predator-prey mass scaling, cross-dataset synthesis, and provenance/citations. Reviewed by biodiversity-science-guard; 6 fixes applied (QA transparency, temperature normalization caveat, Kleiber claim precision, DOIs, min_n standardized to 10, phylogenetic non-independence caveat).
- Hatton 2021 (ocean size spectrum): data repository not resolved during session — Science Advances supplement requires institutional access; placeholder provider directory created at `providers/hatton2021/data/raw/`
