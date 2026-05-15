assign_confidence_tiers <- function(ranges_sf, occ_counts_df) {
  if (!is.null(ranges_sf) && nrow(ranges_sf) > 0 && inherits(ranges_sf, "sf")) {
    ranges_df <- sf::st_drop_geometry(ranges_sf)

    species_col <- NULL
    for (candidate in c("species", "range_name", "scrubbed_species_binomial")) {
      if (candidate %in% names(ranges_df)) {
        species_col <- candidate
        break
      }
    }
    if (is.null(species_col)) {
      non_geom <- setdiff(names(ranges_df), attr(ranges_sf, "sf_column"))
      if (length(non_geom) > 0) species_col <- non_geom[1]
    }

    if (!is.null(species_col) && "overlap_pct" %in% names(ranges_df)) {
      ranges_tbl <- ranges_df[, c(species_col, "overlap_pct"), drop = FALSE]
      names(ranges_tbl)[1] <- "accepted_name"
      ranges_tbl <- ranges_tbl[!is.na(ranges_tbl$accepted_name), ]
    } else {
      ranges_tbl <- data.frame(accepted_name = character(),
                               overlap_pct   = numeric(),
                               stringsAsFactors = FALSE)
    }
  } else {
    ranges_tbl <- data.frame(accepted_name = character(),
                             overlap_pct   = numeric(),
                             stringsAsFactors = FALSE)
  }

  if (!is.null(occ_counts_df) && nrow(occ_counts_df) > 0) {
    occ_df <- as.data.frame(occ_counts_df)
    if ("species" %in% names(occ_df)) {
      names(occ_df)[names(occ_df) == "species"] <- "accepted_name"
    }
    if (!"n_occurrences" %in% names(occ_df)) occ_df$n_occurrences <- 0L
    if (!"family"        %in% names(occ_df)) occ_df$family        <- NA_character_
    occ_df <- occ_df[!is.na(occ_df$accepted_name), ]
    occ_df <- occ_df[, c("accepted_name", "n_occurrences", "family"), drop = FALSE]
  } else {
    occ_df <- data.frame(accepted_name = character(),
                         n_occurrences = integer(),
                         family        = character(),
                         stringsAsFactors = FALSE)
  }

  merged <- merge(ranges_tbl, occ_df, by = "accepted_name", all = TRUE)

  merged$overlap_pct[is.na(merged$overlap_pct)]     <- 0
  merged$n_occurrences[is.na(merged$n_occurrences)] <- 0L
  merged$family[is.na(merged$family)]               <- NA_character_

  merged$confidence_tier <- dplyr::case_when(
    merged$n_occurrences >= 20 & merged$overlap_pct >= 25 ~ "High",
    merged$n_occurrences >= 5  & merged$overlap_pct >= 10 ~ "Moderate",
    merged$n_occurrences >= 1  | merged$overlap_pct >= 1  ~ "Low",
    TRUE                                                   ~ "Very Low"
  )

  merged$iucn_status <- "Not queried (Phase 2)"

  result <- data.frame(
    accepted_name   = merged$accepted_name,
    family          = merged$family,
    confidence_tier = merged$confidence_tier,
    data_support_n  = as.integer(merged$n_occurrences),
    overlap_pct     = round(merged$overlap_pct, 2),
    iucn_status     = merged$iucn_status,
    stringsAsFactors = FALSE
  )

  tier_order <- c("High", "Moderate", "Low", "Very Low")
  result$confidence_tier <- factor(result$confidence_tier, levels = tier_order)
  result <- result[order(result$confidence_tier, result$accepted_name), ]
  result$confidence_tier <- as.character(result$confidence_tier)

  rownames(result) <- NULL
  result
}


check_anchor_species <- function(species_df) {
  if (is.null(species_df) || nrow(species_df) == 0) {
    result <- setNames(rep(FALSE, length(ANCHOR_SPECIES)), ANCHOR_SPECIES)
    return(result)
  }
  setNames(
    ANCHOR_SPECIES %in% species_df$accepted_name,
    ANCHOR_SPECIES
  )
}
