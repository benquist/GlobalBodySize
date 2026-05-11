## Global_Plant_BodySize/providers/bien/load_bien_traits.R
## Stages 2 & 3: Bulk trait retrieval from BIEN.
##
## Strategy: BIEN_trait_traitname() fetches ALL records for a given trait
## in one API call — far more efficient than per-species queries for ~150k spp.
##
## Supported BIEN trait names (verify with BIEN_trait_list() before running):
##   "whole plant height"     → measurement_type = height_m    (unit: m)
##   "stem diameter or width" → measurement_type = dbh_cm      (unit: cm)
##   "growth form"            → measurement_type = growth_form  (categorical)
##
## Unit normalization:
##   Height: BIEN typically returns meters; some records report cm — detected
##     from unit column and converted. Records with ambiguous/missing units are
##     assigned trait_value_numeric = NA and flagged in qa_note.
##   DBH: BIEN typically returns cm; mm records are converted.
##
## Citation (UNVERIFIED — confirm before publication):
##   Maitner BS, et al. (2018). The BIEN package: A tool to access the
##   Botanical Information and Ecology Network (BIEN) database.
##   Methods in Ecology and Evolution 9(2):373-379.
##   https://doi.org/10.1111/mee3.12373
##   NOTE: Confirm DOI, journal, volume, and pages against CrossRef before citing.
##
## Written by: Global_Plant_BodySize pipeline (ecology-user agent, 2026-05-11)

## ---- Dependencies -----------------------------------------------------------
if (!requireNamespace("BIEN", quietly = TRUE))
  stop("Install the BIEN package: install.packages('BIEN')")
if (!requireNamespace("data.table", quietly = TRUE))
  stop("Install data.table: install.packages('data.table')")
if (!requireNamespace("dplyr", quietly = TRUE))
  stop("Install dplyr: install.packages('dplyr')")

## ---- Constants --------------------------------------------------------------
BIEN_SOURCE_ID    <- "bien"
BIEN_DISPLAY_NAME <- "BIEN (Botanical Information and Ecology Network)"
## UNVERIFIED DOI below — confirm via CrossRef before publication
BIEN_DOI          <- "10.1111/mee3.12373"
BIEN_CITATION     <- paste0(
  "Maitner BS, Boyle B, Casler N, Condit R, Donoghue J, Duran SM, Guaderrama D, ",
  "Hinchliff CE, Jorgensen PM, Kraft NJ, et al. (2018). The BIEN package: A tool ",
  "to access the Botanical Information and Ecology Network (BIEN) database. ",
  "Methods in Ecology and Evolution 9(2):373-379. ",
  "https://doi.org/10.1111/mee3.12373 [UNVERIFIED — confirm before publication]"
)

## ---- Trait name → measurement type map ------------------------------------
## Extend this map as additional BIEN traits are incorporated.

## Trait name → measurement type map
## Trait names verified against BIEN_trait_list() with BIEN v1.2.8 (2026-05-11).
bien_trait_to_measurement_type <- function(trait_name) {
  switch(
    tolower(trimws(trait_name)),
    "whole plant height"                 = "height_m",
    "maximum whole plant height"         = "height_m_max",
    "minimum whole plant height"         = "height_m_min",
    "diameter at breast height (1.3 m)" = "dbh_cm",
    "whole plant growth form"            = "growth_form",
    "whole plant woodiness"              = "woodiness",
    "leaf area"                          = "other_size",
    "stem wood density"                  = "wood_density",
    "other_size"             # default for unrecognized traits
  )
}

## ---- Unit normalization: height → meters ------------------------------------
## Returns normalized numeric value in meters, or NA if unit is unrecognized.

normalize_height_to_m <- function(value, unit) {
  unit <- tolower(trimws(as.character(unit)))
  dplyr::case_when(
    unit %in% c("m", "meter", "meters")               ~ value,
    unit %in% c("cm", "centimeter", "centimeters")     ~ value / 100,
    unit %in% c("mm", "millimeter", "millimeters")     ~ value / 1000,
    unit %in% c("ft", "feet", "foot")                  ~ value * 0.3048,
    TRUE ~ NA_real_   # unknown unit — set NA and flag in qa_note
  )
}

## ---- Unit normalization: diameter → centimeters ----------------------------
## Returns normalized numeric value in cm, or NA if unit is unrecognized.

normalize_dbh_to_cm <- function(value, unit) {
  unit <- tolower(trimws(as.character(unit)))
  dplyr::case_when(
    unit %in% c("cm", "centimeter", "centimeters")     ~ value,
    unit %in% c("m", "meter", "meters")                ~ value * 100,
    unit %in% c("mm", "millimeter", "millimeters")     ~ value / 10,
    TRUE ~ NA_real_
  )
}

## ---- Safe column extractor --------------------------------------------------
## Tries each candidate column name in order; returns NA vector if none found.

get_col_safe <- function(df, candidates, type = "character") {
  for (cand in candidates) {
    if (cand %in% names(df)) {
      val <- df[[cand]]
      if (type == "numeric") return(suppressWarnings(as.numeric(val)))
      return(as.character(val))
    }
  }
  if (type == "numeric") return(rep(NA_real_, nrow(df)))
  rep(NA_character_, nrow(df))
}

## ---- Map BIEN trait output to canonical schema ------------------------------
## raw_df        : output of BIEN_trait_traitname() — column names vary by version
## measurement_type: e.g. "height_m", "dbh_cm", "growth_form"
## Returns data.frame conforming to plantsize_raw_schema_columns()

map_bien_trait_to_schema <- function(raw_df, measurement_type) {
  n <- nrow(raw_df)

  ## ---- Extract columns using multiple candidate names (BIEN version resilience) --
  verbatim_name <- get_col_safe(raw_df,
    c("scrubbed_species_binomial", "species_binomial", "species", "taxon_name"))
  family        <- get_col_safe(raw_df, c("family", "scrubbed_family"))
  higher_pg     <- get_col_safe(raw_df, c("higher_plant_group", "plant_group"))
  trait_val_raw <- get_col_safe(raw_df, c("trait_value"))
  unit_raw      <- get_col_safe(raw_df, c("unit"))
  trait_nm      <- get_col_safe(raw_df, c("trait_name"))
  obs_type      <- get_col_safe(raw_df, c("observation_type"))
  lat           <- get_col_safe(raw_df, c("latitude"), type = "numeric")
  lon           <- get_col_safe(raw_df, c("longitude"), type = "numeric")
  date_col      <- get_col_safe(raw_df, c("date_collected", "date"))
  plot_nm       <- get_col_safe(raw_df, c("plot_name", "plot"))
  pi_col        <- get_col_safe(raw_df, c("project_pi", "pi", "contributor"))
  ref_col       <- get_col_safe(raw_df, c("reference_number", "reference_id"))

  ## ---- Parse numeric trait value ------------------------------------------
  val_numeric <- suppressWarnings(as.numeric(trait_val_raw))

  ## ---- Normalize units and values by measurement type ---------------------
  qa_note         <- rep(NA_character_, n)
  unit_canonical  <- rep(NA_character_, n)

  if (measurement_type == "height_m") {
    val_normalized <- normalize_height_to_m(val_numeric, unit_raw)
    unit_canonical <- rep("m", n)
    ## Flag records where normalization yielded NA due to unknown unit
    bad_unit <- is.na(val_normalized) & !is.na(val_numeric)
    qa_note[bad_unit] <- paste0(
      "Unknown height unit: '", unit_raw[bad_unit], "'; trait_value_numeric set NA"
    )

  } else if (measurement_type == "dbh_cm") {
    val_normalized <- normalize_dbh_to_cm(val_numeric, unit_raw)
    unit_canonical <- rep("cm", n)
    bad_unit <- is.na(val_normalized) & !is.na(val_numeric)
    qa_note[bad_unit] <- paste0(
      "Unknown DBH unit: '", unit_raw[bad_unit], "'; trait_value_numeric set NA"
    )

  } else if (measurement_type == "growth_form") {
    val_normalized <- val_numeric   # typically NA for categorical
    unit_canonical <- rep("categorical", n)

  } else {
    val_normalized <- val_numeric
  }

  ## ---- Parse genus from species name --------------------------------------
  genus <- sub(" .*", "", verbatim_name)

  ## ---- Assemble output data.frame -----------------------------------------
  out <- data.frame(
    source_id              = BIEN_SOURCE_ID,
    source_display_name    = BIEN_DISPLAY_NAME,
    source_doi             = BIEN_DOI,
    source_access_date     = as.character(Sys.Date()),
    bibliographic_citation = BIEN_CITATION,
    verbatim_species_name  = verbatim_name,
    higher_plant_group     = higher_pg,
    family                 = family,
    genus                  = genus,
    subfamily              = NA_character_,  # BIEN does not typically return subfamily
    bien_trait_name        = trait_nm,
    trait_value_verbatim   = trait_val_raw,
    trait_value_numeric    = val_normalized,
    trait_unit_verbatim    = unit_raw,
    trait_unit_canonical   = unit_canonical,
    measurement_type       = measurement_type,
    observation_type       = obs_type,
    latitude               = lat,
    longitude              = lon,
    date_collected         = date_col,
    plot_name              = plot_nm,
    project_pi             = pi_col,
    reference_number       = ref_col,
    range_check_pass       = NA,        # populated in Stage 6
    unit_check_pass        = NA,
    outlier_flag           = NA,
    qa_note                = qa_note,
    stringsAsFactors       = FALSE
  )

  out
}

## ---- Main intake function ---------------------------------------------------
## trait_name  : exact BIEN trait name string (e.g. "whole plant height")
## output_file : path to write output CSV
## overwrite   : if FALSE (default), skip if output already exists
##
## Returns: data.frame (invisibly)

run_bien_trait_intake <- function(
    trait_name,
    output_file,
    overwrite = FALSE
) {
  measurement_type <- bien_trait_to_measurement_type(trait_name)

  if (file.exists(output_file) && !overwrite) {
    message("[Trait intake] File exists: ", output_file,
            "\n  Use overwrite=TRUE to re-query BIEN.")
    return(invisible(data.table::fread(output_file, data.table = FALSE)))
  }

  message("[Trait intake] Querying BIEN for trait: '", trait_name, "'")
  message("  Measurement type resolved to: ", measurement_type)
  message("  This may take several minutes for large traits...")

  ## NOTE 2026-05-11: Verified against ls('package:BIEN') with BIEN v1.2.8.
  ## The correct function is BIEN_trait_trait(), not BIEN_trait_traitname().
  raw <- tryCatch(
    BIEN::BIEN_trait_trait(trait_name),
    error = function(e) stop(
      "[Trait intake] BIEN_trait_trait('", trait_name, "') failed: ",
      conditionMessage(e)
    )
  )

  if (is.null(raw) || nrow(raw) == 0) {
    warning("[Trait intake] No records returned for trait: '", trait_name, "'")
    ## Write empty file so downstream stages don't break
    out <- data.frame(matrix(ncol = 27, nrow = 0))
    names(out) <- c(
      "source_id", "source_display_name", "source_doi", "source_access_date",
      "bibliographic_citation", "verbatim_species_name", "higher_plant_group",
      "family", "genus", "subfamily", "bien_trait_name", "trait_value_verbatim",
      "trait_value_numeric", "trait_unit_verbatim", "trait_unit_canonical",
      "measurement_type", "observation_type", "latitude", "longitude",
      "date_collected", "plot_name", "project_pi", "reference_number",
      "range_check_pass", "unit_check_pass", "outlier_flag", "qa_note"
    )
  } else {
    out <- map_bien_trait_to_schema(raw, measurement_type)
  }

  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(out, output_file)

  message("[Trait intake] Done. ", nrow(out), " records written to: ", output_file)
  invisible(out)
}
