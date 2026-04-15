for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) {
  source(f, local = TRUE)
}

library(shiny)

reconcile_taxonomy_local <- function(scientific_names) {
  if (length(scientific_names) == 0) {
    return(data.frame(
      scientificName = character(0),
      canonicalName = character(0),
      status = character(0),
      note = character(0),
      stringsAsFactors = FALSE
    ))
  }

  x <- trimws(as.character(scientific_names))
  x[is.na(x)] <- ""

  # Simple local parser to flag likely unresolved names before external backbone checks.
  status <- ifelse(
    x == "",
    "UNRESOLVED",
    ifelse(grepl("\\b(sp|spp|cf|aff|indet)\\.?$", tolower(x)), "REVIEW", "CANDIDATE")
  )

  canonical <- gsub("\\s+", " ", x)
  canonical <- sub("\\s+(subsp\\.|var\\.|forma)\\s+.*$", "", canonical, ignore.case = TRUE)

  note <- ifelse(
    status == "REVIEW",
    "Contains uncertain qualifier (sp./cf./aff./indet)",
    ifelse(status == "UNRESOLVED", "Blank scientificName", "Candidate for external taxonomy backbone")
  )

  data.frame(
    scientificName = x,
    canonicalName = canonical,
    status = status,
    note = note,
    stringsAsFactors = FALSE
  )
}

ui <- fluidPage(
  titlePanel("Historical Observation Data to BIEN"),
  tags$div(
    style = "margin: 10px 0; padding: 10px; background: #eef6ff; border-left: 4px solid #2f6fab;",
    strong("Goal: "),
    "Upload flat files, link tables, map to Darwin Core, run validation, and export BIEN draft handoff tables."
  ),
  sidebarLayout(
    sidebarPanel(
      h4("Data Source"),
      checkboxInput("use_tutorial_data", "Use built-in tutorial fake data", value = FALSE),
      fileInput("input_csv", "Upload CSV File(s)", accept = ".csv", multiple = TRUE),
      tags$hr(),
      h4("Step Actions"),
      actionButton("prepare_btn", "Step 2: Prepare Linked Table", class = "btn-primary"),
      actionButton("suggest_btn", "Step 3: Suggest Mapping", class = "btn-primary"),
      fileInput("mapping_csv", "Optional Mapping Override CSV", accept = ".csv"),
      actionButton("build_btn", "Step 5: Build BIEN Draft Tables", class = "btn-success"),
      tags$hr(),
      h4("Downloads"),
      downloadButton("download_combined", "Combined Source Table"),
      downloadButton("download_join_audit", "Join Audit Report"),
      downloadButton("download_mapping", "Active Mapping"),
      downloadButton("download_qc", "QC Report"),
      downloadButton("download_bien", "BIEN Loading Draft"),
      downloadButton("download_tnrs", "TNRS Handoff"),
      downloadButton("download_gnrs", "GNRS Handoff"),
      downloadButton("download_gvs", "GVS Handoff"),
      downloadButton("download_nsr", "NSR Handoff"),
      tags$hr(),
      tags$div(
        style = "padding: 10px; background: #fff8e1; border-left: 4px solid #c28b00; font-size: 0.92em;",
        strong("Important"),
        tags$p(
          style = "margin: 6px 0 0 0;",
          "Exports are draft handoff tables. Complete downstream TNRS, GNRS, GVS, and NSR review before BIEN submission."
        )
      )
    ),
    mainPanel(
      tabsetPanel(
        id = "workflow_tabs",
        tabPanel(
          "Step 1 Upload",
          h3("Step 1. Upload and Inspect Files"),
          uiOutput("merge_controls"),
          h4("Loaded File Summary"),
          tableOutput("upload_summary_table"),
          h4("Primary File Preview"),
          tableOutput("primary_preview")
        ),
        tabPanel(
          "Step 2 Link",
          h3("Step 2. Link Observations with Metadata"),
          p("Select a primary observation file and one or more metadata files (location, plot, traits)."),
          h4("Join Audit"),
          uiOutput("join_warning_box"),
          tableOutput("join_audit_table"),
          h4("Linked Table Preview"),
          tableOutput("combined_preview")
        ),
        tabPanel(
          "Step 3 Map",
          h3("Step 3. Darwin Core Mapping"),
          p("Auto-suggestions come from header synonym matching. You can upload a mapping override CSV with source_column,dwc_term."),
          h4("Suggested Mapping"),
          tableOutput("mapping_table"),
          h4("Active Mapping"),
          tableOutput("active_mapping_table")
        ),
        tabPanel(
          "Step 4 Taxonomy",
          h3("Step 4. Taxonomic Reconciliation Triage"),
          p("This step flags unresolved names locally. Use exported TNRS handoff for authoritative reconciliation."),
          h4("Taxonomy Summary"),
          tableOutput("taxonomy_summary"),
          h4("Names Requiring Review"),
          tableOutput("taxonomy_review")
        ),
        tabPanel(
          "Step 5 Validate",
          h3("Step 5. QC Validation"),
          h4("QC Dashboard"),
          tableOutput("qc_table"),
          h4("Build Summary"),
          verbatimTextOutput("summary_text")
        ),
        tabPanel(
          "Step 6 Export",
          h3("Step 6. Export BIEN Draft Tables"),
          p("Download the draft loading and handoff tables for external validation and BIEN review."),
          h4("BIEN Loading Preview"),
          tableOutput("bien_preview"),
          h4("Export Readiness"),
          verbatimTextOutput("export_readiness")
        ),
        tabPanel(
          "Help",
          h3("How to Use This App"),
          tags$ol(
            tags$li("Upload one or more observation and metadata CSV files or turn on tutorial mode."),
            tags$li("Choose primary and metadata join keys, then click 'Step 2: Prepare Linked Table'."),
            tags$li("Click 'Step 3: Suggest Mapping' and review required Darwin Core terms."),
            tags$li("Review taxonomy triage and unresolved names."),
            tags$li("Click 'Step 5: Build BIEN Draft Tables' and resolve any BLOCK QC issues."),
            tags$li("Export draft BIEN, TNRS, GNRS, GVS, and NSR handoff tables.")
          )
        )
      )
    )
  )
)

server <- function(input, output, session) {
  tutorial_files <- reactive({
    list(
      "tutorial_observations.csv" = read_historical_csv("inst/extdata/tutorial_observations.csv"),
      "sample_plot_metadata.csv" = read_historical_csv("inst/extdata/sample_plot_metadata.csv")
    )
  })

  available_files <- reactive({
    if (isTRUE(input$use_tutorial_data)) {
      return(tutorial_files())
    }
    req(input$input_csv)
    read_uploaded_csv_list(input$input_csv)
  })

  output$merge_controls <- renderUI({
    files <- names(available_files())
    req(length(files) > 0)

    primary_default <- files[1]
    metadata_choices <- setdiff(files, primary_default)

    tagList(
      selectInput("primary_file", "Primary observation file", choices = files, selected = primary_default),
      uiOutput("primary_key_ui"),
      selectizeInput("metadata_files", "Metadata file(s)", choices = metadata_choices, multiple = TRUE),
      uiOutput("metadata_keys_ui")
    )
  })

  output$primary_key_ui <- renderUI({
    req(input$primary_file)
    df <- available_files()[[input$primary_file]]
    selectInput("primary_key", "Primary join key", choices = names(df))
  })

  output$metadata_keys_ui <- renderUI({
    req(input$metadata_files)

    controls <- lapply(input$metadata_files, function(f) {
      df <- available_files()[[f]]
      selectInput(
        inputId = paste0("meta_key_", make.names(f)),
        label = paste0("Join key in metadata file: ", f),
        choices = names(df)
      )
    })

    do.call(tagList, controls)
  })

  output$upload_summary_table <- renderTable({
    files <- available_files()
    req(length(files) > 0)
    data.frame(
      file = names(files),
      rows = vapply(files, nrow, integer(1)),
      cols = vapply(files, ncol, integer(1)),
      stringsAsFactors = FALSE
    )
  }, striped = TRUE, bordered = TRUE)

  output$primary_preview <- renderTable({
    req(input$primary_file)
    utils::head(available_files()[[input$primary_file]], 10)
  }, striped = TRUE, bordered = TRUE)

  combined_state <- eventReactive(input$prepare_btn, {
    files <- available_files()
    req(length(files) > 0)
    req(input$primary_file)
    req(input$primary_key)

    metadata_files <- if (is.null(input$metadata_files)) character(0) else input$metadata_files
    metadata_keys <- setNames(vector("list", length(metadata_files)), metadata_files)

    for (f in metadata_files) {
      metadata_keys[[f]] <- input[[paste0("meta_key_", make.names(f))]]
    }

    merged <- merge_uploaded_streams(
      data_list = files,
      primary_file = input$primary_file,
      primary_key = input$primary_key,
      metadata_files = metadata_files,
      metadata_keys = metadata_keys
    )

    audit <- audit_join_quality(
      data_list = files,
      primary_file = input$primary_file,
      primary_key = input$primary_key,
      metadata_files = metadata_files,
      metadata_keys = metadata_keys
    )

    list(merged = merged, audit = audit)
  })

  combined_df <- reactive({
    req(combined_state())
    combined_state()$merged
  })

  join_audit <- reactive({
    req(combined_state())
    combined_state()$audit
  })

  suggested_mapping <- eventReactive(input$suggest_btn, {
    suggest_dwc_mapping(combined_df(), dictionary_path = "inst/dictionaries/header_synonyms.csv")
  })

  active_mapping <- reactive({
    req(suggested_mapping())

    if (!is.null(input$mapping_csv)) {
      m <- utils::read.csv(input$mapping_csv$datapath, stringsAsFactors = FALSE)
      needed <- c("source_column", "dwc_term")
      if (all(needed %in% names(m))) {
        return(m)
      }
    }

    data.frame(
      source_column = suggested_mapping()$source_column,
      dwc_term = suggested_mapping()$suggested_dwc_term,
      stringsAsFactors = FALSE
    )
  })

  build_state <- eventReactive(input$build_btn, {
    dwc <- apply_dwc_mapping(combined_df(), active_mapping())
    qc <- run_dwc_qc(dwc)
    list(dwc = dwc, qc = qc)
  })

  dwc_df <- reactive({
    req(build_state())
    build_state()$dwc
  })

  qc_df <- reactive({
    req(build_state())
    build_state()$qc
  })

  taxonomy_df <- reactive({
    if (!is.null(build_state())) {
      df <- dwc_df()
      if ("scientificName" %in% names(df)) {
        names_vec <- unique(df$scientificName)
      } else {
        names_vec <- character(0)
      }
    } else if (!is.null(combined_state()) && "scientificName" %in% names(combined_df())) {
      names_vec <- unique(combined_df()$scientificName)
    } else {
      names_vec <- character(0)
    }
    reconcile_taxonomy_local(names_vec)
  })

  bien_df <- reactive({
    req(build_state())
    validate(need(!qc_has_blockers(qc_df()), "QC blockers detected. Fix BLOCK issues before building BIEN outputs."))
    build_bien_loading_table(dwc_df())
  })

  handoff <- reactive({
    req(build_state())
    validate(need(!qc_has_blockers(qc_df()), "QC blockers detected. Fix BLOCK issues before exporting handoff tables."))
    build_bien_handoff_tables(dwc_df())
  })

  output$combined_preview <- renderTable({
    req(combined_df())
    utils::head(combined_df(), 12)
  }, striped = TRUE, bordered = TRUE)

  output$join_audit_table <- renderTable({
    req(join_audit())
    join_audit()
  }, striped = TRUE, bordered = TRUE)

  output$join_warning_box <- renderUI({
    req(join_audit())
    audit <- join_audit()

    if (nrow(audit) == 0 || !any(audit$duplicate_metadata_collapse)) {
      return(NULL)
    }

    tags$div(
      style = "margin: 8px 0 12px 0; padding: 12px; background: #fff3cd; border-left: 4px solid #b7791f;",
      strong("Duplicate metadata warning: "),
      "At least one metadata file has duplicate join keys. The merge uses first non-empty values per key. Review before export."
    )
  })

  output$mapping_table <- renderTable({
    req(suggested_mapping())
    suggested_mapping()
  }, striped = TRUE, bordered = TRUE)

  output$active_mapping_table <- renderTable({
    req(active_mapping())
    active_mapping()
  }, striped = TRUE, bordered = TRUE)

  output$taxonomy_summary <- renderTable({
    tx <- taxonomy_df()
    data.frame(
      metric = c("Total unique names", "Candidate", "Review", "Unresolved"),
      value = c(
        nrow(tx),
        sum(tx$status == "CANDIDATE"),
        sum(tx$status == "REVIEW"),
        sum(tx$status == "UNRESOLVED")
      ),
      stringsAsFactors = FALSE
    )
  }, striped = TRUE, bordered = TRUE)

  output$taxonomy_review <- renderTable({
    tx <- taxonomy_df()
    tx[tx$status %in% c("REVIEW", "UNRESOLVED"), , drop = FALSE]
  }, striped = TRUE, bordered = TRUE)

  output$qc_table <- renderTable({
    req(qc_df())
    qc_df()
  }, striped = TRUE, bordered = TRUE)

  output$summary_text <- renderText({
    req(build_state())
    req(active_mapping())

    req_terms <- required_dwc_terms()
    missing <- setdiff(req_terms, names(dwc_df()))

    metadata_count <- if (is.null(input$metadata_files)) 0 else length(input$metadata_files)
    join_blockers <- if (nrow(join_audit()) == 0) 0 else sum(join_audit()$severity == "BLOCK")
    join_warnings <- if (nrow(join_audit()) == 0) 0 else sum(join_audit()$severity == "WARN")
    qc_blocks <- qc_severity_count(qc_df(), "BLOCK")
    qc_warns <- qc_severity_count(qc_df(), "WARN")

    paste(
      paste0("Loaded files: ", length(available_files())),
      paste0("Data mode: ", if (isTRUE(input$use_tutorial_data)) "Tutorial fake data" else "Uploaded files"),
      paste0("Metadata files joined: ", metadata_count),
      paste0("Combined rows (primary records): ", nrow(combined_df())),
      paste0("Join audit blockers: ", join_blockers, " | warnings: ", join_warnings),
      paste0("Mapped Darwin Core columns: ", ncol(dwc_df())),
      if (length(missing) == 0) "Required Darwin Core terms present: yes" else paste0("Missing required terms: ", paste(missing, collapse = ", ")),
      paste0("QC blockers: ", qc_blocks, " | warnings: ", qc_warns),
      if (qc_blocks > 0) "BIEN export blocked until BLOCK issues are fixed." else "Draft handoff tables generated.",
      sep = "\n"
    )
  })

  output$bien_preview <- renderTable({
    req(bien_df())
    utils::head(bien_df(), 10)
  }, striped = TRUE, bordered = TRUE)

  output$export_readiness <- renderText({
    req(qc_df())
    if (qc_has_blockers(qc_df())) {
      "Export blocked: resolve BLOCK issues in Step 5 Validate before BIEN loading export."
    } else {
      "Export ready: download BIEN loading draft and TNRS/GNRS/GVS/NSR handoff files."
    }
  })

  output$download_combined <- downloadHandler(
    filename = function() "combined_observation_stream.csv",
    content = function(file) utils::write.csv(combined_df(), file, row.names = FALSE)
  )

  output$download_join_audit <- downloadHandler(
    filename = function() "join_audit_report.csv",
    content = function(file) utils::write.csv(join_audit(), file, row.names = FALSE)
  )

  output$download_mapping <- downloadHandler(
    filename = function() "active_mapping.csv",
    content = function(file) utils::write.csv(active_mapping(), file, row.names = FALSE)
  )

  output$download_qc <- downloadHandler(
    filename = function() "dwc_qc_report.csv",
    content = function(file) utils::write.csv(qc_df(), file, row.names = FALSE)
  )

  output$download_bien <- downloadHandler(
    filename = function() "bien_loading_table.csv",
    content = function(file) utils::write.csv(bien_df(), file, row.names = FALSE)
  )

  output$download_tnrs <- downloadHandler(
    filename = function() "tnrs_handoff.csv",
    content = function(file) utils::write.csv(handoff()$tnrs, file, row.names = FALSE)
  )

  output$download_gnrs <- downloadHandler(
    filename = function() "gnrs_handoff.csv",
    content = function(file) utils::write.csv(handoff()$gnrs, file, row.names = FALSE)
  )

  output$download_gvs <- downloadHandler(
    filename = function() "gvs_handoff.csv",
    content = function(file) utils::write.csv(handoff()$gvs, file, row.names = FALSE)
  )

  output$download_nsr <- downloadHandler(
    filename = function() "nsr_handoff.csv",
    content = function(file) utils::write.csv(handoff()$nsr, file, row.names = FALSE)
  )
}

shinyApp(ui = ui, server = server)
