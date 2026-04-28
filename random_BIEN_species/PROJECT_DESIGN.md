# PROJECT_DESIGN

## Modeling Objective

Create a simple, reproducible workflow that samples one species from BIEN, filters occurrence records with explicit QA, links each point to WorldClim BIO predictors, and visualizes the realized climate niche in 2D climate space.

## Assumptions

- BIEN APIs are online and return occurrence/taxonomy records.
- BIEN occurrence tables include a species field and coordinate fields that can be normalized.
- WorldClim BIO rasters at selected resolution are suitable for coarse niche-space summaries.
- Eligibility is defined pragmatically as at least `min_records` after QA.

## Risks

- BIEN service downtime or API schema drift can break record retrieval.
- Random draw may repeatedly select species with sparse usable records.
- Coordinates may have residual uncertainty not detected by basic QA filters.
- Climate niche plots are descriptive and should not be interpreted as mechanistic models.

## Workflow

1. Build a candidate species pool from BIEN family taxonomy queries.
2. Randomly draw species with bounded retries.
3. Download occurrence records for each draw.
4. Apply transparent QA filters and count retained records.
5. Select first species that passes the minimum cleaned-record threshold.
6. Download/read WorldClim BIO rasters and extract values at occurrence points.
7. Save intermediate CSVs and produce a BIO1 vs BIO12 climate-space figure.

## Diagnostics

- `outputs/selection_attempts.csv`: each draw with raw and cleaned counts.
- `outputs/qa_summary.csv`: QA attrition by filter step.
- `outputs/selected_species.csv`: selected species and retained sample size.
- `outputs/cleaned_occurrences_with_climate.csv`: final analysis table.
- Climate-space PNG with binned density and contour overlay.

## Key Citations

- Maitner, B. S., et al. (2018). The BIEN R package: A tool to access the Botanical Information and Ecology Network (BIEN) database. Methods in Ecology and Evolution, 9, 373-379. https://doi.org/10.1111/2041-210X.12861
- Enquist, B. J., et al. (2016). The commonness of rarity: Global and future distribution of rarity across land plants. Science Advances, 5(11), eaaz0414. https://doi.org/10.1126/sciadv.aaz0414
- Fick, S. E., and Hijmans, R. J. (2017). WorldClim 2: New 1-km spatial resolution climate surfaces for global land areas. International Journal of Climatology, 37, 4302-4315. https://doi.org/10.1002/joc.5086
- Zizka, A., et al. (2019). CoordinateCleaner: Standardized cleaning of occurrence records from biological collection databases. Methods in Ecology and Evolution, 10, 744-751. https://doi.org/10.1111/2041-210X.13152
- Elith, J., and Leathwick, J. R. (2009). Species distribution models: Ecological explanation and prediction across space and time. Annual Review of Ecology, Evolution, and Systematics, 40, 677-697. https://doi.org/10.1146/annurev.ecolsys.110308.120159
- Franklin, J. (2010). Mapping Species Distributions: Spatial Inference and Prediction. Cambridge University Press. https://doi.org/10.1017/CBO9780511810602
