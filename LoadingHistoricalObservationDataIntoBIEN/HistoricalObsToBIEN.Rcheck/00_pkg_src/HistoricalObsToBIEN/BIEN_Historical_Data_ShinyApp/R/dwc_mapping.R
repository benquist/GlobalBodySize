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

load_header_synonyms <- function(path = "inst/dictionaries/header_synonyms.csv") {
  if (!file.exists(path)) {
    stop("Header synonym dictionary not found: ", path)
  }

  syn <- utils::read.csv(path, stringsAsFactors = FALSE)
  needed <- c("alias", "dwc_term")
  if (!all(needed %in% names(syn))) {
    stop("Synonym dictionary must contain columns: alias, dwc_term")
  }

  syn$alias_canonical <- canonicalize_header(syn$alias)
  syn
}

suggest_dwc_mapping <- function(df, dictionary_path = "inst/dictionaries/header_synonyms.csv") {
  if (!is.data.frame(df)) {
    stop("df must be a data.frame")
  }

  syn <- load_header_synonyms(dictionary_path)
  src <- names(df)
  src_canonical <- canonicalize_header(src)
  bien_reference_fields <- get_bien_reference_fields()

  suggestions <- lapply(seq_along(src), function(i) {
    hits <- syn[syn$alias_canonical == src_canonical[i], , drop = FALSE]
    bien_hit <- suggest_bien_field(src[i], bien_reference_fields = bien_reference_fields)
    if (nrow(hits) > 0) {
      data.frame(
        source_column = src[i],
        suggested_dwc_term = hits$dwc_term[1],
        confidence = "high",
        suggested_bien_field = bien_hit$field,
        bien_confidence = bien_hit$confidence,
        bien_reason = bien_hit$reason,
        stringsAsFactors = FALSE
      )
    } else {
      inferred_dwc <- ""
      inferred_conf <- "low"
      if (grepl("dbh|diameter", src_canonical[i])) {
        inferred_dwc <- "measurementValue"
        inferred_conf <- "medium"
      }

      data.frame(
        source_column = src[i],
        suggested_dwc_term = inferred_dwc,
        confidence = inferred_conf,
        suggested_bien_field = bien_hit$field,
        bien_confidence = bien_hit$confidence,
        bien_reason = bien_hit$reason,
        stringsAsFactors = FALSE
      )
    }
  })

  do.call(rbind, suggestions)
}

apply_dwc_mapping <- function(df, mapping_df) {
  if (!is.data.frame(df)) {
    stop("df must be a data.frame")
  }
  if (!is.data.frame(mapping_df) || !all(c("source_column", "dwc_term") %in% names(mapping_df))) {
    stop("mapping_df must include source_column and dwc_term")
  }

  out <- df[, 0, drop = FALSE]
  for (i in seq_len(nrow(mapping_df))) {
    src <- mapping_df$source_column[i]
    dwc <- mapping_df$dwc_term[i]

    if (!nzchar(dwc) || !src %in% names(df)) {
      next
    }

    out[[dwc]] <- df[[src]]
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
