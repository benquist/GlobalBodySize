# Controlled warning strings
UNIT_INFERRED_FROM_COLUMN_NAME <- "UNIT_INFERRED_FROM_COLUMN_NAME"
UNIT_INFERRED_FROM_VALUE_DISTRIBUTION <- "UNIT_INFERRED_FROM_VALUE_DISTRIBUTION"
UNIT_INFERRED_FROM_SOURCE_CONTEXT <- "UNIT_INFERRED_FROM_SOURCE_CONTEXT"
BASIS_AMBIGUOUS_AREA_VS_MASS <- "BASIS_AMBIGUOUS_AREA_VS_MASS"
UNIT_INFERENCE_LOW_POSTERIOR <- "UNIT_INFERENCE_LOW_POSTERIOR"
DATASET_LEVEL_UNIT_LOCK_APPLIED <- "DATASET_LEVEL_UNIT_LOCK_APPLIED"
RECORD_CONFLICTS_WITH_DATASET_LOCK <- "RECORD_CONFLICTS_WITH_DATASET_LOCK"
DATASET_COHERENCE_FAIL <- "DATASET_COHERENCE_FAIL"

# Trait classes expected to have negative values on the raw scale.
IU_NEGATIVE_EXPECTED_TRAITS <- c(
  "p50", "p88", "turgor_loss_point", "water_potential", "leaf_osmotic_potential"
)

# Traits where area-vs-mass basis is a critical interpretation issue.
IU_BASIS_CRITICAL_TRAITS <- c(
  # leaf_n, leaf_p: routinely reported both per area and per dry mass.
  # photosynthetic_rate (Anet): some papers report per mass basis.
  # stomatal_conductance (gs): excluded — virtually universal convention is per unit projected
  # leaf area (m-2); any exception would be explicitly stated in methods. The bio-units-specialist
  # makes this call; if gs is seen per mass in source context it should be caught by iu_basis_from_tokens.
  "leaf_n", "leaf_p", "photosynthetic_rate"
)

# Alias map used by trait-name and column-name matching.
iu_trait_aliases <- function() {
  list(
    specific_leaf_area = c("specific_leaf_area", "specific leaf area", "sla"),
    plant_height = c("plant_height", "plant height", "height", "max height", "canopy height"),
    leaf_dry_matter_content = c("leaf_dry_matter_content", "leaf dry matter content", "ldmc"),
    wood_density = c("wood_density", "wood density", "wood specific gravity"),
    stem_specific_density = c("stem_specific_density", "stem specific density", "ssd"),
    stomatal_conductance = c("stomatal_conductance", "gs", "stomatal conductance"),
    photosynthetic_rate = c("photosynthetic_rate", "anet", "amax", "asat", "net photosynthesis", "assimilation"),
    seed_mass = c("seed_mass", "seed mass", "seed weight"),
    leaf_area = c("leaf_area", "leaf area", "lamina area"),
    leaf_n = c("leaf_n", "leaf nitrogen", "leaf nitrogen content", "foliar n", "nmass", "narea"),
    leaf_p = c("leaf_p", "leaf phosphorus", "foliar p", "pmass", "parea"),
    leaf_cn_ratio = c("leaf_cn_ratio", "leaf cn ratio", "c:n", "cn ratio",
                      "leaf C:N ratio", "leaf_cn", "leaf_c_n_ratio", "C_N_ratio",
                      "leaf carbon nitrogen ratio", "cn"),
    leaf_cp_ratio = c("leaf_cp_ratio", "leaf cp ratio", "c:p", "cp ratio"),
    leaf_lignin = c("leaf_lignin", "leaf lignin", "lignin",
                    "lignin content", "Lign", "acid detergent lignin",
                    "Klason lignin", "leaf_lignin_content"),
    growth_form = c("growth_form", "growth form", "life form", "habit"),
    leaf_phenology = c("leaf_phenology", "leaf phenology", "leaf habit", "deciduousness"),
    p50 = c("p50", "psi50"),
    p88 = c("p88", "psi88"),
    turgor_loss_point = c("turgor_loss_point", "turgor loss point", "TLP", "tlp",
                          "psi_tlp", "osmotic potential at full turgor",
                          "leaf wilting point", "turgor_loss"),
    stem_hydraulic_conductivity = c("stem_hydraulic_conductivity",
                                    "stem hydraulic conductivity",
                                    "xylem hydraulic conductivity",
                                    "Ks", "kS", "ks", "stem_ks",
                                    "Kh_specific", "hydraulic conductivity",
                                    "specific hydraulic conductivity"),
    # Solution 2: root traits
    specific_root_length = c("specific_root_length", "specific root length", "srl"),
    root_tissue_density  = c("root_tissue_density",  "root tissue density",  "rtd", "root density")
  )
}

iu_norm <- function(x) {
  y <- tolower(trimws(as.character(x)))
  y <- gsub("[^a-z0-9]+", "_", y)
  gsub("(^_+|_+$)", "", y)
}

iu_resolve_trait <- function(trait_name) {
  key <- iu_norm(trait_name)
  aliases <- iu_trait_aliases()
  trait_keys <- names(aliases)
  for (k in trait_keys) {
    if (key %in% iu_norm(aliases[[k]])) {
      return(k)
    }
  }
  NA_character_
}

# Parse text to numeric robustly; non-parseable values become NA.
iu_parse_numeric <- function(x) {
  if (is.numeric(x)) {
    return(as.numeric(x))
  }
  if (is.factor(x)) {
    x <- as.character(x)
  }
  x <- as.character(x)
  x <- trimws(x)
  x[x == ""] <- NA_character_
  x <- gsub(",", "", x, fixed = TRUE)
  # Keep scientific notation and signed decimals only.
  x <- gsub("[^0-9eE+.-]", "", x)
  suppressWarnings(as.numeric(x))
}

# Compute q5, q50, q95 on log(x) by default for x > 0.
# For traits expected to be negative (e.g., water potential / TLP / P50 / P88),
# callers pass use_log = FALSE to use raw quantiles.
iu_value_stats <- function(x, use_log = TRUE) {
  x <- iu_parse_numeric(x)
  x <- x[!is.na(x)]
  if (!length(x)) {
    return(list(q5 = NA_real_, q50 = NA_real_, q95 = NA_real_, n = 0L, scale = if (use_log) "log" else "raw"))
  }

  if (use_log) {
    x <- x[x > 0]
    if (!length(x)) {
      return(list(q5 = NA_real_, q50 = NA_real_, q95 = NA_real_, n = 0L, scale = "log"))
    }
    lx <- log(x)
    q <- as.numeric(stats::quantile(lx, probs = c(0.05, 0.5, 0.95), na.rm = TRUE, names = FALSE, type = 7))
    return(list(q5 = q[[1]], q50 = q[[2]], q95 = q[[3]], n = length(lx), scale = "log"))
  }

  q <- as.numeric(stats::quantile(x, probs = c(0.05, 0.5, 0.95), na.rm = TRUE, names = FALSE, type = 7))
  list(q5 = q[[1]], q50 = q[[2]], q95 = q[[3]], n = length(x), scale = "raw")
}

# Return matched column-name aliases for this trait, or NULL.
iu_column_name_match <- function(column_names, trait_name) {
  trait_key <- iu_resolve_trait(trait_name)
  if (is.na(trait_key)) {
    return(NULL)
  }

  cn <- unique(iu_norm(column_names))
  cn <- cn[!is.na(cn) & nzchar(cn)]
  aliases <- iu_norm(iu_trait_aliases()[[trait_key]])

  matched <- character(0)
  for (name_i in cn) {
    hit <- FALSE
    for (alias_i in aliases) {
      if (identical(name_i, alias_i) || grepl(alias_i, name_i, fixed = TRUE)) {
        hit <- TRUE
        break
      }
    }
    if (hit) {
      matched <- c(matched, name_i)
    }
  }

  if (!length(matched)) NULL else as.list(unique(matched))
}

# Infer basis type from column tokens and methods text for basis-critical traits.
iu_basis_from_tokens <- function(column_names, methods_text) {
  text <- c(column_names, methods_text)
  text <- paste(text[!is.na(text)], collapse = " ")
  text <- tolower(text)

  area_patterns <- c(
    "narea", "parea", "area basis", "area-based", "per unit leaf area",
    "per leaf area", "per m2", "per m\\^2", "m-2", "cm2", "cm\\^2", "mm2", "mm\\^2"
  )
  mass_patterns <- c(
    "nmass", "pmass", "mass basis", "mass-based", "dry mass basis",
    "per mass", "per dry mass", "per g", "g-1", "mg g", "mg/g"
  )

  area_hit <- any(vapply(area_patterns, function(p) grepl(p, text, perl = TRUE), logical(1)))
  mass_hit <- any(vapply(mass_patterns, function(p) grepl(p, text, perl = TRUE), logical(1)))

  if (area_hit && !mass_hit) {
    return("area")
  }
  if (mass_hit && !area_hit) {
    return("mass")
  }
  "unknown"
}

iu_join_unique <- function(x) {
  x <- x[!is.na(x) & nzchar(x)]
  paste(unique(x), collapse = ",")
}

iu_add_evidence <- function(existing, additions) {
  x <- c(existing, additions)
  x <- x[!is.na(x) & nzchar(x)]
  unique(x)
}

iu_add_citation <- function(existing, additions) {
  x <- c(existing, additions)
  x <- x[!is.na(x) & nzchar(x)]
  unique(x)
}

iu_detect_explicit_unit <- function(text, trait_key) {
  if (is.na(trait_key) || !nzchar(trait_key)) {
    return(NA_character_)
  }
  if (is.na(text) || !nzchar(trimws(text))) {
    return(NA_character_)
  }
  txt <- tolower(text)

  if (trait_key == "specific_leaf_area") {
     if (grepl("mm2[_/\\s]*mg|mm\\^2[_/\\s]*mg|mm2_per_mg", txt, perl = TRUE)) return("mm2_per_mg")
     if (grepl("cm2[_/\\s]*g|cm\\^2[_/\\s]*g|cm2_per_g", txt, perl = TRUE)) return("cm2_per_g")
     if (grepl("m2[_/\\s]*kg|m\\^2[_/\\s]*kg|m2_per_kg", txt, perl = TRUE)) return("m2_per_kg")
  }

  if (trait_key == "plant_height") {
    if (grepl("\\bmm\\b", txt)) return("mm")
    if (grepl("\\bcm\\b", txt)) return("cm")
    if (grepl("\\bm\\b|meter|metre", txt)) return("m")
  }

  if (trait_key == "leaf_dry_matter_content") {
     if (grepl("mg[_/\\s]*g|mg_per_g", txt, perl = TRUE)) return("mg_per_g")
     if (grepl("g[_/\\s]*g|g_per_g", txt, perl = TRUE)) return("g_per_g")
    if (grepl("%|percent", txt)) return("percent")
  }

  if (trait_key %in% c("wood_density", "stem_specific_density")) {
     if (grepl("g[_/\\s]*cm3|g[_/\\s]*cm\\^3|g_per_cm3", txt, perl = TRUE)) return("g_per_cm3")
     if (grepl("kg[_/\\s]*m3|kg[_/\\s]*m\\^3|kg_per_m3", txt, perl = TRUE)) return("kg_per_m3")
  }

  if (trait_key == "stomatal_conductance") {
    if (grepl("mmol", txt)) return("mmol_per_m2_per_s")
    if (grepl("\\bmol\\b", txt)) return("mol_per_m2_per_s")
  }

  if (trait_key == "photosynthetic_rate") {
    if (grepl("umol", txt)) return("umol_per_m2_per_s")
    if (grepl("mmol", txt)) return("mmol_per_m2_per_s")
    if (grepl("\\bmol\\b", txt)) return("mol_per_m2_per_s")
  }

  if (trait_key == "seed_mass") {
    if (grepl("\\bmg\\b", txt)) return("mg")
    if (grepl("\\bg\\b", txt)) return("g")
    if (grepl("\\bkg\\b", txt)) return("kg")
  }

  if (trait_key == "leaf_area") {
    if (grepl("mm2|mm\\^2", txt)) return("mm2")
    if (grepl("cm2|cm\\^2", txt)) return("cm2")
    if (grepl("m2|m\\^2", txt)) return("m2")
  }

  if (trait_key == "leaf_lignin") {
    if (grepl("%|percent", txt)) return("percent")
      if (grepl("mg[_/\\s]*g|mg_per_g", txt, perl = TRUE)) return("mg_per_g")
      if (grepl("g[_/\\s]*g|g_per_g", txt, perl = TRUE)) return("fraction")
  }

  NA_character_
}

infer_units_for_dataset <- function(trait_name, values, column_names, source_context) {
  trait_key <- iu_resolve_trait(trait_name)

  result <- list(
    inferred_unit = NA_character_,
    confidence = "none",
    evidence = "",
    citation_keys = "",
    basis_type = NA_character_,
    conversion_factor = NA_real_,
    candidate_units = "",
    notes = "Trait not recognized for unit inference."
  )

  if (is.na(trait_key)) {
    return(result)
  }

  if (trait_key %in% c("growth_form", "leaf_phenology")) {
    result$inferred_unit <- "categorical"
    result$confidence <- "high"
    result$evidence <- ""
    result$citation_keys <- ""
    result$basis_type <- NA_character_
    result$conversion_factor <- 1
    result$candidate_units <- "categorical"
    result$notes <- "Categorical trait; no numeric unit conversion required."
    return(result)
  }

  methods_text <- NA_character_
  dataset_title <- NA_character_
  journal_name <- NA_character_
  if (is.list(source_context)) {
    if (!is.null(source_context$methods_text)) methods_text <- source_context$methods_text
    if (!is.null(source_context$dataset_title)) dataset_title <- source_context$dataset_title
    if (!is.null(source_context$journal_name)) journal_name <- source_context$journal_name
  }

  use_log <- !(trait_key %in% IU_NEGATIVE_EXPECTED_TRAITS)
  stats <- iu_value_stats(values, use_log = use_log)
  q50_raw <- if (!is.na(stats$q50) && stats$scale == "log") exp(stats$q50) else stats$q50

  evidence <- character(0)
  cites <- character(0)

  matched_columns <- iu_column_name_match(column_names, trait_name)
  if (!is.null(matched_columns)) {
    evidence <- iu_add_evidence(evidence, UNIT_INFERRED_FROM_COLUMN_NAME)
  }

  context_blob <- paste(c(dataset_title, journal_name, methods_text), collapse = " ")
  context_blob <- tolower(context_blob)
  if (nzchar(trimws(context_blob))) {
    if (grepl("unit|measurement|dry mass|leaf area|cm2|mm2|m2|mg|g|kg|mol|mmol|umol|µmol", context_blob, perl = TRUE)) {
      evidence <- iu_add_evidence(evidence, UNIT_INFERRED_FROM_SOURCE_CONTEXT)
    }
  }

  basis_type <- NA_character_
  if (trait_key %in% IU_BASIS_CRITICAL_TRAITS) {
    basis_type <- iu_basis_from_tokens(column_names, methods_text)
  }

  chosen_unit <- NA_character_
  candidate_units <- character(0)
  conversion_factor <- NA_real_
  confidence <- "none"
  notes <- "No sufficient evidence for confident inference."

  # Required citation comments:
  # Kattge et al. 2020, Global Change Biology 26:119-188. https://doi.org/10.1111/gcb.14904
  # Wright et al. 2004, Nature 428:821-827. https://doi.org/10.1038/nature02403
  # Perez-Harguindeguy et al. 2013, Australian Journal of Botany 61:167-234. https://doi.org/10.1071/BT12225
  # Chave et al. 2009, Ecology Letters 12:351-366. https://doi.org/10.1111/j.1461-0248.2009.01285.x
  # Medlyn et al. 2017, New Phytologist 216:10-16. https://doi.org/10.1111/nph.14626
  # Bergmann et al. 2020, Science Advances 6:eaba3756. https://doi.org/10.1126/sciadv.aba3756

  if (trait_key == "specific_leaf_area") {
    candidate_units <- c("mm2_per_mg", "cm2_per_g", "m2_per_kg")
    # SLA thresholds from TRY/GLOPNET distributions (Kattge2020; Wright2004):
    # median 1-10 -> mm2/mg (high), 1000-10000 -> cm2/g (high), 10-1000 -> medium.
    if (!is.na(q50_raw) && q50_raw >= 1 && q50_raw <= 10) {
      chosen_unit <- "mm2_per_mg"
      conversion_factor <- 1
      confidence <- "high"
      notes <- "Median SLA in canonical mm2/mg range."
    } else if (!is.na(q50_raw) && q50_raw >= 1000 && q50_raw <= 10000) {
      chosen_unit <- "mm2_per_mg"
      conversion_factor <- 0.1
      confidence <- "high"
      notes <- "Median SLA indicates cm2/g scale converted to mm2/mg."
    } else if (!is.na(q50_raw) && q50_raw > 10 && q50_raw < 1000) {
      chosen_unit <- "mm2_per_mg"
      conversion_factor <- 1
      confidence <- "medium"
      notes <- "Intermediate SLA range; retained canonical unit with medium confidence."
    }
    cites <- iu_add_citation(cites, c("Kattge2020", "Wright2004"))
  }

  if (trait_key == "plant_height") {
    candidate_units <- c("m", "cm", "mm")
    # Plant height thresholds from global trait syntheses (Kattge2020; Bergmann2020):
    # median 0.01-1 -> m (high), 100-10000 -> cm (high), 1-100 -> medium.
    if (!is.na(q50_raw) && q50_raw >= 0.01 && q50_raw <= 1) {
      chosen_unit <- "m"
      conversion_factor <- 1
      confidence <- "high"
      notes <- "Median height already in meters."
    } else if (!is.na(q50_raw) && q50_raw >= 100 && q50_raw <= 10000) {
      chosen_unit <- "m"
      conversion_factor <- 0.01
      confidence <- "high"
      notes <- "Median height indicates centimeter scale converted to meters."
    } else if (!is.na(q50_raw) && q50_raw > 1 && q50_raw < 100) {
      chosen_unit <- "m"
      conversion_factor <- 1
      confidence <- "medium"
      notes <- "Intermediate height range; plausible mixed reporting scale."
    }
    cites <- iu_add_citation(cites, c("Kattge2020", "Bergmann2020"))
  }

  if (trait_key == "leaf_dry_matter_content") {
    candidate_units <- c("mg_per_g", "g_per_g", "percent")
    # LDMC thresholds from standard protocols (PerezHarguindeguy2013; Kattge2020):
    # median 100-900 -> mg/g (high), 0.1-0.9 -> g/g (high).
    if (!is.na(q50_raw) && q50_raw >= 100 && q50_raw <= 900) {
      chosen_unit <- "mg_per_g"
      conversion_factor <- 1
      confidence <- "high"
      notes <- "Median LDMC in mg/g range."
    } else if (!is.na(q50_raw) && q50_raw >= 0.1 && q50_raw <= 0.9) {
      chosen_unit <- "mg_per_g"
      conversion_factor <- 1000
      confidence <- "high"
      notes <- "Median LDMC in g/g range converted to mg/g."
    } else if (!is.na(q50_raw) && q50_raw >= 10 && q50_raw <= 90) {
      chosen_unit <- "mg_per_g"
      conversion_factor <- 10
      confidence <- "medium"
      notes <- "Median LDMC likely percent converted to mg/g."
    }
    cites <- iu_add_citation(cites, c("PerezHarguindeguy2013", "Kattge2020"))
  }

  if (trait_key %in% c("wood_density", "stem_specific_density")) {
    candidate_units <- c("g_per_cm3", "kg_per_m3")
    # Wood density thresholds from global compilations (Chave2009):
    # median 0.1-1.3 -> g/cm3 (high), 100-1300 -> kg/m3 (high).
    if (!is.na(q50_raw) && q50_raw >= 0.1 && q50_raw <= 1.3) {
      chosen_unit <- "g_per_cm3"
      conversion_factor <- 1
      confidence <- "high"
      notes <- "Median wood density in g/cm3 range."
    } else if (!is.na(q50_raw) && q50_raw >= 100 && q50_raw <= 1300) {
      chosen_unit <- "g_per_cm3"
      conversion_factor <- 0.001
      confidence <- "high"
      notes <- "Median wood density indicates kg/m3 scale converted to g/cm3."
    }
    cites <- iu_add_citation(cites, "Chave2009")
  }

  if (trait_key == "stomatal_conductance") {
    candidate_units <- c("mmol_per_m2_per_s", "mol_per_m2_per_s")
    # Stomatal conductance thresholds (Medlyn2017; TRY-derived):
    # median 10-2000 -> mmol/m2/s (high), 0.01-2 -> mol/m2/s (high).
    if (!is.na(q50_raw) && q50_raw >= 10 && q50_raw <= 2000) {
      chosen_unit <- "mmol_per_m2_per_s"
      conversion_factor <- 1
      confidence <- "high"
      notes <- "Median gs in mmol m-2 s-1 range."
    } else if (!is.na(q50_raw) && q50_raw >= 0.01 && q50_raw <= 2) {
      chosen_unit <- "mmol_per_m2_per_s"
      conversion_factor <- 1000
      confidence <- "high"
      notes <- "Median gs in mol m-2 s-1 range converted to mmol m-2 s-1."
    }
    cites <- iu_add_citation(cites, c("Medlyn2017", "Kattge2020"))
  }

  if (trait_key == "photosynthetic_rate") {
    candidate_units <- c("umol_per_m2_per_s", "mmol_per_m2_per_s", "mol_per_m2_per_s")
    # Net assimilation (Anet) thresholds from trait syntheses:
    # median 1-60 -> umol/m2/s (high), 0.001-0.06 -> mmol/m2/s (high).
    if (!is.na(q50_raw) && q50_raw >= 1 && q50_raw <= 60) {
      chosen_unit <- "umol_per_m2_per_s"
      conversion_factor <- 1
      confidence <- "high"
      notes <- "Median Anet in umol m-2 s-1 range."
    } else if (!is.na(q50_raw) && q50_raw >= 0.001 && q50_raw <= 0.06) {
      chosen_unit <- "umol_per_m2_per_s"
      conversion_factor <- 1000
      confidence <- "high"
      notes <- "Median Anet in mmol m-2 s-1 range converted to umol m-2 s-1."
    }
    cites <- iu_add_citation(cites, c("Kattge2020", "Wright2004"))
  }

  if (trait_key == "seed_mass") {
    candidate_units <- c("mg", "g", "kg")
    if (!is.na(q50_raw) && q50_raw >= 0.001 && q50_raw <= 2.5e7) {
      chosen_unit <- "mg"
      conversion_factor <- 1
      confidence <- "medium"
      notes <- "Seed mass range plausible in mg scale; medium without explicit unit tokens."
    }
    cites <- iu_add_citation(cites, "Kattge2020")
  }

  if (trait_key == "leaf_area") {
    candidate_units <- c("mm2", "cm2", "m2")
    if (!is.na(q50_raw) && q50_raw >= 1 && q50_raw <= 3e6) {
      chosen_unit <- "mm2"
      conversion_factor <- 1
      confidence <- "medium"
      notes <- "Leaf area plausible in mm2; medium confidence without explicit units."
    }
    cites <- iu_add_citation(cites, "Kattge2020")
  }

  if (trait_key %in% c("leaf_n", "leaf_p")) {
    candidate_units <- c("mg_per_g")
    chosen_unit <- "mg_per_g"
    conversion_factor <- 1
    confidence <- "medium"
    notes <- "Leaf nutrient concentration assumed canonical mg/g only when basis is resolved."
    cites <- iu_add_citation(cites, c("Kattge2020", "Wright2004"))
  }

  if (trait_key %in% c("leaf_cn_ratio", "leaf_cp_ratio")) {
    candidate_units <- c("dimensionless")
    chosen_unit <- "dimensionless"
    conversion_factor <- 1
    if (!is.na(q50_raw) && q50_raw >= 2 && q50_raw <= 300) {
      confidence <- "high"
      notes <- "Stoichiometric ratio in expected dimensionless range."
    } else {
      confidence <- "low"
      notes <- "Potential scale confusion for a dimensionless stoichiometric ratio."
    }
    cites <- iu_add_citation(cites, c("Kattge2020", "Wright2004"))
  }

  if (trait_key == "leaf_lignin") {
    candidate_units <- c("percent", "fraction", "mg_per_g")
    if (!is.na(q50_raw) && q50_raw >= 1 && q50_raw <= 60) {
      chosen_unit <- "percent"
      conversion_factor <- 1
      confidence <- "high"
      notes <- "Lignin values fit percent scale."
    } else if (!is.na(q50_raw) && q50_raw > 0 && q50_raw < 1) {
      chosen_unit <- "percent"
      conversion_factor <- 100
      confidence <- "medium"
      notes <- "Lignin values fit fraction scale converted to percent."
    } else if (!is.na(q50_raw) && q50_raw >= 10 && q50_raw <= 600) {
      chosen_unit <- "percent"
      conversion_factor <- 0.1
      confidence <- "medium"
      notes <- "Lignin values fit mg/g scale converted to percent."
    }
    cites <- iu_add_citation(cites, c("Kattge2020", "Wright2004"))
  }

  # Negative-expected hydraulic traits remain review-focused unless explicit context is available.
  if (trait_key %in% IU_NEGATIVE_EXPECTED_TRAITS) {
    candidate_units <- c("MPa")
    chosen_unit <- "MPa"
    conversion_factor <- 1
    if (!is.na(stats$q50) && stats$q50 < 0) {
      confidence <- "medium"
      notes <- "Negative hydraulic potential values are directionally consistent; sign convention still requires review."
    } else {
      confidence <- "low"
      notes <- "Hydraulic potential sign convention is unresolved."
    }
    cites <- iu_add_citation(cites, "Kattge2020")
  }

  # Column/context unit tokens can upgrade conversion and confidence when explicit.
  token_pool <- c(column_names, trait_name, methods_text, dataset_title, journal_name)
  token_pool <- token_pool[!is.na(token_pool) & nzchar(token_pool)]
  explicit_units <- unique(vapply(token_pool, function(txt) iu_detect_explicit_unit(txt, trait_key), character(1)))
  explicit_units <- explicit_units[!is.na(explicit_units) & nzchar(explicit_units)]

  if (length(explicit_units)) {
    evidence <- iu_add_evidence(evidence, UNIT_INFERRED_FROM_COLUMN_NAME)

    u <- explicit_units[[1]]
    if (trait_key == "specific_leaf_area" && u %in% c("mm2_per_mg", "cm2_per_g", "m2_per_kg")) {
      chosen_unit <- "mm2_per_mg"
      conversion_factor <- c(mm2_per_mg = 1, cm2_per_g = 0.1, m2_per_kg = 1)[[u]]
      confidence <- if (length(explicit_units) == 1) "high" else "medium"
    }
    if (trait_key == "plant_height" && u %in% c("m", "cm", "mm")) {
      chosen_unit <- "m"
      conversion_factor <- c(m = 1, cm = 0.01, mm = 0.001)[[u]]
      confidence <- if (length(explicit_units) == 1) "high" else "medium"
    }
    if (trait_key == "leaf_dry_matter_content" && u %in% c("mg_per_g", "g_per_g", "percent")) {
      chosen_unit <- "mg_per_g"
      conversion_factor <- c(mg_per_g = 1, g_per_g = 1000, percent = 10)[[u]]
      confidence <- if (length(explicit_units) == 1) "high" else "medium"
    }
    if (trait_key %in% c("wood_density", "stem_specific_density") && u %in% c("g_per_cm3", "kg_per_m3")) {
      chosen_unit <- "g_per_cm3"
      conversion_factor <- c(g_per_cm3 = 1, kg_per_m3 = 0.001)[[u]]
      confidence <- if (length(explicit_units) == 1) "high" else "medium"
    }
    if (trait_key == "stomatal_conductance" && u %in% c("mmol_per_m2_per_s", "mol_per_m2_per_s")) {
      chosen_unit <- "mmol_per_m2_per_s"
      conversion_factor <- c(mmol_per_m2_per_s = 1, mol_per_m2_per_s = 1000)[[u]]
      confidence <- if (length(explicit_units) == 1) "high" else "medium"
    }
    if (trait_key == "photosynthetic_rate" && u %in% c("umol_per_m2_per_s", "mmol_per_m2_per_s", "mol_per_m2_per_s")) {
      chosen_unit <- "umol_per_m2_per_s"
      conversion_factor <- c(umol_per_m2_per_s = 1, mmol_per_m2_per_s = 1000, mol_per_m2_per_s = 1e6)[[u]]
      confidence <- if (length(explicit_units) == 1) "high" else "medium"
    }
    if (trait_key == "seed_mass" && u %in% c("mg", "g", "kg")) {
      chosen_unit <- "mg"
      conversion_factor <- c(mg = 1, g = 1000, kg = 1e6)[[u]]
      confidence <- if (length(explicit_units) == 1) "high" else "medium"
    }
    if (trait_key == "leaf_area" && u %in% c("mm2", "cm2", "m2")) {
      chosen_unit <- "mm2"
      conversion_factor <- c(mm2 = 1, cm2 = 100, m2 = 1e6)[[u]]
      confidence <- if (length(explicit_units) == 1) "high" else "medium"
    }
    if (trait_key == "leaf_lignin" && u %in% c("percent", "fraction", "mg_per_g")) {
      chosen_unit <- "percent"
      conversion_factor <- c(percent = 1, fraction = 100, mg_per_g = 0.1)[[u]]
      confidence <- if (length(explicit_units) == 1) "high" else "medium"
    }
  }

  if (!is.na(chosen_unit)) {
    evidence <- iu_add_evidence(evidence, UNIT_INFERRED_FROM_VALUE_DISTRIBUTION)
  }

  # Basis ambiguity guardrails: area-vs-mass mismatch is not a pure unit conversion.
  if (trait_key %in% IU_BASIS_CRITICAL_TRAITS) {
    if (is.na(basis_type) || basis_type == "unknown") {
      confidence <- if (confidence == "high") "low" else if (confidence == "medium") "low" else confidence
      evidence <- iu_add_evidence(evidence, c(BASIS_AMBIGUOUS_AREA_VS_MASS, UNIT_INFERENCE_LOW_POSTERIOR))
      notes <- paste(notes, "Basis type unresolved (area vs mass); record should remain review unless basis is resolved.")
    }
  }

  if (confidence %in% c("none", "low")) {
    evidence <- iu_add_evidence(evidence, UNIT_INFERENCE_LOW_POSTERIOR)
  }

  result$inferred_unit <- chosen_unit
  result$confidence <- confidence
  result$evidence <- iu_join_unique(evidence)
  result$citation_keys <- iu_join_unique(cites)
  result$basis_type <- basis_type
  result$conversion_factor <- conversion_factor
  result$candidate_units <- iu_join_unique(candidate_units)
  result$notes <- notes
  result
}

infer_units_batch <- function(df) {
  if (!is.data.frame(df)) {
    stop("infer_units_batch() requires a data.frame.", call. = FALSE)
  }

  required <- c(
    "trait_name", "trait_value", "dryad_dataset_doi",
    "source_column_trait_name", "source_column_unit"
  )
  missing_cols <- setdiff(required, names(df))
  if (length(missing_cols)) {
    stop(sprintf("infer_units_batch(): missing required columns: %s", paste(missing_cols, collapse = ", ")), call. = FALSE)
  }

  n <- nrow(df)
  if (!n) {
    df$inferred_unit_value <- character(0)
    df$inferred_unit_confidence <- character(0)
    df$inference_evidence <- character(0)
    df$inference_citation_keys <- character(0)
    df$basis_type <- character(0)
    df$unit_conversion_factor <- numeric(0)
    return(df)
  }

  df$inferred_unit_value <- NA_character_
  df$inferred_unit_confidence <- NA_character_
  df$inference_evidence <- NA_character_
  df$inference_citation_keys <- NA_character_
  df$basis_type <- NA_character_
  df$unit_conversion_factor <- NA_real_

  dataset_key <- ifelse(is.na(df$dryad_dataset_doi), "NA_DOI", as.character(df$dryad_dataset_doi))
  trait_key <- ifelse(is.na(df$trait_name), "NA_TRAIT", iu_norm(df$trait_name))
  group_key <- paste(dataset_key, trait_key, sep = "||")

  group_ids <- unique(group_key)

  for (g in group_ids) {
    idx <- which(group_key == g)
    if (!length(idx)) {
      next
    }

    g_trait_name <- as.character(df$trait_name[[idx[[1]]]])
    g_values <- df$trait_value[idx]
    g_columns <- unique(c(df$source_column_trait_name[idx], df$source_column_unit[idx]))

    inferred <- infer_units_for_dataset(
      trait_name = g_trait_name,
      values = g_values,
      column_names = g_columns,
      source_context = list(dataset_title = NA_character_, journal_name = NA_character_, methods_text = NA_character_)
    )

    locked_evidence <- iu_add_evidence(strsplit(inferred$evidence, ",", fixed = TRUE)[[1]], DATASET_LEVEL_UNIT_LOCK_APPLIED)
    base_evidence <- iu_join_unique(locked_evidence)

    df$inferred_unit_value[idx] <- inferred$inferred_unit
    df$inferred_unit_confidence[idx] <- inferred$confidence
    df$inference_evidence[idx] <- base_evidence
    df$inference_citation_keys[idx] <- inferred$citation_keys
    df$basis_type[idx] <- inferred$basis_type
    df$unit_conversion_factor[idx] <- inferred$conversion_factor

    # Record-level conflict detection against dataset lock when explicit unit tokens disagree.
    conflicts <- logical(length(idx))
    trait_resolved <- iu_resolve_trait(g_trait_name)
    for (k in seq_along(idx)) {
      row_i <- idx[[k]]
      text_candidates <- c(df$source_column_unit[[row_i]], df$source_column_trait_name[[row_i]])
      text_candidates <- text_candidates[!is.na(text_candidates) & nzchar(text_candidates)]
      explicit <- unique(vapply(text_candidates, function(tt) iu_detect_explicit_unit(tt, trait_resolved), character(1)))
      explicit <- explicit[!is.na(explicit) & nzchar(explicit)]

      if (!length(explicit) || is.na(inferred$inferred_unit)) {
        conflicts[[k]] <- FALSE
      } else {
        canonical_from_explicit <- NA_character_
        if (trait_resolved == "specific_leaf_area") canonical_from_explicit <- "mm2_per_mg"
        if (trait_resolved == "plant_height") canonical_from_explicit <- "m"
        if (trait_resolved == "leaf_dry_matter_content") canonical_from_explicit <- "mg_per_g"
        if (trait_resolved %in% c("wood_density", "stem_specific_density")) canonical_from_explicit <- "g_per_cm3"
        if (trait_resolved == "stomatal_conductance") canonical_from_explicit <- "mmol_per_m2_per_s"
        if (trait_resolved == "photosynthetic_rate") canonical_from_explicit <- "umol_per_m2_per_s"
        if (trait_resolved == "seed_mass") canonical_from_explicit <- "mg"
        if (trait_resolved == "leaf_area") canonical_from_explicit <- "mm2"
        if (trait_resolved == "leaf_lignin") canonical_from_explicit <- "percent"

        conflicts[[k]] <- !is.na(canonical_from_explicit) && !identical(canonical_from_explicit, inferred$inferred_unit)
      }
    }

    if (any(conflicts)) {
      row_conflict_idx <- idx[which(conflicts)]
      for (ri in row_conflict_idx) {
        ev <- strsplit(df$inference_evidence[[ri]], ",", fixed = TRUE)[[1]]
        df$inference_evidence[[ri]] <- iu_join_unique(iu_add_evidence(ev, RECORD_CONFLICTS_WITH_DATASET_LOCK))
      }
    }

    # Dataset coherence check: if >5% records conflict with lock, downgrade whole group.
    conflict_rate <- sum(conflicts) / length(idx)
    if (is.finite(conflict_rate) && conflict_rate > 0.05) {
      for (ri in idx) {
        ev <- strsplit(df$inference_evidence[[ri]], ",", fixed = TRUE)[[1]]
        df$inference_evidence[[ri]] <- iu_join_unique(iu_add_evidence(ev, DATASET_COHERENCE_FAIL))
      }
      df$inferred_unit_confidence[idx] <- "low"
    }
  }

  df
}
