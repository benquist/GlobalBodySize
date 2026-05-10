## GlobalBodySize/R/qa_checks.R
## Quality assurance checks for the compiled GlobalBodySize body mass table
## Implements range checks, unit checks, outlier detection, and DwC field validation
## Based on merow-ecology advisory + biodiversity-informatics-checker audit

## ---- Load schema helpers ----------------------------------------------------
## Assumes body_mass_schema.R is sourced first

## ---- 1. Range check: plausible mass in grams by taxonomic group -------------

run_range_check <- function(compiled_df) {
  limits <- globalsize_mass_range_limits()
  results <- vector("logical", nrow(compiled_df))
  notes   <- vector("character", nrow(compiled_df))

  for (i in seq_len(nrow(compiled_df))) {
    grp  <- compiled_df$input_taxonomic_group[i]
    mass <- compiled_df$mass_g[i]

    if (is.na(mass) || is.na(grp)) {
      results[i] <- NA
      notes[i]   <- "mass or group is NA"
      next
    }

    row <- limits[limits$group == grp, , drop = FALSE]
    if (nrow(row) == 0) {
      results[i] <- NA
      notes[i]   <- paste("no range limits defined for group:", grp)
      next
    }

    lo <- row$min_g[1]
    hi <- row$max_g[1]

    in_range <- (is.na(lo) || mass >= lo) & (is.na(hi) || mass <= hi)
    results[i] <- in_range
    if (!in_range) {
      notes[i] <- sprintf("mass_g=%g outside [%s, %s] for group=%s",
                          mass,
                          if (is.na(lo)) "NA" else lo,
                          if (is.na(hi)) "NA" else hi,
                          grp)
    }
  }

  compiled_df$range_check_pass <- results
  compiled_df$qa_note <- ifelse(nzchar(notes), notes, compiled_df$qa_note %||% NA_character_)
  compiled_df
}

## ---- 2. Unit consistency check ----------------------------------------------
## mass_g must be numeric after any conversion; mass_type must be in controlled vocab

run_unit_check <- function(compiled_df) {
  valid_types <- globalsize_mass_type_vocab()
  compiled_df$unit_check_pass <- vapply(seq_len(nrow(compiled_df)), function(i) {
    m <- compiled_df$mass_g[i]
    t <- compiled_df$mass_type[i]
    is.numeric(m) && !is.na(m) && m > 0 &&
      !is.na(t) && t %in% valid_types
  }, logical(1))
  compiled_df
}

## ---- 3. Mandatory field check -----------------------------------------------
## Fields that must be non-NA for a row to be considered QA-pass

mandatory_fields <- function() {
  c("source_id", "verbatim_taxon_name", "input_taxonomic_group",
    "mass_g", "mass_type", "measurement_method", "life_stage", "sex",
    "basis_of_record", "measurement_id", "backbone_version",
    "query_timestamp_utc", "source_doi")
}

run_mandatory_field_check <- function(compiled_df) {
  mf <- mandatory_fields()
  present <- intersect(mf, names(compiled_df))
  missing_cols <- setdiff(mf, names(compiled_df))
  if (length(missing_cols) > 0) {
    warning("Mandatory columns missing from compiled table: ",
            paste(missing_cols, collapse = ", "))
  }

  compiled_df$mandatory_pass <- apply(compiled_df[, present, drop = FALSE], 1, function(row) {
    all(!is.na(row) & nzchar(as.character(row)))
  })
  compiled_df
}

## ---- 4. Statistical outlier detection (hierarchical log-scale) --------------
## Runs at the finest available taxonomic level with n >= min_n.
## Preference order: order > family > input_taxonomic_group (broad class).
## The broad-class IQR is nearly powerless for fish and reptiles (spans 9 log units)
## — hierarchical detection is required to catch meaningful outliers.
## Conservative: flag only, do not remove.

run_outlier_check <- function(compiled_df, iqr_threshold = 3, min_n = 30) {
  compiled_df$outlier_flag  <- FALSE
  compiled_df$outlier_level <- NA_character_   # which level triggered the flag

  ## Hierarchy from finest to broadest; `order` and `family` come from taxonomy reconciliation
  levels <- c("order", "family", "input_taxonomic_group")
  available_levels <- intersect(levels, names(compiled_df))

  for (level in available_levels) {
    groups <- unique(compiled_df[[level]])
    groups <- groups[!is.na(groups)]

    for (grp in groups) {
      ## Only consider unflagged rows in this group
      idx <- which(
        compiled_df[[level]] == grp &
        !is.na(compiled_df$mass_g) &
        compiled_df$mass_g > 0 &
        !compiled_df$outlier_flag
      )
      if (length(idx) < min_n) next

      lm  <- log10(compiled_df$mass_g[idx])
      iqr <- IQR(lm, na.rm = TRUE)
      if (iqr == 0) next

      flags <- abs(lm - median(lm)) > iqr_threshold * iqr
      newly_flagged <- idx[flags]
      compiled_df$outlier_flag[newly_flagged]  <- TRUE
      compiled_df$outlier_level[newly_flagged] <- level
    }
  }

  compiled_df
}

## ---- 5. Assign overall QA status --------------------------------------------

run_qa_status <- function(compiled_df) {
  compiled_df$qa_status <- dplyr::case_when(
    !compiled_df$mandatory_pass                   ~ "fail",
    !is.na(compiled_df$range_check_pass) &
      !compiled_df$range_check_pass               ~ "fail",
    !is.na(compiled_df$unit_check_pass) &
      !compiled_df$unit_check_pass                ~ "fail",
    isTRUE(compiled_df$outlier_flag)              ~ "needs_review",
    isTRUE(compiled_df$cross_group_collision_flag) ~ "needs_review",
    TRUE                                          ~ "pass"
  )
  compiled_df
}

## ---- Master QA runner -------------------------------------------------------

run_all_qa <- function(compiled_df, verbose = TRUE, report_dir = "reports") {
  compiled_df <- run_range_check(compiled_df)
  compiled_df <- run_unit_check(compiled_df)
  compiled_df <- run_mandatory_field_check(compiled_df)
  compiled_df <- run_outlier_check(compiled_df)
  compiled_df <- run_qa_status(compiled_df)

  n_pass   <- sum(compiled_df$qa_status == "pass",         na.rm = TRUE)
  n_review <- sum(compiled_df$qa_status == "needs_review", na.rm = TRUE)
  n_fail   <- sum(compiled_df$qa_status == "fail",         na.rm = TRUE)
  n_out    <- sum(compiled_df$outlier_flag,                na.rm = TRUE)
  n        <- nrow(compiled_df)

  if (verbose) {
    cat(sprintf("QA Summary — %d rows\n", n))
    cat(sprintf("  pass:         %d (%.1f%%)\n", n_pass,   100 * n_pass   / n))
    cat(sprintf("  needs_review: %d (%.1f%%)\n", n_review, 100 * n_review / n))
    cat(sprintf("  fail:         %d (%.1f%%)\n", n_fail,   100 * n_fail   / n))
    cat(sprintf("  outlier_flag: %d\n", n_out))
  }

  ## Write QA summary to timestamped report file — required for audit trail
  dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
  qa_summary <- data.frame(
    run_timestamp      = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    n_total            = n,
    n_pass             = n_pass,
    n_needs_review     = n_review,
    n_fail             = n_fail,
    n_outlier_flag     = n_out,
    pct_pass           = round(100 * n_pass / n, 1),
    stringsAsFactors   = FALSE
  )
  report_path <- file.path(
    report_dir,
    sprintf("qa_report_%s.csv", format(Sys.Date(), "%Y%m%d"))
  )
  data.table::fwrite(qa_summary, report_path)
  if (verbose) message("QA report written: ", report_path)

  compiled_df
}

`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x
