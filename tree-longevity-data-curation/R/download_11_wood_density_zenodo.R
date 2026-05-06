# download_11_wood_density_zenodo.R
# Dataset 11: Wood density database (Zenodo 13322441)
# URL: https://zenodo.org/records/13322441
# Method: Zenodo REST API v1

source(here::here("R", "download_utils.R"))

DATASET_ID   <- "D11"
DATASET_NAME <- "Wood density database (Zenodo 13322441)"
RECORD_ID    <- "13322441"
DEST_DIR     <- here::here("data", "raw", "11_wood_density_zenodo")

# Unit audit note (biodiversity-science-guard):
# Wood density may be reported in g/cm³ or kg/m³ (1 g/cm³ = 1000 kg/m³).
# Verify unit in file header BEFORE any cross-dataset joins.
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
