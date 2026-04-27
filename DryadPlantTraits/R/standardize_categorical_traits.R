# ============================================================================
# CATEGORICAL TRAIT VOCABULARY STANDARDIZATION
# ============================================================================
#
# Purpose: Normalize categorical trait values to a controlled vocabulary
#          before database export. Handles TRY integer codes, text synonyms,
#          and common abbreviations.
#
# References:
#   TRY Plant Trait Database: Kattge et al. 2020, GCB 26:119-188
#   Perez-Harguindeguy et al. 2013, Australian Journal of Botany 61:167-234
#   Raunkiaer life-form system (1934) for growth form classification
# ============================================================================

# ---------------------------------------------------------------------------
# Growth-form vocabulary
# ---------------------------------------------------------------------------
# Canonical tokens: tree, shrub, subshrub, herb, grass, liana_vine,
#                   aquatic, succulent, bryophyte, unknown
#
# TRY trait 1 (Plant growth form) codes:
#   1 = tree, 2 = shrub, 3 = subshrub (dwarf shrub), 4 = herb,
#   5 = graminoid (grass/sedge), 6 = liana (vine), 7 = aquatic,
#   8 = succulent, 9 = bryophyte
GROWTH_FORM_VOCAB <- list(
  tree = c(
    "1", "tree", "trees", "arboreal", "woody tree", "deciduous tree",
    "evergreen tree", "conifer", "broadleaf tree", "forest tree",
    "phanerophyte"
  ),
  shrub = c(
    "2", "shrub", "shrubs", "woody shrub", "deciduous shrub",
    "evergreen shrub", "chamaephyte", "nanophanerophyte"
  ),
  subshrub = c(
    "3", "subshrub", "sub-shrub", "dwarf shrub", "dwarf-shrub",
    "semi-shrub", "semi shrub"
  ),
  herb = c(
    "4", "herb", "herbs", "herbaceous", "forb", "forbs", "herbaceous plant",
    "non-grass herb", "annual", "biennial", "perennial herb",
    "therophyte", "hemicryptophyte", "geophyte", "cryptophyte"
  ),
  grass = c(
    "5", "grass", "grasses", "graminoid", "sedge", "rush",
    "grass-like", "gramineae", "poaceae", "cyperaceae", "juncaceae"
  ),
  liana_vine = c(
    "6", "liana", "lianas", "vine", "vines", "climber", "climbers",
    "liana/vine", "vine/liana", "woody vine", "twining vine"
  ),
  aquatic = c(
    "7", "aquatic", "hydrophyte", "aquatic plant", "submerged",
    "emergent", "floating", "macrophyte"
  ),
  succulent = c(
    "8", "succulent", "succulents", "cactus", "cacti", "stem succulent",
    "leaf succulent", "crassulacean"
  ),
  bryophyte = c(
    "9", "bryophyte", "moss", "liverwort", "hornwort", "bryophyta"
  )
)

# ---------------------------------------------------------------------------
# Leaf-phenology vocabulary
# ---------------------------------------------------------------------------
# Canonical tokens: evergreen, deciduous, semi_deciduous, semi_evergreen, unknown
#
# TRY trait 3 (Leaf phenology) common codes:
#   1 = evergreen, 2 = deciduous, 3 = semi-deciduous
LEAF_PHENOLOGY_VOCAB <- list(
  evergreen = c(
    "1", "evergreen", "evergreen broad-leaved", "evergreen broadleaf",
    "ever-green", "perennifolius"
  ),
  deciduous = c(
    "2", "deciduous", "summer-deciduous", "winter-deciduous",
    "drought-deciduous", "dry season deciduous"
  ),
  semi_deciduous = c(
    "3", "semi-deciduous", "semideciduous", "semi deciduous",
    "partially deciduous"
  ),
  semi_evergreen = c(
    "semi-evergreen", "semievergreen", "semi evergreen",
    "brevideciduous"
  )
)

# ---------------------------------------------------------------------------
# Lookup helper (internal)
# ---------------------------------------------------------------------------
.match_vocab <- function(value, vocab) {
  key_norm <- function(x) {
    tolower(trimws(gsub("[^a-z0-9]+", "_", tolower(trimws(x)))))
  }
  v_norm <- key_norm(as.character(value))
  for (canonical in names(vocab)) {
    synonyms_norm <- vapply(vocab[[canonical]], key_norm, character(1))
    if (v_norm %in% synonyms_norm) {
      return(canonical)
    }
  }
  NA_character_
}

# ---------------------------------------------------------------------------
# Public function: standardize_categorical_trait()
# ---------------------------------------------------------------------------
#' @title Standardize a categorical trait value
#'
#' @description Maps a raw trait value (text or TRY integer code) to a
#'   controlled-vocabulary token. Returns the canonical token and a confidence
#'   level. Confidence is "high" for exact vocabulary matches (including TRY
#'   integer codes), "none" for unrecognized values.
#'
#' @param trait_name Character. Canonical trait key, e.g. "growth_form".
#' @param value Character or numeric. Raw value from the dataset.
#'
#' @return Named list:
#'   \describe{
#'     \item{standardized}{Canonical vocabulary token, or NA_character_ if
#'       unrecognized.}
#'     \item{confidence}{"high" if matched, "none" if not recognized.}
#'     \item{reason}{Character explanation.}
#'   }
standardize_categorical_trait <- function(trait_name, value) {
  vocab <- switch(
    trait_name,
    growth_form    = GROWTH_FORM_VOCAB,
    leaf_phenology = LEAF_PHENOLOGY_VOCAB,
    NULL
  )

  if (is.null(vocab)) {
    return(list(
      standardized = NA_character_,
      confidence   = "none",
      reason       = paste0("No vocabulary defined for categorical trait '", trait_name, "'.")
    ))
  }

  # Handle NA / empty
  if (is.na(value) || !nchar(trimws(as.character(value)))) {
    return(list(
      standardized = NA_character_,
      confidence   = "none",
      reason       = "Value is NA or empty."
    ))
  }

  matched <- .match_vocab(value, vocab)

  if (!is.na(matched)) {
    list(
      standardized = matched,
      confidence   = "high",
      reason       = paste0("Value '", value, "' matched canonical token '", matched, "'.")
    )
  } else {
    list(
      standardized = NA_character_,
      confidence   = "none",
      reason       = paste0("Value '", value, "' not found in controlled vocabulary for '", trait_name, "'.")
    )
  }
}
