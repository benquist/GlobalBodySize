#!/usr/bin/env Rscript
# compile_sdata_traits.R
# Download and compile plant trait data from resolved Scientific Data files.
# Handles: AusTraits (flattened parquet/rds), WOODIV Trait_data.csv (inside zip),
#          and any future tabular files listed in sdata_files_resolved.csv.
#
# Usage (from any directory):
#   Rscript compile_sdata_traits.R \
#     [--resolved-csv=<path>]   # default: output/providers/scientific_data/sdata_files_resolved.csv
#     [--output-dir=<dir>]      # default: output/providers/scientific_data
#     [--dry-run=TRUE]          # preview only, no downloads

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x

# --- Locate project root ---
find_sdata_project_root <- function() {
  cwd <- getwd()
  if (basename(cwd) == "DryadPlantTraits") return(cwd)
  if (basename(cwd) == "scripts") {
    p <- dirname(dirname(dirname(cwd)))
    if (basename(p) == "DryadPlantTraits") return(p)
    p2 <- dirname(cwd)
    if (basename(p2) == "DryadPlantTraits") return(p2)
  }
  probe <- file.path(cwd, "DryadPlantTraits")
  if (dir.exists(probe)) return(probe)
  stop("Cannot locate DryadPlantTraits project root from: ", cwd, call. = FALSE)
}

root       <- find_sdata_project_root()
sdata_root <- file.path(root, "providers", "scientific_data")

source(file.path(root, "R", "dryad_api.R"))

# --- Parse args ---
raw_args <- commandArgs(trailingOnly = TRUE)
args <- list()
for (a in raw_args) {
  if (!startsWith(a, "--")) next
  parts <- strsplit(sub("^--", "", a), "=", fixed = TRUE)[[1]]
  args[[parts[1]]] <- if (length(parts) > 1L) paste(parts[-1L], collapse = "=") else "TRUE"
}

output_dir   <- args$`output-dir` %||% file.path(root, "output", "providers", "scientific_data")
resolved_csv <- args$`resolved-csv` %||% file.path(output_dir, "sdata_files_resolved.csv")
dry_run      <- isTRUE(args$`dry-run` == "TRUE")
download_dir <- file.path(output_dir, "downloads", "sdata_tabular")

message("=== Scientific Data Tabular Trait Compiler ===")
message("Resolved CSV : ", resolved_csv)
message("Output dir   : ", output_dir)
message("Download dir : ", download_dir)
message("Dry run      : ", dry_run)

if (!file.exists(resolved_csv)) {
  stop("Resolved files CSV not found: ", resolved_csv, call. = FALSE)
}

resolved <- read.csv(resolved_csv, stringsAsFactors = FALSE)
message(sprintf("Loaded %d resolved file entries.", nrow(resolved)))

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

download_file_curl <- function(url, dest_path) {
  headers <- c("User-Agent: DryadPlantTraits/1.0 (research pipeline)")
  result <- tryCatch(
    dryad_run_curl(url, headers = headers),
    error = function(e) NULL
  )
  if (is.null(result) || !result$http_code %in% c(200L)) {
    warning(sprintf("download_file_curl: HTTP %s for %s",
                    if (!is.null(result)) result$http_code else "NULL", url))
    return(FALSE)
  }
  tryCatch({
    writeBin(chartr("", "", result$body), dest_path)
    file.exists(dest_path)
  }, error = function(e) {
    # result$body may be binary; use curl directly for binary downloads
    warning(sprintf("download_file_curl: write failed — using system curl: %s", conditionMessage(e)))
    FALSE
  })
}

# Download binary via system curl -L (more robust for large/binary files)
download_binary <- function(url, dest_path) {
  curl_bin <- Sys.which("curl")
  if (!nzchar(curl_bin)) stop("curl not found on PATH", call. = FALSE)
  cmd <- paste(
    shQuote(curl_bin),
    "-L", "--fail", "--silent", "--show-error",
    "-H", shQuote("User-Agent: DryadPlantTraits/1.0"),
    "-o", shQuote(dest_path),
    shQuote(url)
  )
  ret <- system(cmd, intern = FALSE)
  ret == 0L && file.exists(dest_path) && file.info(dest_path)$size > 0
}

ensure_dir <- function(d) dir.create(d, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# Define compile targets
# We build a named list of compile jobs, each producing a data.frame of traits
# with columns: taxon_name, trait_name, value, unit, source_doi, source_paper
# ---------------------------------------------------------------------------

COMPILE_TARGETS <- list(

  # ---- AusTraits (flattened parquet — one row per observation) ----
  austraits = list(
    paper_doi    = "10.1038/s41597-021-01006-6",
    source_paper = "AusTraits: a curated plant trait database for the Australian flora",
    files        = list(
      list(
        name         = "austraits-7.0.0-flattened.parquet",
        url          = "https://zenodo.org/api/records/15718081/files/austraits-7.0.0-flattened.parquet/content",
        type         = "parquet",
        taxon_col    = "taxon_name",
        trait_col    = "trait_name",
        value_col    = "value",
        unit_col     = "unit"
      ),
      # Fallback: flattened rds if parquet fails
      list(
        name         = "austraits-7.0.0-flattened.rds",
        url          = "https://zenodo.org/api/records/15718081/files/austraits-7.0.0-flattened.rds/content",
        type         = "rds",
        taxon_col    = "taxon_name",
        trait_col    = "trait_name",
        value_col    = "value",
        unit_col     = "unit"
      )
    )
  ),

  # ---- WOODIV — Euro-Mediterranean woody plant traits ----
  woodiv = list(
    paper_doi    = "10.1038/s41597-021-00873-3",
    source_paper = "WOODIV, a database of occurrences, functional traits, and phylogenetic data for all Euro-Mediterranean trees",
    files = list(
      list(
        name         = "WOODIV_DB_release_v1.zip",
        url          = "https://ndownloader.figshare.com/files/26576827",
        type         = "zip",
        inner_path   = "WOODIV_DB_release_v1/TRAITS/WOODIV_Trait_data.csv",
        taxon_col    = "spcode",
        trait_col    = "Traits",
        value_col    = "value",
        unit_col     = NULL,
        extra_cols   = c(source_citation = "Trait_source")
      )
    )
  ),

  # ---- CFCCD (Chinese forest carbon cycle) — check if traits inside ----
  cfccd = list(
    paper_doi    = "10.1038/s41597-021-00826-w",
    source_paper = "Reference carbon cycle dataset for typical Chinese forests via colocated observations and data assimilation",
    files = list(
      list(
        name       = "CFCCD datasets.zip",
        url        = "https://ndownloader.figshare.com/files/25892343",
        type       = "zip",
        inner_path = NULL  # Will scan for trait CSVs inside zip
      )
    )
  )
)

# ---------------------------------------------------------------------------
# Schema: normalised output columns
# ---------------------------------------------------------------------------
TRAIT_SCHEMA <- c(
  "source_provider", "source_doi", "source_paper",
  "taxon_name", "trait_name", "value", "unit",
  "source_citation", "compiled_timestamp"
)

make_empty_schema <- function() {
  as.data.frame(
    setNames(lapply(TRAIT_SCHEMA, function(x) character(0)), TRAIT_SCHEMA),
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Read AusTraits parquet
# ---------------------------------------------------------------------------
read_austraits_parquet <- function(path, target) {
  if (!requireNamespace("arrow", quietly = TRUE)) {
    message("  Package 'arrow' not installed. Trying 'nanoparquet'...")
    if (!requireNamespace("nanoparquet", quietly = TRUE)) {
      warning("Cannot read parquet: install 'arrow' or 'nanoparquet'")
      return(NULL)
    }
    df <- tryCatch(nanoparquet::read_parquet(path), error = function(e) { warning(conditionMessage(e)); NULL })
  } else {
    df <- tryCatch(as.data.frame(arrow::read_parquet(path)), error = function(e) { warning(conditionMessage(e)); NULL })
  }
  df
}

# ---------------------------------------------------------------------------
# Read AusTraits rds
# ---------------------------------------------------------------------------
read_austraits_rds <- function(path, target) {
  obj <- tryCatch(readRDS(path), error = function(e) { warning(conditionMessage(e)); NULL })
  if (is.null(obj)) return(NULL)
  # AusTraits rds may be a list; flattened version is a data.frame or list$traits
  if (is.data.frame(obj)) return(obj)
  if (is.list(obj) && !is.null(obj$traits)) return(as.data.frame(obj$traits))
  warning("AusTraits rds object structure not recognized — skipping.")
  NULL
}

# ---------------------------------------------------------------------------
# Normalize a trait data.frame to schema
# ---------------------------------------------------------------------------
normalize_traits <- function(df, target, file_spec, paper_doi, source_paper) {
  if (is.null(df) || !nrow(df)) return(make_empty_schema())

  get_col <- function(df, name) {
    if (is.null(name) || !name %in% names(df)) NA_character_
    else as.character(df[[name]])
  }

  taxon  <- get_col(df, file_spec$taxon_col)
  trait  <- get_col(df, file_spec$trait_col)
  value  <- get_col(df, file_spec$value_col)
  unit   <- get_col(df, file_spec$unit_col)
  cite   <- if (!is.null(file_spec$extra_cols) && "source_citation" %in% names(file_spec$extra_cols)) {
              get_col(df, file_spec$extra_cols[["source_citation"]])
            } else NA_character_

  out <- data.frame(
    source_provider    = "scientific_data",
    source_doi         = paper_doi,
    source_paper       = source_paper,
    taxon_name         = taxon,
    trait_name         = trait,
    value              = value,
    unit               = unit,
    source_citation    = cite,
    compiled_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    stringsAsFactors   = FALSE
  )

  # Remove rows where both taxon_name and trait_name are NA
  out <- out[!(is.na(out$taxon_name) & is.na(out$trait_name)), , drop = FALSE]
  out
}

# ---------------------------------------------------------------------------
# Scan a zip for trait CSVs (for CFCCD or unknown zips)
# ---------------------------------------------------------------------------
scan_zip_for_traits <- function(zip_path) {
  all_files <- tryCatch(utils::unzip(zip_path, list = TRUE)$Name, error = function(e) character(0))
  tabular <- all_files[grepl("\\.(csv|tsv|txt)$", all_files, ignore.case = TRUE)]
  # Prefer files with trait-like names
  trait_like <- tabular[grepl("trait|plant|leaf|wood|root|sla|height|mass|lma", tabular, ignore.case = TRUE)]
  if (length(trait_like)) trait_like else tabular
}

# ---------------------------------------------------------------------------
# Main compile loop
# ---------------------------------------------------------------------------
ensure_dir(output_dir)
if (!dry_run) ensure_dir(download_dir)

all_compiled <- list()
compile_log  <- list()

for (target_name in names(COMPILE_TARGETS)) {
  target <- COMPILE_TARGETS[[target_name]]
  message(sprintf("\n--- Compiling: %s [%s] ---", target_name, target$paper_doi))

  for (file_spec in target$files) {
    fname    <- file_spec$name
    url      <- file_spec$url
    ftype    <- file_spec$type
    dest     <- file.path(download_dir, fname)

    message(sprintf("  File: %s", fname))
    message(sprintf("  URL : %s", url))

    if (dry_run) {
      message("  [DRY RUN] Would download and compile.")
      next
    }

    # Download if not cached
    if (!file.exists(dest) || file.info(dest)$size == 0) {
      message(sprintf("  Downloading to %s ...", dest))
      ok <- download_binary(url, dest)
      if (!ok) {
        warning(sprintf("  Download failed for %s", fname))
        compile_log[[length(compile_log) + 1L]] <- list(
          target = target_name, file = fname, status = "download_failed", rows = 0L
        )
        next
      }
      message(sprintf("  Downloaded: %.1f MB", file.info(dest)$size / 1e6))
    } else {
      message(sprintf("  Using cached: %.1f MB", file.info(dest)$size / 1e6))
    }

    # Read the data
    df <- NULL
    tryCatch({
      if (ftype == "parquet") {
        df <- read_austraits_parquet(dest, target)
      } else if (ftype == "rds") {
        df <- read_austraits_rds(dest, target)
      } else if (ftype == "zip") {
        inner <- file_spec$inner_path
        if (is.null(inner)) {
          # Scan for trait CSVs
          candidates <- scan_zip_for_traits(dest)
          if (!length(candidates)) {
            message("  No trait CSVs found inside zip — skipping.")
            compile_log[[length(compile_log) + 1L]] <- list(
              target = target_name, file = fname, status = "no_trait_csv_in_zip", rows = 0L
            )
            next
          }
          message(sprintf("  Found %d candidate CSV(s) in zip. Trying first: %s",
                          length(candidates), candidates[1]))
          inner <- candidates[1]
        }
        extract_dir <- file.path(download_dir, paste0(target_name, "_extract"))
        ensure_dir(extract_dir)
        tryCatch(
          utils::unzip(dest, files = inner, exdir = extract_dir, junkpaths = TRUE),
          error = function(e) warning(sprintf("  unzip error: %s", conditionMessage(e)))
        )
        extracted <- file.path(extract_dir, basename(inner))
        if (!file.exists(extracted)) {
          warning(sprintf("  Extracted file not found: %s", extracted))
          next
        }
        df <- tryCatch(
          read.csv(extracted, stringsAsFactors = FALSE, check.names = FALSE),
          error = function(e) { warning(conditionMessage(e)); NULL }
        )
      }
    }, error = function(e) {
      warning(sprintf("  Read error for %s: %s", fname, conditionMessage(e)))
    })

    if (is.null(df) || !nrow(df)) {
      message(sprintf("  No data read from %s", fname))
      compile_log[[length(compile_log) + 1L]] <- list(
        target = target_name, file = fname, status = "read_empty", rows = 0L
      )
      next
    }

    message(sprintf("  Read %d rows x %d cols. Columns: %s",
                    nrow(df), ncol(df), paste(head(names(df), 10), collapse = ", ")))

    # Normalize to schema
    norm <- tryCatch(
      normalize_traits(df, target, file_spec, target$paper_doi, target$source_paper),
      error = function(e) { warning(sprintf("  Normalize error: %s", conditionMessage(e))); NULL }
    )

    if (is.null(norm) || !nrow(norm)) {
      message("  Normalization produced 0 rows — skipping.")
      compile_log[[length(compile_log) + 1L]] <- list(
        target = target_name, file = fname, status = "normalize_empty", rows = 0L
      )
      next
    }

    message(sprintf("  Normalized: %d trait observations.", nrow(norm)))
    all_compiled[[length(all_compiled) + 1L]] <- norm
    compile_log[[length(compile_log) + 1L]] <- list(
      target = target_name, file = fname, status = "ok", rows = nrow(norm)
    )

    # For multi-file targets (parquet OR rds fallback), stop on first success
    break
  }
}

# ---------------------------------------------------------------------------
# Write output
# ---------------------------------------------------------------------------
log_df <- if (length(compile_log)) {
  do.call(rbind, lapply(compile_log, as.data.frame, stringsAsFactors = FALSE))
} else {
  data.frame(target = character(0), file = character(0), status = character(0), rows = integer(0))
}
log_path <- file.path(output_dir, "compile_sdata_log.csv")

if (!dry_run && nrow(log_df)) {
  write.csv(log_df, log_path, row.names = FALSE, na = "")
  message(sprintf("\nCompile log written: %s", log_path))
}

message("\n=== Compile Summary ===")
if (nrow(log_df)) print(log_df) else message("(no compile log entries)")

if (length(all_compiled) == 0L) {
  message("\nNo trait data compiled.")
  quit(save = "no", status = 0L)
}

combined <- do.call(rbind, all_compiled)
message(sprintf("\nTotal compiled: %d trait observations from %d target(s).",
                nrow(combined), length(all_compiled)))

# Unique trait names for inspection
trait_counts <- sort(table(combined$trait_name), decreasing = TRUE)
message(sprintf("Unique trait names: %d", length(trait_counts)))
message("Top 20 traits:")
print(head(trait_counts, 20))

# Source breakdown
src_counts <- sort(table(combined$source_doi), decreasing = TRUE)
message("\nRows by source paper:")
print(src_counts)

output_csv <- file.path(output_dir, "compiled_sdata_traits.csv")
write.csv(combined, output_csv, row.names = FALSE, na = "")
message(sprintf("\nCompiled traits written: %s (%d rows)", output_csv, nrow(combined)))
