## Global_Plant_BodySize/scripts/07_summarize.R
## Stage 7: Aggregate QA-passing trait records to species-level summaries.
##
## For height and DBH separately, computes per species:
##   n, mean, median, sd, min, max, cv, confidence_tier
##
## Only records with range_check_pass = TRUE AND unit_check_pass = TRUE
## are included in summary statistics. Outlier-flagged records ARE included
## by default but can be excluded by setting EXCLUDE_OUTLIERS = TRUE below.
## This choice should be documented in any publication using this database.
##
## Input:
##   output/bien_height_qa.csv
##   output/bien_dbh_qa.csv
##   output/species_growth_form.csv
##
## Output:
##   output/plant_size_summary.csv — one row per species with all size metrics
##
## Run from project root:
##   Rscript scripts/07_summarize.R

EXCLUDE_OUTLIERS <- FALSE   # Set TRUE to exclude outlier-flagged records from summaries

if (basename(getwd()) == "scripts") setwd("..")

library(data.table)
source("R/plant_size_schema.R")

## ---- Helper: compute species-level stats for one trait file ----------------
## measurement_col: column name for numeric value (trait_value_numeric)
## prefix:          output column prefix (e.g. "height_m" or "dbh_cm")

summarize_trait <- function(qa_file, measurement_col = "trait_value_numeric",
                            prefix = "height_m") {
  if (!file.exists(qa_file)) {
    message("[Stage 7] Skipping (not found): ", qa_file)
    return(NULL)
  }

  dt <- fread(qa_file, data.table = TRUE)
  message("[Stage 7] Loaded: ", qa_file, " (", nrow(dt), " records)")

  ## Filter to QA-passing records
  dt <- dt[range_check_pass == TRUE & unit_check_pass == TRUE]

  if (EXCLUDE_OUTLIERS) {
    dt <- dt[is.na(outlier_flag) | outlier_flag == FALSE]
    message("  Outlier exclusion: ON")
  } else {
    message("  Outlier exclusion: OFF (outlier-flagged records included in summary)")
  }

  dt <- dt[!is.na(get(measurement_col)) & is.finite(get(measurement_col)) &
             get(measurement_col) > 0]
  message("  Records after QA filter: ", nrow(dt))

  if (nrow(dt) == 0) {
    message("  No valid records for: ", prefix)
    return(NULL)
  }

  ## Vectorized species-level aggregation via data.table
  out <- dt[, {
    v  <- get(measurement_col)
    n  <- .N
    mn <- mean(v)
    md <- median(v)
    sg <- if (.N > 1) sd(v) else NA_real_
    mi <- min(v)
    mx <- max(v)
    cv <- if (!is.na(sg) && mn != 0) sg / mn else NA_real_
    list(
      n          = n,
      mean       = mn,
      median     = md,
      sd         = sg,
      min        = mi,
      max        = mx,
      cv         = cv,
      confidence = plantsize_confidence_tier(n)
    )
  }, by = verbatim_species_name]

  ## Rename columns with prefix
  setnames(out,
           c("n", "mean", "median", "sd", "min", "max", "cv", "confidence"),
           paste0(prefix, c("_n", "_mean", "_median", "_sd", "_min", "_max", "_cv", "_confidence")))
  setnames(out, "verbatim_species_name", "species_name")

  as.data.frame(out)
}

## ---- Compute height and DBH summaries -------------------------------------
ht_summ <- summarize_trait("output/bien_height_qa.csv",
                           prefix = "height_m")
db_summ <- summarize_trait("output/bien_dbh_qa.csv",
                           prefix = "dbh_cm")

## ---- Load growth form species table ----------------------------------------
gf_file <- "output/species_growth_form.csv"
stopifnot(file.exists(gf_file))
gf <- fread(gf_file, data.table = FALSE)
names(gf)[names(gf) == "species_name"] <- "species_name"

## ---- Merge into unified species summary ------------------------------------
summary_df <- gf  # start with growth form table (all species with GF data)

if (!is.null(ht_summ)) {
  summary_df <- merge(summary_df, ht_summ,
                      by.x = "species_name", by.y = "species_name",
                      all.x = TRUE)
}
if (!is.null(db_summ)) {
  summary_df <- merge(summary_df, db_summ,
                      by.x = "species_name", by.y = "species_name",
                      all.x = TRUE)
}

## ---- Derive availability and allometric readiness flags --------------------
ht_n_col <- "height_m_n"
db_n_col <- "dbh_cm_n"

if (ht_n_col %in% names(summary_df)) {
  summary_df$height_data_available <- !is.na(summary_df[[ht_n_col]]) &
                                       summary_df[[ht_n_col]] > 0
} else {
  summary_df$height_data_available <- FALSE
}

if (db_n_col %in% names(summary_df)) {
  summary_df$dbh_data_available <- !is.na(summary_df[[db_n_col]]) &
                                    summary_df[[db_n_col]] > 0
} else {
  summary_df$dbh_data_available <- FALSE
}

summary_df$growth_form_available <- !is.na(summary_df$growth_form_canonical)
summary_df$trait_data_available  <- summary_df$height_data_available |
                                    summary_df$dbh_data_available     |
                                    summary_df$growth_form_available
summary_df$allometric_ready      <- summary_df$height_data_available &
                                    summary_df$dbh_data_available

## ---- Add source provenance columns -----------------------------------------
summary_df$source_id          <- "bien"
summary_df$source_access_date <- as.character(Sys.Date())

## ---- Report -----------------------------------------------------------------
message("[Stage 7] Summary table: ", nrow(summary_df), " species")
message("  With height data:       ",
        sum(summary_df$height_data_available, na.rm = TRUE))
message("  With DBH data:          ",
        sum(summary_df$dbh_data_available, na.rm = TRUE))
message("  Allometric-ready:       ",
        sum(summary_df$allometric_ready, na.rm = TRUE))
message("  Graminoid species:      ",
        sum(summary_df$is_graminoid, na.rm = TRUE))
message("  Bamboo species:         ",
        sum(summary_df$is_bamboo, na.rm = TRUE))

fwrite(summary_df, "output/plant_size_summary.csv")
message("[Stage 7] Summary written to: output/plant_size_summary.csv")
message("=== Stage 7 complete ===")
