## GlobalBodySize/providers/amphibio/load_amphibio.R
## Intake script for AmphiBIO — global database for amphibian ecological traits
##
## Reference:
##   Oliveira BF, São-Pedro VA, Santos-Barrera G, Penone C, Costa GC. 2017.
##   AmphiBIO, a global database for amphibian ecological traits.
##   Scientific Data 4:170123. DOI: 10.1038/sdata.2017.123
##
## Data hosted on Figshare:
##   DOI: 10.6084/m9.figshare.4644424
##   The Figshare API is used to resolve the current download URL.
##
## Body mass column: "Body_mass_g" (grams)
## Species column:   "Species" (binomial)
## SVL column:       "SVL_max" (max snout-vent length in mm — cross-check)
##
## NOTE: AmphiBIO body_mass_g is often NA; the database is primarily morphometric.
##       SVL and body size fields are more complete than mass directly.

## ---- Constants --------------------------------------------------------------

AMPHIBIO_FIGSHARE_ARTICLE_ID <- 4644424
AMPHIBIO_FIGSHARE_API        <- sprintf(
  "https://api.figshare.com/v2/articles/%d", AMPHIBIO_FIGSHARE_ARTICLE_ID
)
AMPHIBIO_SOURCE_ID  <- "amphibio_oliveira2017"
AMPHIBIO_DISPLAY    <- "AmphiBIO (Oliveira et al. 2017)"
AMPHIBIO_DOI        <- "10.1038/sdata.2017.123"
AMPHIBIO_DATA_DOI   <- "10.6084/m9.figshare.4644424"
AMPHIBIO_CITATION   <- paste0(
  "Oliveira BF, S\u00e3o-Pedro VA, Santos-Barrera G, Penone C, Costa GC. 2017. ",
  "AmphiBIO, a global database for amphibian ecological traits. ",
  "Scientific Data 4:170123. https://doi.org/10.1038/sdata.2017.123"
)

## ---- Resolve download URL via Figshare API ----------------------------------

.amphibio_get_download_url <- function() {
  tmp <- tempfile(fileext = ".json")
  on.exit(unlink(tmp), add = TRUE)

  cmd <- sprintf("curl -s -L '%s' -o '%s'", AMPHIBIO_FIGSHARE_API, tmp)
  rc  <- system(cmd, ignore.stdout = TRUE, ignore.stderr = TRUE)
  if (rc != 0 || !file.exists(tmp) || file.size(tmp) < 10) {
    warning("Failed to query Figshare API for AmphiBIO; using fallback URL")
    ## Fallback: try known ndownloader URL for this article (may change with new versions)
    return("https://figshare.com/ndownloader/articles/4644424/versions/2")
  }

  meta <- tryCatch(
    jsonlite::fromJSON(tmp, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.null(meta)) {
    warning("Failed to parse Figshare API response for AmphiBIO")
    return(NULL)
  }

  ## Extract CSV file download URL from files list
  files <- meta$files
  if (is.null(files) || !length(files)) {
    warning("No files found in Figshare API response for AmphiBIO article ", AMPHIBIO_FIGSHARE_ARTICLE_ID)
    return(NULL)
  }

  ## Prefer CSV file
  file_names <- vapply(files, function(f) f$name %||% "", character(1))
  csv_idx    <- grep("\\.csv$", file_names, ignore.case = TRUE)[1]
  if (!is.na(csv_idx)) {
    url <- files[[csv_idx]]$download_url
    message("AmphiBIO: resolved download URL for ", file_names[csv_idx])
    return(url)
  }

  ## Fall back to first file
  url <- files[[1]]$download_url
  message("AmphiBIO: no CSV found, using first file: ", file_names[1])
  url
}

`%||%` <- function(x, y) if (is.null(x)) y else x

## ---- Download ---------------------------------------------------------------

download_amphibio <- function(dest_dir = "data/raw/amphibio", overwrite = FALSE) {
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)

  ## Look specifically for the main data CSV (not the references file)
  known_data_csv <- file.path(dest_dir, "AmphiBIO_v1.csv")
  if (file.exists(known_data_csv) && file.size(known_data_csv) > 10000 && !overwrite) {
    message("AmphiBIO already downloaded: ", known_data_csv)
    return(known_data_csv)
  }

  ## Fallback: find any large CSV (data file >> references file in size)
  existing_csv <- list.files(dest_dir, pattern = "\\.csv$", full.names = TRUE)
  if (length(existing_csv) && !overwrite) {
    sizes <- file.size(existing_csv)
    big   <- existing_csv[sizes == max(sizes)]
    if (max(sizes) > 500000) {  # data CSV is ~5MB; references is ~200KB
      message("AmphiBIO already downloaded (largest CSV): ", big)
      return(big)
    }
  }

  url <- .amphibio_get_download_url()
  if (is.null(url)) stop("Could not resolve AmphiBIO download URL. Download manually to: ", dest_dir)

  ## Download to a temp file first so we can inspect the file type
  tmp_dest <- file.path(dest_dir, "AmphiBIO_download.tmp")
  message("Downloading AmphiBIO from: ", url)
  tryCatch(
    download.file(url, tmp_dest, mode = "wb", quiet = FALSE),
    error = function(e) stop("Failed to download AmphiBIO: ", conditionMessage(e), call. = FALSE)
  )

  ## Determine if this is a zip or CSV by magic bytes
  if (.is_zip(tmp_dest)) {
    message("AmphiBIO download is a zip archive, unzipping...")
    ## Use system unzip for reliability (R's unzip() can fail on some zip variants)
    rc <- system(sprintf("unzip -o '%s' -d '%s'", tmp_dest, dest_dir),
                 ignore.stdout = FALSE, ignore.stderr = FALSE)
    if (rc != 0) {
      ## Fallback to R's unzip
      tryCatch(unzip(tmp_dest, exdir = dest_dir),
               error = function(e) stop("Failed to unzip AmphiBIO: ", conditionMessage(e)))
    }
    unlink(tmp_dest)
    csv_files <- list.files(dest_dir, pattern = "\\.csv$", full.names = TRUE)
    if (!length(csv_files)) stop("No CSV found after unzipping AmphiBIO archive in: ", dest_dir)
    ## Pick the largest CSV — the data file is much bigger than the references CSV
    csv_sizes <- file.size(csv_files)
    dest <- csv_files[which.max(csv_sizes)]
    message("AmphiBIO CSV (largest): ", dest)
  } else {
    ## Treat as CSV directly
    dest <- file.path(dest_dir, "AmphiBIO_v1.csv")
    file.rename(tmp_dest, dest)
  }

  dest
}

.is_zip <- function(path) {
  tryCatch({
    con <- file(path, "rb")
    on.exit(close(con))
    magic <- readBin(con, raw(), n = 4)
    identical(magic[1:2], as.raw(c(0x50, 0x4b)))
  }, error = function(e) FALSE)
}

## ---- Parse ------------------------------------------------------------------

parse_amphibio <- function(raw_file) {
  raw <- tryCatch(
    data.table::fread(raw_file, header = TRUE,
                      na.strings = c("NA", "", " ", "N/A"),
                      data.table = FALSE),
    error = function(e) stop("Failed to read AmphiBIO file: ", conditionMessage(e), call. = FALSE)
  )

  ## Detect columns — UNVERIFIED: confirm against actual file
  species_col  <- intersect(c("Species", "species", "Binomial"), names(raw))[1]
  mass_col     <- intersect(c("Body_mass_g", "body_mass_g", "Mass_g", "mass_g"), names(raw))[1]
  svl_col      <- intersect(c("SVL_max", "svl_max", "Max_SVL"), names(raw))[1]

  if (is.na(species_col)) stop("Cannot find species column in AmphiBIO. Names: ",
                                paste(names(raw)[1:20], collapse = ", "))
  if (is.na(mass_col)) {
    warning("Cannot find body mass column in AmphiBIO. Will use SVL as proxy if available. Names: ",
            paste(names(raw)[1:20], collapse = ", "))
  }

  has_mass <- !is.na(mass_col) && mass_col %in% names(raw)
  mass_vals <- if (has_mass) suppressWarnings(as.numeric(raw[[mass_col]])) else rep(NA_real_, nrow(raw))

  svl_note <- ""
  if (!is.na(svl_col) && svl_col %in% names(raw)) {
    svl_note <- paste0(" | SVL_max_mm=", raw[[svl_col]])
  }

  out <- data.frame(
    source_id              = AMPHIBIO_SOURCE_ID,
    source_display_name    = AMPHIBIO_DISPLAY,
    source_doi             = AMPHIBIO_DOI,
    source_access_date     = as.character(Sys.Date()),
    bibliographic_citation = AMPHIBIO_CITATION,
    dataset_id             = AMPHIBIO_SOURCE_ID,
    original_row_id        = seq_len(nrow(raw)),
    source_file_path       = basename(raw_file),

    verbatim_taxon_name    = raw[[species_col]],
    verbatim_authorship    = NA_character_,
    input_taxonomic_group  = "amphibian",
    input_taxonomic_rank   = "species",

    mass_g                 = mass_vals,
    mass_g_min             = NA_real_,
    mass_g_max             = NA_real_,
    mass_se                = NA_real_,
    mass_n                 = NA_integer_,

    mass_type              = "wet",
    measurement_method     = "literature_mean",
    life_stage             = "adult",
    sex                    = "pooled",

    decimal_latitude       = NA_real_,
    decimal_longitude      = NA_real_,
    coordinate_uncertainty_m = NA_real_,
    country_code           = NA_character_,

    year_measured          = NA_integer_,
    date_measured          = NA_character_,

    measurement_type       = "body mass",
    measurement_unit       = "g",
    basis_of_record        = "Literature",

    mass_confidence        = "medium",
    qa_status              = NA_character_,
    qa_note                = paste0("AmphiBIO", svl_note),

    stringsAsFactors = FALSE
  )

  ## AmphiBIO mass is sparse — retain all rows (including NA mass) so SVL qa_note is preserved,
  ## but filter to rows with mass > 0 for the compiled body mass table
  n_total  <- nrow(out)
  out      <- out[!is.na(out$mass_g) & out$mass_g > 0, ]
  message("AmphiBIO: ", nrow(out), " rows with body mass (of ", n_total, " species total)")
  if (nrow(out) < 100) {
    message("NOTE: AmphiBIO body mass coverage is sparse (~",
            round(100 * nrow(out) / n_total), "%). ",
            "Consider supplementing with AmphibiaWeb or primary literature.")
  }
  out
}

## ---- Master runner ----------------------------------------------------------

run_amphibio_intake <- function(dest_dir   = "data/raw/amphibio",
                                output_file = "data/compiled/amphibio_compiled.csv",
                                overwrite_download = FALSE) {
  raw_file <- download_amphibio(dest_dir, overwrite = overwrite_download)
  out      <- parse_amphibio(raw_file)
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(out, output_file)
  message("AmphiBIO compiled: ", nrow(out), " rows -> ", output_file)
  invisible(out)
}
