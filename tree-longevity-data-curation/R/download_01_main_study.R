# download_01_main_study.R
# Dataset 01: Main study longevity/traits/climate (Figshare 29876984)
# DOI: https://doi.org/10.6084/m9.figshare.29876984
# Method: Figshare REST API v2

source(here::here("R", "download_utils.R"))

DATASET_ID   <- "D01"
DATASET_NAME <- "Main study longevity/traits/climate (Figshare 29876984)"
ARTICLE_ID   <- 29876984L
DEST_DIR     <- here::here("data", "raw", "01_main_study")

# NOTE: Verify this record is public and not embargoed before running.
# The DOI was cited in the paper but independent verification is required.
tryCatch(
  download_figshare(ARTICLE_ID, DEST_DIR, DATASET_ID, DATASET_NAME),
  error = function(e) {
    message("DOWNLOAD FAILED for ", DATASET_NAME, ":\n  ", conditionMessage(e))
    message("  Possible cause: record is embargoed, does not exist, or network error.")
    message("  Action: verify DOI at https://doi.org/10.6084/m9.figshare.29876984")
    source(here::here("R", "download_utils.R"))
    log_download(DATASET_ID, DATASET_NAME,
                 "https://api.figshare.com/v2/articles/29876984",
                 DEST_DIR, NA, NA, NA, "Figshare REST API v2",
                 paste("FAILED:", conditionMessage(e)))
  }
)
