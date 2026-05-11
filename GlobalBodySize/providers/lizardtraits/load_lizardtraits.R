## providers/lizardtraits/load_lizardtraits.R
## Lizard Traits of the World — Meiri 2018 (Dryad doi:10.5061/dryad.f6t39kj)
##
## Reference:
##   Meiri S. 2018. Traits of lizards of the world: Variation around a successful
##   evolutionary design. Global Ecology and Biogeography 27:1004-1016.
##   DOI: 10.1111/geb.12773
##
## Data deposit:
##   Meiri S. 2018. Data from: Traits of lizards of the world.
##   Dryad Digital Repository. https://doi.org/10.5061/dryad.f6t39kj
##
## Coverage: 6,657 lizard species (Squamata sensu lato incl. Amphisbaenia);
##   taxonomy from the Reptile Database (Uetz, 2017/2018).
##
## SIZE COLUMNS (all in mm; divide by 10 for cm):
##   "maximum SVL"            — max snout-vent length, n=6,633 (100%)
##   "female SVL"             — mean female SVL, n=4,452 (67%)
##   "hatchling/neonate SVL"  — neonate SVL midpoint, n=2,112 (32%)
##
## MASS: No direct measurements. Mass is COMPUTED from allometric equations:
##   log10(mass_g) = intercept + slope * log10(maximum SVL [mm])
##   Equations from Feldman et al. 2016 and Meiri 2008; grouped by clade
##   ("mass_equation" column). All 6,657 species have intercept + slope values.
##   Computed mass is flagged as size_measurement_type = "lw_modeled" in the
##   mass table, and match_method = "allometric_equation".
##
## DATA ACCESS: Dryad requires authentication for direct file download.
##   Place the file manually:
##     providers/lizardtraits/data/raw/lizard_traits_meiri2018.csv
##   Source: https://datadryad.org/dataset/doi:10.5061/dryad.f6t39kj
##   File: "Appendix S1 - Lizard data version 1.0.csv"
##
## OUTPUTS:
##   output/lizardtraits_mass_compiled.csv    — allometric mass estimates (lw_modeled)
##   output/lizardtraits_linear_compiled.csv  — SVL linear size rows

suppressPackageStartupMessages({
  library(data.table)
})

## ---- Constants --------------------------------------------------------------

LIZARDTRAITS_SOURCE_ID   <- "lizardtraits_meiri2018"
LIZARDTRAITS_DISPLAY     <- "Lizard Traits of the World (Meiri 2018)"
LIZARDTRAITS_DOI         <- "10.1111/geb.12773"
LIZARDTRAITS_DATA_DOI    <- "10.5061/dryad.f6t39kj"
LIZARDTRAITS_CITATION    <- paste0(
  "Meiri S. 2018. Traits of lizards of the world: Variation around a successful ",
  "evolutionary design. Global Ecology and Biogeography 27:1004-1016. ",
  "https://doi.org/10.1111/geb.12773. ",
  "Data: https://doi.org/10.5061/dryad.f6t39kj"
)

## All species in this dataset are lizards (Squamata + Amphisbaenia)
LIZARDTRAITS_GROUP <- "reptile"

## ---- Helpers ----------------------------------------------------------------

## Compute allometric mass estimate: log10(mass_g) = intercept + slope * log10(SVL_mm)
.compute_mass_g <- function(svl_mm, intercept, slope) {
  svl_mm   <- suppressWarnings(as.numeric(svl_mm))
  intercept <- suppressWarnings(as.numeric(intercept))
  slope     <- suppressWarnings(as.numeric(slope))
  out <- rep(NA_real_, length(svl_mm))
  ok  <- !is.na(svl_mm) & svl_mm > 0 & !is.na(intercept) & !is.na(slope)
  out[ok] <- 10^(intercept[ok] + slope[ok] * log10(svl_mm[ok]))
  out
}

## ---- Main function ----------------------------------------------------------

run_lizardtraits_intake <- function(
    raw_file      = "providers/lizardtraits/data/raw/lizard_traits_meiri2018.csv",
    output_mass   = "output/lizardtraits_mass_compiled.csv",
    output_linear = "output/lizardtraits_linear_compiled.csv"
) {
  message("=== Lizard Traits Intake ===")
  message("Citation: ", LIZARDTRAITS_CITATION)

  ## 1. Check file presence ----------------------------------------------------
  if (!file.exists(raw_file)) {
    stop(
      "Raw data file not found: ", raw_file, "\n",
      "Download from Dryad (requires free account login):\n",
      "  https://datadryad.org/dataset/doi:10.5061/dryad.f6t39kj\n",
      "File: 'Appendix S1 - Lizard data version 1.0.csv'\n",
      "Place at: ", raw_file,
      call. = FALSE
    )
  }

  ## 2. Load -------------------------------------------------------------------
  dt <- data.table::fread(raw_file, encoding = "UTF-8",
                           na.strings = c("", "NA", "N/A", "na", "NULL"))
  message(sprintf("Loaded %d rows, %d columns", nrow(dt), ncol(dt)))

  ## Verify expected columns
  required <- c("Binomial", "Genus", "Family", "maximum SVL", "intercept", "slope")
  missing  <- setdiff(required, names(dt))
  if (length(missing) > 0) {
    stop("Missing expected columns: ", paste(missing, collapse=", "),
         "\n  Available: ", paste(names(dt), collapse=", "), call.=FALSE)
  }

  ## 3. Build mass table (allometric estimates) --------------------------------
  message("Computing allometric mass from SVL + equations (Feldman et al. 2016)...")
  dt[, computed_mass_g := .compute_mass_g(`maximum SVL`, intercept, slope)]

  n_mass <- sum(!is.na(dt$computed_mass_g))
  message(sprintf("  Mass computed for %d / %d species", n_mass, nrow(dt)))

  ## Source accessor for mass schema
  source_access_date <- as.character(Sys.Date())

  mass_dt <- dt[!is.na(computed_mass_g), .(
    source_id              = LIZARDTRAITS_SOURCE_ID,
    source_display_name    = LIZARDTRAITS_DISPLAY,
    source_doi             = LIZARDTRAITS_DOI,
    source_access_date     = source_access_date,
    bibliographic_citation = LIZARDTRAITS_CITATION,
    dataset_id             = LIZARDTRAITS_SOURCE_ID,
    original_row_id        = .I,
    verbatim_taxon_name    = Binomial,
    verbatim_authorship    = NA_character_,
    kingdom                = "Animalia",
    phylum                 = "Chordata",
    class                  = "Reptilia",
    order                  = NA_character_,      # not in source
    family                 = Family,
    genus                  = Genus,
    worms_valid_name       = NA_character_,
    worms_aphia_id         = NA_integer_,
    match_method           = "allometric_equation",  # log10 SVL→mass via Feldman et al. 2016
    taxon_name_used        = Binomial,
    input_taxonomic_group  = LIZARDTRAITS_GROUP,
    mass_g                 = computed_mass_g,
    mass_measurement_type  = "lw_modeled",   # computed, not directly measured
    mass_notes             = paste0(
      "Allometric estimate: log10(mass_g) = intercept + slope*log10(SVL_mm); ",
      "equation group: ", `mass_equation (Feldman et al. 2016 unless stated)`
    ),
    sex                    = NA_character_,
    life_stage             = "adult",        # maximum SVL is adult measurement
    n_individuals          = NA_integer_,
    measurement_precision  = NA_character_,
    geographic_region      = NA_character_,
    habitat                = NA_character_,
    data_quality_flag      = "allometric_modeled"
  )]

  dir.create(dirname(output_mass), recursive=TRUE, showWarnings=FALSE)
  data.table::fwrite(mass_dt, output_mass)
  message(sprintf("Mass table: %d rows -> %s", nrow(mass_dt), output_mass))

  ## 4. Build linear size table (pivot 3 SVL columns) -------------------------
  message("Pivoting SVL columns to long format...")

  ## Define the three SVL columns: (column_name, sex, life_stage, dimension_label)
  svl_cols <- list(
    list(col="maximum SVL",           sex=NA_character_, life_stage="adult",   dim="SVL_max"),
    list(col="female SVL",            sex="female",      life_stage="adult",   dim="SVL_female"),
    list(col="hatchling/neonate SVL", sex=NA_character_, life_stage="neonate", dim="SVL_neonate")
  )

  long_list <- lapply(svl_cols, function(spec) {
    col_vals <- suppressWarnings(as.numeric(dt[[spec$col]]))
    sub_dt   <- dt[!is.na(col_vals) & col_vals > 0]
    if (nrow(sub_dt) == 0) return(NULL)
    svl_numeric <- col_vals[!is.na(col_vals) & col_vals > 0]
    data.table::data.table(
      source_id              = LIZARDTRAITS_SOURCE_ID,
      source_display_name    = LIZARDTRAITS_DISPLAY,
      source_doi             = LIZARDTRAITS_DOI,
      source_access_date     = source_access_date,
      bibliographic_citation = LIZARDTRAITS_CITATION,
      dataset_id             = LIZARDTRAITS_SOURCE_ID,
      original_row_id        = seq_len(nrow(sub_dt)),
      verbatim_taxon_name    = sub_dt$Binomial,
      verbatim_authorship    = NA_character_,
      kingdom                = "Animalia",
      phylum                 = "Chordata",
      class                  = "Reptilia",
      order                  = NA_character_,
      family                 = sub_dt$Family,
      genus                  = sub_dt$Genus,
      worms_valid_name       = NA_character_,
      worms_aphia_id         = NA_integer_,
      aphia_id               = NA_integer_,
      match_method           = "direct_field",
      taxon_name_used        = sub_dt$Binomial,
      input_taxonomic_group  = LIZARDTRAITS_GROUP,
      size_value_cm          = svl_numeric / 10,  # mm -> cm
      size_value_original    = svl_numeric,
      size_unit_original     = "mm",
      size_measurement_class = "linear_dimension",
      size_measurement_type  = "linear_length",
      size_dimension_notes   = spec$dim,   # SVL_max / SVL_female / SVL_neonate
      sex                    = spec$sex,
      life_stage             = spec$life_stage,
      mass_g_equiv           = NA_real_,   # L-W conversion deferred
      lw_conversion_method   = NA_character_,
      n_individuals          = NA_integer_,
      measurement_precision  = NA_character_,
      geographic_region      = NA_character_,
      ocean_region           = NA_character_,
      habitat                = NA_character_,
      data_quality_flag      = NA_character_
    )
  })

  linear_dt <- data.table::rbindlist(Filter(Negate(is.null), long_list), fill=TRUE)
  dir.create(dirname(output_linear), recursive=TRUE, showWarnings=FALSE)
  data.table::fwrite(linear_dt, output_linear)
  message(sprintf("Linear table: %d rows -> %s", nrow(linear_dt), output_linear))

  ## 5. Summary ----------------------------------------------------------------
  svl_tab <- table(linear_dt$size_dimension_notes)
  message("SVL dimension breakdown:")
  for (nm in names(svl_tab)) message(sprintf("  %s: %d rows", nm, svl_tab[[nm]]))
  message("Unique species (linear): ", length(unique(linear_dt$verbatim_taxon_name)))

  invisible(list(mass=mass_dt, linear=linear_dt))
}

## ---- Run on source() (not library) ------------------------------------------
if (!exists("LIZARDTRAITS_SOURCED_AS_LIBRARY")) {
  run_lizardtraits_intake()
}
