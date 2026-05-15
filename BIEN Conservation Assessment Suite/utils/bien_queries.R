#' bien_queries.R — Wrapped, error-handled BIEN API calls
#' All functions return NULL with a warning on API failure.

#' Query BIEN range polygons and compute overlap metrics with user polygon.
#' Returns the ranges sf with two new columns:
#'   overlap_pct_range   = intersection_area / range_area * 100
#'   overlap_pct_polygon = intersection_area / polygon_area * 100
query_bien_ranges <- function(polygon_sf) {
  bbox <- sf::st_bbox(polygon_sf)

  # F2: bounded BIEN call. Falls back to no-timeout if R.utils unavailable.
  timeout_sec <- if (exists("BIEN_API_TIMEOUT_SEC")) BIEN_API_TIMEOUT_SEC else 180

  ranges <- tryCatch({
    if (requireNamespace("R.utils", quietly = TRUE)) {
      R.utils::withTimeout({
        BIEN::BIEN_ranges_box(
          min.lat = bbox["ymin"], max.lat = bbox["ymax"],
          min.lon = bbox["xmin"], max.lon = bbox["xmax"]
        )
      }, timeout = timeout_sec, onTimeout = "error")
    } else {
      BIEN::BIEN_ranges_box(
        min.lat = bbox["ymin"], max.lat = bbox["ymax"],
        min.lon = bbox["xmin"], max.lon = bbox["xmax"]
      )
    }
  }, TimeoutException = function(e) {
    stop(sprintf("BIEN range query exceeded %d s. Try a smaller polygon or retry later.", timeout_sec))
  }, error = function(e) {
    if (inherits(e, "TimeoutException") || grepl("timeout", conditionMessage(e), ignore.case = TRUE)) {
      stop(sprintf("BIEN range query exceeded %d s. Try a smaller polygon or retry later.", timeout_sec))
    }
    warning("BIEN_ranges_box failed: ", conditionMessage(e))
    return(NULL)
  })

  if (is.null(ranges) || nrow(ranges) == 0) return(NULL)

  if (!inherits(ranges, "sf")) {
    warning("BIEN_ranges_box did not return an sf object.")
    return(NULL)
  }

  # Ensure same CRS before intersection
  target_crs <- sf::st_crs(4326)
  if (!isTRUE(sf::st_crs(ranges) == target_crs)) {
    ranges <- tryCatch(sf::st_transform(ranges, target_crs), error = function(e) ranges)
  }
  if (!isTRUE(sf::st_crs(polygon_sf) == target_crs)) {
    polygon_sf <- tryCatch(sf::st_transform(polygon_sf, target_crs), error = function(e) polygon_sf)
  }

  # Coarse filter: keep only ranges whose bbox overlaps polygon
  intersects <- tryCatch(
    sf::st_intersects(ranges, polygon_sf, sparse = FALSE)[, 1],
    error = function(e) rep(FALSE, nrow(ranges))
  )
  ranges <- ranges[intersects, ]
  if (nrow(ranges) == 0) return(NULL)

  # Validate geometry bulk (na.rm=TRUE guards against NA validity for degenerate geometries)
  if (any(!sf::st_is_valid(ranges), na.rm = TRUE)) ranges <- sf::st_make_valid(ranges)

  # Pre-compute areas
  poly_union   <- sf::st_union(polygon_sf)
  polygon_area <- as.numeric(sf::st_area(poly_union))
  range_areas  <- as.numeric(sf::st_area(ranges))

  # Tag rows before bulk intersection (tapply key)
  ranges$.row_id <- seq_len(nrow(ranges))

  # Single vectorized intersection call (GEOS spatial index)
  inter <- suppressWarnings(
    sf::st_intersection(ranges[, ".row_id"], poly_union)
  )

  # Keep only area-bearing geometry types
  if (!is.null(inter) && nrow(inter) > 0) {
    inter_types <- as.character(sf::st_geometry_type(inter))
    inter <- inter[inter_types %in% c("POLYGON", "MULTIPOLYGON",
                                      "GEOMETRYCOLLECTION"), ]
  }

  # Aggregate intersection areas by original row id
  overlap_pct_range   <- rep(0, nrow(ranges))
  overlap_pct_polygon <- rep(0, nrow(ranges))

  if (!is.null(inter) && nrow(inter) > 0) {
    inter_areas     <- as.numeric(sf::st_area(inter))
    inter_area_by_id <- tapply(inter_areas, inter$.row_id, sum)
    matched_ids     <- as.integer(names(inter_area_by_id))

    valid_range <- range_areas[matched_ids] > 0
    overlap_pct_range[matched_ids[valid_range]] <-
      inter_area_by_id[valid_range] / range_areas[matched_ids[valid_range]] * 100
    if (polygon_area > 0) {
      overlap_pct_polygon[matched_ids] <-
        as.numeric(inter_area_by_id) / polygon_area * 100
    }
  }

  ranges$.row_id          <- NULL
  ranges$overlap_pct_range   <- overlap_pct_range
  ranges$overlap_pct_polygon <- overlap_pct_polygon
  ranges
}


#' Summarise pre-fetched occurrence data.frame into per-species counts.
#' Input occ_raw must already be clipped to the polygon (from fetch_bien_occurrences_raw).
query_bien_occurrences <- function(occ_raw) {
  if (is.null(occ_raw) || nrow(occ_raw) == 0) {
    return(data.frame(species = character(), n_occurrences = integer(),
                      family = character(), native_status_flag = character(),
                      stringsAsFactors = FALSE))
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
                      family = character(), native_status_flag = character(),
                      stringsAsFactors = FALSE))
  }

  # Deduplicate by rounded coordinates to remove duplicate aggregation-pipeline records
  occ <- occ[!duplicated(data.frame(
    sp  = occ$scrubbed_species_binomial,
    lat = round(occ$latitude,  3),
    lon = round(occ$longitude, 3)
  )), ]

  family_col <- if ("scrubbed_family" %in% names(occ)) "scrubbed_family" else NULL
  has_native  <- "native_status" %in% names(occ)

  counts <- occ %>%
    dplyr::filter(!is.na(scrubbed_species_binomial)) %>%
    dplyr::group_by(species = scrubbed_species_binomial) %>%
    dplyr::summarise(
      n_occurrences = dplyr::n(),
      family = if (!is.null(family_col)) {
        fam_vals <- .data[[family_col]]
        fam_vals <- fam_vals[!is.na(fam_vals)]
        if (length(fam_vals) == 0) NA_character_
        else names(sort(table(fam_vals), decreasing = TRUE))[1]
      } else NA_character_,
      native_status_flag = if (has_native) {
        ns <- .data[["native_status"]]
        n_nat  <- sum(ns == "native",     na.rm = TRUE)
        n_int  <- sum(ns == "introduced", na.rm = TRUE)
        n_na   <- sum(is.na(ns))
        if (n_na == dplyr::n()) "status_unavailable"
        else if (n_int > n_nat) "likely_introduced"
        else "likely_native"
      } else "status_unavailable",
      .groups = "drop"
    )

  as.data.frame(counts)
}


#' Subsample pre-fetched occurrence data.frame for heatmap rendering.
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


#' Fetch raw BIEN occurrence records for a polygon bounding box, then clip
#' to the actual polygon. Returns filtered data.frame ready for downstream use.
fetch_bien_occurrences_raw <- function(polygon_sf) {
  bbox <- sf::st_bbox(polygon_sf)

  # F2: bounded BIEN call. Falls back to no-timeout if R.utils unavailable.
  timeout_sec <- if (exists("BIEN_API_TIMEOUT_SEC")) BIEN_API_TIMEOUT_SEC else 180

  raw <- tryCatch({
    if (requireNamespace("R.utils", quietly = TRUE)) {
      R.utils::withTimeout({
        BIEN::BIEN_occurrence_box(
          min.lat       = bbox["ymin"], max.lat = bbox["ymax"],
          min.lon       = bbox["xmin"], max.lon = bbox["xmax"],
          cultivated    = FALSE,
          native.status = TRUE,
          natives.only  = FALSE
        )
      }, timeout = timeout_sec, onTimeout = "error")
    } else {
      BIEN::BIEN_occurrence_box(
        min.lat       = bbox["ymin"], max.lat = bbox["ymax"],
        min.lon       = bbox["xmin"], max.lon = bbox["xmax"],
        cultivated    = FALSE,
        native.status = TRUE,
        natives.only  = FALSE
      )
    }
  }, TimeoutException = function(e) {
    stop(sprintf("BIEN occurrence query exceeded %d s. Try a smaller polygon or retry later.", timeout_sec))
  }, error = function(e) {
    if (inherits(e, "TimeoutException") || grepl("timeout", conditionMessage(e), ignore.case = TRUE)) {
      stop(sprintf("BIEN occurrence query exceeded %d s. Try a smaller polygon or retry later.", timeout_sec))
    }
    warning("BIEN_occurrence_box failed: ", conditionMessage(e))
    NULL
  })

  if (is.null(raw) || nrow(raw) == 0) return(raw)

  # Clip to the actual polygon, not just the bounding box
  has_coords <- !is.na(raw$latitude) & !is.na(raw$longitude)
  if (any(has_coords)) {
    occ_sf <- sf::st_as_sf(
      raw[has_coords, ],
      coords = c("longitude", "latitude"),
      crs    = 4326,
      remove = FALSE
    )
    target_crs <- sf::st_crs(polygon_sf)
    if (!isTRUE(sf::st_crs(occ_sf) == target_crs)) {
      occ_sf <- sf::st_transform(occ_sf, target_crs)
    }
    inside  <- lengths(sf::st_intersects(occ_sf, polygon_sf)) > 0
    clipped <- raw[has_coords, ][inside, ]
    raw     <- rbind(clipped, raw[!has_coords, ])
  }

  raw
}
