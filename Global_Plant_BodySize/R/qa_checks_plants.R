## Global_Plant_BodySize/R/qa_checks_plants.R
## Quality assurance checks for plant body size trait records.
## Implements range checks, unit checks, and log-scale outlier detection.
##
## Reasoning basis:
##   - Range limits from plantsize_range_limits() in plant_size_schema.R
##   - Outlier detection: log10-scale z-score within (growth_form × higher_plant_group)
##     Flag: |z| > 3 (approximately 1-in-1000 chance under log-normal assumption)
##   - Unit check: trait_unit_canonical must be in expected set for measurement_type
##   - Records failing QA are FLAGGED, not deleted; downstream scripts filter by flag
##
## REWRITTEN 2026-05-12: fully vectorized via data.table joins and by-group
## operations. Original row-loop implementation was O(n) sequential and could not
## complete on 10M+ records in reasonable time.
##
## Written by: Global_Plant_BodySize pipeline (ecology-user agent, 2026-05-11)

## ---- Dependencies -----------------------------------------------------------
## Assumes plant_size_schema.R is sourced first (provides range limits, vocab)
suppressPackageStartupMessages(library(data.table))

## ---- 1. Range check: plausible height/DBH by growth form -------------------
## Vectorized via data.table merge against the limits lookup table.
## Adds/updates columns: range_check_pass (logical), qa_note (character)

run_range_check_plants <- function(trait_df) {
  limits <- plantsize_range_limits()

  ## Work as data.table; preserve original class on exit
  was_df <- is.data.frame(trait_df) && !is.data.table(trait_df)
  dt <- as.data.table(trait_df)

  ## Initialise output columns
  dt[, range_check_pass := NA_integer_]  # will be coerced to logical after assignment
  if (!"qa_note" %in% names(dt)) dt[, qa_note := NA_character_] else dt[, qa_note := as.character(qa_note)]

  ## Only range-check height_m and dbh_cm
  size_idx <- dt[, measurement_type %in% c("height_m", "dbh_cm")]

  if (any(size_idx)) {
    sub <- dt[size_idx]

    ## Resolve unknown growth forms to "unknown" for lookup
    lim_dt <- as.data.table(limits)
    known_gf <- lim_dt$growth_form_canonical
    sub[, gf_key := ifelse(
      is.na(growth_form_canonical_qa) | !growth_form_canonical_qa %in% known_gf,
      "unknown", growth_form_canonical_qa
    )]

    ## Merge limits once
    sub <- merge(sub, lim_dt, by.x = "gf_key", by.y = "growth_form_canonical",
                 all.x = TRUE)

    ## Vectorized range evaluation
    sub[measurement_type == "height_m",
        range_check_pass := (!is.na(trait_value_numeric)) &
                            (is.na(min_height_m) | trait_value_numeric >= min_height_m) &
                            (is.na(max_height_m) | trait_value_numeric <= max_height_m)]

    sub[measurement_type == "dbh_cm",
        range_check_pass := (!is.na(trait_value_numeric)) &
                            (is.na(min_dbh_cm) | trait_value_numeric >= min_dbh_cm) &
                            (is.na(max_dbh_cm) | trait_value_numeric <= max_dbh_cm)]

    ## Mark NA values explicitly
    sub[is.na(trait_value_numeric), `:=`(range_check_pass = NA,
                                          qa_note = "trait_value_numeric is NA")]

    ## Build failure notes for out-of-range records (vectorized sprintf)
    sub[measurement_type == "height_m" & range_check_pass %in% FALSE,
        qa_note := sprintf("%s=%.4g outside [%s,%s] gf=%s",
                           measurement_type, trait_value_numeric,
                           fifelse(is.na(min_height_m), "NA", as.character(min_height_m)),
                           fifelse(is.na(max_height_m), "NA", as.character(max_height_m)),
                           gf_key)]

    sub[measurement_type == "dbh_cm" & range_check_pass %in% FALSE,
        qa_note := sprintf("%s=%.4g outside [%s,%s] gf=%s",
                           measurement_type, trait_value_numeric,
                           fifelse(is.na(min_dbh_cm), "NA", as.character(min_dbh_cm)),
                           fifelse(is.na(max_dbh_cm), "NA", as.character(max_dbh_cm)),
                           gf_key)]

    ## Drop temporary columns and write back into dt via row index
    extra_cols <- setdiff(names(sub), c(names(dt), "gf_key"))
    if (length(extra_cols)) sub[, (extra_cols) := NULL]
    if ("gf_key" %in% names(sub)) sub[, gf_key := NULL]

    dt[size_idx, `:=`(range_check_pass = sub$range_check_pass,
                       qa_note          = sub$qa_note)]
  }

  if (was_df) as.data.frame(dt) else dt
}

## ---- 2. Unit check: canonical unit is appropriate for measurement type -----
## Fully vectorized using fcase / data.table assignment.
## Adds/updates: unit_check_pass (logical)

run_unit_check_plants <- function(trait_df) {
  was_df <- is.data.frame(trait_df) && !is.data.table(trait_df)
  dt <- as.data.table(trait_df)

  dt[, unit_check_pass := fcase(
    measurement_type == "height_m",   trait_unit_canonical == "m",
    measurement_type == "dbh_cm",     trait_unit_canonical == "cm",
    measurement_type == "growth_form", trait_unit_canonical == "categorical",
    default = NA
  )]

  if (was_df) as.data.frame(dt) else dt
}

## ---- 3. Log-scale outlier detection within growth form × higher_plant_group -
## Computes log10(value) z-score within each (growth_form_canonical_qa,
## higher_plant_group) stratum. Flags |z| > 3 as outlier_flag = TRUE.
## Groups with fewer than 5 records get outlier_flag = NA (insufficient basis).
## Vectorized: one by-group pass using data.table.
## Adds/updates: outlier_flag (logical)

run_outlier_detection_plants <- function(trait_df,
                                         measurement_type_filter = "height_m") {
  was_df <- is.data.frame(trait_df) && !is.data.table(trait_df)
  dt <- as.data.table(trait_df)

  if (!"outlier_flag" %in% names(dt)) dt[, outlier_flag := NA]

  ## Subset to positive numeric records of the target measurement type
  idx <- dt[, .I[measurement_type == measurement_type_filter &
                 !is.na(trait_value_numeric) &
                 trait_value_numeric > 0]]

  if (length(idx) == 0) return(if (was_df) as.data.frame(dt) else dt)

  ## Log-transform
  dt[idx, log_val := log10(trait_value_numeric)]

  ## Compute group mean/sd and z-score in one by-group pass
  dt[idx,
     `:=`(
       grp_n  = .N,
       grp_mu = mean(log_val, na.rm = TRUE),
       grp_sd = sd(log_val,   na.rm = TRUE)
     ),
     by = .(growth_form_canonical_qa, higher_plant_group)]

  ## Flag: NA if group < 5; FALSE/TRUE otherwise
  dt[idx,
     outlier_flag := fcase(
       grp_n < 5,                   NA,
       is.na(grp_sd) | grp_sd == 0, FALSE,
       default = abs(log_val - grp_mu) / grp_sd > 3
     )]

  ## Clean temp columns
  dt[, c("log_val", "grp_n", "grp_mu", "grp_sd") := NULL]

  if (was_df) as.data.frame(dt) else dt
}

## ---- Master QA runner -------------------------------------------------------
## Runs all three QA checks in sequence.
## Expects trait_df to have growth_form_canonical_qa column joined from
## Stage 5 (reconcile_growth_form.R).

run_qa_plants <- function(trait_df) {
  trait_df <- run_range_check_plants(trait_df)
  trait_df <- run_unit_check_plants(trait_df)

  ## Run outlier detection separately for height and DBH
  trait_df <- run_outlier_detection_plants(trait_df, "height_m")
  trait_df <- run_outlier_detection_plants(trait_df, "dbh_cm")

  trait_df
}

## ---- QA pass rate reporter --------------------------------------------------
report_qa_summary <- function(trait_df) {
  cat("=== QA Summary ===\n")
  cat(sprintf("  Total records:         %d\n", nrow(trait_df)))

  n_range <- sum(!is.na(trait_df$range_check_pass))
  n_pass  <- sum(trait_df$range_check_pass %in% TRUE, na.rm = TRUE)
  cat(sprintf("  Range check (n=%d):  %d pass (%.1f%%)\n",
              n_range, n_pass, 100 * n_pass / max(n_range, 1)))

  n_unit  <- sum(!is.na(trait_df$unit_check_pass))
  n_upass <- sum(trait_df$unit_check_pass %in% TRUE, na.rm = TRUE)
  cat(sprintf("  Unit check  (n=%d):  %d pass (%.1f%%)\n",
              n_unit, n_upass, 100 * n_upass / max(n_unit, 1)))

  n_out   <- sum(!is.na(trait_df$outlier_flag))
  n_flag  <- sum(trait_df$outlier_flag %in% TRUE, na.rm = TRUE)
  cat(sprintf("  Outlier flag (n=%d): %d flagged (%.1f%%)\n",
              n_out, n_flag, 100 * n_flag / max(n_out, 1)))

  invisible(trait_df)
}
