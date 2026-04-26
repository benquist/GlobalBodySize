pcqa_or_local <- function(x, y) {
  fn <- get0("%||%", mode = "function", inherits = TRUE)
  if (!is.null(fn)) return(fn(x, y))
  if (is.null(x) || !length(x)) y else x
}

pcqa_is_blank_local <- function(x) {
  fn <- get0("pcqa_is_blank", mode = "function", inherits = TRUE)
  if (!is.null(fn)) return(fn(x))
  x_chr <- trimws(as.character(x))
  is.na(x) | !nzchar(x_chr)
}

pcqa_canonical_unit <- function(x) {
  raw <- tolower(trimws(as.character(x)))
  raw <- gsub("\\s+", "", raw)
  raw <- gsub("\\^", "", raw)
  raw <- gsub("µ", "u", raw, fixed = TRUE)
  ifelse(raw %in% c("", "na"), NA_character_, raw)
}

pcqa_build_dict_lookup <- function(dict) {
  wanted <- c(
    "standardized_trait_name", "value_type", "standard_unit", "expected_unit_class",
    "value_min", "value_max", "range_source"
  )
  missing <- setdiff(wanted, names(dict))
  if (length(missing)) {
    stop("Trait dictionary missing required columns: ", paste(missing, collapse = ", "), call. = FALSE)
  }

  trait_keys <- tolower(trimws(as.character(dict$standardized_trait_name)))
  trait_keys[is.na(trait_keys)] <- ""
  dup_idx <- duplicated(trait_keys) & nzchar(trait_keys)
  if (any(dup_idx)) {
    dup_keys <- unique(dict$standardized_trait_name[dup_idx])
    stop(
      "Trait dictionary has duplicated standardized_trait_name keys: ",
      paste(head(dup_keys, 10), collapse = ", "),
      if (length(dup_keys) > 10) " ..." else "",
      call. = FALSE
    )
  }

  dict_small <- dict[, wanted, drop = FALSE]
  names(dict_small) <- c(
    "trait_name", "dict_value_type", "dict_standard_unit", "dict_expected_unit_class",
    "dict_value_min", "dict_value_max", "dict_range_source"
  )
  dict_small
}

pcqa_unit_conversion <- function(trait_name, value_numeric, unit_original) {
  if (is.na(value_numeric) || is.na(trait_name) || !nzchar(trait_name)) {
    return(list(value = value_numeric, applied = "no", reason = "none"))
  }

  u <- pcqa_canonical_unit(unit_original)
  t <- tolower(trimws(as.character(trait_name)))

  if (is.na(u)) {
    return(list(value = value_numeric, applied = "no", reason = "missing_unit"))
  }

  if (t == "plant_height") {
    if (u == "mm") return(list(value = value_numeric * 0.001, applied = "yes", reason = "mm_to_m"))
    if (u == "cm") return(list(value = value_numeric * 0.01, applied = "yes", reason = "cm_to_m"))
  }

  if (t == "leaf_area") {
    if (u == "cm2") return(list(value = value_numeric * 100, applied = "yes", reason = "cm2_to_mm2"))
  }

  if (t == "specific_leaf_area") {
    if (u %in% c("cm2/g", "cm2perg", "cm2g", "cm2.g-1")) {
      return(list(value = value_numeric * 0.1, applied = "yes", reason = "cm2_per_g_to_mm2_per_mg"))
    }
  }

  if (t == "leaf_dry_matter_content") {
    if (u %in% c("g/g", "gperg", "g.g-1")) {
      return(list(value = value_numeric * 1000, applied = "yes", reason = "g_per_g_to_mg_per_g"))
    }
  }

  list(value = value_numeric, applied = "no", reason = "none")
}

pcqa_unit_matches_standard <- function(unit_original, unit_standard) {
  uo <- pcqa_canonical_unit(unit_original)
  us <- pcqa_canonical_unit(unit_standard)
  if (is.na(uo) || is.na(us)) return(TRUE)
  identical(uo, us)
}

pcqa_score_observations <- function(df, trait_dictionary) {
  dict_lookup <- pcqa_build_dict_lookup(trait_dictionary)
  scored <- merge(df, dict_lookup, by = "trait_name", all.x = TRUE, sort = FALSE)

  scored$range_min_ref <- suppressWarnings(as.numeric(scored$dict_value_min))
  scored$range_max_ref <- suppressWarnings(as.numeric(scored$dict_value_max))
  scored$range_source_ref <- scored$dict_range_source
  scored$range_reference_available <- !is.na(scored$range_min_ref) & !is.na(scored$range_max_ref)
  scored$invalid_reference_range <- scored$range_reference_available & (scored$range_max_ref <= scored$range_min_ref)

  observed_value_type <- pcqa_or_local(scored$value_type, rep(NA_character_, nrow(scored)))
  scored$is_numeric_trait <- (tolower(trimws(as.character(observed_value_type))) == "numeric") |
    (tolower(trimws(as.character(scored$dict_value_type))) == "numeric")

  scored$value_numeric <- suppressWarnings(as.numeric(scored$trait_value))
  scored$value_numeric_parse_ok <- ifelse(scored$is_numeric_trait, !is.na(scored$value_numeric), NA)

  conversion <- lapply(seq_len(nrow(scored)), function(i) {
    if (!isTRUE(scored$is_numeric_trait[[i]]) || !isTRUE(scored$value_numeric_parse_ok[[i]])) {
      return(list(value = NA_real_, applied = "no", reason = "none"))
    }
    pcqa_unit_conversion(scored$trait_name[[i]], scored$value_numeric[[i]], scored$unit[[i]])
  })

  scored$value_used_for_range_check <- vapply(conversion, function(x) x$value, numeric(1))
  scored$unit_conversion_applied <- vapply(conversion, function(x) x$applied, character(1))
  scored$unit_conversion_reason <- vapply(conversion, function(x) x$reason, character(1))

  scored$unit_original <- scored$unit
  scored$unit_standard <- ifelse(pcqa_is_blank_local(scored$dict_standard_unit), scored$standard_unit, scored$dict_standard_unit)

  scored$unit_match_standard <- mapply(pcqa_unit_matches_standard, scored$unit_original, scored$unit_standard)
  scored$unit_mismatch_no_conversion <- scored$is_numeric_trait & scored$value_numeric_parse_ok & !scored$unit_match_standard & scored$unit_conversion_applied == "no"

  assessable <- scored$is_numeric_trait &
    scored$value_numeric_parse_ok &
    scored$range_reference_available &
    !scored$invalid_reference_range &
    !is.na(scored$value_used_for_range_check)
  scored$in_reference_range <- ifelse(
    assessable,
    scored$value_used_for_range_check >= scored$range_min_ref & scored$value_used_for_range_check <= scored$range_max_ref,
    NA
  )

  scored$range_distance_abs <- NA_real_
  scored$range_distance_rel <- NA_real_
  scored$range_position <- "unassessable"

  for (i in which(assessable)) {
    val <- scored$value_used_for_range_check[[i]]
    lo <- scored$range_min_ref[[i]]
    hi <- scored$range_max_ref[[i]]
    width <- hi - lo

    if (val < lo) {
      dist_abs <- lo - val
      scored$range_position[[i]] <- "below"
      scored$range_distance_abs[[i]] <- dist_abs
      scored$range_distance_rel[[i]] <- if (is.finite(width) && width > 0) dist_abs / width else NA_real_
    } else if (val > hi) {
      dist_abs <- val - hi
      scored$range_position[[i]] <- "above"
      scored$range_distance_abs[[i]] <- dist_abs
      scored$range_distance_rel[[i]] <- if (is.finite(width) && width > 0) dist_abs / width else NA_real_
    } else {
      scored$range_position[[i]] <- "within"
      scored$range_distance_abs[[i]] <- 0
      scored$range_distance_rel[[i]] <- 0
    }
  }

  scored
}
