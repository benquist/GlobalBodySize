## scripts/merge_providers.R
## Merge all Animal_scaling_data provider output CSVs into a single compiled file.
##
## Reads each provider output, row-binds, writes:
##   data/compiled/animal_scaling_compiled.csv
##
## Run from the project root:
##   Rscript scripts/merge_providers.R

suppressPackageStartupMessages(library(data.table))

## ---- Configuration ----------------------------------------------------------

OUTPUT_DIR  <- "data/compiled"
OUTPUT_FILE <- file.path(OUTPUT_DIR, "animal_scaling_compiled.csv")
LOG_FILE    <- file.path("output", "merge_providers_log.txt")

## Required provider outputs — all must exist for merge to proceed
PROVIDERS <- character(0)   # No required providers yet; all are optional initially

## Optional provider outputs — included when present
OPTIONAL_PROVIDERS <- c(
  "output/animaltraits_compiled.csv",
  "output/pnas_2303764120_compiled.csv",
  "output/hatton2019_compiled.csv",
  "output/hatton2015_compiled.csv"
)

## ---- Log helper -------------------------------------------------------------

log_msg <- function(...) {
  msg <- paste0(format(Sys.time(), "[%Y-%m-%d %H:%M:%S] "), ...)
  message(msg)
  cat(msg, "\n", file = LOG_FILE, append = TRUE)
}

## Fresh log file
dir.create("output",      recursive = TRUE, showWarnings = FALSE)
dir.create(OUTPUT_DIR,    recursive = TRUE, showWarnings = FALSE)
cat("", file = LOG_FILE)
log_msg("=== Animal_scaling_data merge started ===")

## ---- Check required providers -----------------------------------------------

missing_required <- PROVIDERS[!file.exists(PROVIDERS)]
if (length(missing_required) > 0) {
  stop("Required provider files not found:\n  ",
       paste(missing_required, collapse = "\n  "), call. = FALSE)
}

## ---- Gather all files to merge ----------------------------------------------

present_optional <- OPTIONAL_PROVIDERS[file.exists(OPTIONAL_PROVIDERS)]
absent_optional  <- OPTIONAL_PROVIDERS[!file.exists(OPTIONAL_PROVIDERS)]

if (length(absent_optional) > 0) {
  for (f in absent_optional) {
    log_msg("WARNING: optional provider not found — skipping: ", f)
  }
}

all_files <- c(PROVIDERS, present_optional)

if (length(all_files) == 0L) {
  log_msg("No provider files found. Run run_all_intake.R first.")
  stop("No provider output files to merge.", call. = FALSE)
}

log_msg("Providers to merge: ", paste(basename(all_files), collapse = ", "))

## ---- Read and stack ---------------------------------------------------------

tables <- lapply(all_files, function(f) {
  dt <- tryCatch(
    data.table::fread(f, colClasses = "character"),
    error = function(e) stop("Failed to read ", f, ": ", conditionMessage(e),
                             call. = FALSE)
  )
  log_msg(sprintf("  %-55s %6d rows", basename(f), nrow(dt)))
  dt
})

## Warn on column mismatches across providers
all_cols    <- lapply(tables, names)
common_cols <- Reduce(intersect, all_cols)
union_cols  <- Reduce(union,     all_cols)
if (length(common_cols) < length(union_cols)) {
  extra <- setdiff(union_cols, common_cols)
  log_msg("INFO: columns not shared across all providers (fill = NA): ",
          paste(extra, collapse = ", "))
}

## Merge
compiled <- rbindlist(tables, fill = TRUE, use.names = TRUE)
log_msg(sprintf("Total merged rows: %d", nrow(compiled)))

## ---- Per-provider row counts ------------------------------------------------

if ("source_id" %in% names(compiled)) {
  counts <- compiled[, .N, by = source_id][order(-N)]
  log_msg("Row counts by source_id:")
  for (i in seq_len(nrow(counts))) {
    log_msg(sprintf("  %-45s %6d rows", counts$source_id[i], counts$N[i]))
  }
}

## ---- Write ------------------------------------------------------------------

data.table::fwrite(compiled, OUTPUT_FILE)
log_msg("Wrote compiled file: ", OUTPUT_FILE)
log_msg("=== Merge complete ===")
