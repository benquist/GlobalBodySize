# download_05_oldlist_east.R
# Dataset 05: OldList East (LDEO / Columbia University)
# URL: https://www.ldeo.columbia.edu/~adk/oldlisteast/
# Method: PARTIAL — rvest HTML scraping
# WARNING: personal-directory URL (~adk) is inherently unstable.

source(here::here("R", "download_utils.R"))

DATASET_ID   <- "D05"
DATASET_NAME <- "OldList East — LDEO Columbia"
SOURCE_URL   <- "https://www.ldeo.columbia.edu/~adk/oldlisteast/"
DEST_DIR     <- here::here("data", "raw", "05_oldlist_east")
dir.create(DEST_DIR, recursive = TRUE, showWarnings = FALSE)

if (!requireNamespace("rvest", quietly = TRUE)) {
  stop("Package 'rvest' required. Install with: install.packages('rvest')", call. = FALSE)
}
library(rvest)

scrape_timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")

tryCatch({
  page     <- rvest::read_html(SOURCE_URL)
  raw_html <- as.character(page)
  raw_path <- file.path(DEST_DIR, "oldlist_east_raw.html")
  writeLines(raw_html, raw_path)

  tables <- rvest::html_table(page, fill = TRUE)
  if (length(tables) == 0L) {
    stop("No HTML tables on OldList East page. Structure may have changed.")
  }
  tbl      <- tables[[which.max(sapply(tables, nrow))]]
  csv_path <- file.path(DEST_DIR, "oldlist_east.csv")
  write.csv(tbl, csv_path, row.names = FALSE)

  mf <- write_manifest(csv_path, SOURCE_URL, "rvest HTML scrape",
                       paste0("scrape_timestamp=", scrape_timestamp))
  log_download(DATASET_ID, DATASET_NAME, SOURCE_URL, csv_path,
               "scraped", mf$size, mf$hash, "rvest HTML scrape",
               paste0("n_rows=", nrow(tbl),
                      "; WARNING: personal-directory URL unstable"))
}, error = function(e) {
  message("SCRAPE FAILED for ", DATASET_NAME, ":\n  ", conditionMessage(e))
  log_download(DATASET_ID, DATASET_NAME, SOURCE_URL, DEST_DIR,
               "FAILED", NA, NA, "rvest HTML scrape",
               paste("FAILED:", conditionMessage(e)))
})
