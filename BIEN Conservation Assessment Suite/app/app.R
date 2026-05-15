## ── explicit bootstrap in case global.R failed silently ──────────────────────
library(shiny)
library(bslib)
library(dplyr)
library(sf)
library(leaflet)
library(leaflet.extras)
library(DT)
library(jsonlite)
library(digest)
library(promises)
library(future)

for (.f in list.files("../modules", pattern = "\\.R$", full.names = TRUE)) source(.f)
for (.f in list.files("../utils",   pattern = "\\.R$", full.names = TRUE)) source(.f)
rm(.f)
## ─────────────────────────────────────────────────────────────────────────────

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
      .sdm-overestimate-banner { background:#fff3cd; border:1px solid #ffc107;
                                 border-left:6px solid #e67e22; border-radius:4px;
                                 padding:10px 16px; margin-bottom:12px; font-size:0.9em; }
      .native-warn { color:#c0392b; font-weight:bold; }
    "))
  ),

  sidebarLayout(
    sidebarPanel(
      width = 3,
      h4("BIEN Flora Scout"),
      p("Phase 1 \u2014 Conservation Assessment Suite", class = "text-muted",
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
          fileInput("geojson_file", "Upload GeoJSON", accept = c(".geojson", ".json"))
        ),
        conditionalPanel(
          condition = "input.file_type == 'shapefile'",
          fileInput("shapefile_zip", "Upload shapefile (.zip)", accept = ".zip")
        ),
        conditionalPanel(
          condition = "input.file_type == 'pilot'",
          div(class = "alert alert-info", style = "font-size:0.85em; padding:8px;",
            "Loads the Alto Japur\u00e1 (Brazil) pilot study area.")
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
          class = "btn-success btn-sm", style = "width:100%; margin-bottom:6px;"),
        downloadButton("dl_html", "Download Report (HTML)",
          class = "btn-info btn-sm", style = "width:100%;")
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
          div(class = "sdm-overestimate-banner",
            tags$strong("\u26a0 Stacked SDM richness note:"),
            " Stacking binary range predictions systematically",
            tags$strong(" overestimates"), " local species richness",
            " (Calabrese et al. 2014, GEB 23:1365\u20131372).",
            " Treat this list as an ", tags$strong("upper bound"), ", not a confirmed inventory.",
            " Confidence tiers are heuristic thresholds, not calibrated probability classes.",
            " High / Moderate tiers indicate stronger data support, not certainty of presence."
          ),
          uiOutput("native_status_summary"),
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
      running = "Analysis running\u2026 please wait (2\u20135 min for large AOIs).",
      done    = paste0("Complete. ", nrow(rv$species_df), " species predicted."),
      error   = "Analysis failed. Check inputs and try again."
    )
  })

  observeEvent(input$main_map_draw_new_feature, {
    feat        <- input$main_map_draw_new_feature
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
    if (input$input_mode == "draw") return(rv$polygon)

    ft <- input$file_type
    poly <- NULL

    if (ft == "geojson") {
      req(input$geojson_file)
      poly <- tryCatch(sf::st_read(input$geojson_file$datapath, quiet = TRUE),
                       error = function(e) NULL)
    } else if (ft == "shapefile") {
      req(input$shapefile_zip)
      td <- tempfile(); dir.create(td)
      # Zip Slip mitigation: inspect manifest before extracting
      manifest <- tryCatch(unzip(input$shapefile_zip$datapath, list = TRUE), error = function(e) NULL)
      if (is.null(manifest) || any(grepl("..", manifest$Name, fixed = TRUE))) return(NULL)
      ok <- tryCatch({ unzip(input$shapefile_zip$datapath, exdir = td); TRUE },
                     error = function(e) FALSE)
      if (!ok) return(NULL)
      shp_files <- list.files(td, pattern = "\\.shp$", recursive = TRUE, full.names = TRUE)
      if (length(shp_files) == 0) return(NULL)
      poly <- tryCatch(sf::st_read(shp_files[1], quiet = TRUE), error = function(e) NULL)
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
    if (!all(sf::st_is_valid(poly))) poly <- sf::st_make_valid(poly)
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

  # ── Async analysis ─────────────────────────────────────────────────────────
  # BIEN API calls run in a background multisession worker.
  # rv$* writes happen only in the .then() callback on the main session thread.
  run_analysis <- function(poly, source_label) {
    rv$status <- "running"

    progress <- shiny::Progress$new(session, min = 0, max = 1)
    progress$set(message = "Connecting to BIEN\u2026", value = 0.05,
                 detail  = "Fetching range maps and occurrence records (2\u20135 min).")

    promises::future_promise({
      # Runs in background R worker — no rv$ access here
      list(
        ranges_sf = query_bien_ranges(poly),
        occ_raw   = fetch_bien_occurrences_raw(poly)
      )
    }) %...>% (function(result) {
      # Back on main session thread
      progress$set(value = 0.75, message = "Processing results\u2026",
                   detail = "Assigning confidence tiers.")
      occ_counts     <- query_bien_occurrences(result$occ_raw)
      occ_points     <- get_bien_occurrence_points(result$occ_raw)
      rv$occ_points  <- occ_points
      species_df     <- assign_confidence_tiers(result$ranges_sf, occ_counts)
      anchor_result  <- check_anchor_species(species_df)
      rv$anchor_result <- anchor_result
      n_bbox  <- if (!is.null(result$ranges_sf)) nrow(result$ranges_sf) else 0L
      n_final <- if (!is.null(species_df)) nrow(species_df) else 0L
      session_log    <- build_session_log(poly, source_label, n_bbox, n_final, anchor_result)
      rv$species_df  <- species_df
      rv$session_log <- session_log
      rv$status      <- "done"
      progress$close()
    }) %...!% (function(e) {
      rv$status <- "error"
      progress$close()
      showNotification(paste("Analysis error:", e$message), type = "error", duration = NULL)
    })
  }

  observeEvent(input$run_query, {
    poly <- get_polygon()

    if (is.null(poly)) {
      showNotification(
        "No study area polygon loaded. Upload a file or draw on the map.",
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
            tags$strong("Errors (blocking):"),
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
        title     = "Polygon Validation",
        modal_body,
        footer    = tagList(
          if (!has_errors) actionButton("confirm_proceed", "Proceed Anyway",
                                        class = "btn-warning"),
          modalButton("Cancel")
        ),
        easyClose = FALSE
      ))
      return()
    }

    rv$polygon <- poly
    run_analysis(poly, source_label_current())
  })

  observeEvent(input$confirm_proceed, {
    removeModal()
    poly <- rv$pending_polygon
    if (!is.null(poly)) {
      rv$polygon <- poly
      run_analysis(poly, source_label_current())
    }
  })

  # ── Map outputs ─────────────────────────────────────────────────────────────
  output$main_map <- leaflet::renderLeaflet({ make_base_map() })

  observe({
    poly      <- rv$polygon
    map_proxy <- leaflet::leafletProxy("main_map", session)
    leaflet::clearGroup(map_proxy, "polygon")
    if (!is.null(poly)) {
      add_polygon_layer(map_proxy, poly)
      bb <- sf::st_bbox(poly)
      leaflet::fitBounds(map_proxy, bb["xmin"], bb["ymin"], bb["xmax"], bb["ymax"])
    }
  })

  observe({
    map_proxy <- leaflet::leafletProxy("main_map", session)
    leaflet::clearGroup(map_proxy, "heatmap")
    pts <- rv$occ_points
    if (!is.null(pts) && nrow(pts) > 0) add_heatmap_layer(map_proxy, pts)
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

  # ── Species list outputs ─────────────────────────────────────────────────────
  output$native_status_summary <- renderUI({
    df <- rv$species_df
    if (is.null(df) || nrow(df) == 0) return(NULL)
    n_introduced <- sum(df$native_status_flag == "likely_introduced", na.rm = TRUE)
    n_unavail    <- sum(df$native_status_flag == "status_unavailable", na.rm = TRUE)
    tagList(
      if (n_introduced > 0)
        div(class = "alert alert-danger",
          tags$strong(paste0("\u26a0 ", n_introduced, " species flagged as likely introduced")),
          " based on majority-vote native_status from BIEN occurrence records.",
          " Review before including in a native-flora inventory."
        ),
      if (n_unavail > 0)
        div(class = "alert alert-warning",
          paste0(n_unavail, " species have no native_status data available in BIEN",
                 " for the queried area. Native/introduced status cannot be determined for these taxa.")
        )
    )
  })

  output$tier_summary_bar <- renderUI({
    df <- rv$species_df
    if (is.null(df) || nrow(df) == 0) return(NULL)
    tier_counts <- table(factor(df$confidence_tier,
                                levels = c("High","Moderate","Low","Very Low")))
    tier_colors <- c(High = "#27ae60", Moderate = "#f39c12",
                     Low  = "#e67e22", `Very Low` = "#95a5a6")
    boxes <- lapply(names(tier_counts), function(t) {
      div(class = "tier-box",
          style = sprintf("background:%s; color:%s;",
                          tier_colors[t],
                          if (t == "Very Low") "#333" else "#fff"),
          t, br(), strong(tier_counts[[t]])
      )
    })
    do.call(div, c(boxes, list(style = "margin-bottom:10px;")))
  })

  output$species_table <- DT::renderDT({
    df <- rv$species_df
    if (is.null(df) || nrow(df) == 0) return(NULL)

    display <- data.frame(
      Species         = df$accepted_name,
      Family          = df$family,
      Tier            = df$confidence_tier,
      `N Occ (polygon)` = df$data_support_n,
      `% AOI covered`   = round(df$overlap_pct_polygon, 1),
      `% Range in AOI`  = round(df$overlap_pct_range,   1),
      `Native Status`   = df$native_status_flag,
      IUCN            = df$iucn_status,
      stringsAsFactors = FALSE,
      check.names = FALSE
    )

    DT::datatable(
      display,
      rownames = FALSE,
      filter   = "top",
      options  = list(pageLength = 25, scrollX = TRUE,
                      columnDefs = list(list(width = "180px", targets = 0))),
      caption  = htmltools::tags$caption(
        style = "caption-side:bottom; font-size:0.82em; color:#666;",
        paste0("N Occ (polygon): occurrence records clipped to drawn polygon (deduplicated). ",
               "% AOI covered: fraction of the assessment area predicted suitable (used for tiers). ",
               "% Range in AOI: fraction of species total range inside AOI (endemism indicator). ",
               "Tiers are heuristic, not calibrated probability classes.")
      )
    ) %>%
      DT::formatStyle(
        "Tier",
        backgroundColor = DT::styleEqual(
          c("High",       "Moderate",    "Low",         "Very Low"),
          c("lightgreen", "lightyellow", "lightsalmon", "lightgrey")
        )
      ) %>%
      DT::formatStyle(
        "Native Status",
        color = DT::styleEqual("likely_introduced", "red"),
        fontWeight = DT::styleEqual("likely_introduced", "bold")
      )
  }, server = TRUE)

  # ── Data Quality tab ─────────────────────────────────────────────────────────
  output$anchor_check_ui <- renderUI({
    ar <- rv$anchor_result
    if (is.null(ar)) return(div(class = "alert alert-info", "Run analysis to see anchor species check."))

    items <- lapply(names(ar), function(sp) {
      if (isTRUE(ar[[sp]])) {
        span(class = "anchor-badge-pass", sp, " \u2714")
      } else {
        span(class = "anchor-badge-fail", sp, " \u2718")
      }
    })

    all_pass <- all(unlist(ar))
    tagList(
      h5("Plausibility Gate \u2014 Anchor Species"),
      p(style = "font-size:0.88em; color:#555;",
        "These wide-ranging western Amazonian species are expected to appear in any valid",
        " Alto Japur\u00e1 query. A FAIL indicates a spatial, CRS, or BIEN coverage issue",
        " rather than true absence."),
      div(style = "margin:8px 0;", do.call(tagList, items)),
      div(
        class = if (all_pass) "alert alert-success" else "alert alert-danger",
        if (all_pass)
          "\u2714 All anchor species detected — polygon and BIEN data appear consistent."
        else
          "\u2718 One or more anchor species missing. Interpret results with caution."
      )
    )
  })

  output$occ_density_hist <- renderPlot({
    df <- rv$species_df
    if (is.null(df) || nrow(df) == 0) return(NULL)
    par(mar = c(4, 4, 2, 1))
    hist(log10(df$data_support_n + 1),
         breaks = 20,
         col    = "#3498db",
         border = "white",
         main   = "Distribution of Occurrence Record Counts (log\u2081\u2080 scale)",
         xlab   = "log\u2081\u2080(N occurrences in polygon + 1)",
         ylab   = "Number of species")
    abline(v = log10(c(2, 5, 20) + 1), col = c("#e67e22","#f39c12","#27ae60"),
           lty = 2, lwd = 1.5)
    legend("topright",
           legend = c("Low threshold (n=2)", "Moderate threshold (n=5)", "High threshold (n=20)"),
           col    = c("#e67e22","#f39c12","#27ae60"), lty = 2, lwd = 1.5, cex = 0.8)
  })

  # ── Downloads ────────────────────────────────────────────────────────────────
  output$dl_csv <- downloadHandler(
    filename = function() {
      paste0("BIEN_flora_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".csv")
    },
    content = function(file) {
      df  <- rv$species_df
      sl  <- rv$session_log
      if (is.null(df) || is.null(sl)) return(NULL)
      dwc <- build_dwc_csv(df, sl)
      write.csv(dwc, file, row.names = FALSE)
    }
  )

  output$dl_html <- downloadHandler(
    filename = function() {
      paste0("BIEN_report_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".html")
    },
    content = function(file) {
      df   <- rv$species_df
      sl   <- rv$session_log
      poly <- rv$polygon
      if (is.null(df) || is.null(sl)) return(NULL)
      tmp <- file.path(tempdir(), "report.Rmd")
      file.copy("../report_template/report.Rmd", tmp, overwrite = TRUE)
      rmarkdown::render(
        tmp,
        output_file = file,
        params      = list(species_df = df, session_log = sl, polygon = poly),
        envir       = new.env(parent = globalenv()),
        quiet       = TRUE
      )
    }
  )
}

shinyApp(ui, server)
