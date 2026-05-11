## scripts/merge_linear_size.R
## Merge all completed linear size provider outputs into
## data/compiled/tier1_linear_size_combined.csv
##
## Run this after provider output files in LINEAR_PROVIDERS list are present.
##
## Providers merged:
##   - MOBS 1.0       (marine invertebrates + fish; linear dimensions from literature)
##   - ReptTraits v1-2 (reptiles; SVL, TL, SCL from literature)
##   - SeaLifeBase     (marine non-fish; maximum length via rfishbase)
##   - DISPERSE        (European aquatic macroinvertebrates; maximum body size + wing length)
##
## OPTIONAL_LINEAR_PROVIDERS is reserved for future linear size providers.
## Add paths there when new providers produce mobs-style long-format output.

suppressPackageStartupMessages(library(data.table))

OUTPUT_DIR   <- "data/compiled"
OUTPUT_FILE  <- file.path(OUTPUT_DIR, "tier1_linear_size_combined.csv")
LOG_FILE     <- file.path("output", "merge_linear_size_log.txt")

## Required provider output files
LINEAR_PROVIDERS <- c(
  "output/mobs_linear_compiled.csv",
  "output/repttraits_linear_compiled.csv",
  "output/sealifebase_linear_compiled.csv",
  "output/disperse_linear_compiled.csv",
  "output/lizardtraits_linear_compiled.csv"
)

## Optional providers (include if present)
OPTIONAL_LINEAR_PROVIDERS <- character(0)

## Required columns from globalsize_linear_size_schema_columns()
REQUIRED_COLS <- c(
  "source_id", "source_display_name", "source_doi",
  "verbatim_taxon_name", "input_taxonomic_group",
  "size_measurement_class", "size_measurement_type",
  "size_value_cm", "primary_backbone", "aphia_id",
  "size_confidence", "date_added"
)

## ---- Log helper -------------------------------------------------------------

log_msg <- function(...) {
  msg <- paste0(format(Sys.time(), "[%Y-%m-%d %H:%M:%S] "), ...)
  message(msg)
  cat(msg, "\n", file = LOG_FILE, append = TRUE)
}

## Fresh log file
cat("", file = LOG_FILE)
log_msg("=== Linear size merge started ===")

## ---- Check required providers -----------------------------------------------

missing_required <- LINEAR_PROVIDERS[!file.exists(LINEAR_PROVIDERS)]
if (length(missing_required) > 0) {
  stop(
    "Required linear size provider files not found:\n  ",
    paste(missing_required, collapse = "\n  "),
    call. = FALSE
  )
}

## Include optional providers when present
present_optional <- OPTIONAL_LINEAR_PROVIDERS[file.exists(OPTIONAL_LINEAR_PROVIDERS)]
if (length(present_optional) > 0) {
  log_msg("Including optional providers: ", paste(present_optional, collapse = ", "))
  all_files <- c(LINEAR_PROVIDERS, present_optional)
} else {
  all_files <- LINEAR_PROVIDERS
}

log_msg(sprintf("Merging %d provider file(s)", length(all_files)))

## ---- Read and stack all provider files --------------------------------------

tables <- lapply(all_files, function(f) {
  dt <- tryCatch(
    data.table::fread(f, data.table = FALSE, colClasses = "character"),
    error = function(e) stop("Failed to read ", f, ": ", conditionMessage(e), call. = FALSE)
  )
  log_msg(sprintf("  %-55s %6d rows", basename(f), nrow(dt)))
  dt
})

## Verify column consistency; warn on mismatches
all_cols    <- lapply(tables, names)
common_cols <- Reduce(intersect, all_cols)
union_cols  <- Reduce(union, all_cols)
if (length(common_cols) < length(union_cols)) {
  extra <- setdiff(union_cols, common_cols)
  log_msg("WARNING: columns not shared across all providers: ",
          paste(extra, collapse = ", "))
}

## Row-bind with fill=TRUE to handle any column mismatches across providers
combined <- data.table::rbindlist(tables, use.names = TRUE, fill = TRUE)

## ---- Validate required columns ----------------------------------------------

missing_cols <- setdiff(REQUIRED_COLS, names(combined))
if (length(missing_cols) > 0) {
  log_msg("WARNING: required schema columns missing from merged table: ",
          paste(missing_cols, collapse = ", "))
} else {
  log_msg("Required column check: PASS")
}

## Check for rows missing size_value_cm
combined$size_value_cm <- suppressWarnings(as.numeric(combined$size_value_cm))
n_before <- nrow(combined)
combined_valid <- combined[!is.na(combined$size_value_cm) & combined$size_value_cm > 0, ]
n_dropped <- n_before - nrow(combined_valid)
if (n_dropped > 0) {
  log_msg(sprintf("WARNING: dropped %d rows with NA/non-positive size_value_cm", n_dropped))
}
combined <- combined_valid

log_msg(sprintf("Total rows after merge: %d", nrow(combined)))

## ---- Provider breakdown -----------------------------------------------------

provider_summary <- as.data.frame(table(combined$source_id))
names(provider_summary) <- c("source_id", "n_rows")
log_msg(sprintf("Provider count: %d", nrow(provider_summary)))
log_msg("Provider row counts:")
for (i in seq_len(nrow(provider_summary))) {
  log_msg(sprintf("  %-45s %6d", provider_summary$source_id[i], provider_summary$n_rows[i]))
}

## ---- Dimension type breakdown -----------------------------------------------

dim_summary <- as.data.frame(table(combined$size_measurement_type))
names(dim_summary) <- c("size_measurement_type", "n_rows")
log_msg("Dimension type row counts:")
for (i in seq_len(nrow(dim_summary))) {
  log_msg(sprintf("  %-30s %6d", dim_summary$size_measurement_type[i], dim_summary$n_rows[i]))
}

## ---- Taxonomic group breakdown ----------------------------------------------

group_summary <- as.data.frame(table(combined$input_taxonomic_group))
names(group_summary) <- c("group", "n_rows")
log_msg("Taxonomic group row counts:")
for (i in seq_len(nrow(group_summary))) {
  log_msg(sprintf("  %-30s %6d", group_summary$group[i], group_summary$n_rows[i]))
}

## ---- Write output -----------------------------------------------------------

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
data.table::fwrite(combined, OUTPUT_FILE)
log_msg(sprintf(
  "=== tier1_linear_size_combined.csv written: %d rows -> %s ===",
  nrow(combined), OUTPUT_FILE
))

## ---- Console summary --------------------------------------------------------

cat("\nProvider summary:\n")
print(provider_summary)

cat("\nDimension type summary:\n")
print(dim_summary)

cat("\nTaxonomic group summary:\n")
print(group_summary)
