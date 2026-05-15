# mod_map.R — Leaflet map helpers for BIEN Flora Explora
#
# make_base_map():      initialize the CartoDB light-base map centered on the Alto Japurá region.
# add_polygon_layer():  render the validated user AOI as a thin red outline with light fill.
# add_heatmap_layer():  overlay BIEN occurrence point density using leaflet.extras addHeatmap.

# ── Base map ─────────────────────────────────────────────────────────────────
# CartoDB Positron (light_all) tiles provide a clean, low-contrast base that
# lets the red AOI polygon and occurrence heatmap stand out visually.
# Initial view is centered on the Alto Japurá basin, western Brazilian Amazon
# (lat=-2, lon=-68, zoom=7) — the app's primary pilot region.
# The draw toolbar enables freehand polygon drawing; only polygon mode is enabled
# (rectangle, circle, marker disabled to constrain user input to meaningful AOIs).
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


# ── AOI polygon layer ─────────────────────────────────────────────────────────
# Thin red outline with light fill — visually distinctive against the CartoDB base.
# group="polygon" allows the observe() in app.R to clear and redraw this layer
# via leafletProxy() without re-rendering the entire map.
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


# ── Occurrence heatmap layer ──────────────────────────────────────────────────
# Renders a kernel density heat surface from the subsampled occurrence points
# (≤5000 rows from get_bien_occurrence_points()). radius=10, blur=15 are
# tuned for continent-scale zoom levels; max=0.05 prevents a single record
# cluster from saturating the color scale.
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
