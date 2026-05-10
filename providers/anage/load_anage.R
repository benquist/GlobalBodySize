## GlobalBodySize/providers/anage/load_anage.R
## Intake script for AnAge animal longevity and body mass database
## Human Ageing Genomic Resources — https://genomics.senescence.info/species/
##
## Reference:
##   de Magalhães JP, Costa J. 2009. A database of vertebrate longevity records
##   and their relation to other life-history traits. J Evol Biol 22(8):1770-1774.
##   DOI: 10.1111/j.1420-9101.2009.01783.x
##
## Source URL: https://genomics.senescence.info/species/dataset.zip
## The zip archive contains anage_data.txt (tab-delimited)
##
## Coverage: vertebrates — mammals, birds, reptiles, amphibians, fish
## Body mass column: "Body mass (g)" — values are species means from literature
## Use case: gap-fill for longevity-mass entries not in Tier A sources; Tier B
##
## Output: data.frame conforming to GlobalBodySize schema

## ---- Constants --------------------------------------------------------------

ANAGE_URL        <- "https://genomics.senescence.info/species/dataset.zip"
ANAGE_SOURCE_ID  <- "anage_demagalhaes2009"
ANAGE_DISPLAY    <- "AnAge Build 14 (de Magalhães & Costa 2009)"
ANAGE_DOI        <- "10.1111/j.1420-9101.2009.01783.x"
ANAGE_CITATION   <- paste0(
  "de Magalh\u00e3es JP, Costa J. 2009. A database of vertebrate longevity records ",
  "and their relation to other life-history traits. ",
  "J Evol Biol 22(8):1770-1774. https://doi.org/10.1111/j.1420-9101.2009.01783.x"
)

## Map AnAge kingdom/class to GlobalBodySize input_taxonomic_group
.ANAGE_CLASS_MAP <- c(
  Mammalia    = "mammal",
  Aves        = "bird",
  Reptilia    = "reptile",
  Amphibia    = "amphibian",
  Actinopterygii = "fish",
  Chondrichthyes = "fish",
  Sarcopterygii  = "fish",
  Cephalaspidomorphi = "fish",
  Insecta     = "insect"
)

## ---- Download ---------------------------------------------------------------

download_anage <- function(dest_dir = "data/raw/anage", overwrite = FALSE) {
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  zip_file  <- file.path(dest_dir, "anage_dataset.zip")
  data_file <- file.path(dest_dir, "anage_data.txt")

  if (file.exists(data_file) && !overwrite) {
    message("AnAge already downloaded: ", data_file)
    return(data_file)
  }

  message("Downloading AnAge from: ", ANAGE_URL)
  tryCatch(
    download.file(ANAGE_URL, zip_file, mode = "wb", quiet = FALSE),
    error = function(e) stop("Failed to download AnAge: ", conditionMessage(e), call. = FALSE)
  )

  ## Unzip — file inside is anage_data.txt
  unzipped <- tryCatch(
    unzip(zip_file, exdir = dest_dir),
    error = function(e) stop("Failed to unzip AnAge archive: ", conditionMessage(e), call. = FALSE)
  )
  message("AnAge unzipped: ", paste(basename(unzipped), collapse = ", "))

  ## Locate the data file (name may vary by build)
  txt_files <- list.files(dest_dir, pattern = "\\.txt$", full.names = TRUE)
  if (!length(txt_files)) stop("No .txt file found in AnAge zip archive — inspect manually: ", dest_dir)
  data_file <- txt_files[1]
  message("AnAge data file: ", data_file)
  data_file
}

## ---- Parse ------------------------------------------------------------------

parse_anage <- function(raw_file) {
  if (!requireNamespace("data.table", quietly = TRUE))
    stop("Package 'data.table' required", call. = FALSE)

  raw <- data.table::fread(raw_file, sep = "\t", header = TRUE,
                           na.strings = c("NA", "N/A", "", " "),
                           data.table = FALSE, encoding = "UTF-8")

  ## Expected columns (confirm against actual file):
  ##   Kingdom, Phylum, Class, Order, Family, Genus, Species, Common name,
  ##   Body mass (g), Metabolic rate (W), Temperature (K), ...
  ##   Data quality: "high", "medium", "low", "questionable"

  species_col  <- if ("Species" %in% names(raw)) "Species" else NA_character_
  genus_col    <- if ("Genus"   %in% names(raw)) "Genus"   else NA_character_
  mass_col     <- grep("Body mass", names(raw), ignore.case = TRUE, value = TRUE)[1]
  class_col    <- grep("^Class$",   names(raw), ignore.case = TRUE, value = TRUE)[1]
  quality_col  <- grep("Data quality", names(raw), ignore.case = TRUE, value = TRUE)[1]

  if (is.na(mass_col))    stop("Cannot find 'Body mass (g)' column in AnAge. Names: ",
                                paste(names(raw)[1:20], collapse = ", "))
  if (is.na(species_col)) stop("Cannot find 'Species' column in AnAge")

  ## Build binomial from Genus + Species if needed
  binomial <- if (!is.na(genus_col)) {
    paste(raw[[genus_col]], raw[[species_col]])
  } else {
    raw[[species_col]]
  }

  ## Map class → input_taxonomic_group
  tax_group <- .ANAGE_CLASS_MAP[raw[[class_col]]]
  tax_group[is.na(tax_group)] <- "other"

  ## Mass confidence from AnAge data quality
  confidence <- rep("medium", nrow(raw))
  if (!is.na(quality_col)) {
    confidence[raw[[quality_col]] == "high"]         <- "high"
    confidence[raw[[quality_col]] == "low"]          <- "low"
    confidence[raw[[quality_col]] == "questionable"] <- "low"
  }

  out <- data.frame(
    source_id              = ANAGE_SOURCE_ID,
    source_display_name    = ANAGE_DISPLAY,
    source_doi             = ANAGE_DOI,
    source_access_date     = as.character(Sys.Date()),
    bibliographic_citation = ANAGE_CITATION,
    dataset_id             = ANAGE_SOURCE_ID,
    original_row_id        = seq_len(nrow(raw)),
    source_file_path       = basename(raw_file),

    verbatim_taxon_name    = binomial,
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

    mass_confidence        = confidence,
    qa_status              = NA_character_,
    qa_note                = if (!is.na(quality_col))
                               paste0("AnAge_quality=", raw[[quality_col]])
                             else NA_character_,

    stringsAsFactors = FALSE
  )

  out <- out[!is.na(out$mass_g) & out$mass_g > 0, ]
  message("AnAge: ", nrow(out), " rows with body mass values")

  ## Warn about groups that couldn't be mapped
  unmapped <- unique(raw[[class_col]][is.na(.ANAGE_CLASS_MAP[raw[[class_col]]])])
  if (length(unmapped)) message("AnAge: unmapped classes (set to 'other'): ",
                                paste(unmapped, collapse = ", "))
  out
}

## ---- Master runner ----------------------------------------------------------

run_anage_intake <- function(dest_dir   = "data/raw/anage",
                             output_file = "data/compiled/anage_compiled.csv",
                             overwrite_download = FALSE) {
  raw_file <- download_anage(dest_dir, overwrite = overwrite_download)
  out      <- parse_anage(raw_file)
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(out, output_file)
  message("AnAge compiled: ", nrow(out), " rows -> ", output_file)
  invisible(out)
}
