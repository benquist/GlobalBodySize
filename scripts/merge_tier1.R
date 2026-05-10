## scripts/merge_tier1.R
## Merge all completed provider outputs into data/compiled/tier1_combined.csv
## Run this after all providers in PROVIDERS list have output files.
##
## Providers merged:
##   - PanTHERIA       (mammalia, literature mean)
##   - EltonTraits     (birds + mammals, literature mean)
##   - AnAge           (multi-taxon, literature)
##   - AmphiBIO        (amphibia, literature mean)
##   - FishBase        (actinopterygii, direct + LW-modeled)
##   - NEON            (mammalia, field trapping — optional; include if file exists)

suppressPackageStartupMessages(library(data.table))

OUTPUT_DIR    <- "data/compiled"
OUTPUT_FILE   <- file.path(OUTPUT_DIR, "tier1_combined.csv")
LOG_FILE      <- file.path("output", "merge_tier1_log.txt")

## Provider output files — add NEON if present
PROVIDERS <- c(
  "output/pantheria_compiled.csv",
  "output/eltontraits_compiled.csv",
  "output/anage_compiled.csv",
  "output/amphibio_compiled.csv",
  "output/fishbase_compiled.csv"
)

OPTIONAL_PROVIDERS <- c(
  "output/neon_compiled.csv"
)

## Log helper
log_msg <- function(...) {
  msg <- paste0(format(Sys.time(), "[%Y-%m-%d %H:%M:%S] "), ...)
  message(msg)
  cat(msg, "\n", file = LOG_FILE, append = TRUE)
}

## Fresh log file
cat("", file = LOG_FILE)
log_msg("=== Tier-1 merge started ===")

## Check which files exist
missing <- PROVIDERS[!file.exists(PROVIDERS)]
if (length(missing) > 0) {
  stop("Required provider files not found:\n  ",
       paste(missing, collapse = "\n  "), call. = FALSE)
}

## Include optional providers when present
present_optional <- OPTIONAL_PROVIDERS[file.exists(OPTIONAL_PROVIDERS)]
if (length(present_optional) > 0) {
  log_msg("Including optional providers: ", paste(present_optional, collapse = ", "))
  all_files <- c(PROVIDERS, present_optional)
} else {
  all_files <- PROVIDERS
}

## Read and stack all provider files
tables <- lapply(all_files, function(f) {
  dt <- tryCatch(
    data.table::fread(f, data.table = FALSE, colClasses = "character"),
    error = function(e) stop("Failed to read ", f, ": ", conditionMessage(e), call. = FALSE)
  )
  log_msg(sprintf("  %-50s %6d rows", basename(f), nrow(dt)))
  dt
})

## Verify column consistency (warn on extra/missing columns)
all_cols <- lapply(tables, names)
common_cols <- Reduce(intersect, all_cols)
union_cols  <- Reduce(union, all_cols)
if (length(common_cols) < length(union_cols)) {
  extra <- setdiff(union_cols, common_cols)
  log_msg("WARNING: columns not shared across all providers: ", paste(extra, collapse=", "))
}

## Row-bind — use fill=TRUE to handle any column mismatches
combined <- data.table::rbindlist(tables, use.names = TRUE, fill = TRUE)

## Coerce mass_g to numeric and drop rows without mass
combined$mass_g <- suppressWarnings(as.numeric(combined$mass_g))
n_before <- nrow(combined)
combined <- combined[!is.na(combined$mass_g) & combined$mass_g > 0, ]
n_dropped <- n_before - nrow(combined)
if (n_dropped > 0) {
  log_msg(sprintf("WARNING: dropped %d rows with NA/non-positive mass_g", n_dropped))
}

log_msg(sprintf("Total rows after merge: %d", nrow(combined)))

## Provider breakdown
provider_summary <- as.data.frame(table(combined$source_id))
names(provider_summary) <- c("source_id", "n_rows")
log_msg("Provider row counts:")
for (i in seq_len(nrow(provider_summary))) {
  log_msg(sprintf("  %-40s %6d", provider_summary$source_id[i], provider_summary$n_rows[i]))
}

## Taxonomic group breakdown
group_summary <- as.data.frame(table(combined$input_taxonomic_group))
names(group_summary) <- c("group", "n_rows")
log_msg("Taxonomic group row counts:")
for (i in seq_len(nrow(group_summary))) {
  log_msg(sprintf("  %-30s %6d", group_summary$group[i], group_summary$n_rows[i]))
}

## Write output
dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)
data.table::fwrite(combined, OUTPUT_FILE)
log_msg(sprintf("=== tier1_combined.csv written: %d rows -> %s ===", nrow(combined), OUTPUT_FILE))

cat("\nProvider summary:\n")
print(provider_summary)
