# BIEN Trait Shiny App

Download, inspect, and export BIEN trait observations for one or more plant species with transparent taxonomy matching, provenance fields, map display, citation export, and reproducible query code.

Live app: https://benquist.shinyapps.io/bien-traits-shinyapp/

## What This App Does

- Queries BIEN trait observations for one or more species.
- Reconciles submitted species names against BIEN taxonomy.
- Shows unfiltered trait observations by default so users can see total data availability first.
- Reports filter coverage so users can decide whether to restrict downloads to non-cultivated, native-only, or geovalid records.
- Exports trait tables, summaries, citations, and an R script to reproduce the query outside the app.

## Repository Structure

- `app.R`: active production Shiny app entrypoint.
- `R/helpers.R`, `R/ui.R`, `R/server.R`: scaffold modules retained from earlier project setup.
- `data/`: optional local sample inputs or small helper files.
- `docs/`: supporting notes and project documentation.
- `www/`: static web assets.
- `deploy.R`: shinyapps.io deployment helper.
- `chat_provenance_log.md`: project-level provenance log.

## Requirements

- R 4.2+ recommended.
- Packages: `shiny`, `BIEN`, `dplyr`, `stringr`, `leaflet`, `DT`, `jsonlite`.
- Internet access, because BIEN queries are executed live.

Install required packages:

```r
install.packages(c("shiny", "BIEN", "dplyr", "stringr", "leaflet", "DT", "jsonlite"))
```

## Run Locally

From R:

```r
shiny::runApp("BIEN-TraitsShinyApp-Project")
```

Or from the shell:

```bash
R -e 'shiny::runApp("BIEN-TraitsShinyApp-Project")'
```

## Tutorial

### 1. Start With a Species Name

Enter one species per line, or separate names with commas or semicolons.

Examples:

```text
Pinus ponderosa
Quercus agrifolia
```

You can also paste mixed common/scientific text such as:

```text
Ponderosa Pine Pinus ponderosa
```

The app will try to recover the scientific binomial before querying BIEN.

### 2. Click Query BIEN

The app will:

1. Parse your species input.
2. Reconcile each species against BIEN taxonomy.
3. Query BIEN trait observations.
4. Display unfiltered trait results first.

If BIEN returns data successfully, the taxonomy table should show the matched or accepted name rather than unresolved fragments.

### 3. Review the Taxonomy Reconciliation Table

Use the taxonomy table to confirm that your species matched correctly.

Expected example for ponderosa pine:

```text
input_name          matched_name        accepted_name      match_status
Pinus ponderosa     Pinus ponderosa     ...                ...
```

If the submitted name is unresolved, inspect the spelling or simplify the input to the scientific binomial.

### 4. Check the Coverage Tab

The Coverage tab reports how many trait records are available:

- with no filters,
- excluding cultivated records,
- native only,
- geovalid only,
- and combinations of those filters.

This is meant to show data availability before you decide how restrictive your export should be.

### 5. Inspect the Trait Data Tab

The Trait Data tab shows:

- raw trait observations,
- a trait summary by species, trait, and unit.

The app shows unfiltered observations here so you can assess total BIEN coverage first.

### 6. Inspect Provenance and Citations

Use the Provenance and citations tab to inspect source-like fields and citation-related metadata before downstream analysis.

This is important because BIEN coverage and metadata completeness vary among taxa and datasets.

### 7. Choose Download Filters

The sidebar filters affect exported data rather than the initial discovery view:

- `Include cultivated records`
- `Native records only`
- `Geovalid coordinates only`

Typical workflow:

1. Query without restricting discovery.
2. Review availability in Coverage and Trait Data.
3. Turn filters on only if they match your analytical goal.
4. Download the filtered export.

### 8. Download Outputs

Available downloads:

- trait observations CSV,
- trait summary CSV,
- citations CSV,
- reproducible R query script.

The query script is useful for documenting the BIEN call used to generate a result set.

## Example Workflow

To retrieve trait data for ponderosa pine:

1. Launch the app.
2. Enter `Pinus ponderosa`.
3. Leave all filter checkboxes unchecked.
4. Click `Query BIEN`.
5. Confirm taxonomy resolution in the Query tab.
6. Confirm non-zero counts in the Coverage tab.
7. Inspect the raw trait rows in Trait Data.
8. Download the CSVs you need.

## Troubleshooting

### Taxonomy table shows unresolved fragments

This usually indicates input parsing or malformed species text. Use a clean scientific binomial such as `Pinus ponderosa` and re-run the query.

### Coverage says no trait observations

Possible causes:

- BIEN returned no records for the submitted taxon string.
- The name did not reconcile correctly.
- A query failed upstream and returned an error.

Check the taxonomy table first. If the taxonomy is wrong, the trait query will also fail.

### Very large species may take longer

High-volume species can return many BIEN trait rows. The app uses a bounded query size to keep the Shiny session responsive.

## Interpretation Notes

- BIEN trait availability varies strongly by species, region, and datasource.
- Absence of returned rows is not biological evidence of no trait information in nature.
- Unit harmonization is limited; inspect units before combining values across studies.
- Filters change the biological meaning of the export, so choose them intentionally.

## Deployment

Deploy from R:

```r
source("BIEN-TraitsShinyApp-Project/deploy.R")
```

The current deployment target is shinyapps.io.

## Citation

Please cite BIEN and the original underlying data sources when using exported trait data in analysis, synthesis, or publication.
