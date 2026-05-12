## Global_Plant_BodySize/R/plant_size_schema.R
## Schema definitions for the Global Plant Body Size database.
## Mirrors GlobalBodySize/R/body_size_schema.R architecture for plants.
##
## Data source: BIEN (Botanical Information and Ecology Network)
## Coverage: New World vascular plants (~150,000 species)
## Key traits: whole plant height (m), stem diameter/DBH (cm), growth form
##
## IMPORTANT SCOPE NOTE:
##   BIEN covers VASCULAR PLANTS only (angiosperms, gymnosperms, pteridophytes).
##   Bryophytes (mosses, liverworts, hornworts) are NOT in BIEN.
##   is_bryophyte is included as a placeholder flag for future non-BIEN intake.
##   Height and DBH are NOT applicable to bryophytes if added later.
##
## Schema design decisions:
##   - One row per (species × trait × observation) in raw tables
##   - Species in BIEN species list with NO trait data are retained with
##     NA trait columns and trait_data_available = FALSE in the final table
##   - Growth form is a categorical trait, kept in a separate raw file from
##     numeric size metrics
##   - Special flags: is_graminoid, is_bamboo, is_bryophyte
##   - Measurement class: linear_dimension (height, DBH) or categorical (growth form)
##
## Written by: Global_Plant_BodySize pipeline (ecology-user agent, 2026-05-11)

## ---- Canonical column schema: raw trait records table -----------------------
## One row per (species × BIEN observation)
## Written to:
##   output/bien_height_raw.csv
##   output/bien_dbh_raw.csv
##   output/bien_growth_form_raw.csv

plantsize_raw_schema_columns <- function() {
  c(
    # -- Provenance --
    "source_id",               # e.g. "bien"
    "source_display_name",     # "BIEN (Botanical Information and Ecology Network)"
    "source_doi",              # BIEN publication DOI (UNVERIFIED — confirm on run)
    "source_access_date",      # ISO 8601 date of BIEN query
    "bibliographic_citation",  # full citation string

    # -- Taxon (verbatim from BIEN) --
    "verbatim_species_name",   # scrubbed_species_binomial as returned by BIEN
    "higher_plant_group",      # monocot | dicot | gymnosperm | pteridophyte
    "family",                  # plant family from BIEN taxonomy
    "genus",                   # plant genus (parsed from species name)
    "subfamily",               # subfamily when available (for Bambusoideae detection)

    # -- Trait --
    "bien_trait_name",         # exact BIEN trait name string (e.g. "whole plant height")
    "trait_value_verbatim",    # raw string from BIEN trait_value column
    "trait_value_numeric",     # numeric after parsing and unit normalization
    "trait_unit_verbatim",     # unit string as returned by BIEN
    "trait_unit_canonical",    # "m" (height) | "cm" (DBH) | "categorical" (growth form)
    "measurement_type",        # height_m | dbh_cm | basal_diameter_cm | growth_form | other_size

    # -- Observation metadata --
    "observation_type",        # field_observation | literature | specimen | unknown
    "latitude",                # decimal degrees (NA if not plot-based or not available)
    "longitude",               # decimal degrees (NA if not available)
    "date_collected",          # ISO 8601 or NA
    "plot_name",               # plot identifier (NA if not available)
    "project_pi",              # PI or project of originating study
    "reference_number",        # BIEN internal reference ID

    # -- QA flags (populated in Stage 6) --
    "range_check_pass",        # logical: within plausible range for this growth form
    "unit_check_pass",         # logical: unit normalized without ambiguity
    "outlier_flag",            # logical: log-scale z-score |z| > 3 within growth form group
    "qa_note"                  # free-text QA note
  )
}

## ---- Canonical column schema: species-level summary table ------------------
## One row per species; aggregated from raw trait records.
## Written to: output/plant_size_summary.csv

plantsize_summary_schema_columns <- function() {
  c(
    # -- Taxon --
    "species_name",            # accepted BIEN species name (scrubbed_species_binomial)
    "higher_plant_group",      # monocot | dicot | gymnosperm | pteridophyte | unknown
    "family",
    "genus",
    "subfamily",               # populated for bamboo species when available

    # -- Growth form --
    "growth_form_canonical",   # canonical growth form (see growth_form_vocab.R)
    "growth_form_n_records",   # number of growth form observations in BIEN
    "growth_form_conflict",    # logical: species has conflicting growth form records

    # -- Special group flags --
    "is_graminoid",            # logical: family in (Poaceae, Cyperaceae, Juncaceae)
    "is_bamboo",               # logical: subfamily == Bambusoideae OR genus in bamboo list
    "is_bryophyte",            # logical: always FALSE for BIEN (placeholder for future)

    # -- Height (m) summary --
    "height_m_n",              # number of QA-passing height records
    "height_m_mean",           # arithmetic mean (m)
    "height_m_median",         # median (m)
    "height_m_sd",             # standard deviation (m)
    "height_m_min",            # minimum observed height (m)
    "height_m_max",            # maximum observed height (m)
    "height_m_cv",             # coefficient of variation = sd / mean (dimensionless)
    "height_m_confidence",     # "high" (n>=5) | "medium" (n=2-4) | "low" (n=1) | "none" (n=0)

    # -- DBH / stem diameter (cm) summary --
    "dbh_cm_n",
    "dbh_cm_mean",
    "dbh_cm_median",
    "dbh_cm_sd",
    "dbh_cm_min",
    "dbh_cm_max",
    "dbh_cm_cv",
    "dbh_cm_confidence",       # same tier system as height

    # -- Allometric readiness flag --
    "allometric_ready",        # logical: has BOTH height_m AND dbh_cm data (AGB-estimable)

    # -- Data availability --
    "trait_data_available",    # logical: any BIEN trait data for this species
    "height_data_available",   # logical: at least 1 QA-passing height record
    "dbh_data_available",      # logical: at least 1 QA-passing DBH record
    "growth_form_available",   # logical: at least 1 growth form record

    # -- Provenance --
    "source_id",
    "source_access_date"
  )
}

## ---- Measurement type vocabulary --------------------------------------------

plantsize_measurement_type_vocab <- function() {
  c(
    "height_m",             # whole plant height in meters
    "dbh_cm",               # stem diameter at breast height in cm
    "basal_diameter_cm",    # basal stem diameter (shrubs / herbs)
    "growth_form",          # categorical growth form record
    "other_size"            # catch-all for other BIEN size metrics
  )
}

## ---- Higher plant group vocabulary -----------------------------------------

plantsize_higher_plant_group_vocab <- function() {
  c("dicot", "monocot", "gymnosperm", "pteridophyte", "bryophyte", "unknown")
}

## ---- Confidence tier thresholds --------------------------------------------

plantsize_confidence_tier <- function(n) {
  ## n: integer vector of record counts
  ## Returns character vector of confidence tiers
  dplyr::case_when(
    is.na(n) | n == 0 ~ "none",
    n == 1             ~ "low",
    n >= 2 & n <= 4    ~ "medium",
    n >= 5             ~ "high",
    TRUE               ~ "none"
  )
}

## ---- Plausibility range limits by growth form (for QA range checks) --------
## Returns data.frame: growth_form_canonical, min_height_m, max_height_m,
##   min_dbh_cm, max_dbh_cm
## Limits are ecologically motivated (see references in PROJECT_PLAN.md).
## Flag values outside limits as range_check_pass = FALSE; do NOT delete them.

plantsize_range_limits <- function() {
  data.frame(
    growth_form_canonical = c(
      "tree", "shrub", "subshrub", "herb", "graminoid", "bamboo",
      "vine", "epiphyte", "aquatic", "parasite", "unknown"
    ),
    min_height_m = c(
      0.5,    # tree: excludes seedlings (separate life stage)
      0.1,    # shrub
      0.02,   # subshrub
      0.01,   # herb: includes tiny annual herbs
      0.01,   # graminoid: includes small sedges
      0.3,    # bamboo: smallest bamboos ~0.3 m
      0.1,    # vine
      0.001,  # epiphyte: includes tiny orchids / bromeliads
      0.001,  # aquatic: includes tiny floating plants (Wolffia)
      0.01,   # parasite
      0.001   # unknown: no lower constraint applied
    ),
    max_height_m = c(
      120,    # tree: Sequoia sempervirens ~116 m
      15,     # shrub: tall tree-like shrubs
      2,      # subshrub
      5,      # herb: giant herbs (Musa, Heliconia, Gunnera) reach ~5 m
      8,      # graminoid (non-bamboo): Miscanthus giganteus ~4 m; buffer to 8 m
      40,     # bamboo: Dendrocalamus giganteus ~40 m
      60,     # vine: canopy-reaching lianas in tall tropical forests
      15,     # epiphyte: tank bromeliads + tree-perch orchids; canopy-height capped
      5,      # aquatic: emergent aquatics (Typha, Phragmites) ~4 m
      3,      # parasite: Rafflesia-type excluded (not in BIEN); Cuscuta ~2 m
      120     # unknown: no upper constraint applied
    ),
    min_dbh_cm = c(
      0.1,   # tree: includes saplings
      NA,    # shrub: multi-stem; basal measure variable
      NA,    # subshrub
      NA,    # herb
      NA,    # graminoid
      0.1,   # bamboo: culm diameter
      NA,    # vine: stem diameter not standardized
      NA,    # epiphyte
      NA,    # aquatic
      NA,    # parasite
      0.1    # unknown
    ),
    max_dbh_cm = c(
      2000,  # tree: Adansonia (baobab) up to ~1000 cm; giant sequoia > 1000 cm
      200,   # shrub: multi-stem basal aggregate
      50,    # subshrub
      50,    # herb: large arborescent herbs
      30,    # graminoid: culm diameter
      40,    # bamboo: Dendrocalamus culm ~25 cm typical; buffer to 40 cm
      20,    # vine
      30,    # epiphyte
      30,    # aquatic
      20,    # parasite
      2000   # unknown
    ),
    stringsAsFactors = FALSE
  )
}
