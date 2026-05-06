# download_08_tree_height_zenodo.R
# Dataset 08: Tree height database (Zenodo record 6637599)
# URL: https://zenodo.org/record/6637599
# DOI: https://doi.org/10.5281/zenodo.6637599
# Method: Zenodo REST API v1

source(here::here("R", "download_utils.R"))

DATASET_ID <- "D08"
DATASET_NAME <- "Tree height database (Zenodo 6637599)"
RECORD_ID  <- "6637599"
DEST_DIR   <- here::here("data", "raw", "08_tree_height_zenodo")

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
