# =============================================================================
# R/data_access.R
# Purpose : All functions that retrieve data from the BIEN database. Keeping
#           remote API calls isolated in this one file means:
#             1. If BIEN changes its API, only this file needs updating.
#             2. The rest of the pipeline can be tested offline using mock data.
#             3. It is clear which steps require an internet connection.
#
# Data type (ecology-user Step 1):
#   This file produces PRESENCE-ONLY occurrence data. BIEN records represent
#   georeferenced vascular plant observations from herbarium specimens, field
#   surveys, and vegetation plots across the Americas.
#
# Sampling bias note (ecology-user Step 3):
#   BIEN occurrences reflect collector bias — roads, urban areas, and
#   well-visited nature reserves are over-represented. This pipeline does NOT
#   correct for this bias (no rarefaction, no target-group background sampling).
#   Results should be interpreted as a descriptive climate-space summary, NOT
#   as a calibrated species distribution model.
#
# BIEN citation:
#   Maitner, B. S., et al. (2018). The BIEN R package: A tool to access the
#   Botanical Information and Ecology Network (BIEN) database. Methods in
#   Ecology and Evolution, 9, 373–379. https://doi.org/10.1111/2041-210X.12861
# =============================================================================


# --------------------------------------------------------------------------- #
# BIEN availability guard
#
# Usage : assert_bien_available()
# Called at the top of any function that needs BIEN. Gives a clear, actionable
# error message if the package is not installed, rather than a cryptic "object
# not found" error when BIEN:: is first used.
# --------------------------------------------------------------------------- #
assert_bien_available <- function() {
  if (!requireNamespace("BIEN", quietly = TRUE)) {
    stop("Package 'BIEN' is required. Install with install.packages('BIEN').")
  }
}


# --------------------------------------------------------------------------- #
# Safe BIEN call wrapper
#
# Usage : res <- safe_bien_call(BIEN::BIEN_taxonomy_family("Asteraceae"))
# Wraps any BIEN call in tryCatch so that a network failure or BIEN server
# error returns a structured error object instead of crashing the pipeline.
# The returned object has class "bien_error" so callers can detect failure
# with inherits(res, "bien_error") rather than checking for NULL.
# --------------------------------------------------------------------------- #
safe_bien_call <- function(expr) {
  tryCatch(
    expr,
    error = function(e) {
      structure(
        list(ok = FALSE, message = conditionMessage(e), data = NULL),
        class = "bien_error"
      )
    }
  )
}


# --------------------------------------------------------------------------- #
# Species name extractor (internal helper)
#
# Usage : spp <- extract_species_candidates(bien_taxonomy_df)
# Takes a BIEN taxonomy data frame and returns a vector of valid binomial
# species names.
#
# The regex "^[A-Z][a-zA-Z-]+ [a-z][a-zA-Z-]+$" enforces binomial format:
#   - First word: starts with uppercase (Genus)
#   - Second word: starts with lowercase (specific epithet)
#   - No numerals, no extra words (rules out "sp.", "cf.", hybrids with "×")
#
# Why filter to true binomials?
#   BIEN taxonomy tables sometimes include genus-only names, uncertain IDs
#   ("Senecio sp."), and infraspecific taxa. Restricting to binomials ensures
#   BIEN_occurrence_species() receives a well-formed query.
# --------------------------------------------------------------------------- #
extract_species_candidates <- function(df) {
  if (!is.data.frame(df) || nrow(df) == 0) return(character(0))

  sp_col <- find_first_col(df, c(
    "scrubbed_species_binomial", "species", "species_name", "scientific_name",
    "scientificName", "accepted_binomial"
  ))
  if (is.null(sp_col)) return(character(0))

  x <- as.character(df[[sp_col]])
  x <- trimws(x)
  # Keep only valid binomials (Genus epithet); reject everything else
  x <- x[grepl("^[A-Z][a-zA-Z-]+ [a-z][a-zA-Z-]+$", x)]
  unique(x)
}


# --------------------------------------------------------------------------- #
# Candidate species pool builder
#
# Usage : species_pool <- get_species_pool(cfg)
# Input : cfg — config list from read_config(); uses cfg$families_pool,
#         cfg$candidate_pool_size
# Output: character vector of candidate species names
#
# Workflow:
#   1. Query BIEN taxonomy for each plant family listed in config.yml.
#   2. Extract valid binomial species names from each result.
#   3. Accumulate unique names until the pool reaches candidate_pool_size.
#   4. If the pool exceeds the target size, randomly sub-sample.
#
# Why build a pool first instead of querying a random species directly?
#   BIEN does not expose a "return a random species" endpoint. We must first
#   retrieve a set of known species for each family, then draw randomly from
#   that set. Building the pool once and drawing from it repeatedly (in the
#   attempt loop in run_pipeline.R) is far more efficient than making a new
#   taxonomy API call for each attempt.
#
# Ecological scale (Step 2):
#   Pool is restricted to families in config.yml. This intentionally biases
#   the draw toward well-represented, species-rich angiosperm families
#   (Asteraceae, Fabaceae, etc.) rather than sampling uniformly across all
#   vascular plants. This is a pragmatic choice to maximise the probability
#   that a drawn species has sufficient BIEN occurrence records.
# --------------------------------------------------------------------------- #
get_species_pool <- function(config) {
  assert_bien_available()

  target_n <- as.integer(config$candidate_pool_size %||% 200)
  families <- as.character(config$families_pool %||% c("Asteraceae", "Fabaceae", "Poaceae"))
  families <- unique(families)

  species_pool <- character(0)

  for (fam in families) {
    log_info("Querying BIEN taxonomy for family: ", fam)
    res <- safe_bien_call(BIEN::BIEN_taxonomy_family(fam))

    # If this family lookup failed (network error, server issue), skip it
    # and try the next family rather than crashing the whole pipeline
    if (inherits(res, "bien_error")) {
      log_info("Family lookup failed for ", fam, ": ", res$message)
      next
    }

    spp <- extract_species_candidates(res)
    if (length(spp) == 0) next

    species_pool <- unique(c(species_pool, spp))

    # Early exit once we have enough candidates — avoids unnecessary API calls
    if (length(species_pool) >= target_n) break
  }

  if (length(species_pool) == 0) {
    stop("Could not build a BIEN species pool. BIEN may be unavailable or offline.")
  }

  # Sub-sample to target size (random, uses seed set in run_pipeline.R)
  if (length(species_pool) > target_n) {
    species_pool <- sample(species_pool, size = target_n)
  }

  species_pool
}


# --------------------------------------------------------------------------- #
# BIEN occurrence downloader
#
# Usage : raw <- fetch_occurrences("Quercus robur", occurrence_limit = 10000)
# Input : species         — binomial species name (Genus species)
#         occurrence_limit — max records to download (prevents memory issues
#                            for very common species like Zea mays)
# Output: data.frame of raw BIEN occurrence records (column names vary by
#         BIEN version; normalize_occurrence_columns() in utils.R standardizes
#         them downstream)
#
# Why try multiple argument templates?
#   The BIEN R package has evolved across versions and some argument names
#   have changed (e.g., `natives.only` was added in a later version). By
#   trying progressively simpler call signatures we maximise compatibility
#   across BIEN package versions without requiring users to upgrade.
#   The first template requests the broadest possible data (cultivated records
#   included, geo-validation off); later templates fall back to simpler calls.
#
# Uncertainty note (Step 7):
#   BIEN occurrence records have varying spatial precision. Some herbarium
#   records are georeferenced to county centroids (low precision); others
#   are GPS-exact. This pipeline does NOT filter by coordinate uncertainty.
#   Users interpreting climate-niche results should be aware that imprecise
#   coordinates contribute noise to the climate extraction step.
# --------------------------------------------------------------------------- #
fetch_occurrences <- function(species, occurrence_limit = 10000) {
  assert_bien_available()

  # Ranked argument templates — try in order, stop at first success
  arg_templates <- list(
    # Template 1: broadest request — includes cultivated, no geo-validation,
    #             all taxonomy fields. Most informative but requires latest BIEN.
    list(
      species        = species,
      all.taxonomy   = TRUE,
      cultivated     = TRUE,
      natives.only   = FALSE,
      only.geovalid  = FALSE,
      limit          = as.integer(occurrence_limit)
    ),
    # Template 2: drop cultivated and natives.only args (older BIEN versions)
    list(
      species       = species,
      all.taxonomy  = TRUE,
      only.geovalid = FALSE,
      limit         = as.integer(occurrence_limit)
    ),
    # Template 3: minimal args with limit — maximum compatibility
    list(
      species = species,
      limit   = as.integer(occurrence_limit)
    ),
    # Template 4: bare minimum — no limit (last resort; may be slow for
    #             common species but should work on any BIEN version)
    list(
      species = species
    )
  )

  last_error <- NULL

  for (args in arg_templates) {
    res <- tryCatch(
      do.call(BIEN::BIEN_occurrence_species, args),
      error = function(e) {
        last_error <<- conditionMessage(e)
        NULL
      }
    )

    # Return the first successful data.frame we get
    if (is.data.frame(res)) {
      return(res)
    }
  }

  # All templates failed — surface the last error with context
  stop("Failed to retrieve BIEN occurrences for species '", species, "'. Last error: ", last_error)
}
