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

read_local_app_version <- function(desc_path = "DESCRIPTION") {
  if (!file.exists(desc_path)) {
    return("unknown")
  }

  desc <- tryCatch(read.dcf(desc_path), error = function(e) NULL)
  if (is.null(desc) || !"Version" %in% colnames(desc)) {
    return("unknown")
  }

  as.character(desc[1, "Version"])
}

build_release_note <- function() {
  version_txt <- read_local_app_version()
  app_mtime <- tryCatch(format(file.info("app.R")$mtime, "%Y-%m-%d %H:%M"), error = function(e) "unknown")
  paste0("Build ", version_txt, " | app.R updated ", app_mtime, " | includes GNRS preview and submission packet export")
}

write_submission_packet <- function(zipfile, combined_tbl, join_audit_tbl, mapping_tbl, qc_tbl, bien_tbl, handoff_tbls, join_conflicts_tbl = NULL) {
  packet_dir <- file.path(tempdir(), paste0("historical_obs_packet_", as.integer(Sys.time())))
  dir.create(packet_dir, recursive = TRUE, showWarnings = FALSE)

  file_specs <- list(
    list(name = "combined_observation_stream.csv", data = combined_tbl, description = "Linked source table after chosen joins."),
    list(name = "join_audit_report.csv", data = join_audit_tbl, description = "Join coverage and cardinality audit."),
    list(name = "active_mapping.csv", data = mapping_tbl, description = "Current source-to-Darwin-Core mapping used in build step."),
    list(name = "dwc_qc_report.csv", data = qc_tbl, description = "QC results for the Darwin Core draft."),
    list(name = "bien_loading_table.csv", data = bien_tbl, description = "Draft BIEN loading table with staging and augmentation columns."),
    list(name = "tnrs_handoff.csv", data = handoff_tbls$tnrs, description = "Draft TNRS handoff for external name reconciliation."),
    list(name = "gnrs_handoff.csv", data = handoff_tbls$gnrs, description = "Draft GNRS handoff with GNRS-ready geography fields."),
    list(name = "gvs_handoff.csv", data = handoff_tbls$gvs, description = "Draft GVS handoff for coordinate review."),
    list(name = "nsr_handoff.csv", data = handoff_tbls$nsr, description = "Draft NSR handoff for native-status review.")
  )

  if (!is.null(join_conflicts_tbl) && is.data.frame(join_conflicts_tbl) && nrow(join_conflicts_tbl) > 0) {
    file_specs[[length(file_specs) + 1]] <- list(
      name = "join_duplicate_conflict_report.csv",
      data = join_conflicts_tbl,
      description = "Conflicting duplicate metadata values detected during join review."
    )
  }

  manifest_rows <- lapply(file_specs, function(spec) {
    out_path <- file.path(packet_dir, spec$name)
    utils::write.csv(spec$data, out_path, row.names = FALSE)
    data.frame(
      file_name = spec$name,
      description = spec$description,
      n_rows = if (is.data.frame(spec$data)) nrow(spec$data) else NA_integer_,
      stringsAsFactors = FALSE
    )
  })
  manifest <- do.call(rbind, manifest_rows)
  utils::write.csv(manifest, file.path(packet_dir, "submission_packet_manifest.csv"), row.names = FALSE)

  readme_lines <- c(
    "Historical Observation Data to BIEN - Submission Packet",
    paste0("Build note: ", build_release_note()),
    "",
    "Contents:",
    "- BIEN loading draft",
    "- TNRS, GNRS, GVS, and NSR handoff tables",
    "- Join audit, active mapping, QC report",
    "- Optional duplicate-join conflict report when conflicts were detected",
    "- submission_packet_manifest.csv describing the included files",
    "",
    "These are draft handoff tables and require downstream external review before BIEN submission."
  )
  writeLines(readme_lines, file.path(packet_dir, "README_submission_packet.txt"), useBytes = TRUE)

  old_wd <- setwd(packet_dir)
  on.exit(setwd(old_wd), add = TRUE)
  utils::zip(zipfile = zipfile, files = list.files(packet_dir, all.files = FALSE))
}

ui <- fluidPage(
  titlePanel("Historical Observation Data to BIEN"),
  tags$div(
    style = "margin: 10px 0; padding: 10px; background: #eef6ff; border-left: 4px solid #2f6fab;",
    strong("Goal: "),
    "Upload flat files, link tables, map to Darwin Core, run validation, and export BIEN draft handoff tables."
  ),
  tags$div(
    style = "margin: 0 0 10px 0; color: #5a6b7a; font-size: 0.9em;",
    build_release_note()
  ),
  sidebarLayout(
    sidebarPanel(
      h4("Quick Start: 5 Steps"),
      tags$ol(
        tags$li("Upload your main survey and plot/location files as CSVs."),
        tags$li("In Step 2, select the join key (e.g., Plot_Name) for both files. Keys must match exactly!"),
        tags$li("After linking, check that every observation row has Lat and Long filled. If not, check your join and file contents."),
        tags$li("In Step 5, resolve any BLOCK errors. Click the QC Dashboard for details. If you see 'missing_geography', your join did not propagate Lat/Long."),
        tags$li("Once all BLOCK issues are fixed, export your BIEN draft tables and handoffs.")
      ),
      tags$div(
        style = "margin: 8px 0 8px 0; padding: 8px; background: #fffbe6; border-left: 4px solid #c28b00; font-size: 0.92em;",
        strong("Troubleshooting:"),
        tags$ul(
          tags$li("If you see BLOCK or QC errors, click the QC Dashboard for details."),
          tags$li("Missing Lat/Long? Check your join key and file contents. Plot/location file must have Lat/Long, and join key must match survey file exactly."),
          tags$li("Still stuck? Download the example files from the Help tab and try those first.")
        )
      ),
      checkboxInput("use_tutorial_data", "Use built-in tutorial fake data", value = FALSE),
      fileInput("input_csv", "Upload CSV File(s)", accept = ".csv", multiple = TRUE),
      tags$hr(),
      h4("Step Actions"),
      actionButton("prepare_btn", "Step 2: Prepare Linked Table", class = "btn-primary"),
      actionButton("suggest_btn", "Step 3: Suggest Mapping", class = "btn-primary"),
      fileInput("mapping_csv", "Optional Mapping Override CSV", accept = ".csv"),
      actionButton("build_btn", "Step 5: Build BIEN Draft Tables", class = "btn-success"),
      actionButton("run_bien_services", "Run BIEN Web Services (TNRS, GNRS, GVS, NSR)", class = "btn-warning"),
      tags$hr(),
      h4("Downloads"),
      downloadButton("download_combined", "Combined Source Table"),
      downloadButton("download_join_audit", "Join Audit Report"),
      downloadButton("download_join_conflicts", "Join Conflict Report"),
      downloadButton("download_mapping", "Active Mapping"),
      downloadButton("download_qc", "QC Report"),
      downloadButton("download_bien", "BIEN Loading Draft"),
      downloadButton("download_tnrs", "TNRS Handoff"),
      downloadButton("download_gnrs", "GNRS Handoff"),
      downloadButton("download_gvs", "GVS Handoff"),
      downloadButton("download_nsr", "NSR Handoff"),
      tags$div(
        style = "margin: 6px 0 4px 0; padding: 8px 10px; background: #f0f4ff; border-left: 3px solid #2f6fab; font-size: 0.85em;",
        strong("Submission Packet includes:"),
        tags$ul(
          style = "margin: 4px 0 0 0; padding-left: 16px;",
          tags$li("combined_observation_stream.csv"),
          tags$li("join_audit_report.csv"),
          tags$li("active_mapping.csv"),
          tags$li("dwc_qc_report.csv"),
          tags$li("bien_loading_table.csv"),
          tags$li("tnrs_handoff.csv"),
          tags$li("gnrs_handoff.csv"),
          tags$li("gvs_handoff.csv"),
          tags$li("nsr_handoff.csv"),
          tags$li("submission_packet_manifest.csv"),
          tags$li("README_submission_packet.txt")
        )
      ),
      downloadButton("download_submission_packet", "Submission Packet Zip"),
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
          uiOutput("merge_plan_box"),
          h4("Suggested Merge Plan"),
          tableOutput("merge_plan_table"),
          h4("Loaded File Summary"),
          tableOutput("upload_summary_table"),
          h4("Primary File Preview"),
          tableOutput("primary_preview")
        ),
        tabPanel(
          "Step 2 Link",
          h3("Step 2. Link Observations with Metadata"),
          p("Select a primary observation file and one or more metadata files (location, plot, traits)."),
          uiOutput("link_loading_ui"),
          h4("Join Audit"),
          uiOutput("join_warning_box"),
          tableOutput("join_audit_table"),
          h4("Duplicate Key Conflict Report"),
          tableOutput("join_conflicts_table"),
          h4("Linked Table Preview"),
          tableOutput("combined_preview")
        ),
        tabPanel(
          "Step 3 Map",
          h3("Step 3. Darwin Core Mapping"),
          p("Auto-suggestions come from header synonym matching plus BIEN-aware field matching. You can upload a mapping override CSV with source_column,dwc_term."),
          uiOutput("map_loading_ui"),
          tags$div(
            style = "margin: 10px 0; padding: 10px; background: #f4f8ff; border-left: 4px solid #2f6fab;",
            strong("What to review in this step"),
            tags$ol(
              tags$li("Click 'Step 3: Suggest Mapping' in the left sidebar."),
              tags$li("Confirm that the species column maps to scientificName and any latitude/longitude columns map to decimalLatitude and decimalLongitude."),
              tags$li("If a DBH or diameter column is detected, the app may map it to measurementValue automatically and add measurementType = diameter_at_breast_height with a default unit when possible."),
              tags$li("If any suggestion is wrong, upload a mapping override CSV before continuing.")
            )
          ),
          h4("Suggested Mapping"),
          tableOutput("mapping_table"),
          h4("Active Mapping"),
          tableOutput("active_mapping_table")
        ),
        tabPanel(
          "Step 4 Taxonomy",
          h3("Step 4. Taxonomic Reconciliation Triage"),
          p("This step flags unresolved names locally. Use exported TNRS handoff for authoritative reconciliation."),
          uiOutput("taxonomy_loading_ui"),
          h4("Taxonomy Summary"),
          tableOutput("taxonomy_summary"),
          h4("Names Requiring Review"),
          tableOutput("taxonomy_review")
        ),
          taxonomy_loading <- reactiveVal(FALSE)

          observe({
            # Show spinner when taxonomy is being calculated
            taxonomy_loading(TRUE)
            invalidateLater(500, session)
            isolate({
              # Simulate calculation delay for demonstration (replace with real triggers as needed)
              if (!is.null(build_state())) {
                Sys.sleep(0.5)
              }
            })
            taxonomy_loading(FALSE)
          })

          output$taxonomy_loading_ui <- renderUI({
            if (taxonomy_loading()) {
              tags$div(style = "margin: 10px 0; color: #2f6fab; font-weight: bold;", 
                tags$span("⏳ Calculating taxonomy summary... Please wait."),
                tags$div(class = "spinner-border", role = "status", style = "display:inline-block; width: 1.5rem; height: 1.5rem; margin-left: 10px; vertical-align: middle; border: 0.25em solid #2f6fab; border-right-color: transparent; border-radius: 50%; animation: spin 0.75s linear infinite;")
              )
            } else {
              NULL
            }
          })

          tags$head(tags$style(HTML('@keyframes spin { 100% { transform: rotate(360deg); } } .spinner-border { animation: spin 0.75s linear infinite; }')))
        tabPanel(
          "Step 5 Validate",
          h3("Step 5. QC Validation"),
          uiOutput("validate_loading_ui"),
          h4("QC Dashboard"),
          tableOutput("qc_table"),
          h4("Build Summary"),
          verbatimTextOutput("summary_text")
        ),
          # --- Loading spinner state for each step ---
          link_loading <- reactiveVal(FALSE)
          map_loading <- reactiveVal(FALSE)
          validate_loading <- reactiveVal(FALSE)

          # --- Step 2 Link spinner logic ---
          observeEvent(input$prepare_btn, {
            link_loading(TRUE)
            # Simulate delay for demonstration; replace with real triggers as needed
            invalidateLater(500, session)
            isolate({ Sys.sleep(0.5) })
            link_loading(FALSE)
          })
          output$link_loading_ui <- renderUI({
            if (link_loading()) {
              tags$div(style = "margin: 10px 0; color: #2f6fab; font-weight: bold;", 
                tags$span("⏳ Preparing linked table... Please wait."),
                tags$div(class = "spinner-border", role = "status", style = "display:inline-block; width: 1.5rem; height: 1.5rem; margin-left: 10px; vertical-align: middle; border: 0.25em solid #2f6fab; border-right-color: transparent; border-radius: 50%; animation: spin 0.75s linear infinite;")
              )
            } else NULL
          })

          # --- Step 3 Map spinner logic ---
          observeEvent(input$suggest_btn, {
            map_loading(TRUE)
            invalidateLater(500, session)
            isolate({ Sys.sleep(0.5) })
            map_loading(FALSE)
          })
          output$map_loading_ui <- renderUI({
            if (map_loading()) {
              tags$div(style = "margin: 10px 0; color: #2f6fab; font-weight: bold;", 
                tags$span("⏳ Suggesting mapping... Please wait."),
                tags$div(class = "spinner-border", role = "status", style = "display:inline-block; width: 1.5rem; height: 1.5rem; margin-left: 10px; vertical-align: middle; border: 0.25em solid #2f6fab; border-right-color: transparent; border-radius: 50%; animation: spin 0.75s linear infinite;")
              )
            } else NULL
          })

          # --- Step 5 Validate spinner logic ---
          observeEvent(input$build_btn, {
            validate_loading(TRUE)
            invalidateLater(500, session)
            isolate({ Sys.sleep(0.5) })
            validate_loading(FALSE)
          })
          output$validate_loading_ui <- renderUI({
            if (validate_loading()) {
              tags$div(style = "margin: 10px 0; color: #2f6fab; font-weight: bold;", 
                tags$span("⏳ Validating and building BIEN draft tables... Please wait."),
                tags$div(class = "spinner-border", role = "status", style = "display:inline-block; width: 1.5rem; height: 1.5rem; margin-left: 10px; vertical-align: middle; border: 0.25em solid #2f6fab; border-right-color: transparent; border-radius: 50%; animation: spin 0.75s linear infinite;")
              )
            } else NULL
          })

          # --- Spinner CSS (only add once) ---
          tags$head(tags$style(HTML('@keyframes spin { 100% { transform: rotate(360deg); } } .spinner-border { animation: spin 0.75s linear infinite; }')))
        tabPanel(
          "Step 6 Export",
          h3("Step 6. Export BIEN Draft Tables"),
          p("Download the draft loading and handoff tables for external validation and BIEN review."),
          tags$div(
            style = "margin: 10px 0; padding: 10px; background: #eef7ee; border-left: 4px solid #3a7d44;",
            strong("What is in the BIEN Loading Draft now"),
            tags$ul(
              tags$li("Mapped Darwin Core fields plus BIEN-backed taxonomy and coordinate augmentation columns."),
              tags$li("Explicit staging status columns so you can see which rows still need review before BIEN loading."),
              tags$li("GNRS-ready location fields and query identifiers in the GNRS handoff export."),
              tags$li("Submission Packet Zip bundles the BIEN draft, handoff tables, QC, mapping, join audit, and a manifest file."),
              tags$li("These files are still draft handoff tables, not final proof that names or places are validated.")
            )
          ),
          h4("BIEN Loading Preview"),
          tableOutput("bien_preview"),
          h4("GNRS Handoff Preview"),
          tableOutput("gnrs_preview"),
          h4("Export Readiness"),
          verbatimTextOutput("export_readiness")
        ),
        tabPanel(
          "Help",
          h3("How to Use This App"),
          tags$ol(
            tags$li("Upload your main survey and plot/location files as CSVs, or turn on tutorial mode for a demo."),
            tags$li("In Step 2, select the join key (e.g., Plot_Name) for both files. Keys must match exactly!"),
            tags$li("After linking, check that every observation row has Lat and Long filled. If not, check your join and file contents."),
            tags$li("In Step 5, resolve any BLOCK errors. Click the QC Dashboard for details. If you see 'missing_geography', your join did not propagate Lat/Long."),
            tags$li("Once all BLOCK issues are fixed, export your BIEN draft tables and handoffs.")
          ),
          tags$hr(),
          h4("How to prepare your data for BIEN"),
          tags$ul(
            tags$li("Each observation must have a matching plot/location with Lat/Long."),
            tags$li("Join keys (like Plot_Name) must match exactly in both files (no typos, spaces, or case mismatches)."),
            tags$li("No empty rows or columns for required fields."),
            tags$li("Download and test with the example files below if unsure.")
          ),
          tags$hr(),
          h4("FAQ: Common Problems and Solutions"),
          tags$ul(
            tags$li(strong("Q: I see BLOCK or QC errors!"), " — Click the QC Dashboard for details. Most often, Lat/Long are missing due to a join problem."),
            tags$li(strong("Q: My Lat/Long are NA or missing!"), " — Check that your plot/location file has Lat/Long, and that the join key matches exactly in both files."),
            tags$li(strong("Q: Can I see an example?"), " — Yes! Download the sample files below and try them in the app.")
          ),
          tags$hr(),
          tags$div(
            style = "font-size: 0.9em; color: #555;",
            tags$strong("Live app: "),
            tags$a(
              href = "https://benquist.shinyapps.io/historical-obs-to-bien/",
              target = "_blank",
              "https://benquist.shinyapps.io/historical-obs-to-bien/"
            ),
            tags$br(),
            tags$span(paste0("Last deployed: ", format(Sys.Date(), "%Y-%m-%d")))
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

  merge_plan <- reactive({
    files <- available_files()
    req(length(files) > 0)
    suggest_merge_plan(files)
  })

  output$merge_controls <- renderUI({
    files <- names(available_files())
    req(length(files) > 0)

    plan <- merge_plan()
    primary_default <- if (!is.null(plan$primary_file) && nzchar(plan$primary_file)) plan$primary_file else files[1]
    metadata_choices <- setdiff(files, primary_default)
    metadata_default <- intersect(metadata_choices, plan$metadata_files)

    tagList(
      selectInput("primary_file", "Primary observation file", choices = files, selected = primary_default),
      uiOutput("primary_key_ui"),
      selectizeInput("metadata_files", "Metadata file(s)", choices = metadata_choices, selected = metadata_default, multiple = TRUE),
      uiOutput("metadata_keys_ui")
    )
  })

  output$primary_key_ui <- renderUI({
    req(input$primary_file)
    df <- available_files()[[input$primary_file]]
    plan <- merge_plan()
    selected_key <- if (!is.null(plan$primary_key) && plan$primary_key %in% names(df)) plan$primary_key else names(df)[[1]]
    selectInput("primary_key", "Primary join key", choices = names(df), selected = selected_key)
  })

  output$metadata_keys_ui <- renderUI({
    req(input$metadata_files)
    plan <- merge_plan()

    controls <- lapply(input$metadata_files, function(f) {
      df <- available_files()[[f]]
      selected_key <- NULL
      if (is.data.frame(plan$join_suggestions) && nrow(plan$join_suggestions) > 0) {
        hit <- plan$join_suggestions[plan$join_suggestions$metadata_file == f, , drop = FALSE]
        if (nrow(hit) > 0 && hit$metadata_key[[1]] %in% names(df)) {
          selected_key <- hit$metadata_key[[1]]
        }
      }
      selectInput(
        inputId = paste0("meta_key_", make.names(f)),
        label = paste0("Join key in metadata file: ", f),
        choices = names(df),
        selected = if (!is.null(selected_key)) selected_key else names(df)[[1]]
      )
    })

    do.call(tagList, controls)
  })

  output$merge_plan_box <- renderUI({
    plan <- merge_plan()

    if (!is.data.frame(plan$join_suggestions) || nrow(plan$join_suggestions) == 0) {
      return(tags$div(
        style = "margin: 8px 0 12px 0; padding: 10px; background: #eef6ff; border-left: 4px solid #2f6fab;",
        strong("Merge suggestion: "),
        "The app could not infer a high-confidence join pair automatically. Select the primary file and keys manually below."
      ))
    }

    best <- plan$join_suggestions[1, , drop = FALSE]
    tags$div(
      style = "margin: 8px 0 12px 0; padding: 10px; background: #eef6ff; border-left: 4px solid #2f6fab;",
      strong("Merge suggestion: "),
      paste0(
        "Use ", best$primary_file[[1]], " as the primary observation file, then join ",
        best$metadata_file[[1]], " by ", best$primary_key[[1]], " = ", best$metadata_key[[1]],
        " (shared unique values: ", best$shared_unique_values[[1]], ")."
      )
    )
  })

  output$merge_plan_table <- renderTable({
    plan <- merge_plan()
    if (!is.data.frame(plan$join_suggestions) || nrow(plan$join_suggestions) == 0) {
      return(data.frame(note = "No automatic merge candidates detected.", stringsAsFactors = FALSE))
    }
    plan$join_suggestions
  }, striped = TRUE, bordered = TRUE)

  output$upload_summary_table <- renderTable({
    plan <- merge_plan()
    req(is.data.frame(plan$file_summary))
    plan$file_summary
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

    conflicts <- find_duplicate_metadata_conflicts(
      data_list = files,
      metadata_files = metadata_files,
      metadata_keys = metadata_keys
    )

    list(merged = merged, audit = audit, conflicts = conflicts)
  })

  combined_df <- reactive({
    req(combined_state())
    combined_state()$merged
  })

  join_audit <- reactive({
    req(combined_state())
    combined_state()$audit
  })

  join_conflicts <- reactive({
    req(combined_state())
    combined_state()$conflicts
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

  staging_preview_df <- reactive({
    req(build_state())
    build_bien_loading_table(dwc_df())
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
    staging_preview_df()
  })

  handoff <- reactive({
    req(build_state())
    build_bien_handoff_tables(staging_preview_df())
  })

  output$combined_preview <- renderTable({
    req(combined_df())
    utils::head(combined_df(), 12)
  }, striped = TRUE, bordered = TRUE)

  output$join_audit_table <- renderTable({
    req(join_audit())
    join_audit()
  }, striped = TRUE, bordered = TRUE)

  output$join_conflicts_table <- renderTable({
    req(join_conflicts())
    if (nrow(join_conflicts()) == 0) {
      return(data.frame(
        note = "No duplicate-key column conflicts detected in selected metadata files.",
        stringsAsFactors = FALSE
      ))
    }
    join_conflicts()
  }, striped = TRUE, bordered = TRUE)

  output$join_warning_box <- renderUI({
    req(join_audit())
    audit <- join_audit()

    if (nrow(audit) == 0 || !any(audit$duplicate_metadata_collapse)) {
      return(NULL)
    }

    conflict_count <- nrow(join_conflicts())
    tags$div(
      style = "margin: 8px 0 12px 0; padding: 12px; background: #fff3cd; border-left: 4px solid #b7791f;",
      strong("Duplicate metadata warning: "),
      paste0(
        "At least one metadata file has duplicate join keys. The merge uses first non-empty values per key. ",
        "Detected conflicting duplicate values: ",
        conflict_count,
        ". Review the conflict report before export."
      )
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
    if (!is.null(build_state())) {
      bien_tbl <- staging_preview_df()
      data.frame(
        metric = c("Total records", "Unique submitted names", "BIEN/backbone matched", "Needs review", "Blank scientificName"),
        value = c(
          nrow(bien_tbl),
          length(unique(bien_tbl$scientificName)),
          sum(!is.na(bien_tbl$bien_matched_name) & trimws(as.character(bien_tbl$bien_matched_name)) != ""),
          sum(grepl("review|unresolved", bien_tbl$bien_taxonomy_status, ignore.case = TRUE), na.rm = TRUE),
          sum(is.na(bien_tbl$scientificName) | trimws(as.character(bien_tbl$scientificName)) == "")
        ),
        stringsAsFactors = FALSE
      )
    } else {
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
    }
  }, striped = TRUE, bordered = TRUE)

  output$taxonomy_review <- renderTable({
    if (!is.null(build_state())) {
      bien_tbl <- staging_preview_df()
      review_idx <- grepl("review|unresolved", bien_tbl$bien_taxonomy_status, ignore.case = TRUE) |
        is.na(bien_tbl$scientificName) |
        trimws(as.character(bien_tbl$scientificName)) == ""
      bien_tbl[review_idx, c("occurrenceID", "scientificName", "bien_matched_name", "bien_taxonomy_status", "bien_family"), drop = FALSE]
    } else {
      tx <- taxonomy_df()
      tx[tx$status %in% c("REVIEW", "UNRESOLVED"), , drop = FALSE]
    }
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
    join_conflict_rows <- nrow(join_conflicts())
    qc_blocks <- qc_severity_count(qc_df(), "BLOCK")
    qc_warns <- qc_severity_count(qc_df(), "WARN")
    bien_matches <- if ("bien_matched_name" %in% names(staging_preview_df())) sum(!is.na(staging_preview_df()$bien_matched_name) & trimws(as.character(staging_preview_df()$bien_matched_name)) != "") else 0
    coord_ready <- if ("coordinate_valid_basic" %in% names(staging_preview_df())) sum(isTRUE(staging_preview_df()$coordinate_valid_basic), na.rm = TRUE) else 0

    paste(
      paste0("Loaded files: ", length(available_files())),
      paste0("Data mode: ", if (isTRUE(input$use_tutorial_data)) "Tutorial fake data" else "Uploaded files"),
      paste0("Metadata files joined: ", metadata_count),
      paste0("Combined rows (primary records): ", nrow(combined_df())),
      paste0("Join audit blockers: ", join_blockers, " | warnings: ", join_warnings),
      paste0("Join duplicate-conflict rows: ", join_conflict_rows),
      paste0("Mapped Darwin Core columns: ", ncol(dwc_df())),
      paste0("BIEN/backbone matched names: ", bien_matches),
      paste0("Rows with basic-valid coordinates: ", coord_ready),
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

  output$gnrs_preview <- renderTable({
    req(handoff())
    utils::head(handoff()$gnrs, 10)
  }, striped = TRUE, bordered = TRUE)

  output$export_readiness <- renderText({
    req(qc_df())
    if (qc_has_blockers(qc_df())) {
      "Export blocked: resolve BLOCK issues in Step 5 Validate before BIEN loading export."
    } else {
      "Export ready: download the BIEN loading draft with BIEN-backed taxonomy, coordinate, staging-status, and GNRS-ready augmentation plus TNRS/GNRS/GVS/NSR handoff files."
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

  output$download_join_conflicts <- downloadHandler(
    filename = function() "join_duplicate_conflict_report.csv",
    content = function(file) utils::write.csv(join_conflicts(), file, row.names = FALSE)
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
    content = function(file) {
      tnrs_tbl <- tryCatch({
        req(build_state())
        build_bien_handoff_tables(staging_preview_df())$tnrs
      }, error = function(e) {
        src <- if (!is.null(combined_state())) combined_df() else data.frame(stringsAsFactors = FALSE)
        data.frame(
          occurrenceID = if ("occurrenceID" %in% names(src)) src$occurrenceID else seq_len(nrow(src)),
          scientificName = if ("scientificName" %in% names(src)) src$scientificName else NA_character_,
          stringsAsFactors = FALSE
        )
      })

      if (!"occurrenceID" %in% names(tnrs_tbl)) {
        tnrs_tbl$occurrenceID <- seq_len(nrow(tnrs_tbl))
      }
      if (!"scientificName" %in% names(tnrs_tbl)) {
        tnrs_tbl$scientificName <- NA_character_
      }

      utils::write.csv(tnrs_tbl[, c("occurrenceID", "scientificName"), drop = FALSE], file, row.names = FALSE)
    }
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

  output$download_submission_packet <- downloadHandler(
    filename = function() paste0("historical_obs_submission_packet_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".zip"),
    content = function(file) {
      write_submission_packet(
        zipfile = file,
        combined_tbl = combined_df(),
        join_audit_tbl = join_audit(),
        mapping_tbl = active_mapping(),
        qc_tbl = qc_df(),
        bien_tbl = bien_df(),
        handoff_tbls = handoff(),
        join_conflicts_tbl = join_conflicts()
      )
    }
  )

  bien_services_status <- reactiveVal("")

  observeEvent(input$run_bien_services, {
    bien_services_status("Starting BIEN web service workflow...")
    # 1. TNRS
    bien_services_status("Submitting names to TNRS...")
    tnrs_result <- tryCatch({
      bien_tnrs_query(unique(bien_loading_table()$scientificName))
    }, error = function(e) e)
    # 2. GNRS
    bien_services_status("Submitting coordinates to GNRS...")
    gnrs_result <- tryCatch({
      bien_gnrs_query(unique(bien_loading_table()$locality))
    }, error = function(e) e)
    # 3. GVS
    bien_services_status("Submitting coordinates to GVS...")
    gvs_result <- tryCatch({
      bien_gvs_query(unique(bien_loading_table()[,c("decimalLatitude","decimalLongitude")]))
    }, error = function(e) e)
    # 4. NSR
    bien_services_status("Submitting names to NSR...")
    nsr_result <- tryCatch({
      bien_nsr_query(unique(bien_loading_table()$scientificName))
    }, error = function(e) e)
    bien_services_status("All BIEN services complete. Staging table updated.")
    # TODO: Integrate results into staging table and update UI/exports
  })
  output$bien_services_status <- renderText({ bien_services_status() })
}

shinyApp(ui = ui, server = server)
