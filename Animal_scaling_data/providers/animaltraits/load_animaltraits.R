## providers/animaltraits/load_animaltraits.R
## AnimalTraits — curated terrestrial animal trait database
## (body mass, metabolic rate, brain size) across a wide taxonomic range
## including vertebrates and many invertebrate groups.
##
## Reference:
##   Herberstein ME, McLean DJ, Lowe E, Wolff JO, Khan MK, Smith K, ... Carthey AJR.
##   2022. AnimalTraits — a curated animal trait database for body mass, metabolic
##   rate and brain size. Scientific Data 9(1):265.
##   DOI: 10.1038/s41597-022-01364-9
##
## Data hosted on Zenodo (public domain waiver — no restrictions):
##   DOI: 10.5281/zenodo.6468938
##   CSV: https://zenodo.org/record/6468938/files/observations.csv?download=1
##
## Schema: long-format — one row per trait observation per individual/study.
##   Known columns: phylum, class, order, family, genus, species,
##                  traitName, traitValue, traitUnit, sex, n, references
##   traitName values include "body mass", "metabolic rate", "brain mass", etc.
##   Body mass values are in KILOGRAMS — converted to grams here.
##
## Coverage (Zenodo 6468938):
##   ~3,580 observation rows; ~2,856 with body mass; ~1,830 unique species with mass
##   Mammalia, Aves, Reptilia, Amphibia, Insecta, Arachnida, and other invertebrates

suppressPackageStartupMessages({
  library(data.table)
  library(httr)
})

## ---- Constants --------------------------------------------------------------

ANIMALTRAITS_URL        <- "https://zenodo.org/record/6468938/files/observations.csv?download=1"
SOURCE_ID               <- "animaltraits_herberstein2022"
DOI                     <- "10.1038/s41597-022-01364-9"
DATA_DOI                <- "10.5281/zenodo.6468938"
CITATION                <- paste0(
  "Herberstein ME, McLean DJ, Lowe E, Wolff JO, Khan MK, Smith K, ",
  "Buzatto BA, Eldridge MDB, Endler J, Evans JP, Gaskett AC, Holwell GI, ",
  "Johnson SL, Joseph L, Latty T, Lighton JRB, Madin JS, Phillips BL, ",
  "Pintor LM, Popple LW, Pryke SR, Redhead JW, Rodgers E, Rojas B, ",
  "Sato CF, Tatarnic N, Wapstra E, Whiting MJ, Wong BBM, Yee MS, ",
  "Zeil J, Carthey AJR. 2022. ",
  "AnimalTraits - a curated animal trait database for body mass, metabolic rate ",
  "and brain size. Scientific Data 9(1):265. ",
  "https://doi.org/10.1038/s41597-022-01364-9. ",
  "Data: https://doi.org/10.5281/zenodo.6468938"
)

CLASS_TO_GROUP <- c(
  "Mammalia"           = "mammal",
  "Aves"               = "bird",
  "Reptilia"           = "reptile",
  "Amphibia"           = "amphibian",
  ## Ray-finned and cartilaginous fishes
  "Actinopterygii"     = "fish",
  "Actinopteri"        = "fish",
  "Chondrichthyes"     = "fish",
  "Cephalaspidomorphi" = "fish",
  ## Invertebrates
  "Insecta"            = "insect",
  "Arachnida"          = "arachnid",
  "Malacostraca"       = "crustacean",
  "Chilopoda"          = "myriapod",
  "Diplopoda"          = "myriapod",
  "Clitellata"         = "annelid",
  "Polychaeta"         = "annelid",
  "Gastropoda"         = "gastropod",
  "Bivalvia"           = "bivalve"
)

## ---- Download ---------------------------------------------------------------

#' Download AnimalTraits observations.csv from Zenodo with caching.
#'
#' @param dest_dir   Directory to save the raw file
#' @param overwrite  Re-download even if file already exists
#' @return Absolute path to the downloaded file
download_animaltraits <- function(dest_dir = "providers/animaltraits/data/raw",
                                  overwrite = FALSE) {
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  dest_file <- file.path(dest_dir, "animaltraits_observations.csv")

  if (file.exists(dest_file) && !overwrite) {
    message("AnimalTraits: using cached file at ", dest_file)
    return(dest_file)
  }

  message("AnimalTraits: downloading from Zenodo (", DATA_DOI, ") ...")
  rc <- tryCatch(
    {
      download.file(
        url      = ANIMALTRAITS_URL,
        destfile = dest_file,
        mode     = "wb",
        quiet    = FALSE
      )
      0L
    },
    error   = function(e) { warning("Download failed: ", conditionMessage(e)); 1L },
    warning = function(w) { warning("Download warning: ", conditionMessage(w)); 1L }
  )

  if (rc != 0L || !file.exists(dest_file) || file.size(dest_file) < 1000L) {
    stop("AnimalTraits: download failed or file too small. Check network and URL.",
         call. = FALSE)
  }
  message(sprintf("AnimalTraits: downloaded %.1f MB -> %s",
                  file.size(dest_file) / 1e6, dest_file))
  dest_file
}

## ---- Parse ------------------------------------------------------------------

#' Parse the raw AnimalTraits observations CSV and return a compiled data.table
#' mapped to the animal_scaling_schema columns.
#'
#' The source is long-format (one trait per row). This function:
#'   1. Identifies body-mass rows (traitName == "body mass"), converts kg -> g.
#'   2. Identifies metabolic-rate rows (traitName matches "metabolic rate").
#'   3. Pivots to wide format: one row per unique species × study observation.
#'   4. Maps columns to the canonical schema.
#'
#' @param raw_file  Path to downloaded observations.csv
#' @return data.table with canonical schema columns
parse_animaltraits <- function(raw_file) {
  dt <- data.table::fread(raw_file, encoding = "UTF-8",
                           na.strings = c("", "NA", "N/A", "na"))

  ## Print actual column names for audit / schema-change detection
  message("AnimalTraits raw columns: ", paste(names(dt), collapse = ", "))
  message(sprintf("AnimalTraits: %d total observation rows", nrow(dt)))

  ## The AnimalTraits CSV is WIDE format: one row per observation (species × study),
  ## with separate columns for each trait. Key columns verified 2026-05-11:
  ##   "body mass"             — numeric, units in kg (see "body mass - units")
  ##   "body mass - units"     — typically "kg"
  ##   "metabolic rate"        — numeric, raw value
  ##   "metabolic rate - units" — string (e.g., "mL O2/h", "W")
  ##   "original temperature"  — numeric, assay temp (°C or other; see metadata)
  ##   "metabolic rate - method" — method description string

  access_date <- format(Sys.Date(), "%Y-%m-%d")

  ## ---- Taxonomy -------------------------------------------------------------
  ## Combine genus + species for binomial name; species column holds epithet only
  verbatim <- ifelse(
    is.na(dt$genus) | is.na(dt$species),
    NA_character_,
    trimws(paste(trimws(dt$genus), trimws(dt$species)))
  )

  ## ---- Body mass ------------------------------------------------------------
  ## Source units are kg per the AnimalTraits data dictionary; convert to grams.
  ## Rows without body mass are retained (metabolic rate may still be present).
  mass_raw <- suppressWarnings(as.numeric(dt$`body mass`))
  mass_g   <- mass_raw * 1000  # kg → g

  ## ---- Metabolic rate -------------------------------------------------------
  mr_val  <- suppressWarnings(as.numeric(dt$`metabolic rate`))
  mr_unit <- as.character(dt$`metabolic rate - units`)
  mr_temp <- suppressWarnings(as.numeric(dt$`original temperature`))

  ## Infer metabolic rate type from method description
  mr_method <- tolower(as.character(dt$`metabolic rate - method`))
  mr_type <- ifelse(grepl("basal|bmr",       mr_method, perl = TRUE), "basal",
             ifelse(grepl("standard|smr",    mr_method, perl = TRUE), "standard",
             ifelse(grepl("resting",         mr_method, perl = TRUE), "resting",
             ifelse(grepl("field|doubly",    mr_method, perl = TRUE), "field",
             ifelse(!is.na(mr_val),          "unknown",
             NA_character_)))))

  ## ---- Build output ---------------------------------------------------------
  out <- data.table(
    source_id              = SOURCE_ID,
    source_display_name    = "AnimalTraits (Herberstein et al. 2022)",
    source_doi             = DOI,
    source_access_date     = access_date,
    bibliographic_citation = CITATION,
    original_row_id        = as.character(seq_len(nrow(dt))),
    source_file_path       = basename(raw_file),

    ## Taxonomy
    verbatim_taxon_name    = verbatim,
    input_taxonomic_rank   = "species",
    resolved_taxon_name    = NA_character_,
    kingdom                = NA_character_,
    phylum                 = as.character(dt$phylum),
    class                  = as.character(dt$class),
    order                  = as.character(dt$order),
    family                 = as.character(dt$family),
    genus                  = as.character(dt$genus),
    input_taxonomic_group  = unname(CLASS_TO_GROUP[as.character(dt$class)]),

    ## Body mass
    body_mass_g            = mass_g,
    body_mass_source       = ifelse(!is.na(mass_g), "literature_mean", NA_character_),

    ## Metabolic rate
    metabolic_rate_value   = mr_val,
    metabolic_rate_unit    = mr_unit,
    metabolic_rate_type    = mr_type,
    metabolic_rate_temp_C  = mr_temp,

    ## Life history (not in AnimalTraits)
    lifespan_max_years     = NA_real_,
    lifespan_source        = NA_character_,
    age_at_maturity_years  = NA_real_,
    litter_clutch_size     = NA_real_,
    litters_per_year       = NA_real_,

    ## Growth (not in AnimalTraits)
    growth_rate_value      = NA_real_,
    growth_rate_unit       = NA_character_,
    growth_model           = NA_character_
  )

  ## ---- QA ------------------------------------------------------------------
  out[, qa_flag := ""]
  out[is.na(body_mass_g) & is.na(metabolic_rate_value),
      qa_flag := "no_body_mass|no_metabolic_rate"]
  out[is.na(body_mass_g) & !is.na(metabolic_rate_value),
      qa_flag := "no_body_mass"]
  out[!is.na(body_mass_g) & is.na(metabolic_rate_value),
      qa_flag := "no_metabolic_rate"]

  out[, qa_body_mass_range := fcase(
    is.na(body_mass_g),                      "missing",
    body_mass_g < 1e-6,                      "suspect_low",
    body_mass_g > 2e8,                       "suspect_high",
    default = "ok"
  )]
  out[, qa_metabolic_unit_verified := !is.na(mr_unit) & nchar(trimws(mr_unit)) > 0]

  mass_n <- sum(!is.na(out$body_mass_g))
  mr_n   <- sum(!is.na(out$metabolic_rate_value))
  message(sprintf("AnimalTraits: %d rows — body mass: %d, metabolic rate: %d",
                  nrow(out), mass_n, mr_n))

  ## Enforce schema column order
  if (!exists("animal_scaling_schema_columns", mode = "function"))
    source("R/animal_scaling_schema.R")
  schema_cols <- animal_scaling_schema_columns()
  for (col in setdiff(schema_cols, names(out))) out[[col]] <- NA
  out[, ..schema_cols]
}
## ---- Orchestrator -----------------------------------------------------------

#' Download, parse, and write AnimalTraits data to the canonical schema CSV.
#'
#' @param dest_dir    Directory for the raw downloaded file
#' @param output_file Path for the compiled output CSV (relative to project root)
#' @param overwrite   Re-download raw file if TRUE
run_animaltraits_intake <- function(
    dest_dir    = "providers/animaltraits/data/raw",
    output_file = "output/animaltraits_compiled.csv",
    overwrite   = FALSE
) {
  message("=== AnimalTraits Intake ===")
  message("Citation: ", CITATION)

  raw_file <- download_animaltraits(dest_dir = dest_dir, overwrite = overwrite)
  compiled <- parse_animaltraits(raw_file)

  out_dir <- dirname(output_file)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(compiled, output_file)
  message(sprintf("AnimalTraits: wrote %d rows to %s", nrow(compiled), output_file))
  invisible(compiled)
}
