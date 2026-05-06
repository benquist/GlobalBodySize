# download_09_conifers_height.R
# Dataset 09: Conifer maximum height — conifers.org
# URL: https://www.conifers.org
# Status: NO direct download. Per-species page scraping is theoretically feasible
#         but requires: ToS review, rate limiting, ~900 page requests.
# Action required: review ToS at https://www.conifers.org before any scraping.

source(here::here("R", "download_utils.R"))

DATASET_ID   <- "D09"
DATASET_NAME <- "Conifer max height — conifers.org"
SOURCE_URL   <- "https://www.conifers.org"
DEST_DIR     <- here::here("data", "raw", "09_conifers_height")
dir.create(DEST_DIR, recursive = TRUE, showWarnings = FALSE)

README_TEXT <- "
# conifers.org — Maximum Height Data

URL: https://www.conifers.org
Maintainer: Gymnosperm Database (Christopher J. Earle)

## Status: MANUAL — ToS review required before any scraping

conifers.org provides per-species pages with height data but no bulk download
or public API.

## Scraping requirements (do NOT proceed without completing these)
1. Review ToS / robots.txt at https://www.conifers.org/robots.txt
2. If scraping is permitted: use the R `polite` package (enforces robots.txt
   compliance and rate limiting). Do not use bare rvest without rate control.
3. Approximate scope: ~900 species × 1 page = 900 requests. Minimum delay: 5 s.
4. Extract: species name, max height (m), native range, reference.
5. Archive raw HTML for each species page alongside the extracted CSV.
6. Record: scrape date, polite::bow() session, n_species, n_missing_height.

## Alternative
Contact Christopher J. Earle (cearle@xericdesign.com) to request a bulk export.

## Unit note
Heights on conifers.org are reported in meters (m). Verify unit per record.
"
writeLines(README_TEXT, file.path(DEST_DIR, "README_conifers_height.txt"))

message("D09 conifers.org: ToS review required before scraping. README written.")
log_download(DATASET_ID, DATASET_NAME, SOURCE_URL,
             file.path(DEST_DIR, "README_conifers_height.txt"),
             "NO-DOWNLOAD", NA, NA, "manual — ToS review required",
             "Per-species page scraping possible but ToS must be reviewed first.")
