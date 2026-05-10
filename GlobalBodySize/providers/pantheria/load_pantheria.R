## GlobalBodySize/providers/pantheria/load_pantheria.R
## Intake script for PanTHERIA mammal body mass database
## Jones KE, et al. 2009. Ecology 90(9):2648. DOI: 10.1890/08-1494.1
##
## Source: ESA Ecological Archives E090-184-D1
## URL: https://esapubs.org/archive/ecol/E090/184/
## NOTE: URL UNVERIFIED — confirm ESA archive is serving this file
##
## Output: data.frame conforming to GlobalBodySize schema (body_mass_schema.R)
## Tier A data source (merow-ecology advisory)

source(file.path(dirname(dirname(dirname(sys.frame(1)$ofile))), "R", "body_mass_schema.R"))

PANTHERIA_URL <- "https://esapubs.org/archive/ecol/E090/184/PanTHERIA_1-0_WR05_Aug2008.txt"
## UNVERIFIED: confirm filename and URL

PANTHERIA_SOURCE_ID  <- "pantheria_jones2009"
PANTHERIA_DISPLAY    <- "PanTHERIA v1.0 (Jones et al. 2009)"
PANTHERIA_DOI        <- "10.1890/08-1494.1"  # UNVERIFIED — confirm DOI
PANTHERIA_CITATION   <- "Jones KE, Bielby J, Cardillo M, Fritz SA, O'Dell J, et al. 2009. PanTHERIA: a species-level database of life history, ecology, and geography of extant and recently extinct mammals. Ecology 90(9):2648. https://doi.org/10.1890/08-1494.1"

## ---- Download PanTHERIA if not cached ---------------------------------------

download_pantheria <- function(dest_dir = "data/raw/pantheria",
                               overwrite = FALSE) {
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  dest_file <- file.path(dest_dir, "PanTHERIA_raw.txt")
  if (file.exists(dest_file) && !overwrite) {
    message("PanTHERIA already downloaded: ", dest_file)
    return(dest_file)
  }
  message("Downloading PanTHERIA from: ", PANTHERIA_URL)
  tryCatch(
    download.file(PANTHERIA_URL, dest_file, mode = "wb"),
    error = function(e) stop("Failed to download PanTHERIA. Verify URL: ", PANTHERIA_URL, call. = FALSE)
  )
  dest_file
}

## ---- Parse and map PanTHERIA to GlobalBodySize schema -----------------------

parse_pantheria <- function(raw_file) {
  raw <- data.table::fread(raw_file, sep = "\t", na.strings = c("-999", "-999.0", "NA", ""),
                           data.table = FALSE)

  ## PanTHERIA mass column: "5-1_AdultBodyMass_g" (UNVERIFIED — confirm column name)
  mass_col <- grep("AdultBodyMass_g", names(raw), value = TRUE)[1]
  if (is.na(mass_col)) stop("Cannot find adult body mass column in PanTHERIA. Check column names.")

  species_col <- "MSW05_Binomial"  # UNVERIFIED — confirm column name

  out <- data.frame(
    source_id              = PANTHERIA_SOURCE_ID,
    source_display_name    = PANTHERIA_DISPLAY,
    source_doi             = PANTHERIA_DOI,
    source_access_date     = as.character(Sys.Date()),
    bibliographic_citation = PANTHERIA_CITATION,
    dataset_id             = PANTHERIA_SOURCE_ID,
    original_row_id        = seq_len(nrow(raw)),
    source_file_path       = basename(raw_file),

    verbatim_taxon_name    = raw[[species_col]],
    verbatim_authorship    = NA_character_,
    input_taxonomic_group  = "mammal",
    input_taxonomic_rank   = "species",

    mass_g                 = suppressWarnings(as.numeric(raw[[mass_col]])),
    mass_g_min             = NA_real_,
    mass_g_max             = NA_real_,
    mass_se                = NA_real_,
    mass_n                 = NA_integer_,

    mass_type              = "wet",  # PanTHERIA values are live wet mass means
    measurement_method     = "literature_mean",
    life_stage             = "adult",
    sex                    = "pooled",

    decimal_latitude       = NA_real_,
    decimal_longitude      = NA_real_,
    coordinate_uncertainty_m = NA_real_,
    country_code           = NA_character_,

    year_measured          = NA_integer_,
    date_measured          = NA_character_,

    measurement_type       = "body mass",
    measurement_unit       = "g",
    basis_of_record        = "Literature",

    mass_confidence        = "high",
    qa_status              = NA_character_,
    qa_note                = NA_character_,

    stringsAsFactors = FALSE
  )

  ## Remove rows with no mass
  out <- out[!is.na(out$mass_g), ]
  message("PanTHERIA: ", nrow(out), " rows with body mass values")
  out
}

## ---- Master runner ----------------------------------------------------------

run_pantheria_intake <- function(dest_dir = "data/raw/pantheria",
                                 output_file = "data/compiled/pantheria_compiled.csv",
                                 overwrite_download = FALSE) {
  raw_file <- download_pantheria(dest_dir, overwrite = overwrite_download)
  out      <- parse_pantheria(raw_file)
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(out, output_file)
  message("PanTHERIA compiled: ", nrow(out), " rows -> ", output_file)
  invisible(out)
}
