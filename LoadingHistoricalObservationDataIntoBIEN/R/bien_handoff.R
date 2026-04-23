build_bien_loading_table <- function(dwc_df, taxonomy_cap = 50) {
  if (!is.data.frame(dwc_df) || nrow(dwc_df) == 0) {
    stop("dwc_df must be a non-empty data.frame")
  }

  req <- required_dwc_terms()
  missing <- setdiff(req, names(dwc_df))
  for (m in missing) {
    dwc_df[[m]] <- NA_character_
  }

  dwc_df <- augment_bien_pipeline(dwc_df, taxonomy_cap = taxonomy_cap)
  dwc_df$ready_for_bien <- !is.na(dwc_df$scientificName) &
    trimws(as.character(dwc_df$scientificName)) != "" &
    (is.na(dwc_df$coordinate_issue) | dwc_df$coordinate_issue %in% c("", "missing_coordinates"))

  # Add explicit staging columns for BIEN loading handoff while preserving mapped Darwin Core fields.
  dwc_df$staging_record_id <- seq_len(nrow(dwc_df))
  dwc_df$scientificName_submitted <- as.character(dwc_df$scientificName)
  dwc_df$scientificName_matched <- as.character(dwc_df$bien_matched_name)
  dwc_df$taxonomy_match_status <- as.character(dwc_df$bien_taxonomy_status)
  dwc_df$coordinate_status <- ifelse(
    !is.na(dwc_df$coordinate_valid_basic) & dwc_df$coordinate_valid_basic == TRUE,
    "basic_valid",
    ifelse(is.na(dwc_df$coordinate_issue) | as.character(dwc_df$coordinate_issue) == "", "unknown", as.character(dwc_df$coordinate_issue))
  )
  dwc_df$gnrs_status <- as.character(dwc_df$gnrs_status)
  dwc_df$tnrs_status <- as.character(dwc_df$tnrs_status)
  dwc_df$gvs_status <- as.character(dwc_df$gvs_status)
  dwc_df$nsr_status <- as.character(dwc_df$nsr_status)
  dwc_df$staging_notes <- ifelse(
    !is.na(dwc_df$ready_for_bien) & dwc_df$ready_for_bien == TRUE,
    "record appears ready for BIEN staging after external handoff checks",
    "record needs review before BIEN staging"
  )

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
    canonicalName = safe_col("scientificName_matched"),
    bien_matched_name = safe_col("bien_matched_name"),
    bien_taxonomy_status = safe_col("bien_taxonomy_status"),
    tnrs_status = safe_col("tnrs_status"),
    stringsAsFactors = FALSE
  )

  gnrs <- data.frame(
    gnrs_query_id = safe_col("gnrs_query_id"),
    occurrenceID = safe_col("occurrenceID"),
    country = safe_col("gnrs_input_country"),
    stateProvince = safe_col("gnrs_input_stateProvince"),
    county = safe_col("gnrs_input_county"),
    locality = safe_col("gnrs_input_locality"),
    decimalLatitude = safe_col("decimalLatitude"),
    decimalLongitude = safe_col("decimalLongitude"),
    coordinateUncertaintyInMeters = safe_col("coordinateUncertaintyInMeters"),
    gnrs_status = safe_col("gnrs_status"),
    gnrs_ready_for_submission = safe_col("gnrs_ready_for_submission"),
    stringsAsFactors = FALSE
  )

  gvs <- data.frame(
    occurrenceID = safe_col("occurrenceID"),
    decimalLatitude = safe_col("decimalLatitude"),
    decimalLongitude = safe_col("decimalLongitude"),
    coordinateUncertaintyInMeters = safe_col("coordinateUncertaintyInMeters"),
    coordinate_valid_basic = safe_col("coordinate_valid_basic"),
    coordinate_issue = safe_col("coordinate_issue"),
    gvs_status = safe_col("gvs_status"),
    stringsAsFactors = FALSE
  )

  nsr <- data.frame(
    occurrenceID = safe_col("occurrenceID"),
    scientificName = safe_col("scientificName"),
    country = safe_col("country"),
    nsr_status = safe_col("nsr_status"),
    stringsAsFactors = FALSE
  )

  list(tnrs = tnrs, gnrs = gnrs, gvs = gvs, nsr = nsr)
}
