# bien_queries.R — Wrapped, error-handled BIEN API calls
#
# All functions return NULL (with a warning) on API failure so the
# calling stage can degrade gracefully rather than crash the app.
#
# BIEN query architecture:
#   query_species_list_fast()  — Stage 1: polygon-specific checklist via BIEN_list_sf
#   fetch_bien_occurrences_raw() — Stage 2: full occurrences via PostGIS (minutes)
#   query_bien_occurrences()   — Stage 2: summarise raw occurrences to per-species counts
#   get_bien_occurrence_points() — Stage 2: subsample for heatmap (≤5000 pts)
#   query_bien_ranges()        — Stage 3: SDM range polygons + overlap geometry (slow)
#   .prepare_aoi_for_bien()    — Internal: validate + reproject polygon before any BIEN call

# ── Internal helper ───────────────────────────────────────────────────────────
# Prepare a polygon for BIEN_*_sf calls: WGS84, valid, single-feature union.
# Implements the Block B guards:
#   B1 — s2 must be enabled (geodesic area and intersection)
#   B2 — geometry must be valid (st_make_valid if needed)
#   B3 — no antimeridian crossing (lon span > 180°)
#   B4 — vertex cap: auto-simplify above 5000 vertices to avoid server timeout
#   B5 — Americas domain check: bbox must overlap CFG$BIEN_AMERICAS_BBOX
#   B6 — reproject to WGS84 / EPSG:4326 if needed

#' Prepare a polygon for BIEN_*_sf calls: WGS84, valid, single union.
#' Block B guards: s2 enabled, valid geometry, no antimeridian crossing,
#' B5 Americas domain overlap, vertex cap with auto-simplify notification.
.prepare_aoi_for_bien <- function(polygon_sf) {
  # B1: assert s2 is on
  if (!isTRUE(sf::sf_use_s2())) {
    stop("sf_use_s2() is FALSE; refusing to query BIEN. Restart R or set sf::sf_use_s2(TRUE).")
  }
  # CRS reproject (B6)
  current_crs <- sf::st_crs(polygon_sf)
  if (!isTRUE(current_crs == sf::st_crs(4326))) {
    epsg <- if (!is.null(current_crs$epsg)) current_crs$epsg else "unknown"
    polygon_sf <- sf::st_transform(polygon_sf, 4326)
    if (requireNamespace("shiny", quietly = TRUE) && !is.null(shiny::getDefaultReactiveDomain())) {
      shiny::showNotification(
        sprintf("Transformed AOI from EPSG:%s to EPSG:4326 for BIEN query.", epsg),
        type = "message"
      )
    }
  }
  # B2: validate
  if (any(!sf::st_is_valid(polygon_sf), na.rm = TRUE)) {
    polygon_sf <- sf::st_make_valid(polygon_sf)
  }
  # Union to single feature for BIEN
  aoi <- sf::st_union(polygon_sf)
  aoi_sf <- sf::st_sf(geometry = aoi)
  # B3: antimeridian
  bb <- sf::st_bbox(aoi_sf)
  if (bb["xmax"] - bb["xmin"] > 180) {
    stop("AOI appears to cross the antimeridian (lon span > 180 deg). Split into hemisphere pieces and retry.")
  }
  # B5: BIEN Americas domain check
  # BIEN's occurrence and range data cover the New World (Americas).
  # If the AOI's bounding box has no overlap with the declared Americas domain,
  # the PostGIS spatial scan will still run to completion (minutes) and return
  # zero records. Refuse the query immediately to avoid the wasted round-trip.
  CFG_local <- tryCatch(getOption("bien_cfg"), error = function(e) NULL)
  if (!is.null(CFG_local) && !is.null(CFG_local$BIEN_AMERICAS_BBOX)) {
    dom <- CFG_local$BIEN_AMERICAS_BBOX
    no_overlap <- (bb["xmax"] <= dom$xmin || bb["xmin"] >= dom$xmax ||
                   bb["ymax"] <= dom$ymin || bb["ymin"] >= dom$ymax)
    if (no_overlap) {
      stop(sprintf(
        paste0("AOI bounding box [%.2f, %.2f] lon / [%.2f, %.2f] lat has no overlap ",
               "with the BIEN Americas domain (lon %.0f to %.0f, lat %.0f to %.0f). ",
               "BIEN does not contain occurrence data for this region."),
        bb["xmin"], bb["xmax"], bb["ymin"], bb["ymax"],
        dom$xmin, dom$xmax, dom$ymin, dom$ymax
      ))
    }
  }
  # B4: vertex cap
  n_vert <- tryCatch(nrow(sf::st_coordinates(aoi_sf)), error = function(e) NA_integer_)
  if (!is.na(n_vert) && n_vert > 5000) {
    area_m2 <- as.numeric(sf::st_area(aoi_sf))
    tol <- sqrt(area_m2) / 1000
    aoi_sf <- sf::st_simplify(aoi_sf, dTolerance = tol, preserveTopology = TRUE)
    if (any(!sf::st_is_valid(aoi_sf), na.rm = TRUE)) aoi_sf <- sf::st_make_valid(aoi_sf)
    if (requireNamespace("shiny", quietly = TRUE) && !is.null(shiny::getDefaultReactiveDomain())) {
      shiny::showNotification(
        sprintf("AOI had %d vertices (cap 5000). Auto-simplified for BIEN query.", n_vert),
        type = "warning"
      )
    }
  }
  aoi_sf
}

#' Query BIEN range polygons via PostGIS server-side polygon intersection
#' (BIEN_ranges_sf). Returns the ranges sf with two new columns:
#'   overlap_pct_range   = intersection_area / range_area * 100
#'   overlap_pct_polygon = intersection_area / polygon_area * 100
query_bien_ranges <- function(polygon_sf) {
  CFG <- getOption("bien_cfg")
  polygon_sf <- .prepare_aoi_for_bien(polygon_sf)

  # Single-step: BIEN_ranges_sf with species.names.only=FALSE returns range geometries
  # directly via a PostGIS spatial-intersection query — no per-species shapefile downloads.
  # This replaces the previous two-step (get names via species.names.only=TRUE, then
  # BIEN_ranges_load_species) which was downloading one shapefile per species and
  # caused 80+ min runtimes on large polygons.
  ranges <- tryCatch({
    BIEN::BIEN_ranges_sf(
      sf                  = polygon_sf,
      species.names.only  = FALSE,
      return.species.list = FALSE,
      crop.ranges         = FALSE,
      include.gid         = FALSE
    )
  }, error = function(e) {
    warning("BIEN_ranges_sf failed (possible timeout or network error): ", conditionMessage(e))
    return(NULL)
  })

  if (is.null(ranges) || nrow(ranges) == 0) return(NULL)

  if (!inherits(ranges, "sf")) {
    warning("BIEN_ranges_sf did not return an sf object.")
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
#' Returns one row per accepted species with n_occurrences, family, and native_status_flag.
query_bien_occurrences <- function(occ_raw) {
  if (is.null(occ_raw) || nrow(occ_raw) == 0) {
    return(data.frame(species = character(), n_occurrences = integer(),
                      family = character(), native_status_flag = character(),
                      stringsAsFactors = FALSE))
  }

  # Drop records with NULL coordinates and likely coordinate-reference artifacts
  # (exact (0,0) indicates a failed geocode, not Gulf-of-Guinea occurrences).
  occ <- occ_raw[!is.na(occ_raw$latitude) & !is.na(occ_raw$longitude), ]
  occ <- occ[!(abs(occ$latitude) < 0.001 & abs(occ$longitude) < 0.001), ]

  # Drop non-Accepted taxonomic status (synonyms, hybrids, unresolved).
  # This reduces false richness from multiple names for the same taxon.
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

  # Deduplicate by rounded coordinates to remove duplicate aggregation-pipeline records.
  # paste() string key is significantly faster than constructing a data.frame for
  # !duplicated() on 1M+ rows (avoids a full N-row object allocation).
  occ <- occ[!duplicated(paste(
    occ$scrubbed_species_binomial,
    round(occ$latitude,  3L),
    round(occ$longitude, 3L),
    sep = "\x1f"
  )), ]

  family_col <- if ("scrubbed_family" %in% names(occ)) "scrubbed_family" else NULL
  has_native  <- "native_status" %in% names(occ)

  counts <- occ %>%
    dplyr::filter(!is.na(scrubbed_species_binomial)) %>%
    dplyr::group_by(species = scrubbed_species_binomial) %>%
    dplyr::summarise(
      n_occurrences = dplyr::n(),
      # scrubbed_family is taxonomically invariant per scrubbed_species_binomial;
      # first non-NA value is equivalent to modal and avoids O(n) table() per group.
      family = if (!is.null(family_col)) {
        fam_vals <- .data[[family_col]]
        fam_vals <- fam_vals[!is.na(fam_vals)]
        if (length(fam_vals) == 0L) NA_character_ else fam_vals[1L]
      } else NA_character_,
      # Majority-vote native status: flag a species as likely_introduced only if
      # introduced records outnumber native records. NA-dominated columns become
      # status_unavailable rather than silently misclassifying.
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
#' Leaflet heatmap performance degrades significantly above ~5000 points.
#' Returns up to 5000 spatially valid occurrence rows (random sample).
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


# ── Stage 1 — Polygon-specific species checklist via BIEN_list_sf ────────────
# BIEN_list_sf() performs a PostGIS spatial intersection against the drawn
# polygon, returning only species documented within the polygon boundary.
# This is spatially precise: no country-level superset is returned.
# Stage 2 (BIEN_occurrence_sf) further refines with occurrence counts and
# native-status filtering.
# Returns: character vector of scrubbed_species_binomial, or NULL on failure.
query_species_list_fast <- function(polygon_sf) {
  aoi <- .prepare_aoi_for_bien(polygon_sf)

  res <- tryCatch(
    BIEN::BIEN_list_sf(sf = aoi, cultivated = FALSE, new.world = NULL),
    error = function(e) { warning("BIEN_list_sf failed: ", conditionMessage(e)); NULL }
  )

  if (is.null(res) || nrow(res) == 0) return(NULL)

  nm_col <- intersect(c("scrubbed_species_binomial", "species"), names(res))[1]
  if (is.na(nm_col)) return(NULL)

  unique(stats::na.omit(res[[nm_col]]))
}

fetch_bien_occurrences_raw <- function(polygon_sf,
                                       natives_only  = TRUE,
                                       geo_valid_only = TRUE) {
  CFG <- getOption("bien_cfg")
  polygon_sf <- .prepare_aoi_for_bien(polygon_sf)

  # Use BIEN_occurrence_box() instead of BIEN_occurrence_sf():
  #   BIEN_occurrence_sf sends the full polygon geometry for a server-side
  #   ST_Intersects() PostGIS spatial scan (~5-20 min on the NCEAS vegbiendev
  #   server regardless of result count — the index walk is the bottleneck).
  #   BIEN_occurrence_box sends a simple lat/lon bounding box that maps to a
  #   B-tree range scan (seconds), then we clip to the exact polygon boundary
  #   client-side with sf::st_within(). For compact polygons the bbox overshoot
  #   is small; client-side clip is geodesically precise with sf_use_s2=TRUE.
  #
  # Apply BIEN_API_TIMEOUT_SEC via R's download timeout option (best-effort;
  # does not affect PostgreSQL connection waits but limits HTTP-layer stalls).
  bb       <- sf::st_bbox(polygon_sf)
  prev_to  <- getOption("timeout", default = 60L)
  timeout_sec <- if (!is.null(CFG) && !is.null(CFG$BIEN_API_TIMEOUT_SEC))
    CFG$BIEN_API_TIMEOUT_SEC else 180L
  on.exit(options(timeout = prev_to), add = TRUE)
  options(timeout = timeout_sec)

  # BIEN_occurrence_box parameter notes:
  #   - only.geovalid is NOT a valid parameter for BIEN_occurrence_box (causes
  #     "unused argument" error). Geo-validity is already hardcoded in the SQL
  #     as "AND is_geovalid = 1", so all returned records are geo-validated.
  #   - native.status=TRUE adds the native_status column via a server-side JOIN.
  #     When natives.only=TRUE, all returned records are already native per the
  #     WHERE clause; the JOIN is redundant and slow. Skip it and add a synthetic
  #     native_status="native" column below so downstream logic stays intact.
  #   - min.long / max.long: note the BIEN function uses ".long" not ".lon";
  #     R partial-matches "min.lon" → "min.long" but we use explicit names here.
  need_native_status_col <- !natives_only   # only fetch the JOIN col when querying all species
  raw <- tryCatch({
    BIEN::BIEN_occurrence_box(
      min.lat              = bb["ymin"],
      max.lat              = bb["ymax"],
      min.long             = bb["xmin"],
      max.long             = bb["xmax"],
      cultivated           = FALSE,
      new.world            = NULL,
      all.taxonomy         = FALSE,
      native.status        = need_native_status_col,
      natives.only         = natives_only,
      observation.type     = FALSE,
      political.boundaries = FALSE,
      collection.info      = FALSE
    )
  }, error = function(e) {
    warning("BIEN_occurrence_box failed: ", conditionMessage(e))
    NULL
  })

  # When natives_only=TRUE, native.status=FALSE was used (no JOIN) so the
  # native_status column is absent. Add it synthetically so query_bien_occurrences()
  # majority-vote logic correctly labels all records as "likely_native".
  if (natives_only && !is.null(raw) && nrow(raw) > 0 &&
      !"native_status" %in% names(raw)) {
    raw$native_status <- "native"
  }

  # Client-side polygon clip: BIEN_occurrence_box queries by bounding box so
  # records outside the exact polygon boundary must be excluded here.
  # sf::st_within with sf_use_s2=TRUE is geodesically precise.
  if (!is.null(raw) && nrow(raw) > 0 &&
      "latitude" %in% names(raw) && "longitude" %in% names(raw)) {
    valid_coords <- !is.na(raw$latitude) & !is.na(raw$longitude)
    if (any(valid_coords)) {
      pts <- tryCatch({
        sf::st_as_sf(raw[valid_coords, ],
                     coords = c("longitude", "latitude"),
                     crs    = 4326,
                     remove = FALSE)
      }, error = function(e) NULL)
      if (!is.null(pts)) {
        inside <- tryCatch(
          as.logical(sf::st_within(pts, sf::st_union(polygon_sf), sparse = FALSE)[, 1]),
          error = function(e) rep(TRUE, nrow(pts))  # on error, keep all rather than drop all
        )
        n_before  <- nrow(raw)
        raw_valid  <- raw[valid_coords, ][inside, ]
        raw_invld  <- raw[!valid_coords, ]   # rows with NA coords pass through unchanged
        raw       <- rbind(raw_valid, raw_invld)
        n_dropped <- n_before - nrow(raw)
        if (n_dropped > 0) {
          message(sprintf(
            "[fetch_bien_occurrences_raw] Client-side polygon clip removed %d record(s) outside the polygon boundary.",
            n_dropped
          ))
        }
      }
    }
  }

  raw
}
