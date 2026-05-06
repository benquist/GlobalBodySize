# download_17_treegOER_climate.R
# Dataset 17: TreeGOER species-level climate and soil data (Zenodo 10008994)
# URL: https://zenodo.org/records/10008994
# Method: Zenodo REST API v1

source(here::here("R", "download_utils.R"))

DATASET_ID   <- "D17"
DATASET_NAME <- "TreeGOER climate/soil (Zenodo 10008994)"
RECORD_ID    <- "10008994"
DEST_DIR     <- here::here("data", "raw", "17_treegOER_climate")

# NOTE (biodiversity-informatics-checker):
# Verify that TreeGOER reports species-level MEAN climate values, not raw
# occurrence grid values. Unit audit required for all soil variables.
tryCatch(
  download_zenodo(RECORD_ID, DEST_DIR, DATASET_ID, DATASET_NAME),
  error = function(e) {
    message("DOWNLOAD FAILED for ", DATASET_NAME, ":\n  ", conditionMessage(e))
    log_download(DATASET_ID, DATASET_NAME,
                 paste0("https://zenodo.org/api/records/", RECORD_ID),
                 DEST_DIR, NA, NA, NA, "Zenodo REST API v1",
                 paste("FAILED:", conditionMessage(e)))
  }
)
