library(shiny)
library(DT)
library(httr)
library(jsonlite)

# ── Static field lists ────────────────────────────────────────────────────────

BIEN_STAGING_FIELDS <- c(
  "scrubbed_species_binomial", "scrubbed_family", "scrubbed_genus",
  "scrubbed_author", "scrubbed_taxonomic_status",
  "latitude", "longitude", "date_collected",
  "dataset", "datasource", "dataowner", "collection_code",
  "locality", "country", "state_province", "county", "plot_name",
  "occurrenceID", "basisOfRecord",
  "is_cultivated", "native_status",
  "verbatimLocality", "verbatimElevation",
  "elevation_min", "elevation_max"
)

DWC_TERMS <- c(
  "occurrenceID", "basisOfRecord", "scientificName", "scientificNameAuthorship",
  "family", "genus", "taxonRank", "eventDate", "year", "month", "day",
  "decimalLatitude", "decimalLongitude", "coordinateUncertaintyInMeters",
  "geodeticDatum", "country", "stateProvince", "county", "locality",
  "verbatimLocality", "verbatimElevation", "minimumElevationInMeters",
  "maximumElevationInMeters", "institutionCode", "collectionCode",
  "catalogNumber", "datasetName", "occurrenceStatus", "habitat",
  "recordedBy", "identifiedBy", "taxonID"
)

# ── Canonicalize helper ───────────────────────────────────────────────────────

canonicalize <- function(x) {
  gsub("_+", "_", gsub("[^a-z0-9]+", "_", tolower(trimws(as.character(x)))))
}

# ── Mapping lookup tables (built once at load time) ───────────────────────────

DWC_LOOKUP <- setNames(DWC_TERMS, canonicalize(DWC_TERMS))

DWC_ALIASES <- c(
  scientific_name = "scientificName", species = "scientificName", taxon = "scientificName",
  taxon_name = "scientificName", name = "scientificName",
  lat = "decimalLatitude", latitude = "decimalLatitude", decimal_latitude = "decimalLatitude",
  lon = "decimalLongitude", long = "decimalLongitude", longitude = "decimalLongitude",
  decimal_longitude = "decimalLongitude",
  date = "eventDate", event_date = "eventDate", collection_date = "eventDate",
  date_collected = "eventDate", sample_date = "eventDate",
  state = "stateProvince", state_province = "stateProvince", province = "stateProvince",
  occurrence_id = "occurrenceID", basis_of_record = "basisOfRecord",
  family_name = "family", genus_name = "genus",
  collector = "recordedBy", observer = "recordedBy", recorded_by = "recordedBy",
  site = "locality", plot = "locality", plot_name = "locality", location = "locality",
  institution = "institutionCode", collection = "collectionCode",
  catalog_number = "catalogNumber", dataset = "datasetName", dataset_name = "datasetName",
  habitat_notes = "habitat", notes = NA_character_, elevation = "minimumElevationInMeters",
  elevation_m = "minimumElevationInMeters"
)

BIEN_LOOKUP <- setNames(BIEN_STAGING_FIELDS, canonicalize(BIEN_STAGING_FIELDS))

BIEN_ALIASES <- c(
  scientific_name = "scrubbed_species_binomial", species = "scrubbed_species_binomial",
  scientificname  = "scrubbed_species_binomial", taxon = "scrubbed_species_binomial",
  name = "scrubbed_species_binomial",
  lat = "latitude", decimal_latitude = "latitude", decimallatitude = "latitude",
  lon = "longitude", long = "longitude", decimal_longitude = "longitude",
  decimallongitude = "longitude",
  date = "date_collected", event_date = "date_collected", eventdate = "date_collected",
  collection_date = "date_collected",
  state = "state_province", stateprovince = "state_province",
  plot = "plot_name", site = "plot_name",
  occurrence_id = "occurrenceID", occurrenceid = "occurrenceID",
  family_name = "scrubbed_family", family = "scrubbed_family",
  genus_name = "scrubbed_genus",  genus = "scrubbed_genus",
  observer = "dataowner", collector = "dataowner", recorded_by = "dataowner",
  elevation_m = "elevation_min", elevation = "elevation_min",
  dataset_name = "dataset", dataset = "dataset",
  locality_description = "verbatimLocality"
)

# ── Vectorized auto-suggest ───────────────────────────────────────────────────

suggest_mapping <- function(col_names) {
  can <- canonicalize(col_names)

  dwc_direct <- DWC_LOOKUP[can]
  dwc_alias  <- DWC_ALIASES[can]
  dwc        <- ifelse(!is.na(dwc_direct), dwc_direct,
                  ifelse(!is.na(dwc_alias), dwc_alias, NA_character_))

  bien_direct <- BIEN_LOOKUP[can]
  bien_alias  <- BIEN_ALIASES[can]
  bien        <- ifelse(!is.na(bien_direct), bien_direct,
                   ifelse(!is.na(bien_alias), bien_alias, NA_character_))

  data.frame(
    source_col  = col_names,
    dwc_term    = unname(dwc),
    bien_field  = unname(bien),
    stringsAsFactors = FALSE
  )
}

# ── Build staging table (vectorized) ─────────────────────────────────────────

build_staging <- function(merged_df, mapping) {
  # Drop rows with no bien_field mapping
  m <- mapping[!is.na(mapping$bien_field) & nzchar(trimws(mapping$bien_field)), , drop=FALSE]

  staged <- data.frame(matrix(NA_character_, nrow=nrow(merged_df), ncol=length(BIEN_STAGING_FIELDS)),
                       stringsAsFactors=FALSE)
  names(staged) <- BIEN_STAGING_FIELDS

  for (i in seq_len(nrow(m))) {
    src <- m$source_col[i]
    fld <- m$bien_field[i]
    if (src %in% names(merged_df) && fld %in% BIEN_STAGING_FIELDS) {
      staged[[fld]] <- as.character(merged_df[[src]])
    }
  }

  if (all(is.na(staged$basisOfRecord) | staged$basisOfRecord == "")) {
    staged$basisOfRecord <- "HumanObservation"
  }
  staged
}

# ── Build DWC table (vectorized) ─────────────────────────────────────────────

build_dwc <- function(merged_df, mapping) {
  m <- mapping[!is.na(mapping$dwc_term) & nzchar(trimws(mapping$dwc_term)), , drop=FALSE]
  if (nrow(m) == 0) return(data.frame(stringsAsFactors=FALSE))

  out <- lapply(seq_len(nrow(m)), function(i) {
    src <- m$source_col[i]
    if (src %in% names(merged_df)) as.character(merged_df[[src]]) else rep(NA_character_, nrow(merged_df))
  })
  names(out) <- m$dwc_term
  as.data.frame(out, stringsAsFactors=FALSE)
}

# ── Vectorized QC checks ──────────────────────────────────────────────────────

run_qc <- function(staged) {
  rows <- list()

  check_field <- function(label, field, check_fn, sev_fail) {
    if (!field %in% names(staged)) return(NULL)
    vals <- as.character(staged[[field]])
    pass <- check_fn(vals)
    n_pass <- sum(pass, na.rm=TRUE)
    n_fail <- sum(!pass, na.rm=TRUE)
    ex_fail <- vals[which(!pass)[1]]
    data.frame(field=field, check=label,
               n_records=nrow(staged), n_pass=n_pass, n_fail=n_fail,
               severity=if(n_fail==0) "PASS" else sev_fail,
               example_fail=if(is.na(ex_fail)) NA_character_ else ex_fail,
               stringsAsFactors=FALSE)
  }

  # Date parseable
  if ("date_collected" %in% names(staged)) {
    raw <- as.character(staged$date_collected)
    parsed <- suppressWarnings(as.Date(raw))
    n_pass <- sum(!is.na(parsed))
    n_fail <- sum(is.na(parsed) & !is.na(raw) & trimws(raw) != "")
    ex <- raw[which(is.na(parsed) & !is.na(raw) & trimws(raw) != "")][1]
    rows[["date"]] <- data.frame(
      field="date_collected", check="Date parseable (ISO 8601)",
      n_records=nrow(staged), n_pass=n_pass, n_fail=n_fail,
      severity=if(n_fail==0) "PASS" else "WARN",
      example_fail=if(is.na(ex)) NA_character_ else ex,
      stringsAsFactors=FALSE)
  }

  # Latitude
  rows[["lat"]] <- check_field("Latitude in range [-90, 90]", "latitude",
    function(v) { n <- suppressWarnings(as.numeric(v)); !is.na(n) & n >= -90 & n <= 90 }, "BLOCK")

  # Longitude
  rows[["lon"]] <- check_field("Longitude in range [-180, 180]", "longitude",
    function(v) { n <- suppressWarnings(as.numeric(v)); !is.na(n) & n >= -180 & n <= 180 }, "BLOCK")

  # Species name not blank
  rows[["spp"]] <- check_field("Species name not blank", "scrubbed_species_binomial",
    function(v) !is.na(v) & trimws(v) != "", "WARN")

  # Required fields all present (not 100% blank)
  for (fld in c("latitude","longitude","date_collected","country","scrubbed_species_binomial")) {
    if (fld %in% names(staged)) {
      vals <- as.character(staged[[fld]])
      n_miss <- sum(is.na(vals) | trimws(vals) == "")
      sev    <- if (n_miss == nrow(staged)) "BLOCK" else if (n_miss > 0) "WARN" else "PASS"
      rows[[paste0("req_",fld)]] <- data.frame(
        field=fld, check="Required field populated",
        n_records=nrow(staged), n_pass=nrow(staged)-n_miss, n_fail=n_miss,
        severity=sev, example_fail=NA_character_, stringsAsFactors=FALSE)
    }
  }

  qc <- do.call(rbind, Filter(Negate(is.null), rows))
  if (!is.null(qc)) row.names(qc) <- NULL
  qc
}

# ── UI ────────────────────────────────────────────────────────────────────────

ui <- navbarPage(
  title = "BIEN Data Loader",
  id    = "tabs",
  header = tagList(
    tags$head(
      tags$style(HTML("
        body { font-family: 'Segoe UI', Arial, sans-serif; }

        /* Cold-start overlay */
        #cold-overlay {
          position:fixed; inset:0; z-index:9999;
          background:rgba(255,255,255,0.97);
          display:flex; flex-direction:column;
          align-items:center; justify-content:center;
        }
        @keyframes spin { 100% { transform:rotate(360deg); } }
        .cold-spin {
          width:52px; height:52px; border-radius:50%;
          border:6px solid #d0e4f7; border-top-color:#2f6fab;
          animation:spin 0.8s linear infinite; margin-bottom:18px;
        }
        #cold-overlay p  { font-size:1.1em; color:#2f6fab; font-weight:600; margin:0 0 6px; }
        #cold-overlay small { color:#777; font-size:0.85em; }

        /* Info cards */
        .bl-card {
          background:#f8fbff; border-left:4px solid #2f6fab;
          padding:12px 16px; margin:10px 0; border-radius:4px;
        }
        .bl-card-warn  { border-left-color:#e6a817; background:#fffbf0; }
        .bl-card-block { border-left-color:#c0392b; background:#fff5f5; }
        .bl-card-pass  { border-left-color:#27ae60; background:#f0fff4; }

        /* Step badges */
        .step-badge {
          display:inline-block; width:28px; height:28px; border-radius:50%;
          background:#2f6fab; color:#fff; font-weight:700;
          text-align:center; line-height:28px; margin-right:8px; font-size:0.9em;
        }
        .step-done { background:#27ae60; }

        /* QC severity colours in tables */
        .qc-PASS  { color:#27ae60; font-weight:700; }
        .qc-WARN  { color:#e6a817; font-weight:700; }
        .qc-BLOCK { color:#c0392b; font-weight:700; }

        /* Spacing */
        .shiny-input-container { margin-bottom:8px; }
        .navbar { background-color:#2f6fab !important; }
        .navbar-brand, .navbar-nav > li > a { color:#fff !important; }
        .navbar-nav > .active > a { background-color:#1a4980 !important; }
      ")),
      tags$script(HTML("
        $(document).on('shiny:connected', function() {
          var ov = document.getElementById('cold-overlay');
          if (ov) ov.style.display = 'none';
        });
      "))
    ),
    tags$div(id="cold-overlay",
      tags$div(class="cold-spin"),
      tags$p("BIEN Data Loader is starting up\u2026"),
      tags$small("First load may take a moment on free hosting.")
    )
  ),

  # ── Tab 1: Upload & Merge ─────────────────────────────────────────────────
  tabPanel("1 \u2022 Upload & Merge",
    fluidRow(
      column(4,
        tags$div(class="bl-card",
          tags$span(class="step-badge", "1"),
          tags$strong("Load Data"),
          tags$hr(style="margin:8px 0"),
          checkboxInput("use_demo", "Use built-in demo data (12 obs + 6 plots)", value=TRUE),
          conditionalPanel("!input.use_demo",
            fileInput("files", "Upload CSV files", multiple=TRUE, accept=".csv",
                      placeholder="Select one or more .csv files")
          ),
          tags$hr(style="margin:8px 0"),
          uiOutput("primary_file_ui"),
          uiOutput("join_key_ui"),
          tags$br(),
          actionButton("btn_prepare", "Prepare Dataset \u25b6", class="btn-primary btn-lg",
                       style="width:100%")
        ),
        uiOutput("step1_status")
      ),
      column(8,
        uiOutput("preview_header"),
        DT::dataTableOutput("preview_table")
      )
    )
  ),

  # ── Tab 2: Map Fields ─────────────────────────────────────────────────────
  tabPanel("2 \u2022 Map Fields",
    uiOutput("tab2_gating"),
    fluidRow(
      column(12,
        tags$div(class="bl-card",
          tags$span(class="step-badge", "2"),
          tags$strong("Review and adjust field mappings"),
          tags$span(style="color:#555; font-size:0.9em; margin-left:8px;",
            "Edit any cell in the table below, then click Apply."),
          tags$br(), tags$br(),
          actionButton("btn_apply_mapping", "Apply Mapping \u25b6", class="btn-primary"),
          tags$span(style="margin-left:12px;"),
          uiOutput("step2_status_inline")
        ),
        DT::dataTableOutput("mapping_table")
      )
    )
  ),

  # ── Tab 3: Stage & Validate ───────────────────────────────────────────────
  tabPanel("3 \u2022 Stage & Validate",
    uiOutput("tab3_gating"),
    fluidRow(
      column(4,
        tags$div(class="bl-card",
          tags$span(class="step-badge", "3"),
          tags$strong("QC Summary")
        ),
        uiOutput("qc_summary_ui"),
        tags$br(),
        tags$div(class="bl-card bl-card-warn",
          tags$strong("Optional: BIEN Web Services"),
          tags$p(style="font-size:0.85em; margin:4px 0 8px;",
            "TNRS checks taxonomy; GNRS validates geography. Both require network access and may take 5\u201315s."),
          actionButton("btn_tnrs", "Run TNRS (max 20 names)", class="btn-warning btn-sm",
                       style="width:100%; margin-bottom:6px;"),
          uiOutput("tnrs_status_ui"),
          tags$br(),
          actionButton("btn_gnrs", "Run GNRS (geography check)", class="btn-warning btn-sm",
                       style="width:100%;"),
          uiOutput("gnrs_status_ui")
        )
      ),
      column(8,
        tabsetPanel(id="stage_tabs",
          tabPanel("Staging Table",  DT::dataTableOutput("staged_table")),
          tabPanel("DWC Table",      DT::dataTableOutput("dwc_table")),
          tabPanel("QC Details",     DT::dataTableOutput("qc_table")),
          tabPanel("TNRS Results",   DT::dataTableOutput("tnrs_table")),
          tabPanel("GNRS Results",   DT::dataTableOutput("gnrs_table"))
        )
      )
    )
  ),

  # ── Tab 4: Export ─────────────────────────────────────────────────────────
  tabPanel("4 \u2022 Export",
    uiOutput("tab4_gating"),
    fluidRow(
      column(4,
        tags$div(class="bl-card",
          tags$span(class="step-badge", "4"),
          tags$strong("Download Outputs"),
          tags$hr(style="margin:8px 0"),
          downloadButton("dl_staged",  "BIEN Staging Table (.csv)",
                         style="width:100%; margin-bottom:8px;"),
          downloadButton("dl_dwc",     "Darwin Core Table (.csv)",
                         style="width:100%; margin-bottom:8px;"),
          downloadButton("dl_mapping", "Field Mapping (.csv)",
                         style="width:100%; margin-bottom:8px;"),
          downloadButton("dl_qc",      "QC Report (.csv)",
                         style="width:100%; margin-bottom:8px;"),
          downloadButton("dl_packet",  "Full Packet (.zip)",
                         style="width:100%;")
        )
      ),
      column(8,
        tags$div(class="bl-card",
          tags$strong("Export Summary"),
          tags$hr(style="margin:8px 0"),
          verbatimTextOutput("export_summary")
        )
      )
    )
  )
)

# ── Server ────────────────────────────────────────────────────────────────────

server <- function(input, output, session) {

  rv <- reactiveValues(
    raw_files    = NULL,
    merged       = NULL,
    mapping_draft = NULL,
    mapping      = NULL,
    staged       = NULL,
    dwc          = NULL,
    qc           = NULL,
    tnrs_result  = NULL,
    gnrs_result  = NULL
  )

  # ── Resolve demo data path reliably regardless of working directory ──────────
  demo_data_path <- function(filename) {
    # 1. Relative to app directory (standard runApp)
    rel <- file.path("demo_data", filename)
    if (file.exists(rel)) return(rel)
    # 2. Relative to the directory of this script (shinyapps.io)
    app_dir <- tryCatch(dirname(sys.frame(1)$ofile), error=function(e) NULL)
    if (!is.null(app_dir)) {
      p <- file.path(app_dir, "demo_data", filename)
      if (file.exists(p)) return(p)
    }
    NULL
  }

  # ── Load raw files whenever source changes (for column detection only) ──────
  observe({
    # Clear all downstream state when source switches
    rv$merged <- NULL; rv$mapping_draft <- NULL; rv$mapping <- NULL
    rv$staged <- NULL; rv$dwc <- NULL; rv$qc <- NULL
    rv$tnrs_result <- NULL; rv$gnrs_result <- NULL

    if (isTRUE(input$use_demo)) {
      obs_path  <- demo_data_path("observations.csv")
      meta_path <- demo_data_path("plot_metadata.csv")
      if (is.null(obs_path) || is.null(meta_path)) {
        showNotification("Demo data files not found. Check that demo_data/ folder is present.",
                         type="error", duration=12)
        return()
      }
      rv$raw_files <- list(
        "observations.csv"  = read.csv(obs_path,  stringsAsFactors=FALSE, check.names=FALSE),
        "plot_metadata.csv" = read.csv(meta_path, stringsAsFactors=FALSE, check.names=FALSE)
      )
    } else if (!is.null(input$files)) {
      # Basic file size guard: warn if any file > 50 MB
      large <- input$files$name[input$files$size > 50 * 1024 * 1024]
      if (length(large) > 0) {
        showNotification(paste0("Large file(s) detected (> 50 MB): ",
          paste(large, collapse=", "), ". Loading may be slow."),
          type="warning", duration=10)
      }
      rv$raw_files <- setNames(
        lapply(input$files$datapath,
               function(p) read.csv(p, stringsAsFactors=FALSE, check.names=FALSE)),
        input$files$name
      )
    }
  })

  # ── Primary file selector ─────────────────────────────────────────────────
  output$primary_file_ui <- renderUI({
    req(rv$raw_files)
    fnames <- names(rv$raw_files)
    selectInput("primary_file", "Primary observation file", choices=fnames, selected=fnames[[1]])
  })

  # ── Join key UI ───────────────────────────────────────────────────────────
  output$join_key_ui <- renderUI({
    req(rv$raw_files)
    req(input$primary_file)
    primary <- input$primary_file
    others  <- setdiff(names(rv$raw_files), primary)
    if (length(others) == 0) return(tags$p(style="color:#555; font-size:0.85em;",
      "Single file — no join needed."))

    tagList(lapply(others, function(f) {
      prim_cols <- names(rv$raw_files[[primary]])
      meta_cols <- names(rv$raw_files[[f]])
      # Auto-guess matching keys by canonical name intersection
      can_prim <- setNames(prim_cols, canonicalize(prim_cols))
      can_meta <- setNames(meta_cols, canonicalize(meta_cols))
      shared   <- intersect(names(can_prim), names(can_meta))
      pk_guess <- if (length(shared) > 0) can_prim[[shared[1]]] else prim_cols[[1]]
      fk_guess <- if (length(shared) > 0) can_meta[[shared[1]]] else meta_cols[[1]]

      tags$div(
        tags$p(style="font-weight:600; margin:8px 0 4px;",
               paste0("Join \u2192 ", f)),
        fluidRow(
          column(6, selectInput(paste0("pk_", make.names(f)),
                                paste("Key in", primary),
                                choices=prim_cols, selected=pk_guess)),
          column(6, selectInput(paste0("fk_", make.names(f)),
                                paste("Key in", f),
                                choices=meta_cols, selected=fk_guess))
        )
      )
    }))
  })

  # ── Step 1: Prepare (merge) ───────────────────────────────────────────────
  observeEvent(input$btn_prepare, {
    req(rv$raw_files)
    primary <- if (!is.null(input$primary_file) && nzchar(input$primary_file)) {
      input$primary_file
    } else names(rv$raw_files)[[1]]

    merged <- rv$raw_files[[primary]]
    others <- setdiff(names(rv$raw_files), primary)

    for (f in others) {
      pk  <- input[[paste0("pk_", make.names(f))]]
      fk  <- input[[paste0("fk_", make.names(f))]]
      if (is.null(pk) || !nzchar(pk)) pk <- names(merged)[[1]]
      if (is.null(fk) || !nzchar(fk)) fk <- names(rv$raw_files[[f]])[[1]]

      meta <- rv$raw_files[[f]]
      meta <- meta[!duplicated(meta[[fk]]), , drop=FALSE]
      merged <- merge(merged, meta, by.x=pk, by.y=fk, all.x=TRUE,
                      suffixes=c("", paste0(".", make.names(f))))
    }

    rv$merged        <- merged
    rv$mapping_draft <- suggest_mapping(names(merged))
    rv$mapping       <- NULL
    rv$staged        <- NULL
    rv$dwc           <- NULL
    rv$qc            <- NULL
    rv$tnrs_result   <- NULL
    rv$gnrs_result   <- NULL
  })

  output$step1_status <- renderUI({
    if (is.null(rv$merged)) return(NULL)
    tags$div(class="bl-card bl-card-pass", style="margin-top:10px;",
      tags$strong("Dataset ready"),
      tags$br(),
      paste0(nrow(rv$merged), " rows \u00d7 ", ncol(rv$merged), " columns"),
      tags$br(),
      paste0("Files: ", paste(names(rv$raw_files), collapse=", "))
    )
  })

  output$preview_header <- renderUI({
    if (is.null(rv$merged)) return(tags$div(class="bl-card",
      tags$em("Click \u2018Prepare Dataset\u2019 to load and merge your files.")))
    tags$div(class="bl-card",
      tags$strong("Merged data preview (first 8 rows)"))
  })

  output$preview_table <- DT::renderDataTable({
    req(rv$merged)
    DT::datatable(utils::head(rv$merged, 8), rownames=FALSE,
      options=list(pageLength=8, scrollX=TRUE, dom='t'))
  }, server=FALSE)

  # ── Tab 2 gating ─────────────────────────────────────────────────────────
  output$tab2_gating <- renderUI({
    if (is.null(rv$merged)) {
      tags$div(class="bl-card bl-card-warn",
        tags$strong("Complete Step 1 first: "),
        "Go to \u20181 \u2022 Upload & Merge\u2019 and click Prepare Dataset.")
    }
  })

  # ── Step 2: Mapping table (editable DT) ───────────────────────────────────
  output$mapping_table <- DT::renderDataTable({
    req(rv$mapping_draft)
    DT::datatable(
      rv$mapping_draft,
      editable = list(target="cell", disable=list(columns=0L)),
      rownames = FALSE,
      colnames = c("Source Column", "Suggested DWC Term", "Suggested BIEN Field"),
      options  = list(pageLength=30, scrollX=TRUE, dom='frtip'),
      caption  = "Edit 'Suggested DWC Term' or 'Suggested BIEN Field' cells directly (Source Column is locked), then click Apply Mapping."
    )
  }, server=FALSE)

  observeEvent(input$mapping_table_cell_edit, {
    info <- input$mapping_table_cell_edit
    df   <- rv$mapping_draft
    # DT 0-indexed col: +1 for R 1-indexed, but rownames=FALSE means col 0 = source_col (col 1 in df)
    col_idx <- info$col + 1L
    if (col_idx >= 1L && col_idx <= ncol(df)) {
      df[info$row, col_idx] <- info$value
      rv$mapping_draft <- df
    }
  })

  observeEvent(input$btn_apply_mapping, {
    req(rv$mapping_draft)
    req(rv$merged)
    rv$mapping <- rv$mapping_draft
    rv$staged  <- build_staging(rv$merged, rv$mapping)
    rv$dwc     <- build_dwc(rv$merged, rv$mapping)
    rv$qc      <- run_qc(rv$staged)
  })

  output$step2_status_inline <- renderUI({
    if (is.null(rv$mapping)) return(NULL)
    n_dwc  <- sum(!is.na(rv$mapping$dwc_term) & nzchar(trimws(rv$mapping$dwc_term)))
    n_bien <- sum(!is.na(rv$mapping$bien_field) & nzchar(trimws(rv$mapping$bien_field)))
    tags$span(style="color:#27ae60; font-weight:600;",
      paste0("Mapping applied \u2014 ", n_dwc, " DWC terms, ", n_bien, " BIEN fields mapped"))
  })

  # ── Tab 3 gating ─────────────────────────────────────────────────────────
  output$tab3_gating <- renderUI({
    if (is.null(rv$mapping)) {
      tags$div(class="bl-card bl-card-warn",
        tags$strong("Complete Step 2 first: "),
        "Go to \u20182 \u2022 Map Fields\u2019 and click Apply Mapping.")
    }
  })

  # ── QC summary ───────────────────────────────────────────────────────────
  output$qc_summary_ui <- renderUI({
    if (is.null(rv$qc)) return(tags$div(class="bl-card",
      tags$em("Apply mapping to see QC results.")))

    qc <- rv$qc
    n_pass  <- sum(qc$severity == "PASS",  na.rm=TRUE)
    n_warn  <- sum(qc$severity == "WARN",  na.rm=TRUE)
    n_block <- sum(qc$severity == "BLOCK", na.rm=TRUE)

    card_cls <- if (n_block > 0) "bl-card bl-card-block" else
                if (n_warn  > 0) "bl-card bl-card-warn"  else "bl-card bl-card-pass"

    verdict <- if (n_block > 0) "Export blocked \u2014 fix BLOCK issues" else
               if (n_warn  > 0) "Ready with warnings" else "All checks passed"

    tags$div(class=card_cls,
      tags$strong(verdict),
      tags$ul(style="margin:6px 0 0; padding-left:16px;",
        tags$li(style="color:#27ae60;", paste0("PASS: ", n_pass)),
        tags$li(style="color:#e6a817;", paste0("WARN: ", n_warn)),
        tags$li(style="color:#c0392b;", paste0("BLOCK: ", n_block))
      )
    )
  })

  # ── Stage/DWC/QC tables ───────────────────────────────────────────────────
  output$staged_table <- DT::renderDataTable({
    req(rv$staged)
    DT::datatable(rv$staged, rownames=FALSE,
      options=list(pageLength=10, scrollX=TRUE))
  }, server=FALSE)

  output$dwc_table <- DT::renderDataTable({
    req(rv$dwc)
    DT::datatable(rv$dwc, rownames=FALSE,
      options=list(pageLength=10, scrollX=TRUE))
  }, server=FALSE)

  output$qc_table <- DT::renderDataTable({
    req(rv$qc)
    DT::datatable(rv$qc, rownames=FALSE,
      options=list(pageLength=20, scrollX=TRUE),
      callback=DT::JS("
        table.on('draw', function() {
          table.rows().every(function() {
            var data = this.data();
            var sev  = data[data.length-2];
            if (sev === 'BLOCK') $(this.node()).css('color','#c0392b');
            else if (sev === 'WARN') $(this.node()).css('color','#b07d00');
          });
        });
      ")
    )
  }, server=FALSE)

  # ── TNRS ─────────────────────────────────────────────────────────────────
  observeEvent(input$btn_tnrs, {
    req(rv$staged)
    names_vec <- unique(trimws(as.character(rv$staged$scrubbed_species_binomial)))
    names_vec <- names_vec[!is.na(names_vec) & names_vec != ""]
    n_total <- length(names_vec)
  if (n_total > 20) {
    names_vec <- names_vec[seq_len(20)]
    showNotification(paste0("TNRS capped to first 20 of ", n_total,
      " unique names. Download mapping CSV to see which names were submitted."),
      type="warning", duration=8)
  }

    withProgress(message="Submitting to TNRS\u2026", value=0.2, {
      result <- tryCatch({
        resp <- httr::POST(
          "https://tnrs.biendata.org/tnrs_api_r.php",
          body   = list(names=paste(names_vec, collapse="\n")),
          encode = "form",
          httr::timeout(20)
        )
        setProgress(0.8)
        if (httr::status_code(resp) == 200) {
          txt <- httr::content(resp, "text", encoding="UTF-8")
          df  <- tryCatch(read.csv(text=txt, stringsAsFactors=FALSE), error=function(e) NULL)
          if (!is.null(df) && nrow(df) > 0) df else NULL
        } else NULL
      }, error=function(e) NULL)

      setProgress(1.0)
      rv$tnrs_result <- if (is.null(result)) {
        data.frame(note="TNRS request failed or timed out. Check network and try again.",
                   stringsAsFactors=FALSE)
      } else result
    })
  })

  output$tnrs_status_ui <- renderUI({
    if (is.null(rv$tnrs_result)) return(NULL)
    if ("note" %in% names(rv$tnrs_result)) {
      tags$p(style="color:#c0392b; font-size:0.85em; margin-top:4px;",
             rv$tnrs_result$note[1])
    } else {
      tags$p(style="color:#27ae60; font-size:0.85em; margin-top:4px;",
             paste0("TNRS complete: ", nrow(rv$tnrs_result), " name(s) returned"))
    }
  })

  output$tnrs_table <- DT::renderDataTable({
    req(rv$tnrs_result)
    DT::datatable(rv$tnrs_result, rownames=FALSE,
      options=list(pageLength=20, scrollX=TRUE))
  }, server=FALSE)

  # ── GNRS ─────────────────────────────────────────────────────────────────
  observeEvent(input$btn_gnrs, {
    req(rv$staged)
    geo_cols <- intersect(c("country","state_province","county"), names(rv$staged))
    if (length(geo_cols) == 0) {
      rv$gnrs_result <- data.frame(note="No geography columns (country/state_province/county) found in staging table.",
                                   stringsAsFactors=FALSE)
      return()
    }

    geo_tbl <- unique(rv$staged[, geo_cols, drop=FALSE])
    geo_tbl <- geo_tbl[rowSums(!is.na(geo_tbl) & geo_tbl != "") > 0, , drop=FALSE]
    # GNRS expects DWC column names
    names(geo_tbl) <- gsub("state_province", "stateProvince", names(geo_tbl))

    withProgress(message="Submitting to GNRS\u2026", value=0.2, {
      result <- tryCatch({
        body_json <- jsonlite::toJSON(geo_tbl, auto_unbox=FALSE)
        resp <- httr::POST(
          "https://gnrs.biendata.org/api/",
          body = body_json,
          httr::content_type("application/json"),
          httr::timeout(20)
        )
        setProgress(0.8)
        if (httr::status_code(resp) == 200) {
          txt <- httr::content(resp, "text", encoding="UTF-8")
          df  <- tryCatch(jsonlite::fromJSON(txt, flatten=TRUE), error=function(e) NULL)
          if (is.data.frame(df) && nrow(df) > 0) df else NULL
        } else NULL
      }, error=function(e) NULL)

      setProgress(1.0)
      rv$gnrs_result <- if (is.null(result)) {
        data.frame(note="GNRS request failed or timed out.",
                   stringsAsFactors=FALSE)
      } else result
    })
  })

  output$gnrs_status_ui <- renderUI({
    if (is.null(rv$gnrs_result)) return(NULL)
    if ("note" %in% names(rv$gnrs_result)) {
      tags$p(style="color:#c0392b; font-size:0.85em; margin-top:4px;",
             rv$gnrs_result$note[1])
    } else {
      tags$p(style="color:#27ae60; font-size:0.85em; margin-top:4px;",
             paste0("GNRS complete: ", nrow(rv$gnrs_result), " record(s) checked"))
    }
  })

  output$gnrs_table <- DT::renderDataTable({
    req(rv$gnrs_result)
    DT::datatable(rv$gnrs_result, rownames=FALSE,
      options=list(pageLength=20, scrollX=TRUE))
  }, server=FALSE)

  # ── Tab 4 gating ─────────────────────────────────────────────────────────
  output$tab4_gating <- renderUI({
    if (is.null(rv$staged)) {
      tags$div(class="bl-card bl-card-warn",
        tags$strong("Not ready yet: "),
        "Go to \u20182 \u2022 Map Fields\u2019 and click Apply Mapping to build the staging table first.")
    }
  })

  # ── Export summary ────────────────────────────────────────────────────────
  output$export_summary <- renderText({
    req(rv$staged)
    qc <- rv$qc
    n_block <- if (!is.null(qc)) sum(qc$severity=="BLOCK", na.rm=TRUE) else NA
    n_warn  <- if (!is.null(qc)) sum(qc$severity=="WARN",  na.rm=TRUE) else NA
    n_dwc   <- if (!is.null(rv$mapping))
      sum(!is.na(rv$mapping$dwc_term) & nzchar(trimws(rv$mapping$dwc_term))) else 0
    n_bien  <- if (!is.null(rv$mapping))
      sum(!is.na(rv$mapping$bien_field) & nzchar(trimws(rv$mapping$bien_field))) else 0

    paste(
      paste0("Records in staging table:  ", nrow(rv$staged)),
      paste0("BIEN fields populated:     ", n_bien, " / ", length(BIEN_STAGING_FIELDS)),
      paste0("DWC terms mapped:          ", n_dwc),
      paste0("QC BLOCK issues:           ", n_block),
      paste0("QC WARN issues:            ", n_warn),
      paste0("TNRS run:                  ", if (!is.null(rv$tnrs_result)) "yes" else "no"),
      paste0("GNRS run:                  ", if (!is.null(rv$gnrs_result)) "yes" else "no"),
      "",
      "NOTE: This staging table reflects the field mapping and QC",
      "applied in this session. Authoritative taxonomic reconciliation",
      "requires downstream expert and service review before BIEN DB append.",
      sep="\n"
    )
  })

  # ── Download handlers ─────────────────────────────────────────────────────
  # CSV formula-injection sanitizer (OWASP: prevent Excel formula injection)
  sanitize_csv_col <- function(x) {
    s <- as.character(x)
    ifelse(!is.na(s) & grepl("^[=+\\-@]", s), paste0("'", s), s)
  }
  safe_write_csv <- function(df, file) {
    df[] <- lapply(df, sanitize_csv_col)
    utils::write.csv(df, file, row.names=FALSE)
  }

  output$dl_staged <- downloadHandler(
    filename = function() paste0("bien_staging_", Sys.Date(), ".csv"),
    content  = function(file) { if (is.null(rv$staged))  return(); safe_write_csv(rv$staged,  file) }
  )

  output$dl_dwc <- downloadHandler(
    filename = function() paste0("dwc_table_", Sys.Date(), ".csv"),
    content  = function(file) { if (is.null(rv$dwc))     return(); safe_write_csv(rv$dwc,     file) }
  )

  output$dl_mapping <- downloadHandler(
    filename = function() paste0("field_mapping_", Sys.Date(), ".csv"),
    content  = function(file) { if (is.null(rv$mapping)) return(); safe_write_csv(rv$mapping, file) }
  )

  output$dl_qc <- downloadHandler(
    filename = function() paste0("qc_report_", Sys.Date(), ".csv"),
    content  = function(file) { if (is.null(rv$qc))      return(); safe_write_csv(rv$qc,      file) }
  )

  output$dl_packet <- downloadHandler(
    filename = function() paste0("bien_data_packet_", Sys.Date(), ".zip"),
    content  = function(file) {
      if (is.null(rv$staged)) return()
      # Use tempfile() for guaranteed-unique path; clean up on exit
      tmp <- tempfile(pattern="bien_packet_")
      dir.create(tmp, recursive=TRUE, showWarnings=FALSE)
      on.exit(unlink(tmp, recursive=TRUE), add=TRUE)

      out_files <- character(0)
      write_part <- function(df, fname) {
        p <- file.path(tmp, fname)
        safe_write_csv(df, p)
        out_files <<- c(out_files, p)
      }
      if (!is.null(rv$staged))       write_part(rv$staged,       "bien_staging.csv")
      if (!is.null(rv$dwc))          write_part(rv$dwc,          "dwc_table.csv")
      if (!is.null(rv$mapping))      write_part(rv$mapping,      "field_mapping.csv")
      if (!is.null(rv$qc))           write_part(rv$qc,           "qc_report.csv")
      if (!is.null(rv$tnrs_result))  write_part(rv$tnrs_result,  "tnrs_results.csv")
      if (!is.null(rv$gnrs_result))  write_part(rv$gnrs_result,  "gnrs_results.csv")

      # zip with full paths + junk-path flag (-j) to avoid setwd() race condition
      utils::zip(zipfile=file, files=out_files, flags="-j")
    }
  )
}

shinyApp(ui, server)
