## providers/neon/load_neon.R
## NEON Small Mammal Trapping — body mass intake
## Source: NEON DP1.10072.001 (Small mammal box trapping)
## Access: neonUtilities::loadByProduct(); no API key required
## Output schema: GlobalBodySize standard schema (mass_g in grams)
## Coverage: ~150 small mammal species, North America
## Note: Weight field is in grams. Multiple captures per individual exist —
##       this script takes the maximum recorded weight per species per sex/lifestage
##       to yield a representative adult body mass estimate.

## DEPENDENCIES ---------------------------------------------------------------
suppressPackageStartupMessages({
  library(neonUtilities)   # CRAN — NEON data API client
  library(data.table)      # fast I/O
})

## CONSTANTS -------------------------------------------------------------------
NEON_SOURCE_ID       <- "NEON_DP1.10072.001"
NEON_DISPLAY         <- "NEON Small Mammal Trapping (DP1.10072.001)"
NEON_DOI             <- "10.48443/s4ph-2z37"   ## NEON small mammal dataset DOI
NEON_CITATION        <- paste0(
  "National Ecological Observatory Network (NEON). Small mammal box trapping ",
  "(DP1.10072.001). Battelle, Boulder, CO, USA. https://doi.org/10.48443/s4ph-2z37")

## MAIN FUNCTION ---------------------------------------------------------------
## @param output_file  Path for the compiled output CSV
## @param startdate   YYYY-MM format; NULL = earliest available
## @param enddate     YYYY-MM format; NULL = latest available
## @param check.size  Passed to neonUtilities::loadByProduct(); FALSE skips size prompt
run_neon_intake <- function(
    output_file = "output/neon_compiled.csv",
    startdate   = NULL,
    enddate     = NULL,
    check.size  = FALSE
) {
  message("=== NEON Small Mammal Intake ===")

  ## Download all NEON sites for DP1.10072.001
  ## loadByProduct returns a named list; pertrapnight is the per-capture table
  message("Downloading NEON DP1.10072.001 (all sites) — this may take several minutes...")
  neon_data <- tryCatch(
    neonUtilities::loadByProduct(
      dpID       = "DP1.10072.001",
      site       = "all",
      startdate  = startdate,
      enddate    = enddate,
      check.size = check.size,
      package    = "basic",
      release    = "current"
    ),
    error = function(e) {
      stop("neonUtilities::loadByProduct() failed: ", conditionMessage(e), call. = FALSE)
    }
  )

  ## The per-capture table
  if (!"mam_pertrapnight" %in% names(neon_data)) {
    stop("Expected table 'mam_pertrapnight' not found in NEON download. ",
         "Available tables: ", paste(names(neon_data), collapse=", "), call. = FALSE)
  }
  cap <- as.data.frame(neon_data[["mam_pertrapnight"]])
  message(sprintf("NEON: %d capture records loaded", nrow(cap)))

  ## Filter to captured individuals with a recorded weight
  ## trapStatus == "5 - capture" means an animal was caught
  cap <- cap[!is.na(cap$weight) & cap$weight > 0, ]
  cap <- cap[grepl("capture", cap$trapStatus, ignore.case = TRUE), ]
  message(sprintf("NEON: %d records with weight after trap-status filter", nrow(cap)))

  ## taxonID is the NEON species code; scientificName is the binomial
  if (!"scientificName" %in% names(cap)) {
    stop("Column 'scientificName' not found. Check NEON schema version.", call. = FALSE)
  }

  ## Aggregate: max weight per species, sex, lifeStage
  ## Using max weight as a representative body mass (analogous to literature max)
  agg <- aggregate(
    weight ~ scientificName + taxonID + sex + lifeStage,
    data = cap,
    FUN  = function(x) max(x, na.rm = TRUE)
  )
  names(agg)[names(agg) == "weight"] <- "mass_g"

  ## Also record sample size
  n_cap <- aggregate(
    weight ~ scientificName + taxonID + sex + lifeStage,
    data = cap,
    FUN  = length
  )
  names(n_cap)[names(n_cap) == "weight"] <- "n_captures"
  agg <- merge(agg, n_cap, by = c("scientificName", "taxonID", "sex", "lifeStage"))

  message(sprintf("NEON: %d species x sex x lifeStage rows after aggregation", nrow(agg)))

  ## Normalize sex / lifeStage for schema
  agg$sex_norm       <- tolower(trimws(agg$sex))
  agg$sex_norm[agg$sex_norm %in% c("", "u", "unknown")] <- "unknown"
  agg$lifestage_norm <- tolower(trimws(agg$lifeStage))
  agg$lifestage_norm[agg$lifestage_norm %in% c("", "u", "unknown", NA)] <- "unknown"

  ## Map to GlobalBodySize schema
  out <- data.frame(
    source_id              = NEON_SOURCE_ID,
    source_display_name    = NEON_DISPLAY,
    source_doi             = NEON_DOI,
    source_access_date     = as.character(Sys.Date()),
    bibliographic_citation = NEON_CITATION,
    dataset_id             = NEON_SOURCE_ID,
    original_row_id        = seq_len(nrow(agg)),
    source_file_path       = "neonUtilities_api",

    verbatim_taxon_name    = agg$scientificName,
    verbatim_authorship    = NA_character_,
    input_taxonomic_group  = "mammalia",
    input_taxonomic_rank   = "species",

    mass_g                 = agg$mass_g,
    mass_g_min             = NA_real_,
    mass_g_max             = NA_real_,
    mass_se                = NA_real_,
    mass_n                 = agg$n_captures,

    mass_type              = "wet",
    measurement_method     = "field_trapping_max_weight",
    life_stage             = agg$lifestage_norm,
    sex                    = agg$sex_norm,

    decimal_latitude       = NA_real_,
    decimal_longitude      = NA_real_,
    coordinate_uncertainty_m = NA_real_,
    country_code           = "US",

    year_measured          = NA_integer_,
    date_measured          = NA_character_,

    measurement_type       = "body mass",
    measurement_unit       = "g",
    basis_of_record        = "HumanObservation",

    mass_confidence        = "high",
    qa_note                = sprintf("NEON_taxonID=%s; max weight from %d captures across all sites",
                                     agg$taxonID, agg$n_captures),
    qa_status              = NA_character_,

    stringsAsFactors = FALSE
  )

  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(out, output_file)
  message(sprintf("NEON compiled: %d rows -> %s", nrow(out), output_file))
  invisible(out)
}
