make_base_map <- function() {
  leaflet::leaflet() %>%
    leaflet::addTiles(
      urlTemplate = "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png",
      attribution  = paste0(
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
        ' contributors &copy; <a href="https://carto.com/attributions">CARTO</a>'
      )
    ) %>%
    leaflet::setView(-68, -2, zoom = 7) %>%
    leaflet.extras::addDrawToolbar(
      targetGroup          = "drawn",
      polylineOptions      = FALSE,
      rectangleOptions     = FALSE,
      circleOptions        = FALSE,
      markerOptions        = FALSE,
      circleMarkerOptions  = FALSE,
      polygonOptions       = leaflet.extras::drawPolygonOptions(repeatMode = FALSE),
      editOptions          = leaflet.extras::editToolbarOptions()
    )
}


add_polygon_layer <- function(map_proxy, polygon_sf) {
  map_proxy %>%
    leaflet::addPolygons(
      data        = polygon_sf,
      group       = "polygon",
      color       = "#e74c3c",
      weight      = 3,
      opacity     = 1,
      fillColor   = "#e74c3c",
      fillOpacity = 0.1,
      label       = "Study area"
    )
}


add_heatmap_layer <- function(map_proxy, occ_points_df) {
  if (is.null(occ_points_df) || nrow(occ_points_df) == 0) return(map_proxy)
  map_proxy %>%
    leaflet.extras::addHeatmap(
      data   = occ_points_df,
      lat    = ~latitude,
      lng    = ~longitude,
      group  = "heatmap",
      radius = 10,
      blur   = 15,
      max    = 0.05
    )
}
