## providers/pnas_2303764120/load_pnas_2303764120.R
## Hoehler et al. 2023 — "The Metabolic Rate of the Biosphere and its Components"
## PNAS 120(25):e2303764120. DOI: 10.1073/pnas.2303764120
##
## SD01 "Metabolic_Data" sheet: 10,530 rows × 27 columns.
## Covers Animalia (Amphibians, Birds, Fishes, Insects, Mammals, Reptiles,
## and marine invertebrates) plus Bacteria, Archaea, Fungi, and Plants.
## Key columns: Wet Mass (g), Metabolic Rate (W, at 25C), T (C),
##              Type of Metabolic Rate, tsn (ITIS), full taxonomy.
##
## SD02: geochemical flux estimates (not species-level trait data; skipped).
##
## Files expected at:
##   providers/pnas_2303764120/data/raw/pnas_2303764120_sd01.xlsx
##   providers/pnas_2303764120/data/raw/pnas_2303764120_sd02.xlsx
##
## Verified column mapping (inspected 2026-05-11):
##   verbatim_taxon_name   <- paste(Genus, Species)
##   body_mass_g           <- `Wet Mass (g)`  [already in grams]
##   metabolic_rate_value  <- `Metabolic Rate (W, at 25C)`  [Watts]
##   metabolic_rate_unit   <- "W"
##   metabolic_rate_temp_C <- `T (C)` (measurement temp; standardized to 25C)
##   metabolic_rate_type   <- `Type of Metabolic Rate` (mapped to controlled vocab)
##   input_taxonomic_group <- Group (mapped via GROUP_TO_TYPE)

suppressPackageStartupMessages({
  library(data.table)
  library(readxl)
})

## ---- Constants --------------------------------------------------------------

SOURCE_ID    <- "pnas_hoehler2023"
DOI          <- "10.1073/pnas.2303764120"
CITATION     <- paste0(
  "Hoehler TM, Mankel DJ, Girguis PR, McCollom TM, Hendry KR, Jorgensen BB. ",
  "2023. The Metabolic Rate of the Biosphere and its Components. ",
  "PNAS 120(25):e2303764120. https://doi.org/10.1073/pnas.2303764120"
)

.SD01_FILENAME <- "pnas_2303764120_sd01.xlsx"
.SD02_FILENAME <- "pnas_2303764120_sd02.xlsx"

## ---- Lookup tables ----------------------------------------------------------

## Source "Group" → controlled vocab input_taxonomic_group
GROUP_TO_TYPE <- c(
  "Amphibians"                                         = "amphibian",
  "Bird"                                               = "bird",
  "Fishes"                                             = "fish",
  "Insect"                                             = "insect",
  "Mammal"                                             = "mammal",
  "Reptiles"                                           = "reptile",
  "Cephalopods, Mollusca"                              = "mollusc",
  "Copepods and Krill, Crustacea"                      = "crustacean",
  "Decapods, Crustacea"                                = "crustacean",
  "Peracarids, Crustacea"                              = "crustacean",
  "Gelatinous Invertebrates: Chaetognaths and Medusae" = "invertebrate",
  "Heterotrophic protozoa"                             = "protozoa",
  "Eukaryotic Microalgae (non-filamentous)"            = "microalgae",
  "Archaea"                                            = "archaea",
  "Bacteria"                                           = "bacteria",
  "Cyanobacteria"                                      = "bacteria",
  "Fungi"                                              = "fungi",
  "Seedling"                                           = "plant",
  "Tree sapling"                                       = "plant"
)

## Source "Type of Metabolic Rate" → controlled vocab metabolic_rate_type
METAB_TYPE_MAP <- c(
  "Basal"                             = "basal",
  "Dark respiration"                  = "basal",
  "Endogenous"                        = "basal",
  "Field"                             = "field",
  "Growing"                           = "active",
  "Maintenance"                       = "resting",
  "Maintenance, flushed chemostat"    = "resting",
  "Maintenance, nonflushed chemostat" = "resting",
  "Maximum"                           = "active"
)

## ---- File check -------------------------------------------------------------

#' Check whether the required Excel files are present in data_dir.
#'
#' Prints a clear message with placement instructions if files are missing.
#'
#' @param data_dir  Directory that should contain the Excel files
#' @return logical TRUE if both files present, FALSE otherwise
check_pnas_files <- function(data_dir = "providers/pnas_2303764120/data/raw") {
  sd01 <- file.path(data_dir, .SD01_FILENAME)
  sd02 <- file.path(data_dir, .SD02_FILENAME)
  missing <- c(sd01, sd02)[!file.exists(c(sd01, sd02))]

  if (length(missing) == 0L) {
    message("PNAS 2303764120: both Excel files found.")
    return(TRUE)
  }

  message(
    "\n",
    "=== PNAS 2303764120: manual file placement required ===\n",
    "The following files are missing:\n",
    paste0("  ", missing, collapse = "\n"), "\n\n",
    "Steps:\n",
    "  1. Navigate to https://doi.org/10.1073/pnas.2303764120\n",
    "  2. Download the supplementary data files (SD01 and SD02).\n",
    "  3. Rename them to:\n",
    "       ", .SD01_FILENAME, "\n",
    "       ", .SD02_FILENAME, "\n",
    "  4. Place both files in:\n",
    "       ", normalizePath(data_dir, mustWork = FALSE), "\n",
    "  5. Re-run run_pnas_intake().\n"
  )
  FALSE
}

## ---- Parse SD01 -------------------------------------------------------------

#' Read and map PNAS SD01 "Metabolic_Data" sheet to canonical schema.
#'
#' Column names verified 2026-05-11. Key mappings:
#'   verbatim_taxon_name  <- paste(Genus, Species)
#'   body_mass_g          <- `Wet Mass (g)` (already grams)
#'   metabolic_rate_value <- `Metabolic Rate (W, at 25C)` (Watts, 25°C standard)
#'
#' @param file_path  Path to pnas_2303764120_sd01.xlsx
#' @return data.table with canonical schema columns
parse_pnas_sd01 <- function(file_path) {
  message("PNAS SD01: reading ", file_path)
  raw <- as.data.table(
    readxl::read_excel(file_path, sheet = "Metabolic_Data")
  )
  message(sprintf("PNAS SD01: %d rows x %d columns", nrow(raw), ncol(raw)))

  ## The two identically-named "Metabolic Rate (W, at T)" columns are renamed by
  ## readxl to ...18 and ...19. Column 18 is used (primary measurement).
  MR_AT_T_COL <- names(raw)[18]  # "Metabolic Rate (W, at T)...18"

  access_date <- format(Sys.Date(), "%Y-%m-%d")

  out <- data.table(
    source_id              = SOURCE_ID,
    source_display_name    = "Hoehler et al. 2023 PNAS SD01",
    source_doi             = DOI,
    source_access_date     = access_date,
    bibliographic_citation = CITATION,
    original_row_id        = as.character(raw$Number),
    source_file_path       = basename(file_path),

    ## ---- Taxonomy -----------------------------------------------------------
    ## Use ifelse to avoid paste(NA) producing literal "NA" or "NA NA" strings
    verbatim_taxon_name    = ifelse(
      is.na(raw$Genus) | is.na(raw$Species),
      NA_character_,
      paste(trimws(raw$Genus), trimws(raw$Species))
    ),
    input_taxonomic_rank   = "species",
    resolved_taxon_name    = NA_character_,
    kingdom                = raw$Kingdom,
    phylum                 = raw$Phylum,
    class                  = raw$Class,
    order                  = raw$Order,
    family                 = raw$Family,
    genus                  = raw$Genus,

    ## Map source Group to controlled vocab
    input_taxonomic_group  = unname(GROUP_TO_TYPE[raw$Group]),

    ## ---- Body mass ----------------------------------------------------------
    ## Source: Wet Mass (g) — already in grams
    body_mass_g            = suppressWarnings(as.numeric(raw$`Wet Mass (g)`)),
    ## Use Individual or Average measurement column to classify source
    body_mass_source       = ifelse(
      grepl("individual", tolower(raw$`Individual or Average measurement`),
            fixed = FALSE),
      "measured",
      "literature_mean"
    ),

    ## ---- Metabolic rate -----------------------------------------------------
    ## Primary: Metabolic Rate (W, at 25C) — temperature-standardised to 25°C
    ## Secondary: Metabolic Rate (W, at T) — at measurement temperature
    metabolic_rate_value   = suppressWarnings(
                               as.numeric(raw$`Metabolic Rate (W, at 25C)`)),
    metabolic_rate_unit    = "W",
    metabolic_rate_type    = ifelse(
      is.na(unname(METAB_TYPE_MAP[raw$`Type of Metabolic Rate`])),
      ifelse(!is.na(suppressWarnings(as.numeric(raw$`Metabolic Rate (W, at 25C)`))),
             "unknown", NA_character_),
      unname(METAB_TYPE_MAP[raw$`Type of Metabolic Rate`])
    ),
    metabolic_rate_temp_C  = suppressWarnings(as.numeric(raw$`T (C)`)),

    ## ---- Life history (not in SD01) -----------------------------------------
    lifespan_max_years     = NA_real_,
    lifespan_source        = NA_character_,
    age_at_maturity_years  = NA_real_,
    litter_clutch_size     = NA_real_,
    litters_per_year       = NA_real_,

    ## ---- Growth (not in SD01) -----------------------------------------------
    growth_rate_value      = NA_real_,
    growth_rate_unit       = NA_character_,
    growth_model           = NA_character_,

    ## ---- Additional provenance ----------------------------------------------
    tsn                    = as.character(raw$tsn),
    reference_raw          = raw$Reference,
    individual_or_average  = raw$`Individual or Average measurement`,
    dry_mass_g             = suppressWarnings(as.numeric(raw$`Dry Mass (g)`)),
    carbon_mass_g          = suppressWarnings(as.numeric(raw$`Carbon Mass (g)`)),
    metabolic_rate_at_T_W  = suppressWarnings(as.numeric(raw[[MR_AT_T_COL]]))
  )

  ## ---- QA -----------------------------------------------------------------
  out[, qa_flag := ""]
  out[is.na(body_mass_g), qa_flag := paste0(qa_flag, "no_body_mass|")]
  out[is.na(metabolic_rate_value), qa_flag := paste0(qa_flag, "no_metabolic_rate|")]
  out[, qa_flag := gsub("\\|$", "", qa_flag)]

  out[, qa_body_mass_range := fcase(
    is.na(body_mass_g),          "missing",
    body_mass_g <= 0,            "suspect_low",
    body_mass_g < 1e-14,         "suspect_low",
    body_mass_g > 2e8,           "suspect_high",
    default = "ok"
  )]
  out[, qa_metabolic_unit_verified := TRUE]  # unit confirmed as W

  if (!exists("animal_scaling_schema_columns", mode = "function"))
    source("R/animal_scaling_schema.R")
  schema_cols <- animal_scaling_schema_columns()
  extra_cols  <- setdiff(names(out), schema_cols)
  out[, c(schema_cols[schema_cols %in% names(out)], extra_cols), with = FALSE]
}

## ---- Parse SD02 -------------------------------------------------------------

#' SD02 contains global geochemical flux estimates (electron donors, habitats),
#' NOT species-level trait data. It is not mapped to the animal scaling schema.
#' Returns NULL with an informative message.
#'
#' @param file_path  Path to pnas_2303764120_sd02.xlsx
#' @return NULL (invisibly)
parse_pnas_sd02 <- function(file_path) {
  message(
    "PNAS SD02: This file contains global biogeochemical flux estimates ",
    "(sheets: Overview, Fluxes, Flux estimates, Energy calculations, ",
    "Deep-sea hydrothermal fluids, Notes, References). ",
    "It does not contain species-level trait data and is not compiled ",
    "into the animal_scaling schema. Skipping."
  )
  invisible(NULL)
}

## ---- Orchestrator -----------------------------------------------------------

#' Check for files, parse SD01, and write compiled CSV.
#' SD02 is skipped (geochemical flux data, not species traits).
#'
#' @param data_dir    Directory containing the Excel files
#' @param output_file Path for the compiled output CSV
run_pnas_intake <- function(
    data_dir    = "providers/pnas_2303764120/data/raw",
    output_file = "output/pnas_2303764120_compiled.csv"
) {
  message("=== PNAS Hoehler et al. 2023 Intake ===")
  message("Citation: ", CITATION)

  if (!check_pnas_files(data_dir)) {
    message("PNAS 2303764120: skipping intake — files not present.")
    return(invisible(NULL))
  }

  compiled <- parse_pnas_sd01(file.path(data_dir, .SD01_FILENAME))
  parse_pnas_sd02(file.path(data_dir, .SD02_FILENAME))  # logs skip message only

  message(sprintf("PNAS Hoehler 2023: %d compiled rows", nrow(compiled)))

  out_dir <- dirname(output_file)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(compiled, output_file)
  message("PNAS Hoehler 2023: wrote ", output_file)
  invisible(compiled)
}
