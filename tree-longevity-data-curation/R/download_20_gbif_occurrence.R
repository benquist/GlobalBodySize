# download_20_gbif_occurrence.R
# Dataset 20: GBIF species occurrence — prepared download dl.77gcvq
# DOI: https://doi.org/10.15468/dl.77gcvq
# Method: rgbif::occ_download_get() OR direct curl of GBIF download ZIP
# WARNING: GBIF prepared downloads expire after ~6 months. Verify first.

source(here::here("R", "download_utils.R"))

DATASET_ID    <- "D20"
DATASET_NAME  <- "GBIF species occurrence (dl.77gcvq)"
DOWNLOAD_KEY  <- "dl.77gcvq"
SOURCE_URL    <- paste0("https://doi.org/10.15468/", DOWNLOAD_KEY)
DEST_DIR      <- here::here("data", "raw", "20_gbif_occurrence")
dir.create(DEST_DIR, recursive = TRUE, showWarnings = FALSE)

README_TEXT <- "
# GBIF Species Occurrence — Download dl.77gcvq

DOI: https://doi.org/10.15468/dl.77gcvq
Download key: dl.77gcvq

## IMPORTANT: GBIF prepared downloads expire after ~6 months
Verify this download is still available before running the script:
  https://www.gbif.org/occurrence/download/dl.77gcvq

## To re-download if expired
GBIF requires an account for new download requests. Steps:
1. Register at https://www.gbif.org/user/profile
2. Set credentials in .Renviron:
     GBIF_USER=your_username
     GBIF_PWD=your_password
     GBIF_EMAIL=your@email.com
3. Submit a new download request using rgbif:

library(rgbif)
# Example filter (replace with the original study's filter criteria):
dl <- occ_download(
  pred('taxonKey', <taxon_key>),       # specify taxon
  pred('hasCoordinate', TRUE),
  pred('hasGeospatialIssue', FALSE),
  format = 'SIMPLE_CSV'
)
occ_download_wait(dl)
occ_download_get(dl[1], path = 'data/raw/20_gbif_occurrence/')

## REQUIRED: Document the original download filter criteria
The catalog entry for D20 MUST record:
  - Taxon key(s) or species list used
  - Coordinate filters applied
  - Date range filter
  - basisOfRecord filter (e.g., PRESERVED_SPECIMEN, HUMAN_OBSERVATION)
  - Any spatial bounding box
  - GBIF issues excluded
  - Download date of original dl.77gcvq
Without this, the download cannot be reproduced.

## File format
Darwin Core Archive (ZIP containing occurrence.txt, meta.xml, eml.xml)
Parse with: readr::read_tsv('occurrence.txt') or rgbif::occ_download_import()
"
writeLines(README_TEXT, file.path(DEST_DIR, "README_gbif_occurrence.txt"))

# Attempt to download the existing prepared download
tryCatch({
  if (!requireNamespace("rgbif", quietly = TRUE)) {
    stop("Package 'rgbif' required. Install with: install.packages('rgbif')",
         call. = FALSE)
  }
  library(rgbif)

  local_zip <- file.path(DEST_DIR, paste0(DOWNLOAD_KEY, ".zip"))
  message("Attempting to retrieve GBIF download: ", DOWNLOAD_KEY)
  message("  Checking availability at: https://www.gbif.org/occurrence/download/",
          DOWNLOAD_KEY)

  # Try to get download metadata first
  dl_meta <- tryCatch(
    rgbif::occ_download_meta(DOWNLOAD_KEY),
    error = function(e) NULL
  )

  if (is.null(dl_meta)) {
    stop("Could not retrieve metadata for download key ", DOWNLOAD_KEY,
         ". The download may have expired (>6 months old). ",
         "See README for re-download instructions.", call. = FALSE)
  }

  status <- dl_meta$status
  message("  Download status: ", status)

  if (status != "SUCCEEDED") {
    stop("Download status is '", status, "' — not SUCCEEDED. Cannot download.",
         call. = FALSE)
  }

  message("  Downloading ZIP (~may be large)...")
  rgbif::occ_download_get(DOWNLOAD_KEY, path = DEST_DIR, overwrite = FALSE)

  # Find the downloaded file
  zip_files <- list.files(DEST_DIR, pattern = "\\.zip$", full.names = TRUE)
  if (length(zip_files) == 0L) {
    stop("Download appeared to succeed but no ZIP found in ", DEST_DIR)
  }
  local_zip <- zip_files[1]
  mf <- write_manifest(local_zip, SOURCE_URL, "rgbif::occ_download_get",
                       paste0("download_key=", DOWNLOAD_KEY,
                              "; n_records=", dl_meta$totalRecords))
  log_download(DATASET_ID, DATASET_NAME, SOURCE_URL, local_zip,
               200, mf$size, mf$hash, "rgbif::occ_download_get",
               paste0("n_records=", dl_meta$totalRecords,
                      "; FILTER CRITERIA MUST BE DOCUMENTED — see README"))

}, error = function(e) {
  message("DOWNLOAD FAILED or EXPIRED for ", DATASET_NAME, ":\n  ",
          conditionMessage(e))
  message("  Action: verify at https://www.gbif.org/occurrence/download/",
          DOWNLOAD_KEY)
  message("  If expired: submit a new download request. See README for steps.")
  log_download(DATASET_ID, DATASET_NAME, SOURCE_URL, DEST_DIR,
               "FAILED", NA, NA, "rgbif::occ_download_get",
               paste("FAILED:", conditionMessage(e),
                     "| Likely expired. Re-download required."))
})
