# download_12_wood_density_dv.R
# Dataset 12: Wood density — CIRAD DataVerse
# DOI: https://doi.org/10.18167/DVN1/KRVF0E
# Method: DataVerse native API (CIRAD server, France)
# WARNING: DOI prefix 10.18167 resolves to CIRAD DataVerse. May require API token.

source(here::here("R", "download_utils.R"))

DATASET_ID   <- "D12"
DATASET_NAME <- "Wood density — CIRAD DataVerse (DVN1/KRVF0E)"
DOI          <- "10.18167/DVN1/KRVF0E"
SOURCE_URL   <- paste0("https://doi.org/", DOI)
DEST_DIR     <- here::here("data", "raw", "12_wood_density_dv")
dir.create(DEST_DIR, recursive = TRUE, showWarnings = FALSE)

# Resolve DOI to DataVerse server URL first
tryCatch({
  resp_doi <- httr2::request(SOURCE_URL) |>
    httr2::req_user_agent("tree-longevity-data-curation/1.0") |>
    httr2::req_options(followlocation = FALSE) |>
    httr2::req_perform()

  redirect_url <- httr2::resp_header(resp_doi, "Location")
  if (is.null(redirect_url) || !nzchar(redirect_url)) {
    # Fallback: try known CIRAD DataVerse server
    redirect_url <- paste0(
      "https://dataverse.cirad.fr/api/datasets/:persistentId/?persistentId=doi:",
      DOI
    )
    message("DOI did not redirect. Using fallback CIRAD DataVerse API URL.")
  } else {
    # Convert landing page URL to API URL
    # Extract base (scheme + host) only
    base_url     <- gsub("(https?://[^/]+).*", "\\1/", redirect_url)
    redirect_url <- paste0(base_url, "api/datasets/:persistentId/?persistentId=doi:", DOI)
    message("Resolved DataVerse API URL: ", redirect_url)
  }

  api_resp <- httr2::request(redirect_url) |>
    httr2::req_user_agent("tree-longevity-data-curation/1.0") |>
    httr2::req_perform()

  if (httr2::resp_status(api_resp) != 200L) {
    stop("DataVerse API returned status ", httr2::resp_status(api_resp))
  }

  meta  <- httr2::resp_body_json(api_resp)
  files <- meta$data$latestVersion$files

  if (length(files) == 0L) {
    stop("No files found in DataVerse dataset ", DOI)
  }

  for (f in files) {
    file_id  <- f$dataFile$id
    fname    <- f$dataFile$filename
    dl_url   <- paste0(gsub("/api/datasets.*", "", redirect_url),
                       "/api/access/datafile/", file_id)
    local_p  <- file.path(DEST_DIR, fname)
    message("Downloading: ", fname)
    httr2::request(dl_url) |>
      httr2::req_user_agent("tree-longevity-data-curation/1.0") |>
      httr2::req_perform(path = local_p)
    mf <- write_manifest(local_p, dl_url, "DataVerse API")
    log_download(DATASET_ID, DATASET_NAME, dl_url, local_p,
                 200, mf$size, mf$hash, "DataVerse API")
  }

}, error = function(e) {
  message("DOWNLOAD FAILED for ", DATASET_NAME, ":\n  ", conditionMessage(e))
  message("  Action: visit https://doi.org/10.18167/DVN1/KRVF0E manually.")
  message("  Some CIRAD DataVerse datasets require an API token for download.")
  log_download(DATASET_ID, DATASET_NAME, SOURCE_URL, DEST_DIR,
               "FAILED", NA, NA, "DataVerse API",
               paste("FAILED:", conditionMessage(e),
                     "| API token may be required"))
})
