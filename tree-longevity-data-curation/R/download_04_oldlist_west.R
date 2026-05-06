# download_04_oldlist_west.R
# Dataset 04: OldList West (Rocky Mountain Tree Ring Research)
# URL: http://www.rmtrr.org/oldlist.htm
# Method: PARTIAL — rvest HTML table scraping (HTTP only, no structured download)
# Status: Fragile scrape — raw HTML archived; ToS not stated on site.

source(here::here("R", "download_utils.R"))

DATASET_ID   <- "D04"
DATASET_NAME <- "OldList West — RMTRR"
SOURCE_URL   <- "http://www.rmtrr.org/oldlist.htm"
DEST_DIR     <- here::here("data", "raw", "04_oldlist_west")
dir.create(DEST_DIR, recursive = TRUE, showWarnings = FALSE)

if (!requireNamespace("rvest", quietly = TRUE)) {
  stop("Package 'rvest' required. Install with: install.packages('rvest')", call. = FALSE)
}
library(rvest)

scrape_timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")

tryCatch({
  page     <- rvest::read_html(SOURCE_URL)
  raw_html <- as.character(page)
  raw_path <- file.path(DEST_DIR, "oldlist_west_raw.html")
  writeLines(raw_html, raw_path)
  message("Raw HTML saved: ", raw_path)

  # Parse all tables; OldList page typically has one main species table
  tables <- rvest::html_table(page, fill = TRUE)
  if (length(tables) == 0L) {
    stop("No HTML tables found on OldList West page. Page structure may have changed.")
  }

  # Take the largest table (most rows) as the main data table
  tbl <- tables[[which.max(sapply(tables, nrow))]]
  csv_path <- file.path(DEST_DIR, "oldlist_west.csv")
  write.csv(tbl, csv_path, row.names = FALSE)
  message("Parsed table saved: ", csv_path, " (", nrow(tbl), " rows)")

  mf <- write_manifest(csv_path, SOURCE_URL, "rvest HTML scrape",
                       paste0("scrape_timestamp=", scrape_timestamp,
                              "; n_tables_found=", length(tables)))
  log_download(DATASET_ID, DATASET_NAME, SOURCE_URL, csv_path,
               "scraped", mf$size, mf$hash, "rvest HTML scrape",
               paste0("n_rows=", nrow(tbl), "; raw_html_archived=yes"))
  message("WARNING: This dataset has no DOI or persistent identifier.",
          " Cite as scraped on ", Sys.Date(), " from ", SOURCE_URL)

}, error = function(e) {
  message("SCRAPE FAILED for ", DATASET_NAME, ":\n  ", conditionMessage(e))
  log_download(DATASET_ID, DATASET_NAME, SOURCE_URL, DEST_DIR,
               "FAILED", NA, NA, "rvest HTML scrape",
               paste("FAILED:", conditionMessage(e)))
})
