## providers/disperse/load_disperse.R
## DISPERSE — trait database for dispersal potential of European aquatic macroinvertebrates
## Sarremejane R, Cid N, Stubbington R, et al. 2020.
## Scientific Data 7:386. https://doi.org/10.1038/s41597-020-00732-7
## Data: https://doi.org/10.6084/m9.figshare.12417251.v1
##
## Source: Figshare XLSX. Sheets: DataKey, Data, Reference list.
##         Always read sheet = "Data".
## Taxonomy: genus-level records (aquatic macroinvertebrates); no species backbone used.
## Size columns confirmed from live check:
##   "Maximum body size (cm)" — already in cm; size_dimension_notes = "body_length_max"
##   "Female wing length (mm)" — optional; divide by 10 for cm; sex = "female"
##
## UNVERIFIED: Taxonomy column names (Order, Family, Genus) — identified dynamically
##   via case-insensitive grep; logged to console if not found.
##
## Output:
##   output/disperse_linear_compiled.csv — linear size table (body_size_schema.R)

suppressPackageStartupMessages({
  library(data.table)
  library(httr)
  library(readxl)
})

## ---- Constants --------------------------------------------------------------

DISPERSE_FIGSHARE_FILE_ID <- "24964343"
DISPERSE_FIGSHARE_URL     <- "https://ndownloader.figshare.com/files/24964343"
DISPERSE_SOURCE_ID        <- "disperse_sarremejane2020"
DISPERSE_DISPLAY          <- "DISPERSE (Sarremejane et al. 2020)"
DISPERSE_DOI              <- "10.1038/s41597-020-00732-7"
DISPERSE_DATA_DOI         <- "10.6084/m9.figshare.12417251.v1"
DISPERSE_CITATION         <- paste0(
  "Sarremejane R, Cid N, Stubbington R, et al. 2020. ",
  "DISPERSE, a trait database to assess the dispersal potential of ",
  "European aquatic macroinvertebrates. ",
  "Scientific Data 7:386. ",
  "https://doi.org/10.1038/s41597-020-00732-7. ",
  "Data: https://doi.org/10.6084/m9.figshare.12417251.v1"
)

## Size column names confirmed from live Figshare file preview
DISPERSE_BODY_SIZE_COL   <- "Maximum body size (cm)"
DISPERSE_WING_LENGTH_COL <- "Female wing length (mm)"   # mm → /10 → cm

## ---- Download helper --------------------------------------------------------

.disperse_download <- function(dest_dir, overwrite = FALSE) {
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  dest_file <- file.path(dest_dir, "disperse.xlsx")

  if (file.exists(dest_file) && !overwrite) {
    message("DISPERSE: using cached XLSX at ", dest_file)
    return(dest_file)
  }

  message("DISPERSE: downloading XLSX from Figshare ...")
  message("  URL: ", DISPERSE_FIGSHARE_URL)

  resp <- tryCatch(
    httr::GET(
      DISPERSE_FIGSHARE_URL,
      httr::write_disk(dest_file, overwrite = TRUE),
      httr::timeout(120),
      httr::progress()
    ),
    error = function(e) {
      message("  Download error: ", conditionMessage(e))
      NULL
    }
  )

  if (is.null(resp) || httr::http_error(resp)) {
    stop(
      "DISPERSE: download failed (HTTP ",
      if (!is.null(resp)) httr::status_code(resp) else "?",
      "). URL: ", DISPERSE_FIGSHARE_URL,
      call. = FALSE
    )
  }

  if (!file.exists(dest_file) || file.size(dest_file) < 1000) {
    stop("DISPERSE: downloaded file is missing or too small.", call. = FALSE)
  }

  message(sprintf("DISPERSE: downloaded %.1f KB -> %s",
                  file.size(dest_file) / 1e3, dest_file))
  dest_file
}

## ---- Load sheet helper ------------------------------------------------------

.disperse_load_sheet <- function(xlsx_file) {
  message("DISPERSE: reading sheet 'Data' from ", basename(xlsx_file))
  dt <- as.data.table(
    readxl::read_excel(xlsx_file, sheet = "Data", na = c("", "NA", "N/A"))
  )
  message(sprintf("DISPERSE: %d rows, %d columns loaded", nrow(dt), ncol(dt)))
  message("DISPERSE: first 8 column names: ",
          paste(names(dt)[seq_len(min(8L, ncol(dt)))], collapse = " | "))
  dt
}

## ---- Taxonomy column finder -------------------------------------------------
## UNVERIFIED: column names found via case-insensitive grep.
## Logs a warning if a taxonomy column is absent.

.disperse_find_taxon_col <- function(nms, patterns, label) {
  for (p in patterns) {
    m <- grep(p, nms, ignore.case = TRUE, value = TRUE, perl = TRUE)
    if (length(m) > 0) return(m[1])
  }
  message("DISPERSE: UNVERIFIED — '", label, "' column not found; ",
          "tried patterns: ", paste(patterns, collapse = ", "))
  NA_character_
}

## ---- Build linear size table ------------------------------------------------

.disperse_build_linear <- function(dt, xlsx_file) {
  nms <- names(dt)

  ## Identify taxonomy columns (UNVERIFIED names — found dynamically)
  order_col  <- .disperse_find_taxon_col(nms, c("^order$",  "order"),  "Order")
  family_col <- .disperse_find_taxon_col(nms, c("^family$", "family"), "Family")
  genus_col  <- .disperse_find_taxon_col(nms, c("^genus$",  "genus"),  "Genus")

  ## Add taxonomy vectors as columns for safe row-parallel access
  dt$order_val  <- if (!is.na(order_col))  as.character(dt[[order_col]])  else rep(NA_character_, nrow(dt))
  dt$family_val <- if (!is.na(family_col)) as.character(dt[[family_col]]) else rep(NA_character_, nrow(dt))
  dt$genus_val  <- if (!is.na(genus_col))  as.character(dt[[genus_col]])  else rep(NA_character_, nrow(dt))

  ## verbatim_taxon_name: prefer genus; fall back to order value
  dt$verbatim_val <- ifelse(
    !is.na(dt$genus_val),
    dt$genus_val,
    ifelse(!is.na(dt$order_val), dt$order_val, NA_character_)
  )

  dt[, .src_row := .I]

  ## ---- Dimension 1: Maximum body size (cm) ----------------------------------

  if (!DISPERSE_BODY_SIZE_COL %in% names(dt)) {
    stop(
      "DISPERSE: body size column '", DISPERSE_BODY_SIZE_COL, "' not found.\n",
      "  First 20 available columns: ",
      paste(names(dt)[seq_len(min(20L, ncol(dt)))], collapse = ", "),
      call. = FALSE
    )
  }

  body_size_vals <- suppressWarnings(as.numeric(dt[[DISPERSE_BODY_SIZE_COL]]))
  body_dt        <- dt[!is.na(body_size_vals)]
  body_vals_cm   <- body_size_vals[!is.na(body_size_vals)]

  message(sprintf("DISPERSE body size: %d / %d rows have '%s'",
                  nrow(body_dt), nrow(dt), DISPERSE_BODY_SIZE_COL))

  body_rows <- data.table(
    source_id              = DISPERSE_SOURCE_ID,
    source_display_name    = DISPERSE_DISPLAY,
    source_doi             = DISPERSE_DOI,
    source_access_date     = as.character(Sys.Date()),
    bibliographic_citation = DISPERSE_CITATION,
    dataset_id             = DISPERSE_SOURCE_ID,
    original_row_id        = body_dt$.src_row,
    source_file_path       = basename(xlsx_file),

    verbatim_taxon_name    = body_dt$verbatim_val,
    verbatim_authorship    = NA_character_,
    input_taxonomic_group  = "macroinvertebrate",
    input_taxonomic_rank   = "genus",

    resolved_taxon_name    = body_dt$verbatim_val,
    resolved_authorship    = NA_character_,
    resolved_taxon_rank    = "genus",
    kingdom                = "Animalia",
    phylum                 = NA_character_,
    class                  = NA_character_,
    order                  = body_dt$order_val,
    family                 = body_dt$family_val,
    genus                  = body_dt$genus_val,
    primary_backbone       = NA_character_,
    gbif_usage_key         = NA_integer_,
    aphia_id               = NA_integer_,
    match_method           = "direct_field",
    match_confidence       = "unassessable",
    matched_status         = "unresolved",
    reconciliation_note    = "Genus-level taxonomy; no species-level backbone lookup performed",

    size_measurement_class = "linear_dimension",
    size_measurement_type  = "linear_length",
    size_value_cm          = body_vals_cm,      # already in cm per column name
    size_value_cm_min      = NA_real_,
    size_value_cm_max      = body_vals_cm,      # maximum body size
    size_dimension_notes   = "body_length_max",

    mass_g_equiv           = NA_real_,
    lw_conversion_method   = NA_character_,

    life_stage             = "adult",
    sex                    = "unknown",
    specimen_type          = "unknown",
    biological_unit        = "individual",
    measurement_method     = "literature",
    basis_of_record        = "Literature",

    size_reference_doi     = DISPERSE_DOI,
    size_reference_text    = DISPERSE_CITATION,

    decimal_latitude       = NA_real_,
    decimal_longitude      = NA_real_,
    country_code           = NA_character_,
    ocean_region           = NA_character_,

    worms_valid_name       = NA_character_,
    worms_phylum           = NA_character_,
    worms_class            = NA_character_,
    worms_order            = NA_character_,
    worms_family           = NA_character_,

    size_confidence        = "medium",
    qa_status              = "needs_review",
    qa_note                = paste0(
      "Maximum body size (cm) from DISPERSE; genus-level record; ",
      "backbone reconciliation pending"
    ),

    date_added             = as.character(Sys.Date())
  )

  ## ---- Dimension 2: Female wing length (mm) → cm (optional) ----------------

  wing_rows <- NULL
  if (DISPERSE_WING_LENGTH_COL %in% names(dt)) {
    wing_vals_mm <- suppressWarnings(as.numeric(dt[[DISPERSE_WING_LENGTH_COL]]))
    wing_dt      <- dt[!is.na(wing_vals_mm)]
    wing_vals_cm <- wing_vals_mm[!is.na(wing_vals_mm)] / 10   # mm → cm

    message(sprintf("DISPERSE wing length: %d / %d rows have '%s'",
                    nrow(wing_dt), nrow(dt), DISPERSE_WING_LENGTH_COL))

    wing_rows <- data.table(
      source_id              = DISPERSE_SOURCE_ID,
      source_display_name    = DISPERSE_DISPLAY,
      source_doi             = DISPERSE_DOI,
      source_access_date     = as.character(Sys.Date()),
      bibliographic_citation = DISPERSE_CITATION,
      dataset_id             = DISPERSE_SOURCE_ID,
      original_row_id        = wing_dt$.src_row,
      source_file_path       = basename(xlsx_file),

      verbatim_taxon_name    = wing_dt$verbatim_val,
      verbatim_authorship    = NA_character_,
      input_taxonomic_group  = "macroinvertebrate",
      input_taxonomic_rank   = "genus",

      resolved_taxon_name    = wing_dt$verbatim_val,
      resolved_authorship    = NA_character_,
      resolved_taxon_rank    = "genus",
      kingdom                = "Animalia",
      phylum                 = NA_character_,
      class                  = NA_character_,
      order                  = wing_dt$order_val,
      family                 = wing_dt$family_val,
      genus                  = wing_dt$genus_val,
      primary_backbone       = NA_character_,
      gbif_usage_key         = NA_integer_,
      aphia_id               = NA_integer_,
      match_method           = "direct_field",
      match_confidence       = "unassessable",
      matched_status         = "unresolved",
      reconciliation_note    = "Genus-level taxonomy; no species-level backbone lookup performed",

      size_measurement_class = "linear_dimension",
      size_measurement_type  = "linear_length",
      size_value_cm          = wing_vals_cm,
      size_value_cm_min      = NA_real_,
      size_value_cm_max      = wing_vals_cm,
      size_dimension_notes   = "wing_length_female",

      mass_g_equiv           = NA_real_,
      lw_conversion_method   = NA_character_,

      life_stage             = "adult",
      sex                    = "female",
      specimen_type          = "unknown",
      biological_unit        = "individual",
      measurement_method     = "literature",
      basis_of_record        = "Literature",

      size_reference_doi     = DISPERSE_DOI,
      size_reference_text    = DISPERSE_CITATION,

      decimal_latitude       = NA_real_,
      decimal_longitude      = NA_real_,
      country_code           = NA_character_,
      ocean_region           = NA_character_,

      worms_valid_name       = NA_character_,
      worms_phylum           = NA_character_,
      worms_class            = NA_character_,
      worms_order            = NA_character_,
      worms_family           = NA_character_,

      size_confidence        = "medium",
      qa_status              = "needs_review",
      qa_note                = paste0(
        "Female wing length from DISPERSE; converted mm to cm; ",
        "genus-level record; backbone reconciliation pending"
      ),

      date_added             = as.character(Sys.Date())
    )
  } else {
    message("DISPERSE: UNVERIFIED — '", DISPERSE_WING_LENGTH_COL,
            "' column not found; wing length rows skipped")
  }

  ## Combine all dimension rows
  parts <- list(body_rows)
  if (!is.null(wing_rows) && nrow(wing_rows) > 0) {
    parts <- c(parts, list(wing_rows))
  }

  out <- rbindlist(parts, use.names = TRUE, fill = TRUE)

  message(sprintf("DISPERSE linear: %d total rows", nrow(out)))
  dim_tab <- sort(table(out$size_dimension_notes), decreasing = TRUE)
  message("Dimension breakdown:")
  for (nm in names(dim_tab)) {
    message(sprintf("  %-25s %d rows", nm, dim_tab[[nm]]))
  }

  out
}

## ---- Master runner ----------------------------------------------------------

run_disperse_intake <- function(
  dest_dir           = "providers/disperse/data/raw",
  output_file        = "output/disperse_linear_compiled.csv",
  overwrite_download = FALSE
) {
  message("=== DISPERSE Intake ===")
  message("Citation: ", DISPERSE_CITATION)

  ## 1. Download XLSX ----------------------------------------------------------
  xlsx_file <- .disperse_download(dest_dir, overwrite = overwrite_download)

  ## 2. Load sheet "Data" -------------------------------------------------------
  dt <- .disperse_load_sheet(xlsx_file)

  ## 3. Build and write linear size table --------------------------------------
  linear_out <- .disperse_build_linear(dt, xlsx_file)

  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(linear_out, output_file)
  message(sprintf("DISPERSE compiled: %d rows -> %s", nrow(linear_out), output_file))

  n_genera <- length(unique(linear_out$verbatim_taxon_name[
    !is.na(linear_out$verbatim_taxon_name)
  ]))
  message(sprintf("Unique genera: %d", n_genera))

  invisible(linear_out)
}

## ---- Standalone runner ------------------------------------------------------
if (!interactive() && !exists("DISPERSE_SOURCED_AS_LIBRARY")) {
  run_disperse_intake(
    dest_dir    = "providers/disperse/data/raw",
    output_file = "output/disperse_linear_compiled.csv"
  )
}

DISPERSE_SOURCED_AS_LIBRARY <- TRUE
