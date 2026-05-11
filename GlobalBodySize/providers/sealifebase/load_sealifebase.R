## providers/sealifebase/load_sealifebase.R
## SeaLifeBase — body mass and maximum body length for marine non-fish species
## Froese R, Pauly D (eds). 2024. SeaLifeBase.
## https://www.sealifebase.ca
##
## Data accessed via the rfishbase R package (server = "sealifebase").
## rfishbase handles its own local caching; no dest_dir needed here.
##
## UNVERIFIED: Weight column units — rfishbase SeaLifeBase Weight is expected to
##   be in grams per SeaLifeBase convention, but this should be confirmed against
##   a known species before using mass values in analysis.
## UNVERIFIED: Length column units — rfishbase Length for SeaLifeBase is expected
##   to be in cm, consistent with FishBase convention.
##
## Outputs:
##   output/sealifebase_mass_compiled.csv   — body mass table (body_mass_schema.R)
##   output/sealifebase_linear_compiled.csv — linear size table (body_size_schema.R)

suppressPackageStartupMessages({
  library(data.table)
  library(rfishbase)
})

## ---- Constants --------------------------------------------------------------

SEALIFEBASE_SOURCE_ID <- "sealifebase_froese2024"
SEALIFEBASE_DISPLAY   <- "SeaLifeBase (Froese & Pauly 2024)"
SEALIFEBASE_DOI       <- NA_character_   # no DOI; living database
SEALIFEBASE_SERVER    <- "sealifebase"
SEALIFEBASE_CITATION  <- paste0(
  "Froese R, Pauly D (eds). 2024. SeaLifeBase. ",
  "World Wide Web electronic publication. ",
  "https://www.sealifebase.ca. ",
  "Accessed ", format(Sys.Date(), "%Y-%m-%d"), "."
)

## ---- Pull species data via rfishbase ----------------------------------------

.sealifebase_pull_species <- function() {
  message("SeaLifeBase: pulling species table via rfishbase ...")
  message("  server = '", SEALIFEBASE_SERVER, "'")
  message("  rfishbase handles local caching internally")

  ## rfishbase::species(server="sealifebase") does NOT expose a 'Species' column
  ## (verified 2026-05-11). Use load_taxa() to get full binomial + higher taxonomy,
  ## then merge onto species() by SpecCode.
  sp <- tryCatch(
    rfishbase::species(
      server = SEALIFEBASE_SERVER,
      fields = c(
        "SpecCode", "Genus", "FBname",
        "Length", "LTypeMaxM",
        "Weight", "WeightFemale", "MaxWeightRef",
        "CommonLength", "LTypeComM"
      )
    ),
    error = function(e) {
      stop("SeaLifeBase: rfishbase::species() failed: ", conditionMessage(e),
           call. = FALSE)
    }
  )

  if (is.null(sp) || nrow(sp) == 0) {
    stop("SeaLifeBase: rfishbase::species() returned empty result. ",
         "Check rfishbase installation and network connection.",
         call. = FALSE)
  }

  sp <- as.data.table(sp)
  message(sprintf("SeaLifeBase: %d species records from species() table", nrow(sp)))

  ## load_taxa() provides: SpecCode, Species (full binomial), Family, Order,
  ## Class, Phylum, Kingdom — join by SpecCode to enrich species table
  taxa <- tryCatch(
    as.data.table(rfishbase::load_taxa(server = SEALIFEBASE_SERVER)),
    error = function(e) {
      message("SeaLifeBase WARNING: load_taxa() failed — Species/taxonomy columns will be NA: ",
              conditionMessage(e))
      NULL
    }
  )

  if (!is.null(taxa) && nrow(taxa) > 0) {
    taxa <- taxa[, .(SpecCode, Species, Family, Order, Class, Phylum, Kingdom)]
    sp <- merge(sp, taxa, by = "SpecCode", all.x = TRUE)
    message(sprintf("SeaLifeBase: taxonomy joined; %d / %d rows have Species name",
                    sum(!is.na(sp$Species)), nrow(sp)))
  } else {
    sp[, c("Species", "Family", "Order", "Class", "Phylum", "Kingdom") := NA_character_]
    message("SeaLifeBase WARNING: taxonomy join skipped — Species/taxonomy set to NA")
  }

  sp
}

## ---- Build mass table -------------------------------------------------------

.sealifebase_build_mass <- function(dt) {
  if (!"Weight" %in% names(dt)) {
    stop(
      "SeaLifeBase: 'Weight' column not found in species table. ",
      "Available columns: ", paste(names(dt), collapse = ", "),
      call. = FALSE
    )
  }

  dt[, .src_row   := .I]
  dt[, .weight_g  := suppressWarnings(as.numeric(Weight))]

  mass_dt <- dt[!is.na(.weight_g) & .weight_g > 0]
  message(sprintf("SeaLifeBase mass: %d / %d species have Weight data",
                  nrow(mass_dt), nrow(dt)))

  ## UNVERIFIED: Weight is assumed grams per SeaLifeBase convention.
  ## WeightFemale is available but not merged here; kept as separate column in source.
  out <- data.table(
    source_id                  = SEALIFEBASE_SOURCE_ID,
    source_display_name        = SEALIFEBASE_DISPLAY,
    source_doi                 = SEALIFEBASE_DOI,
    source_access_date         = as.character(Sys.Date()),
    bibliographic_citation     = SEALIFEBASE_CITATION,
    dataset_id                 = SEALIFEBASE_SOURCE_ID,
    original_row_id            = mass_dt$.src_row,
    source_file_path           = "rfishbase::species(server='sealifebase')",

    verbatim_taxon_name        = as.character(mass_dt$Species),  # full binomial from load_taxa()
    verbatim_authorship        = NA_character_,
    input_taxonomic_group      = "marine_other",
    input_taxonomic_rank       = "species",

    resolved_taxon_name        = as.character(mass_dt$Species),
    resolved_authorship        = NA_character_,
    resolved_taxon_rank        = "species",
    resolved_taxonomic_group   = "marine_other",
    kingdom                    = as.character(mass_dt$Kingdom),
    phylum                     = as.character(mass_dt$Phylum),
    class                      = as.character(mass_dt$Class),
    order                      = as.character(mass_dt$Order),
    family                     = as.character(mass_dt$Family),
    genus                      = as.character(mass_dt$Genus),
    primary_backbone           = NA_character_,
    gbif_usage_key             = NA_integer_,
    group_specific_taxon_id    = as.character(mass_dt$SpecCode),
    group_specific_backbone    = "SeaLifeBase_SpecCode",
    match_method               = "direct_field",
    match_confidence           = "unassessable",
    matched_status             = "unresolved",
    synonym_type               = NA_character_,
    cross_group_collision_flag = NA,
    genus_only_flag            = FALSE,
    reconciliation_note        = paste0(
      "SeaLifeBase SpecCode=", mass_dt$SpecCode,
      "; no WoRMS/GBIF backbone reconciliation performed"
    ),
    reconciliation_timestamp_utc = NA_character_,
    backbone_version           = NA_character_,

    ## Weight column: maximum weight in grams (UNVERIFIED — confirm units)
    mass_g                     = mass_dt$.weight_g,
    mass_g_min                 = NA_real_,
    mass_g_max                 = mass_dt$.weight_g,   # SeaLifeBase Weight is maximum weight
    mass_se                    = NA_real_,
    mass_n                     = NA_integer_,

    mass_type                  = "wet",
    measurement_method         = "literature_mean",
    life_stage                 = "adult",
    sex                        = "unknown",

    decimal_latitude           = NA_real_,
    decimal_longitude          = NA_real_,
    coordinate_uncertainty_m   = NA_real_,
    country_code               = NA_character_,

    year_measured              = NA_integer_,
    date_measured              = NA_character_,

    measurement_id             = paste0(SEALIFEBASE_SOURCE_ID, "_mass_", mass_dt$.src_row),
    measurement_type           = "body mass",
    measurement_value          = as.character(mass_dt$.weight_g),
    measurement_unit           = "g",
    measurement_determined_date = NA_character_,
    basis_of_record            = "Literature",

    mass_confidence            = "medium",
    range_check_pass           = NA,
    unit_check_pass            = NA,    # UNVERIFIED: confirm Weight column is grams
    outlier_flag               = NA,
    qa_status                  = "needs_review",
    qa_note                    = paste0(
      "SeaLifeBase maximum weight; UNVERIFIED units (expected grams per rfishbase convention); ",
      "SpecCode=", mass_dt$SpecCode, "; ",
      "backbone reconciliation pending"
    )
  )

  out
}

## ---- Build linear size table ------------------------------------------------

.sealifebase_build_linear <- function(dt) {
  if (!"Length" %in% names(dt)) {
    stop(
      "SeaLifeBase: 'Length' column not found in species table. ",
      "Available columns: ", paste(names(dt), collapse = ", "),
      call. = FALSE
    )
  }

  dt[, .src_row    := .I]
  dt[, .length_cm  := suppressWarnings(as.numeric(Length))]

  len_dt <- dt[!is.na(.length_cm) & .length_cm > 0]
  message(sprintf("SeaLifeBase linear: %d / %d species have Length data",
                  nrow(len_dt), nrow(dt)))

  ## LTypeMaxM: length type code e.g. "TL", "SL", "BL"; use as-is for size_dimension_notes
  ltype <- as.character(len_dt$LTypeMaxM)
  ltype[is.na(ltype) | trimws(ltype) == ""] <- "unspecified"

  out <- data.table(
    source_id              = SEALIFEBASE_SOURCE_ID,
    source_display_name    = SEALIFEBASE_DISPLAY,
    source_doi             = SEALIFEBASE_DOI,
    source_access_date     = as.character(Sys.Date()),
    bibliographic_citation = SEALIFEBASE_CITATION,
    dataset_id             = SEALIFEBASE_SOURCE_ID,
    original_row_id        = len_dt$.src_row,
    source_file_path       = "rfishbase::species(server='sealifebase')",

    verbatim_taxon_name    = as.character(len_dt$Species),  # full binomial from load_taxa()
    verbatim_authorship    = NA_character_,
    input_taxonomic_group  = "marine_other",
    input_taxonomic_rank   = "species",

    resolved_taxon_name    = as.character(len_dt$Species),
    resolved_authorship    = NA_character_,
    resolved_taxon_rank    = "species",
    kingdom                = as.character(len_dt$Kingdom),
    phylum                 = as.character(len_dt$Phylum),
    class                  = as.character(len_dt$Class),
    order                  = as.character(len_dt$Order),
    family                 = as.character(len_dt$Family),
    genus                  = as.character(len_dt$Genus),
    primary_backbone       = NA_character_,
    gbif_usage_key         = NA_integer_,
    aphia_id               = NA_integer_,
    match_method           = "direct_field",
    match_confidence       = "unassessable",
    matched_status         = "unresolved",
    reconciliation_note    = paste0(
      "SeaLifeBase SpecCode=", len_dt$SpecCode,
      "; no WoRMS/GBIF backbone reconciliation performed"
    ),

    size_measurement_class = "linear_dimension",
    size_measurement_type  = "linear_length",
    ## UNVERIFIED: Length assumed to be in cm per rfishbase/SeaLifeBase convention
    size_value_cm          = len_dt$.length_cm,
    size_value_cm_min      = NA_real_,
    size_value_cm_max      = len_dt$.length_cm,   # maximum length field
    size_dimension_notes   = ltype,               # LTypeMaxM code: "TL", "SL", "BL", etc.

    mass_g_equiv           = NA_real_,
    lw_conversion_method   = NA_character_,

    life_stage             = "adult",
    sex                    = "unknown",
    specimen_type          = "unknown",
    biological_unit        = "individual",
    measurement_method     = "literature",
    basis_of_record        = "Literature",

    size_reference_doi     = NA_character_,
    size_reference_text    = SEALIFEBASE_CITATION,

    decimal_latitude       = NA_real_,
    decimal_longitude      = NA_real_,
    country_code           = NA_character_,
    ocean_region           = NA_character_,

    worms_valid_name       = NA_character_,
    worms_phylum           = NA_character_,
    worms_class            = NA_character_,
    worms_order            = NA_character_,
    worms_family           = NA_character_,

    size_confidence        = "medium",
    qa_status              = "needs_review",
    qa_note                = paste0(
      "SeaLifeBase maximum length; UNVERIFIED units (expected cm per rfishbase convention); ",
      "LTypeMaxM=", ltype, "; ",
      "backbone reconciliation pending"
    ),

    date_added             = as.character(Sys.Date())
  )

  out
}

## ---- Master runner ----------------------------------------------------------

run_sealifebase_intake <- function(
  output_mass   = "output/sealifebase_mass_compiled.csv",
  output_linear = "output/sealifebase_linear_compiled.csv",
  overwrite     = FALSE
) {
  message("=== SeaLifeBase Intake ===")
  message("Citation: ", SEALIFEBASE_CITATION)

  if (!overwrite && file.exists(output_mass) && file.exists(output_linear)) {
    message("SeaLifeBase: output files already exist (set overwrite=TRUE to rerun)")
    return(invisible(NULL))
  }

  ## 1. Pull species data via rfishbase ----------------------------------------
  sp_dt <- .sealifebase_pull_species()

  ## 2. Build and write mass table ---------------------------------------------
  mass_out <- .sealifebase_build_mass(sp_dt)
  dir.create(dirname(output_mass), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(mass_out, output_mass)
  message(sprintf("SeaLifeBase mass compiled:   %d rows -> %s", nrow(mass_out), output_mass))

  ## 3. Build and write linear size table --------------------------------------
  linear_out <- .sealifebase_build_linear(sp_dt)
  dir.create(dirname(output_linear), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(linear_out, output_linear)
  message(sprintf("SeaLifeBase linear compiled: %d rows -> %s", nrow(linear_out), output_linear))

  ## 4. Summary ----------------------------------------------------------------
  ltype_tab <- sort(table(linear_out$size_dimension_notes), decreasing = TRUE)
  message("Length type (LTypeMaxM) breakdown:")
  for (nm in names(ltype_tab)) {
    message(sprintf("  %-15s %d rows", nm, ltype_tab[[nm]]))
  }

  n_spp <- length(unique(sp_dt[, paste(Genus, Species)]))
  message(sprintf("Total unique species in SeaLifeBase pull: %d", n_spp))

  invisible(list(mass = mass_out, linear = linear_out))
}

## ---- Standalone runner ------------------------------------------------------
if (!interactive() && !exists("SEALIFEBASE_SOURCED_AS_LIBRARY")) {
  run_sealifebase_intake(
    output_mass   = "output/sealifebase_mass_compiled.csv",
    output_linear = "output/sealifebase_linear_compiled.csv"
  )
}

SEALIFEBASE_SOURCED_AS_LIBRARY <- TRUE
