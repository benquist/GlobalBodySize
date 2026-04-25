dryad_trait_dictionary_path <- function() {
  candidates <- c(
    file.path("data", "trait_dictionary_starter.csv"),
    file.path("DryadPlantTraits", "data", "trait_dictionary_starter.csv"),
    file.path("..", "data", "trait_dictionary_starter.csv")
  )
  found <- Filter(file.exists, candidates)
  if (length(found)) found[[1L]] else candidates[[1L]]
}

dryad_read_trait_dictionary <- function(path = dryad_trait_dictionary_path()) {
  if (!file.exists(path)) {
    stop(sprintf("Trait dictionary not found at %s", path), call. = FALSE)
  }

  utils::read.csv(
    path,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}

dryad_canonical_name <- function(x) {
  out <- tolower(trimws(as.character(x)))
  out <- gsub("[^a-z0-9]+", "_", out)
  gsub("(^_+|_+$)", "", out)
}

dryad_trait_dictionary_lookup <- function(dictionary = dryad_read_trait_dictionary()) {
  lookup <- vector("list", 0)

  for (row_index in seq_len(nrow(dictionary))) {
    row <- dictionary[row_index, , drop = FALSE]
    aliases <- unlist(strsplit(row$aliases[[1]], ";", fixed = TRUE), use.names = FALSE)
    aliases <- unique(c(row$standardized_trait_name[[1]], aliases))
    alias_keys <- unique(dryad_canonical_name(aliases))

    for (alias_key in alias_keys) {
      lookup[[alias_key]] <- list(
        standardized_trait_name = row$standardized_trait_name[[1]],
        expected_unit_class = row$expected_unit_class[[1]],
        value_type = row$value_type[[1]],
        standard_unit = row$standard_unit[[1]],
        notes = row$notes[[1]]
      )
    }
  }

  lookup
}

dryad_standardize_trait_label <- function(raw_trait_name, lookup = dryad_trait_dictionary_lookup()) {
  key <- dryad_canonical_name(raw_trait_name)
  match <- lookup[[key]]

  if (is.null(match)) {
    return(list(
      standardized_trait_name = as.character(raw_trait_name),
      expected_unit_class = NA_character_,
      value_type = NA_character_,
      standard_unit = NA_character_,
      notes = "Trait not found in starter dictionary; retained as source label."
    ))
  }

  match
}
