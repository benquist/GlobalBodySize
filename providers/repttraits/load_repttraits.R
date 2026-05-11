## providers/repttraits/load_repttraits.R
## ReptTraits v1-2 — comprehensive reptile ecological trait database
## Meiri S, Aaron S, Beavan A, et al. 2024. ReptTraits: a comprehensive dataset
## of ecological traits in reptiles. Scientific Data 11:386.
## https://doi.org/10.1038/s41597-024-03079-5
## Data: https://doi.org/10.6084/m9.figshare.24572683
##
## Source: Figshare XLSX (~18 MB). First sheet is 'Changes' (metadata log);
##         always read sheet = "Data" explicitly.
##
## Outputs:
##   output/repttraits_mass_compiled.csv   — body mass table (body_mass_schema.R)
##   output/repttraits_linear_compiled.csv — linear size table (body_size_schema.R)
##
## UNVERIFIED: Exact XLSX column names containing embedded double-quotes —
##   confirmed from live Figshare preview but may vary between file versions.
##   If column not found, the script will stop with available column names listed.

suppressPackageStartupMessages({
  library(data.table)
  library(httr)
  library(readxl)
})

## ---- Constants --------------------------------------------------------------

REPTTRAITS_FIGSHARE_FILE_ID <- "45408133"
REPTTRAITS_FIGSHARE_URL     <- "https://ndownloader.figshare.com/files/45408133"
REPTTRAITS_SOURCE_ID        <- "repttraits_meiri2024"
REPTTRAITS_DISPLAY          <- "ReptTraits v1-2 (Meiri et al. 2024)"
REPTTRAITS_DOI              <- "10.1038/s41597-024-03079-5"
REPTTRAITS_DATA_DOI         <- "10.6084/m9.figshare.24572683"
REPTTRAITS_CITATION         <- paste0(
  "Meiri S, Aaron S, Beavan A, et al. 2024. ",
  "ReptTraits: a comprehensive dataset of ecological traits in reptiles. ",
  "Scientific Data 11:386. ",
  "https://doi.org/10.1038/s41597-024-03079-5. ",
  "Data: https://doi.org/10.6084/m9.figshare.24572683"
)

## Mass column (UNVERIFIED: exact name confirmed from live preview; check if version changes)
REPTTRAITS_MASS_COL <- "Maximum body mass (g)"

## Length columns and their metadata.
## Keys are XLSX column names (with embedded double-quotes); values carry dimension
## abbreviation (→ size_dimension_notes) and sex (→ sex field).
## UNVERIFIED: column names with embedded quotes may differ across file versions.
REPTTRAITS_LENGTH_COLS <- list(
  'Maximum total length ("TL", mm)'                                                         = list(dimension = "TL",         sex = NA_character_),
  'Maximum length ("SVL", mm)/straight carapace length for turtles ("SCL", mm)'             = list(dimension = "SVL_SCL",    sex = NA_character_),
  'Maximum female length ("SVL", mm)/straight carapace length for turtles ("SCL", mm)'      = list(dimension = "SVL_female", sex = "female"),
  'Maximum male length ("SVL", mm)/straight carapace length for turtles ("SCL", mm)'        = list(dimension = "SVL_male",   sex = "male")
)

## Order → input_taxonomic_group mapping
ORDER_TO_GROUP <- c(
  "Squamata"        = "reptile",
  "Testudines"      = "reptile",
  "Crocodylia"      = "reptile",
  "Rhynchocephalia" = "reptile",
  "Amphisbaenia"    = "reptile"   # suborder of Squamata; all are reptiles
)

## ---- Download helper --------------------------------------------------------

.repttraits_download <- function(dest_dir, overwrite = FALSE) {
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  dest_file <- file.path(dest_dir, "repttraits_v1-2.xlsx")

  if (file.exists(dest_file) && !overwrite) {
    message("ReptTraits: using cached XLSX at ", dest_file)
    return(dest_file)
  }

  message("ReptTraits: downloading XLSX (~18 MB) from Figshare ...")
  message("  URL: ", REPTTRAITS_FIGSHARE_URL)
  message("  This may take a moment for the ~18 MB file.")

  resp <- tryCatch(
    httr::GET(
      REPTTRAITS_FIGSHARE_URL,
      httr::write_disk(dest_file, overwrite = TRUE),
      httr::timeout(300),
      httr::progress()
    ),
    error = function(e) {
      message("  Download error: ", conditionMessage(e))
      NULL
    }
  )

  if (is.null(resp) || httr::http_error(resp)) {
    stop(
      "ReptTraits: download failed (HTTP ",
      if (!is.null(resp)) httr::status_code(resp) else "?",
      "). URL: ", REPTTRAITS_FIGSHARE_URL,
      call. = FALSE
    )
  }

  if (!file.exists(dest_file) || file.size(dest_file) < 1e5) {
    stop("ReptTraits: downloaded file is missing or too small. Check URL and network.",
         call. = FALSE)
  }

  message(sprintf("ReptTraits: downloaded %.1f MB -> %s",
                  file.size(dest_file) / 1e6, dest_file))
  dest_file
}

## ---- Load sheet helper ------------------------------------------------------

.repttraits_load_sheet <- function(xlsx_file) {
  message("ReptTraits: reading sheet 'Data' from ", basename(xlsx_file))
  ## NOTE: sheet 1 is 'Changes' (metadata log) — always read 'Data' by name
  dt <- as.data.table(
    readxl::read_excel(xlsx_file, sheet = "Data", na = c("", "NA", "N/A"))
  )
  message(sprintf("ReptTraits: %d rows, %d columns loaded from sheet 'Data'",
                  nrow(dt), ncol(dt)))
  dt
}

## ---- Mass table builder -----------------------------------------------------

.repttraits_build_mass <- function(dt) {
  if (!REPTTRAITS_MASS_COL %in% names(dt)) {
    stop(
      "ReptTraits: mass column '", REPTTRAITS_MASS_COL, "' not found in sheet 'Data'.\n",
      "  First 20 available columns: ",
      paste(names(dt)[seq_len(min(20L, ncol(dt)))], collapse = ", "),
      call. = FALSE
    )
  }

  dt[, .src_row := .I]
  dt[, .mass_val := suppressWarnings(as.numeric(get(REPTTRAITS_MASS_COL)))]

  mass_dt <- dt[!is.na(.mass_val)]
  message(sprintf("ReptTraits mass: %d / %d rows have body mass data",
                  nrow(mass_dt), nrow(dt)))

  ## Map Order → group; fallback to "reptile" (all ReptTraits taxa are reptiles)
  grp <- ORDER_TO_GROUP[as.character(mass_dt$Order)]
  grp[is.na(grp)] <- "reptile"

  out <- data.table(
    source_id                  = REPTTRAITS_SOURCE_ID,
    source_display_name        = REPTTRAITS_DISPLAY,
    source_doi                 = REPTTRAITS_DOI,
    source_access_date         = as.character(Sys.Date()),
    bibliographic_citation     = REPTTRAITS_CITATION,
    dataset_id                 = REPTTRAITS_SOURCE_ID,
    original_row_id            = mass_dt$.src_row,
    source_file_path           = "repttraits_v1-2.xlsx",

    verbatim_taxon_name        = as.character(mass_dt$Species),
    verbatim_authorship        = NA_character_,
    input_taxonomic_group      = grp,
    input_taxonomic_rank       = "species",

    resolved_taxon_name        = as.character(mass_dt$Species),
    resolved_authorship        = NA_character_,
    resolved_taxon_rank        = "species",
    resolved_taxonomic_group   = grp,
    kingdom                    = "Animalia",
    phylum                     = NA_character_,    # not in source
    class                      = "Reptilia",       # inferred from dataset scope
    order                      = as.character(mass_dt$Order),
    family                     = as.character(mass_dt$Family),
    genus                      = as.character(mass_dt$Genus),
    primary_backbone           = NA_character_,
    gbif_usage_key             = NA_integer_,
    group_specific_taxon_id    = NA_character_,
    group_specific_backbone    = NA_character_,
    match_method               = "direct_field",
    match_confidence           = "unassessable",
    matched_status             = "unresolved",
    synonym_type               = NA_character_,
    cross_group_collision_flag = NA,
    genus_only_flag            = FALSE,
    reconciliation_note        = "No backbone reconciliation performed; verbatim Species name used directly",
    reconciliation_timestamp_utc = NA_character_,
    backbone_version           = NA_character_,

    ## Mass fields — "Maximum body mass (g)" is already in grams
    mass_g                     = mass_dt$.mass_val,
    mass_g_min                 = NA_real_,
    mass_g_max                 = mass_dt$.mass_val,   # column is maximum reported mass
    mass_se                    = NA_real_,
    mass_n                     = NA_integer_,

    ## mass_type = "literature_maximum": ReptTraits REPTTRAITS_MASS_COL is
    ## 'Maximum body mass (g)' — the maximum recorded body mass across published
    ## literature, NOT a species mean. Do NOT pool with 'wet' (species mean)
    ## values in scaling regressions without stratifying on mass_type.
    ## data_quality_flag = "maximum_not_mean" is set in qa_note.
    mass_type                  = "literature_maximum",
    measurement_method         = "literature_maximum",
    life_stage                 = "adult",
    sex                        = "unknown",

    decimal_latitude           = NA_real_,
    decimal_longitude          = NA_real_,
    coordinate_uncertainty_m   = NA_real_,
    country_code               = NA_character_,

    year_measured              = NA_integer_,
    date_measured              = NA_character_,

    measurement_id             = paste0(REPTTRAITS_SOURCE_ID, "_mass_", mass_dt$.src_row),
    measurement_type           = "body mass",
    measurement_value          = as.character(mass_dt$.mass_val),
    measurement_unit           = "g",
    measurement_determined_date = NA_character_,
    basis_of_record            = "Literature",

    mass_confidence            = "medium",
    range_check_pass           = NA,
    unit_check_pass            = TRUE,
    outlier_flag               = NA,
    qa_status                  = "needs_review",
    qa_note                    = paste0(
      "Maximum body mass (g) from ReptTraits compiled literature; ",
      "mass_type=literature_maximum (maximum recorded, not species mean); ",
      "data_quality_flag=maximum_not_mean; ",
      "backbone reconciliation pending"
    )
  )

  out
}

## ---- Linear size table builder ----------------------------------------------

.repttraits_build_linear <- function(dt) {
  len_col_names <- names(REPTTRAITS_LENGTH_COLS)
  present_cols  <- intersect(len_col_names, names(dt))
  absent_cols   <- setdiff(len_col_names, names(dt))

  if (length(absent_cols) > 0) {
    message("ReptTraits: UNVERIFIED — expected length column(s) not found in sheet 'Data':")
    for (ac in absent_cols) message("  UNVERIFIED: '", ac, "'")
    message("  (Column may be renamed in this file version; check names(dt))")
  }
  if (length(present_cols) == 0) {
    stop("ReptTraits: no length columns found in sheet 'Data'. ",
         "Expected: ", paste(len_col_names, collapse = "; "),
         call. = FALSE)
  }

  dt[, .src_row := .I]

  long_list <- lapply(present_cols, function(col) {
    meta      <- REPTTRAITS_LENGTH_COLS[[col]]
    dim_label <- meta$dimension
    sex_val   <- if (is.na(meta$sex)) "unknown" else meta$sex

    vals    <- suppressWarnings(as.numeric(dt[[col]]))
    sub_dt  <- dt[!is.na(vals)]
    sub_vals <- vals[!is.na(vals)]

    if (nrow(sub_dt) == 0) {
      message(sprintf("ReptTraits linear: '%s' (%s) — 0 non-NA rows, skipping",
                      dim_label, col))
      return(NULL)
    }
    message(sprintf("ReptTraits linear: '%s' (%s) — %d rows",
                    dim_label, col, nrow(sub_dt)))

    grp <- ORDER_TO_GROUP[as.character(sub_dt$Order)]
    grp[is.na(grp)] <- "reptile"

    data.table(
      source_id              = REPTTRAITS_SOURCE_ID,
      source_display_name    = REPTTRAITS_DISPLAY,
      source_doi             = REPTTRAITS_DOI,
      source_access_date     = as.character(Sys.Date()),
      bibliographic_citation = REPTTRAITS_CITATION,
      dataset_id             = REPTTRAITS_SOURCE_ID,
      original_row_id        = sub_dt$.src_row,
      source_file_path       = "repttraits_v1-2.xlsx",

      verbatim_taxon_name    = as.character(sub_dt$Species),
      verbatim_authorship    = NA_character_,
      input_taxonomic_group  = grp,
      input_taxonomic_rank   = "species",

      resolved_taxon_name    = as.character(sub_dt$Species),
      resolved_authorship    = NA_character_,
      resolved_taxon_rank    = "species",
      kingdom                = "Animalia",
      phylum                 = NA_character_,
      class                  = "Reptilia",
      order                  = as.character(sub_dt$Order),
      family                 = as.character(sub_dt$Family),
      genus                  = as.character(sub_dt$Genus),
      primary_backbone       = NA_character_,
      gbif_usage_key         = NA_integer_,
      aphia_id               = NA_integer_,
      match_method           = "direct_field",
      match_confidence       = "unassessable",
      matched_status         = "unresolved",
      reconciliation_note    = "No backbone reconciliation performed; verbatim Species name used directly",

      size_measurement_class = "linear_dimension",
      size_measurement_type  = "linear_length",
      size_value_cm          = sub_vals / 10,     # mm → cm
      size_value_cm_min      = NA_real_,
      size_value_cm_max      = sub_vals / 10,     # column is maximum length
      size_dimension_notes   = dim_label,         # e.g. "TL", "SVL_SCL", "SVL_female", "SVL_male"

      mass_g_equiv           = NA_real_,
      lw_conversion_method   = NA_character_,

      life_stage             = "adult",
      sex                    = sex_val,
      specimen_type          = "unknown",
      biological_unit        = "individual",
      measurement_method     = "literature",
      basis_of_record        = "Literature",

      size_reference_doi     = REPTTRAITS_DOI,
      size_reference_text    = REPTTRAITS_CITATION,

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
        "Maximum length dimension=", dim_label, " from ReptTraits; ",
        "converted from mm to cm; backbone reconciliation pending"
      ),

      date_added             = as.character(Sys.Date())
    )
  })

  long_list <- long_list[!sapply(long_list, is.null)]
  if (length(long_list) == 0) {
    stop("ReptTraits: no linear size rows produced. Check length column names.",
         call. = FALSE)
  }

  out <- rbindlist(long_list, use.names = TRUE, fill = TRUE)
  message(sprintf("ReptTraits linear: %d total rows from %d dimension column(s)",
                  nrow(out), length(long_list)))
  out
}

## ---- Master runner ----------------------------------------------------------

run_repttraits_intake <- function(
  dest_dir           = "providers/repttraits/data/raw",
  output_mass        = "output/repttraits_mass_compiled.csv",
  output_linear      = "output/repttraits_linear_compiled.csv",
  overwrite_download = FALSE
) {
  message("=== ReptTraits Intake ===")
  message("Citation: ", REPTTRAITS_CITATION)

  ## 1. Download XLSX ----------------------------------------------------------
  xlsx_file <- .repttraits_download(dest_dir, overwrite = overwrite_download)

  ## 2. Load sheet "Data" -------------------------------------------------------
  dt <- .repttraits_load_sheet(xlsx_file)

  ## 3. Build and write mass table ---------------------------------------------
  mass_out <- .repttraits_build_mass(dt)
  dir.create(dirname(output_mass), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(mass_out, output_mass)
  message(sprintf("ReptTraits mass compiled:   %d rows -> %s", nrow(mass_out), output_mass))

  ## 4. Build and write linear size table --------------------------------------
  linear_out <- .repttraits_build_linear(dt)
  dir.create(dirname(output_linear), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(linear_out, output_linear)
  message(sprintf("ReptTraits linear compiled: %d rows -> %s", nrow(linear_out), output_linear))

  ## 5. Dimension breakdown summary --------------------------------------------
  dim_tab <- sort(table(linear_out$size_dimension_notes), decreasing = TRUE)
  message("Linear dimension breakdown:")
  for (nm in names(dim_tab)) {
    message(sprintf("  %-15s %d rows", nm, dim_tab[[nm]]))
  }

  n_spp_mass   <- length(unique(mass_out$verbatim_taxon_name))
  n_spp_linear <- length(unique(linear_out$verbatim_taxon_name))
  message(sprintf("Unique species — mass: %d  |  linear: %d", n_spp_mass, n_spp_linear))

  invisible(list(mass = mass_out, linear = linear_out))
}

## ---- Standalone runner ------------------------------------------------------
if (!interactive() && !exists("REPTTRAITS_SOURCED_AS_LIBRARY")) {
  run_repttraits_intake(
    dest_dir      = "providers/repttraits/data/raw",
    output_mass   = "output/repttraits_mass_compiled.csv",
    output_linear = "output/repttraits_linear_compiled.csv"
  )
}

REPTTRAITS_SOURCED_AS_LIBRARY <- TRUE
