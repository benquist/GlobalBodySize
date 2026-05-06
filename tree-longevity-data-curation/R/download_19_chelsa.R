# download_19_chelsa.R
# Dataset 19: CHELSA — growing season length and NPP
# URL: https://chelsa-climate.org/
# Method: direct curl to CHELSA v2.1 cloud storage (SwitchDrive)
# WARNING: Individual CHELSA raster files are large (200–600 MB each, global).

source(here::here("R", "download_utils.R"))

DATASET_ID   <- "D19"
DATASET_NAME <- "CHELSA v2.1 — growing season + NPP"
SOURCE_URL   <- "https://chelsa-climate.org/"
DEST_DIR     <- here::here("data", "raw", "19_chelsa")
dir.create(DEST_DIR, recursive = TRUE, showWarnings = FALSE)

# CHELSA v2.1 SwitchDrive base URL
BASE_URL <- "https://os.zhdk.cloud.switch.ch/chelsav2/GLOBAL"

# Selected variables (subset; expand as needed):
#   kg_gsl : growing season length (days)
#   npp    : net primary productivity (kg C / m² / yr)
#   bio1   : mean annual temperature (°C × 10)
#   bio12  : annual precipitation (mm)
CHELSA_FILES <- list(
  list(
    var     = "kg_gsl",
    path    = "indices/kg_gsl/CHELSA_kg_gsl_1981-2010_V.2.1.tif",
    desc    = "Growing season length (days), 1981-2010 climatology"
  ),
  list(
    var     = "npp",
    path    = "npp/CHELSA_npp_1981-2010_V.2.1.tif",
    desc    = "Net Primary Productivity (kg C/m²/yr), 1981-2010"
  )
)

for (cf in CHELSA_FILES) {
  url     <- paste0(BASE_URL, "/", cf$path)
  fname   <- basename(cf$path)
  local_p <- file.path(DEST_DIR, fname)

  if (file.exists(local_p)) {
    message("Already exists, skipping: ", fname)
    next
  }

  message("Downloading CHELSA: ", cf$var, " — ", cf$desc)
  message("  URL: ", url)
  message("  WARNING: file may be 200-600 MB. This will take several minutes.")

  tryCatch({
    download.file(url, destfile = local_p, method = "curl",
                  extra = "--user-agent tree-longevity-data-curation/1.0",
                  quiet = FALSE)
    mf <- write_manifest(local_p, url, "direct curl — CHELSA SwitchDrive",
                         paste0("variable=", cf$var, "; ", cf$desc))
    log_download(DATASET_ID, DATASET_NAME, url, local_p,
                 200, mf$size, mf$hash, "direct curl — CHELSA SwitchDrive",
                 paste0("variable=", cf$var, "; ", cf$desc))
  }, error = function(e) {
    message("DOWNLOAD FAILED: ", cf$var, " — ", conditionMessage(e))
    message("  Verify URL at: https://chelsa-climate.org/downloads/")
    log_download(DATASET_ID, DATASET_NAME, url, DEST_DIR,
                 "FAILED", NA, NA, "direct curl — CHELSA SwitchDrive",
                 paste("FAILED:", cf$var, conditionMessage(e)))
  })
}
