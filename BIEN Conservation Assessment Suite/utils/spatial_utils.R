# spatial_utils.R — Polygon validation, session provenance logging, DwC CSV export
#
# validate_polygon(): pre-flight checks on user-uploaded polygon before BIEN queries.
# build_session_log(): generates a SHA-256-fingerprinted provenance record for audit trails.
# build_dwc_csv():     formats query results as a Darwin Core-compliant data.frame for CSV export.

# ── Polygon validation ────────────────────────────────────────────────────────
# Checks:
#   B5 — area bounds (MIN_POLYGON_AREA_KM2 warning, MAX_POLYGON_AREA_KM2 hard error)
#   B7 — disjoint feature detection (warns if multiple features >25 km centroid separation)
#        These will be unioned for the BIEN query; user may want to query separately.
#   Americas bbox — polygon centroid must be within the BIEN domain (lon -170 to -34, lat -55 to 55)
validate_polygon <- function(polygon_sf) {
  CFG <- getOption("bien_cfg")
  warnings_out <- character()
  errors_out   <- character()

  # B5: carry units through area math; convert at boundary only
  area_units_km2 <- tryCatch(
    units::set_units(sum(sf::st_area(polygon_sf)), "km^2"),
    error = function(e) NULL
  )
  area_km2 <- if (!is.null(area_units_km2)) as.numeric(area_units_km2) else NA_real_

  # B7: multi-feature detection — flag disjoint pieces (centroid > 25 km apart)
  n_features <- nrow(polygon_sf)
  if (isTRUE(!is.na(n_features)) && isTRUE(n_features > 1)) {
    cents <- tryCatch(suppressWarnings(sf::st_centroid(sf::st_geometry(polygon_sf))),
                      error = function(e) NULL)
    if (!is.null(cents) && length(cents) > 1) {
      d_km <- tryCatch(
        as.numeric(units::set_units(max(sf::st_distance(cents)), "km")),
        error = function(e) NA_real_
      )
      if (isTRUE(!is.na(d_km)) && isTRUE(d_km > 25)) {
        warnings_out <- c(warnings_out, sprintf(
          "Upload contains %d disjoint features (max centroid distance %.1f km). They will be unioned for the BIEN query. To analyze separately, upload one feature at a time.",
          n_features, d_km
        ))
      }
    }
  }

  centroid <- tryCatch(
    sf::st_coordinates(sf::st_centroid(sf::st_union(polygon_sf))),
    error = function(e) matrix(c(NA_real_, NA_real_), nrow = 1,
                               dimnames = list(NULL, c("X", "Y")))
  )

  if (isTRUE(!is.na(area_km2)) && isTRUE(area_km2 < CFG$MIN_POLYGON_AREA_KM2)) {
    warnings_out <- c(warnings_out, sprintf(
      "Study area is %.1f km\u00b2, below the recommended minimum of %d km\u00b2. Results may be unreliable for small areas.",
      area_km2, CFG$MIN_POLYGON_AREA_KM2
    ))
  }

  # Hard upper-area guard prevents accidental hemisphere-spanning queries.
  # Raised to 500,000 km² to support large legitimate conservation units
  # (e.g. Alto Japurá ~250,000 km²). Antimeridian check in .prepare_aoi_for_bien
  # provides the safety backstop against truly pathological polygons.
  if (isTRUE(!is.na(area_km2)) && isTRUE(area_km2 > CFG$MAX_POLYGON_AREA_KM2)) {
    errors_out <- c(errors_out, sprintf(
      "Study area is %s km\u00b2, above the maximum supported size of %s km\u00b2. Split the area into smaller regions and run them separately. Very large polygons stall the BIEN API and produce unreliable richness estimates.",
      formatC(area_km2, format = "d", big.mark = ","),
      formatC(CFG$MAX_POLYGON_AREA_KM2, format = "d", big.mark = ",")
    ))
  }

  if (isTRUE(!is.na(centroid[1, "X"])) && isTRUE(!is.na(centroid[1, "Y"]))) {
    lon <- centroid[1, "X"]
    lat <- centroid[1, "Y"]
    bb  <- if (!is.null(CFG)) CFG$BIEN_AMERICAS_BBOX else NULL
    if (!is.null(bb) && !is.null(bb$xmin) && !is.null(bb$ymax)) {
      outside <- lon < bb$xmin || lon > bb$xmax ||
                 lat < bb$ymin || lat > bb$ymax
      if (isTRUE(outside)) {
        errors_out <- c(errors_out, sprintf(
          "Polygon centroid (lon %.4f, lat %.4f) is outside the BIEN Americas domain (lon %d to %d, lat %d to %d). BIEN has no occurrence data for this region.",
          lon, lat, bb$xmin, bb$xmax, bb$ymin, bb$ymax
        ))
      }
    }
  }

  list(
    valid           = length(errors_out) == 0,
    warnings        = warnings_out,
    errors          = errors_out,
    area_km2        = area_km2,
    centroid        = centroid,
    elevation_check = "Not checked (Phase 1 — no elevation raster loaded)"
  )
}


# ── Session provenance log ────────────────────────────────────────────────────
# SHA-256 fingerprints the polygon WKT so any modification to the geometry is
# detectable in the exported CSV or HTML report. This supports reproducibility
# audits: the same polygon should always produce the same fingerprint.
build_session_log <- function(polygon_sf, polygon_source, n_bbox, n_final, anchor_result) {
  CFG <- getOption("bien_cfg")
  centroid <- tryCatch(
    sf::st_coordinates(sf::st_centroid(sf::st_union(polygon_sf))),
    error = function(e) matrix(c(NA_real_, NA_real_), nrow = 1,
                               dimnames = list(NULL, c("X", "Y")))
  )

  area_km2 <- tryCatch(
    sum(as.numeric(sf::st_area(polygon_sf))) / 1e6,
    error = function(e) NA_real_
  )

  wkt    <- tryCatch(sf::st_as_text(sf::st_geometry(polygon_sf)), error = function(e) "")
  sha256 <- digest::digest(wkt, algo = "sha256")

  list(
    query_timestamp_utc          = format(Sys.time(), tz = "UTC", usetz = TRUE),
    bien_package_version         = tryCatch(as.character(utils::packageVersion("BIEN")),
                                            error = function(e) "unknown"),
    polygon_source               = polygon_source,
    polygon_sha256               = sha256,
    polygon_area_km2             = round(area_km2, 2),
    polygon_centroid_lon         = round(centroid[1, "X"], 4),
    polygon_centroid_lat         = round(centroid[1, "Y"], 4),
    n_species_bbox               = n_bbox,
    n_species_after_intersection = n_final,
    anchor_check                 = anchor_result,
    r_version                    = paste(R.version$major, R.version$minor, sep = "."),
    app_version                  = CFG$APP_VERSION
  )
}



# ── Darwin Core CSV export ────────────────────────────────────────────────────
# Maps BIEN Flora Explora columns to Darwin Core (DwC) standard terms.
# Notable choices:
#   basisOfRecord = "Occurrence" — BIEN aggregates herbarium vouchers, plot records,
#     and remote sensing inferences. "HumanObservation" would be factually incorrect
#     for SDM-inferred presences. "Occurrence" is the broadest correct term.
#   occurrenceRemarks — encodes confidence tier evidence so downstream users
#     understand data support behind each record.
#   informationWithheld — explicitly flags that SDM model fit statistics (AUC,
#     Boyce Index, training n) are not available via the BIEN API.
build_dwc_csv <- function(species_df, session_log) {
  # DwC basisOfRecord: "Occurrence" is the broadest valid term for aggregated BIEN records
  # (which mix herbarium vouchers, plot observations, etc. with no per-record basisOfRecord
  # available via the BIEN API). Using "Occurrence" rather than the more specific but
  # factually incorrect "HumanObservation" (which implies a living organism observed directly).
  basis <- "Occurrence"

  data.frame(
    scientificName    = species_df$accepted_name,
    taxonRank         = "species",
    acceptedNameUsage = species_df$accepted_name,
    taxonomicStatus   = "accepted",
    family            = species_df$family,
    occurrenceStatus  = "present",
    occurrenceRemarks = paste0(
      "Modeled predicted presence (BIEN MaxEnt SDM). Not field-verified. ",
      "data_support_n=", species_df$data_support_n,
      "; overlap_pct_polygon=", round(species_df$overlap_pct_polygon, 2),
      "%; overlap_pct_range=", round(species_df$overlap_pct_range, 2), "%."
    ),
    basisOfRecord     = basis,
    informationWithheld = "BIEN range polygon is a MaxEnt binary output (MTP threshold). No AUC, Boyce Index, or training record count is available via the BIEN API. data_support_n reflects BIEN polygon-clipped occurrence density, not SDM training support.",
    establishmentMeans = dplyr::case_when(
      species_df$native_status_flag == "likely_introduced" ~ "introduced",
      species_df$native_status_flag == "likely_native"     ~ "native",
      TRUE                                                  ~ NA_character_
    ),
    dataSource        = "Botanical Information and Ecology Network (BIEN)",
    decimalLatitude   = session_log$polygon_centroid_lat,
    decimalLongitude  = session_log$polygon_centroid_lon,
    country           = NA_character_,
    datasetName       = paste0("BIEN Conservation Assessment Suite v", session_log$app_version),
    rightsHolder      = "Botanical Information and Ecology Network (BIEN)",
    accessRights      = "See BIEN data use policy: https://bien.nceas.ucsb.edu",
    modified          = session_log$query_timestamp_utc,
    confidence_tier       = species_df$confidence_tier,
    data_support_n        = species_df$data_support_n,
    overlap_pct_polygon   = species_df$overlap_pct_polygon,
    overlap_pct_range     = species_df$overlap_pct_range,
    native_status_flag    = species_df$native_status_flag,
    bien_pkg_version      = session_log$bien_package_version,
    query_timestamp       = session_log$query_timestamp_utc,
    stringsAsFactors      = FALSE
  )
}
