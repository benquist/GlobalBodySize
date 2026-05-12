## Global_Plant_BodySize/scripts/06_qa_checks.R
## Stage 6: Quality assurance on numeric size trait records.
##
## Steps:
##   1. Join growth_form_canonical from species_growth_form.csv onto height
##      and DBH raw records (needed for growth-form-specific range limits).
##   2. Run range check: flag records outside plausible height/DBH range for
##      the species' growth form.
##   3. Run unit check: verify trait_unit_canonical is correct for measurement type.
##   4. Run outlier detection: log10-scale z-score |z| > 3 within
##      (growth_form_canonical × higher_plant_group) strata.
##   5. Write QA-flagged tables and a QA summary report.
##
## Input:
##   output/bien_height_raw.csv
##   output/bien_dbh_raw.csv
##   output/species_growth_form.csv
##
## Output:
##   output/bien_height_qa.csv    — height records with QA columns populated
##   output/bien_dbh_qa.csv       — DBH records with QA columns populated
##   output/qa_summary_report.csv — per-check pass rates and failure counts
##
## Records failing QA are FLAGGED, not removed. Downstream stages filter on
## range_check_pass, unit_check_pass, and outlier_flag as appropriate.
##
## Run from project root:
##   Rscript scripts/06_qa_checks.R

if (basename(getwd()) == "scripts") setwd("..")

library(data.table)
source("R/plant_size_schema.R")
source("R/qa_checks_plants.R")

## ---- Load growth form lookup -----------------------------------------------
stopifnot(file.exists("output/species_growth_form.csv"))
gf_lookup <- fread("output/species_growth_form.csv",
                   select = c("species_name", "growth_form_canonical"),
                   data.table = FALSE)
names(gf_lookup)[names(gf_lookup) == "species_name"] <- "verbatim_species_name"
names(gf_lookup)[names(gf_lookup) == "growth_form_canonical"] <- "growth_form_canonical_qa"

## ---- Helper: run full QA on one trait file ---------------------------------
qa_one_file <- function(input_file, output_file) {
  if (!file.exists(input_file)) {
    message("[Stage 6] Skipping (not found): ", input_file)
    return(invisible(NULL))
  }

  message("[Stage 6] Loading: ", input_file)
  dt <- fread(input_file, data.table = TRUE)

  ## Join growth form for range checks (data.table merge)
  gf_dt <- as.data.table(gf_lookup)
  dt <- merge(dt, gf_dt, by = "verbatim_species_name", all.x = TRUE)
  ## Fill growth_form_canonical_qa as "unknown" if not matched
  dt[is.na(growth_form_canonical_qa), growth_form_canonical_qa := "unknown"]

  ## Run QA checks (all vectorized; returns data.table)
  dt <- run_qa_plants(dt)

  ## Report
  report_qa_summary(dt)

  ## Write output
  fwrite(dt, output_file)
  message("[Stage 6] Written: ", output_file, " (", nrow(dt), " records)")

  invisible(dt)
}

## ---- Run QA on height and DBH ----------------------------------------------
ht <- qa_one_file("output/bien_height_raw.csv", "output/bien_height_qa.csv")
db <- qa_one_file("output/bien_dbh_raw.csv",    "output/bien_dbh_qa.csv")

## ---- Write aggregate QA summary report -------------------------------------
qa_summary_rows <- list()

collect_summary <- function(dt, source_label) {
  if (is.null(dt)) return(NULL)
  data.frame(
    source              = source_label,
    n_total             = nrow(dt),
    n_range_checked     = sum(!is.na(dt$range_check_pass)),
    n_range_pass        = sum(dt$range_check_pass %in% TRUE, na.rm = TRUE),
    n_range_fail        = sum(dt$range_check_pass %in% FALSE, na.rm = TRUE),
    n_unit_checked      = sum(!is.na(dt$unit_check_pass)),
    n_unit_pass         = sum(dt$unit_check_pass %in% TRUE, na.rm = TRUE),
    n_unit_fail         = sum(dt$unit_check_pass %in% FALSE, na.rm = TRUE),
    n_outlier_checked   = sum(!is.na(dt$outlier_flag)),
    n_outlier_flagged   = sum(dt$outlier_flag %in% TRUE, na.rm = TRUE),
    stringsAsFactors    = FALSE
  )
}

summary_df <- do.call(rbind, Filter(Negate(is.null), list(
  collect_summary(ht, "height"),
  collect_summary(db, "dbh")
)))

fwrite(summary_df, "output/qa_summary_report.csv")
message("[Stage 6] QA summary written to: output/qa_summary_report.csv")
print(summary_df)
message("=== Stage 6 complete ===")
