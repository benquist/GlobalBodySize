# download_14_p50_sci_advances.R
# Dataset 14: P50 + HSM — Science Advances supplementary data
# Paper DOI: https://doi.org/10.1126/sciadv.aav1332
# Status: PARTIAL — supplementary file URL must be located manually from paper landing page.
# May require institutional access.
# WARNING: AAAS/Science Advances CDN URLs for supplementary files are not stable.

source(here::here("R", "download_utils.R"))

DATASET_ID   <- "D14"
DATASET_NAME <- "P50 + HSM — Science Advances (aav1332) supplementary"
PAPER_DOI    <- "https://doi.org/10.1126/sciadv.aav1332"
DEST_DIR     <- here::here("data", "raw", "14_p50_sci_advances")
dir.create(DEST_DIR, recursive = TRUE, showWarnings = FALSE)

README_TEXT <- "
# Science Advances aav1332 — Supplementary Data

Paper: Choat et al. (2018) Triggers of tree mortality under drought.
       Science Advances 4(1): eaav1332
Paper DOI: https://doi.org/10.1126/sciadv.aav1332

## Status: PARTIAL — manual supplementary file retrieval required

Supplementary data files at AAAS/Science Advances are served from CDN URLs
that are not stable across time and are not listed in any public API.

## Steps to obtain the data
1. Navigate to: https://doi.org/10.1126/sciadv.aav1332
2. Locate the 'Supplementary Materials' section.
3. Download the supplementary data file(s) (typically Excel or CSV).
4. Save to: data/raw/14_p50_sci_advances/
5. Record: filename, download date, institutional access required (yes/no).

## Access note
May require institutional journal access. Check if open-access copy is
available on bioRxiv, ResearchGate, or the author's institutional page.
Authors: Choat B et al.

## P50 sign convention audit (CRITICAL before joining with D13)
Science Advances aav1332 may use positive or negative MPa convention for P50.
After download, run:
  source('R/qa_utils.R')
  check_p50_sign(df$P50, 'D14', 'P50+HSM SciAdv aav1332')
Compare result with D13 (Dryad) convention before merging.

## Unit note
P50: MPa (sign convention TBD — see above)
HSM (Hydraulic Safety Margin): MPa
"
writeLines(README_TEXT, file.path(DEST_DIR, "README_p50_sci_advances.txt"))

message("D14 Science Advances: PARTIAL. Manual supplementary download required.")
log_download(DATASET_ID, DATASET_NAME, PAPER_DOI,
             file.path(DEST_DIR, "README_p50_sci_advances.txt"),
             "PARTIAL", NA, NA, "manual — CDN URL unstable",
             "Supplementary file must be located and downloaded manually from paper page.")
