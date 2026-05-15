# confidence_utils.R — Confidence tier assignment and anchor species plausibility gate
#
# assign_confidence_tiers(): merges range overlap and occurrence counts into a single
# species data.frame, then assigns each species to one of four confidence tiers based
# on the combined evidence. The tier system is designed for conservation triage in
# regions where BIEN data coverage is heterogeneous.
#
# check_anchor_species(): a binary plausibility gate that checks whether well-known
# western Amazonian indicator species appear in the query results. A FAIL does not
# mean those species are absent — it may indicate a CRS mismatch, a BIEN coverage
# gap, or that the polygon does not include suitable habitat. See CFG$ANCHOR_SPECIES.

#' Merge range overlap and occurrence evidence; assign confidence tiers.
#'
#' Tier thresholds (both overlap_pct_polygon and n_occurrences are used):
#'   High      — n_occ ≥ 20  AND overlap_pct_polygon ≥ 25%  (strong dual evidence)
#'   Moderate  — n_occ ≥ 5   AND overlap_pct_polygon ≥ 10%  (moderate dual evidence)
#'   Low       — n_occ ≥ 2   OR  overlap_pct_polygon ≥ 2%   (any credible evidence)
#'   Very Low  — all remaining (checklist-only, no occurrence evidence)
#'
#' overlap_pct_polygon: fraction of the AOI predicted suitable by the range model.
#' overlap_pct_range:   fraction of the species' global range inside the AOI (endemism proxy).
#'
#' Both range columns are retained as display columns regardless of tier calculation.
assign_confidence_tiers <- function(ranges_sf, occ_counts_df) {

  if (!is.null(ranges_sf) && nrow(ranges_sf) > 0 && inherits(ranges_sf, "sf")) {
    ranges_df <- sf::st_drop_geometry(ranges_sf)

    # Detect species name column
    species_col <- NULL
    for (candidate in c("species", "range_name", "scrubbed_species_binomial")) {
      if (candidate %in% names(ranges_df)) { species_col <- candidate; break }
    }
    if (is.null(species_col)) {
      non_geom <- setdiff(names(ranges_df), attr(ranges_sf, "sf_column"))
      if (length(non_geom) > 0) species_col <- non_geom[1]
    }

    overlap_poly_col  <- "overlap_pct_polygon"
    overlap_range_col <- "overlap_pct_range"

    if (!is.null(species_col) && overlap_poly_col %in% names(ranges_df)) {
      keep_cols <- intersect(c(species_col, overlap_poly_col, overlap_range_col),
                             names(ranges_df))
      ranges_tbl <- ranges_df[, keep_cols, drop = FALSE]
      names(ranges_tbl)[1] <- "accepted_name"
      # ensure both overlap columns present
      if (!overlap_poly_col  %in% names(ranges_tbl)) ranges_tbl$overlap_pct_polygon <- 0
      if (!overlap_range_col %in% names(ranges_tbl)) ranges_tbl$overlap_pct_range   <- 0
      ranges_tbl <- ranges_tbl[!is.na(ranges_tbl$accepted_name), ]
    } else {
      ranges_tbl <- data.frame(accepted_name = character(),
                               overlap_pct_polygon = numeric(),
                               overlap_pct_range   = numeric(),
                               stringsAsFactors = FALSE)
    }
  } else {
    ranges_tbl <- data.frame(accepted_name = character(),
                             overlap_pct_polygon = numeric(),
                             overlap_pct_range   = numeric(),
                             stringsAsFactors = FALSE)
  }

  if (!is.null(occ_counts_df) && nrow(occ_counts_df) > 0) {
    occ_df <- as.data.frame(occ_counts_df)
    if ("species" %in% names(occ_df)) names(occ_df)[names(occ_df) == "species"] <- "accepted_name"
    if (!"n_occurrences"     %in% names(occ_df)) occ_df$n_occurrences     <- 0L
    if (!"family"            %in% names(occ_df)) occ_df$family             <- NA_character_
    if (!"native_status_flag"%in% names(occ_df)) occ_df$native_status_flag <- "status_unavailable"
    occ_df <- occ_df[!is.na(occ_df$accepted_name), ]
    occ_df <- occ_df[, intersect(c("accepted_name","n_occurrences","family","native_status_flag"),
                                 names(occ_df)), drop = FALSE]
  } else {
    occ_df <- data.frame(accepted_name = character(), n_occurrences = integer(),
                         family = character(), native_status_flag = character(),
                         stringsAsFactors = FALSE)
  }

  merged <- merge(ranges_tbl, occ_df, by = "accepted_name", all = TRUE)

  merged$overlap_pct_polygon[is.na(merged$overlap_pct_polygon)] <- 0
  merged$overlap_pct_range[is.na(merged$overlap_pct_range)]     <- 0
  merged$n_occurrences[is.na(merged$n_occurrences)]             <- 0L
  merged$family[is.na(merged$family)]                           <- NA_character_
  merged$native_status_flag[is.na(merged$native_status_flag)]   <- "status_unavailable"

  # Tier logic: dual-evidence (range + occurrence) promotes a species to High or Moderate;
  # single-evidence OR threshold gives Low. Very Low is the default for checklist-only
  # species returned by Stage 1 with no occurrence records in the polygon.
  # Thresholds were calibrated against the Alto Japurá pilot dataset (250,000 km² AOI).
  merged$confidence_tier <- dplyr::case_when(
    merged$n_occurrences >= 20 & merged$overlap_pct_polygon >= 25 ~ "High",
    merged$n_occurrences >= 5  & merged$overlap_pct_polygon >= 10 ~ "Moderate",
    merged$n_occurrences >= 2  | merged$overlap_pct_polygon >= 2  ~ "Low",
    TRUE                                                           ~ "Very Low"
  )

  merged$iucn_status <- "Not queried (Phase 2)"

  result <- data.frame(
    accepted_name      = merged$accepted_name,
    family             = merged$family,
    confidence_tier    = merged$confidence_tier,
    data_support_n     = as.integer(merged$n_occurrences),
    overlap_pct_polygon= round(merged$overlap_pct_polygon, 2),
    overlap_pct_range  = round(merged$overlap_pct_range, 2),
    native_status_flag = merged$native_status_flag,
    iucn_status        = merged$iucn_status,
    stringsAsFactors   = FALSE
  )

  tier_order <- c("High", "Moderate", "Low", "Very Low")
  result$confidence_tier <- factor(result$confidence_tier, levels = tier_order)
  result <- result[order(result$confidence_tier, result$accepted_name), ]
  result$confidence_tier <- as.character(result$confidence_tier)

  rownames(result) <- NULL
  result
}


#' Anchor species plausibility gate.
#' Returns a named logical vector (TRUE = species found, FALSE = not found).
#' A FAIL on a western Amazonian indicator species should trigger a user-visible
#' warning in the Data Quality tab, prompting review of the input polygon and CRS.
check_anchor_species <- function(species_df) {
  CFG <- getOption("bien_cfg")
  if (is.null(species_df) || nrow(species_df) == 0) {
    return(setNames(rep(FALSE, length(CFG$ANCHOR_SPECIES)), CFG$ANCHOR_SPECIES))
  }
  setNames(CFG$ANCHOR_SPECIES %in% species_df$accepted_name, CFG$ANCHOR_SPECIES)
}
