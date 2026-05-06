# download_07_oldgrowth_canada.R
# Dataset 07: Old Growth Canada — old trees records
# URL: https://www.oldgrowth.ca/oldtrees/
# Status: NO — records appear as HTML text/galleries; no bulk download available.
# Action required: contact site maintainers or manually extract records.

source(here::here("R", "download_utils.R"))

DATASET_ID   <- "D07"
DATASET_NAME <- "Old Growth Canada — old trees"
SOURCE_URL   <- "https://www.oldgrowth.ca/oldtrees/"
DEST_DIR     <- here::here("data", "raw", "07_oldgrowth_canada")
dir.create(DEST_DIR, recursive = TRUE, showWarnings = FALSE)

README_TEXT <- "
# Old Growth Canada — Download Instructions

Dataset: Old trees records from OldGrowth.ca
URL: https://www.oldgrowth.ca/oldtrees/

## Status: MANUAL — no structured download available

The website presents individual tree records as HTML text or image galleries
with no bulk download endpoint and no API.

## Action required
1. Review the website to assess the number of records.
2. Contact site maintainers (https://www.oldgrowth.ca/contact/) to request
   a structured data export (CSV/Excel).
3. If contacting maintainers, cite intended use and request attribution terms.
4. If manual extraction is required, document: field names used, extraction
   date, number of records, and any quality notes.

## Provenance note
This source has no DOI or persistent identifier. Archive the raw HTML of the
data pages alongside any extracted data. Record scrape/access date.
"
writeLines(README_TEXT, file.path(DEST_DIR, "README_oldgrowth_canada.txt"))

message("D07 Old Growth Canada: MANUAL status. Contact maintainers required.")
log_download(DATASET_ID, DATASET_NAME, SOURCE_URL,
             file.path(DEST_DIR, "README_oldgrowth_canada.txt"),
             "NO-DOWNLOAD", NA, NA, "manual",
             "No structured bulk download. Maintainer contact required.")
