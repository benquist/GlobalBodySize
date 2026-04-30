#!/usr/bin/env Rscript
# providers/manual_intake/scripts/stage_manual_trait_sources.R
# Inspect manual trait ingestion files before implementing source-specific mapping.

suppressPackageStartupMessages({
  library(data.table)
})

script_file <- tryCatch(normalizePath(sys.frame(0)$ofile, winslash = "/", mustWork = FALSE),
                        error = function(e) "")
if (!nzchar(script_file)) {
  args0 <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args0, value = TRUE)
  if (length(file_arg)) {
    script_file <- normalizePath(sub("^--file=", "", file_arg[[1]]), winslash = "/", mustWork = FALSE)
  }
}
root_candidates <- c(getwd(), dirname(getwd()), dirname(dirname(getwd())))
if (nzchar(script_file)) {
  d1 <- dirname(script_file); d2 <- dirname(d1); d3 <- dirname(d2)
  root_candidates <- c(root_candidates, d1, d2, d3)
}
root_candidates <- unique(normalizePath(root_candidates[file.exists(root_candidates)], winslash = "/", mustWork = FALSE))
proj_hits <- root_candidates[basename(root_candidates) == "DryadPlantTraits"]
if (!length(proj_hits)) stop("Cannot locate DryadPlantTraits project root from: ", getwd(), call. = FALSE)
project_root <- proj_hits[[1]]
cat("Project root:", project_root, "\n")

INTAKE_DIR <- file.path(project_root, "data", "manual_ingestion")
if (!dir.exists(INTAKE_DIR)) {
  dir.create(INTAKE_DIR, recursive = TRUE, showWarnings = FALSE)
}

manual_sources <- list(
  list(source_id = "manual_alltraits_phynames_csv",
       file_name = "alltraits with phynames.csv",
       type = "csv",
       description = "Spasojevic 2016 Ozark study trait table"),
  list(source_id = "manual_oztrait_data_joe_csv",
       file_name = "oztrait data JoE.csv",
       type = "csv",
       description = "Spasojevic 2016 Ozark study JoE trait file"),
  list(source_id = "manual_ozark_trait_metadata2_xlsx",
       file_name = "ozark trait metadata2.xlsx",
       type = "xlsx",
       description = "Spasojevic 2016 Ozark trait metadata workbook")
)

read_csv_sample <- function(path) {
  dt <- tryCatch(fread(path, showProgress = FALSE), error = function(e) NULL)
  if (is.null(dt)) return(NULL)
  list(nrow = nrow(dt), ncol = ncol(dt), names = names(dt), head = head(dt, 5))
}

read_xlsx_sample <- function(path) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    message("Package 'openxlsx' is required to inspect XLSX files. Install with install.packages('openxlsx')")
    return(NULL)
  }
  dt <- tryCatch(openxlsx::read.xlsx(path), error = function(e) NULL)
  if (is.null(dt)) return(NULL)
  dt <- as.data.table(dt)
  list(nrow = nrow(dt), ncol = ncol(dt), names = names(dt), head = head(dt, 5))
}

for (src in manual_sources) {
  path <- file.path(INTAKE_DIR, src$file_name)
  cat("\n---\n")
  cat(sprintf("Source: %s\n", src$source_id))
  cat(sprintf("Description: %s\n", src$description))
  cat(sprintf("Expected path: %s\n", path))
  if (!file.exists(path)) {
    cat("[MISSING] file not found\n")
    next
  }
  cat("[FOUND] file exists\n")
  sample <- switch(src$type,
                   csv = read_csv_sample(path),
                   xlsx = read_xlsx_sample(path),
                   {
                     cat("Unsupported file type:", src$type, "\n")
                     NULL
                   })
  if (is.null(sample)) {
    cat("[WARN] Unable to read file contents.\n")
    next
  }
  cat(sprintf("Dimensions: %d rows x %d cols\n", sample$nrow, sample$ncol))
  cat("Columns:\n")
  cat(paste0("  - ", sample$names, collapse = "\n"), "\n")
  cat("Head (first 5 rows):\n")
  print(sample$head)
}

cat("\nInspection complete. If source files are present, run ingest scripts from providers/manual_intake/scripts.\n")
