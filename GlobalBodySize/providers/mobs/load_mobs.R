## providers/mobs/load_mobs.R
## MOBS 1.0 — Marine Organismal Body Sizes database (McClain et al. 2025)
## A curated cross-phylum database of marine animal body size measurements
## compiled from the published literature.
##
## Reference:
##   McClain CR, Heim NA, Knope ML, Monarrez PM, Payne JL. 2025.
##   MOBS 1.0: A Database of Interspecific Variation in Marine Organismal
##   Body Sizes. Global Ecology and Biogeography. DOI: 10.1111/geb.70062
##
## Data hosted on GitHub (open access, public repository):
##   https://github.com/crmcclain/MOBS_OPEN
##   Full data: https://raw.githubusercontent.com/crmcclain/MOBS_OPEN/main/data_all_112224.csv
##
## Source columns (12):
##   Order_Added, valid_AphiaID, length_cm, diameter_width_cm, height_cm,
##   Notes, Size_Ref, Date_Added, Biological_Unit, Is_Ref_DOI, Sex, Specimen_Type
##
## TAXONOMY NOTE: The MOBS CSV contains only WoRMS AphiaID (valid_AphiaID) —
##   NO species names. Species names are resolved via the worrms package API.
##   Cache is written to providers/mobs/data/raw/worms_name_cache.csv.
##
## OUTPUT: Long-format linear size table (one row per dimension measurement).
##   A source row with length_cm AND height_cm both non-NA produces 2 output rows.
##   Written to: output/mobs_linear_compiled.csv
##   Schema follows globalsize_linear_size_schema_columns() in R/body_size_schema.R.

suppressPackageStartupMessages({
  library(data.table)
  library(httr)
})

## ---- Constants --------------------------------------------------------------

MOBS_RAW_URL       <- "https://raw.githubusercontent.com/crmcclain/MOBS_OPEN/main/data_all_112224.csv"
MOBS_SOURCE_ID     <- "mobs_mcclain2025"
MOBS_DISPLAY       <- "MOBS 1.0 (McClain et al. 2025)"
MOBS_DOI           <- "10.1111/geb.70062"
MOBS_CITATION      <- paste0(
  "McClain CR, Heim NA, Knope ML, Monarrez PM, Payne JL. 2025. ",
  "MOBS 1.0: A Database of Interspecific Variation in Marine Organismal ",
  "Body Sizes. Global Ecology and Biogeography. ",
  "https://doi.org/10.1111/geb.70062. ",
  "Data: https://github.com/crmcclain/MOBS_OPEN"
)

## Map WoRMS phylum -> input_taxonomic_group (fallback; CLASS_TO_GROUP takes priority)
PHYLUM_TO_GROUP <- c(
  "Chordata"        = "fish",              # fallback only; CLASS_TO_GROUP handles finer resolution
  "Arthropoda"      = "crustacean",
  "Mollusca"        = "mollusc",
  "Echinodermata"   = "echinoderm",
  "Cnidaria"        = "cnidarian",
  "Porifera"        = "sponge",
  "Annelida"        = "annelid",
  "Bryozoa"         = "bryozoan",
  "Brachiopoda"     = "brachiopod",
  "Platyhelminthes" = "flatworm",
  "Nematoda"        = "nematode"
)

## Class-level override: finer resolution than phylum alone.
## Critical for Chordata: disambiguates marine mammals, seabirds, sea turtles from fish.
CLASS_TO_GROUP <- c(
  ## Chordata — vertebrate classes
  "Actinopterygii"     = "fish",
  "Chondrichthyes"     = "fish",
  "Sarcopterygii"      = "fish",
  "Cephalaspidomorphi" = "fish",
  "Myxini"             = "fish",
  "Mammalia"           = "mammal",
  "Aves"               = "bird",
  "Reptilia"           = "reptile",
  "Amphibia"           = "amphibian",
  ## Arthropoda — crustacean classes
  "Malacostraca"       = "crustacean",
  "Maxillopoda"        = "crustacean",
  "Ostracoda"          = "crustacean",
  "Remipedia"          = "crustacean",
  ## Other arthropod classes (minor marine presence)
  "Insecta"            = "insect",
  "Arachnida"          = "arachnid"
)

## ---- Download helper --------------------------------------------------------

.mobs_download <- function(dest_dir, overwrite = FALSE) {
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  dest_file <- file.path(dest_dir, "mobs_data_all.csv")

  if (file.exists(dest_file) && !overwrite) {
    message("MOBS: using cached raw file at ", dest_file)
    return(dest_file)
  }

  message("MOBS: downloading full dataset (~30 MB) from GitHub ...")
  message("  URL: ", MOBS_RAW_URL)

  rc <- tryCatch(
    {
      download.file(
        url      = MOBS_RAW_URL,
        destfile = dest_file,
        mode     = "wb",
        quiet    = FALSE
      )
      0L
    },
    error   = function(e) { warning("Download failed: ", conditionMessage(e)); 1L },
    warning = function(w) { warning("Download warning: ", conditionMessage(w)); 1L }
  )

  if (rc != 0 || !file.exists(dest_file) || file.size(dest_file) < 10000) {
    stop("MOBS: download failed or file too small. Check network and URL.",
         call. = FALSE)
  }

  message(sprintf("MOBS: downloaded %.1f MB -> %s",
                  file.size(dest_file) / 1e6, dest_file))
  dest_file
}

## ---- WoRMS lookup helpers ---------------------------------------------------

## Helper: safely extract a field from a WoRMS record list element
.worms_chr <- function(x) if (is.null(x) || length(x) == 0) NA_character_ else as.character(x[[1]])
.worms_int <- function(x) if (is.null(x) || length(x) == 0) NA_integer_  else as.integer(x[[1]])

## Batch WoRMS lookup via the REST AphiaRecordsByAphiaIDs endpoint.
## One HTTP request per batch (up to 50 IDs); httr only — no worrms package needed.
.worms_lookup_batch <- function(aphia_ids) {
  ## Build query string: aphiaids[]=1234&aphiaids[]=5678 ...
  query_str <- paste(paste0("aphiaids%5B%5D=", aphia_ids), collapse = "&")
  full_url  <- paste0(
    "https://www.marinespecies.org/rest/AphiaRecordsByAphiaIDs?", query_str
  )

  resp <- tryCatch(
    httr::GET(full_url, httr::timeout(30)),
    error = function(e) {
      message("  WoRMS API error: ", conditionMessage(e))
      NULL
    }
  )

  if (is.null(resp) || httr::http_error(resp)) {
    message("  WoRMS batch failed (HTTP ",
            if (!is.null(resp)) httr::status_code(resp) else "?", ")")
    return(data.table())
  }

  records_raw <- httr::content(resp, as = "parsed", simplifyVector = FALSE)
  if (is.null(records_raw) || length(records_raw) == 0) return(data.table())

  rows <- lapply(seq_along(records_raw), function(i) {
    r           <- records_raw[[i]]
    query_id    <- aphia_ids[i]
    if (is.null(r)) {
      return(data.table(aphia_id_query = query_id, valid_name = NA_character_,
                        status = "not_found"))
    }
    data.table(
      aphia_id_query  = query_id,
      valid_aphia_id  = .worms_int(r["valid_AphiaID"]),
      valid_name      = .worms_chr(r["valid_name"]),
      scientificname  = .worms_chr(r["scientificname"]),
      status          = .worms_chr(r["status"]),
      rank            = .worms_chr(r["rank"]),
      kingdom         = .worms_chr(r["kingdom"]),
      phylum          = .worms_chr(r["phylum"]),
      class           = .worms_chr(r["class"]),
      order           = .worms_chr(r["order"]),
      family          = .worms_chr(r["family"]),
      genus           = .worms_chr(r["genus"])
    )
  })

  rbindlist(rows[!sapply(rows, is.null)], fill = TRUE)
}

.worms_lookup_all <- function(unique_ids, cache_file, overwrite_cache = FALSE,
                               batch_size = 50, delay_sec = 0.5,
                               max_ids = NULL) {
  dir.create(dirname(cache_file), recursive = TRUE, showWarnings = FALSE)

  if (!overwrite_cache && file.exists(cache_file)) {
    message("WoRMS lookup: using cache at ", cache_file)
    cache <- data.table::fread(cache_file, colClasses = "character")
    cache[, aphia_id_query := as.integer(aphia_id_query)]
    ## Check if all requested IDs are in cache
    cached_ids <- cache$aphia_id_query
    missing_ids <- setdiff(unique_ids, cached_ids)
    if (length(missing_ids) == 0) {
      message(sprintf("WoRMS lookup: all %d IDs found in cache", length(unique_ids)))
      return(cache[aphia_id_query %in% unique_ids])
    }
    message(sprintf("WoRMS lookup: %d IDs in cache, %d new IDs to look up",
                    length(intersect(unique_ids, cached_ids)), length(missing_ids)))
    lookup_ids <- missing_ids
  } else {
    lookup_ids <- unique_ids
    cache <- data.table()
  }

  if (!is.null(max_ids)) {
    lookup_ids <- head(lookup_ids, max_ids)
    message(sprintf("WoRMS lookup: limited to first %d IDs (max_aphia_ids set)", max_ids))
  }

  n_batches <- ceiling(length(lookup_ids) / batch_size)
  message(sprintf("WoRMS lookup: looking up %d IDs in %d batches (batch size %d) ...",
                  length(lookup_ids), n_batches, batch_size))

  new_results <- vector("list", n_batches)
  for (i in seq_len(n_batches)) {
    idx_start <- (i - 1) * batch_size + 1
    idx_end   <- min(i * batch_size, length(lookup_ids))
    chunk     <- lookup_ids[idx_start:idx_end]

    new_results[[i]] <- .worms_lookup_batch(chunk)

    if (i %% 10 == 0 || i == n_batches) {
      message(sprintf("  WoRMS: completed batch %d / %d", i, n_batches))
    }

    if (i < n_batches) Sys.sleep(delay_sec)
  }

  new_dt <- rbindlist(new_results[!sapply(new_results, is.null)], fill = TRUE)

  ## Merge with existing cache
  if (nrow(cache) > 0) {
    combined_cache <- rbindlist(list(cache, new_dt), fill = TRUE, use.names = TRUE)
  } else {
    combined_cache <- new_dt
  }

  ## Write updated cache
  data.table::fwrite(combined_cache, cache_file)
  message(sprintf("WoRMS lookup: cache updated -> %s (%d records)",
                  cache_file, nrow(combined_cache)))

  n_resolved <- sum(!is.na(new_dt$valid_name) & nchar(new_dt$valid_name) > 0)
  message(sprintf("WoRMS lookup complete: %d / %d IDs resolved",
                  n_resolved, length(lookup_ids)))

  combined_cache[aphia_id_query %in% unique_ids]
}

## ---- Main function ----------------------------------------------------------
##
## The full data file (data_all_112224.csv) already contains WoRMS-resolved
## taxonomy columns: scientificName, scientificNameAuthorship, phylum, class,
## order, family, genus. No WoRMS API lookup is required when using this file.
##
## The WoRMS lookup helpers above (.worms_lookup_batch, .worms_lookup_all) are
## retained for use with the per-dimension part files (mobs.pt1–6.csv) which
## lack taxonomy. The run_mobs_intake() function auto-detects which schema is
## present and skips the lookup when taxonomy columns are present.
##
## @param dest_dir              Directory for raw downloaded CSV (and WoRMS cache if needed)
## @param output_file           Path for compiled long-format output CSV
## @param overwrite_download    Re-download raw CSV even if cached
## @param overwrite_worms_cache Redo WoRMS lookups even if cache exists (part-file mode only)
## @param max_aphia_ids         For testing: limit WoRMS lookup to first N unique IDs

run_mobs_intake <- function(
    dest_dir              = "providers/mobs/data/raw",
    output_file           = "output/mobs_linear_compiled.csv",
    overwrite_download    = FALSE,
    overwrite_worms_cache = FALSE,
    max_aphia_ids         = NULL
) {
  message("=== MOBS Intake ===")
  message("Citation: ", MOBS_CITATION)

  ## 1. Download ---------------------------------------------------------------
  raw_file <- .mobs_download(dest_dir, overwrite = overwrite_download)

  ## 2. Load -------------------------------------------------------------------
  message(sprintf("Loading rows from raw CSV: %s", raw_file))
  dt <- data.table::fread(
    raw_file,
    encoding   = "UTF-8",
    na.strings = c("", "NA", "N/A", "na", "NULL")
  )
  message(sprintf("MOBS: %d rows loaded", nrow(dt)))

  ## Normalise AphiaID column name (full-data file uses 'valid_aphiaID';
  ## part files use 'valid_AphiaID'). Rename to internal 'valid_AphiaID'.
  if ("valid_aphiaID" %in% names(dt) && !"valid_AphiaID" %in% names(dt)) {
    setnames(dt, "valid_aphiaID", "valid_AphiaID")
  }

  expected_cols <- c("valid_AphiaID", "length_cm", "diameter_width_cm", "height_cm")
  missing_cols  <- setdiff(expected_cols, names(dt))
  if (length(missing_cols) > 0) {
    stop("MOBS: expected columns not found: ", paste(missing_cols, collapse = ", "),
         "\n  Available: ", paste(names(dt), collapse = ", "), call. = FALSE)
  }

  ## Coerce AphiaID to integer; drop rows without one
  dt[, valid_AphiaID := suppressWarnings(as.integer(valid_AphiaID))]
  n_missing_id <- sum(is.na(dt$valid_AphiaID))
  if (n_missing_id > 0) {
    message(sprintf("MOBS: dropping %d rows with NA AphiaID", n_missing_id))
    dt <- dt[!is.na(valid_AphiaID)]
  }

  ## Coerce dimension columns to numeric
  for (col in c("length_cm", "diameter_width_cm", "height_cm")) {
    dt[[col]] <- suppressWarnings(as.numeric(dt[[col]]))
  }

  ## 3. Taxonomy: auto-detect schema -------------------------------------------
  has_taxonomy <- all(c("phylum", "class", "scientificName") %in% names(dt))

  if (has_taxonomy) {
    message("MOBS: taxonomy columns present in source CSV (full data file mode)")
    message("      skipping WoRMS API lookup")
    ## 'kingdom' is not in the full data file; set to "Animalia" (all MOBS taxa)
    if (!"kingdom" %in% names(dt)) dt[, kingdom := "Animalia"]
  } else {
    ## Part-file mode: no names in CSV — must look up via WoRMS REST API
    unique_ids  <- sort(unique(dt$valid_AphiaID))
    message(sprintf("MOBS (part-file mode): found %d unique AphiaIDs", length(unique_ids)))
    cache_file  <- file.path(dest_dir, "worms_name_cache.csv")
    worms_cache <- .worms_lookup_all(
      unique_ids      = unique_ids,
      cache_file      = cache_file,
      overwrite_cache = overwrite_worms_cache,
      max_ids         = max_aphia_ids
    )
    setnames(worms_cache, "aphia_id_query", "valid_AphiaID")
    dt <- merge(dt, worms_cache, by = "valid_AphiaID", all.x = TRUE)
    ## Add optional part-file columns as NA if absent
    for (opt_col in c("scientificName", "scientificNameAuthorship",
                      "Is_Ref_DOI", "Sex", "Specimen_Type", "Biological_Unit")) {
      if (!opt_col %in% names(dt)) dt[[opt_col]] <- NA_character_
    }
  }

  ## 4. Group mapping ----------------------------------------------------------
  ## Map class first (finer resolution), fall back to phylum.
  ## CLASS_TO_GROUP correctly disambiguates Chordata into fish/mammal/bird/reptile.
  dt[, input_taxonomic_group := CLASS_TO_GROUP[class]]
  dt[is.na(input_taxonomic_group), input_taxonomic_group := PHYLUM_TO_GROUP[phylum]]
  dt[is.na(input_taxonomic_group), input_taxonomic_group := "marine_other"]
  ## Log Chordata class-level assignments for audit
  n_chordata <- sum(dt$phylum == "Chordata", na.rm = TRUE)
  if (n_chordata > 0) {
    chordata_tab <- sort(table(dt[phylum == "Chordata", input_taxonomic_group]),
                         decreasing = TRUE)
    message("Chordata class-level breakdown:")
    for (nm in names(chordata_tab)) {
      message(sprintf("  %s: %d rows", nm, chordata_tab[[nm]]))
    }
  }

  ## Ensure optional columns that may be absent in full-data file
  for (opt_col in c("Is_Ref_DOI", "Sex", "Specimen_Type", "Biological_Unit")) {
    if (!opt_col %in% names(dt)) dt[[opt_col]] <- NA_character_
  }
  if (!"valid_name" %in% names(dt)) dt[, valid_name := scientificName]
  if (!"status"     %in% names(dt)) dt[, status     := NA_character_]
  if (!"rank"       %in% names(dt)) dt[, rank        := "species"]

  ## 5. Pivot to long format ---------------------------------------------------
  ## Dimension columns and their controlled vocabulary type
  dim_cols <- list(
    length_cm         = "linear_length",
    diameter_width_cm = "linear_diameter",
    height_cm         = "linear_height"
  )

  ## Add source row index before pivoting
  dt[, .src_row := .I]

  long_list <- lapply(names(dim_cols), function(col) {
    mtype  <- dim_cols[[col]]
    sub_dt <- dt[!is.na(get(col))]
    if (nrow(sub_dt) == 0) return(NULL)

    data.table(
      source_id              = MOBS_SOURCE_ID,
      source_display_name    = MOBS_DISPLAY,
      source_doi             = MOBS_DOI,
      source_access_date     = as.character(Sys.Date()),
      bibliographic_citation = MOBS_CITATION,
      dataset_id             = MOBS_SOURCE_ID,
      original_row_id        = sub_dt$.src_row,
      source_file_path       = raw_file,

      verbatim_taxon_name    = sub_dt$scientificName,           # as-reported in WoRMS-resolved source CSV
      verbatim_authorship    = if ("scientificNameAuthorship" %in% names(sub_dt))
                                 sub_dt$scientificNameAuthorship else NA_character_,
      input_taxonomic_group  = sub_dt$input_taxonomic_group,
      input_taxonomic_rank   = tolower(trimws(sub_dt$rank)),

      resolved_taxon_name    = sub_dt$valid_name,
      resolved_authorship    = NA_character_,
      resolved_taxon_rank    = tolower(trimws(sub_dt$rank)),
      kingdom                = sub_dt$kingdom,  # from WoRMS (Animalia for all marine animals)
      phylum                 = sub_dt$phylum,
      class                  = sub_dt$class,
      order                  = sub_dt$order,
      family                 = sub_dt$family,
      genus                  = sub_dt$genus,
      primary_backbone       = "WoRMS",
      gbif_usage_key         = NA_integer_,
      aphia_id               = sub_dt$valid_AphiaID,
      match_method           = "aphia_id_lookup",  # AphiaID→record; no name matching performed      match_confidence       = "high",
      matched_status         = sub_dt$status,
      reconciliation_note    = NA_character_,

      size_measurement_class = "linear_dimension",
      size_measurement_type  = mtype,
      size_value_cm          = sub_dt[[col]],
      size_value_cm_min      = NA_real_,
      size_value_cm_max      = NA_real_,
      size_dimension_notes   = as.character(sub_dt$Notes),

      mass_g_equiv           = NA_real_,
      lw_conversion_method   = NA_character_,

      life_stage             = NA_character_,
      sex                    = tolower(trimws(sub_dt$Sex)),
      specimen_type          = as.character(sub_dt$Specimen_Type),
      biological_unit        = as.character(sub_dt$Biological_Unit),
      measurement_method     = "literature",
      basis_of_record        = "Literature",

      size_reference_doi     = ifelse(
        !is.na(sub_dt$Is_Ref_DOI) & as.logical(sub_dt$Is_Ref_DOI),
        as.character(sub_dt$Size_Ref),
        NA_character_
      ),  # as.logical() handles TRUE/FALSE/1/0 after fread coercion
      size_reference_text    = as.character(sub_dt$Size_Ref),

      decimal_latitude       = NA_real_,
      decimal_longitude      = NA_real_,
      country_code           = NA_character_,
      ocean_region           = NA_character_,

      worms_valid_name       = sub_dt$valid_name,
      worms_phylum           = sub_dt$phylum,
      worms_class            = sub_dt$class,
      worms_order            = sub_dt$order,
      worms_family           = sub_dt$family,

      size_confidence        = "moderate",
      qa_status              = NA_character_,
      qa_note                = paste0(
        "AphiaID=", sub_dt$valid_AphiaID,
        "; worms_status=", sub_dt$status
      ),

      date_added             = as.character(Sys.Date())
    )
  })

  long_list <- long_list[!sapply(long_list, is.null)]
  out <- rbindlist(long_list, use.names = TRUE, fill = TRUE)

  n_src_rows <- nrow(dt)
  message(sprintf(
    "Pivoting to long format: %d dimension rows from %d source rows",
    nrow(out), n_src_rows
  ))

  ## 6. Summary and write ------------------------------------------------------
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(out, output_file)

  message(sprintf("MOBS compiled: %d rows -> %s", nrow(out), output_file))

  ## Dimension type breakdown
  dim_tab <- sort(table(out$size_measurement_type), decreasing = TRUE)
  message("Dimension type breakdown:")
  for (nm in names(dim_tab)) {
    message(sprintf("  %s: %d rows", nm, dim_tab[[nm]]))
  }

  n_unique_spp <- length(unique(out$worms_valid_name[!is.na(out$worms_valid_name)]))
  message(sprintf("Unique species (valid_name): %d", n_unique_spp))

  invisible(out)
}

## Standalone runner
if (!interactive() && !exists("MOBS_SOURCED_AS_LIBRARY")) {
  run_mobs_intake(
    dest_dir    = "providers/mobs/data/raw",
    output_file = "output/mobs_linear_compiled.csv"
  )
}

MOBS_SOURCED_AS_LIBRARY <- TRUE
