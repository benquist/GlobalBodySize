# qa_checks.R — Two-pass trait QA validation and per-dataset spot-check sampling
#
# Pass 1 (structural): numeric parsability, unit class compatibility,
#                       species resolution, coordinate bounds, sign checks.
# Pass 2 (biological plausibility): scientifically cited range bounds,
#                                    categorical vocabulary validation,
#                                    cross-trait red flags.
# Both passes append flags to `qa_flags`; flags are prefixed P1_ or P2_
# so downstream consumers can distinguish structural from biological failures.

# ---------------------------------------------------------------------------
# Allowed vocabulary for categorical traits.
# Sources:
#   growth_form: Raunkiaer 1934; Díaz et al. 2016 Nature 529:167-171.
#     DOI:10.1038/nature16489.
#   leaf_phenology: Reich et al. 2014 Nature 506:78-81. DOI:10.1038/nature12902.
#   dispersal_syndrome: van der Pijl 1982 Principles of Dispersal in Higher
#     Plants (Springer); Vittoz & Engler 2007 Plant Ecol 192:313.
#     DOI:10.1007/s11258-007-9298-3.
# ---------------------------------------------------------------------------

dryad_categorical_vocab <- function() {
  list(
    growth_form = c(
      "tree", "shrub", "herb", "grass", "vine", "liana",
      "subshrub", "fern", "moss", "epiphyte", "succulent", "palm"
    ),
    leaf_phenology = c(
      "evergreen", "deciduous", "semi-deciduous",
      "drought-deciduous", "cold-deciduous"
    ),
    dispersal_syndrome = c(
      "anemochory", "endozoochory", "epizoochory",
      "hydrochory", "autochory", "myrmecochory", "barochory"
    )
  )
}

# ---------------------------------------------------------------------------
# Trait plausibility ranges (standard units from the trait dictionary).
# Loaded from dictionary at runtime; hard-coded fallback with full citations
# for all 30 numeric traits.
#
# Key sources for fallback ranges:
#   Kattge et al. 2020 Glob Change Biol 26:119-188. DOI:10.1111/gcb.14904 (TRY)
#   Díaz et al. 2016 Nature 529:167-171. DOI:10.1038/nature16489 (global LHS)
#   Wright et al. 2004 Nature 428:821-827. DOI:10.1038/nature02403 (GLOPNET)
#   Choat et al. 2012 Nature 491:752-755. DOI:10.1038/nature11688 (P50 global)
#   Bartlett et al. 2012 Ecol Lett 15:393-405. DOI:10.1111/j.1461-0248.2012.01751.x (TLP)
#   Chave et al. 2009 Ecol Lett 12:351-366. DOI:10.1111/j.1461-0248.2009.01285.x (wood density)
#   Moles et al. 2005 Science 307:576-580. DOI:10.1126/science.1105809 (seed mass)
#   Pérez-Harguindeguy et al. 2013 Aust J Bot 61:167-234. DOI:10.1071/BT12225 (protocol)
#   Tyree & Ewers 1991 New Phytol 119:345-360. DOI:10.1111/j.1469-8137.1991.tb00035.x (Ks)
#   Weemstra et al. 2016 New Phytol 211:1213-1229. DOI:10.1111/nph.14065 (SRL)
#   Zanne et al. 2010 Am J Bot 97:519-531. DOI:10.3732/ajb.0900178 (vessel density)
#   Wheeler et al. 2005 Am J Bot 92:1588-1600. DOI:10.3732/ajb.92.9.1588 (vessel diameter)
# ---------------------------------------------------------------------------

dryad_trait_ranges <- function(dictionary = NULL) {
  if (is.null(dictionary)) {
    if (exists("dryad_read_trait_dictionary", mode = "function", inherits = TRUE)) {
      dictionary <- get("dryad_read_trait_dictionary", mode = "function", inherits = TRUE)()
    }
  }
  if (!is.null(dictionary) &&
      all(c("standardized_trait_name", "value_min", "value_max") %in% names(dictionary))) {
    # Only load ranges for numeric traits (categorical have NA min/max)
    num_rows <- dictionary[dictionary$value_type != "categorical", , drop = FALSE]
    ranges <- lapply(seq_len(nrow(num_rows)), function(i) {
      list(
        min = suppressWarnings(as.numeric(num_rows$value_min[[i]])),
        max = suppressWarnings(as.numeric(num_rows$value_max[[i]]))
      )
    })
    names(ranges) <- num_rows$standardized_trait_name
    return(ranges)
  }

  # Hard-coded fallback — full citations above
  list(
    # Leaf economics
    leaf_area                         = list(min = 1,        max = 3e6),
    specific_leaf_area                = list(min = 0.5,      max = 500),
    leaf_dry_matter_content           = list(min = 10,       max = 990),
    leaf_n                            = list(min = 0.5,      max = 60),
    leaf_p                            = list(min = 0.05,     max = 10),
    leaf_carbon                       = list(min = 350,      max = 600),
    leaf_cn_ratio                     = list(min = 5,        max = 200),
    leaf_chlorophyll                  = list(min = 1,        max = 100),
    leaf_lifespan                     = list(min = 1,        max = 48),
    leaf_water_content                = list(min = 0.5,      max = 30),
    leaf_thickness                    = list(min = 0.01,     max = 20),
    # Gas exchange
    photosynthetic_rate               = list(min = 0.1,      max = 60),
    stomatal_conductance              = list(min = 0.5,      max = 2000),
    # Stem structure
    wood_density                      = list(min = 0.05,     max = 1.4),
    stem_specific_density             = list(min = 0.05,     max = 1.4),
    stem_diameter                     = list(min = 0.01,     max = 1000),
    bark_thickness                    = list(min = 0.1,      max = 200),
    vessel_density                    = list(min = 0.1,      max = 3000),
    xylem_vessel_diameter             = list(min = 5,        max = 500),
    huber_value                       = list(min = 0.00001,  max = 0.01),
    # Whole plant
    seed_mass                         = list(min = 0.001,    max = 2.5e7),
    fruit_mass                        = list(min = 1,        max = 5e6),
    plant_height                      = list(min = 0.001,    max = 120),
    # Root economics
    specific_root_length              = list(min = 1,        max = 1000),
    root_tissue_density               = list(min = 0.05,     max = 1.0),
    # Hydraulics — note: pressure traits have negative min AND max
    p50                               = list(min = -20,      max = -0.05),
    p88                               = list(min = -25,      max = -0.1),
    turgor_loss_point                 = list(min = -8,       max = -0.1),
    stem_hydraulic_conductivity       = list(min = 0.0001,   max = 100),
    leaf_specific_hydraulic_conductivity = list(min = 0.00001, max = 10)
  )
}

# ---------------------------------------------------------------------------
# Hydraulic pressure traits that must be negative (MPa).
# Source: Choat et al. 2012 Nature 491:752-755. DOI:10.1038/nature11688.
# ---------------------------------------------------------------------------

dryad_negative_pressure_traits <- function() {
  c("p50", "p88", "turgor_loss_point")
}

# ---------------------------------------------------------------------------
# Unit compatibility patterns per unit class.
# ---------------------------------------------------------------------------

dryad_unit_patterns <- function() {
  list(
    area                 = "(?i)(mm2|cm2|m2|mm\\^2|cm\\^2|mm.2|cm.2|sq|area)",
    ratio                = "(?i)(mm2.per.mg|mg.per.g|g.per.g|m2.per.m2|m.per.g|ratio|fraction|dimensionless|mm2.mg|mg.g)",
    concentration        = "(?i)(mg.per.g|mg.g|percent|pct|%|mmol|mg.kg|g.kg|ug.per.cm2|ug.cm)",
    density              = "(?i)(g.per.cm3|g.cm3|g.cm.3|gcm3|g\\/cm|g\\.cm|specific.gravity|gcm|vessels.per.mm2|vessels.mm)",
    mass                 = "(?i)(mg|g|kg|gram|milligram)",
    length               = "(?i)(mm|cm|m|meter|metre|km|um|micron|micrometer)",
    gas_exchange         = "(?i)(umol|µmol|micromol|mmol)(.*)(m2|m\\^2|m-2)",
    time                 = "(?i)(month|year|day|week)",
    pressure             = "(?i)(mpa|megapascal|bar|kpa|psi)",
    hydraulic_conductivity = "(?i)(kg.*m.*s.*mpa|mmol.*m.*s.*mpa|mol.*m.*s.*mpa|m2.*s.*mpa)"
  )
}

dryad_unit_likely_compatible <- function(unit_str, expected_unit_class) {
  if (is.na(unit_str) || !nzchar(unit_str) || is.na(expected_unit_class)) return(TRUE)
  patterns <- dryad_unit_patterns()
  pattern <- patterns[[expected_unit_class]]
  if (is.null(pattern)) return(TRUE)
  grepl(pattern, unit_str, perl = TRUE)
}

# ---------------------------------------------------------------------------
# PASS 1 — Structural QA
# Checks: numeric parsability, unit class compatibility, species resolution,
#         coordinate geographic bounds, sign check for pressure traits.
# Returns a character vector of P1_ prefixed flags, one entry per row.
# ---------------------------------------------------------------------------

dryad_qa_pass1 <- function(df) {
  flags <- character(nrow(df))
  neg_pressure <- dryad_negative_pressure_traits()

  for (i in seq_len(nrow(df))) {
    row_flags <- character(0)
    trait_nm  <- df$trait_name[[i]]
    val_type  <- df$value_type[[i]]

    # Skip structural numeric checks for categorical traits
    if (!is.na(val_type) && val_type == "categorical") {
      flags[[i]] <- ""
      next
    }

    # 1a. Trait value must parse as numeric
    trait_val_raw <- df$trait_value[[i]]
    num_val <- suppressWarnings(as.numeric(trait_val_raw))
    if (!is.na(trait_val_raw) && nzchar(trait_val_raw) && is.na(num_val)) {
      row_flags <- c(row_flags, "P1_VALUE_NOT_NUMERIC")
    }

    # 1b. Sign check: pressure traits (P50, P88, TLP) must be negative MPa
    if (!is.na(num_val) && !is.na(trait_nm) && trait_nm %in% neg_pressure) {
      if (num_val > 0) {
        row_flags <- c(row_flags,
          sprintf("P1_PRESSURE_SIGN_ERROR[%s must be negative MPa, got %g]", trait_nm, num_val))
      }
    }

    # 1c. Unit vs. expected_unit_class compatibility
    unit_str  <- df$unit[[i]]
    exp_class <- df$expected_unit_class[[i]]
    if (!is.na(unit_str) && nzchar(unit_str) &&
        !is.na(exp_class) && nzchar(exp_class) &&
        !dryad_unit_likely_compatible(unit_str, exp_class)) {
      row_flags <- c(row_flags,
        sprintf("P1_UNIT_MISMATCH[expected:%s,got:%s]", exp_class, unit_str))
    }

    # 1d. Species binomial must be resolved
    if (is.na(df$scrubbed_species_binomial[[i]]) ||
        !nzchar(df$scrubbed_species_binomial[[i]])) {
      row_flags <- c(row_flags, "P1_SPECIES_UNRESOLVED")
    }

    # 1e. Latitude / longitude geographic bounds
    lat <- df$latitude[[i]]
    lon <- df$longitude[[i]]
    if (!is.na(lat) && (lat < -90  || lat > 90))  row_flags <- c(row_flags, "P1_LAT_OUT_OF_RANGE")
    if (!is.na(lon) && (lon < -180 || lon > 180)) row_flags <- c(row_flags, "P1_LON_OUT_OF_RANGE")

    flags[[i]] <- paste(row_flags, collapse = "|")
  }
  flags
}

# ---------------------------------------------------------------------------
# PASS 2 — Biological plausibility QA (independent re-check)
# Checks: cited range bounds for numeric traits, categorical vocabulary
#         validation, Huber value × vessel diameter cross-trait red flag.
# Returns a character vector of P2_ prefixed flags, one entry per row.
# ---------------------------------------------------------------------------

dryad_qa_pass2 <- function(df, ranges = NULL) {
  if (is.null(ranges)) ranges <- dryad_trait_ranges()
  vocab <- dryad_categorical_vocab()
  flags <- character(nrow(df))

  for (i in seq_len(nrow(df))) {
    row_flags <- character(0)
    trait_nm  <- df$trait_name[[i]]
    val_type  <- df$value_type[[i]]

    # --- Categorical traits: vocabulary check ---
    if (!is.na(val_type) && val_type == "categorical") {
      if (!is.na(trait_nm) && !is.null(vocab[[trait_nm]])) {
        raw_val  <- tolower(trimws(df$trait_value[[i]]))
        allowed  <- vocab[[trait_nm]]
        if (!is.na(raw_val) && nzchar(raw_val) && !raw_val %in% allowed) {
          row_flags <- c(row_flags,
            sprintf("P2_CATEGORICAL_VOCAB_MISMATCH[expected one of: %s; got: %s]",
                    paste(allowed, collapse = "/"), raw_val))
        }
      }
      flags[[i]] <- paste(row_flags, collapse = "|")
      next
    }

    # --- Numeric traits: plausibility range check ---
    trait_val_raw <- df$trait_value[[i]]
    num_val <- suppressWarnings(as.numeric(trait_val_raw))

    if (!is.na(num_val) && !is.null(ranges[[trait_nm]])) {
      rng <- ranges[[trait_nm]]
      if (!is.na(rng$min) && !is.na(rng$max)) {
        if (num_val < rng$min || num_val > rng$max) {
          row_flags <- c(row_flags,
            sprintf("P2_VALUE_OUT_OF_RANGE[cited_range:%g_to_%g,got:%g]",
                    rng$min, rng$max, num_val))
        }
      }
    }

    # --- Cross-trait red flag: Huber value implausibly large for a plant ---
    # Huber values > 0.01 m2/m2 are anatomically implausible for most species.
    # Source: Tyree & Ewers 1991 New Phytol 119:345-360. DOI:10.1111/j.1469-8137.1991.tb00035.x
    if (!is.na(trait_nm) && trait_nm == "huber_value" && !is.na(num_val) && num_val > 0.01) {
      row_flags <- c(row_flags,
        "P2_HUBER_VALUE_SUSPECT[>0.01 m2/m2 is anatomically implausible; confirm units are m2/m2 not cm2/m2]")
    }

    flags[[i]] <- paste(row_flags, collapse = "|")
  }
  flags
}

# ---------------------------------------------------------------------------
# Main QA entry point — runs both passes and merges flags into qa_flags column.
# ---------------------------------------------------------------------------

dryad_qa_check <- function(df, ranges = NULL) {
  if (!nrow(df)) return(df)
  pass1 <- dryad_qa_pass1(df)
  pass2 <- dryad_qa_pass2(df, ranges)
  # Merge: non-empty flags from each pass separated by "|"
  merged <- mapply(function(p1, p2) {
    parts <- c(p1, p2)
    parts <- parts[nzchar(parts)]
    paste(parts, collapse = "|")
  }, pass1, pass2, SIMPLIFY = TRUE, USE.NAMES = FALSE)
  df$qa_flags <- merged
  df
}

# ---------------------------------------------------------------------------
# Per-dataset spot check — randomly sample up to n rows, return a
# narrow data frame suitable for appending to spot_check_log.csv.
# Includes qa_flags so human reviewers can see both pass results together.
# ---------------------------------------------------------------------------

dryad_spot_check <- function(df, n = 5L) {
  if (!nrow(df)) return(NULL)
  sample_idx <- sample(seq_len(nrow(df)), min(n, nrow(df)))
  rows <- df[sample_idx, , drop = FALSE]

  keep_cols <- c(
    "dryad_dataset_doi", "dryad_version_id", "dryad_file_id", "source_file_path",
    "original_row_number",
    "scrubbed_species_binomial", "raw_taxon",
    "trait_name", "raw_trait_name",
    "trait_value", "raw_trait_value",
    "unit", "raw_unit",
    "standard_unit", "expected_unit_class",
    "latitude", "longitude", "elevation_m",
    "date_collected",
    "source_column_taxon", "source_column_trait_name",
    "source_column_trait_value", "source_column_unit",
    "qa_flags"
  )
  existing <- intersect(keep_cols, names(rows))
  rows[, existing, drop = FALSE]
}

