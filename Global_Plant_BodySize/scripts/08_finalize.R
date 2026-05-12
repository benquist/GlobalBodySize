## Global_Plant_BodySize/scripts/08_finalize.R
## Stage 8: Build the final plant body size database.
##
## This stage is the CRITICAL COMPLETENESS STEP:
##   Every species in the BIEN species roster is included in the final table.
##   Species with NO trait data receive NA size columns and
##   trait_data_available = FALSE. Do NOT silently drop no-data species.
##
## Operations:
##   1. Load species roster (output/bien_species_roster.csv) — all BIEN species.
##   2. Left-join species-level size summary (output/plant_size_summary.csv).
##   3. Fill unjoined species with NA size columns and trait_data_available = FALSE.
##   4. Enforce column schema from plantsize_summary_schema_columns().
##   5. Write final database.
##   6. Write a coverage report (fraction of species with data by group/family).
##
## Output:
##   output/plant_bodysize_final.csv   — full database (all species, inc. no-data)
##   output/coverage_report.csv        — coverage by higher_plant_group and family
##
## Run from project root:
##   Rscript scripts/08_finalize.R

if (basename(getwd()) == "scripts") setwd("..")

library(data.table)
source("R/plant_size_schema.R")

## ---- Load species roster ---------------------------------------------------
roster_file <- "output/bien_species_roster.csv"
if (!file.exists(roster_file)) roster_file <- "output/bien_species_list.csv"
stopifnot(file.exists(roster_file))

roster <- fread(roster_file, data.table = FALSE)
message("[Stage 8] Species roster: ", nrow(roster), " species")

## Standardize roster species column name
if (!"species_name" %in% names(roster) && "species" %in% names(roster)) {
  roster$species_name <- roster$species
}

## ---- Load size summary -----------------------------------------------------
summary_file <- "output/plant_size_summary.csv"
if (!file.exists(summary_file)) {
  stop("[Stage 8] plant_size_summary.csv not found. Run Stage 7 first.")
}
summ <- fread(summary_file, data.table = FALSE)
message("[Stage 8] Size summary: ", nrow(summ), " species with trait data")

## ---- Left-join: roster ← summary -------------------------------------------
final <- merge(roster, summ,
               by.x = "species_name", by.y = "species_name",
               all.x = TRUE,
               suffixes = c("", "_summ"))

## ---- Fill NA flags for species with no data --------------------------------
## trait_data_available
if ("trait_data_available" %in% names(final)) {
  final$trait_data_available[is.na(final$trait_data_available)] <- FALSE
} else {
  final$trait_data_available <- FALSE
}

## height / dbh / growth_form availability flags
for (flag_col in c("height_data_available", "dbh_data_available",
                   "growth_form_available", "allometric_ready",
                   "is_graminoid", "is_bamboo", "is_bryophyte")) {
  if (flag_col %in% names(final)) {
    final[[flag_col]][is.na(final[[flag_col]])] <- FALSE
  } else {
    final[[flag_col]] <- FALSE
  }
}

## confidence tiers: default to "none" for species with no records
for (conf_col in c("height_m_confidence", "dbh_cm_confidence")) {
  if (conf_col %in% names(final)) {
    final[[conf_col]][is.na(final[[conf_col]])] <- "none"
  } else {
    final[[conf_col]] <- "none"
  }
}

## growth_form_canonical: "unknown" for species with no growth form data
if ("growth_form_canonical" %in% names(final)) {
  final$growth_form_canonical[is.na(final$growth_form_canonical)] <- "unknown"
} else {
  final$growth_form_canonical <- "unknown"
}

## Add source columns if missing
if (!"source_id" %in% names(final))
  final$source_id <- "bien"
if (!"source_access_date" %in% names(final))
  final$source_access_date <- as.character(Sys.Date())

## ---- Enforce column order from schema --------------------------------------
schema_cols <- plantsize_summary_schema_columns()
## Only keep schema columns that exist; add missing schema cols as NA
for (col in schema_cols) {
  if (!col %in% names(final)) final[[col]] <- NA
}
## Re-order to schema order first, then any extra columns
extra_cols  <- setdiff(names(final), schema_cols)
final       <- final[, c(schema_cols, extra_cols), drop = FALSE]

## ---- Sort for reproducibility ----------------------------------------------
final <- final[order(final$species_name), ]
rownames(final) <- NULL

## ---- Write final database --------------------------------------------------
fwrite(final, "output/plant_bodysize_final.csv")
message("[Stage 8] Final database: ", nrow(final), " species")
message("  With any trait data:    ",
        sum(final$trait_data_available, na.rm = TRUE),
        sprintf(" (%.1f%%)", 100 * mean(final$trait_data_available, na.rm = TRUE)))
message("  No trait data (no-data rows): ",
        sum(!final$trait_data_available, na.rm = TRUE))

## ---- Write coverage report -------------------------------------------------
## Coverage by higher_plant_group
if ("higher_plant_group" %in% names(final)) {
  cov_group <- do.call(rbind, lapply(
    split(final, final$higher_plant_group), function(df) {
      data.frame(
        group           = df$higher_plant_group[1],
        n_species       = nrow(df),
        n_height        = sum(df$height_data_available, na.rm = TRUE),
        n_dbh           = sum(df$dbh_data_available, na.rm = TRUE),
        n_growth_form   = sum(df$growth_form_available, na.rm = TRUE),
        pct_any_data    = round(100 * mean(df$trait_data_available, na.rm = TRUE), 1),
        stringsAsFactors = FALSE
      )
    }
  ))
  if (is.null(cov_group)) cov_group <- data.frame()
  rownames(cov_group) <- NULL

  ## Coverage by family (top 50 most species-rich)
  if ("family" %in% names(final)) {
    fam_counts <- sort(table(final$family[!is.na(final$family)]), decreasing = TRUE)
    top_families <- names(fam_counts)[seq_len(min(50, length(fam_counts)))]
    cov_family <- do.call(rbind, lapply(top_families, function(fam) {
      df <- final[!is.na(final$family) & final$family == fam, ]
      data.frame(
        family          = fam,
        n_species       = nrow(df),
        n_height        = sum(df$height_data_available, na.rm = TRUE),
        n_dbh           = sum(df$dbh_data_available, na.rm = TRUE),
        pct_any_data    = round(100 * mean(df$trait_data_available, na.rm = TRUE), 1),
        stringsAsFactors = FALSE
      )
    }))
    if (is.null(cov_family)) cov_family <- data.frame()
  } else {
    cov_family <- data.frame()
  }

  coverage_report <- list(by_group = cov_group, by_family = cov_family)
  if (nrow(cov_group) > 0)  fwrite(cov_group,  "output/coverage_by_group.csv")
  if (nrow(cov_family) > 0) fwrite(cov_family, "output/coverage_by_family.csv")

  message("[Stage 8] Coverage by higher_plant_group:")
  print(cov_group)
}

message("[Stage 8] Final database written to: output/plant_bodysize_final.csv")
message("=== Stage 8 complete — pipeline finished ===")
message("")
message("NEXT STEPS:")
message("  1. Verify BIEN citation DOI before publication")
message("  2. Check bamboo genus assignments for Chusquea and Guadua (New World bamboos)")
message("  3. Cross-validate a random sample of height records against TRY database")
message("  4. Review coverage_by_group.csv for data-poor groups (pteridophytes, gymnosperms)")
