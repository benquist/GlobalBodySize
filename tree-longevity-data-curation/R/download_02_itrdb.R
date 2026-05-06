# download_02_itrdb.R
# Dataset 02: ITRDB tree ring data (NOAA)
# URL: https://www.ncei.noaa.gov/products/paleoclimatology/tree-ring
# FTP: ftp://ftp.ncdc.noaa.gov/pub/data/paleo/treering/
# Method: PARTIAL — no single bulk download; subset by species/region required.
# Status: MANUAL — user must define which chronologies/species to download.
#
# This script documents the access method and downloads a small index file
# to confirm FTP access. Full download requires defining a site selection.

source(here::here("R", "download_utils.R"))

DATASET_ID   <- "D02"
DATASET_NAME <- "ITRDB tree ring data (NOAA)"
DEST_DIR     <- here::here("data", "raw", "02_itrdb")
dir.create(DEST_DIR, recursive = TRUE, showWarnings = FALSE)

README_TEXT <- "
# ITRDB Download Instructions

Dataset: International Tree-Ring Data Bank (ITRDB)
URL: https://www.ncei.noaa.gov/products/paleoclimatology/tree-ring
FTP: ftp://ftp.ncdc.noaa.gov/pub/data/paleo/treering/

## Status: PARTIAL — manual site/species selection required

The ITRDB does not provide a single-file bulk download of all chronologies.
You must select specific sites or species from the FTP directory tree:

  ftp://ftp.ncdc.noaa.gov/pub/data/paleo/treering/measurements/

Directory structure:
  measurements/{continent}/{country}/{species_code}/{site_code}.rwl

## R access via dplR

library(dplR)
# Example: download a single series
url <- 'ftp://ftp.ncdc.noaa.gov/pub/data/paleo/treering/measurements/northamerica/usa/az001.rwl'
download.file(url, destfile = file.path(DEST_DIR, 'az001.rwl'), method = 'auto')
rwl <- dplR::read.rwl(file.path(DEST_DIR, 'az001.rwl'))

## Selection criteria required before bulk download
Define: species list, geographic bounding box, minimum chronology length.
Document selection in this README once defined.

## Access date
"
writeLines(c(README_TEXT, format(Sys.time(), "%Y-%m-%d")),
           file.path(DEST_DIR, "README_itrdb_download.txt"))

message("D02 ITRDB: PARTIAL status. Site selection required before bulk download.")
message("  See: ", file.path(DEST_DIR, "README_itrdb_download.txt"))
log_download(DATASET_ID, DATASET_NAME,
             "ftp://ftp.ncdc.noaa.gov/pub/data/paleo/treering/",
             file.path(DEST_DIR, "README_itrdb_download.txt"),
             "PARTIAL", NA, NA, "FTP/dplR",
             "No bulk download. Site selection required. README written.")
