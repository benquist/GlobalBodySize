# download_06_nts_dendro.R
# Dataset 06: Native Tree Society — dendro maximum ages
# URL: http://www.nativetreesociety.org/dendro/ents_maximum_ages.htm
# Method: PARTIAL — rvest HTML scraping (HTTP only)
# WARNING: Community-maintained page; structure may be irregular.

source(here::here("R", "download_utils.R"))

DATASET_ID   <- "D06"
DATASET_NAME <- "Native Tree Society dendro ages"
SOURCE_URL   <- "http://www.nativetreesociety.org/dendro/ents_maximum_ages.htm"
DEST_DIR     <- here::here("data", "raw", "06_nts_dendro")
dir.create(DEST_DIR, recursive = TRUE, showWarnings = FALSE)

if (!requireNamespace("rvest", quietly = TRUE)) {
  stop("Package 'rvest' required. Install with: install.packages('rvest')", call. = FALSE)
}
library(rvest)

scrape_timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")

tryCatch({
  page     <- rvest::read_html(SOURCE_URL)
  raw_html <- as.character(page)
  writeLines(raw_html, file.path(DEST_DIR, "nts_dendro_raw.html"))

  tables <- rvest::html_table(page, fill = TRUE)
  if (length(tables) > 0L) {
    tbl      <- tables[[which.max(sapply(tables, nrow))]]
    csv_path <- file.path(DEST_DIR, "nts_dendro.csv")
    write.csv(tbl, csv_path, row.names = FALSE)
    mf <- write_manifest(csv_path, SOURCE_URL, "rvest HTML scrape",
                         paste0("scrape_timestamp=", scrape_timestamp,
                                "; n_rows=", nrow(tbl)))
    log_download(DATASET_ID, DATASET_NAME, SOURCE_URL, csv_path,
                 "scraped", mf$size, mf$hash, "rvest HTML scrape",
                 paste0("n_rows=", nrow(tbl), "; manual_review_required=yes"))
  } else {
    # No tables — record text-based page
    message("No HTML tables found. Page may be text-based. Raw HTML archived for manual extraction.")
    log_download(DATASET_ID, DATASET_NAME, SOURCE_URL,
                 file.path(DEST_DIR, "nts_dendro_raw.html"),
                 "scraped-html-only", NA, NA, "rvest HTML scrape",
                 "No structured tables. Manual text extraction required.")
  }
}, error = function(e) {
  message("SCRAPE FAILED for ", DATASET_NAME, ":\n  ", conditionMessage(e))
  log_download(DATASET_ID, DATASET_NAME, SOURCE_URL, DEST_DIR,
               "FAILED", NA, NA, "rvest HTML scrape",
               paste("FAILED:", conditionMessage(e)))
})
