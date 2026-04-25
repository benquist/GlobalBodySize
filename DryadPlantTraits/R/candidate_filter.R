dryad_count_term_hits <- function(text, terms) {
  if (!length(terms) || !nzchar(text)) {
    return(0L)
  }
  sum(vapply(terms, function(term) grepl(term, text, fixed = TRUE), logical(1)))
}

dryad_score_candidate_dataset <- function(title, abstract, source_subjects, signal_terms = dryad_candidate_signal_terms()) {
  text_blob <- paste(title, abstract, source_subjects, sep = " ")
  text_blob <- tolower(gsub("\\s+", " ", text_blob))

  plant_hits <- dryad_count_term_hits(text_blob, signal_terms$plant)
  trait_hits <- dryad_count_term_hits(text_blob, signal_terms$trait)
  measurement_hits <- dryad_count_term_hits(text_blob, signal_terms$measurement)
  exclude_hits <- dryad_count_term_hits(text_blob, signal_terms$exclude)

  score <- (plant_hits * 3L) + (trait_hits * 4L) + (measurement_hits * 2L) - (exclude_hits * 5L)
  include_candidate <- plant_hits > 0L && trait_hits > 0L && score >= 6L

  rationale_parts <- c(
    sprintf("plant_hits=%s", plant_hits),
    sprintf("trait_hits=%s", trait_hits),
    sprintf("measurement_hits=%s", measurement_hits),
    sprintf("exclude_hits=%s", exclude_hits)
  )

  list(
    candidate_score = score,
    candidate_keep = include_candidate,
    candidate_rationale = paste(rationale_parts, collapse = "; "),
    plant_signal_count = plant_hits,
    trait_signal_count = trait_hits,
    measurement_signal_count = measurement_hits,
    exclude_signal_count = exclude_hits
  )
}

dryad_score_candidate_table <- function(dataset_table) {
  if (!nrow(dataset_table)) {
    return(dataset_table)
  }

  score_rows <- lapply(seq_len(nrow(dataset_table)), function(index) {
    score <- dryad_score_candidate_dataset(
      title = dataset_table$title[[index]],
      abstract = dataset_table$abstract[[index]],
      source_subjects = dataset_table$source_subjects[[index]]
    )
    as.data.frame(score, stringsAsFactors = FALSE)
  })

  cbind(dataset_table, do.call(rbind, score_rows), stringsAsFactors = FALSE)
}
