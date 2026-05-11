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

---

## 2026-05-11 (allometric scaling analysis)

**Prompt:** "For the Animal Scaling Data project - I would like to use these data sets to assess the allometric scaling of metabolism and growth rate with body size. Within and across taxa. I would like to see the analyses broken down by study, all taxa, within family, within species (intraspecific). Provide a separate .rmd and .html files. Use similar methodologies as was done in the other project plant_scaling_data summaries."

**Changes:**
- `animal_allometric_scaling.Rmd` — new 89-chunk R Markdown document with 13 sections: Introduction (WBE theory), Data Coverage, Cross-Study Metabolic Scaling, By Study, By Taxonomic Group, Within Order, Within Family, Intraspecific Scaling, Growth Rate Scaling, Lifespan Scaling, Predator-Prey Mass Scaling, Methods & Caveats, References. Implements OLS + SMA regressions; within-order, within-family, and intraspecific panels; min_n filters; color-blind-safe palettes (viridis/ColorBrewer); kableExtra tables with slope, SE, 95% CI, R². All four compiled datasets used (AnimalTraits, Hoehler 2023 PNAS, Hatton 2019 PNAS, Hatton 2015 Science).
- `animal_allometric_scaling.html` — rendered output (7.3 MB; HTML gitignored).

---

## 2026-05-11 (insect metabolic scaling — Chown 2007)

**Prompt:** "Lets now update the .rmd and .html files associated with this project as well as the analyses in 'Animal Allometric Scaling: Metabolism and Growth Across Taxa'. Include now the insect metabolic scaling relationships"

**Changes:**
- `providers/chown2007/load_chown2007.R` — new provider; parses Appendix S2 of fec1245_supmat.doc (Chown et al. 2007, Funct. Ecol. 21:1023–1033); strips multi-line EndNoteXML citation blobs before field parsing; outputs 346 insect species across 16 orders with columns: species, order, family, wing_status, body_mass_g, metabolic_rate_mW, temperature_C, source; applies Riveros & Enquist 2011 corrections to 3 Coleoptera entries
- `animal_allometric_scaling.Rmd` — ch07 added to `all_list` and `met_sources`; new section "# Insect Metabolic Scaling (Chown 2007, corrected)" with subsections: overall OLS + SMA with WBE 3/4 reference line; within-order scaling (9 orders N≥10, Isoptera highlighted); wing status intercept comparison (winged vs. wingless ANCOVA); Termitidae deviation analysis (scaling with and without Termitidae); within-family OLS (11 families N≥10, Formicidae and Termitidae highlighted); fixed palette size mismatches in scale_colour/fill_manual calls throughout document
- `animal_allometric_scaling.html` — re-rendered successfully (11 MB); HTML timestamp 2026-05-11 14:34
- Committed as 91f8e00 and pushed to origin/master
