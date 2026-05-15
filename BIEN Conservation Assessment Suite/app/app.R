# app.R — BIEN Flora Explora: Conservation Assessment Suite
# Main Shiny UI + server. Implements the three-stage async query architecture:
#   Stage 1 — BIEN_list_country: fast political-unit checklist (seconds)
#   Stage 2 — BIEN_occurrence_sf: full occurrence records (minutes)
#   Stage 3 — BIEN_ranges_sf: range overlap analysis (slow, optional)
#
# Stages 1 and 2 run concurrently in separate future workers.
# The UI updates progressively as each stage completes.

# ── Package bootstrap (explicit, in case global.R failed silently) ────────────
# global.R is auto-sourced by Shiny before app.R, but we re-declare packages
# here as a defensive measure so the app never silently degrades.
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
if (!requireNamespace("R.utils", quietly = TRUE)) {
  warning("R.utils not installed; BIEN call timeouts will be disabled.")
}

# Re-source modules and utils (idempotent; no-op if already loaded)
for (.f in list.files("../modules", pattern = "\\.R$", full.names = TRUE)) sys.source(.f, envir = globalenv())
for (.f in list.files("../utils",   pattern = "\\.R$", full.names = TRUE)) sys.source(.f, envir = globalenv())
rm(.f)

# Ensure async plan is active even if global.R partially failed.
# plan() is idempotent; re-declaring it is cheap and safe.
future::plan(future::multisession, workers = 3)
message("[BIEN-app] Active future plan: ", paste(class(future::plan())[1:2], collapse = " / "),
        " | workers requested: 3")
# ─────────────────────────────────────────────────────────────────────────────

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

      /* Visible 'analysis running' indicators */
      .running-banner {
        background: linear-gradient(90deg, #1abc9c 0%, #16a085 100%);
        color:#fff; padding:18px 24px; border-radius:8px; margin-bottom:14px;
        font-size:1.1em; box-shadow:0 2px 8px rgba(0,0,0,0.15);
        display:flex; align-items:center; gap:14px;
      }
      .running-banner .spinner {
        width:28px; height:28px; border:4px solid rgba(255,255,255,0.35);
        border-top-color:#fff; border-radius:50%;
        animation: bien-spin 1s linear infinite; flex-shrink:0;
      }
      @keyframes bien-spin { to { transform: rotate(360deg); } }
      .running-banner .elapsed { font-weight:bold; font-size:1.15em; margin-left:auto;
                                  background:rgba(0,0,0,0.18); padding:4px 12px; border-radius:4px; }
      .status-running { color:#16a085; font-weight:bold; }
      .status-partial { color:#e67e22; font-weight:bold; }
      .status-done    { color:#27ae60; font-weight:bold; }
      .status-error   { color:#c0392b; font-weight:bold; }
      .btn-primary[disabled], .btn-primary.disabled {
        background:#7f8c8d !important; border-color:#7f8c8d !important;
        cursor:not-allowed !important;
      }
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
            "KML / KMZ (.kml/.kmz)"   = "kml",
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
          condition = "input.file_type == 'kml'",
          fileInput("kml_file", "Upload KML or KMZ", accept = c(".kml", ".kmz"))
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
      div(style = "margin-top:10px; padding:8px; background:#f8f9fa; border-radius:6px; border:1px solid #dee2e6;",
        tags$small(tags$strong("Occurrence filters (Stage 2):")),
        div(style = "margin-top:4px;",
          checkboxInput("include_nonnative",
            label = tags$span(style="font-size:0.85em;",
              "Include non-native / introduced species"
            ),
            value = FALSE
          )
        ),
        div(
          checkboxInput("include_geounvalidated",
            label = tags$span(style="font-size:0.85em;",
              "Include geo-unvalidated records"
            ),
            value = FALSE
          )
        )
      ),
      div(style = "margin-top:8px;",
        checkboxInput("include_ranges",
          label = tags$span(style="font-size:0.85em;",
            "Include range overlap analysis ",
            tags$em("(slow, ~20–60 min)")
          ),
          value = FALSE
        )
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
      uiOutput("running_banner"),
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

  # rv holds all app state. Writing to rv from .then() callbacks is safe
  # because Shiny's promise integration guarantees callbacks run on the
  # main session thread (no concurrent writes to rv from workers).
  rv <- reactiveValues(
    polygon         = NULL,   # validated sf polygon from user input
    species_df      = NULL,   # current species data.frame (updated by each stage)
    session_log     = NULL,   # provenance metadata for CSV/HTML export
    occ_raw         = NULL,   # raw BIEN_occurrence_sf output (Stage 2)
    occ_counts      = NULL,   # per-species occurrence summary from Stage 2
    occ_points      = NULL,   # subsampled points for heatmap (≤5000 rows)
    anchor_result   = NULL,   # named logical vector from check_anchor_species()
    pending_polygon = NULL,   # polygon held for user confirmation on validation warnings
    status          = "idle", # one of: idle / running / listing / enriching / partial / done / error
    started_at      = NULL    # POSIXct: when Run Analysis was clicked (for elapsed timer)
  )

  # 1-second reactive timer — drives the elapsed-time display in the running banner.
  # Takes a dependency in running_banner's renderUI so it re-renders every second.
  elapsed_tick <- reactiveTimer(1000)

  output$results_ready <- reactive({
    !is.null(rv$species_df) && nrow(rv$species_df) > 0
  })
  outputOptions(output, "results_ready", suspendWhenHidden = FALSE)

  output$status_text <- renderText({
    switch(rv$status,
      idle      = "Ready. Load a polygon and click Run Analysis.",
      running   = "Stage 1: Querying BIEN species checklist\u2026",
      listing   = paste0("Polygon species list ready (\u2248", nrow(rv$species_df), " species). Stage 2: loading occurrence counts\u2026"),
      enriching = paste0(nrow(rv$species_df), " species with occurrence tiers. Stage 3: range overlap analysis running\u2026"),
      partial   = paste0(nrow(rv$species_df), " species. Range overlap analysis still running\u2026"),
      done      = paste0("Complete. ", nrow(rv$species_df), " species."),
      error     = "Analysis failed. Check inputs and try again."
    )
  })

  # Expose running state to UI conditionalPanel + JS
  output$is_running <- reactive({ rv$status %in% c("running", "listing", "enriching", "partial") })
  outputOptions(output, "is_running", suspendWhenHidden = FALSE)

  # Prominent running banner with live elapsed-time counter
  output$running_banner <- renderUI({
    if (!rv$status %in% c("running", "listing", "enriching", "partial")) return(NULL)
    elapsed_tick()  # take a dependency so this re-renders every second
    secs <- if (!is.null(rv$started_at))
      as.integer(difftime(Sys.time(), rv$started_at, units = "secs"))
    else 0L
    mm <- sprintf("%02d:%02d", secs %/% 60, secs %% 60)
    msg <- switch(rv$status,
      running   = list(
        strong  = "Stage 1 of 3: Querying BIEN species checklist\u2026",
        detail  = "BIEN_list_sf — typically 5\u201330 seconds. Species table will appear shortly."
      ),
      listing   = list(
        strong  = "Stage 2 of 3: Loading occurrence records\u2026",
        detail  = "Preliminary species list shown. Occurrence counts and heatmap loading in background."
      ),
      enriching = list(
        strong  = "Stage 3 of 3: Range overlap analysis running\u2026",
        detail  = "Occurrence-based tiers shown. Table will update with range overlap columns when complete."
      ),
      partial   = list(
        strong  = "Range overlap analysis running\u2026",
        detail  = "Occurrence-based tiers shown. Table will update when complete. Do not refresh."
      )
    )
    div(class = "running-banner",
      div(class = "spinner"),
      div(
        tags$div(tags$strong(msg$strong)),
        tags$div(style = "font-size:0.85em; opacity:0.92; margin-top:2px;", msg$detail)
      ),
      div(class = "elapsed", "\u23f1 ", mm)
    )
  })

  observeEvent(input$main_map_draw_new_feature, {
    feat        <- input$main_map_draw_new_feature
    geojson_str <- jsonlite::toJSON(feat, auto_unbox = TRUE)
    poly <- tryCatch({
      p <- sf::st_read(geojson_str, quiet = TRUE)
      p <- sf::st_transform(p, 4326)
      if (!isTRUE(all(sf::st_is_valid(p)))) p <- sf::st_make_valid(p)
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
      if (is.null(manifest) || any(grepl("..", manifest$Name, fixed = TRUE)) ||
          any(grepl("^/", manifest$Name))) return(NULL)
      ok <- tryCatch({ unzip(input$shapefile_zip$datapath, exdir = td); TRUE },
                     error = function(e) FALSE)
      if (!ok) return(NULL)
      shp_files <- list.files(td, pattern = "\\.shp$", recursive = TRUE, full.names = TRUE)
      if (length(shp_files) == 0) return(NULL)
      poly <- tryCatch(sf::st_read(shp_files[1], quiet = TRUE), error = function(e) NULL)
    } else if (ft == "kml") {
      req(input$kml_file)
      kml_path <- input$kml_file$datapath
      # KMZ = zipped KML; extract first .kml from archive
      if (grepl("\\.kmz$", input$kml_file$name, ignore.case = TRUE)) {
        td <- tempfile(); dir.create(td)
        manifest <- tryCatch(unzip(kml_path, list = TRUE), error = function(e) NULL)
        if (is.null(manifest) || any(grepl("..", manifest$Name, fixed = TRUE)) ||
            any(grepl("^/", manifest$Name))) return(NULL)
        ok <- tryCatch({ unzip(kml_path, exdir = td); TRUE }, error = function(e) FALSE)
        if (!ok) return(NULL)
        kml_files <- list.files(td, pattern = "\\.kml$", recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
        if (length(kml_files) == 0) return(NULL)
        kml_path <- kml_files[1]
      }
      poly <- tryCatch(sf::st_read(kml_path, quiet = TRUE), error = function(e) NULL)
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
    if (!isTRUE(all(sf::st_is_valid(poly)))) poly <- sf::st_make_valid(poly)
    poly
  })

  source_label_current <- function() {
    if (input$input_mode == "draw") return("Drawn on map")
    switch(input$file_type,
      geojson   = "GeoJSON upload",
      shapefile = "Shapefile upload",
      kml       = "KML/KMZ upload",
      pilot     = "Pilot polygon (Alto Japur\u00e1)",
      "Unknown"
    )
  }

  # ── Async analysis — Three-stage design ─────────────────────────────────────
  #
  # Stage 1 (Worker 1): query_species_list_fast()
  #   Uses BIEN_list_sf() — a PostGIS spatial intersection against the drawn polygon.
  #   Returns only species documented within the polygon boundary (not a country superset).
  #   Populates an immediate species table so the user sees something fast.
  #
  # Stage 2 (Worker 2): fetch_bien_occurrences_raw() → query_bien_occurrences()
  #   Full BIEN_occurrence_sf() call — server-side polygon intersection (minutes).
  #   Provides spatially precise occurrence counts and enables the heatmap.
  #   Overwrites Stage 1 table with occurrence-based confidence tiers.
  #
  # Stage 3 (Worker 3, optional): query_bien_ranges()
  #   BIEN_ranges_sf() — returns range polygons with overlap percentages (slow).
  #   Only activated when the user checks "Include range overlap analysis."
  #   Updates the table with overlap_pct_polygon and overlap_pct_range columns.
  #
  # All rv$* writes happen in .then() / %...>% callbacks on the main session
  # thread, NOT inside the worker futures. This is the correct async pattern
  # for Shiny: futures compute, callbacks update state.
  run_analysis <- function(poly, source_label) {
    rv$status     <- "running"
    rv$started_at <- Sys.time()
    rv$occ_raw    <- NULL
    rv$occ_counts <- NULL
    rv$occ_points <- NULL

    include_ranges        <- isTRUE(input$include_ranges)
    natives_only_snap     <- !isTRUE(input$include_nonnative)    # default TRUE (native only)
    geo_valid_only_snap   <- !isTRUE(input$include_geounvalidated)  # default TRUE (geo-valid only)

    # Snapshot CFG on the main thread before launching workers.
    # Workers cannot access Shiny session globals directly; they need the
    # snapshot passed in through their closure or set via options() inside
    # the worker body (first line: options(bien_cfg = cfg_snap)).
    cfg_snap       <- getOption("bien_cfg")

    progress <- shiny::Progress$new(session, min = 0, max = 1)
    progress$set(
      message = "Stage 1: Querying BIEN species checklist\u2026",
      value   = 0.05,
      detail  = "BIEN_list_sf \u2014 typically 5\u201330 seconds."
    )

    # ---- Stage 1 (Worker 1): polygon-specific species checklist ----------------
    # query_species_list_fast() uses BIEN_list_sf() — a PostGIS spatial
    # intersection that returns only species documented within the polygon boundary.
    # Stage 1 is non-fatal: if it fails, Stage 2 still supplies the species list.
    promises::future_promise({
      options(bien_cfg = cfg_snap)  # restore CFG in worker session
      query_species_list_fast(poly)
    }, seed = TRUE) %...>% (function(species_vec) {
      progress$set(value = 0.25,
                   message = "Checklist ready. Loading occurrence records\u2026",
                   detail  = "Stage 2 running in background \u2014 table will update with counts.")
      if (!is.null(species_vec) && length(species_vec) > 0) {
        # Build a minimal species data.frame from the checklist names only.
        # n_occurrences = 0 because occurrence data is not yet available.
        # assign_confidence_tiers() will assign Very Low tier to these rows;
        # they will be overwritten by Stage 2 with real occurrence-based tiers.
        occ_df_s1 <- data.frame(
          species            = species_vec,
          n_occurrences      = 0L,
          family             = NA_character_,
          native_status_flag = "status_unavailable",
          stringsAsFactors   = FALSE
        )
        species_df_s1  <- assign_confidence_tiers(NULL, occ_df_s1)
        anchor_result  <- check_anchor_species(species_df_s1)
        rv$anchor_result <- anchor_result
        rv$session_log <- build_session_log(poly, source_label, 0L, nrow(species_df_s1), anchor_result)
        rv$species_df  <- species_df_s1
      }
      rv$status <- "listing"   # signal UI: Stage 2 is now running
    }) %...!% (function(e) {
      # Stage 1 failure is non-fatal: Stage 2 will supply occurrence-based species
      warning("Stage 1 BIEN_list_sf failed: ", e$message)
      rv$status <- "listing"
    })

    # ---- Stage 2 (Worker 2): full occurrence records — always runs ------------
    # BIEN_occurrence_sf() performs a server-side PostGIS polygon intersection,
    # returning all occurrence records inside the user's polygon.
    # This is the authoritative spatial refinement step. It overwrites the
    # Stage 1 table with per-species occurrence counts, heatmap points,
    # and occurrence-based confidence tiers.
    promises::future_promise({
      options(bien_cfg = cfg_snap)  # restore CFG in worker session
      fetch_bien_occurrences_raw(poly,
                                 natives_only   = natives_only_snap,
                                 geo_valid_only = geo_valid_only_snap)
    }, seed = TRUE) %...>% (function(occ_raw) {
      progress$set(value = 0.65, message = "Occurrence records ready. Processing\u2026", detail = "")
      occ_counts    <- query_bien_occurrences(occ_raw)   # deduplicate + summarise per-species
      rv$occ_raw    <- occ_raw
      rv$occ_counts <- occ_counts
      rv$occ_points <- get_bien_occurrence_points(occ_raw)  # ≤5000 pts for heatmap
      species_df    <- assign_confidence_tiers(NULL, occ_counts)
      anchor_result <- check_anchor_species(species_df)
      rv$anchor_result <- anchor_result
      rv$session_log   <- build_session_log(poly, source_label, 0L, nrow(species_df), anchor_result)
      rv$species_df    <- species_df
      if (include_ranges) {
        rv$status <- "enriching"  # Stage 3 will update table further
        progress$set(value = 0.75,
                     message = "Occurrence tiers shown. Range maps running\u2026",
                     detail  = "Stage 3 of 3: table updates with overlap columns when complete.")
      } else {
        rv$status <- "done"
        progress$close()
      }
    }) %...!% (function(e) {
      # Stage 2 failure: keep Stage 1 table visible if it exists; otherwise error state.
      if (is.null(rv$species_df)) rv$status <- "error"
      else if (!rv$status %in% c("enriching", "done")) rv$status <- "done"
      progress$close()
      showNotification(paste("Occurrence query failed:", e$message), type = "error", duration = NULL)
    })

    # ---- Stage 3 (Worker 3): range overlap — optional, user-activated ----------
    # BIEN_ranges_sf() returns SDM-derived range polygons via a PostGIS intersection.
    # Client-side st_intersection() then computes overlap_pct_polygon (fraction of
    # the AOI predicted suitable) and overlap_pct_range (fraction of species total
    # range inside the AOI — an endemism indicator).
    # This stage is slow (20–60 min) because it downloads range geometries for
    # potentially thousands of species. Users must explicitly opt in.
    if (include_ranges) {
      promises::future_promise({
        options(bien_cfg = cfg_snap)  # restore CFG in worker session
        query_bien_ranges(poly)
      }, seed = TRUE) %...>% (function(ranges_sf) {
        # Use the most current occurrence counts available when Stage 3 completes.
        # Stage 2 may have finished before or concurrently with Stage 3.
        occ_counts <- if (!is.null(rv$occ_counts)) {
          rv$occ_counts
        } else if (!is.null(rv$occ_raw)) {
          query_bien_occurrences(rv$occ_raw)  # re-summarise if rv$occ_counts not yet set
        } else {
          data.frame(species = character(), n_occurrences = integer(),
                     family  = character(), native_status_flag = character(),
                     stringsAsFactors = FALSE)
        }
        species_df    <- assign_confidence_tiers(ranges_sf, occ_counts)
        anchor_result <- check_anchor_species(species_df)
        rv$anchor_result <- anchor_result
        n_bbox  <- if (!is.null(ranges_sf)) nrow(ranges_sf) else 0L
        rv$session_log <- build_session_log(poly, source_label, n_bbox, nrow(species_df), anchor_result)
        rv$species_df  <- species_df
        rv$status      <- "done"
        progress$close()
      }) %...!% (function(e) {
        # Stage 3 failure is non-fatal: occurrence-based tiers from Stage 2 remain.
        if (rv$status %in% c("enriching", "partial")) rv$status <- "done"
        progress$close()
        showNotification(
          paste("Range analysis failed; occurrence-based results remain.", e$message),
          type = "warning", duration = 20
        )
      })
    }
  }

  observeEvent(input$run_query, {
    if (rv$status %in% c("running", "listing", "enriching", "partial")) {
      showNotification("Analysis already in progress. Please wait.", type = "warning")
      return()
    }
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
    if (rv$status %in% c("running", "listing", "enriching", "partial")) {
      showNotification("Analysis already in progress. Please wait.", type = "warning")
      return()
    }
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
      if (is.null(df) || is.null(sl)) {
        showNotification("No results available to download.", type = "warning")
        return()
      }
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
      if (is.null(df) || is.null(sl)) {
        showNotification("No results available to download.", type = "warning")
        return()
      }
      template_src <- "../report_template/report.Rmd"
      if (!file.exists(template_src)) {
        showNotification("Report template not found; HTML download unavailable.", type = "error")
        return()
      }
      tmp <- file.path(tempdir(), "report.Rmd")
      file.copy(template_src, tmp, overwrite = TRUE)
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
