## R/animal_scaling_schema.R
## Canonical output schema for Animal_scaling_data compiled table.
##
## All provider intake scripts must map their fields to these columns.
## Columns not provided by a source should be NA (not omitted).
##
## Use animal_scaling_schema_columns() to get the full column list.
## Use make_empty_animal_scaling_row() for safe row construction.

## ---- Column definitions -----------------------------------------------------

#' Return the canonical column names for the Animal_scaling_data compiled table.
#'
#' @return character vector of column names
animal_scaling_schema_columns <- function() {
  c(
    ## -- Provenance -----------------------------------------------------------
    "source_id",               # Short stable identifier, e.g. "animaltraits_herberstein2022"
    "source_display_name",     # Human-readable name, e.g. "AnimalTraits (Herberstein et al. 2022)"
    "source_doi",              # DOI of the data publication or dataset
    "source_access_date",      # ISO date string when data were accessed/downloaded
    "bibliographic_citation",  # Full citation string
    "original_row_id",         # Row identifier from the source file (character)
    "source_file_path",        # Relative path to the raw source file used

    ## -- Taxonomy (verbatim input) --------------------------------------------
    "verbatim_taxon_name",     # Binomial as it appears in the source
    "input_taxonomic_group",   # Coarse group: "mammal", "bird", "reptile", etc.
    "input_taxonomic_rank",    # "species", "genus", "family", etc.

    ## -- Taxonomy (resolved, e.g. via GBIF/TNRS) ------------------------------
    "resolved_taxon_name",     # Accepted name after reconciliation (NA if not done)
    "kingdom",
    "phylum",
    "class",
    "order",
    "family",
    "genus",

    ## -- Body mass ------------------------------------------------------------
    "body_mass_g",             # Numeric, grams
    "body_mass_source",        # "measured" | "modeled" | "literature_mean" |
                               # "literature_range_midpoint" | "unknown"

    ## -- Metabolic rate -------------------------------------------------------
    "metabolic_rate_value",    # Numeric; unit given in metabolic_rate_unit
    "metabolic_rate_unit",     # e.g. "mL_O2_hr" | "W" | "J_day"
    "metabolic_rate_type",     # "basal" | "standard" | "field" | "resting" |
                               # "active" | "unknown"
    "metabolic_rate_temp_C",   # Numeric assay temperature in °C, or NA

    ## -- Life history ---------------------------------------------------------
    "lifespan_max_years",      # Numeric
    "lifespan_source",         # "captivity" | "wild" | "unknown"
    "age_at_maturity_years",   # Numeric
    "litter_clutch_size",      # Numeric
    "litters_per_year",        # Numeric

    ## -- Growth ---------------------------------------------------------------
    "growth_rate_value",       # Numeric
    "growth_rate_unit",        # e.g. "g_day" | "von_Bertalanffy_K"
    "growth_model",            # "von_Bertalanffy" | "logistic" | "linear" |
                               # "other" | NA

    ## -- QA flags -------------------------------------------------------------
    "qa_flag",                 # "" for clean; pipe-separated issues otherwise
    "qa_body_mass_range",      # "ok" | "suspect_low" | "suspect_high" | "missing"
    "qa_metabolic_unit_verified"  # logical
  )
}

## ---- Empty row constructor --------------------------------------------------

#' Return a one-row data.frame with all schema columns set to NA.
#'
#' Useful as a safe template in intake scripts:
#'   row <- make_empty_animal_scaling_row()
#'   row$body_mass_g <- 42.5
#'   ...
#'
#' @return data.frame with 1 row and all canonical columns
make_empty_animal_scaling_row <- function() {
  cols <- animal_scaling_schema_columns()
  row  <- as.data.frame(
    lapply(cols, function(x) NA),
    stringsAsFactors = FALSE
  )
  names(row) <- cols
  ## Coerce numeric columns explicitly
  numeric_cols <- c(
    "body_mass_g", "metabolic_rate_value", "metabolic_rate_temp_C",
    "lifespan_max_years", "age_at_maturity_years", "litter_clutch_size",
    "litters_per_year", "growth_rate_value"
  )
  for (col in numeric_cols) {
    row[[col]] <- NA_real_
  }
  ## Coerce logical columns
  row[["qa_metabolic_unit_verified"]] <- NA
  ## Coerce character columns (everything else)
  char_cols <- setdiff(cols, c(numeric_cols, "qa_metabolic_unit_verified"))
  for (col in char_cols) {
    row[[col]] <- NA_character_
  }
  row
}
