canonicalize_header <- function(x) {
  out <- tolower(trimws(x))
  out <- gsub("[^a-z0-9]+", "_", out)
  gsub("(^_+|_+$)", "", out)
}

infer_measurement_unit <- function(source_col_name) {
  nm <- canonicalize_header(source_col_name)
  if (grepl("_mm$|millimeter|millimetre|_millimeters?$", nm)) return("mm")
  if (grepl("_cm$|centimeter|centimetre|dbh", nm)) return("cm")
  if (grepl("_in$|inch|inches", nm)) return("in")
  if (grepl("_m$|meter|metre", nm)) return("m")
  NA_character_
}

load_header_synonyms <- local({
  cache <- list()

  function(path = "inst/dictionaries/header_synonyms.csv") {
    if (!is.null(cache[[path]])) {
      return(cache[[path]])
    }
    if (!file.exists(path)) {
      stop("Header synonym dictionary not found: ", path)
    }

    syn <- utils::read.csv(path, stringsAsFactors = FALSE)
    needed <- c("alias", "dwc_term")
    if (!all(needed %in% names(syn))) {
      stop("Synonym dictionary must contain columns: alias, dwc_term")
    }

    syn$alias_canonical <- canonicalize_header(syn$alias)
    cache[[path]] <<- syn
    syn
  }
})

# Vectorized BIEN field suggestion for a canonical name vector.
# Uses pre-cached lookup tables from bien_pipeline_helpers.R.
.suggest_bien_fields_vec <- function(src_canonical) {
  tbl       <- .bien_lookup_tables()
  exact_idx <- match(src_canonical, tbl$bien_norm)
  alias_hit <- tbl$alias_rev[src_canonical]           # named vector; NA where no alias match

  field  <- ifelse(!is.na(exact_idx), tbl$bien_ref[exact_idx],
             ifelse(!is.na(alias_hit), as.character(alias_hit), ""))
  conf   <- ifelse(!is.na(exact_idx), "high",
             ifelse(!is.na(alias_hit), "medium", "low"))
  reason <- ifelse(!is.na(exact_idx), "exact_header_match",
             ifelse(!is.na(alias_hit), "alias_match", "no_bien_match"))

  list(field = field, confidence = conf, reason = reason)
}

suggest_dwc_mapping <- function(df, dictionary_path = "inst/dictionaries/header_synonyms.csv") {
  if (!is.data.frame(df)) stop("df must be a data.frame")

  src <- names(df)
  if (length(src) == 0) {
    return(data.frame(
      source_column = character(0), suggested_dwc_term = character(0),
      confidence = character(0), suggested_bien_field = character(0),
      bien_confidence = character(0), bien_reason = character(0),
      stringsAsFactors = FALSE
    ))
  }

  syn           <- load_header_synonyms(dictionary_path)
  src_canonical <- canonicalize_header(src)

  # O(1) per-column dictionary lookup via named vector (replaces per-column table scan)
  syn_lookup     <- setNames(syn$dwc_term, syn$alias_canonical)
  matched_dwc    <- syn_lookup[src_canonical]          # NA where no match
  has_dbh        <- grepl("dbh|diameter", src_canonical)

  suggested_dwc_term <- ifelse(!is.na(matched_dwc), matched_dwc,
                               ifelse(has_dbh, "measurementValue", ""))
  confidence         <- ifelse(!is.na(matched_dwc), "high",
                               ifelse(has_dbh, "medium", "low"))

  # BIEN suggestions: fully vectorized, single pass over all columns
  bien_hits <- .suggest_bien_fields_vec(src_canonical)

  data.frame(
    source_column      = src,
    suggested_dwc_term = suggested_dwc_term,
    confidence         = confidence,
    suggested_bien_field = bien_hits$field,
    bien_confidence    = bien_hits$confidence,
    bien_reason        = bien_hits$reason,
    stringsAsFactors   = FALSE
  )
}

apply_dwc_mapping <- function(df, mapping_df) {
  if (!is.data.frame(df)) {
    stop("df must be a data.frame")
  }
  if (!is.data.frame(mapping_df) || !all(c("source_column", "dwc_term") %in% names(mapping_df))) {
    stop("mapping_df must include source_column and dwc_term")
  }

  valid <- nzchar(mapping_df$dwc_term) & (mapping_df$source_column %in% names(df))
  valid_map <- mapping_df[valid, , drop = FALSE]
  col_data <- setNames(
    lapply(valid_map$source_column, function(src) df[[src]]),
    valid_map$dwc_term
  )
  out <- if (length(col_data) > 0) {
    as.data.frame(col_data, stringsAsFactors = FALSE, check.names = FALSE)
  } else {
    df[, 0L, drop = FALSE]
  }

  if (!"occurrenceID" %in% names(out)) {
    out$occurrenceID <- paste0("hist-", seq_len(nrow(df)))
  }
  if (!"basisOfRecord" %in% names(out)) {
    out$basisOfRecord <- "HumanObservation"
  }
  if (!"occurrenceStatus" %in% names(out)) {
    out$occurrenceStatus <- "present"
  }

  mapped_measurement_source <- mapping_df$source_column[mapping_df$dwc_term == "measurementValue"]
  mapped_measurement_source <- mapped_measurement_source[mapped_measurement_source %in% names(df)]
  measurement_source_name <- if (length(mapped_measurement_source) > 0) mapped_measurement_source[[1]] else NA_character_

  if ("measurementValue" %in% names(out) && !"measurementType" %in% names(out)) {
    if (!is.na(measurement_source_name) && grepl("dbh|diameter", canonicalize_header(measurement_source_name))) {
      out$measurementType <- "diameter_at_breast_height"
    } else {
      out$measurementType <- "measurement"
    }
  }

  if ("measurementValue" %in% names(out) && !"measurementUnit" %in% names(out)) {
    guessed_unit <- if (!is.na(measurement_source_name)) infer_measurement_unit(measurement_source_name) else NA_character_
    out$measurementUnit <- if (!is.na(guessed_unit)) guessed_unit else "cm"
  }

  out
}
