pcqa_is_blank_local <- function(x) {
  fn <- get0("pcqa_is_blank", mode = "function", inherits = TRUE)
  if (!is.null(fn)) return(fn(x))
  x_chr <- trimws(as.character(x))
  is.na(x) | !nzchar(x_chr)
}

pcqa_binomial_ok_local <- function(x) {
  fn <- get0("pcqa_binomial_ok", mode = "function", inherits = TRUE)
  if (!is.null(fn)) return(fn(x))
  x_chr <- trimws(as.character(x))
  grepl("^[A-Z][A-Za-z.-]+\\s+[a-z][A-Za-z.-]+$", x_chr)
}

pcqa_apply_species_gate <- function(df) {
  if (!nrow(df)) {
    summary <- data.frame(
      stage = "species_gate",
      rows_input = 0L,
      rows_kept = 0L,
      rows_dropped = 0L,
      pct_kept = 0,
      pct_dropped = 0,
      stringsAsFactors = FALSE
    )
    return(list(kept = df, dropped = df, summary = summary))
  }

  species <- if ("scrubbed_species_binomial" %in% names(df)) df$scrubbed_species_binomial else rep(NA_character_, nrow(df))
  species_non_blank <- !pcqa_is_blank_local(species)
  species_binomial <- pcqa_binomial_ok_local(species)
  keep_idx <- species_non_blank & species_binomial

  kept <- df[keep_idx, , drop = FALSE]
  dropped <- df[!keep_idx, , drop = FALSE]

  dropped$species_gate_reason <- ifelse(
    !species_non_blank[!keep_idx],
    "species_missing",
    "species_not_simple_binomial"
  )

  summary <- data.frame(
    stage = "species_gate",
    rows_input = nrow(df),
    rows_kept = nrow(kept),
    rows_dropped = nrow(dropped),
    pct_kept = round(100 * nrow(kept) / nrow(df), 3),
    pct_dropped = round(100 * nrow(dropped) / nrow(df), 3),
    stringsAsFactors = FALSE
  )

  list(kept = kept, dropped = dropped, summary = summary)
}
