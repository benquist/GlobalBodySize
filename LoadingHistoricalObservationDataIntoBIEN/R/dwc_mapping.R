canonicalize_header <- function(x) {
  out <- tolower(trimws(x))
  out <- gsub("[^a-z0-9]+", "_", out)
  gsub("(^_+|_+$)", "", out)
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

  suggestions <- lapply(seq_along(src), function(i) {
    hits <- syn[syn$alias_canonical == src_canonical[i], , drop = FALSE]
    if (nrow(hits) > 0) {
      data.frame(
        source_column = src[i],
        suggested_dwc_term = hits$dwc_term[1],
        confidence = "high",
        stringsAsFactors = FALSE
      )
    } else {
      data.frame(
        source_column = src[i],
        suggested_dwc_term = "",
        confidence = "low",
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

  out
}
