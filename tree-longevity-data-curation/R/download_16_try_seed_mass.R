# download_16_try_seed_mass.R
# Dataset 16: Seed mass — TRY database request No. 30569
# URL: https://www.try-db.org/TryWeb/dp.php
# Status: NO — requires free account registration + formal request submission.
# CRITICAL: TRY data CANNOT be redistributed. Do not commit to git.

source(here::here("R", "download_utils.R"))

DATASET_ID   <- "D16"
DATASET_NAME <- "Seed mass — TRY database request 30569"
SOURCE_URL   <- "https://www.try-db.org/TryWeb/dp.php"
DEST_DIR     <- here::here("data", "raw", "16_try_seed_mass")
dir.create(DEST_DIR, recursive = TRUE, showWarnings = FALSE)

README_TEXT <- "
# TRY Plant Trait Database — Seed Mass Data

URL: https://www.try-db.org
Citation: Kattge J et al. (2020) TRY plant trait database — enhanced coverage and
          open access. Global Change Biology 26:119–188.
          https://doi.org/10.1111/gcb.14904

## Status: MANUAL — registration + formal data request required

TRY data cannot be downloaded without:
1. Creating a free account at https://www.try-db.org/TryWeb/dp.php
2. Submitting a formal data request (describing intended use)
3. Waiting for approval (typically days to weeks)
4. Downloading the approved dataset from the confirmation email link

## Reference request
The original study used TRY request No. 30569. This is a SPECIFIC approved
request and cannot be re-used by others without submitting a new request.

## Steps to obtain your own download
1. Register at: https://www.try-db.org/TryWeb/Account/Register
2. Submit a new request at: https://www.try-db.org/TryWeb/dp.php
   - Select trait: Seed mass (TraitID 26) or Diaspore mass (TraitID 4)
   - Specify taxon scope (trees, gymnosperms, angiosperms)
3. Record: request ID, submission date, approval date, download date,
   TRY database version, and trait IDs selected.
4. Save downloaded file to: data/raw/16_try_seed_mass/
   File name format from TRY: {request_id}_{YYYY-MM-DD}.txt (tab-delimited)

## DATA REDISTRIBUTION RESTRICTION
TRY data may NOT be redistributed. This folder is gitignored.
Provide only: request ID, TRY version, submission date, and trait IDs in catalog.

## Key TRY column names (tab-delimited output)
DatasetID, Dataset, SpeciesName, AccSpeciesName, TraitID, TraitName,
OrigValueStr, OrigUnitStr, StdValue, UnitName, ObsDataID, Reference

## Unit note
TRY seed mass: standard unit is mg (dry mass). Some records report g.
Check UnitName column; do not assume mg without verification.
"
writeLines(README_TEXT, file.path(DEST_DIR, "README_try_seed_mass.txt"))

message("D16 TRY seed mass: NO automated download. Registration + request required.")
message("  See: ", file.path(DEST_DIR, "README_try_seed_mass.txt"))
log_download(DATASET_ID, DATASET_NAME, SOURCE_URL,
             file.path(DEST_DIR, "README_try_seed_mass.txt"),
             "NO-DOWNLOAD", NA, NA, "manual — TRY registration required",
             "Request 30569 is study-specific. New request needed. Cannot redistribute.")
