app_server <- function(input, output, session) {
  rv <- shiny::reactiveValues(
    traits = data.frame(),
    status = "Enter species and click Query BIEN."
  )

  shiny::observeEvent(input$run_query, {
    spp <- parse_species_input(input$species_text)
    if (length(spp) == 0) {
      rv$status <- "No valid species provided."
      return(NULL)
    }

    shiny::withProgress(message = "Querying BIEN", value = 0.2, {
      tr <- query_trait_data(spp, max_records = input$max_records)
      rv$traits <- tr
      rv$status <- paste0("Species queried: ", length(spp), "; trait rows returned: ", ifelse(is.data.frame(tr), nrow(tr), 0))
    })
  })

  output$query_status <- shiny::renderText(rv$status)

  output$trait_table <- DT::renderDT({
    if (!is.data.frame(rv$traits) || nrow(rv$traits) == 0) {
      return(DT::datatable(data.frame(message = "No trait rows returned."), options = list(dom = "t"), rownames = FALSE))
    }
    DT::datatable(rv$traits, options = list(pageLength = 15, scrollX = TRUE), rownames = FALSE)
  })

  output$trait_map <- leaflet::renderLeaflet({
    tr <- rv$traits
    lat_col <- first_existing_col(tr, c("latitude", "lat", "decimalLatitude"))
    lon_col <- first_existing_col(tr, c("longitude", "long", "lon", "decimalLongitude"))

    if (!is.data.frame(tr) || nrow(tr) == 0 || is.null(lat_col) || is.null(lon_col)) {
      return(leaflet::leaflet() |> leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron))
    }

    tr[[lat_col]] <- suppressWarnings(as.numeric(tr[[lat_col]]))
    tr[[lon_col]] <- suppressWarnings(as.numeric(tr[[lon_col]]))
    map_df <- dplyr::filter(tr, !is.na(rlang::.data[[lat_col]]), !is.na(rlang::.data[[lon_col]]))

    if (nrow(map_df) == 0) {
      return(leaflet::leaflet() |> leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron))
    }

    leaflet::leaflet(map_df) |>
      leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron) |>
      leaflet::addCircleMarkers(lng = map_df[[lon_col]], lat = map_df[[lat_col]], radius = 4, stroke = FALSE, fillOpacity = 0.8)
  })

  output$download_traits <- shiny::downloadHandler(
    filename = function() sprintf("bien_traits_%s.csv", format(Sys.Date(), "%Y%m%d")),
    content = function(file) {
      write.csv(rv$traits, file, row.names = FALSE)
    }
  )
}
