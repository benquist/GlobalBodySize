#!/usr/bin/env Rscript
# providers/fred/scripts/download_and_compile_fred_traits.R
# FRED ingest pipeline: download new tabular files identified in the FRED candidate
# manifest, parse them, and map to the 58-column final schema.
#
# Download strategy:
#   Dryad individual file downloads (/api/v2/files/{id}/download) require bearer auth.
#   Version ZIPs (/api/v2/versions/{version_id}/download) are publicly accessible.
#   This script looks up version IDs from the Dryad API, downloads one ZIP per dataset
#   version, then extracts only the target files from each ZIP.
#
# Resumable: skips already-downloaded ZIPs and already-extracted files.

library(data.table)

# ---------------------------------------------------------------------------
# Locate project root
# ---------------------------------------------------------------------------
script_file <- tryCatch(normalizePath(sys.frame(0)$ofile, winslash = "/", mustWork = FALSE),
                        error = function(e) "")
if (!nzchar(script_file)) {
  args0 <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args0, value = TRUE)
  if (length(file_arg)) {
    script_file <- normalizePath(sub("^--file=", "", file_arg[[1]]), winslash = "/", mustWork = FALSE)
  }
}

root_candidates <- c(getwd(), dirname(getwd()),
                     dirname(dirname(getwd())), dirname(dirname(dirname(getwd()))))
if (nzchar(script_file)) {
  d1 <- dirname(script_file); d2 <- dirname(d1)
  d3 <- dirname(d2);         d4 <- dirname(d3)
  root_candidates <- c(root_candidates, d1, d2, d3, d4)
}
root_candidates <- unique(normalizePath(
  root_candidates[file.exists(root_candidates)], winslash = "/", mustWork = FALSE))
proj_hits <- root_candidates[basename(root_candidates) == "DryadPlantTraits"]
if (!length(proj_hits)) stop("Cannot locate DryadPlantTraits project root from: ", getwd(), call. = FALSE)
project_root <- proj_hits[[1]]
cat("Project root:", project_root, "\n")

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
manifest_path <- file.path(project_root, "output", "providers", "fred",
                           "new_tabular_files_to_download.csv")
download_dir  <- file.path(project_root, "output", "providers", "fred", "downloads")
compiled_out  <- file.path(project_root, "output", "providers", "fred",
                           "compiled_trait_observations.csv")
log_out       <- file.path(project_root, "output", "providers", "fred",
                           "processing_log.csv")
dir.create(download_dir, recursive = TRUE, showWarnings = FALSE)

FINAL_COLS <- c(
  "scrubbed_species_binomial", "latitude", "longitude", "date_collected",
  "dataset", "datasource", "dataowner", "collection_code",
  "trait_name", "trait_value", "unit", "inferred_unit", "method",
  "country", "stateProvince", "county", "locality", "elevation_m",
  "expected_unit_class", "value_type", "standard_unit", "trait_dictionary_notes",
  "dryad_dataset_doi", "dryad_version_id", "dryad_file_id",
  "source_title", "source_authors", "source_subjects", "source_abstract",
  "download_timestamp_utc", "source_file_path", "original_row_number",
  "raw_taxon", "raw_trait_name", "raw_trait_value", "raw_unit",
  "raw_latitude", "raw_longitude", "raw_elevation", "raw_country",
  "raw_stateProvince", "raw_county", "raw_locality", "raw_date_collected",
  "input_name_verbatim", "infraspecific_rank", "infraspecific_epithet",
  "source_column_taxon", "source_column_trait_name", "source_column_trait_value",
  "source_column_unit", "qa_flags", "inferred_unit_value",
  "inferred_unit_confidence", "inference_evidence", "inference_citation_keys",
  "basis_type", "unit_conversion_factor"
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
curl_bin_path <- Sys.which("curl")
if (!nzchar(curl_bin_path)) stop("curl not found on PATH", call. = FALSE)

curl_download_file <- function(url, destfile, timeout_secs = 300L) {
  cmd_str <- paste(
    shQuote(curl_bin_path), "-L", "--silent", "--show-error",
    "--max-time", as.integer(timeout_secs),
    "-o", shQuote(destfile),
    "--write-out", shQuote("__STATUS__:%{http_code}"),
    shQuote(url)
  )
  out <- suppressWarnings(system(cmd_str, intern = TRUE, ignore.stderr = FALSE))
  combined <- paste(out, collapse = "\n")
  m <- regexpr("__STATUS__:[0-9]{3}", combined)
  code <- if (m > 0L) as.integer(sub("__STATUS__:", "", regmatches(combined, m))) else 0L
  list(http_code = code, ok = (code >= 200L && code < 300L))
}

dryad_get_version_id <- function(doi) {
  encoded <- utils::URLencode(doi, reserved = TRUE)
  url <- sprintf("https://datadryad.org/api/v2/datasets/%s/versions", encoded)
  cmd_str <- paste(
    shQuote(curl_bin_path), "-L", "--silent", "--show-error", "--max-time", "30",
    shQuote(url)
  )
  raw <- suppressWarnings(system(cmd_str, intern = TRUE, ignore.stderr = FALSE))
  if (!length(raw)) return(NA_integer_)
  body <- paste(raw, collapse = "")
  ids <- regmatches(body, gregexpr('"/api/v2/versions/[0-9]+"', body))[[1]]
  if (!length(ids)) return(NA_integer_)
  as.integer(sub('"/api/v2/versions/', "", sub('"$', "", ids[[1]])))
}

find_col_re <- function(nms, pattern) {
  hits <- grep(pattern, nms, ignore.case = TRUE, perl = TRUE, value = FALSE)
  if (length(hits)) hits[[1L]] else NA_integer_
}

parse_to_long <- function(raw_dt) {
  nms <- names(raw_dt)
  if (!length(nms) || nrow(raw_dt) == 0L) return(NULL)

  ci_taxon <- find_col_re(nms, "(?i)species|taxon|taxa|\\bname\\b|binomial")
  ci_trait <- find_col_re(nms, "(?i)\\btrait\\b|\\bparameter\\b|\\bvariable\\b")
  ci_value <- find_col_re(nms, "(?i)\\bvalue\\b|\\bmean\\b|\\bmeasurement\\b|\\bobserved\\b")
  ci_unit  <- find_col_re(nms, "(?i)\\bunit\\b")
  ci_lat   <- find_col_re(nms, "(?i)\\blat\\b|latitude")
  ci_lon   <- find_col_re(nms, "(?i)\\blon\\b|\\blng\\b|longitude")

  if (is.na(ci_taxon)) return(NULL)
  col_taxon <- nms[ci_taxon]
  col_unit  <- if (!is.na(ci_unit)) nms[ci_unit] else NA_character_
  col_lat   <- if (!is.na(ci_lat))  nms[ci_lat]  else NA_character_
  col_lon   <- if (!is.na(ci_lon))  nms[ci_lon]  else NA_character_

  if (!is.na(ci_trait) && !is.na(ci_value)) {
    col_trait <- nms[ci_trait]
    col_value <- nms[ci_value]
    return(data.table(
      taxon       = as.character(raw_dt[[col_taxon]]),
      trait_name  = as.character(raw_dt[[col_trait]]),
      trait_value = as.character(raw_dt[[col_value]]),
      unit_val    = if (!is.na(col_unit)) as.character(raw_dt[[col_unit]]) else NA_character_,
      lat_val     = if (!is.na(col_lat))  as.character(raw_dt[[col_lat]])  else NA_character_,
      lon_val     = if (!is.na(col_lon))  as.character(raw_dt[[col_lon]])  else NA_character_,
      col_taxon = col_taxon, col_trait = col_trait,
      col_value = col_value, col_unit  = col_unit
    ))
  }

  # Wide-format pivot
  exclude_cols <- c(col_taxon, col_unit, col_lat, col_lon)
  exclude_cols <- exclude_cols[!is.na(exclude_cols)]
  candidate_cols <- setdiff(nms, exclude_cols)
  is_num <- vapply(candidate_cols, function(cn)
    sum(!is.na(suppressWarnings(as.numeric(raw_dt[[cn]])))) > 0L, logical(1))
  pivot_cols <- candidate_cols[is_num]
  if (length(pivot_cols) < 2L || length(pivot_cols) > 50L) return(NULL)

  id_vars <- c(col_taxon, if (!is.na(col_unit)) col_unit,
               if (!is.na(col_lat)) col_lat, if (!is.na(col_lon)) col_lon)
  id_vars <- id_vars[!is.na(id_vars)]
  dt_sub <- as.data.table(raw_dt)[, c(id_vars, pivot_cols), with = FALSE]
  long <- melt(dt_sub, id.vars = id_vars, measure.vars = pivot_cols,
               variable.name = "trait_name", value.name = "trait_value",
               variable.factor = FALSE)
  data.table(
    taxon       = as.character(long[[col_taxon]]),
    trait_name  = as.character(long$trait_name),
    trait_value = as.character(long$trait_value),
    unit_val    = if (!is.na(col_unit)) as.character(long[[col_unit]]) else NA_character_,
    lat_val     = if (!is.na(col_lat)) as.character(long[[col_lat]]) else NA_character_,
    lon_val     = if (!is.na(col_lon)) as.character(long[[col_lon]]) else NA_character_,
    col_taxon = col_taxon, col_trait = "pivoted_wide",
    col_value = "pivoted_wide", col_unit = col_unit
  )
}

log_rows <- list()
log_append <- function(fid, fp, status, rows_out = NA_integer_, msg = "") {
  log_rows[[length(log_rows) + 1L]] <<- list(
    provider_file_id = as.character(fid),
    file_path        = as.character(fp),
    status           = as.character(status),
    rows_out         = as.integer(rows_out),
    message          = as.character(msg)
  )
}

collapse_text <- function(...) {
  vals <- unlist(list(...), use.names = FALSE)
  if (!length(vals)) return("")
  vals <- trimws(as.character(vals))
  vals[is.na(vals)] <- ""
  tolower(paste(vals[nzchar(vals)], collapse = " | "))
}

collapse_text_vec <- function(...) {
  vals <- lapply(list(...), function(x) {
    x <- trimws(as.character(x))
    x[is.na(x)] <- ""
    x
  })
  if (!length(vals)) return(character())
  tolower(do.call(paste, c(vals, sep = " | ")))
}

normalize_missing_text <- function(x) {
  x <- trimws(as.character(x))
  x[is.na(x) | !nzchar(x) | tolower(x) %in% c("na", "nan", "null", "none")] <- NA_character_
  x
}

text_has_pattern <- function(text, pattern) {
  nzchar(text) && grepl(pattern, text, ignore.case = TRUE, perl = TRUE)
}

finalize_flag_string <- function(flags) {
  flags <- sort(unique(flags[!is.na(flags) & nzchar(flags)]))
  if (!length(flags)) NA_character_ else paste(flags, collapse = "|")
}

append_flag_list <- function(flag_list, idx, flag) {
  if (!length(idx)) return(flag_list)
  flag_list[idx] <- Map(c, flag_list[idx], rep(list(flag), length(idx)))
  flag_list
}

FRED_BIEN_STUDY_PATTERN <- paste(
  c(
    "\\btry\\b", "austraits", "traithub", "\\bgbif\\b", "rainbio", "\\becat\\b",
    "botanic(?:al)? garden", "herbari(?:um|a)", "floristic", "\\boccurrence(?:s)?\\b",
    "specimen", "forest inventory", "community weighted mean", "\\bcwm\\b",
    "predicted", "model(?:ed|ing)?", "range[ _-]?map", "random forest",
    "simulation", "phylogen", "species[ _-]?list", "checklist"
  ),
  collapse = "|"
)

FRED_GBIF_STUDY_PATTERN <- paste(
  c(
    "\\bgbif\\b", "herbari(?:um|a)", "specimen", "\\boccurrence(?:s)?\\b",
    "\\bflora\\b", "floristic", "voucher", "botanic(?:al)? garden",
    "collection", "forest inventory"
  ),
  collapse = "|"
)

FRED_NON_OBSERVATION_PATTERN <- paste(
  c(
    "community weighted mean", "\\bcwm\\b", "predicted", "model(?:ed|ing)?",
    "functional diversity", "\\bfdis\\b", "principal component", "\\bpca\\b",
    "ordination", "species[ _-]?list", "checklist", "range[ _-]?map",
    "random forest", "simulation"
  ),
  collapse = "|"
)

FRED_SEQUENCE_PATTERN <- paste(
  c(
    "sequence", "genome", "genomic", "genotype", "genotyp", "amplicon",
    "\\bits[0-9]*\\b", "\\bmatk\\b", "\\brbcl\\b", "\\bdna\\b", "\\brna\\b"
  ),
  collapse = "|"
)

study_qa_flags <- function(source_title, source_subjects, source_abstract, file_path) {
  text <- collapse_text(source_title, source_subjects, source_abstract, file_path)
  flags <- character()
  if (text_has_pattern(text, FRED_BIEN_STUDY_PATTERN)) {
    flags <- c(flags, "likely_already_in_bien_study")
  }
  if (text_has_pattern(text, FRED_GBIF_STUDY_PATTERN)) {
    flags <- c(flags, "possibly_in_gbif_study")
  }
  sort(unique(flags))
}

row_context_flags <- function(scrubbed_species_binomial, latitude, longitude,
                              trait_name, raw_trait_name,
                              source_title, source_subjects, source_abstract,
                              file_path) {
  flags <- character()
  species_val <- normalize_missing_text(scrubbed_species_binomial)
  lat_num <- suppressWarnings(as.numeric(latitude))
  lon_num <- suppressWarnings(as.numeric(longitude))
  context_text <- collapse_text(
    source_title, source_subjects, source_abstract, file_path,
    trait_name, raw_trait_name
  )

  if (is.na(species_val)) flags <- c(flags, "missing_species_id")
  if (!is.finite(lat_num) || !is.finite(lon_num)) flags <- c(flags, "missing_coordinates")
  if (text_has_pattern(context_text, FRED_NON_OBSERVATION_PATTERN)) {
    flags <- c(flags, "non_observation_trait_aggregate")
  }
  if (text_has_pattern(context_text, FRED_SEQUENCE_PATTERN)) {
    flags <- c(flags, "possible_sequence_or_genomic_source")
  }

  sort(unique(flags))
}

# ===========================================================================
# Step 1: Load and filter manifest
# ===========================================================================
cat("\n--- Step 1: Load and filter manifest ---\n")
manifest <- fread(manifest_path, encoding = "UTF-8")
cat("Manifest rows loaded:", nrow(manifest), "\n")
manifest[, file_size := suppressWarnings(as.numeric(file_size))]
manifest_file_text <- tolower(as.character(manifest$file_path))

keep <- rep(TRUE, nrow(manifest))
keep <- keep & (is.na(manifest$file_size) | manifest$file_size <= 100e6)
keep <- keep & !grepl(
  "SNP|genot|haplotype|\\.hmp\\.|imputed|sequence|fasta|vcf|bam|fastq|genome|genomic|genotype|genotyp|amplicon|\\bits[0-9]*\\b|\\bmatk\\b|\\brbcl\\b|\\bdna\\b|\\brna\\b",
  manifest_file_text, ignore.case = TRUE, perl = TRUE
)
keep <- keep & !grepl(
  "Figure[0-9]|Simulated|simulation|_DYNAMIC_|_INPUTS_|predicted|model(?:ed|ing)?|range[ _-]?map|community weighted mean|\\bcwm\\b|functional diversity|\\bfdis\\b|phylogen|ordination|\\bpca\\b|random forest|species[ _-]?list|checklist|readme|code_for_",
  manifest_file_text, ignore.case = TRUE, perl = TRUE
)
keep <- keep & !grepl(
  "climate|hobo_|logger|weather|precipitation|temperature",
  manifest_file_text, ignore.case = TRUE, perl = TRUE
)
keep <- keep & !(tolower(tools::file_ext(manifest$file_path)) == "txt" &
                   !is.na(manifest$file_size) & manifest$file_size > 5e6)
keep <- keep & !grepl("lookup|taxonomy|species_list|phylogen",
                      manifest_file_text, ignore.case = TRUE, perl = TRUE)

manifest_filtered <- manifest[keep]
cat("Files after filtering:", nrow(manifest_filtered), "\n")

# ===========================================================================
# Step 2a: Look up Dryad version IDs
# ===========================================================================
cat("\n--- Step 2a: Look up Dryad version IDs ---\n")
unique_dois <- unique(manifest_filtered$provider_dataset_id)
cat("Unique dataset DOIs:", length(unique_dois), "\n")

version_cache_path <- file.path(project_root, "output", "providers", "fred", "doi_version_cache.csv")
if (file.exists(version_cache_path)) {
  doi_to_version <- fread(version_cache_path)
  doi_to_version[, version_id := suppressWarnings(as.integer(version_id))]
} else {
  doi_to_version <- data.table(provider_dataset_id = character(0), version_id = integer(0))
}

need_lookup <- setdiff(unique_dois, doi_to_version[!is.na(version_id)]$provider_dataset_id)

if (length(need_lookup)) {
  cat("Looking up", length(need_lookup), "version IDs...\n")
  new_rows <- list()
  for (doi in need_lookup) {
    vid <- tryCatch(dryad_get_version_id(doi), error = function(e) NA_integer_)
    cat(sprintf("  %s -> %s\n", doi, if (is.na(vid)) "NA" else as.character(vid)))
    new_rows[[length(new_rows) + 1L]] <- data.table(provider_dataset_id = doi, version_id = vid)
    Sys.sleep(0.8)
  }
  doi_to_version <- rbindlist(c(list(doi_to_version), new_rows), fill = TRUE, use.names = TRUE)
  doi_to_version <- unique(doi_to_version, by = "provider_dataset_id")
  fwrite(doi_to_version, version_cache_path, na = "")
  cat("Version cache saved.\n")
}

manifest_filtered <- merge(manifest_filtered, doi_to_version, by = "provider_dataset_id", all.x = TRUE)
manifest_work <- manifest_filtered[!is.na(version_id)]
cat(sprintf("%d files with resolved version IDs; %d skipped (no version)\n",
            nrow(manifest_work), nrow(manifest_filtered) - nrow(manifest_work)))

# ===========================================================================
# Step 2b: Download version ZIPs
# ===========================================================================
cat("\n--- Step 2b: Download version ZIPs ---\n")
unique_versions <- unique(manifest_work$version_id)
cat("Unique version ZIPs:", length(unique_versions), "\n")

zip_paths <- setNames(vector("character", length(unique_versions)), as.character(unique_versions))

for (vid in unique_versions) {
  zip_dest <- file.path(download_dir, sprintf("version_%d.zip", vid))
  zip_paths[as.character(vid)] <- zip_dest
  if (file.exists(zip_dest) && file.info(zip_dest)$size > 0) {
    cat(sprintf("  SKIP (exists): version_%d.zip\n", vid))
    next
  }
  url <- sprintf("https://datadryad.org/api/v2/versions/%d/download", vid)
  cat(sprintf("  GET version_%d.zip ...", vid))
  r <- tryCatch(curl_download_file(url, zip_dest), error = function(e) list(ok = FALSE, http_code = 0L))
  if (r$ok) {
    cat(sprintf(" OK (%.1f KB)\n", file.info(zip_dest)$size / 1024))
  } else {
    cat(sprintf(" FAILED HTTP %d\n", r$http_code))
    if (file.exists(zip_dest)) file.remove(zip_dest)
  }
  Sys.sleep(1.2)
}

# ===========================================================================
# Step 2c: Extract target files from ZIPs
# ===========================================================================
cat("\n--- Step 2c: Extract files from ZIPs ---\n")
extracted_paths <- character(nrow(manifest_work))

for (i in seq_len(nrow(manifest_work))) {
  row     <- manifest_work[i]
  fid     <- as.character(row$provider_file_id)
  fp      <- as.character(row$file_path)
  vid     <- as.integer(row$version_id)
  zip_dst <- zip_paths[as.character(vid)]

  if (!nzchar(zip_dst) || !file.exists(zip_dst)) {
    log_append(fid, fp, "failed_download", msg = "ZIP not available"); next
  }

  ext_dir   <- file.path(download_dir, sprintf("v%d", vid))
  dir.create(ext_dir, recursive = TRUE, showWarnings = FALSE)
  dest_file <- file.path(ext_dir, basename(fp))

  if (file.exists(dest_file) && file.info(dest_file)$size > 0) {
    extracted_paths[i] <- dest_file
    log_append(fid, fp, "skipped_exists", msg = "already extracted")
    next
  }

  listing <- tryCatch(utils::unzip(zip_dst, list = TRUE), error = function(e) NULL)
  if (is.null(listing)) {
    log_append(fid, fp, "failed_download", msg = "ZIP unreadable"); next
  }

  target_bn <- basename(fp)
  matches   <- listing$Name[tolower(basename(listing$Name)) == tolower(target_bn)]

  if (!length(matches)) {
    log_append(fid, fp, "failed_download",
               msg = paste0("not found in ZIP (", nrow(listing), " files); sample: ",
                            paste(head(basename(listing$Name), 3), collapse = ", ")))
    next
  }

  ok <- tryCatch({
    utils::unzip(zip_dst, files = matches[[1]], exdir = ext_dir, junkpaths = TRUE)
    TRUE
  }, error = function(e) {
    log_append(fid, fp, "failed_download", msg = conditionMessage(e))
    FALSE
  })

  if (ok) {
    extracted_paths[i] <- dest_file
    log_append(fid, fp, "downloaded", msg = sprintf("extracted from v%d.zip", vid))
    cat(sprintf("  [%d/%d] %s\n", i, nrow(manifest_work), basename(dest_file)))
  }
}

# ===========================================================================
# Step 3+4: Parse and map to 58-column schema
# ===========================================================================
cat("\n--- Step 3+4: Parse and map ---\n")
timestamp_utc <- format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
compiled_list <- list()

for (i in seq_len(nrow(manifest_work))) {
  row <- manifest_work[i]
  fid <- as.character(row$provider_file_id)
  fp  <- as.character(row$file_path)
  dst <- extracted_paths[i]
  if (!nzchar(dst) || !file.exists(dst)) next

  ext <- tolower(tools::file_ext(dst))
  cat(sprintf("[parse %d/%d] %s\n", i, nrow(manifest_work), basename(dst)))

  raw_dt <- tryCatch({
    if (ext == "csv") {
      fread(dst, encoding = "UTF-8", fill = TRUE, showProgress = FALSE)
    } else if (ext %in% c("tsv", "tab")) {
      fread(dst, sep = "\t", encoding = "UTF-8", fill = TRUE, showProgress = FALSE)
    } else if (ext %in% c("xlsx", "xls")) {
      if (requireNamespace("openxlsx", quietly = TRUE)) {
        as.data.table(openxlsx::read.xlsx(dst, sheet = 1))
      } else {
        as.data.table(readxl::read_excel(dst, sheet = 1))
      }
    } else {
      fread(dst, encoding = "UTF-8", fill = TRUE, showProgress = FALSE)
    }
  }, error = function(e) { cat("  PARSE ERROR:", conditionMessage(e), "\n"); NULL })

  if (is.null(raw_dt) || nrow(raw_dt) == 0L) {
    log_append(fid, fp, "failed_parse", msg = "empty or unreadable"); next
  }

  long_dt <- tryCatch(parse_to_long(raw_dt), error = function(e) NULL)
  if (is.null(long_dt) || nrow(long_dt) == 0L) {
    log_append(fid, fp, "uninterpretable",
               msg = "no taxon column or insufficient structure"); next
  }

  n <- nrow(long_dt)
  lat_num <- suppressWarnings(as.numeric(long_dt$lat_val))
  lon_num <- suppressWarnings(as.numeric(long_dt$lon_val))
  study_flags <- study_qa_flags(
    source_title = row$source_title,
    source_subjects = row$source_subjects,
    source_abstract = row$source_abstract,
    file_path = fp
  )
  row_context_text <- collapse_text_vec(
    rep(as.character(row$source_title), n),
    rep(as.character(row$source_subjects), n),
    rep(as.character(row$source_abstract), n),
    rep(fp, n),
    long_dt$trait_name,
    long_dt$taxon
  )
  flag_list <- lapply(seq_len(n), function(...) study_flags)

  species_missing <- is.na(normalize_missing_text(long_dt$taxon))
  coords_missing <- !is.finite(lat_num) | !is.finite(lon_num)
  non_observation_rows <- grepl(FRED_NON_OBSERVATION_PATTERN, row_context_text,
                                ignore.case = TRUE, perl = TRUE)
  sequence_rows <- grepl(FRED_SEQUENCE_PATTERN, row_context_text,
                         ignore.case = TRUE, perl = TRUE)

  flag_list <- append_flag_list(flag_list, which(species_missing), "missing_species_id")
  flag_list <- append_flag_list(flag_list, which(coords_missing), "missing_coordinates")
  flag_list <- append_flag_list(flag_list, which(non_observation_rows), "non_observation_trait_aggregate")
  flag_list <- append_flag_list(flag_list, which(sequence_rows), "possible_sequence_or_genomic_source")
  qa_flags <- vapply(flag_list, finalize_flag_string, character(1))

  out <- data.table(
    scrubbed_species_binomial = long_dt$taxon,
    latitude                  = lat_num,
    longitude                 = lon_num,
    date_collected            = NA_character_,
    dataset                   = "FRED_sourced_dryad",
    datasource                = "fred",
    dataowner                 = as.character(row$source_authors),
    collection_code           = NA_character_,
    trait_name                = long_dt$trait_name,
    trait_value               = long_dt$trait_value,
    unit                      = long_dt$unit_val,
    inferred_unit             = NA_character_,
    method                    = NA_character_,
    country                   = NA_character_,
    stateProvince             = NA_character_,
    county                    = NA_character_,
    locality                  = NA_character_,
    elevation_m               = NA_real_,
    expected_unit_class       = NA_character_,
    value_type                = NA_character_,
    standard_unit             = NA_character_,
    trait_dictionary_notes    = NA_character_,
    dryad_dataset_doi         = as.character(row$provider_dataset_id),
    dryad_version_id          = as.character(row$version_id),
    dryad_file_id             = as.integer(fid),
    source_title              = as.character(row$source_title),
    source_authors            = as.character(row$source_authors),
    source_subjects           = as.character(row$source_subjects),
    source_abstract           = as.character(row$source_abstract),
    download_timestamp_utc    = timestamp_utc,
    source_file_path          = dst,
    original_row_number       = seq_len(n),
    raw_taxon                 = long_dt$taxon,
    raw_trait_name            = long_dt$trait_name,
    raw_trait_value           = long_dt$trait_value,
    raw_unit                  = long_dt$unit_val,
    raw_latitude              = long_dt$lat_val,
    raw_longitude             = long_dt$lon_val,
    raw_elevation             = NA_character_,
    raw_country               = NA_character_,
    raw_stateProvince         = NA_character_,
    raw_county                = NA_character_,
    raw_locality              = NA_character_,
    raw_date_collected        = NA_character_,
    input_name_verbatim       = long_dt$taxon,
    infraspecific_rank        = NA_character_,
    infraspecific_epithet     = NA_character_,
    source_column_taxon       = long_dt$col_taxon,
    source_column_trait_name  = long_dt$col_trait,
    source_column_trait_value = long_dt$col_value,
    source_column_unit        = long_dt$col_unit,
    qa_flags                  = qa_flags,
    inferred_unit_value       = NA_character_,
    inferred_unit_confidence  = "none",
    inference_evidence        = NA_character_,
    inference_citation_keys   = "FRED_manifest_2026",
    basis_type                = NA_character_,
    unit_conversion_factor    = NA_real_
  )

  cat(sprintf("  -> %d rows\n", n))
  compiled_list[[length(compiled_list) + 1L]] <- out

  # Update log
  idx <- which(vapply(log_rows, function(x) x$provider_file_id == fid, logical(1)))
  if (length(idx)) {
    log_rows[[idx[[1L]]]]$status   <- "compiled"
    log_rows[[idx[[1L]]]]$rows_out <- n
  } else {
    log_append(fid, fp, "compiled", rows_out = n)
  }
}

# ===========================================================================
# Step 5: Write output
# ===========================================================================
cat("\n--- Step 5: Write output ---\n")

if (!length(compiled_list)) {
  compiled <- data.table(matrix(NA_character_, 0L, length(FINAL_COLS)))
  setnames(compiled, FINAL_COLS)
} else {
  compiled <- rbindlist(compiled_list, fill = TRUE, use.names = TRUE)
  for (mc in setdiff(FINAL_COLS, names(compiled))) compiled[, (mc) := NA_character_]
  setcolorder(compiled, FINAL_COLS)
}

if (file.exists(compiled_out) && nrow(compiled) > 0L) {
  existing <- fread(compiled_out, encoding = "UTF-8")
  refreshed_ids <- unique(compiled$dryad_file_id)
  keep_existing <- existing[!dryad_file_id %in% refreshed_ids]
  merged_out <- rbindlist(list(keep_existing, compiled), fill = TRUE, use.names = TRUE)
  if (nrow(compiled) > 0L) {
    fwrite(merged_out, compiled_out, na = "")
    cat(sprintf("Refreshed %d rows across %d file IDs.\n", nrow(compiled), length(refreshed_ids)))
  } else {
    cat("All rows already present — no refresh needed.\n")
  }
} else {
  fwrite(compiled, compiled_out, na = "")
  cat(sprintf("Wrote %d rows to %s\n", nrow(compiled), compiled_out))
}

log_dt <- rbindlist(lapply(log_rows, as.data.table), fill = TRUE, use.names = TRUE)
if (!nrow(log_dt)) {
  log_dt <- data.table(provider_file_id = character(), file_path = character(),
                       status = character(), rows_out = integer(), message = character())
}
fwrite(log_dt, log_out, na = "")
cat(sprintf("Log: %d entries -> %s\n", nrow(log_dt), log_out))

# ===========================================================================
# Summary
# ===========================================================================
cat("\n=== FRED INGEST SUMMARY ===\n")
final_out <- if (file.exists(compiled_out)) fread(compiled_out, encoding = "UTF-8") else compiled
stbl <- if (nrow(log_dt)) table(log_dt$status) else table(character(0))
gn <- function(nm) if (nm %in% names(stbl)) stbl[[nm]] else 0L

cat(sprintf("Files attempted:      %d\n", nrow(manifest_work)))
cat(sprintf("  downloaded:         %d\n", gn("downloaded")))
cat(sprintf("  skipped_exists:     %d\n", gn("skipped_exists")))
cat(sprintf("  failed_download:    %d\n", gn("failed_download")))
cat(sprintf("  failed_parse:       %d\n", gn("failed_parse")))
cat(sprintf("  uninterpretable:    %d\n", gn("uninterpretable")))
cat(sprintf("  compiled:           %d\n", gn("compiled")))
cat(sprintf("Total rows in output: %d\n", nrow(final_out)))
cat(sprintf("Unique species:       %d\n",
            length(unique(final_out$scrubbed_species_binomial[!is.na(final_out$scrubbed_species_binomial)]))))
cat(sprintf("Unique traits:        %d\n",
            length(unique(final_out$trait_name[!is.na(final_out$trait_name)]))))
qa_values <- final_out$qa_flags[!is.na(final_out$qa_flags) & nzchar(final_out$qa_flags)]
if (length(qa_values)) {
  qa_counts <- sort(table(unlist(strsplit(qa_values, "\\|", perl = TRUE))), decreasing = TRUE)
  cat("Top qa_flags:\n")
  for (flag_name in names(head(qa_counts, 10L))) {
    cat(sprintf("  %s: %d\n", flag_name, qa_counts[[flag_name]]))
  }
} else {
  cat("Top qa_flags: none\n")
}
cat("===========================\n")
