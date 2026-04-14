build_bien_loading_table <- function(dwc_df) {
  if (!is.data.frame(dwc_df) || nrow(dwc_df) == 0) {
    stop("dwc_df must be a non-empty data.frame")
  }

  req <- required_dwc_terms()
  missing <- setdiff(req, names(dwc_df))
  for (m in missing) {
    dwc_df[[m]] <- NA_character_
  }

  dwc_df$tnrs_status <- "pending"
  dwc_df$gnrs_status <- "pending"
  dwc_df$gvs_status <- "pending"
  dwc_df$nsr_status <- "pending"
  dwc_df$ready_for_bien <- FALSE

  dwc_df
}

build_bien_handoff_tables <- function(dwc_df) {
  if (!is.data.frame(dwc_df) || nrow(dwc_df) == 0) {
    stop("dwc_df must be a non-empty data.frame")
  }

  safe_col <- function(x) if (x %in% names(dwc_df)) dwc_df[[x]] else NA_character_

  tnrs <- data.frame(
    occurrenceID = safe_col("occurrenceID"),
    scientificName = safe_col("scientificName"),
    stringsAsFactors = FALSE
  )

  gnrs <- data.frame(
    occurrenceID = safe_col("occurrenceID"),
    country = safe_col("country"),
    stateProvince = safe_col("stateProvince"),
    county = safe_col("county"),
    locality = safe_col("locality"),
    stringsAsFactors = FALSE
  )

  gvs <- data.frame(
    occurrenceID = safe_col("occurrenceID"),
    decimalLatitude = safe_col("decimalLatitude"),
    decimalLongitude = safe_col("decimalLongitude"),
    coordinateUncertaintyInMeters = safe_col("coordinateUncertaintyInMeters"),
    stringsAsFactors = FALSE
  )

  nsr <- data.frame(
    occurrenceID = safe_col("occurrenceID"),
    scientificName = safe_col("scientificName"),
    country = safe_col("country"),
    stringsAsFactors = FALSE
  )

  list(tnrs = tnrs, gnrs = gnrs, gvs = gvs, nsr = nsr)
}
