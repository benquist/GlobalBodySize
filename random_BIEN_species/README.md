# random_BIEN_species

Reproducible R workflow for sampling random plant species from BIEN, cleaning occurrence data, extracting WorldClim climate values, and producing species-level and multi-species climate-space analyses.

This project includes:

1. A single-species pipeline (`scripts/run_pipeline.R`) that draws one random eligible species and generates core outputs.
2. A multi-species ordination report (`multispecies_climate_multivariate_analysis.Rmd`) that samples several eligible species and performs multivariate climate analyses (PCA + constrained ordination with DCA-based method selection).

## Why This Project Exists

The workflow is designed to be simple enough for teaching and robust enough for exploratory ecological analysis:

- Transparent QA filtering with explicit attrition logs.
- Reproducible random selection controlled by a fixed seed.
- Standardized climate extraction using WorldClim BIO layers.
- Interpretable multivariate analyses with permutation-based inference.

## Project Structure

```
random_BIEN_species/
	config.yml
	PROJECT_DESIGN.md
	README.md
	multispecies_climate_multivariate_analysis.Rmd
	R/
		utils.R
		data_access.R
		cleaning.R
		climate.R
		plotting.R
	scripts/
		run_pipeline.R
	outputs/
```

## Dependencies

Install required R packages:

```r
install.packages(c(
	"BIEN", "yaml", "terra", "geodata", "ggplot2",
	"dplyr", "tidyr", "vegan", "rmarkdown", "knitr"
))
```

Notes:

- BIEN API availability is required for full runs.
- WorldClim rasters are cached locally under `outputs/worldclim_cache`.
- No `renv` lockfile is required for this scaffold, but adding one is recommended for publication-grade reproducibility.

## Configuration (`config.yml`)

Main parameters:

- `seed`: random seed for reproducible species draws.
- `min_records`: minimum cleaned occurrences required for eligibility.
- `max_random_attempts`: max random draws before failing.
- `candidate_pool_size`: size of BIEN species pool.
- `occurrence_limit`: cap on records requested per species.
- `worldclim_res`: WorldClim resolution (arc-min; default `10`).
- `bio_vars`: BIO layers used for extraction/plotting.
- `families_pool`: family list used to build candidate species pool.

## Quick Start

From project root:

```bash
cd random_BIEN_species
```

### 1) Validate setup

```bash
Rscript scripts/run_pipeline.R --dry-run
```

### 2) Run single-species pipeline

```bash
Rscript scripts/run_pipeline.R
```

### 3) Render multi-species multivariate report

```bash
Rscript -e "rmarkdown::render('multispecies_climate_multivariate_analysis.Rmd', output_format='html_document')"
```

## Single-Species Outputs

Written to `outputs/`:

- `species_pool.csv`
- `selection_attempts.csv`
- `selected_species.csv`
- `qa_summary.csv`
- `cleaned_occurrences.csv`
- `cleaned_occurrences_with_climate.csv`
- `climate_niche_<bio_x>_vs_<bio_y>.png`
- `worldclim_cache/`

## Multi-Species Report Outputs

The R Markdown report writes:

- `multispecies_climate_multivariate_analysis.html`
- `outputs/multispecies/selection_attempts_multispecies.csv`
- `outputs/multispecies/selected_species_multispecies.csv`
- `outputs/multispecies/occurrences_with_climate_multispecies.csv`
- `outputs/multispecies/method_decision_table.csv`
- `outputs/multispecies/plot_climate_space_facet.png`
- `outputs/multispecies/plot_pca_climate.png`
- `outputs/multispecies/plot_ordination_rda.png` or `outputs/multispecies/plot_ordination_cca.png`

## QA Logic (Occurrence Cleaning)

Current QA steps in `R/cleaning.R`:

1. Remove rows with missing/blank species binomial.
2. Remove rows with missing/non-finite coordinates.
3. Remove out-of-bounds coordinates (lat not in [-90, 90], lon not in [-180, 180]).
4. Remove exact duplicate `(species, latitude, longitude)` records.

The QA attrition trail is recorded in `qa_summary.csv`.

## Multivariate Analysis Logic

The report follows gradient-analysis guidance:

- Compute DCA axis-1 gradient length.
- Use rule-of-thumb decision:
	- `> 4` SD: prefer CCA (unimodal response).
	- `< 2` SD: prefer RDA (linear response).
	- `2-4` SD: compare both and inspect adjusted R2 + permutation tests.
- Use permutation inference (`999` permutations) for constrained ordination significance.

## Ecological Interpretation Notes

- Results represent realized climate niches, not fundamental niches.
- Presence-only records are affected by collection and accessibility bias.
- Spatial uncertainty and cultivated occurrences can broaden apparent climate envelopes.
- Outputs are exploratory and hypothesis-generating unless paired with explicit bias correction and independent validation.

## Core References

- Maitner, B.S., et al. (2018). The BIEN R package: A tool to access the Botanical Information and Ecology Network (BIEN) database. Methods in Ecology and Evolution 9:373-379. https://doi.org/10.1111/2041-210X.12861
- Fick, S.E. and Hijmans, R.J. (2017). WorldClim 2: New 1-km spatial resolution climate surfaces for global land areas. International Journal of Climatology 37:4302-4315. https://doi.org/10.1002/joc.5086
- Zizka, A., et al. (2019). CoordinateCleaner: Standardized cleaning of occurrence records from biological collection databases. Methods in Ecology and Evolution 10:744-751. https://doi.org/10.1111/2041-210X.13152
- ter Braak, C.J.F. (1986). Canonical Correspondence Analysis: a new eigenvector technique for multivariate direct gradient analysis. Ecology 67:1167-1179. https://doi.org/10.2307/1938672
- ter Braak, C.J.F. and Prentice, I.C. (1988). A theory of gradient analysis. Advances in Ecological Research 18:271-317. https://doi.org/10.1016/S0065-2504(08)60183-X
- Legendre, P. and Gallagher, E.D. (2001). Ecologically meaningful transformations for ordination of species data. Oecologia 129:271-280. https://doi.org/10.1007/s004420100716
- Blanchet, F.G., Legendre, P. and Borcard, D. (2008). Forward selection of explanatory variables. Ecology 89:2623-2632. https://doi.org/10.1890/07-0986.1
