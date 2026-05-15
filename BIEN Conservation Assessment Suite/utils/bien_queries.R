#' bien_queries.R — Wrapped, error-handled BIEN API calls
#' All functions return NULL with a warning on API failure.

query_bien_ranges <- function(polygon_sf) {
  bbox <- sf::st_bbox(polygon_sf)

  ranges <- tryCatch({
    BIEN::BIEN_ranges_box(
      min.lat = bbox["ymin"],
      max.lat = bbox["ymax"],
      min.lon = bbox["xmin"],
      max.lon = bbox["xmax"]
    )
  }, error = function(e) {
    warning("BIEN_ranges_box failed: ", conditionMessage(e))
    return(NULL)
  })

  if (is.null(ranges) || nrow(ranges) == 0) return(NULL)

  if (!inherits(ranges, "sf")) {
    warning("BIEN_ranges_box did not return an sf object.")
    return(NULL)
  }

  if (!sf::st_crs(ranges) == sf::st_crs(polygon_sf)) {
    ranges <- tryCatch(
      sf::st_transform(ranges, sf::st_crs(polygon_sf)),
      error = function(e) ranges
    )
  }

  intersects <- tryCatch(
    sf::st_intersects(ranges, polygon_sf, sparse = FALSE)[, 1],
    error = function(e) rep(FALSE, nrow(ranges))
  )
  ranges <- ranges[intersects, ]

  if (nrow(ranges) == 0) return(NULL)

  overlap_pct <- vapply(seq_len(nrow(ranges)), function(i) {
    tryCatch({
      range_i <- ranges[i, ]
      if (!sf::st_is_valid(range_i)) range_i <- sf::st_make_valid(range_i)
      intersection <- suppressWarnings(sf::st_intersection(range_i, polygon_sf))
      if (is.null(intersection) || nrow(intersection) == 0) return(0)
      geom_types <- as.character(sf::st_geometry_type(intersection))
      intersection <- intersection[geom_types %in% c("POLYGON", "MULTIPOLYGON"), ]
      if (nrow(intersection) == 0) return(0)
      range_area <- as.numeric(sf::st_area(range_i))
      if (range_area <= 0) return(0)
      sum(as.numeric(sf::st_area(intersection))) / range_area * 100
    }, error = function(e) 0)
  }, numeric(1))

  ranges$overlap_pct <- overlap_pct
  ranges
}


query_bien_occurrences <- function(occ_raw) {
  if (is.null(occ_raw) || nrow(occ_raw) == 0) {
    return(data.frame(species = character(), n_occurrences = integer(),
                      family = character(), stringsAsFactors = FALSE))
  }

  occ <- occ_raw[!is.na(occ_raw$latitude) & !is.na(occ_raw$longitude), ]
  occ <- occ[!(abs(occ$latitude) < 0.001 & abs(occ$longitude) < 0.001), ]

  if ("scrubbed_taxonomic_status" %in% names(occ)) {
    n_before <- nrow(occ)
    occ <- occ[!is.na(occ$scrubbed_taxonomic_status) &
                 occ$scrubbed_taxonomic_status == "Accepted", ]
    n_dropped <- n_before - nrow(occ)
    if (n_dropped > 0) {
      warning(sprintf(
        "Dropped %d occurrence record(s) with non-Accepted scrubbed_taxonomic_status.",
        n_dropped
      ))
    }
  }

  if (nrow(occ) == 0) {
    return(data.frame(species = character(), n_occurrences = integer(),
                      family = character(), stringsAsFactors = FALSE))
  }

  family_col <- if ("scrubbed_family" %in% names(occ)) "scrubbed_family" else NULL

  counts <- occ %>%
    dplyr::filter(!is.na(scrubbed_species_binomial)) %>%
    dplyr::group_by(species = scrubbed_species_binomial) %>%
    dplyr::summarise(
      n_occurrences = dplyr::n(),
      family = if (!is.null(family_col)) {
        fam_vals <- .data[[family_col]]
        fam_vals <- fam_vals[!is.na(fam_vals)]
        if (length(fam_vals) == 0) NA_character_ else names(sort(table(fam_vals), decreasing = TRUE))[1]
      } else NA_character_,
      .groups = "drop"
    )

  as.data.frame(counts)
}


#' Subsample a pre-fetched occurrence data.frame for heatmap rendering.
#' Accepts the raw occurrence data.frame already fetched by query_bien_occurrences_raw()
#' to avoid a duplicate BIEN API call.
get_bien_occurrence_points <- function(occ_raw) {
  if (is.null(occ_raw) || nrow(occ_raw) == 0) return(NULL)

  occ <- occ_raw[!is.na(occ_raw$latitude) & !is.na(occ_raw$longitude), ]
  occ <- occ[!(abs(occ$latitude) < 0.001 & abs(occ$longitude) < 0.001), ]

  if ("scrubbed_taxonomic_status" %in% names(occ)) {
    occ <- occ[!is.na(occ$scrubbed_taxonomic_status) &
                 occ$scrubbed_taxonomic_status == "Accepted", ]
  }

  if (nrow(occ) == 0) return(NULL)

  if (nrow(occ) > 5000) {
    occ <- dplyr::slice_sample(occ, n = 5000)
  }

  occ
}

#' Fetch raw BIEN occurrence records for a polygon bounding box.
#' Returns the unfiltered data.frame; callers should process with
#' query_bien_occurrences() (for counts) or get_bien_occurrence_points() (for heatmap).
fetch_bien_occurrences_raw <- function(polygon_sf) {
  bbox <- sf::st_bbox(polygon_sf)

  tryCatch({
    BIEN::BIEN_occurrence_box(
      min.lat              = bbox["ymin"],
      max.lat              = bbox["ymax"],
      min.lon              = bbox["xmin"],
      max.lon              = bbox["xmax"],
      cultivated           = FALSE,
      all.taxonomy         = TRUE,
      native.status        = TRUE,
      natives.only         = FALSE,
      observation.type     = TRUE,
      political.boundaries = TRUE
    )
  }, error = function(e) {
    warning("BIEN_occurrence_box failed: ", conditionMessage(e))
    NULL
  })
}
