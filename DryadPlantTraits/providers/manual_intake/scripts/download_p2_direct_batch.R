#!/usr/bin/env Rscript
# providers/manual_intake/scripts/download_p2_direct_batch.R
#
# P2 batch ingest — Direct dataset download for Pensoft (BDJ/PhytoKeys),
# PLOS, MDPI, and INFOR sources that have not yet been compiled.
#
# Strategy: Most Pensoft data papers register their underlying datasets
# on GBIF; we use the GBIF Literature API to discover associated datasets
# from the article DOI, then call the existing GBIF ingest pattern from
# download_occurrence_sources.R.
#
# Resumable: skips sources whose compiled_occurrences.csv already exists
# (consistent with the P1 pipeline).

suppressPackageStartupMessages({
  library(data.table)
  library(httr)
  library(jsonlite)
})

# ---------------------------------------------------------------------------
# Locate project root (same idiom as download_occurrence_sources.R)
# ---------------------------------------------------------------------------
script_file <- tryCatch(normalizePath(sys.frame(0)$ofile, winslash = "/", mustWork = FALSE),
                        error = function(e) "")
if (!nzchar(script_file)) {
  args0 <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args0, value = TRUE)
  if (length(file_arg)) {
    script_file <- normalizePath(sub("^--file=", "", file_arg[[1]]),
                                 winslash = "/", mustWork = FALSE)
  }
}
root_candidates <- c(getwd(), dirname(getwd()),
                     dirname(dirname(getwd())), dirname(dirname(dirname(getwd()))))
if (nzchar(script_file)) {
  d1 <- dirname(script_file); d2 <- dirname(d1)
  d3 <- dirname(d2);         d4 <- dirname(d3)
  root_candidates <- c(root_candidates, d1, d2, d3, d4)
}
root_candidates <- unique(normalizePath(
  root_candidates[file.exists(root_candidates)], winslash = "/", mustWork = FALSE))
proj_hits <- root_candidates[basename(root_candidates) == "DryadPlantTraits"]
if (!length(proj_hits)) stop("Cannot locate DryadPlantTraits project root from: ", getwd(), call. = FALSE)
project_root <- proj_hits[[1]]
cat("Project root:", project_root, "\n")

# ---------------------------------------------------------------------------
# Reuse DwC schema from P1 script
# ---------------------------------------------------------------------------
DWC_COLS <- c(
  "source_id", "occurrenceID", "species", "scientificName", "taxonRank",
  "decimalLatitude", "decimalLongitude", "coordinateUncertaintyInMeters",
  "countryCode", "country", "stateProvince", "locality", "eventDate",
  "year", "month", "day", "basisOfRecord", "institutionCode",
  "collectionCode", "catalogNumber", "recordedBy", "identifiedBy",
  "datasetName", "gbif_datasetKey", "source_doi",
  "download_timestamp_utc", "qa_flags"
)

empty_dwc <- function() {
  dt <- as.data.table(matrix(NA_character_, nrow = 0L, ncol = length(DWC_COLS)))
  setnames(dt, DWC_COLS)
  dt
}

out_root <- file.path(project_root, "output", "providers", "occurrences")
dir.create(out_root, recursive = TRUE, showWarnings = FALSE)

TIMESTAMP <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
MAX_RECS  <- 25000L  # higher cap than P1 since some BDJ datasets are larger
PAGE_SIZE <- 300L

safe_get <- function(url, n_retry = 3L, pause = 2) {
  for (i in seq_len(n_retry)) {
    resp <- tryCatch(GET(url, timeout(60)), error = function(e) NULL)
    if (!is.null(resp) && status_code(resp) < 400) return(resp)
    Sys.sleep(pause)
  }
  NULL
}

# ---------------------------------------------------------------------------
# Scrape Pensoft / publisher article HTML for GBIF dataset DOIs (10.15468/...)
# Returns vector of DOIs.
# ---------------------------------------------------------------------------
gbif_dataset_dois_from_publication <- function(pub_doi) {
  url <- paste0("https://doi.org/", pub_doi)
  resp <- tryCatch(GET(url, user_agent("Mozilla/5.0 (BIEN ingest)"), timeout(60)),
                   error = function(e) NULL)
  if (is.null(resp) || status_code(resp) >= 400) return(character())
  html <- rawToChar(resp$content)
  hits <- regmatches(html, gregexpr("10\\.15468/[a-zA-Z0-9]+", html))[[1]]
  unique(hits)
}

# Resolve a GBIF dataset DOI -> dataset UUID via doi.org redirect.
gbif_uuid_from_doi <- function(doi) {
  doi_url <- paste0("https://doi.org/", doi)
  resp <- tryCatch(GET(doi_url, timeout(30)), error = function(e) NULL)
  if (!is.null(resp)) {
    final_url <- resp$url
    if (grepl("gbif\\.org/dataset/", final_url)) {
      key <- sub(".*gbif\\.org/dataset/", "", final_url)
      key <- sub("[/?#].*$", "", key)
      if (nzchar(key)) return(key)
    }
  }
  encoded <- URLencode(doi, reserved = FALSE)
  url <- paste0("https://api.gbif.org/v1/dataset?doi=", encoded, "&limit=1")
  resp2 <- safe_get(url)
  if (is.null(resp2)) return(NA_character_)
  parsed <- tryCatch(fromJSON(rawToChar(resp2$content), simplifyVector = FALSE),
                     error = function(e) NULL)
  if (is.null(parsed) || length(parsed$results) == 0) return(NA_character_)
  res1 <- parsed$results[[1]]
  res_doi <- res1$doi
  if (!is.null(res_doi) && grepl(sub("^10\\.[0-9]+/", "", doi), res_doi, ignore.case = TRUE)) {
    return(res1$key)
  }
  NA_character_
}

# Inventory of GBIF dataset DOIs already compiled under a different source_id
already_compiled_gbif_dois <- function() {
  compiled_files <- Sys.glob(file.path(out_root, "*", "compiled_occurrences.csv"))
  out <- character()
  for (f in compiled_files) {
    dt <- tryCatch(fread(f, select = "source_doi", showProgress = FALSE,
                         nrows = 1000),
                   error = function(e) NULL)
    if (is.null(dt) || !"source_doi" %in% names(dt)) next
    dois <- unique(dt$source_doi)
    out <- c(out, dois[grepl("^10\\.15468/", dois)])
  }
  unique(out)
}

# ---------------------------------------------------------------------------
# GBIF occurrence fetch (paginated)
# ---------------------------------------------------------------------------
extract_field <- function(rec, field) {
  v <- rec[[field]]
  if (is.null(v)) return(NA_character_)
  as.character(v)
}

gbif_record_to_row <- function(rec, ds_key, source_doi_val, source_id_val) {
  data.table(
    source_id                     = source_id_val,
    occurrenceID                  = extract_field(rec, "key"),
    species                       = extract_field(rec, "species"),
    scientificName                = extract_field(rec, "scientificName"),
    taxonRank                     = extract_field(rec, "taxonRank"),
    decimalLatitude               = extract_field(rec, "decimalLatitude"),
    decimalLongitude              = extract_field(rec, "decimalLongitude"),
    coordinateUncertaintyInMeters = extract_field(rec, "coordinateUncertaintyInMeters"),
    countryCode                   = extract_field(rec, "countryCode"),
    country                       = extract_field(rec, "country"),
    stateProvince                 = extract_field(rec, "stateProvince"),
    locality                      = extract_field(rec, "locality"),
    eventDate                     = extract_field(rec, "eventDate"),
    year                          = extract_field(rec, "year"),
    month                         = extract_field(rec, "month"),
    day                           = extract_field(rec, "day"),
    basisOfRecord                 = extract_field(rec, "basisOfRecord"),
    institutionCode               = extract_field(rec, "institutionCode"),
    collectionCode                = extract_field(rec, "collectionCode"),
    catalogNumber                 = extract_field(rec, "catalogNumber"),
    recordedBy                    = extract_field(rec, "recordedBy"),
    identifiedBy                  = extract_field(rec, "identifiedBy"),
    datasetName                   = extract_field(rec, "datasetName"),
    gbif_datasetKey               = ds_key,
    source_doi                    = source_doi_val,
    download_timestamp_utc        = TIMESTAMP,
    qa_flags                      = NA_character_
  )
}

gbif_fetch_dataset <- function(ds_key, source_doi_val, source_id_val) {
  url_count <- sprintf("https://api.gbif.org/v1/occurrence/search?datasetKey=%s&limit=1", ds_key)
  resp_count <- safe_get(url_count)
  total_avail <- 0L
  if (!is.null(resp_count)) {
    parsed_count <- tryCatch(fromJSON(rawToChar(resp_count$content), simplifyVector = FALSE),
                             error = function(e) NULL)
    if (!is.null(parsed_count$count)) total_avail <- as.integer(parsed_count$count)
  }
  n_to_fetch <- min(total_avail, MAX_RECS)
  cat(sprintf("    dataset %s: %d records available, fetching up to %d\n",
              ds_key, total_avail, n_to_fetch))

  rows <- list()
  offset <- 0L
  repeat {
    if (offset >= n_to_fetch) break
    url <- sprintf(
      "https://api.gbif.org/v1/occurrence/search?datasetKey=%s&limit=%d&offset=%d",
      ds_key, PAGE_SIZE, offset)
    resp <- safe_get(url)
    if (is.null(resp)) break
    page <- tryCatch(fromJSON(rawToChar(resp$content), simplifyVector = FALSE),
                     error = function(e) NULL)
    if (is.null(page) || length(page$results) == 0) break
    for (rec in page$results) {
      rows[[length(rows) + 1L]] <- gbif_record_to_row(rec, ds_key, source_doi_val, source_id_val)
    }
    offset <- offset + PAGE_SIZE
    if (isTRUE(page$endOfRecords)) break
    Sys.sleep(0.5)
  }
  if (length(rows) == 0) return(empty_dwc())
  rbindlist(rows, fill = TRUE, use.names = TRUE)
}

# ---------------------------------------------------------------------------
# Process one P2 source: discover GBIF datasets via Literature API, fetch all
# ---------------------------------------------------------------------------
ingest_p2_source <- function(source_id_val, pub_doi, already_dois) {
  out_dir <- file.path(out_root, source_id_val)
  compiled <- file.path(out_dir, "compiled_occurrences.csv")
  if (file.exists(compiled)) {
    cat("  [SKIP] Already compiled:", compiled, "\n")
    dt <- fread(compiled, showProgress = FALSE)
    return(list(nrow = nrow(dt), status = "skipped", n_datasets = NA_integer_))
  }
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  cat("  Scraping publication HTML for GBIF dataset DOIs:", pub_doi, "\n")
  ds_dois <- gbif_dataset_dois_from_publication(pub_doi)
  if (length(ds_dois) == 0) {
    cat("  [INFO] No GBIF dataset DOIs found in publication HTML\n")
    return(list(nrow = 0L, status = "no_gbif_dataset_in_html", n_datasets = 0L))
  }
  cat("  Found", length(ds_dois), "GBIF dataset DOI(s):",
      paste(ds_dois, collapse = ", "), "\n")

  # Filter out datasets already compiled under another source_id
  ds_dois_new <- setdiff(ds_dois, already_dois)
  if (length(ds_dois_new) == 0) {
    cat("  [INFO] All GBIF datasets already compiled under other source_ids\n")
    return(list(nrow = 0L, status = "duplicate_of_existing_source",
                n_datasets = length(ds_dois)))
  }
  if (length(ds_dois_new) < length(ds_dois)) {
    cat("  [INFO] Skipping",
        length(ds_dois) - length(ds_dois_new),
        "duplicate dataset(s); ingesting", length(ds_dois_new), "new\n")
  }

  per_ds <- list()
  for (d in ds_dois_new) {
    k <- gbif_uuid_from_doi(d)
    if (is.na(k)) {
      cat("    [WARN] Could not resolve UUID for DOI:", d, "\n")
      next
    }
    cat("    Resolved", d, "->", k, "\n")
    per_ds[[k]] <- tryCatch(
      gbif_fetch_dataset(k, d, source_id_val),
      error = function(e) { cat("    [ERROR]", conditionMessage(e), "\n"); empty_dwc() }
    )
  }
  combined <- if (length(per_ds)) rbindlist(per_ds, fill = TRUE, use.names = TRUE) else empty_dwc()
  if (nrow(combined) == 0) {
    cat("  [WARN] Datasets discovered but no records fetched\n")
    return(list(nrow = 0L, status = "datasets_empty", n_datasets = length(ds_dois_new)))
  }
  fwrite(combined, compiled)
  cat(sprintf("  Wrote %d rows -> %s\n", nrow(combined), compiled))
  list(nrow = nrow(combined), status = "compiled", n_datasets = length(ds_dois_new))
}

# ---------------------------------------------------------------------------
# P2 sources (publication DOI as the lookup key)
# ---------------------------------------------------------------------------
p2_sources <- list(
  list(source_id = "manual_ecat_central_africa",            doi = "10.3897/phytokeys.206.77379"),
  list(source_id = "manual_oxytropis_asian_russia",         doi = "10.3897/BDJ.10.e78666"),
  list(source_id = "manual_altb_virtual_herbarium",         doi = "10.3897/BDJ.9.e67616"),
  list(source_id = "manual_fleroff_georef_records",         doi = "10.3897/BDJ.9.e75299"),
  list(source_id = "manual_flora_russia_inaturalist",       doi = "10.3897/BDJ.8.e59249"),
  list(source_id = "manual_lesser_sunda_endemics",          doi = "10.3897/phytokeys.273.184780"),
  list(source_id = "manual_theobroma_occurrences",          doi = "10.3897/BDJ.11.e99646"),
  list(source_id = "manual_pucv_herbarium_chile_bdj",       doi = "10.3897/BDJ.10.e90591"),
  list(source_id = "manual_luebert_chile_diversity",        doi = "10.3390/d14040271"),
  list(source_id = "manual_colombia_bioregions_bystriakova",doi = "10.1371/journal.pone.0256457")
  # manual_rasgos_cl_chile_traits — INFOR handle, no GBIF deposit; needs manual XLS download.
)

results <- list()
already_dois <- already_compiled_gbif_dois()
cat("Already-compiled GBIF dataset DOIs in pipeline:",
    length(already_dois), "->", paste(already_dois, collapse = ", "), "\n")

for (src in p2_sources) {
  cat("\n=== P2:", src$source_id, "===\n")
  res <- tryCatch(
    ingest_p2_source(src$source_id, src$doi, already_dois),
    error = function(e) {
      cat("  [ERROR]", conditionMessage(e), "\n")
      list(nrow = 0L, status = paste0("error: ", conditionMessage(e)), n_datasets = NA_integer_)
    }
  )
  results[[src$source_id]] <- res
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
summary_dt <- rbindlist(lapply(names(results), function(id) {
  r <- results[[id]]
  data.table(source_id = id, status = r$status,
             n_datasets = r$n_datasets, n_rows = r$nrow)
}), fill = TRUE)
cat("\n\n=========================================================\n")
cat("P2 batch ingest summary\n")
cat("=========================================================\n")
print(summary_dt)
summary_path <- file.path(project_root, "output", "providers", "occurrences",
                          "_p2_batch_summary.csv")
fwrite(summary_dt, summary_path)
cat("\nSummary written to:", summary_path, "\n")
