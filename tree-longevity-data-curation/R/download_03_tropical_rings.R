# download_03_tropical_rings.R
# Dataset 03: Tropical tree ring data — Locoselli et al. 2020 (Figshare 13119842)
# URL: https://figshare.com/articles/dataset/Locoselli_et_al_2020.../13119842
# Specific file asset: 25178405
# Method: Figshare REST API v2

source(here::here("R", "download_utils.R"))

DATASET_ID   <- "D03"
DATASET_NAME <- "Tropical tree rings — Locoselli et al. 2020 (Figshare 13119842)"
ARTICLE_ID   <- 13119842L
DEST_DIR     <- here::here("data", "raw", "03_tropical_rings")

tryCatch(
  download_figshare(ARTICLE_ID, DEST_DIR, DATASET_ID, DATASET_NAME),
  error = function(e) {
    message("DOWNLOAD FAILED for ", DATASET_NAME, ":\n  ", conditionMessage(e))
    log_download(DATASET_ID, DATASET_NAME,
                 "https://api.figshare.com/v2/articles/13119842",
                 DEST_DIR, NA, NA, NA, "Figshare REST API v2",
                 paste("FAILED:", conditionMessage(e)))
  }
)
