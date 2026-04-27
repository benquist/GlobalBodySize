# ============================================================================
# PRIORITIZED DECISION-TREE ALGORITHM FOR TRAIT-UNIT INFERENCE
# ============================================================================
#
# Purpose: Implement robust, traceable unit inference for ambiguous trait values
#          using a prioritized decision-tree approach.
#
# Core principle: "Trust the paper's stated trait name first, then validate with
#                  evidence. If traits are outside bounds of first assumed units,
#                  check various other units. If those are still suspicious, assess
#                  whether the trait is indeed what's stated or its reciprocal."
#
# Reference papers:
#   Kattge et al. 2020, Global Change Biology 26:119-188. https://doi.org/10.1111/gcb.14904
#   Wright et al. 2004, Nature 428:821-827. https://doi.org/10.1038/nature02403
#   Perez-Harguindeguy et al. 2013, Australian Journal of Botany 61:167-234. https://doi.org/10.1071/BT12225
#   Chave et al. 2009, Ecology Letters 12:351-366. https://doi.org/10.1111/j.1461-0248.2009.01285.x
#   Medlyn et al. 2017, New Phytologist 216:10-16. https://doi.org/10.1111/nph.14626
#   Bergmann et al. 2020, Science Advances 6:eaba3756. https://doi.org/10.1126/sciadv.aba3756
# ============================================================================

# ============================================================================
# STEP 1: Get reference range for a trait + unit combination
# ============================================================================
#
# Returns: list(min, max, source_citation) for the specified trait + unit.
# Extracts bounds from trait_dictionary reference ranges based on established
# thresholds from global trait syntheses (Kattge2020, Wright2004, etc.).
#
# @param trait_key canonical trait name (e.g., "specific_leaf_area")
# @param unit canonical unit (e.g., "mm2_per_mg")
# @return list(min, max, source_citation)
iu_get_reference_range <- function(trait_key, unit) {
  # Reference ranges from published trait syntheses with explicit bounds and cites.
  # Format: list(min=numeric, max=numeric, cite=character_vector)

  range_map <- list(
    specific_leaf_area = list(
      # mm2_per_mg and m2_per_kg are IDENTICAL units (1 mm2/mg == 1 m2/kg exactly).
      # Range from Kattge2020 / Wright2004: most plants 1-500, extremes to 1000 m2/kg.
      mm2_per_mg = list(min = 1, max = 1000, cite = c("Kattge2020", "Wright2004")),
      cm2_per_g  = list(min = 0.1, max = 100,  cite = c("Kattge2020", "Wright2004")),
      m2_per_kg  = list(min = 1,   max = 1000, cite = c("Kattge2020", "Wright2004"))
    ),
    leaf_mass_per_area = list(
      mg_per_mm2 = list(min = 0.001, max = 1, cite = c("Kattge2020", "Wright2004")),
      mg_per_cm2 = list(min = 0.01, max = 10, cite = c("Kattge2020", "Wright2004")),
      g_per_m2 = list(min = 1, max = 1000, cite = c("Kattge2020", "Wright2004"))
    ),
    plant_height = list(
      m = list(min = 0.01, max = 150, cite = c("Kattge2020", "Bergmann2020")),
      cm = list(min = 1, max = 15000, cite = c("Kattge2020", "Bergmann2020")),
      mm = list(min = 10, max = 1.5e6, cite = c("Kattge2020", "Bergmann2020"))
    ),
    leaf_dry_matter_content = list(
      mg_per_g = list(min = 50, max = 900, cite = c("PerezHarguindeguy2013", "Kattge2020")),
      g_per_g = list(min = 0.05, max = 0.9, cite = c("PerezHarguindeguy2013", "Kattge2020")),
      percent = list(min = 5, max = 90, cite = c("PerezHarguindeguy2013", "Kattge2020"))
    ),
    wood_density = list(
      g_per_cm3 = list(min = 0.1, max = 1.3, cite = "Chave2009"),
      kg_per_m3 = list(min = 100, max = 1300, cite = "Chave2009")
    ),
    stem_specific_density = list(
      g_per_cm3 = list(min = 0.1, max = 1.3, cite = "Chave2009"),
      kg_per_m3 = list(min = 100, max = 1300, cite = "Chave2009")
    ),
    stomatal_conductance = list(
      mmol_per_m2_per_s = list(min = 10, max = 2000, cite = c("Medlyn2017", "Kattge2020")),
      mol_per_m2_per_s = list(min = 0.01, max = 2, cite = c("Medlyn2017", "Kattge2020"))
    ),
    photosynthetic_rate = list(
      umol_per_m2_per_s = list(min = 0.1, max = 60, cite = c("Kattge2020", "Wright2004")),
      mmol_per_m2_per_s = list(min = 0.0001, max = 0.06, cite = c("Kattge2020", "Wright2004")),
      mol_per_m2_per_s = list(min = 1e-7, max = 6e-5, cite = c("Kattge2020", "Wright2004"))
    ),
    seed_mass = list(
      mg = list(min = 0.001, max = 2.5e7, cite = "Kattge2020"),
      g = list(min = 1e-6, max = 2.5e4, cite = "Kattge2020"),
      kg = list(min = 1e-9, max = 25000, cite = "Kattge2020")
    ),
    leaf_area = list(
      mm2 = list(min = 1, max = 3e6, cite = "Kattge2020"),
      cm2 = list(min = 0.01, max = 3e4, cite = "Kattge2020"),
      m2 = list(min = 1e-6, max = 30, cite = "Kattge2020")
    ),
    leaf_n = list(
      mg_per_g   = list(min = 5,    max = 80,  cite = c("Kattge2020", "Wright2004")),
      mg_per_cm2 = list(min = 0.05, max = 8,   cite = c("Kattge2020", "Wright2004")),
      # 1% = 10 mg/g, so 5-80 mg/g == 0.5-8%
      percent    = list(min = 0.5,  max = 8,   cite = c("Kattge2020", "Wright2004")),
      # g/kg is numerically identical to mg/g
      g_per_kg   = list(min = 5,    max = 80,  cite = c("Kattge2020", "Wright2004"))
    ),
    leaf_p = list(
      mg_per_g   = list(min = 0.5,   max = 10,  cite = c("Kattge2020", "Wright2004")),
      mg_per_cm2 = list(min = 0.005, max = 1,   cite = c("Kattge2020", "Wright2004")),
      # 0.5-10 mg/g == 0.05-1%
      percent    = list(min = 0.05,  max = 1,   cite = c("Kattge2020", "Wright2004")),
      # g/kg numerically identical to mg/g
      g_per_kg   = list(min = 0.5,   max = 10,  cite = c("Kattge2020", "Wright2004"))
    ),
    # --- Solution 2: SRL, RTD, p50/p88 additions ---
    # Perez-Harguindeguy 2013 (doi:10.1071/BT12225); Bergmann 2020 (doi:10.1126/sciadv.aba3756)
    specific_root_length = list(
      m_per_g   = list(min = 0.5,   max = 1500,  cite = c("PerezHarguindeguy2013", "Kattge2020")),
      cm_per_g  = list(min = 50,    max = 150000, cite = c("PerezHarguindeguy2013", "Kattge2020")),
      km_per_kg = list(min = 0.5,   max = 1500,  cite = c("PerezHarguindeguy2013", "Kattge2020"))
    ),
    # Kramer-Walter et al. 2016, New Phytologist 209:1553-1565 (doi:10.1111/nph.13737)
    root_tissue_density = list(
      g_per_cm3  = list(min = 0.05, max = 1.5,   cite = c("KramerWalter2016", "Kattge2020")),
      mg_per_cm3 = list(min = 50,   max = 1500,  cite = c("KramerWalter2016", "Kattge2020")),
      kg_per_m3  = list(min = 50,   max = 1500,  cite = c("KramerWalter2016", "Kattge2020"))
    ),
    # Choat et al. 2012, Nature 491:752-755 (doi:10.1038/nature11688)
    # Maherali et al. 2004, Ecology 85:2361-2380 (doi:10.1890/03-0238)
    # All p50/p88 values expected negative (MPa); bar would be 10x more negative
    p50 = list(
      MPa = list(min = -20, max = -0.1, cite = c("Choat2012", "Maherali2004")),
      bar = list(min = -200, max = -1,  cite = c("Choat2012", "Maherali2004"))
    ),
    p88 = list(
      MPa = list(min = -20, max = -0.1, cite = c("Choat2012", "Maherali2004")),
      bar = list(min = -200, max = -1,  cite = c("Choat2012", "Maherali2004"))
    ),
    # Perez-Harguindeguy et al. 2013 (doi:10.1071/BT12225):
    #   typical 5-40% dry mass in angiosperms, up to ~45% in conifers/grasses.
    #   Herbaceous, aquatic, or young-tissue samples can be below 5% — the DT
    #   minimum is set to 0.1% to accommodate the observed data range without
    #   producing false "low" scores. Values below 0.5% warrant biological review.
    #   mg/g and g/kg are numerically identical; 1% == 10 mg/g.
    leaf_lignin = list(
      percent  = list(min = 0.1,  max = 50,  cite = "PerezHarguindeguy2013"),
      mg_per_g = list(min = 1,    max = 500, cite = "PerezHarguindeguy2013"),
      g_per_kg = list(min = 1,    max = 500, cite = "PerezHarguindeguy2013")
    ),
    # Tyree & Ewers 1991, Ann Bot 67:115-135 (doi:10.1093/oxfordjournals.aob.a088109).
    # Ks (stem-specific hydraulic conductivity, path-length normalised).
    # Range is extremely wide across organ types and species:
    #   angiosperm stems typically 0.1-20 kg m-1 s-1 MPa-1;
    #   outer bounds 0.0001-100 span roots to large-stemmed trees.
    # CAVEAT: upper bound of 100 is rarely exceeded; flag values >50 for review.
    stem_hydraulic_conductivity = list(
      kg_per_m_per_s_per_MPa   = list(min = 1e-4, max = 100,     cite = "TyreeEwers1991"),
      # 1 kg = 1000 g => g range is 1000x larger
      g_per_m_per_s_per_MPa    = list(min = 0.1,  max = 100000,  cite = "TyreeEwers1991"),
      # 1 kg/s = 55556 mmol/s (MW water 18 g/mol)
      mmol_per_m_per_s_per_MPa = list(min = 5.56, max = 5.556e6, cite = "TyreeEwers1991")
    ),
    # Bartlett et al. 2012, PNAS 109:10787-10792 (doi:10.1073/pnas.1204680109).
    # Negative values are biologically expected (water potential).
    # Global range -0.5 to -4.0 MPa; using -5 as outer bound for outlier tolerance.
    turgor_loss_point = list(
      MPa = list(min = -5,  max = -0.3, cite = "Bartlett2012"),
      # 1 MPa = 10 bar => bar range 10x more negative
      bar = list(min = -50, max = -3,   cite = "Bartlett2012")
    ),
    # Kattge2020; Reich et al. 1997, Am Nat 149:369-422 (doi:10.1086/285996).
    # Mass-based C:N ratio is dimensionless; most plants 5-100, median ~20.
    # CAVEAT: extreme outliers (>200) occur in very N-poor soils; cap at 150 for QA.
    leaf_cn_ratio = list(
      dimensionless = list(min = 3,  max = 150, cite = c("Kattge2020", "Reich1997")),
      ratio         = list(min = 3,  max = 150, cite = c("Kattge2020", "Reich1997"))
    )
  )

  trait_ranges <- range_map[[trait_key]]
  if (is.null(trait_ranges)) {
    return(list(min = NA_real_, max = NA_real_, cite = character(0)))
  }

  unit_range <- trait_ranges[[unit]]
  if (is.null(unit_range)) {
    return(list(min = NA_real_, max = NA_real_, cite = character(0)))
  }

  list(min = unit_range$min, max = unit_range$max, cite = unit_range$cite)
}

# ============================================================================
# STEP 2: Get conversion factor between two units
# ============================================================================
#
# Returns: numeric conversion factor from source_unit to target_unit.
# Conversion factors are multiplicative: converted_value = raw_value * factor
#
# @param trait_key canonical trait name
# @param from_unit source unit key
# @param to_unit target unit key
# @return numeric conversion factor (NA if conversion undefined)
iu_get_conversion_factor <- function(trait_key, from_unit, to_unit) {
  if (identical(from_unit, to_unit)) {
    return(1)
  }

  # Conversion matrix: from_unit -> to_unit -> factor
  conversion_map <- list(
    specific_leaf_area = list(
      list(from = "cm2_per_g", to = "mm2_per_mg", factor = 0.1),
      list(from = "m2_per_kg", to = "mm2_per_mg", factor = 1),
      list(from = "mm2_per_mg", to = "cm2_per_g", factor = 10),
      list(from = "m2_per_kg", to = "cm2_per_g", factor = 10)
    ),
    plant_height = list(
      list(from = "cm", to = "m", factor = 0.01),
      list(from = "mm", to = "m", factor = 0.001),
      list(from = "m", to = "cm", factor = 100),
      list(from = "mm", to = "cm", factor = 0.1),
      list(from = "m", to = "mm", factor = 1000),
      list(from = "cm", to = "mm", factor = 10)
    ),
    leaf_dry_matter_content = list(
      list(from = "g_per_g", to = "mg_per_g", factor = 1000),
      list(from = "percent", to = "mg_per_g", factor = 10),
      list(from = "mg_per_g", to = "g_per_g", factor = 0.001),
      list(from = "percent", to = "g_per_g", factor = 0.01),
      list(from = "mg_per_g", to = "percent", factor = 0.1),
      list(from = "g_per_g", to = "percent", factor = 100),
      list(from = "fraction",  to = "g_per_g",  factor = 1),
      list(from = "fraction",  to = "mg_per_g", factor = 1000),
      list(from = "fraction",  to = "percent",  factor = 100),
      list(from = "g_per_g",   to = "fraction", factor = 1),
      list(from = "mg_per_g",  to = "fraction", factor = 0.001),
      list(from = "percent",   to = "fraction", factor = 0.01)
    ),
    wood_density = list(
      list(from = "kg_per_m3", to = "g_per_cm3", factor = 0.001),
      list(from = "g_per_cm3", to = "kg_per_m3", factor = 1000)
    ),
    stem_specific_density = list(
      list(from = "kg_per_m3", to = "g_per_cm3", factor = 0.001),
      list(from = "g_per_cm3", to = "kg_per_m3", factor = 1000)
    ),
    stomatal_conductance = list(
      list(from = "mol_per_m2_per_s", to = "mmol_per_m2_per_s", factor = 1000),
      list(from = "mmol_per_m2_per_s", to = "mol_per_m2_per_s", factor = 0.001)
    ),
    # Solution 2: SRL conversions (km/kg == m/g numerically)
    specific_root_length = list(
      list(from = "cm_per_g",  to = "m_per_g",   factor = 0.01),
      list(from = "km_per_kg", to = "m_per_g",   factor = 1),
      list(from = "m_per_g",   to = "cm_per_g",  factor = 100),
      list(from = "km_per_kg", to = "cm_per_g",  factor = 100),
      list(from = "m_per_g",   to = "km_per_kg", factor = 1),
      list(from = "cm_per_g",  to = "km_per_kg", factor = 0.01)
    ),
    root_tissue_density = list(
      list(from = "mg_per_cm3", to = "g_per_cm3",  factor = 0.001),
      list(from = "kg_per_m3",  to = "g_per_cm3",  factor = 0.001),
      list(from = "g_per_cm3",  to = "mg_per_cm3", factor = 1000),
      list(from = "kg_per_m3",  to = "mg_per_cm3", factor = 1),
      list(from = "g_per_cm3",  to = "kg_per_m3",  factor = 1000),
      list(from = "mg_per_cm3", to = "kg_per_m3",  factor = 1)
    ),
    p50 = list(
      list(from = "bar", to = "MPa", factor = 0.1),
      list(from = "MPa", to = "bar", factor = 10)
    ),
    p88 = list(
      list(from = "bar", to = "MPa", factor = 0.1),
      list(from = "MPa", to = "bar", factor = 10)
    ),
    # leaf_n: 1% = 10 mg/g; g/kg = mg/g numerically
    leaf_n = list(
      list(from = "percent",   to = "mg_per_g", factor = 10),
      list(from = "g_per_kg",  to = "mg_per_g", factor = 1),
      list(from = "mg_per_g",  to = "percent",   factor = 0.1),
      list(from = "g_per_kg",  to = "percent",   factor = 0.1),
      list(from = "mg_per_g",  to = "g_per_kg",  factor = 1),
      list(from = "percent",   to = "g_per_kg",  factor = 10)
    ),
    # leaf_p: same scaling as leaf_n
    leaf_p = list(
      list(from = "percent",   to = "mg_per_g", factor = 10),
      list(from = "g_per_kg",  to = "mg_per_g", factor = 1),
      list(from = "mg_per_g",  to = "percent",   factor = 0.1),
      list(from = "g_per_kg",  to = "percent",   factor = 0.1),
      list(from = "mg_per_g",  to = "g_per_kg",  factor = 1),
      list(from = "percent",   to = "g_per_kg",  factor = 10)
    ),
    # leaf_lignin: 1% = 10 mg/g = 10 g/kg
    leaf_lignin = list(
      list(from = "percent",   to = "mg_per_g", factor = 10),
      list(from = "percent",   to = "g_per_kg", factor = 10),
      list(from = "mg_per_g",  to = "percent",  factor = 0.1),
      list(from = "g_per_kg",  to = "percent",  factor = 0.1),
      list(from = "mg_per_g",  to = "g_per_kg", factor = 1),
      list(from = "g_per_kg",  to = "mg_per_g", factor = 1)
    ),
    # stem_hydraulic_conductivity: kg<->g (×1000); kg<->mmol (×55556, MW water 18 g/mol)
    stem_hydraulic_conductivity = list(
      list(from = "g_per_m_per_s_per_MPa",    to = "kg_per_m_per_s_per_MPa",   factor = 0.001),
      list(from = "mmol_per_m_per_s_per_MPa", to = "kg_per_m_per_s_per_MPa",   factor = 1 / 55555.6),
      list(from = "kg_per_m_per_s_per_MPa",   to = "g_per_m_per_s_per_MPa",    factor = 1000),
      list(from = "mmol_per_m_per_s_per_MPa", to = "g_per_m_per_s_per_MPa",    factor = 1000 / 55555.6),
      list(from = "kg_per_m_per_s_per_MPa",   to = "mmol_per_m_per_s_per_MPa", factor = 55555.6),
      list(from = "g_per_m_per_s_per_MPa",    to = "mmol_per_m_per_s_per_MPa", factor = 55.556)
    ),
    # turgor_loss_point: 1 MPa = 10 bar
    turgor_loss_point = list(
      list(from = "bar", to = "MPa", factor = 0.1),
      list(from = "MPa", to = "bar", factor = 10)
    ),
    # leaf_cn_ratio: dimensionless and ratio are identical
    leaf_cn_ratio = list(
      list(from = "ratio",         to = "dimensionless", factor = 1),
      list(from = "dimensionless", to = "ratio",         factor = 1)
    ),
    photosynthetic_rate = list(
      list(from = "mmol_per_m2_per_s", to = "umol_per_m2_per_s", factor = 1000),
      list(from = "mol_per_m2_per_s", to = "umol_per_m2_per_s", factor = 1e6),
      list(from = "umol_per_m2_per_s", to = "mmol_per_m2_per_s", factor = 0.001),
      list(from = "mol_per_m2_per_s", to = "mmol_per_m2_per_s", factor = 1000),
      list(from = "umol_per_m2_per_s", to = "mol_per_m2_per_s", factor = 1e-6),
      list(from = "mmol_per_m2_per_s", to = "mol_per_m2_per_s", factor = 0.001)
    ),
    seed_mass = list(
      list(from = "g", to = "mg", factor = 1000),
      list(from = "kg", to = "mg", factor = 1e6),
      list(from = "mg", to = "g", factor = 0.001),
      list(from = "kg", to = "g", factor = 1000),
      list(from = "mg", to = "kg", factor = 1e-6),
      list(from = "g", to = "kg", factor = 0.001)
    ),
    leaf_area = list(
      list(from = "cm2", to = "mm2", factor = 100),
      list(from = "m2", to = "mm2", factor = 1e6),
      list(from = "mm2", to = "cm2", factor = 0.01),
      list(from = "m2", to = "cm2", factor = 1e4),
      list(from = "mm2", to = "m2", factor = 1e-6),
      list(from = "cm2", to = "m2", factor = 1e-4)
    )
  )

  trait_convs <- conversion_map[[trait_key]]
  if (is.null(trait_convs)) {
    return(NA_real_)
  }

  for (conv in trait_convs) {
    if (identical(conv$from, from_unit) && identical(conv$to, to_unit)) {
      return(conv$factor)
    }
  }

  NA_real_
}

# ============================================================================
# STEP 3: Test for reciprocal trait keywords in column/unit strings
# ============================================================================
#
# Scans column_name and unit_string for tokens indicating a reciprocal trait
# (e.g., "lma", "leaf_mass_per_area", "mg/mm2" for LMA vs SLA).
#
# @param column_name character string (column header)
# @param unit_string character string (unit specification)
# @return logical TRUE if reciprocal tokens detected
iu_test_reciprocal_tokens <- function(column_name, unit_string) {
  text <- paste(
    tolower(as.character(column_name)),
    tolower(as.character(unit_string)),
    collapse = " "
  )
  text <- tolower(text)

  lma_tokens <- c(
    "lma", "leaf_mass_per_area", "leaf mass per area",
    "mass per area", "mg_mm2", "mg/mm2", "mg_cm2", "mg/cm2",
    "g_m2", "g/m2"
  )

    reciprocal_detected <- any(vapply(lma_tokens, function(p) {
      suppressWarnings(grepl(p, text, fixed = TRUE, ignore.case = TRUE))
    }, logical(1)))

  reciprocal_detected
}

# ============================================================================
# STEP 4: Scan available unit variants for a trait
# ============================================================================
#
# Returns: list of candidate unit keys for the trait (e.g., for SLA:
#         c("mm2_per_mg", "cm2_per_g", "m2_per_kg"))
#
# @param trait_key canonical trait name
# @return character vector of unit variant keys
iu_scan_unit_variants <- function(trait_key) {
  variants_map <- list(
    specific_leaf_area = c("mm2_per_mg", "cm2_per_g", "m2_per_kg"),
    leaf_mass_per_area = c("mg_per_mm2", "mg_per_cm2", "g_per_m2"),
    plant_height = c("m", "cm", "mm"),
    wood_density = c("g_per_cm3", "kg_per_m3"),
    stem_specific_density = c("g_per_cm3", "kg_per_m3"),
    stomatal_conductance = c("mmol_per_m2_per_s", "mol_per_m2_per_s"),
    photosynthetic_rate = c("umol_per_m2_per_s", "mmol_per_m2_per_s", "mol_per_m2_per_s"),
    seed_mass = c("mg", "g", "kg"),
    leaf_area = c("mm2", "cm2", "m2"),
    leaf_n = c("mg_per_g", "mg_per_cm2", "percent", "g_per_kg"),
    leaf_p = c("mg_per_g", "mg_per_cm2", "percent", "g_per_kg"),
    leaf_dry_matter_content = c("mg_per_g", "g_per_g", "percent", "fraction"),
    # Solution 2 additions
    specific_root_length = c("m_per_g", "cm_per_g", "km_per_kg"),
    root_tissue_density  = c("g_per_cm3", "mg_per_cm3", "kg_per_m3"),
    p50 = c("MPa", "bar"),
    p88 = c("MPa", "bar"),
    # Solution 7 additions
    leaf_lignin                 = c("percent", "mg_per_g", "g_per_kg"),
    stem_hydraulic_conductivity = c("kg_per_m_per_s_per_MPa", "g_per_m_per_s_per_MPa", "mmol_per_m_per_s_per_MPa"),
    turgor_loss_point           = c("MPa", "bar"),
    leaf_cn_ratio               = c("dimensionless", "ratio")
  )

  variants <- variants_map[[trait_key]]
  if (is.null(variants)) {
    return(character(0))
  }
  variants
}

# ============================================================================
# STEP 5: Get reciprocal trait mapping
# ============================================================================
#
# For SLA/LMA pairs, return the reciprocal trait key and reference range.
#
# @param trait_key canonical trait name
# @return list(reciprocal_trait, reciprocal_unit) or NULL if no reciprocal
iu_get_reciprocal_trait <- function(trait_key) {
  reciprocal_map <- list(
    specific_leaf_area = list(trait = "leaf_mass_per_area", unit = "mg_per_mm2"),
    leaf_mass_per_area = list(trait = "specific_leaf_area", unit = "mm2_per_mg")
  )

  reciprocal_map[[trait_key]]
}

# ============================================================================
# MAIN DECISION-TREE FUNCTION
# ============================================================================
#
# Prioritized algorithm for trait-unit inference:
#
# STEP 1: Resolve trait_name to canonical key
# STEP 2: Assume canonical unit from trait dictionary
# STEP 3: Parse trait_value to numeric
# STEP 4: Check bounds under assumed canonical unit
# STEP 5: Try unit VARIANTS (same trait, different unit scale)
# STEP 6: Test reciprocal-trait hypothesis (ONLY for SLA↔LMA pair)
#
# @param trait_name stated trait name from column/dataset
# @param values numeric values (raw, not yet converted)
# @param column_name optional column header name
# @param unit_string optional explicit unit specification
# @param source_context optional list(methods_text, dataset_title, journal_name)
#
# @return list(
#   inferred_unit = character,
#   confidence = "high" | "medium" | "low" | "none",
#   evidence = character (e.g., "CANONICAL_UNIT_IN_BOUNDS"),
#   candidate_units = character vector,
#   conversion_factor = numeric,
#   reciprocal = logical,
#   reason = character,
#   citation_keys = character vector
# )
iu_infer_unit_by_decision_tree <- function(
  trait_name,
  values,
  column_name = NA_character_,
  unit_string = NA_character_,
  source_context = NULL
) {
  # ========== STEP 1: Resolve trait_name to canonical key ==========
  canonical_trait_key <- iu_resolve_trait(trait_name)

  result_template <- list(
    inferred_unit = NA_character_,
    confidence = "none",
    evidence = "NO_TRAIT_MATCH",
    candidate_units = character(0),
    conversion_factor = NA_real_,
    reciprocal = FALSE,
    reason = "Trait not recognized for unit inference.",
    citation_keys = character(0)
  )

  if (is.na(canonical_trait_key)) {
    return(result_template)
  }

  # ========== STEP 2: Assume canonical unit ==========
  canonical_unit_map <- list(
    specific_leaf_area = "mm2_per_mg",
    leaf_mass_per_area = "mg_per_mm2",
    plant_height = "m",
    leaf_dry_matter_content = "mg_per_g",
    wood_density = "g_per_cm3",
    stem_specific_density = "g_per_cm3",
    stomatal_conductance = "mmol_per_m2_per_s",
    photosynthetic_rate = "umol_per_m2_per_s",
    seed_mass = "mg",
    leaf_area = "mm2",
    leaf_n = "mg_per_g",
    leaf_p = "mg_per_g",
    # Solution 2 additions
    specific_root_length = "m_per_g",
    root_tissue_density  = "g_per_cm3",
    p50 = "MPa",
    p88 = "MPa",
    # Solution 7 additions
    leaf_lignin                 = "percent",
    stem_hydraulic_conductivity = "kg_per_m_per_s_per_MPa",
    turgor_loss_point           = "MPa",
    leaf_cn_ratio               = "dimensionless"
  )

  # Solution 3: Categorical trait early-exit — no unit to infer
  IU_CATEGORICAL_TRAITS <- c(
    "growth_form", "leaf_phenology", "dispersal_syndrome",
    "leaf_type", "mycorrhizal_type", "woodiness"
  )
  if (canonical_trait_key %in% IU_CATEGORICAL_TRAITS) {
    return(list(
      inferred_unit     = "categorical",
      confidence        = "categorical",
      evidence          = "CATEGORICAL_TRAIT_NO_UNIT",
      candidate_units   = character(0),
      conversion_factor = NA_real_,
      reciprocal        = FALSE,
      reason            = paste0(
        "Trait '", canonical_trait_key, "' is categorical; ",
        "use standardize_categorical_trait() for vocabulary mapping. No unit inference applicable."
      ),
      citation_keys = character(0)
    ))
  }

  assumed_canonical_unit <- canonical_unit_map[[canonical_trait_key]]
  if (is.null(assumed_canonical_unit)) {
    result_template$reason <- "Canonical unit not defined for this trait."
    return(result_template)
  }

  # ========== STEP 3: Parse trait_value to numeric ==========
  numeric_values <- iu_parse_numeric(values)
  numeric_values <- numeric_values[!is.na(numeric_values)]

  if (!length(numeric_values)) {
    result_template$reason <- "No parseable numeric values."
    return(result_template)
  }

  # Get summary statistics (using log scale for most traits)
  use_log <- !(canonical_trait_key %in% IU_NEGATIVE_EXPECTED_TRAITS)
  stats <- iu_value_stats(numeric_values, use_log = use_log)

  # Back-transform median if log scale was used
  median_value <- if (stats$scale == "log") exp(stats$q50) else stats$q50
  if (is.na(median_value)) {
    result_template$reason <- "Cannot compute median from values."
    return(result_template)
  }

  # ========== STEP 4: Check bounds under assumed canonical unit ==========
  canonical_range <- iu_get_reference_range(canonical_trait_key, assumed_canonical_unit)

  if (!is.na(canonical_range$min) && !is.na(canonical_range$max)) {
    in_canonical_bounds <- (median_value >= canonical_range$min &&
                           median_value <= canonical_range$max)

    if (in_canonical_bounds) {
      # ===== RECIPROCAL PRE-CHECK =====
      # Before accepting HIGH confidence, verify that column/unit tokens do NOT
      # strongly indicate the reciprocal trait (e.g. "LMA" column labelled as SLA).
      # Only relevant for the SLA<->LMA reciprocal pair.
      if (canonical_trait_key %in% c("specific_leaf_area", "leaf_mass_per_area")) {
        has_reciprocal_evidence <- iu_test_reciprocal_tokens(column_name, unit_string)
        if (has_reciprocal_evidence) {
          reciprocal_info_early <- iu_get_reciprocal_trait(canonical_trait_key)
          if (!is.null(reciprocal_info_early)) {
            reciprocal_value_early <- 1 / median_value
            reciprocal_range_early <- iu_get_reference_range(
              reciprocal_info_early$trait, reciprocal_info_early$unit
            )
            recip_in_bounds_early <- (
              !is.na(reciprocal_range_early$min) &&
              !is.na(reciprocal_range_early$max) &&
              reciprocal_value_early >= reciprocal_range_early$min &&
              reciprocal_value_early <= reciprocal_range_early$max
            )
            if (recip_in_bounds_early) {
              return(list(
                inferred_unit    = reciprocal_info_early$unit,
                confidence       = "medium",
                evidence         = "RECIPROCAL_TRAIT_DETECTED",
                candidate_units  = iu_scan_unit_variants(reciprocal_info_early$trait),
                conversion_factor = NA_real_,  # reciprocal: multiplicative factor undefined
                reciprocal       = TRUE,
                reason = sprintf(
                  "Column/unit tokens suggest %s (not %s); reciprocal value %.4g in range [%.4g, %.4g]; canonical value %.4g also in canonical range [%.4g, %.4g] — reciprocal evidence takes precedence.",
                  reciprocal_info_early$trait, canonical_trait_key,
                  reciprocal_value_early,
                  reciprocal_range_early$min, reciprocal_range_early$max,
                  median_value, canonical_range$min, canonical_range$max
                ),
                citation_keys = unique(c(canonical_range$cite, reciprocal_range_early$cite))
              ))
            }
          }
        }
      }
      # ===== END RECIPROCAL PRE-CHECK =====
      return(list(
        inferred_unit = assumed_canonical_unit,
        confidence = "high",
        evidence = "CANONICAL_UNIT_IN_BOUNDS",
        candidate_units = iu_scan_unit_variants(canonical_trait_key),
        conversion_factor = 1,
        reciprocal = FALSE,
        reason = sprintf(
          "Median value %.4g in canonical unit %s range [%.4g, %.4g].",
          median_value, assumed_canonical_unit,
          canonical_range$min, canonical_range$max
        ),
        citation_keys = canonical_range$cite
      ))
    }
  }

  # ========== STEP 5: Try unit VARIANTS (same trait, different unit scale) ==========
  #
  # Correct inference direction: ask "does the raw value fall directly within the
  # biologically expected range for each candidate unit?"
  #
  # For each candidate unit C:
  #   If median_value ∈ C's reference range → raw data is plausibly in unit C.
  #   Report conversion_factor = C→canonical so downstream code can normalize.
  #
  # This is more robust than computing canonical→C first (which fails when values
  # are at biological extremes and the ranges are not strictly proportional), and
  # naturally excludes units that lack a conversion path to canonical (e.g.,
  # mg_per_cm2 for leaf N, which requires LMA to bridge mass and area bases).
  unit_variants <- iu_scan_unit_variants(canonical_trait_key)
  variant_matches <- character(0)
  variant_factors <- numeric(0)

  for (candidate_unit in unit_variants) {
    if (identical(candidate_unit, assumed_canonical_unit)) {
      next
    }

    # Only consider candidates with a defined C→canonical conversion factor;
    # this implicitly excludes incompatible bases (e.g., area-based vs mass-based).
    reverse_factor <- iu_get_conversion_factor(canonical_trait_key, candidate_unit, assumed_canonical_unit)
    if (is.na(reverse_factor)) {
      next
    }

    candidate_range <- iu_get_reference_range(canonical_trait_key, candidate_unit)
    if (!is.na(candidate_range$min) && !is.na(candidate_range$max)) {
      if (median_value >= candidate_range$min &&
          median_value <= candidate_range$max) {
        variant_matches <- c(variant_matches, candidate_unit)
        variant_factors <- c(variant_factors, reverse_factor)  # C→canonical, for normalization
      }
    }
  }

  # Exactly one variant matches → high confidence with inferred unit
  if (length(variant_matches) == 1) {
    return(list(
      inferred_unit = assumed_canonical_unit,  # normalize to canonical unit
      confidence = "high",
      evidence = "UNIT_VARIANT_FOUND",
      candidate_units = unit_variants,
      conversion_factor = variant_factors[[1]],  # apply to raw values to get canonical
      reciprocal = FALSE,
      reason = sprintf(
        "Median value %.4g in range for unit %s; conversion factor %.4g to %s.",
        median_value, variant_matches[[1]], variant_factors[[1]], assumed_canonical_unit
      ),
      citation_keys = iu_get_reference_range(canonical_trait_key, variant_matches[[1]])$cite
    ))
  }

  # Multiple variants plausible → medium confidence, ambiguous
  if (length(variant_matches) > 1) {
    return(list(
      inferred_unit = assumed_canonical_unit,
      confidence = "medium",
      evidence = "AMBIGUOUS_UNIT_SCALE",
      candidate_units = c(assumed_canonical_unit, variant_matches),
      conversion_factor = NA_real_,
      reciprocal = FALSE,
      reason = sprintf(
        "Median value %.4g plausible under multiple unit scales: %s.",
        median_value, paste(c(assumed_canonical_unit, variant_matches), collapse = ", ")
      ),
      citation_keys = unique(unlist(lapply(c(assumed_canonical_unit, variant_matches), function(u) {
        iu_get_reference_range(canonical_trait_key, u)$cite
      })))
    ))
  }

  # No variant matches canonical → proceed to STEP 6 (reciprocal test)

  # ========== STEP 6: Test reciprocal-trait hypothesis ==========
  # Only for SLA↔LMA pair
  if (!(canonical_trait_key %in% c("specific_leaf_area", "leaf_mass_per_area"))) {
    return(list(
      inferred_unit = NA_character_,
      confidence = "low",
      evidence = "OUT_OF_BOUNDS_NO_RECIPROCAL_PAIR",
      candidate_units = unit_variants,
      conversion_factor = NA_real_,
      reciprocal = FALSE,
      reason = sprintf(
        "Median value %.4g out of bounds for canonical unit %s, and no reciprocal pair defined.",
        median_value, assumed_canonical_unit
      ),
      citation_keys = iu_get_reference_range(canonical_trait_key, assumed_canonical_unit)$cite
    ))
  }

  reciprocal_info <- iu_get_reciprocal_trait(canonical_trait_key)
  if (is.null(reciprocal_info)) {
    return(list(
      inferred_unit = NA_character_,
      confidence = "low",
      evidence = "OUT_OF_BOUNDS_NO_RECIPROCAL_PAIR",
      candidate_units = unit_variants,
      conversion_factor = NA_real_,
      reciprocal = FALSE,
      reason = sprintf("Median value %.4g out of bounds; reciprocal mapping not found.", median_value),
      citation_keys = iu_get_reference_range(canonical_trait_key, assumed_canonical_unit)$cite
    ))
  }

  # Compute reciprocal and check bounds
  reciprocal_value <- 1 / median_value
  reciprocal_range <- iu_get_reference_range(reciprocal_info$trait, reciprocal_info$unit)
  reciprocal_in_bounds <- (!is.na(reciprocal_range$min) && !is.na(reciprocal_range$max) &&
                           reciprocal_value >= reciprocal_range$min &&
                           reciprocal_value <= reciprocal_range$max)

  # Check for reciprocal evidence in column/unit tokens
  has_reciprocal_evidence <- iu_test_reciprocal_tokens(column_name, unit_string)

  # Decision logic:
  if (reciprocal_in_bounds && has_reciprocal_evidence) {
    return(list(
      inferred_unit = reciprocal_info$unit,
      confidence = "medium",
      evidence = "RECIPROCAL_TRAIT_DETECTED",
      candidate_units = iu_scan_unit_variants(reciprocal_info$trait),
      conversion_factor = NA_real_,  # reciprocal: multiplicative factor undefined
      reciprocal = TRUE,
      reason = sprintf(
        "Column/unit tokens suggest %s (not %s); reciprocal value %.4g in range [%.4g, %.4g].",
        reciprocal_info$trait, canonical_trait_key,
        reciprocal_value, reciprocal_range$min, reciprocal_range$max
      ),
      citation_keys = reciprocal_range$cite
    ))
  }

  if (reciprocal_in_bounds && !has_reciprocal_evidence) {
    return(list(
      inferred_unit = NA_character_,
      confidence = "low",
      evidence = "RECIPROCAL_POSSIBLE_VALUE_MATCH_ONLY",
      candidate_units = c(unit_variants, iu_scan_unit_variants(reciprocal_info$trait)),
      conversion_factor = NA_real_,
      reciprocal = NA,
      reason = sprintf(
        "Median value %.4g matches reciprocal %s (value range), but column name suggests %s; ambiguous interpretation.",
        median_value, reciprocal_info$trait, canonical_trait_key
      ),
      citation_keys = unique(c(
        iu_get_reference_range(canonical_trait_key, assumed_canonical_unit)$cite,
        reciprocal_range$cite
      ))
    ))
  }

  # Neither canonical nor reciprocal fits
  return(list(
    inferred_unit = NA_character_,
    confidence = "low",
    evidence = "OUT_OF_BOUNDS_RECIPROCAL_ALSO_FAILS",
    candidate_units = c(unit_variants, iu_scan_unit_variants(reciprocal_info$trait)),
    conversion_factor = NA_real_,
    reciprocal = FALSE,
    reason = sprintf(
      "Median value %.4g fails bounds check for both %s (canonical) and %s (reciprocal).",
      median_value, canonical_trait_key, reciprocal_info$trait
    ),
    citation_keys = unique(c(
      iu_get_reference_range(canonical_trait_key, assumed_canonical_unit)$cite,
      reciprocal_range$cite
    ))
  ))
}

# ============================================================================
# TEST CASES FOR VALIDATION
# ============================================================================

# Test function: validate decision-tree output against expected results
iu_test_decision_tree <- function(verbose = FALSE) {
  test_results <- list()

  # TEST 1: SLA median 5 mm²/mg → high confidence, canonical unit
  test1 <- iu_infer_unit_by_decision_tree(
    trait_name = "specific leaf area",
    values = c(3, 4, 5, 6, 7),
    column_name = "SLA",
    unit_string = "mm2/mg"
  )
  test_results$test1 <- list(
    expected_confidence = "high",
    actual_confidence = test1$confidence,
    expected_evidence = "CANONICAL_UNIT_IN_BOUNDS",
    actual_evidence = test1$evidence,
    pass = (test1$confidence == "high" && test1$evidence == "CANONICAL_UNIT_IN_BOUNDS")
  )

  # TEST 2: SLA values clearly within canonical mm2/mg range → high confidence.
  # Values 40-60 mm2/mg are textbook mesophyte SLA (Kattge2020 median ~12, range to 500).
  # No reciprocal token in column name, so canonical HIGH is correct.
  test2 <- iu_infer_unit_by_decision_tree(
    trait_name = "SLA",
    values = c(40, 50, 60),
    column_name = "SLA_ambiguous"
  )
  test_results$test2 <- list(
    expected_confidence = "high",
    actual_confidence = test2$confidence,
    expected_evidence = "CANONICAL_UNIT_IN_BOUNDS",
    actual_evidence = test2$evidence,
    pass = (test2$confidence == "high" && test2$evidence == "CANONICAL_UNIT_IN_BOUNDS")
  )

  # TEST 3: SLA values out of canonical mm2/mg range [1,1000]; median 0.15.
  # Step 5 finds exactly one variant: cm2/g (0.15 * 10 = 1.5 in [0.1,100]).
  # m2/kg is the SAME unit as mm2/mg, so its converted value 0.15 also fails [1,1000].
  # No reciprocal token → returns HIGH with UNIT_VARIANT_FOUND (actual unit is cm2/g).
  test3 <- iu_infer_unit_by_decision_tree(
    trait_name = "SLA",
    values = c(0.1, 0.15, 0.2),
    column_name = "SLA_column"
  )
  test_results$test3 <- list(
    expected_confidence = "high",
    actual_confidence = test3$confidence,
    expected_evidence = "UNIT_VARIANT_FOUND",
    actual_evidence = test3$evidence,
    pass = (test3$confidence == "high" && test3$evidence == "UNIT_VARIANT_FOUND")
  )

  # TEST 4: LMA masquerading as SLA: values indicate reciprocal relationship
  # Values around 0.5-2 (plausible mg/mm² for LMA) with LMA keyword in column
  test4 <- iu_infer_unit_by_decision_tree(
    trait_name = "SLA",
    values = c(0.5, 1.0, 1.5),
    column_name = "LMA_mg_mm2"
  )
  test_results$test4 <- list(
    expected_confidence = "medium",
    actual_confidence = test4$confidence,
    expected_reciprocal = TRUE,
    actual_reciprocal = test4$reciprocal,
    pass = (test4$confidence == "medium" && test4$reciprocal == TRUE)
  )

  # TEST 5: Out-of-bounds: values 1e6 mm²/mg → low confidence
  test5 <- iu_infer_unit_by_decision_tree(
    trait_name = "SLA",
    values = c(900000, 1000000, 1100000)
  )
  test_results$test5 <- list(
    expected_confidence = "low",
    actual_confidence = test5$confidence,
    expected_evidence = "OUT_OF_BOUNDS_RECIPROCAL_ALSO_FAILS",
    actual_evidence = test5$evidence,
    pass = (test5$confidence == "low" && 
            test5$evidence %in% c("OUT_OF_BOUNDS_RECIPROCAL_ALSO_FAILS", "OUT_OF_BOUNDS_NO_RECIPROCAL_PAIR"))
  )

  if (verbose) {
    cat("\n=== DECISION-TREE TEST RESULTS ===\n")
    for (test_name in names(test_results)) {
      test_result <- test_results[[test_name]]
      status <- if (test_result$pass) "PASS" else "FAIL"
      cat(sprintf("\n%s: %s\n", test_name, status))
      cat(sprintf("  Expected confidence: %s\n", paste(test_result$expected_confidence, collapse=" or ")))
      cat(sprintf("  Actual confidence:   %s\n", test_result$actual_confidence))
      if (!is.null(test_result$expected_evidence) && !is.na(test_result$expected_evidence)) {
        cat(sprintf("  Expected evidence:   %s\n", test_result$expected_evidence))
        cat(sprintf("  Actual evidence:     %s\n", test_result$actual_evidence))
      }
      if (!is.null(test_result$expected_reciprocal) && length(test_result$expected_reciprocal) > 0 && !is.na(test_result$expected_reciprocal)) {
        cat(sprintf("  Expected reciprocal: %s\n", test_result$expected_reciprocal))
        cat(sprintf("  Actual reciprocal:   %s\n", test_result$actual_reciprocal))
      }
    }

    total_pass <- sum(sapply(test_results, function(r) r$pass))
    cat(sprintf("\n=== SUMMARY: %d/%d tests passed ===\n", total_pass, length(test_results)))
  }

  # --- leaf_n: 20 mg/g -> canonical mg_per_g, HIGH ---
  res <- iu_infer_unit_by_decision_tree("leaf nitrogen", c(18, 22, 25), unit_string = "mg/g")
  stopifnot(res$confidence == "high")
  stopifnot(res$inferred_unit == "mg_per_g")
  if (verbose) message("leaf_n HIGH: PASS")

  # --- leaf_n: 2.0 % -> in percent range (0.5-8%) -> HIGH ---
  res <- iu_infer_unit_by_decision_tree("leaf nitrogen", c(1.8, 2.0, 2.5))
  stopifnot(res$confidence == "high")
  if (verbose) message("leaf_n percent HIGH: PASS")

  # --- leaf_p: 1.5 mg/g -> HIGH ---
  res <- iu_infer_unit_by_decision_tree("leaf phosphorus", c(1.2, 1.5, 1.8))
  stopifnot(res$confidence == "high")
  if (verbose) message("leaf_p HIGH: PASS")

  # --- leaf_lignin: 20 % -> HIGH ---
  res <- iu_infer_unit_by_decision_tree("leaf lignin", c(15, 20, 25))
  stopifnot(res$confidence == "high")
  if (verbose) message("leaf_lignin HIGH: PASS")

  # --- leaf_cn_ratio: 25 -> dimensionless, HIGH ---
  res <- iu_infer_unit_by_decision_tree("leaf C:N ratio", c(20, 25, 30))
  stopifnot(res$confidence == "high")
  stopifnot(res$inferred_unit == "dimensionless")
  if (verbose) message("leaf_cn_ratio HIGH: PASS")

  # --- stem_hydraulic_conductivity: 2.5 kg/m/s/MPa -> HIGH ---
  res <- iu_infer_unit_by_decision_tree("stem hydraulic conductivity", c(1.5, 2.5, 5.0))
  stopifnot(res$confidence == "high")
  if (verbose) message("stem_hydraulic_conductivity HIGH: PASS")

  # --- turgor_loss_point: -1.5 MPa -> HIGH (negative value) ---
  res <- iu_infer_unit_by_decision_tree("turgor loss point", c(-2.0, -1.5, -1.0))
  stopifnot(res$confidence == "high")
  stopifnot(res$inferred_unit == "MPa")
  if (verbose) message("turgor_loss_point HIGH: PASS")

  # --- leaf_dry_matter_content: fraction input 0.25 -> mg_per_g via conversion ---
  res <- iu_infer_unit_by_decision_tree("leaf dry matter content", c(0.2, 0.25, 0.3))
  # 0.25 falls in g_per_g range [0.05, 0.9] -> UNIT_VARIANT_FOUND, converts to mg_per_g
  stopifnot(res$confidence == "high")
  if (verbose) message("LDMC fraction HIGH: PASS")

  # --- leaf_dry_matter_content: normal mg/g input 250 -> HIGH ---
  res <- iu_infer_unit_by_decision_tree("leaf dry matter content", c(200, 250, 300))
  stopifnot(res$confidence == "high")
  stopifnot(res$inferred_unit == "mg_per_g")
  if (verbose) message("LDMC mg_per_g HIGH: PASS")

  invisible(test_results)
}
