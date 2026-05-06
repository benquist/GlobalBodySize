# download_18_worldclim.R
# Dataset 18: WorldClim 2.1 gridded climate and elevation
# URL: https://www.worldclim.org/data/worldclim21.html
# Method: geodata R package (recommended) or direct curl to UCDAVIS CDN

source(here::here("R", "download_utils.R"))

DATASET_ID   <- "D18"
DATASET_NAME <- "WorldClim 2.1 gridded climate and elevation"
SOURCE_URL   <- "https://www.worldclim.org/data/worldclim21.html"
DEST_DIR     <- here::here("data", "raw", "18_worldclim")
dir.create(DEST_DIR, recursive = TRUE, showWarnings = FALSE)

# RESOLUTION NOTE: full resolution (30 arc-sec ≈ 1 km) is very large (~8 GB).
# Use 10 arc-min for development/testing; document resolution used in catalog.
# For production: change RES to "2.5m" or "0.5m" as appropriate.

RES <- "10m"  # Options: "10m", "5m", "2.5m", "0.5m", "30s"

if (!requireNamespace("geodata", quietly = TRUE)) {
  stop("Package 'geodata' required. Install with: install.packages('geodata')",
       call. = FALSE)
}

# Variables to download:
VARIABLES <- c("tmin", "tmax", "prec", "bio", "elev")

downloaded <- character()
failed     <- character()

for (var in VARIABLES) {
  message("Downloading WorldClim ", RES, " — ", var)
  tryCatch({
    if (var == "elev") {
      r <- geodata::elevation_global(res = as.numeric(gsub("m", "", RES)),
                                     path = DEST_DIR)
    } else {
      r <- geodata::worldclim_global(var = var, res = as.numeric(gsub("m", "", RES)),
                                     path = DEST_DIR)
    }
    message("  Downloaded: ", var)
    downloaded <- c(downloaded, var)
    log_download(DATASET_ID, DATASET_NAME,
                 paste0(SOURCE_URL, "#", var),
                 file.path(DEST_DIR, paste0("wc2.1_", RES, "_", var, ".tif")),
                 200, NA, NA, paste0("geodata::worldclim_global() res=", RES),
                 paste0("variable=", var, "; resolution=", RES))
  }, error = function(e) {
    message("  FAILED: ", var, " — ", conditionMessage(e))
    failed <<- c(failed, var)
    log_download(DATASET_ID, DATASET_NAME,
                 paste0(SOURCE_URL, "#", var),
                 DEST_DIR, "FAILED", NA, NA,
                 paste0("geodata res=", RES),
                 paste("FAILED:", var, conditionMessage(e)))
  })
}

message(sprintf("WorldClim download complete: %d succeeded, %d failed",
                length(downloaded), length(failed)))
if (length(failed) > 0)
  message("  Failed variables: ", paste(failed, collapse = ", "))
