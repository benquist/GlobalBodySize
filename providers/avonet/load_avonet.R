## GlobalBodySize/providers/avonet/load_avonet.R
## Intake script for AVONET bird morphology + body mass database
## Tobias JA, et al. 2022. Ecology Letters 25(3):581-597.
## DOI: 10.1111/ele.13898 — VERIFIED 2026-05-10 (resolves to Wiley OnlineLibrary)
##
## AVONET is available via Figshare article 16586228 (doi: 10.6084/m9.figshare.16586228.v7)
## Three taxonomic treatments available: BirdLife, eBird/Clements, BirdTree
## Default: use BirdLife treatment as primary
##
## Tier A source (merow-ecology advisory) — best available bird body mass database
## Note: species means derived from museum specimens + live captures (>90,000 individuals)

AVONET_SOURCE_ID   <- "avonet_tobias2022"
AVONET_DISPLAY     <- "AVONET (Tobias et al. 2022)"
AVONET_DOI         <- "10.1111/ele.13898"  # VERIFIED 2026-05-10
AVONET_FIGSHARE_FILE_URL <- "https://ndownloader.figshare.com/files/34480856"  # VERIFIED 2026-05-10
## Figshare article: https://figshare.com/articles/dataset/AVONET_morphological_ecological_and_geographical_data_for_all_birds_Tobias_et_al_2022_Ecology_Letters/16586228
AVONET_CITATION    <- "Tobias JA, Sheard C, Pigot AL, et al. 2022. AVONET: morphological, ecological and geographical data for all birds. Ecology Letters 25(3):581-597. https://doi.org/10.1111/ele.13898"

## ---- Download AVONET --------------------------------------------------------
## AVONET is distributed as an Excel workbook with multiple sheets (one per taxonomy)
## UNVERIFIED: confirm current Figshare URL and sheet names

download_avonet <- function(dest_dir = "data/raw/avonet",
                            overwrite = FALSE) {
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  dest_file <- file.path(dest_dir, "AVONET_raw.xlsx")

  if (file.exists(dest_file) && !overwrite) {
    message("AVONET already downloaded: ", dest_file)
    return(dest_file)
  }

  ## Verified Figshare file ID 34480856 for "AVONET Supplementary dataset 1.xlsx"
  ## Article: 10.6084/m9.figshare.16586228.v7 — verified 2026-05-10
  message("Downloading AVONET from Figshare (file ID 34480856)...")
  dl_result <- tryCatch(
    download.file(
      url      = AVONET_FIGSHARE_FILE_URL,
      destfile = dest_file,
      mode     = "wb",
      quiet    = FALSE
    ),
    error = function(e) {
      message("AVONET download failed: ", conditionMessage(e))
      return(1L)
    }
  )
  if (dl_result != 0 || !file.exists(dest_file) || file.size(dest_file) < 10000) {
    message("AVONET download failed or file too small. Manual download may be needed.")
    message("  URL: ", AVONET_FIGSHARE_FILE_URL)
    message("  Save to: ", dest_file)
    return(NULL)
  }
  message("AVONET downloaded: ", format(file.size(dest_file), big.mark=","), " bytes")
  return(dest_file)
}

## ---- Parse AVONET -----------------------------------------------------------
## UNVERIFIED: confirm Excel sheet names and column names from actual file

parse_avonet <- function(raw_file,
                         taxonomy = c("BirdLife", "eBird", "BirdTree")) {
  taxonomy <- match.arg(taxonomy)

  if (!requireNamespace("readxl", quietly = TRUE)) {
    stop("Package 'readxl' required: install.packages('readxl')", call. = FALSE)
  }

  ## Sheet names verified from AVONET Supplementary dataset 1.xlsx (file ID 34480856)
  ## If sheet names differ, inspect with readxl::excel_sheets(raw_file)
  sheet_map <- c(
    BirdLife = "AVONET1_BirdLife",
    eBird    = "AVONET2_eBird",
    BirdTree = "AVONET3_BirdTree"
  )
  sheet <- sheet_map[[taxonomy]]
  message("Reading AVONET sheet: ", sheet)

  raw <- readxl::read_excel(raw_file, sheet = sheet, na = c("NA", ""))

  ## Column names per AVONET data dictionary (Tobias et al. 2022 Table S1)
  ## Species1 = BirdLife / eBird / BirdTree binomial (varies by sheet)
  species_col <- "Species1"          # binomial for the chosen taxonomy
  mass_col    <- "Mass"              # mean species body mass in grams
  n_mass_col  <- "Mass.Source"       # source of mass value

  if (!mass_col %in% names(raw)) {
    stop("Body mass column '", mass_col, "' not found in AVONET sheet '", sheet,
         "'. Inspect column names: ", paste(names(raw)[1:20], collapse = ", "))
  }

  out <- data.frame(
    source_id              = AVONET_SOURCE_ID,
    source_display_name    = AVONET_DISPLAY,
    source_doi             = AVONET_DOI,
    source_access_date     = as.character(Sys.Date()),
    bibliographic_citation = AVONET_CITATION,
    dataset_id             = paste0(AVONET_SOURCE_ID, "_", tolower(taxonomy)),
    original_row_id        = seq_len(nrow(raw)),
    source_file_path       = basename(raw_file),

    verbatim_taxon_name    = raw[[species_col]],
    verbatim_authorship    = NA_character_,
    input_taxonomic_group  = "bird",
    input_taxonomic_rank   = "species",

    mass_g                 = suppressWarnings(as.numeric(raw[[mass_col]])),
    mass_g_min             = NA_real_,
    mass_g_max             = NA_real_,
    mass_se                = NA_real_,
    mass_n                 = NA_integer_,

    ## AVONET mass is from museum specimens + live capture — mark as wet
    ## Some values may be from preserved specimens (flag as unspecified if unclear)
    mass_type              = "wet",
    measurement_method     = "literature_mean",  # species means from >90,000 specimens
    life_stage             = "adult",
    sex                    = "pooled",  ## UNVERIFIED — check if AVONET separates sex

    decimal_latitude       = NA_real_,
    decimal_longitude      = NA_real_,
    coordinate_uncertainty_m = NA_real_,
    country_code           = NA_character_,

    year_measured          = NA_integer_,
    date_measured          = NA_character_,

    measurement_type       = "body mass",
    measurement_unit       = "g",
    basis_of_record        = "PreservedSpecimen",  # majority from museum specimens

    mass_confidence        = "high",
    qa_status              = NA_character_,
    qa_note                = paste0("AVONET taxonomy: ", taxonomy,
                                    " | Figshare file ID 34480856; DOI 10.1111/ele.13898"),

    stringsAsFactors = FALSE
  )

  out <- out[!is.na(out$mass_g), ]
  message("AVONET (", taxonomy, "): ", nrow(out), " rows with body mass values")
  out
}

## ---- Master runner ----------------------------------------------------------

run_avonet_intake <- function(dest_dir = "data/raw/avonet",
                              output_file = "data/compiled/avonet_compiled.csv",
                              taxonomy = "BirdLife") {
  raw_file <- download_avonet(dest_dir)
  if (is.null(raw_file)) {
    message("AVONET: download step skipped (manual download required)")
    return(invisible(NULL))
  }
  out <- parse_avonet(raw_file, taxonomy = taxonomy)
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(out, output_file)
  message("AVONET compiled: ", nrow(out), " rows -> ", output_file)
  invisible(out)
}
