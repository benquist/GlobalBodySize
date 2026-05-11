# providers/grady2014/data/raw

## Contents

- `grady2014_table_s1.csv` — Table S1 from the supplementary materials of
  Grady et al. 2014 (Science 344:1268-1272, DOI: 10.1126/science.1253143),
  parsed from the PDF supplement `grady.sm.pdf` on 2026-05-11 using the R
  `pdftools` package.

## How this file was created

1. PDF supplement obtained from Science journal website (behind paywall).
2. Text extracted with:
   ```r
   library(pdftools)
   txt <- pdf_text("grady.sm (1).pdf")
   ```
3. Table S1 parsed line-by-line in `/tmp/parse_grady2.R` using 2+ space splits
   as column delimiters. See that script for full parsing logic.
4. 381 rows × 13 columns written to `grady2014_table_s1.csv`.

## Columns

| Column | Description |
|--------|-------------|
| `verbatim_taxon_name` | Species name as printed in Table S1 (φ and * markers stripped) |
| `taxonomic_group` | Section header from Table S1 (Crocodylia, Mesozoic Dinosaurs, etc.) |
| `is_extinct` | TRUE if marked φ in original table |
| `is_mesotherm` | TRUE if marked * (elevated growth rate consistent with endothermy) |
| `metabolic_mass_g` | Body mass (g) at which BMR was measured; often differs from final_adult_mass_g |
| `metabolic_rate_W` | Basal/standard metabolic rate in watts |
| `ta_c` | Ambient temperature (°C) at which BMR was measured |
| `final_adult_mass_g` | Final adult body mass (g) from growth curve asymptote |
| `gmax_g_per_day` | Maximum growth rate (g/day) |
| `r2_growth_curve` | r² of growth curve fit |
| `n_growth_obs` | Number of mass-at-age data points used in growth curve |
| `curve_only` | TRUE if r² and n are from curve fit only (r² shown as "C" in PDF) |
| `equation_only` | TRUE if r² and n are from equation only ("EQ" in PDF) |

## Data notes

- 381 taxa total: 21 extinct (Mesozoic Dinosaurs + extinct Crocodylia + Cretoxyrhina shark)
- 122 taxa have metabolic rate measurements (extant species with BMR data)
- 5 rows are missing `final_adult_mass_g` (parsing artifact; check raw PDF if needed)
- Extinct taxa have growth data from bone histology (osteohistological inference)
- Mesotherms (*): Isurus oxyrinchus (mako shark), Tachyglossus aculeatus (echidna),
  Dermochelys coriacea (leatherback), 4 tuna species (Euthynnus, Katsuwonus, Thunnus spp.)

## Citation

Grady JM, Enquist BJ, Dettweiler-Robinson E, Wright NA, Smith FA (2014)
Evidence for mesothermy in dinosaurs. *Science* 344:1268-1272.
https://doi.org/10.1126/science.1253143
