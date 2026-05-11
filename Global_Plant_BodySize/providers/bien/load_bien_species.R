## Global_Plant_BodySize/providers/bien/load_bien_species.R
## Stage 1: Retrieve the complete BIEN species list.
##
## Uses BIEN::BIEN_species_list() to fetch all vascular plant species in BIEN
## (New World; ~150,000 species as of BIEN v4.x).
##
## Output: output/bien_species_list.csv — one row per species with taxonomy
##   columns. This file is the authoritative species roster for all downstream
##   stages. Species absent from trait files are carried forward with
##   trait_data_available = FALSE in Stage 8 (finalize).
##
## NOTE: BIEN_species_list() does not guarantee completeness relative to the
##   full BIEN database. Verify record count against known BIEN totals after run.
##
## Written by: Global_Plant_BodySize pipeline (ecology-user agent, 2026-05-11)

## ---- Dependencies -----------------------------------------------------------
if (!requireNamespace("BIEN", quietly = TRUE))
  stop("Install the BIEN package: install.packages('BIEN')")
if (!requireNamespace("data.table", quietly = TRUE))
  stop("Install data.table: install.packages('data.table')")

## ---- Constants --------------------------------------------------------------
BIEN_SOURCE_ID     <- "bien"
BIEN_ACCESS_DATE   <- as.character(Sys.Date())

## ---- Main intake function ---------------------------------------------------
## Arguments:
##   output_file : path to write species list CSV
##   overwrite   : if FALSE (default), skip if file already exists
##
## Returns: data.frame (invisibly)

run_bien_species_intake <- function(
    output_file = "output/bien_species_list.csv",
    overwrite   = FALSE
) {
  if (file.exists(output_file) && !overwrite) {
    message("[Stage 1] Species list already exists: ", output_file,
            "\n  Use overwrite=TRUE to re-query BIEN.")
    return(invisible(data.table::fread(output_file, data.table = FALSE)))
  }

  ## NOTE 2026-05-11: BIEN v1.2.8 does not export BIEN_species_list().
  ## The correct function is BIEN_list_all(), verified via ls('package:BIEN').
  message("[Stage 1] Querying BIEN_list_all() ...")
  message("  This may take 1-5 minutes depending on server load.")

  spp <- tryCatch(
    BIEN::BIEN_list_all(),
    error = function(e) stop(
      "[Stage 1] BIEN_list_all() failed: ", conditionMessage(e),
      "\n  Check BIEN server status or your internet connection."
    )
  )

  if (is.null(spp) || nrow(spp) == 0)
    stop("[Stage 1] BIEN_species_list() returned no data.")

  ## Standardize column names (BIEN may return varying case/whitespace)
  names(spp) <- tolower(gsub("[[:space:]]+", "_", names(spp)))

  ## Required column check
  if (!"species" %in% names(spp))
    stop(
      "[Stage 1] Expected column 'species' not found. Actual columns: ",
      paste(names(spp), collapse = ", ")
    )

  ## Parse genus from species name (first word)
  spp$genus <- sub(" .*", "", spp$species)

  ## Add provenance columns
  spp$source_id          <- BIEN_SOURCE_ID
  spp$source_access_date <- BIEN_ACCESS_DATE
  spp$n_species_total    <- nrow(spp)   # total roster size (constant for all rows)

  ## Sort for reproducibility
  spp <- spp[order(spp$species), ]

  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(spp, output_file)

  message("[Stage 1] Done. ", nrow(spp), " species written to: ", output_file)
  invisible(spp)
}
