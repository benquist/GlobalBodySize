pcqa_is_blank_local <- function(x) {
  fn <- get0("pcqa_is_blank", mode = "function", inherits = TRUE)
  if (!is.null(fn)) return(fn(x))
  x_chr <- trimws(as.character(x))
  is.na(x) | !nzchar(x_chr)
}

pcqa_apply_triage <- function(scored) {
  trait_missing <- pcqa_is_blank_local(scored$trait_name)
  trait_unknown <- pcqa_is_blank_local(scored$dict_value_type)
  numeric_nonparseable <- scored$is_numeric_trait & (is.na(scored$value_numeric_parse_ok) | !scored$value_numeric_parse_ok)
  invalid_reference_range <- if ("invalid_reference_range" %in% names(scored)) as.logical(scored$invalid_reference_range) else rep(FALSE, nrow(scored))
  invalid_reference_range[is.na(invalid_reference_range)] <- FALSE
  severe_exceedance <- scored$range_position %in% c("below", "above") & !is.na(scored$range_distance_rel) & scored$range_distance_rel > 1
  mild_exceedance <- scored$range_position %in% c("below", "above") & !is.na(scored$range_distance_rel) & scored$range_distance_rel <= 1
  inferred_unit_used <- if ("inferred_unit" %in% names(scored)) as.logical(scored$inferred_unit) else rep(FALSE, nrow(scored))
  inferred_unit_used[is.na(inferred_unit_used)] <- FALSE

  no_reference_range <- scored$is_numeric_trait & !scored$range_reference_available
  unit_mismatch_no_conversion <- scored$unit_mismatch_no_conversion
  unit_mismatch_no_conversion[is.na(unit_mismatch_no_conversion)] <- FALSE

  scored$qa_decision <- "keep"
  scored$qa_decision_reason <- "in_range_structurally_valid"

  reject_idx <- trait_missing | trait_unknown | numeric_nonparseable | invalid_reference_range | unit_mismatch_no_conversion | severe_exceedance
  scored$qa_decision[reject_idx] <- "reject"
  scored$qa_decision_reason[reject_idx] <- ifelse(
    trait_missing[reject_idx], "trait_missing",
    ifelse(
      trait_unknown[reject_idx], "trait_not_in_dictionary",
      ifelse(
        numeric_nonparseable[reject_idx], "numeric_trait_nonparseable",
        ifelse(
          invalid_reference_range[reject_idx], "invalid_reference_range",
          ifelse(unit_mismatch_no_conversion[reject_idx], "unit_mismatch_no_conversion", "severe_exceedance")
        )
      )
    )
  )

  review_idx <- !reject_idx & (mild_exceedance | inferred_unit_used | no_reference_range)
  scored$qa_decision[review_idx] <- "review"
  scored$qa_decision_reason[review_idx] <- ifelse(
    mild_exceedance[review_idx], "mild_exceedance",
    ifelse(inferred_unit_used[review_idx], "inferred_unit_used", "no_reference_range")
  )

  keep <- scored[scored$qa_decision == "keep", , drop = FALSE]
  review <- scored[scored$qa_decision == "review", , drop = FALSE]
  reject <- scored[scored$qa_decision == "reject", , drop = FALSE]

  triage_summary <- aggregate(
    x = list(rows = scored$qa_decision),
    by = list(qa_decision = scored$qa_decision),
    FUN = length
  )
  triage_summary$pct <- round(100 * triage_summary$rows / nrow(scored), 3)

  trait_name_grp <- ifelse(pcqa_is_blank_local(scored$trait_name), "__NA_TRAIT_NAME__", scored$trait_name)
  qa_decision_grp <- ifelse(pcqa_is_blank_local(scored$qa_decision), "__NA_QA_DECISION__", scored$qa_decision)
  range_position_grp <- ifelse(pcqa_is_blank_local(scored$range_position), "__NA_RANGE_POSITION__", scored$range_position)
  unit_conversion_grp <- ifelse(pcqa_is_blank_local(scored$unit_conversion_applied), "__NA_UNIT_CONVERSION_APPLIED__", scored$unit_conversion_applied)

  trait_diagnostics <- aggregate(
    x = list(rows = scored$trait_name),
    by = list(
      trait_name = trait_name_grp,
      qa_decision = qa_decision_grp,
      range_position = range_position_grp,
      unit_conversion_applied = unit_conversion_grp
    ),
    FUN = length
  )
  trait_diagnostics <- trait_diagnostics[order(trait_diagnostics$trait_name, trait_diagnostics$qa_decision), , drop = FALSE]

  list(
    scored = scored,
    keep = keep,
    review = review,
    reject = reject,
    triage_summary = triage_summary,
    trait_diagnostics = trait_diagnostics
  )
}
