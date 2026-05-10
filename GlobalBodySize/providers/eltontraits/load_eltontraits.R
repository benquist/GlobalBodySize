## GlobalBodySize/providers/eltontraits/load_eltontraits.R
## Intake script for EltonTraits 1.0 — species-level foraging attributes
## for the world's birds and mammals, including body mass.
##
## Reference:
##   Wilman H, Belmaker J, Simpson J, de la Rosa C, Rivadeneira MM, Jetz W. 2014.
##   EltonTraits 1.0: Species-level foraging attributes of the world's birds and mammals.
##   Ecology 95(7):2027. DOI: 10.1890/13-1917.1
##
## Source: ESA Ecological Archives E095-178
## Base URL: https://esapubs.org/archive/ecol/E095/178/
## Files (UNVERIFIED — confirm against ESA archive):
##   Birds:   BirdFuncDat.txt
##   Mammals: MamFuncDat.txt
##
## Body mass column: "BodyMass-Value" (grams, species mean) in both files
## Species column:   "Scientific" (binomial)
##
## Use case: cross-check for birds (Tier A), gap-fill for mammals (Tier B)
## NOTE: EltonTraits bird mass largely derives from Dunning 2008 — overlaps AVONET

## ---- Constants --------------------------------------------------------------

ELTONTRAITS_DOI     <- "10.1890/13-1917.1"
ELTONTRAITS_BASE    <- "https://esapubs.org/archive/ecol/E095/178/"
ELTONTRAITS_BIRD_FILE <- "BirdFuncDat.txt"    ## UNVERIFIED filename
ELTONTRAITS_MAM_FILE  <- "MamFuncDat.txt"     ## UNVERIFIED filename
ELTONTRAITS_CITATION  <- paste0(
  "Wilman H, Belmaker J, Simpson J, de la Rosa C, Rivadeneira MM, Jetz W. 2014. ",
  "EltonTraits 1.0: Species-level foraging attributes of the world's birds and mammals. ",
  "Ecology 95(7):2027. https://doi.org/10.1890/13-1917.1"
)

## ---- Download ---------------------------------------------------------------

.download_eltontraits_file <- function(filename, dest_dir, overwrite) {
  dest <- file.path(dest_dir, filename)
  if (file.exists(dest) && !overwrite) {
    message("EltonTraits already downloaded: ", dest)
    return(dest)
  }
  url <- paste0(ELTONTRAITS_BASE, filename)
  message("Downloading: ", url)
  tryCatch(
    download.file(url, dest, mode = "wb", quiet = FALSE),
    error = function(e) {
      warning("Failed to download ", filename, ": ", conditionMessage(e))
      NULL
    }
  )
  if (file.exists(dest)) dest else NULL
}

download_eltontraits <- function(dest_dir = "data/raw/eltontraits", overwrite = FALSE) {
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  bird_file <- .download_eltontraits_file(ELTONTRAITS_BIRD_FILE, dest_dir, overwrite)
  mam_file  <- .download_eltontraits_file(ELTONTRAITS_MAM_FILE,  dest_dir, overwrite)
  list(birds = bird_file, mammals = mam_file)
}

## ---- Parse one EltonTraits file ---------------------------------------------

.parse_eltontraits_one <- function(raw_file, tax_group) {
  if (is.null(raw_file) || !file.exists(raw_file)) {
    warning("EltonTraits file not found: ", raw_file)
    return(NULL)
  }

  raw <- tryCatch(
    data.table::fread(raw_file, sep = "\t", header = TRUE,
                      na.strings = c("NA", "", " "), data.table = FALSE),
    error = function(e) {
      warning("Failed to parse ", raw_file, ": ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(raw)) return(NULL)

  ## Detect column names — UNVERIFIED; try common variants
  species_col <- intersect(c("Scientific", "BinomialName", "Species"), names(raw))[1]
  mass_col    <- intersect(c("BodyMass-Value", "BodyMass_Value", "Body_mass"), names(raw))[1]
  source_col  <- intersect(c("BodyMass-Source", "BodyMass_Source"), names(raw))[1]

  if (is.na(species_col)) stop("Cannot find species column in ", raw_file,
                                ". Names: ", paste(names(raw)[1:15], collapse = ", "))
  if (is.na(mass_col))    stop("Cannot find body mass column in ", raw_file,
                                ". Names: ", paste(names(raw)[1:15], collapse = ", "))

  source_id_str   <- paste0("eltontraits_", tax_group)
  source_note     <- if (!is.na(source_col)) raw[[source_col]] else NA_character_

  out <- data.frame(
    source_id              = source_id_str,
    source_display_name    = paste0("EltonTraits 1.0 — ", tools::toTitleCase(tax_group), "s (Wilman et al. 2014)"),
    source_doi             = ELTONTRAITS_DOI,
    source_access_date     = as.character(Sys.Date()),
    bibliographic_citation = ELTONTRAITS_CITATION,
    dataset_id             = source_id_str,
    original_row_id        = seq_len(nrow(raw)),
    source_file_path       = basename(raw_file),

    verbatim_taxon_name    = raw[[species_col]],
    verbatim_authorship    = NA_character_,
    input_taxonomic_group  = tax_group,
    input_taxonomic_rank   = "species",

    mass_g                 = suppressWarnings(as.numeric(raw[[mass_col]])),
    mass_g_min             = NA_real_,
    mass_g_max             = NA_real_,
    mass_se                = NA_real_,
    mass_n                 = NA_integer_,

    mass_type              = "wet",
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

    ## Birds = Tier A cross-check; mammals = Tier B (use PanTHERIA as primary)
    mass_confidence        = if (tax_group == "bird") "high" else "medium",
    qa_status              = NA_character_,
    qa_note                = paste0("EltonTraits_mass_source=",
                                    ifelse(is.na(source_note), "unknown", source_note)),

    stringsAsFactors = FALSE
  )

  out <- out[!is.na(out$mass_g) & out$mass_g > 0, ]
  message("EltonTraits (", tax_group, "): ", nrow(out), " rows with body mass")
  out
}

## ---- Master runner ----------------------------------------------------------

run_eltontraits_intake <- function(dest_dir    = "data/raw/eltontraits",
                                   output_file = "data/compiled/eltontraits_compiled.csv",
                                   overwrite_download = FALSE) {
  files <- download_eltontraits(dest_dir, overwrite = overwrite_download)

  birds   <- .parse_eltontraits_one(files$birds, "bird")
  mammals <- .parse_eltontraits_one(files$mammals, "mammal")

  parts <- Filter(Negate(is.null), list(birds, mammals))
  if (!length(parts)) {
    warning("EltonTraits: no data returned from either file")
    return(invisible(NULL))
  }

  out <- do.call(rbind, parts)
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(out, output_file)
  message("EltonTraits compiled: ", nrow(out), " rows -> ", output_file)
  invisible(out)
}
