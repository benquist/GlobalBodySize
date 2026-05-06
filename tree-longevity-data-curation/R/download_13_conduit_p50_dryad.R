# download_13_conduit_p50_dryad.R
# Dataset 13: Conduit density, P50, and HSM — Dryad
# DOI: https://doi.org/10.5061/dryad.1138
# Method: Dryad API v2
# NOTE: dryad.1138 is a short-form DOI — verify resolution at datadryad.org

source(here::here("R", "download_utils.R"))

DATASET_ID   <- "D13"
DATASET_NAME <- "Conduit density + P50 + HSM (Dryad 10.5061/dryad.1138)"
DOI          <- "10.5061/dryad.1138"
SOURCE_URL   <- paste0("https://doi.org/", DOI)
DEST_DIR     <- here::here("data", "raw", "13_conduit_p50_dryad")
dir.create(DEST_DIR, recursive = TRUE, showWarnings = FALSE)

# P50 SIGN CONVENTION NOTE (biodiversity-science-guard):
# P50 values in this dataset must be checked for sign before joining with D14.
# Expected convention: negative MPa. Run qa_utils::check_p50_sign() after download.

tryCatch({
  # Dryad v2 API: search by DOI
  api_url  <- paste0("https://datadryad.org/api/v2/datasets/",
                     utils::URLencode(paste0("doi:", DOI), reserved = TRUE))
  message("Querying Dryad API: ", api_url)

  resp <- httr2::request(api_url) |>
    httr2::req_user_agent("tree-longevity-data-curation/1.0") |>
    httr2::req_perform()

  if (httr2::resp_status(resp) != 200L) {
    stop("Dryad API returned status ", httr2::resp_status(resp),
         " for DOI ", DOI)
  }

  meta      <- httr2::resp_body_json(resp)
  files_url <- meta$`_links`$`stash:files`$href
  if (is.null(files_url)) {
    stop("Could not locate files link in Dryad API response for ", DOI)
  }

  files_resp <- httr2::request(paste0("https://datadryad.org", files_url)) |>
    httr2::req_user_agent("tree-longevity-data-curation/1.0") |>
    httr2::req_perform()
  files <- httr2::resp_body_json(files_resp)$`_embedded`$`stash:files`

  for (f in files) {
    fname   <- f$path
    dl_url  <- paste0("https://datadryad.org",
                      f$`_links`$`stash:file-download`$href)
    local_p <- file.path(DEST_DIR, basename(fname))
    message("Downloading: ", fname)
    httr2::request(dl_url) |>
      httr2::req_user_agent("tree-longevity-data-curation/1.0") |>
      httr2::req_perform(path = local_p)
    mf <- write_manifest(local_p, dl_url, "Dryad API v2")
    log_download(DATASET_ID, DATASET_NAME, dl_url, local_p,
                 200, mf$size, mf$hash, "Dryad API v2",
                 "P50 sign convention must be verified after download")
  }

}, error = function(e) {
  message("DOWNLOAD FAILED for ", DATASET_NAME, ":\n  ", conditionMessage(e))
  message("  Action: visit https://doi.org/10.5061/dryad.1138 manually.")
  message("  Older short-form Dryad DOIs may require API v1 or direct browser download.")
  log_download(DATASET_ID, DATASET_NAME, SOURCE_URL, DEST_DIR,
               "FAILED", NA, NA, "Dryad API v2",
               paste("FAILED:", conditionMessage(e)))
})
