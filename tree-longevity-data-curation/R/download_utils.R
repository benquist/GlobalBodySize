# download_utils.R
# Shared helpers for tree-longevity-data-curation download scripts.
# Requires: httr2, digest, cli

library(httr2)
library(digest)
library(cli)

LOG_PATH <- here::here("logs", "download_log.csv")

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

#' Append one row to the download log CSV.
log_download <- function(dataset_id, dataset_name, source_url, local_path,
                         http_status, file_size_bytes, sha256,
                         download_method, notes = "") {
  row <- data.frame(
    dataset_id       = dataset_id,
    dataset_name     = dataset_name,
    source_url       = source_url,
    local_path       = as.character(local_path),
    download_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    http_status      = http_status,
    file_size_bytes  = file_size_bytes,
    sha256           = sha256,
    download_method  = download_method,
    notes            = notes,
    stringsAsFactors = FALSE
  )
  if (!file.exists(LOG_PATH)) {
    write.csv(row, LOG_PATH, row.names = FALSE)
  } else {
    existing <- read.csv(LOG_PATH, stringsAsFactors = FALSE)
    write.csv(rbind(existing, row), LOG_PATH, row.names = FALSE)
  }
  invisible(row)
}

# ---------------------------------------------------------------------------
# Download guards
# ---------------------------------------------------------------------------

#' Stop with a clear message if a required data file is absent or too small.
assert_file_present <- function(local_path, source_url,
                                min_bytes = 1000L) {
  if (!file.exists(local_path) ||
      file.info(local_path)$size < min_bytes) {
    stop(
      "Data file not found or too small: ", local_path, "\n",
      "Expected source: ", source_url, "\n",
      "Do NOT substitute simulated data. Download the file and re-run.\n",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# Manifest writing
# ---------------------------------------------------------------------------

#' Write a companion manifest file alongside a downloaded data file.
write_manifest <- function(local_path, source_url, download_method,
                           extra_notes = "") {
  hash   <- digest::digest(file = local_path, algo = "sha256")
  size   <- file.info(local_path)$size
  tstamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  manifest_path <- paste0(local_path, "_manifest.txt")
  lines <- c(
    paste("file:             ", basename(local_path)),
    paste("local_path:       ", local_path),
    paste("source_url:       ", source_url),
    paste("download_method:  ", download_method),
    paste("download_timestamp:", tstamp),
    paste("file_size_bytes:  ", size),
    paste("sha256:           ", hash),
    if (nzchar(extra_notes)) paste("notes:            ", extra_notes)
  )
  writeLines(lines, manifest_path)
  cli::cli_alert_success("Manifest written: {manifest_path}")
  invisible(list(hash = hash, size = size, timestamp = tstamp))
}

# ---------------------------------------------------------------------------
# Zenodo API download
# ---------------------------------------------------------------------------

#' Download all files from a Zenodo record (open access).
#' Returns a data.frame of downloaded files.
download_zenodo <- function(record_id, dest_dir,
                            dataset_id, dataset_name) {
  api_url  <- paste0("https://zenodo.org/api/records/", record_id)
  cli::cli_alert_info("Querying Zenodo API: {api_url}")

  resp <- httr2::request(api_url) |>
    httr2::req_user_agent("tree-longevity-data-curation/1.0") |>
    httr2::req_perform()

  if (httr2::resp_status(resp) != 200L) {
    stop("Zenodo API returned status ", httr2::resp_status(resp),
         " for record ", record_id, call. = FALSE)
  }

  meta  <- httr2::resp_body_json(resp)
  files <- meta$files
  if (length(files) == 0L) {
    stop("No files found in Zenodo record ", record_id, call. = FALSE)
  }

  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  results <- vector("list", length(files))

  for (i in seq_along(files)) {
    f        <- files[[i]]
    fname    <- f$key %||% f$filename
    dl_url   <- f$links$self %||% f$links$download
    local_p  <- file.path(dest_dir, fname)

    cli::cli_alert_info("Downloading [{i}/{length(files)}]: {fname}")
    httr2::request(dl_url) |>
      httr2::req_user_agent("tree-longevity-data-curation/1.0") |>
      httr2::req_perform(path = local_p)

    mf <- write_manifest(local_p, dl_url, "Zenodo REST API v1")
    log_download(dataset_id, dataset_name, dl_url, local_p,
                 200, mf$size, mf$hash, "Zenodo REST API v1")
    results[[i]] <- list(file = fname, path = local_p, hash = mf$hash)
  }
  invisible(results)
}

# ---------------------------------------------------------------------------
# Figshare API download
# ---------------------------------------------------------------------------

#' Download all files from a Figshare article.
download_figshare <- function(article_id, dest_dir,
                              dataset_id, dataset_name) {
  api_url <- paste0("https://api.figshare.com/v2/articles/", article_id)
  cli::cli_alert_info("Querying Figshare API: {api_url}")

  resp <- httr2::request(api_url) |>
    httr2::req_user_agent("tree-longevity-data-curation/1.0") |>
    httr2::req_perform()

  if (httr2::resp_status(resp) != 200L) {
    stop("Figshare API returned status ", httr2::resp_status(resp),
         " for article ", article_id, call. = FALSE)
  }

  meta  <- httr2::resp_body_json(resp)
  files <- meta$files
  if (length(files) == 0L) {
    stop("No files found in Figshare article ", article_id, call. = FALSE)
  }

  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  results <- vector("list", length(files))

  for (i in seq_along(files)) {
    f       <- files[[i]]
    fname   <- f$name
    dl_url  <- f$download_url
    local_p <- file.path(dest_dir, fname)

    cli::cli_alert_info("Downloading [{i}/{length(files)}]: {fname}")
    httr2::request(dl_url) |>
      httr2::req_user_agent("tree-longevity-data-curation/1.0") |>
      httr2::req_perform(path = local_p)

    mf <- write_manifest(local_p, dl_url, "Figshare REST API v2")
    log_download(dataset_id, dataset_name, dl_url, local_p,
                 200, mf$size, mf$hash, "Figshare REST API v2")
    results[[i]] <- list(file = fname, path = local_p, hash = mf$hash)
  }
  invisible(results)
}

# ---------------------------------------------------------------------------
# Generic URL download
# ---------------------------------------------------------------------------

#' Download a single file from a direct URL.
download_url_file <- function(url, local_path, dataset_id, dataset_name,
                              method_label = "direct URL") {
  dir.create(dirname(local_path), recursive = TRUE, showWarnings = FALSE)
  cli::cli_alert_info("Downloading: {url}")

  resp <- httr2::request(url) |>
    httr2::req_user_agent("tree-longevity-data-curation/1.0") |>
    httr2::req_perform(path = local_path)

  status <- httr2::resp_status(resp)
  mf     <- write_manifest(local_path, url, method_label)
  log_download(dataset_id, dataset_name, url, local_path,
               status, mf$size, mf$hash, method_label)
  invisible(list(path = local_path, hash = mf$hash))
}

# ---------------------------------------------------------------------------
# Null coalescing
# ---------------------------------------------------------------------------
`%||%` <- function(a, b) if (!is.null(a)) a else b
