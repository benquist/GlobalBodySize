## providers/hatton2015/load_hatton2015.R
## Hatton et al. 2015 — "The predator-prey power law: Biomass scaling across
## terrestrial and aquatic biomes." Science 349(6252):aac6284.
## DOI: 10.1126/science.aac6284
##
## User-provided file (not downloaded): providers/hatton2015/data/raw/database_s1.xls
## Sheet used: "ind" — individual predator-prey mass pairs (1,705 rows x 16 cols)
## Each row represents a prey-species observation; x_g = prey body mass (g),
## y_g = paired predator body mass (g).

suppressPackageStartupMessages({
  library(data.table)
  library(readxl)
})

## ---- Constants --------------------------------------------------------------

SOURCE_ID              <- "hatton2015"
SOURCE_DISPLAY         <- "Hatton et al. 2015"
SOURCE_DOI             <- "10.1126/science.aac6284"
DATA_NOTE              <- "User-provided file: database_s1.xls (Science 2015 Database S1)"
BIBLIOGRAPHIC_CITATION <- paste0(
  "Hatton IA, McCann KS, Fryxell JM, Davies TJ, Smerlak M, Sinclair ARE, Loreau M. 2015. ",
  "The predator-prey power law: Biomass scaling across terrestrial and aquatic biomes. ",
  "Science 349(6252):aac6284. https://doi.org/10.1126/science.aac6284"
)

TAXA_MAP <- c(
  "Mammal"       = "mammal",
  "Bird"         = "bird",
  "Fish"         = "fish",
  "Invertebrate" = "invertebrate",
  "Plant"        = "plant",
  "Protist"      = "protist",
  "Prokaryote"   = "prokaryote"
)

## ---- Check ------------------------------------------------------------------

check_hatton2015_file <- function(data_dir) {
  xls_path <- file.path(data_dir, "database_s1.xls")
  if (file.exists(xls_path)) return(TRUE)
  message(
    "Hatton2015: file not found: ", xls_path, "\n",
    "Please place database_s1.xls (Science 2015 Database S1) in ", data_dir
  )
  FALSE
}

## ---- Parse ------------------------------------------------------------------

parse_hatton2015 <- function(data_file) {
  source_access_date <- format(Sys.Date(), "%Y-%m-%d")

  if (!exists("animal_scaling_schema_columns", mode = "function"))
    source("R/animal_scaling_schema.R")

  raw <- readxl::read_excel(data_file, sheet = "ind")
  setDT(raw)
  message(sprintf("Hatton2015: ind sheet — %d rows x %d columns", nrow(raw), ncol(raw)))

  x_g <- suppressWarnings(as.numeric(raw$x_g))
  y_g <- suppressWarnings(as.numeric(raw$y_g))

  out <- data.table(
    source_id              = SOURCE_ID,
    source_display_name    = SOURCE_DISPLAY,
    source_doi             = SOURCE_DOI,
    source_access_date     = source_access_date,
    bibliographic_citation = BIBLIOGRAPHIC_CITATION,
    original_row_id        = as.character(raw$Unique_ID),
    source_file_path       = "providers/hatton2015/data/raw/database_s1.xls",

    ## ---- Taxonomy ----------------------------------------------------------
    verbatim_taxon_name    = as.character(raw$Species),
    input_taxonomic_group  = unname(TAXA_MAP[as.character(raw$Taxa)]),
    input_taxonomic_rank   = "species",
    resolved_taxon_name    = NA_character_,
    kingdom                = NA_character_,
    phylum                 = NA_character_,
    class                  = NA_character_,
    order                  = as.character(raw$Order),
    family                 = as.character(raw$Family),
    genus                  = as.character(raw$Genus),

    ## ---- Body mass ---------------------------------------------------------
    body_mass_g            = x_g,
    body_mass_source       = "measured",

    ## ---- Metabolic rate ----------------------------------------------------
    metabolic_rate_value   = NA_real_,
    metabolic_rate_unit    = NA_character_,
    metabolic_rate_type    = NA_character_,
    metabolic_rate_temp_C  = NA_real_,

    ## ---- Life history ------------------------------------------------------
    lifespan_max_years     = NA_real_,
    lifespan_source        = NA_character_,
    age_at_maturity_years  = NA_character_,
    litter_clutch_size     = NA_character_,
    litters_per_year       = NA_character_,

    ## ---- Growth ------------------------------------------------------------
    growth_rate_value      = NA_real_,
    growth_rate_unit       = NA_character_,
    growth_model           = NA_character_,

    ## ---- QA ----------------------------------------------------------------
    qa_flag = fcase(
      is.na(x_g) | x_g <= 0, "body_mass_missing_or_invalid",
      default = "ok"
    ),
    qa_body_mass_range = fcase(
      !is.na(x_g) & x_g > 0 & x_g < 1e-6,  "below_1ug",
      !is.na(x_g) & x_g > 0 & x_g < 0.001, "below_1mg",
      !is.na(x_g) & x_g > 0 & x_g > 1e8,   "above_100t",
      !is.na(x_g) & x_g > 0,                "ok",
      default = NA_character_
    ),
    qa_metabolic_unit_verified = NA_character_,

    ## ---- Extra provenance (beyond 34-column schema) ------------------------
    predator_mass_g_paired = y_g
  )

  schema_cols <- animal_scaling_schema_columns()
  for (col in setdiff(schema_cols, names(out))) out[[col]] <- NA
  out[, c(schema_cols, "predator_mass_g_paired"), with = FALSE]
}

## ---- Orchestrator -----------------------------------------------------------

run_hatton2015_intake <- function(
    data_dir    = "providers/hatton2015/data/raw",
    output_file = "output/hatton2015_compiled.csv"
) {
  message("=== Hatton et al. 2015 Intake ===")
  message("Citation: ", BIBLIOGRAPHIC_CITATION)
  message("Note: ", DATA_NOTE)

  if (!check_hatton2015_file(data_dir)) {
    stop(
      "Hatton2015: database_s1.xls not found in ", data_dir, ". ",
      "Please place the file and re-run.",
      call. = FALSE
    )
  }

  compiled <- parse_hatton2015(file.path(data_dir, "database_s1.xls"))

  out_dir <- dirname(output_file)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  fwrite(compiled, output_file)
  message(sprintf("Hatton2015: wrote %d rows to %s", nrow(compiled), output_file))
  invisible(compiled)
}
