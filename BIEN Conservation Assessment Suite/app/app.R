ui <- fluidPage(
  theme = bslib::bs_theme(bootswatch = "flatly"),

  tags$head(
    tags$style(HTML("
      .tier-box { display:inline-block; padding:12px 22px; margin:5px; border-radius:8px;
                  font-weight:bold; font-size:1.05em; border:1px solid #ccc; }
      .sidebar-section { padding: 4px 0; }
      .anchor-badge-pass { background:#27ae60; color:#fff; padding:3px 10px;
                           border-radius:4px; font-weight:bold; }
      .anchor-badge-fail { background:#c0392b; color:#fff; padding:3px 10px;
                           border-radius:4px; font-weight:bold; }
    "))
  ),

  sidebarLayout(
    sidebarPanel(
      width = 3,
      h4("BIEN Flora Scout"),
      p("Phase 1 — Conservation Assessment Suite", class = "text-muted",
        style = "font-size:0.88em; margin-top:-8px;"),
      hr(),

      radioButtons("input_mode", "Study area input:",
        choices  = c("Upload / Select" = "upload", "Draw on Map" = "draw"),
        selected = "upload"
      ),

      conditionalPanel(
        condition = "input.input_mode == 'upload'",
        radioButtons("file_type", "File type:",
          choices = c(
            "GeoJSON (.geojson/.json)" = "geojson",
            "Shapefile (.zip)"         = "shapefile",
            "Pilot: Alto Japur\u00e1 (example)" = "pilot"
          ),
          selected = "geojson"
        ),
        conditionalPanel(
          condition = "input.file_type == 'geojson'",
          fileInput("geojson_file", "Upload GeoJSON",
                    accept = c(".geojson", ".json"))
        ),
        conditionalPanel(
          condition = "input.file_type == 'shapefile'",
          fileInput("shapefile_zip", "Upload shapefile (.zip)", accept = ".zip")
        ),
        conditionalPanel(
          condition = "input.file_type == 'pilot'",
          div(class = "alert alert-info", style = "font-size:0.85em; padding:8px;",
            "Loads the Alto Japur\u00e1 (Brazil) pilot study area. Reflects BIEN data coverage for western Amazonia.")
        )
      ),

      actionButton("run_query", "Run Analysis",
        class = "btn-primary btn-lg",
        style = "width:100%; margin-top:12px;"
      ),

      hr(),
      div(class = "sidebar-section",
        strong("Status:"),
        textOutput("status_text")
      ),
      br(),

      conditionalPanel(
        condition = "output.results_ready",
        downloadButton("dl_csv", "Download Species List (CSV)",
          class = "btn-success btn-sm",
          style = "width:100%; margin-bottom:6px;"
        ),
        downloadButton("dl_html", "Download Report (HTML)",
          class = "btn-info btn-sm",
          style = "width:100%;"
        )
      )
    ),

    mainPanel(
      width = 9,
      tabsetPanel(
        tabPanel("Map",
          br(),
          leaflet::leafletOutput("main_map", height = "500px"),
          uiOutput("map_info_box")
        ),
        tabPanel("Species List",
          br(),
          uiOutput("tier_summary_bar"),
          DT::DTOutput("species_table")
        ),
        tabPanel("Data Quality",
          br(),
          uiOutput("anchor_check_ui"),
          br(),
          plotOutput("occ_density_hist", height = "300px")
        ),
        tabPanel("About & Caveats",
          br(),
          includeHTML("../www/disclaimer.html")
        )
      )
    )
  )
)


server <- function(input, output, session) {

  rv <- reactiveValues(
    polygon         = NULL,
    species_df      = NULL,
    session_log     = NULL,
    occ_points      = NULL,
    anchor_result   = NULL,
    pending_polygon = NULL,
    status          = "idle"
  )

  output$results_ready <- reactive({
    !is.null(rv$species_df) && nrow(rv$species_df) > 0
  })
  outputOptions(output, "results_ready", suspendWhenHidden = FALSE)

  output$status_text <- renderText({
    switch(rv$status,
      idle    = "Ready. Load a polygon and click Run Analysis.",
      running = "Analysis running\u2026 please wait.",
      done    = paste0("Complete. ", nrow(rv$species_df), " species predicted."),
      error   = "Analysis failed. Check inputs and try again."
    )
  })

  observeEvent(input$main_map_draw_new_feature, {
    feat <- input$main_map_draw_new_feature
    geojson_str <- jsonlite::toJSON(feat, auto_unbox = TRUE)
    poly <- tryCatch({
      p <- sf::st_read(geojson_str, quiet = TRUE)
      p <- sf::st_transform(p, 4326)
      if (!all(sf::st_is_valid(p))) p <- sf::st_make_valid(p)
      p
    }, error = function(e) {
      showNotification(paste("Error parsing drawn polygon:", e$message), type = "error")
      NULL
    })
    if (!is.null(poly)) {
      rv$polygon <- poly
      showNotification("Polygon captured. Click Run Analysis to proceed.", type = "message")
    }
  })

  get_polygon <- reactive({
    if (input$input_mode == "draw") {
      return(rv$polygon)
    }

    ft   <- input$file_type
    poly <- NULL

    if (ft == "geojson") {
      req(input$geojson_file)
      poly <- tryCatch(
        sf::st_read(input$geojson_file$datapath, quiet = TRUE),
        error = function(e) NULL
      )
    } else if (ft == "shapefile") {
      req(input$shapefile_zip)
      td <- tempfile()
      dir.create(td)
      ok <- tryCatch({ unzip(input$shapefile_zip$datapath, exdir = td); TRUE },
                     error = function(e) FALSE)
      if (!ok) return(NULL)
      shp_files <- list.files(td, pattern = "\\.shp$", recursive = TRUE, full.names = TRUE)
      if (length(shp_files) == 0) return(NULL)
      poly <- tryCatch(
        sf::st_read(shp_files[1], quiet = TRUE),
        error = function(e) NULL
      )
    } else if (ft == "pilot") {
      pilot_path <- "../data/Japura_AOI_Nov2025_mapshaper.json"
      if (!file.exists(pilot_path)) return(NULL)
      poly <- tryCatch(
        sf::st_read(pilot_path, quiet = TRUE),
        error = function(e) {
          showNotification(paste("Error reading pilot polygon:", e$message), type = "error")
          NULL
        }
      )
    }

    if (is.null(poly)) return(NULL)

    poly <- tryCatch(sf::st_transform(poly, 4326), error = function(e) poly)

    geom_types <- unique(as.character(sf::st_geometry_type(poly)))
    if (!any(geom_types %in% c("POLYGON", "MULTIPOLYGON"))) return(NULL)

    if (!all(sf::st_is_valid(poly))) {
      poly <- sf::st_make_valid(poly)
    }

    poly
  })

  source_label_current <- function() {
    if (input$input_mode == "draw") return("Drawn on map")
    switch(input$file_type,
      geojson   = "GeoJSON upload",
      shapefile = "Shapefile upload",
      pilot     = "Pilot polygon (Alto Japur\u00e1)",
      "Unknown"
    )
  }

  do_analysis <- function(poly, source_label) {
    withProgress(message = "Querying BIEN\u2026", value = 0, {
      rv$status  <- "running"
      rv$polygon <- poly

      setProgress(0.15, detail = "Fetching species range maps\u2026")
      ranges_sf <- query_bien_ranges(poly)

      setProgress(0.40, detail = "Fetching occurrence records\u2026")
      occ_raw    <- fetch_bien_occurrences_raw(poly)
      occ_counts <- query_bien_occurrences(occ_raw)
      occ_points <- get_bien_occurrence_points(occ_raw)
      rv$occ_points <- occ_points

      setProgress(0.65, detail = "Assigning confidence tiers\u2026")
      species_df <- assign_confidence_tiers(ranges_sf, occ_counts)

      setProgress(0.82, detail = "Checking anchor species\u2026")
      anchor_result   <- check_anchor_species(species_df)
      rv$anchor_result <- anchor_result

      n_bbox  <- if (!is.null(ranges_sf)) nrow(ranges_sf) else 0L
      n_final <- if (!is.null(species_df)) nrow(species_df) else 0L

      session_log    <- build_session_log(poly, source_label, n_bbox, n_final, anchor_result)
      rv$species_df  <- species_df
      rv$session_log <- session_log
      rv$status      <- "done"

      setProgress(1, detail = "Complete.")
    })
  }

  observeEvent(input$run_query, {
    poly <- get_polygon()

    if (is.null(poly)) {
      showNotification(
        "No study area polygon loaded. Upload a file or draw a polygon on the map.",
        type = "error"
      )
      return()
    }

    validation   <- validate_polygon(poly)
    has_errors   <- length(validation$errors)   > 0
    has_warnings <- length(validation$warnings) > 0

    if (has_errors || has_warnings) {
      rv$pending_polygon <- poly
      modal_body <- tagList()

      if (has_errors) {
        modal_body <- tagList(modal_body,
          div(class = "alert alert-danger",
            tags$strong("Errors (blocking — analysis cannot proceed):"),
            tags$ul(lapply(validation$errors, tags$li))
          )
        )
      }
      if (has_warnings) {
        modal_body <- tagList(modal_body,
          div(class = "alert alert-warning",
            tags$strong("Warnings:"),
            tags$ul(lapply(validation$warnings, tags$li))
          )
        )
      }

      showModal(modalDialog(
        title      = "Polygon Validation",
        modal_body,
        footer     = tagList(
          if (!has_errors) {
            actionButton("confirm_proceed", "Proceed Anyway", class = "btn-warning")
          },
          modalButton("Cancel")
        ),
        easyClose  = FALSE
      ))
      return()
    }

    tryCatch(
      do_analysis(poly, source_label_current()),
      error = function(e) {
        rv$status <- "error"
        showNotification(paste("Analysis error:", e$message), type = "error", duration = NULL)
      }
    )
  })

  observeEvent(input$confirm_proceed, {
    removeModal()
    poly <- rv$pending_polygon
    if (!is.null(poly)) {
      tryCatch(
        do_analysis(poly, source_label_current()),
        error = function(e) {
          rv$status <- "error"
          showNotification(paste("Analysis error:", e$message), type = "error", duration = NULL)
        }
      )
    }
  })

  output$main_map <- leaflet::renderLeaflet({
    make_base_map()
  })

  observe({
    poly      <- rv$polygon
    map_proxy <- leaflet::leafletProxy("main_map", session)
    map_proxy %>% leaflet::clearGroup("polygon")
    if (!is.null(poly)) {
      add_polygon_layer(map_proxy, poly)
      bb <- sf::st_bbox(poly)
      map_proxy %>% leaflet::fitBounds(bb["xmin"], bb["ymin"], bb["xmax"], bb["ymax"])
    }
  })

  observe({
    map_proxy <- leaflet::leafletProxy("main_map", session)
    map_proxy %>% leaflet::clearGroup("heatmap")
    pts <- rv$occ_points
    if (!is.null(pts) && nrow(pts) > 0) {
      add_heatmap_layer(map_proxy, pts)
    }
  })

  output$map_info_box <- renderUI({
    poly <- rv$polygon
    if (is.null(poly)) {
      return(div(class = "alert alert-info mt-2",
        "Load a study area polygon or draw one on the map, then click Run Analysis."
      ))
    }
    area_km2 <- tryCatch(
      round(sum(as.numeric(sf::st_area(poly))) / 1e6, 1),
      error = function(e) NA_real_
    )
    div(class = "alert alert-secondary mt-2",
      tags$strong("Study area loaded. "),
      sprintf("Approximate area: %s km\u00b2", formatC(area_km2, format = "f", digits = 1))
    )
  })

  output$species_table <- DT::renderDT({
    req(rv$species_df)
    df <- rv$species_df

    DT::datatable(
      df,
      rownames = FALSE,
      colnames = c("Species", "Family", "Confidence Tier",
                   "Occurrence Records", "Range Overlap (%)", "IUCN Status"),
      filter   = "top",
      options  = list(
        pageLength      = 25,
        searchHighlight = TRUE,
        order           = list(list(2L, "asc")),
        columnDefs      = list(list(className = "dt-center", targets = 2:5))
      )
    ) %>%
      DT::formatRound("overlap_pct", digits = 2) %>%
      DT::formatStyle(
        "confidence_tier",
        target          = "row",
        backgroundColor = DT::styleEqual(
          c("High",        "Moderate",     "Low",          "Very Low"),
          c("lightgreen",  "lightyellow",  "lightsalmon",  "lightgrey")
        )
      )
  })

  output$tier_summary_bar <- renderUI({
    req(rv$species_df)
    df     <- rv$species_df
    counts <- table(df$confidence_tier)

    tiers  <- c("High", "Moderate", "Low", "Very Low")
    colors <- c(High = "#90EE90", Moderate = "#FFFFE0", Low = "#FFA07A", "Very Low" = "#D3D3D3")

    boxes <- lapply(tiers, function(t) {
      n <- if (t %in% names(counts)) as.integer(counts[[t]]) else 0L
      div(class = "tier-box", style = paste0("background:", colors[t], ";"),
        paste0(t, ": ", n)
      )
    })

    tagList(
      div(style = "padding:10px 0;",
        h5("Species by Confidence Tier:"),
        do.call(tagList, boxes)
      ),
      p(class = "text-muted", style = "font-size:0.85em; margin-top:6px;",
        "High/Moderate tiers have stronger data support (range overlap AND occurrence records). Low/Very Low are more speculative."
      ),
      hr()
    )
  })

  output$anchor_check_ui <- renderUI({
    req(rv$anchor_result)
    result  <- rv$anchor_result
    n_pass  <- sum(result)
    n_total <- length(result)

    rows <- lapply(names(result), function(sp) {
      pass <- result[[sp]]
      badge_class <- if (pass) "anchor-badge-pass" else "anchor-badge-fail"
      tags$tr(
        tags$td(tags$em(sp)),
        tags$td(span(class = badge_class, if (pass) "PASS" else "FAIL"))
      )
    })

    all_fail_alert <- if (n_pass == 0) {
      div(class = "alert alert-danger mt-2",
        tags$strong(
          "Plausibility check FAILED \u2014 BIEN coverage appears insufficient for this region.",
          " All predictions should be treated as highly speculative."
        )
      )
    } else NULL

    tagList(
      h5("Anchor Species Plausibility Check"),
      p(class = "text-muted", style = "font-size:0.88em;",
        paste0(
          "These 5 ecologically characteristic Amazonian species serve as a plausibility check. ",
          "Their presence in the predicted list reflects BIEN\u2019s data coverage for this region. ",
          n_pass, " of ", n_total, " present."
        )
      ),
      tags$table(
        class = "table table-sm table-bordered",
        style = "max-width:520px;",
        tags$thead(
          tags$tr(tags$th("Species"), tags$th("In Predicted List"))
        ),
        tags$tbody(rows)
      ),
      all_fail_alert
    )
  })

  output$occ_density_hist <- renderPlot({
    req(rv$species_df)
    df <- rv$species_df
    if (nrow(df) == 0) {
      plot.new()
      text(0.5, 0.5, "No species to display.", cex = 1.4, col = "grey50")
      return(invisible())
    }
    old_par <- par(mar = c(5, 4, 4, 2))
    on.exit(par(old_par), add = TRUE)
    hist(
      log10(df$data_support_n + 1),
      main   = "Occurrence Record Counts per Predicted Species",
      xlab   = expression(log[10](occurrence~records + 1)),
      ylab   = "Number of species",
      col    = "steelblue",
      border = "white",
      breaks = 20
    )
    mtext(
      "Note: Low counts may reflect collection gaps rather than true rarity (BIEN sampling is uneven).",
      side = 1, line = 4, cex = 0.78, col = "grey40"
    )
  })

  output$dl_csv <- downloadHandler(
    filename = function() {
      lbl <- if (!is.null(rv$session_log)) {
        gsub("[^a-zA-Z0-9]", "_", rv$session_log$polygon_source)
      } else "polygon"
      paste0("BIEN_species_list_", lbl, "_", format(Sys.Date(), "%Y%m%d"), ".csv")
    },
    content = function(file) {
      req(rv$species_df, rv$session_log)
      dwc <- build_dwc_csv(rv$species_df, rv$session_log)
      write.csv(dwc, file, row.names = FALSE, fileEncoding = "UTF-8")
    }
  )

  output$dl_html <- downloadHandler(
    filename = function() {
      lbl <- if (!is.null(rv$session_log)) {
        gsub("[^a-zA-Z0-9]", "_", rv$session_log$polygon_source)
      } else "polygon"
      paste0("BIEN_report_", lbl, "_", format(Sys.Date(), "%Y%m%d"), ".html")
    },
    content = function(file) {
      req(rv$species_df, rv$session_log, rv$polygon)
      rmarkdown::render(
        input       = "../report_template/report.Rmd",
        output_file = file,
        params      = list(
          species_df  = rv$species_df,
          session_log = rv$session_log,
          polygon     = rv$polygon
        ),
        envir  = new.env(parent = globalenv()),
        quiet  = TRUE
      )
    }
  )
}

shinyApp(ui = ui, server = server)
