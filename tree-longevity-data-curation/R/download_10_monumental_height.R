# download_10_monumental_height.R
# Dataset 10: MonumentalTrees — maximum height measurements
# URL: https://www.monumentaltrees.com
# Status: NO direct download. User-contributed data; ToS review mandatory.
# WARNING: Uncertain individual-record provenance.

source(here::here("R", "download_utils.R"))

DATASET_ID   <- "D10"
DATASET_NAME <- "MonumentalTrees max height"
SOURCE_URL   <- "https://www.monumentaltrees.com"
DEST_DIR     <- here::here("data", "raw", "10_monumental_height")
dir.create(DEST_DIR, recursive = TRUE, showWarnings = FALSE)

README_TEXT <- "
# MonumentalTrees.com — Maximum Height Data

URL: https://www.monumentaltrees.com

## Status: MANUAL — ToS review required; uncertain provenance

MonumentalTrees is a community-contributed database of large/tall tree
measurements. It does not provide bulk downloads or an API.

## Critical caveats (biodiversity-science-guard)
- Records are user-submitted; measurement quality is variable and unverified.
- No formal peer review of individual height measurements.
- Provenance of each record (who measured, when, method) is inconsistently
  documented and must be audited per record.
- Do NOT use MonumentalTrees as a primary scientific source without independent
  verification from primary literature or herbarium vouchers.

## Action required before any scraping
1. Review Terms of Service and robots.txt at https://www.monumentaltrees.com/robots.txt
2. Contact site administrator to request bulk data export or formal data collaboration.
3. If scraping is permitted: use `polite` package; rate-limit to >= 5 s per request.
4. Record: species name, height (m), location, measurer (if available), date.
5. Flag all records as 'unverified community observation' in downstream analyses.

## Unit note
Heights appear to be in meters. Verify per record; some entries may mix units.
"
writeLines(README_TEXT, file.path(DEST_DIR, "README_monumental_trees.txt"))

message("D10 MonumentalTrees: MANUAL. ToS review + provenance audit required.")
log_download(DATASET_ID, DATASET_NAME, SOURCE_URL,
             file.path(DEST_DIR, "README_monumental_trees.txt"),
             "NO-DOWNLOAD", NA, NA, "manual — ToS review required",
             "Community-contributed; uncertain per-record provenance. ToS must be reviewed.")
