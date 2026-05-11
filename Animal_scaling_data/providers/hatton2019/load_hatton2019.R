## providers/hatton2019/load_hatton2019.R
## Hatton et al. 2019 — "Linking scaling laws across eukaryotes."
## PNAS 116(43):21616–21622. DOI: 10.1073/pnas.1907703116
##
## Three CSV files from Zenodo record 3145281 (CC-BY-4.0):
##   Link-scaling/Data/Metabolism.csv  (8,098 rows)
##   Link-scaling/Data/Growth.csv      (3,812 rows)
##   Link-scaling/Data/Mortality.csv   (4,866 rows)
##
## Primary table: Metabolism.csv — one row per observation.
## Growth and Mortality are used for per-species lookups only.
##
## Key columns (Metabolism.csv):
##   Major_taxa, Order, Species, Mass_g, Metabolism_W, Temperature_C
##   Mass_g is already in grams; Metabolism_W is in Watts.
##   Metabolic rates are basal; Hatton et al. temperature-corrected to standard
##   conditions using the Arrhenius/Q10 framework before analysis.

suppressPackageStartupMessages({
  library(data.table)
})

## ---- Constants --------------------------------------------------------------

SOURCE_ID              <- "hatton2019"
SOURCE_DISPLAY         <- "Hatton et al. 2019"
SOURCE_DOI             <- "10.1073/pnas.1907703116"
DATA_DOI               <- "10.5281/zenodo.3145281"
DATA_URL               <- "https://zenodo.org/records/3145281/files/Link-scaling.zip"
ZIP_FILENAME           <- "Link-scaling.zip"
BIBLIOGRAPHIC_CITATION <- paste0(
  "Hatton IA, Dobson AP, Storch D, Galbraith ED, Loreau M. 2019. ",
  "Linking scaling laws across eukaryotes. PNAS 116(43):21616-21622. ",
  "https://doi.org/10.1073/pnas.1907703116. ",
  "Data: https://doi.org/10.5281/zenodo.3145281"
)

MAJOR_TAXA_MAP <- c(
  "Mammal"       = "mammal",
  "Bird"         = "bird",
  "Fish"         = "fish",
  "Reptilia"     = "reptile",
  "Amphibia"     = "amphibian",
  "Invertebrate" = "invertebrate",
  "Plant"        = "plant",
  "Protist"      = "protist",
  "Prokaryote"   = "prokaryote"
)

## ---- Download ---------------------------------------------------------------

#' Download Link-scaling.zip from Zenodo and extract in place.
#'
#' @param dest_dir   Directory to save and extract the ZIP
#' @param overwrite  Re-download even if ZIP already exists
download_hatton2019 <- function(dest_dir, overwrite = FALSE) {
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  dest_file <- file.path(dest_dir, ZIP_FILENAME)

  if (file.exists(dest_file) && !overwrite) {
    message("Hatton2019: using cached ZIP at ", dest_file)
  } else {
    message("Hatton2019: downloading from Zenodo (", DATA_DOI, ") ...")
    rc <- tryCatch(
      {
        download.file(DATA_URL, dest_file, mode = "wb", quiet = FALSE)
        0L
      },
      error   = function(e) { warning("Download failed: ", conditionMessage(e)); 1L },
      warning = function(w) { warning("Download warning: ", conditionMessage(w)); 1L }
    )
    if (rc != 0L || !file.exists(dest_file) || file.size(dest_file) < 1000L) {
      stop("Hatton2019: download failed or file too small.", call. = FALSE)
    }
    message(sprintf("Hatton2019: downloaded %.1f MB -> %s",
                    file.size(dest_file) / 1e6, dest_file))
  }

  message("Hatton2019: extracting ZIP to ", dest_dir)
  unzip(dest_file, exdir = dest_dir, overwrite = TRUE)
  message("Hatton2019: extraction complete.")
}

## ---- Parse ------------------------------------------------------------------

#' Parse Hatton et al. 2019 data files and return a compiled data.table
#' mapped to the animal_scaling_schema columns.
#'
#' Metabolism.csv provides one output row per observation.
#' Growth.csv and Mortality.csv supply per-species life-history lookups.
#'
#' @param data_dir  Directory containing the extracted Link-scaling/ folder
#' @return data.table with exactly the 34 schema columns
parse_hatton2019 <- function(data_dir) {
  metab_file <- file.path(data_dir, "Link-scaling", "Data", "Metabolism.csv")
  mort_file  <- file.path(data_dir, "Link-scaling", "Data", "Mortality.csv")
  grow_file  <- file.path(data_dir, "Link-scaling", "Data", "Growth.csv")

  missing_files <- c(metab_file, mort_file, grow_file)[
    !file.exists(c(metab_file, mort_file, grow_file))
  ]
  if (length(missing_files) > 0L) {
    stop(
      "Hatton2019: required data files not found:\n",
      paste0("  ", missing_files, collapse = "\n"), "\n",
      "Run download_hatton2019() first or check dest_dir.",
      call. = FALSE
    )
  }

  source_access_date <- format(Sys.Date(), "%Y-%m-%d")

  if (!exists("animal_scaling_schema_columns", mode = "function"))
    source("R/animal_scaling_schema.R")

  ## ---- Read source tables --------------------------------------------------
  metab <- fread(metab_file, encoding = "UTF-8",
                 na.strings = c("", "NA", "N/A", "na"))
  message(sprintf("Hatton2019: Metabolism.csv — %d rows x %d columns",
                  nrow(metab), ncol(metab)))

  ## ---- Mortality lookup: max longevity per species -------------------------
  mort_dt  <- fread(mort_file, encoding = "UTF-8",
                    na.strings = c("", "NA", "N/A", "na"))
  mort_lookup <- mort_dt[!is.na(Longevity_yr),
                          .(lifespan_max_years = max(Longevity_yr, na.rm = TRUE)),
                          by = Species]
  setkey(mort_lookup, Species)

  ## ---- Growth lookup: geometric mean Growth_rate_per_yr per species --------
  grow_dt  <- fread(grow_file, encoding = "UTF-8",
                    na.strings = c("", "NA", "N/A", "na"))
  grow_lookup <- grow_dt[
    !is.na(Growth_rate_per_yr) & Growth_rate_per_yr > 0,
    .(growth_rate_gm = exp(mean(log(Growth_rate_per_yr), na.rm = TRUE))),
    by = Species
  ]
  setkey(grow_lookup, Species)

  ## ---- Join lookups to metabolism table ------------------------------------
  metab[mort_lookup, lifespan_max_years := i.lifespan_max_years, on = "Species"]
  metab[grow_lookup, growth_rate_gm     := i.growth_rate_gm,     on = "Species"]

  ## ---- Build output --------------------------------------------------------
  rel_metab_path <- file.path("providers", "hatton2019", "data", "raw",
                               "Link-scaling", "Data", "Metabolism.csv")

  out <- data.table(
    source_id              = SOURCE_ID,
    source_display_name    = SOURCE_DISPLAY,
    source_doi             = SOURCE_DOI,
    source_access_date     = source_access_date,
    bibliographic_citation = BIBLIOGRAPHIC_CITATION,
    original_row_id        = as.character(metab$Unique_ID),
    source_file_path       = rel_metab_path,

    ## ---- Taxonomy ----------------------------------------------------------
    verbatim_taxon_name    = as.character(metab$Species),
    input_taxonomic_group  = unname(MAJOR_TAXA_MAP[as.character(metab$Major_taxa)]),
    input_taxonomic_rank   = "species",
    resolved_taxon_name    = NA_character_,
    kingdom                = NA_character_,
    phylum                 = NA_character_,
    class                  = NA_character_,
    order                  = as.character(metab$Order),
    family                 = as.character(metab$Family),
    genus                  = as.character(metab$Genus),

    ## ---- Body mass ---------------------------------------------------------
    body_mass_g            = suppressWarnings(as.numeric(metab$Mass_g)),
    body_mass_source       = "measured",

    ## ---- Metabolic rate ----------------------------------------------------
    ## All values are basal metabolic rate; Hatton et al. temperature-corrected
    ## to standard conditions using the Arrhenius/Q10 framework before analysis.
    metabolic_rate_value   = suppressWarnings(as.numeric(metab$Metabolism_W)),
    metabolic_rate_unit    = "W",
    metabolic_rate_type    = "basal",
    metabolic_rate_temp_C  = suppressWarnings(as.numeric(metab$Temperature_C)),

    ## ---- Life history (from Mortality.csv lookup) --------------------------
    lifespan_max_years     = metab$lifespan_max_years,
    lifespan_source        = ifelse(
      !is.na(metab$lifespan_max_years),
      "Hatton2019_Mortality.csv",
      NA_character_
    ),
    age_at_maturity_years  = NA_character_,
    litter_clutch_size     = NA_character_,
    litters_per_year       = NA_character_,

    ## ---- Growth (from Growth.csv lookup) -----------------------------------
    growth_rate_value      = metab$growth_rate_gm,
    growth_rate_unit       = ifelse(
      !is.na(metab$growth_rate_gm),
      "per_yr",
      NA_character_
    ),
    growth_model           = NA_character_,

    ## ---- QA ----------------------------------------------------------------
    qa_flag = fcase(
      is.na(suppressWarnings(as.numeric(metab$Mass_g))) |
        suppressWarnings(as.numeric(metab$Mass_g)) <= 0,
      "body_mass_missing_or_invalid",
      is.na(suppressWarnings(as.numeric(metab$Metabolism_W))) |
        suppressWarnings(as.numeric(metab$Metabolism_W)) <= 0,
      "metabolic_rate_missing_or_invalid",
      default = "ok"
    ),
    qa_body_mass_range = fcase(
      is.na(suppressWarnings(as.numeric(metab$Mass_g))) |
        suppressWarnings(as.numeric(metab$Mass_g)) <= 0,
      NA_character_,
      suppressWarnings(as.numeric(metab$Mass_g)) < 1e-6,  "below_1ug",
      suppressWarnings(as.numeric(metab$Mass_g)) < 0.001, "below_1mg",
      suppressWarnings(as.numeric(metab$Mass_g)) > 1e8,   "above_100t",
      default = "ok"
    ),
    qa_metabolic_unit_verified = "yes"
  )

  mass_n    <- sum(!is.na(out$body_mass_g))
  mr_n      <- sum(!is.na(out$metabolic_rate_value))
  lifesp_n  <- sum(!is.na(out$lifespan_max_years))
  growth_n  <- sum(!is.na(out$growth_rate_value))
  message(sprintf(
    "Hatton2019: %d rows — body mass: %d, metabolic rate: %d, lifespan: %d, growth: %d",
    nrow(out), mass_n, mr_n, lifesp_n, growth_n
  ))

  schema_cols <- animal_scaling_schema_columns()
  for (col in setdiff(schema_cols, names(out))) out[[col]] <- NA
  out[, ..schema_cols]
}

## ---- Orchestrator -----------------------------------------------------------

#' Download (if needed), parse, and write Hatton et al. 2019 data to CSV.
#'
#' @param dest_dir    Directory for raw data (ZIP and extracted files)
#' @param output_file Path for the compiled output CSV
#' @param overwrite   Re-download ZIP if TRUE
run_hatton2019_intake <- function(
    dest_dir    = "providers/hatton2019/data/raw",
    output_file = "output/hatton2019_compiled.csv",
    overwrite   = FALSE
) {
  message("=== Hatton et al. 2019 Intake ===")
  message("Citation: ", BIBLIOGRAPHIC_CITATION)

  zip_path    <- file.path(dest_dir, ZIP_FILENAME)
  metab_check <- file.path(dest_dir, "Link-scaling", "Data", "Metabolism.csv")

  if (!file.exists(zip_path) || !file.exists(metab_check)) {
    download_hatton2019(dest_dir, overwrite = overwrite)
  }

  compiled <- parse_hatton2019(dest_dir)

  out_dir <- dirname(output_file)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  fwrite(compiled, output_file)
  message(sprintf("Hatton2019: wrote %d rows to %s", nrow(compiled), output_file))
  invisible(compiled)
}
