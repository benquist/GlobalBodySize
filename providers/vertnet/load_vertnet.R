## GlobalBodySize/providers/vertnet/load_vertnet.R
## Intake script for VertNet — global aggregator of vertebrate specimen records
## http://vertnet.org/
##
## Reference:
##   Constable H, Guralnick R, Wieczorek J, Spencer C, Peterson AT, et al. 2010.
##   VertNet: A New Model for Biodiversity Data Sharing.
##   PLoS Biol 8(2):e1000309. DOI: 10.1371/journal.pbio.1000309
##
## Access via rvertnet R package or VertNet API:
##   https://github.com/ropensci/rvertnet
##
## IMPORTANT CAVEATS:
##   - VertNet records are raw museum specimen labels — mass values are rare,
##     inconsistently recorded, and often lack units.
##   - Use VertNet only for gap-filling species not covered by Tier A/B databases.
##   - All mass records from VertNet should be flagged mass_confidence="low"
##     and manually reviewed before inclusion.
##   - This loader queries VertNet for records with "body mass" or "weight" fields.
##
## Status: Stub implementation — requires rvertnet package and API access.
##         Full download not automated due to query-rate limits and data heterogeneity.

## ---- Constants --------------------------------------------------------------

VERTNET_SOURCE_ID  <- "vertnet_constable2010"
VERTNET_DISPLAY    <- "VertNet (Constable et al. 2010)"
VERTNET_DOI        <- "10.1371/journal.pbio.1000309"
VERTNET_CITATION   <- paste0(
  "Constable H, Guralnick R, Wieczorek J, Spencer C, Peterson AT, et al. 2010. ",
  "VertNet: A New Model for Biodiversity Data Sharing. ",
  "PLoS Biol 8(2):e1000309. https://doi.org/10.1371/journal.pbio.1000309"
)

## ---- Check prerequisites ----------------------------------------------------

.check_rvertnet <- function() {
  if (!requireNamespace("rvertnet", quietly = TRUE)) {
    stop(
      "Package 'rvertnet' is required for VertNet intake.\n",
      "Install with: install.packages('rvertnet')",
      call. = FALSE
    )
  }
}

## ---- Query VertNet for body mass records ------------------------------------
## Queries VertNet for records containing dynamicproperties or fieldnotes
## with mass-related keywords. Returns raw search results.
##
## NOTE: VertNet API limits: ~1000 records per request, rate-limited.
## For broad coverage, iterate over taxonomic groups or families.

query_vertnet_mass <- function(taxon_group = "Mammalia",
                               max_records = 1000,
                               mass_keyword = "body mass") {
  .check_rvertnet()

  message("Querying VertNet for '", mass_keyword, "' in ", taxon_group,
          " (max ", max_records, " records)...")

  ## rvertnet::searchbyterm searches DwC fields
  ## dynamicProperties often contains mass measurements
  res <- tryCatch(
    rvertnet::searchbyterm(
      class      = taxon_group,
      mappedlocality = NULL,
      limit      = max_records,
      verbose    = FALSE
    ),
    error = function(e) {
      warning("VertNet query failed: ", conditionMessage(e))
      NULL
    }
  )
  res
}

## ---- Parse VertNet records --------------------------------------------------
## VertNet records store mass in 'dynamicProperties' as free text, e.g.:
##   "mass=45g" or "weight: 12.3 g" or "bodymass: 450 g"
## This function attempts to extract numeric mass values from that field.

.extract_mass_from_dynprop <- function(dynprop_vec) {
  ## Regex to find numeric mass values in dynamic properties text
  ## Handles: "mass=45g", "weight: 12.3 g", "body mass: 450g", "45 g", etc.
  pattern <- "(?:body[ _]?mass|weight|mass)\\s*[=:]?\\s*([0-9]+\\.?[0-9]*)\\s*(?:g|grams?|gram)?"
  matches <- regmatches(dynprop_vec,
                        regexpr(pattern, dynprop_vec, perl = TRUE, ignore.case = TRUE))
  ## Extract the numeric portion
  nums <- regmatches(matches,
                     regexpr("[0-9]+\\.?[0-9]*", matches, perl = TRUE))
  mass <- suppressWarnings(as.numeric(nums))
  ## Return NA where no match
  result <- rep(NA_real_, length(dynprop_vec))
  result[nzchar(nums)] <- mass
  result
}

parse_vertnet <- function(vertnet_result, tax_group = "other") {
  if (is.null(vertnet_result) || is.null(vertnet_result$data)) {
    warning("VertNet: no data to parse")
    return(NULL)
  }

  raw <- vertnet_result$data

  ## Key DwC columns (may not all be present)
  species_col  <- if ("scientificname"   %in% names(raw)) "scientificname"   else NA
  dynprop_col  <- if ("dynamicproperties" %in% names(raw)) "dynamicproperties" else NA
  lat_col      <- if ("decimallatitude"  %in% names(raw)) "decimallatitude"  else NA
  lon_col      <- if ("decimallongitude" %in% names(raw)) "decimallongitude" else NA
  yr_col       <- if ("year"             %in% names(raw)) "year"             else NA
  country_col  <- if ("countrycode"      %in% names(raw)) "countrycode"      else NA
  record_col   <- if ("occurrenceid"     %in% names(raw)) "occurrenceid"     else "catalognumber"

  if (is.na(species_col)) {
    warning("VertNet: no scientificname column found")
    return(NULL)
  }

  ## Extract mass from dynamicProperties
  mass_vals <- if (!is.na(dynprop_col)) {
    .extract_mass_from_dynprop(raw[[dynprop_col]])
  } else {
    rep(NA_real_, nrow(raw))
  }

  out <- data.frame(
    source_id              = VERTNET_SOURCE_ID,
    source_display_name    = VERTNET_DISPLAY,
    source_doi             = VERTNET_DOI,
    source_access_date     = as.character(Sys.Date()),
    bibliographic_citation = VERTNET_CITATION,
    dataset_id             = VERTNET_SOURCE_ID,
    original_row_id        = seq_len(nrow(raw)),
    source_file_path       = "vertnet_api",

    verbatim_taxon_name    = if (!is.na(species_col)) raw[[species_col]] else NA_character_,
    verbatim_authorship    = NA_character_,
    input_taxonomic_group  = tax_group,
    input_taxonomic_rank   = "species",

    mass_g                 = mass_vals,
    mass_g_min             = NA_real_,
    mass_g_max             = NA_real_,
    mass_se                = NA_real_,
    mass_n                 = 1L,  # individual specimen

    mass_type              = "wet",
    measurement_method     = "museum_label",
    life_stage             = "unknown",
    sex                    = "unknown",

    decimal_latitude       = if (!is.na(lat_col))     suppressWarnings(as.numeric(raw[[lat_col]]))     else NA_real_,
    decimal_longitude      = if (!is.na(lon_col))     suppressWarnings(as.numeric(raw[[lon_col]]))     else NA_real_,
    coordinate_uncertainty_m = NA_real_,
    country_code           = if (!is.na(country_col)) raw[[country_col]] else NA_character_,

    year_measured          = if (!is.na(yr_col))      suppressWarnings(as.integer(raw[[yr_col]]))      else NA_integer_,
    date_measured          = NA_character_,

    measurement_type       = "body mass",
    measurement_unit       = "g",
    basis_of_record        = "PreservedSpecimen",

    ## VertNet mass is specimen label text — low confidence until verified
    mass_confidence        = "low",
    qa_status              = "needs_review",
    qa_note                = paste0("VertNet_dynprop_extract | MANUAL_REVIEW_REQUIRED",
                                    if (!is.na(dynprop_col))
                                      paste0(" | dynprop=", substr(raw[[dynprop_col]], 1, 80))
                                    else ""),

    stringsAsFactors = FALSE
  )

  out <- out[!is.na(out$mass_g) & out$mass_g > 0, ]
  message("VertNet (", tax_group, "): ", nrow(out), " records with extractable mass")
  out
}

## ---- Master runner ----------------------------------------------------------
## NOTE: VertNet intake is NOT fully automated. Use for gap-filling only.
## Results require manual review before integration into the compiled table.

run_vertnet_intake <- function(taxon_groups = c("Mammalia", "Aves", "Reptilia", "Amphibia", "Actinopterygii"),
                               max_per_group = 500,
                               output_file   = "data/compiled/vertnet_compiled.csv") {
  .check_rvertnet()

  ## Map class to group vocab
  group_map <- c(
    Mammalia       = "mammal",
    Aves           = "bird",
    Reptilia       = "reptile",
    Amphibia       = "amphibian",
    Actinopterygii = "fish"
  )

  results <- lapply(taxon_groups, function(cls) {
    tax_group <- group_map[cls]
    if (is.na(tax_group)) tax_group <- "other"
    res <- query_vertnet_mass(taxon_group = cls, max_records = max_per_group)
    parse_vertnet(res, tax_group = tax_group)
  })

  results_valid <- Filter(Negate(is.null), results)
  if (!length(results_valid)) {
    warning("VertNet: no mass records retrieved")
    return(invisible(NULL))
  }

  out <- do.call(rbind, results_valid)
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(out, output_file)
  message("VertNet compiled: ", nrow(out), " rows (NEEDS_REVIEW) -> ", output_file)
  invisible(out)
}
