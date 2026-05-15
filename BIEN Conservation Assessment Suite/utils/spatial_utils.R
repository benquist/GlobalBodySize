validate_polygon <- function(polygon_sf) {
  warnings_out <- character()
  errors_out   <- character()

  area_km2 <- tryCatch(
    sum(as.numeric(sf::st_area(polygon_sf))) / 1e6,
    error = function(e) NA_real_
  )

  centroid <- tryCatch(
    sf::st_coordinates(sf::st_centroid(sf::st_union(polygon_sf))),
    error = function(e) matrix(c(NA_real_, NA_real_), nrow = 1,
                               dimnames = list(NULL, c("X", "Y")))
  )

  if (!is.na(area_km2) && area_km2 < MIN_POLYGON_AREA_KM2) {
    warnings_out <- c(warnings_out, sprintf(
      "Study area is %.1f km\u00b2, below the recommended minimum of %d km\u00b2. Results may be unreliable for small areas.",
      area_km2, MIN_POLYGON_AREA_KM2
    ))
  }

  if (!is.na(centroid[1, "X"])) {
    lon <- centroid[1, "X"]
    lat <- centroid[1, "Y"]
    outside <- lon < BIEN_AMERICAS_BBOX$xmin || lon > BIEN_AMERICAS_BBOX$xmax ||
               lat < BIEN_AMERICAS_BBOX$ymin || lat > BIEN_AMERICAS_BBOX$ymax
    if (outside) {
      errors_out <- c(errors_out, sprintf(
        "Polygon centroid (lon %.4f, lat %.4f) is outside the BIEN Americas domain (lon %d to %d, lat %d to %d).",
        lon, lat,
        BIEN_AMERICAS_BBOX$xmin, BIEN_AMERICAS_BBOX$xmax,
        BIEN_AMERICAS_BBOX$ymin, BIEN_AMERICAS_BBOX$ymax
      ))
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


build_session_log <- function(polygon_sf, polygon_source, n_bbox, n_final, anchor_result) {
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
    app_version                  = APP_VERSION
  )
}


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
