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
  paste0("BIEN Observation Ingest Tool build ", version_txt, " | app.R updated ", app_mtime, " | includes GNRS preview and submission packet export")
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
    "BIEN Observation Ingest and Reconciliation Tool - Submission Packet",
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
  tags$head(
    tags$style(HTML('
      @keyframes spin { 100% { transform: rotate(360deg); } }
      .spinner-border { animation: spin 0.75s linear infinite; }

      /* ── Global loading pill ── */
      .global-loading-pill {
        position: fixed;
        top: 14px;
        right: 14px;
        z-index: 1050;
        padding: 10px 18px;
        border-radius: 999px;
        background: #2f6fab;
        border: none;
        color: #ffffff;
        font-weight: 700;
        font-size: 0.95em;
        box-shadow: 0 4px 14px rgba(47, 111, 171, 0.45);
        letter-spacing: 0.01em;
      }
      .global-help-btn {
        position: fixed;
        top: 14px;
        right: 220px;
        z-index: 1050;
      }

      /* ── Sidebar section cards ── */
      .bien-sidebar-section {
        margin: 0 0 14px 0;
        padding: 12px 14px;
        background: #f8fbff;
        border: 1px solid #d0e4f7;
        border-radius: 6px;
      }
      .bien-sidebar-section h5 {
        margin: 0 0 10px 0;
        font-size: 0.85em;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: #1f4f82;
      }

      /* ── Step action buttons ── */
      .btn-step {
        display: block;
        width: 100%;
        text-align: left;
        padding: 12px 16px;
        margin-bottom: 8px;
        font-size: 1em;
        font-weight: 600;
        border-radius: 6px;
        border: none;
        cursor: pointer;
        transition: filter 0.15s, transform 0.1s;
      }
      .btn-step:active {
        transform: scale(0.98);
        filter: brightness(0.93);
      }
      .btn-step-primary {
        background: #2f6fab;
        color: #fff;
      }
      .btn-step-primary:hover {
        background: #245d96;
        color: #fff;
      }
      .btn-step-success {
        background: #2d7a3a;
        color: #fff;
      }
      .btn-step-success:hover {
        background: #236130;
        color: #fff;
      }
      .btn-step-warning {
        background: #b87c00;
        color: #fff;
      }
      .btn-step-warning:hover {
        background: #9a6700;
        color: #fff;
      }

      /* ── Working banners ── */
      .bien-working-banner {
        margin: 8px 0 12px 0;
        padding: 14px 18px;
        background: #e8f0fb;
        border-left: 5px solid #2f6fab;
        border-radius: 4px;
        font-weight: 700;
        font-size: 1em;
        color: #1a3d6e;
        display: flex;
        align-items: center;
        gap: 12px;
      }
      .bien-working-spinner {
        display: inline-block;
        width: 1.4rem;
        height: 1.4rem;
        border: 3px solid #2f6fab;
        border-right-color: transparent;
        border-radius: 50%;
        flex-shrink: 0;
      }

      /* ── Step number badge ── */
      .step-badge {
        display: inline-block;
        width: 1.6em;
        height: 1.6em;
        line-height: 1.6em;
        text-align: center;
        background: rgba(255,255,255,0.25);
        border-radius: 50%;
        font-size: 0.88em;
        font-weight: 800;
        margin-right: 8px;
      }

      /* ── Download section ── */
      .bien-download-grid {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 5px;
        margin-top: 6px;
      }
      .bien-download-grid .btn {
        font-size: 0.78em;
        padding: 5px 6px;
        white-space: normal;
        text-align: center;
      }

      @media (max-width: 767px) {
        .global-help-btn { right: 145px; }
        .global-loading-pill { max-width: calc(100vw - 24px); font-size: 0.88em; }
        .bien-download-grid { grid-template-columns: 1fr; }
      }
      @media (max-width: 575px) {
        .global-help-btn { top: 56px; right: 12px; }
        .global-help-btn .btn { padding: 6px 10px; font-size: 0.9em; }
      }
    '))
    ,
    tags$script(HTML(
      "$(document).on('shiny:connected', function() { Shiny.setInputValue('app_busy', false, {priority: 'event'}); });\n$(document).on('shiny:busy', function() { Shiny.setInputValue('app_busy', true, {priority: 'event'}); });\n$(document).on('shiny:idle', function() { Shiny.setInputValue('app_busy', false, {priority: 'event'}); });"
    ))
  ),
  titlePanel("BIEN Observation Ingest and Reconciliation Tool"),
  tags$div(
    style = "margin: 10px 0; padding: 10px; background: #eef6ff; border-left: 4px solid #2f6fab;",
    strong("Goal: "),
    "Ingest observation datasets, map to Darwin Core, prepare BIEN reconciliation packets, and build staging-ready outputs."
  ),
  tags$div(
    style = "margin: 0 0 10px 0; color: #5a6b7a; font-size: 0.9em;",
    build_release_note()
  ),
  tags$div(
    class = "global-help-btn",
    actionButton("open_global_help", "Help", class = "btn-info")
  ),
  uiOutput("global_loading_ui"),
  sidebarLayout(
    sidebarPanel(
      # ── Workflow status card ──
      tags$div(
        class = "bien-sidebar-section",
        style = "background: #eef7ff; border-color: #2f6fab;",
        h5("Workflow Status"),
        verbatimTextOutput("workflow_status_text")
      ),

      # ── Section 1: Upload ──
      tags$div(
        class = "bien-sidebar-section",
        h5("Upload"),
        checkboxInput("use_tutorial_data", "Use built-in tutorial fake data", value = FALSE),
        conditionalPanel(
          condition = "!input.use_tutorial_data",
          fileInput("input_csv", "Upload CSV File(s)", accept = ".csv", multiple = TRUE)
        ),
        conditionalPanel(
          condition = "input.use_tutorial_data",
          tags$div(
            style = "margin: 4px 0 2px 0; padding: 8px; background: #eef7ff; border-left: 3px solid #2f6fab; font-size: 0.9em;",
            tags$strong("Tutorial mode active."),
            " Using built-in synthetic observation and plot-metadata files. Uncheck above to upload your own data."
          )
        )
      ),

      # ── Section 2: Actions ──
      tags$div(
        class = "bien-sidebar-section",
        h5("Run Pipeline"),
        actionButton("prepare_btn",
          tags$span(tags$span(class = "step-badge", "A"), " Prepare Linked Table"),
          class = "btn btn-step btn-step-primary", width = "100%"),
        selectInput(
          "duplicate_strategy",
          "Duplicate metadata key resolution",
          choices = c(
            "First non-empty value" = "first_non_empty",
            "Last non-empty value" = "last_non_empty",
            "Most frequent non-empty value" = "most_frequent_non_empty",
            "Block and resolve manually" = "require_manual_resolution"
          ),
          selected = "first_non_empty"
        ),
        actionButton("suggest_btn",
          tags$span(tags$span(class = "step-badge", "B"), " Suggest Mapping"),
          class = "btn btn-step btn-step-primary", width = "100%"),
        fileInput("mapping_csv", "Optional Mapping Override CSV", accept = ".csv"),
        actionButton("build_btn",
          tags$span(tags$span(class = "step-badge", "C"), " Build BIEN Draft Tables"),
          class = "btn btn-step btn-step-success", width = "100%"),
        actionButton("run_bien_services",
          tags$span(tags$span(class = "step-badge", "D"), " Run BIEN Service Checks"),
          class = "btn btn-step btn-step-warning", width = "100%")
      ),

      # ── Section 3: Downloads ──
      tags$div(
        class = "bien-sidebar-section",
        h5("Downloads"),
        tags$p(
          style = "margin: 0 0 8px 0; font-size: 0.85em; color: #444;",
          "Starter templates:"
        ),
        downloadButton("download_historical_template", "Template: Historical Observations",
          style = "width:100%; margin-bottom:4px; font-size:0.82em;"),
        downloadButton("download_ecological_template", "Template: New Ecological Source",
          style = "width:100%; margin-bottom:10px; font-size:0.82em;"),
        tags$p(
          style = "margin: 0 0 6px 0; font-size: 0.85em; color: #444;",
          "Pipeline outputs:"
        ),
        tags$div(
          class = "bien-download-grid",
          downloadButton("download_combined", "Source Table"),
          downloadButton("download_join_audit", "Join Audit"),
          downloadButton("download_join_conflicts", "Join Conflicts"),
          downloadButton("download_mapping", "Active Mapping"),
          downloadButton("download_qc", "QC Report"),
          downloadButton("download_bien", "BIEN Draft"),
          downloadButton("download_tnrs", "TNRS Handoff"),
          downloadButton("download_gnrs", "GNRS Handoff"),
          downloadButton("download_gvs", "GVS Handoff"),
          downloadButton("download_nsr", "NSR Handoff")
        ),
        tags$div(style = "height: 8px;"),
        downloadButton("download_submission_packet", "⬇ Submission Packet Zip",
          style = "width:100%; font-weight:700; background:#2f6fab; color:#fff; border:none;")
      )
    ),

    mainPanel(
      tabsetPanel(
        id = "workflow_tabs",
        tabPanel(
          "Step 1 Upload",
          h3("Step 1. Upload and Inspect Files"),
          tags$div(
            style = "margin: 10px 0; padding: 10px; background: #f4f8ff; border-left: 4px solid #2f6fab;",
            strong("What to do in this step"),
            tags$ol(
              tags$li("In the left sidebar, check 'Use built-in tutorial fake data' — or upload your own CSV files."),
              tags$li("Review the Suggested Merge Plan and Loaded File Summary below to confirm the app detected the right primary observation file and join key."),
              tags$li("When ready, click the '", tags$strong("A Prepare Linked Table"), "' button in the sidebar. Results appear in the Step 2 Link tab.")
            )
          ),
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
          tags$div(
            style = "margin: 10px 0; padding: 10px; background: #f4f8ff; border-left: 4px solid #2f6fab;",
            strong("What to do in this step"),
            tags$ol(
              tags$li("This tab shows results after you click '", tags$strong("A Prepare Linked Table"), "' in the sidebar from Step 1."),
              tags$li("Check the Join Audit table — rows marked BLOCK must be resolved before proceeding (many-to-many join). WARN rows are informational."),
              tags$li("If the join looks correct, proceed to Step 3 Map and click '", tags$strong("B Suggest Mapping"), "'.")
            )
          ),
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
          tags$div(
            style = "margin: 10px 0; padding: 10px; background: #f4f8ff; border-left: 4px solid #2f6fab;",
            strong("What to do in this step"),
            tags$ol(
              tags$li("Click the '", tags$strong("B Suggest Mapping"), "' button in the left sidebar. Results appear below."),
              tags$li("Confirm that the species column maps to ", tags$code("scientificName"), " and any latitude/longitude columns map to ", tags$code("decimalLatitude"), " and ", tags$code("decimalLongitude"), "."),
              tags$li("If a DBH or diameter column is detected, the app may map it to ", tags$code("measurementValue"), " automatically and add ", tags$code("measurementType = diameter_at_breast_height"), " with a default unit when possible."),
              tags$li("If any suggestion is wrong, upload a mapping override CSV (optional) before continuing."),
              tags$li("When satisfied, click '", tags$strong("C Build BIEN Draft Tables"), "' in the sidebar to proceed to Step 5 Validate.")
            ),
            tags$p(style = "margin: 8px 0 0 0; font-size: 0.9em; color: #555;",
              "You can also upload a custom mapping CSV with columns ", tags$code("source_column"), " and ", tags$code("dwc_term"), " to override the auto-suggestions."
            )
          ),
          uiOutput("map_loading_ui"),
          h4("Suggested Mapping"),
          tableOutput("mapping_table"),
          h4("Active Mapping"),
          tableOutput("active_mapping_table")
        ),


        tabPanel(
          "Step 4 Taxonomy",
          h3("Step 4. Taxonomic Reconciliation Triage"),
          tags$div(
            style = "margin: 10px 0; padding: 10px; background: #f4f8ff; border-left: 4px solid #2f6fab;",
            strong("What to do in this step"),
            tags$ol(
              tags$li("This tab shows a local taxonomy triage of your scientific names — no button click needed. It updates automatically after Step 2 (Prepare Linked Table) completes."),
              tags$li("Review the Taxonomy Summary table. Names flagged as REVIEW contain uncertain qualifiers (sp., cf., aff., indet.) and should be inspected before submission."),
              tags$li("Names flagged as CANDIDATE are ready for external backbone checking — this happens in Step 6 via the 'D Run BIEN Service Checks' button, not here."),
              tags$li("When you are satisfied with the name review, click the 'C Build BIEN Draft Tables' button in the sidebar to proceed.")
            ),
            tags$p(
              style = "margin: 8px 0 0 0; font-size: 0.9em; color: #555;",
              "Note: This triage is local and fast. Authoritative reconciliation against the BIEN taxonomic backbone requires the downstream TNRS service (Step 6)."
            )
          ),
          uiOutput("taxonomy_loading_ui"),
          uiOutput("taxonomy_cap_warning_ui"),
          h4("Taxonomy Summary"),
          tableOutput("taxonomy_summary"),
          textOutput("taxonomy_review_note"),
          h4("Names Requiring Review"),
          DT::DTOutput("taxonomy_review")
        ),



        tabPanel(
          "Step 5 Validate",
          h3("Step 5. QC Validation"),
          uiOutput("validate_loading_ui"),
          h4("QC Dashboard"),
          tableOutput("qc_table"),
          h4("Build Summary"),
          verbatimTextOutput("summary_text")
        ),

        tabPanel(
          "Step 6 Export",
          h3("Step 6. Export BIEN Draft Tables"),
          p("Download the draft loading and handoff tables for external validation and BIEN review."),
          h4("BIEN Service Run State (Not Final Authority)"),
          uiOutput("bien_services_loading_ui"),
          verbatimTextOutput("bien_services_status"),
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
            tags$li("Upload your survey and plot/location CSVs in Step 1 Upload, or turn on tutorial mode for a demo."),
            tags$li("Click 'A Prepare Linked Table' and confirm the Step 2 Link join key matches exactly across files."),
            tags$li("Click 'B Suggest Mapping', then verify scientificName and any latitude/longitude fields in Step 3 Map."),
            tags$li("Click 'C Build BIEN Draft Tables', then use Step 5 Validate to clear any BLOCK errors. If you see 'missing_geography', your join did not propagate Lat/Long."),
            tags$li("Use Step 6 Export for draft BIEN tables and handoffs only after blockers are cleared.")
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
          h4("Optional: Run BIEN Web Services"),
          tags$p(
            "After you click 'C Build BIEN Draft Tables' and review Step 5 Validate, you can optionally request BIEN service-state checks for downstream reconciliation:"
          ),
          tags$ul(
            tags$li(strong("TNRS"), " (Taxonomic Name Resolution Service) — Reconciles scientific names against BIEN's taxonomic backbone."),
            tags$li(strong("GNRS"), " (Geographic Name Resolution Service) — Reconciles place and locality names to coordinates."),
            tags$li(strong("GVS"), " (Geospatial Validation Service) — Validates and flags problematic coordinates."),
            tags$li(strong("NSR"), " (Native Status Reference) — Flags introduced, invasive, or cultivated species.")
          ),
          tags$p(
            "Click the 'D Run BIEN Service Checks' button in the sidebar after building your draft tables. ",
            "Results display in Step 6 Export as conservative service-state summaries. Review and reconcile downstream before final BIEN submission."
          ),
          tags$hr(),
          h4("FAQ: Common Problems and Solutions"),
          tags$ul(
            tags$li(strong("Q: I see BLOCK or QC errors!"), " — Click the QC Dashboard for details. Most often, Lat/Long are missing due to a join problem."),
            tags$li(strong("Q: My Lat/Long are NA or missing!"), " — Check that your plot/location file has Lat/Long, and that the join key matches exactly in both files."),
            tags$li(strong("Q: Can I see an example?"), " — Yes! Download the sample files below and try them in the app."),
            tags$li(strong("Q: What do I do with BIEN Web Services results?"), " — Review the TNRS, GNRS, GVS, and NSR service-state output in Step 6 Export. Integrate any critical corrections back into your source data, rebuild BIEN tables if needed, and complete downstream reconciliation before submission.")
          ),
          tags$hr(),
          tags$div(
            style = "font-size: 0.9em; color: #555;",
            tags$strong("Live app: "),
            tags$a(
              href = "https://benquist.shinyapps.io/LoadingHistoricalObservationDataIntoBIEN/",
              target = "_blank",
              "https://benquist.shinyapps.io/LoadingHistoricalObservationDataIntoBIEN/"
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
  taxonomy_lookup_cap <- 50

  # --- Loading spinner state for each step ---
  link_loading <- reactiveVal(FALSE)
  map_loading <- reactiveVal(FALSE)
  taxonomy_loading <- reactiveVal(FALSE)
  validate_loading <- reactiveVal(FALSE)
  bien_services_loading <- reactiveVal(FALSE)

  any_step_loading <- reactive({
    isTRUE(input$app_busy) ||
      link_loading() ||
      map_loading() ||
      taxonomy_loading() ||
      validate_loading() ||
      bien_services_loading()
  })

  output$global_loading_ui <- renderUI({
    if (!any_step_loading()) {
      return(NULL)
    }
    tags$div(
      class = "global-loading-pill",
      tags$div(
        class = "spinner-border",
        role = "status",
        style = "display:inline-block; width: 1.1rem; height: 1.1rem; margin-right: 8px; vertical-align: middle; border: 0.25em solid rgba(255,255,255,0.85); border-right-color: transparent; border-radius: 50%;"
      ),
      tags$span("Working...")
    )
  })

  observeEvent(input$open_global_help, {
    showModal(modalDialog(
      title = "BIEN Observation Ingest Help",
      easyClose = TRUE,
      footer = modalButton("Close"),
      tags$ol(
        tags$li("Upload all required CSV files in Step 1 Upload (observations plus metadata)."),
        tags$li("Click 'A Prepare Linked Table', then clear any Step 2 Link BLOCK rows before moving on."),
        tags$li("Click 'B Suggest Mapping', review Step 3 Map and Step 4 Taxonomy, then click 'C Build BIEN Draft Tables'."),
        tags$li("Review Step 5 Validate. If you run 'D Run BIEN Service Checks', treat the results as service-state summaries, not final authority."),
        tags$li("Use Step 6 Export for draft handoff files only after blockers are cleared, then complete downstream expert and service reconciliation before BIEN submission.")
      )
    ))
  })

  # --- Step 2 Link spinner logic ---
  # Single observer: always clears spinner even if combined_state() errors or req() fails silently.
  observeEvent(input$prepare_btn, {
    link_loading(TRUE)
    session$onFlushed(function() {
      tryCatch(
        combined_state(),
        error = function(e) {
          showNotification(paste0("Step 2 error: ", conditionMessage(e)),
                           type = "error", duration = 15)
        }
      )
      link_loading(FALSE)
    }, once = TRUE)
  })
  output$link_loading_ui <- renderUI({
    if (!link_loading()) return(NULL)
    tags$div(
      class = "bien-working-banner",
      tags$div(class = "bien-working-spinner spinner-border"),
      tags$span("Step 2: Preparing linked table — please wait...")
    )
  })

  # --- Step 3 Map spinner logic ---
  # Single observer: always clears spinner even if suggested_mapping() errors or req() fails silently.
  observeEvent(input$suggest_btn, {
    map_loading(TRUE)
    session$onFlushed(function() {
      tryCatch(
        suggested_mapping(),
        error = function(e) {
          showNotification(paste0("Step 3 error: ", conditionMessage(e)),
                           type = "error", duration = 15)
        }
      )
      map_loading(FALSE)
    }, once = TRUE)
  })
  output$map_loading_ui <- renderUI({
    if (!map_loading()) return(NULL)
    tags$div(
      class = "bien-working-banner",
      tags$div(class = "bien-working-spinner spinner-border"),
      tags$span("Step 3: Suggesting field mapping — please wait...")
    )
  })

  # --- Step 4 Taxonomy spinner logic ---
  # Local triage is instant — no forced onFlushed evaluation needed.
  # taxonomy_loading reactiveVal is kept so global_loading_ui doesn't need rewiring.
  observeEvent(input$workflow_tabs, {
    taxonomy_loading(FALSE)
  }, ignoreInit = TRUE)
  output$taxonomy_loading_ui <- renderUI(NULL)

  # --- Step 5 Validate spinner logic ---
  # Single observer: always clears spinner even if build_state() errors or req() fails silently.
  observeEvent(input$build_btn, {
    validate_loading(TRUE)
    session$onFlushed(function() {
      tryCatch(
        build_state(),
        error = function(e) {
          showNotification(paste0("Step 5 error: ", conditionMessage(e)),
                           type = "error", duration = 15)
        }
      )
      validate_loading(FALSE)
    }, once = TRUE)
  })
  output$validate_loading_ui <- renderUI({
    if (!validate_loading()) return(NULL)
    tags$div(
      class = "bien-working-banner",
      tags$div(class = "bien-working-spinner spinner-border"),
      tags$span("Step 5: Validating and building BIEN draft tables — please wait...")
    )
  })

  # Robust path resolution: works both from source dir and when deployed as a package.
  resolve_extdata_path <- function(filename) {
    # 1. Prefer system.file (works when installed as package on shinyapps.io).
    pkg_path <- system.file("extdata", filename, package = "HistoricalObsToBIEN")
    if (nzchar(pkg_path) && file.exists(pkg_path)) return(pkg_path)
    # 2. Fall back to relative inst/extdata (works from source dir).
    rel <- file.path("inst", "extdata", filename)
    if (file.exists(rel)) return(rel)
    # 3. App-root extdata (alternative deploy layout).
    alt <- file.path("extdata", filename)
    if (file.exists(alt)) return(alt)
    stop(paste0("Tutorial data file not found: ", filename,
                " (searched system.file, inst/extdata, extdata)"))
  }

  resolve_dict_path <- function(filename) {
    pkg_path <- system.file("dictionaries", filename, package = "HistoricalObsToBIEN")
    if (nzchar(pkg_path) && file.exists(pkg_path)) return(pkg_path)
    rel <- file.path("inst", "dictionaries", filename)
    if (file.exists(rel)) return(rel)
    alt <- file.path("dictionaries", filename)
    if (file.exists(alt)) return(alt)
    stop(paste0("Dictionary file not found: ", filename))
  }

  tutorial_files <- reactive({
    tryCatch(
      list(
        "tutorial_observations.csv" = read_historical_csv(
          resolve_extdata_path("tutorial_observations.csv")
        ),
        "sample_plot_metadata.csv" = read_historical_csv(
          resolve_extdata_path("sample_plot_metadata.csv")
        )
      ),
      error = function(e) {
        showNotification(
          paste0("Could not load tutorial data: ", conditionMessage(e)),
          type = "error", duration = 12
        )
        NULL
      }
    )
  })

  available_files <- reactive({
    if (isTRUE(input$use_tutorial_data)) {
      tut <- tutorial_files()
      validate(
        need(!is.null(tut),
             "Tutorial data could not be loaded. See error notification. Try uploading your own files instead.")
      )
      return(tut)
    }
    validate(
      need(!is.null(input$input_csv),
           "Please upload at least one CSV file, or check the 'Use built-in tutorial fake data' box.")
    )
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

  output$workflow_status_text <- renderText({
    upload_ready <- if (isTRUE(input$use_tutorial_data)) TRUE else !is.null(input$input_csv)
    link_ready <- !is.null(combined_state())
    join_blocked <- if (link_ready) has_join_blockers(join_audit()) else FALSE
    mapping_ready <- !is.null(suggested_mapping())
    build_ready <- !is.null(build_state())
    qc_blocked <- if (build_ready) qc_has_blockers(qc_df()) else NA

    paste(
      paste0("Upload: ", if (upload_ready) "ready" else "waiting for files"),
      paste0("Link: ", if (!link_ready) "not started" else if (join_blocked) "blocked (join blockers)" else "complete"),
      paste0("Map: ", if (mapping_ready) "complete" else "pending"),
      paste0("Build: ", if (!build_ready) "pending" else if (isTRUE(qc_blocked)) "blocked (QC BLOCK)" else "complete"),
      "Services: optional after successful build",
      sep = "\n"
    )
  })

  combined_state <- eventReactive(input$prepare_btn, {
    files <- available_files()
    req(length(files) > 0)
    plan <- merge_plan()
    primary_file <- if (!is.null(input$primary_file) && nzchar(input$primary_file)) {
      input$primary_file
    } else {
      req(!is.null(plan$primary_file), cancelOutput = FALSE)
      plan$primary_file
    }
    primary_key_val <- if (!is.null(input$primary_key) && nzchar(input$primary_key)) {
      input$primary_key
    } else {
      req(!is.null(plan$primary_key), cancelOutput = FALSE)
      plan$primary_key
    }

    metadata_files <- if (!is.null(input$metadata_files) && length(input$metadata_files) > 0) {
      input$metadata_files
    } else if (is.character(plan$metadata_files) && length(plan$metadata_files) > 0) {
      plan$metadata_files
    } else {
      character(0)
    }
    metadata_keys <- setNames(vector("list", length(metadata_files)), metadata_files)

    for (f in metadata_files) {
      input_key <- input[[paste0("meta_key_", make.names(f))]]
      if (!is.null(input_key) && nzchar(input_key)) {
        metadata_keys[[f]] <- input_key
      } else if (is.data.frame(plan$join_suggestions) && nrow(plan$join_suggestions) > 0) {
        hit <- plan$join_suggestions[plan$join_suggestions$metadata_file == f, , drop = FALSE]
        if (nrow(hit) > 0) {
          metadata_keys[[f]] <- hit$metadata_key[[1]]
        } else {
          df <- available_files()[[f]]
          metadata_keys[[f]] <- names(df)[[1]]
        }
      } else {
        df <- available_files()[[f]]
        metadata_keys[[f]] <- names(df)[[1]]
      }
    }

    selected_strategy <- if (is.null(input$duplicate_strategy) || !nzchar(input$duplicate_strategy)) {
      "first_non_empty"
    } else {
      input$duplicate_strategy
    }

    conflicts <- find_duplicate_metadata_conflicts(
      data_list = files,
      metadata_files = metadata_files,
      metadata_keys = metadata_keys
    )

    duplicate_key_count <- count_duplicate_metadata_keys(
      data_list = files,
      metadata_files = metadata_files,
      metadata_keys = metadata_keys
    )

    if (identical(selected_strategy, "require_manual_resolution") && duplicate_key_count > 0) {
      stop(
        paste0(
          "Duplicate metadata keys detected (",
          duplicate_key_count,
          " keys, ",
          nrow(conflicts),
          " conflicting rows). Resolve duplicates in source files or choose a non-blocking duplicate strategy."
        )
      )
    }

    merged <- merge_uploaded_streams(
      data_list = files,
      primary_file = primary_file,
      primary_key = primary_key_val,
      metadata_files = metadata_files,
      metadata_keys = metadata_keys,
      duplicate_strategy = if (identical(selected_strategy, "require_manual_resolution")) "first_non_empty" else selected_strategy
    )

    audit <- audit_join_quality(
      data_list = files,
      primary_file = primary_file,
      primary_key = primary_key_val,
      metadata_files = metadata_files,
      metadata_keys = metadata_keys,
      duplicate_strategy = selected_strategy
    )

    list(merged = merged, audit = audit, conflicts = conflicts, duplicate_strategy = selected_strategy)
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
    # Only column names are needed — pass a zero-row stub to avoid copying the full dataset.
    suggest_dwc_mapping(combined_df()[0L, ], dictionary_path = resolve_dict_path("header_synonyms.csv"))
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
    req(join_audit())
    if (has_join_blockers(join_audit())) {
      blocker_tbl <- join_audit()[join_audit()$severity == "BLOCK", c("metadata_file", "join_cardinality", "detail"), drop = FALSE]
      stop(
        paste0(
          "Join blockers must be resolved before build. Blocking joins: ",
          paste(
            paste0(blocker_tbl$metadata_file, " (", blocker_tbl$join_cardinality, ")"),
            collapse = "; "
          )
        )
      )
    }

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
    build_bien_loading_table(dwc_df(), taxonomy_cap = taxonomy_lookup_cap)
  })

  taxonomy_df <- reactive({
    if (!is.null(build_state())) {
      df <- dwc_df()
      names_vec <- if ("scientificName" %in% names(df)) unique(df$scientificName) else character(0)
    } else {
      cs <- combined_state()
      if (!is.null(cs) && "scientificName" %in% names(cs$merged)) {
        names_vec <- unique(cs$merged$scientificName)
      } else {
        names_vec <- character(0)
      }
    }
    reconcile_taxonomy_local(names_vec)
  })

  # TNRS queries run only from the explicit "D Run BIEN Service Checks" action in Step 6.
  # No TNRS infrastructure is needed in Step 4 — local triage is instant.

  taxonomy_view_state <- reactive({
    tx <- taxonomy_df()

    # Step 4 is always the fast local triage path — no augment_bien_pipeline().
    # External TNRS calls are run only from the "Run BIEN Service Checks" action in Step 6.
    review_idx <- tx$status %in% c("REVIEW", "UNRESOLVED")
    review_tbl <- tx[review_idx, , drop = FALSE]
    total_review_rows <- nrow(review_tbl)

    metrics <- data.frame(
      metric = c("Total unique names", "Candidate for backbone check", "Needs review", "Unresolved (blank)"),
      value = c(
        nrow(tx),
        sum(tx$status == "CANDIDATE"),
        sum(tx$status == "REVIEW"),
        sum(tx$status == "UNRESOLVED")
      ),
      stringsAsFactors = FALSE
    )

    list(
      metrics = metrics,
      review_tbl = review_tbl,
      total_review_rows = total_review_rows
    )
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
    utils::head(join_conflicts(), 200)
  }, striped = TRUE, bordered = TRUE)

  output$join_warning_box <- renderUI({
    req(join_audit())
    audit <- join_audit()

    if (nrow(audit) == 0 || !any(audit$duplicate_metadata_collapse)) {
      return(NULL)
    }

    conflict_count <- nrow(join_conflicts())
    strategy <- if (!is.null(combined_state()$duplicate_strategy)) combined_state()$duplicate_strategy else "first_non_empty"
    tags$div(
      style = "margin: 8px 0 12px 0; padding: 12px; background: #fff3cd; border-left: 4px solid #b7791f;",
      strong("Duplicate metadata warning: "),
      paste0(
        "At least one metadata file has duplicate join keys. Current strategy: ", strategy, ". ",
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
    taxonomy_view_state()$metrics
  }, striped = TRUE, bordered = TRUE)

  output$taxonomy_review_note <- renderText({
    state <- taxonomy_view_state()
    paste0(
      "Review rows: ", state$total_review_rows,
      ". Names flagged REVIEW contain uncertain qualifiers (sp./cf./aff./indet.). ",
      "Use search, sorting, and pagination to inspect records quickly."
    )
  })

  output$taxonomy_cap_warning_ui <- renderUI({
    # Step 4 local triage processes all unique names — no cap applied here.
    NULL
  })

  output$taxonomy_review <- DT::renderDT({
    review_tbl <- taxonomy_view_state()$review_tbl

    if (nrow(review_tbl) > 0) {
      display_cols <- intersect(
        c("scientificName", "canonicalName", "status", "note"),
        names(review_tbl)
      )
      review_tbl_display <- review_tbl[, display_cols, drop = FALSE]
      names(review_tbl_display) <- gsub("_", " ", tools::toTitleCase(names(review_tbl_display)))
    } else {
      review_tbl_display <- review_tbl
    }

    DT::datatable(
      review_tbl_display,
      options = list(pageLength = 25, lengthMenu = c(25, 50, 100), autoWidth = TRUE),
      rownames = FALSE
    )
  }, server = TRUE)

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
    coord_ready <- if ("coordinate_valid_basic" %in% names(staging_preview_df())) count_basic_valid_coordinates(staging_preview_df()$coordinate_valid_basic) else 0
    taxonomy_unique_total <- if ("taxonomy_lookup_total_unique_names" %in% names(staging_preview_df())) unique(stats::na.omit(staging_preview_df()$taxonomy_lookup_total_unique_names))[1] else NA_integer_
    taxonomy_cap_msg <- if (!is.na(taxonomy_unique_total) && taxonomy_unique_total > taxonomy_lookup_cap) {
      paste0("Taxonomy lookup cap applied: first ", taxonomy_lookup_cap, " of ", taxonomy_unique_total, " unique names processed")
    } else {
      paste0("Taxonomy lookup coverage: ", ifelse(is.na(taxonomy_unique_total), "unknown", taxonomy_unique_total), " unique names")
    }

    paste(
      paste0("Loaded files: ", length(available_files())),
      paste0("Data mode: ", if (isTRUE(input$use_tutorial_data)) "Tutorial fake data" else "Uploaded files"),
      paste0("Metadata files joined: ", metadata_count),
      paste0("Combined rows (primary records): ", nrow(combined_df())),
      paste0("Join audit blockers: ", join_blockers, " | warnings: ", join_warnings),
      paste0("Join duplicate-conflict rows: ", join_conflict_rows),
      paste0("Mapped Darwin Core columns: ", ncol(dwc_df())),
      paste0("BIEN/backbone matched names: ", bien_matches),
      taxonomy_cap_msg,
      paste0("Rows with basic-valid coordinates: ", coord_ready),
      if (length(missing) == 0) "Required Darwin Core terms present: yes" else paste0("Missing required terms: ", paste(missing, collapse = ", ")),
      paste0("QC blockers: ", qc_blocks, " | warnings: ", qc_warns),
      if (qc_blocks > 0) "BIEN export blocked until BLOCK issues are fixed." else "Draft handoff tables generated.",
      "Service checks report processing state only; authoritative completion requires downstream expert/service review.",
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
    req(join_audit())
    if (bien_services_loading()) {
      return("BIEN Web Services are currently running. Export is available, but wait for the BIEN service run to complete if you want the latest TNRS/GNRS/GVS/NSR status before final submission.")
    }
    if (has_join_blockers(join_audit())) {
      return("Export blocked: resolve join cardinality BLOCK issues in Step 2 Link before final BIEN loading export.")
    }
    if (qc_has_blockers(qc_df())) {
      "Export blocked: resolve BLOCK issues in Step 5 Validate before BIEN loading export."
    } else {
      "Export ready: draft BIEN loading and TNRS/GNRS/GVS/NSR handoff files are available. Final authoritative reconciliation still requires downstream service and expert review."
    }
  })

  output$download_historical_template <- downloadHandler(
    filename = function() "historical_observation_import_template.zip",
    content = function(file) {
      packet_dir <- file.path(tempdir(), paste0("historical_template_", as.integer(Sys.time())))
      dir.create(packet_dir, recursive = TRUE, showWarnings = FALSE)

      obs_template <- data.frame(
        occurrenceID = c("hist-1", "hist-2"),
        Plot_Name = c("Plot_A", "Plot_B"),
        scientificName = c("Abies bracteata", "Pinus ponderosa"),
        eventDate = c("1912-06-10", "1912-06-11"),
        observer = c("A. Botanist", "A. Botanist"),
        stringsAsFactors = FALSE
      )

      plot_template <- data.frame(
        Plot_Name = c("Plot_A", "Plot_B"),
        decimalLatitude = c(35.321, 35.456),
        decimalLongitude = c(-120.123, -120.334),
        country = c("United States", "United States"),
        stateProvince = c("California", "California"),
        locality = c("Santa Lucia Range", "Santa Lucia Range"),
        stringsAsFactors = FALSE
      )

      instructions <- c(
        "Historical Observation Import Template",
        "",
        "Use case: Importing legacy field records into BIEN staging.",
        "",
        "1) Fill historical_observations.csv with one row per occurrence.",
        "2) Fill plot_location_metadata.csv with one row per Plot_Name.",
        "3) In the app, select historical_observations.csv as primary file.",
        "4) Join by Plot_Name and review Join Audit and conflict report.",
        "5) Run mapping + QC, then export BIEN and handoff tables."
      )

      utils::write.csv(obs_template, file.path(packet_dir, "historical_observations.csv"), row.names = FALSE)
      utils::write.csv(plot_template, file.path(packet_dir, "plot_location_metadata.csv"), row.names = FALSE)
      writeLines(instructions, file.path(packet_dir, "README_historical_import_template.txt"), useBytes = TRUE)

      old_wd <- setwd(packet_dir)
      on.exit(setwd(old_wd), add = TRUE)
      utils::zip(zipfile = file, files = list.files(packet_dir, all.files = FALSE))
    }
  )

  output$download_ecological_template <- downloadHandler(
    filename = function() "new_ecological_source_template.zip",
    content = function(file) {
      packet_dir <- file.path(tempdir(), paste0("ecological_template_", as.integer(Sys.time())))
      dir.create(packet_dir, recursive = TRUE, showWarnings = FALSE)

      source_template <- data.frame(
        source_record_id = c("src-1", "src-2"),
        occurrenceID = c("hist-1", "hist-2"),
        scientificName = c("Abies bracteata", "Pinus ponderosa"),
        traitName = c("plant_height", "leaf_area"),
        traitValue = c("14.2", "32.5"),
        traitUnit = c("m", "cm2"),
        measurementMethod = c("field_estimate", "digital_image"),
        sourceCitation = c("Example et al. 1950", "Example et al. 1950"),
        sourceLicense = c("CC-BY-4.0", "CC-BY-4.0"),
        stringsAsFactors = FALSE
      )

      provenance_template <- data.frame(
        source_name = "Archive field notebook",
        source_type = "trait_table",
        extraction_date = format(Sys.Date(), "%Y-%m-%d"),
        contact_email = "data_owner@example.org",
        citation = "Replace with full citation",
        license = "CC-BY-4.0",
        stringsAsFactors = FALSE
      )

      instructions <- c(
        "New Ecological Source Template",
        "",
        "Use case: Adding a new ecological dataset into BIEN staging.",
        "",
        "1) Fill new_ecological_source.csv with trait/environment records.",
        "2) Complete source_provenance.csv for citation, license, and contact.",
        "3) Upload alongside occurrence/location tables and map trait fields.",
        "4) Harmonize units before export and confirm provenance fields are complete.",
        "5) Export handoff tables and preserve packet manifest for audit trail."
      )

      utils::write.csv(source_template, file.path(packet_dir, "new_ecological_source.csv"), row.names = FALSE)
      utils::write.csv(provenance_template, file.path(packet_dir, "source_provenance.csv"), row.names = FALSE)
      writeLines(instructions, file.path(packet_dir, "README_new_ecological_source_template.txt"), useBytes = TRUE)

      old_wd <- setwd(packet_dir)
      on.exit(setwd(old_wd), add = TRUE)
      utils::zip(zipfile = file, files = list.files(packet_dir, all.files = FALSE))
    }
  )

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
    content = function(file) {
      ensure_join_clear_for_export(join_audit(), "BIEN Loading Draft")
      utils::write.csv(bien_df(), file, row.names = FALSE)
    }
  )

  output$download_tnrs <- downloadHandler(
    filename = function() "tnrs_handoff.csv",
    content = function(file) {
      ensure_join_clear_for_export(join_audit(), "TNRS Handoff")

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
    content = function(file) {
      ensure_join_clear_for_export(join_audit(), "GNRS Handoff")
      utils::write.csv(handoff()$gnrs, file, row.names = FALSE)
    }
  )

  output$download_gvs <- downloadHandler(
    filename = function() "gvs_handoff.csv",
    content = function(file) {
      ensure_join_clear_for_export(join_audit(), "GVS Handoff")
      utils::write.csv(handoff()$gvs, file, row.names = FALSE)
    }
  )

  output$download_nsr <- downloadHandler(
    filename = function() "nsr_handoff.csv",
    content = function(file) {
      ensure_join_clear_for_export(join_audit(), "NSR Handoff")
      utils::write.csv(handoff()$nsr, file, row.names = FALSE)
    }
  )

  output$download_submission_packet <- downloadHandler(
    filename = function() paste0("historical_obs_submission_packet_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".zip"),
    content = function(file) {
      ensure_join_clear_for_export(join_audit(), "Submission Packet Zip")

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
    req(build_state())
    req(staging_preview_df())
    req(join_audit())

    if (has_join_blockers(join_audit())) {
      bien_services_status("Cannot run BIEN service checks: resolve join BLOCK issues in Step 2 Link first.")
      return()
    }
    if (qc_has_blockers(qc_df())) {
      bien_services_status("Cannot run BIEN service checks: resolve QC BLOCK issues in Step 5 Validate first.")
      return()
    }

    bien_services_loading(TRUE)
    on.exit(bien_services_loading(FALSE), add = TRUE)

    stage_tbl <- staging_preview_df()
    if (!is.data.frame(stage_tbl) || nrow(stage_tbl) == 0) {
      bien_services_status("No staged records are available. Build BIEN draft tables first.")
      return()
    }

    bien_services_status("Starting BIEN web service workflow...")

    name_vec <- if ("scientificName" %in% names(stage_tbl)) {
      unique(trimws(as.character(stage_tbl$scientificName)))
    } else {
      character(0)
    }
    name_vec <- name_vec[!is.na(name_vec) & name_vec != ""]
    tnrs_name_cap <- 20L
    if (length(name_vec) > tnrs_name_cap) {
      name_vec <- name_vec[seq_len(tnrs_name_cap)]
      bien_services_status(
        paste0(
          "Starting BIEN web service workflow... TNRS capped to first ",
          tnrs_name_cap,
          " unique names for responsiveness."
        )
      )
    }

    coord_tbl <- stage_tbl[, intersect(c("decimalLatitude", "decimalLongitude"), names(stage_tbl)), drop = FALSE]
    gnrs_input <- tryCatch({
      gnrs_tbl <- build_bien_handoff_tables(stage_tbl)$gnrs
      gnrs_tbl[, intersect(c("country", "stateProvince", "county", "locality"), names(gnrs_tbl)), drop = FALSE]
    }, error = function(e) {
      data.frame(stringsAsFactors = FALSE)
    })

    # 1. TNRS
    bien_services_status("Running service-state checks: submitting names to TNRS...")
    tnrs_result <- tryCatch({
      bien_tnrs_query(name_vec, request_timeout = 6, max_names = tnrs_name_cap)
    }, error = function(e) e)

    # 2. GNRS
    bien_services_status("Submitting structured geography fields to GNRS...")
    gnrs_result <- tryCatch({
      bien_gnrs_query(gnrs_input)
    }, error = function(e) e)

    # 3. GVS
    bien_services_status("Submitting coordinates to GVS...")
    gvs_result <- tryCatch({
      bien_gvs_query(coord_tbl)
    }, error = function(e) e)

    # 4. NSR
    bien_services_status("Submitting names to NSR...")
    nsr_result <- tryCatch({
      bien_nsr_query(name_vec)
    }, error = function(e) e)

    bien_services_status(paste(
      "BIEN service-state run complete.",
      summarize_bien_service_state("TNRS", tnrs_result, authoritative = TRUE),
      summarize_bien_service_state("GNRS", gnrs_result, authoritative = FALSE),
      summarize_bien_service_state("GVS", gvs_result, authoritative = FALSE),
      summarize_bien_service_state("NSR", nsr_result, authoritative = FALSE),
      "Do not treat this stage as final authority. Complete downstream reconciliation and expert review before BIEN submission.",
      sep = "\n"
    ))
    # TODO: Integrate results into staging table and update UI/exports
  })
  output$bien_services_status <- renderText({ bien_services_status() })

  output$bien_services_loading_ui <- renderUI({
    if (!bien_services_loading()) return(NULL)
    tags$div(
      class = "bien-working-banner",
      style = "border-left-color: #b87c00;",
      tags$div(class = "bien-working-spinner spinner-border", style = "border-color: #b87c00; border-right-color: transparent;"),
      tags$span("Step 4: Running BIEN Web Services — please wait...")
    )
  })
}

shinyApp(ui = ui, server = server)
