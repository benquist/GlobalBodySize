# =============================================================================
# BIEN Historical Data Ingestion & Validation App - Redesign Prototype
# =============================================================================
# New app purpose: Multi-file data ingestion, schema mapping, validation,
# and preparation for BIEN submission.
# NOT a BIEN query/browsing app.
# =============================================================================

suppressPackageStartupMessages({
  required_packages <- c(
    "shiny", "shinyFiles", "shinyFeedback", "shinyjs",
    "dplyr", "tidyr", "stringr", "readxl", "data.table",
    "DT", "reactable",
    "leaflet", "sf",
    "ggplot2",
    "bs4Dash", "fresh"
  )
  
  missing_packages <- required_packages[!vapply(required_packages, 
                                                 requireNamespace, 
                                                 logical(1), 
                                                 quietly = TRUE)]
  if (length(missing_packages) > 0) {
    stop(paste("Missing packages:", paste(missing_packages, collapse = ", ")))
  }
  
  library(shiny)
  library(shinyFiles)
  library(shinyFeedback)
  library(shinyjs)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(readxl)
  library(data.table)
  library(DT)
  library(reactable)
  library(leaflet)
  library(sf)
  library(ggplot2)
  library(bs4Dash)
})

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Darwin Core field specification
darwin_core_spec <- list(
  required = c(
    "occurrenceID" = "Unique identifier for the occurrence record",
    "scientificName" = "Organism name (Genus species)",
    "eventDate" = "Date of observation (ISO 8601: YYYY-MM-DD)",
    "decimalLatitude" = "Latitude in decimal degrees (-90 to 90)",
    "decimalLongitude" = "Longitude in decimal degrees (-180 to 180)",
    "basisOfRecord" = "Type of record (PreservedSpecimen, Observation, Literature, etc.)"
  ),
  optional = c(
    "eventID" = "Plot/survey unit identifier",
    "coordinateUncertaintyInMeters" = "Positional accuracy in meters",
    "samplingProtocol" = "Method of observation collection",
    "samplingEffort" = "Effort expended (time, area, distance, etc.)",
    "individualCount" = "Number of individuals observed",
    "recordedBy" = "Collector/observer name",
    "identifiedBy" = "Taxonomist who identified organism",
    "eventRemarks" = "Notes about the survey event",
    "occurrenceRemarks" = "Notes about the occurrence",
    "datasetName" = "Name of the dataset/project",
    "accessRights" = "License/usage rights (CC0, CC-BY, etc.)"
  ),
  vocabulary = list(
    basisOfRecord = c("PreservedSpecimen", "FossilSpecimen", "Observation", 
                      "HumanObservation", "MachineObservation", "Occurrence", "Taxon"),
    occurrenceStatus = c("present", "absent")
  )
)

# Validate coordinate bounds
validate_coordinates <- function(lat, lon) {
  errors <- character(0)
  
  if (any(is.na(lat) | is.na(lon))) {
    errors <- c(errors, "Missing coordinates detected")
  }
  if (any(lat < -90 | lat > 90, na.rm = TRUE)) {
    errors <- c(errors, "Latitude outside valid range [-90, 90]")
  }
  if (any(lon < -180 | lon > 180, na.rm = TRUE)) {
    errors <- c(errors, "Longitude outside valid range [-180, 180]")
  }
  if (all(lat == 0 & lon == 0, na.rm = TRUE)) {
    errors <- c(errors, "All coordinates at (0,0) - likely placeholder")
  }
  
  list(valid = length(errors) == 0, errors = errors)
}

# Validate ISO 8601 dates
validate_dates <- function(date_col) {
  errors <- character(0)
  
  if (any(is.na(date_col))) {
    errors <- c(errors, "Missing dates detected")
  }
  
  # Try to parse as ISO 8601
  parsed <- tryCatch(
    lubridate::ymd(date_col),
    error = function(e) rep(NA, length(date_col))
  )
  
  if (any(is.na(parsed) & !is.na(date_col))) {
    errors <- c(errors, paste(sum(is.na(parsed) & !is.na(date_col)), 
                              "dates could not be parsed as YYYY-MM-DD"))
  }
  
  if (any(parsed > Sys.Date(), na.rm = TRUE)) {
    errors <- c(errors, "Some dates are in the future")
  }
  
  list(valid = length(errors) == 0, errors = errors)
}

# Detect likely foreign key columns for joining tables
detect_join_keys <- function(table1_colnames, table2_colnames) {
  # Common naming patterns for ID columns
  id_patterns <- c("id$", "ID$", "_id$", "_ID$", "key$", "code$", "num$")
  
  pot_keys_t1 <- grep(paste(id_patterns, collapse = "|"), table1_colnames, value = TRUE)
  pot_keys_t2 <- grep(paste(id_patterns, collapse = "|"), table2_colnames, value = TRUE)
  
  # Find common names
  common_keys <- intersect(pot_keys_t1, pot_keys_t2)
  
  list(
    table1_candidates = pot_keys_t1,
    table2_candidates = pot_keys_t2,
    likely_matches = common_keys
  )
}

# =============================================================================
# UI DEFINITION
# =============================================================================

ui <- dashboardPage(
  dashboardHeader(
    title = "BIEN Historical Data Ingest",
    leftUi = NULL
  ),
  
  dashboardSidebar(
    sidebarMenu(
      menuItem("Upload", tabName = "upload", icon = icon("upload")),
      menuItem("Link Files", tabName = "link", icon = icon("link")),
      menuItem("Schema Mapping", tabName = "schema", icon = icon("table")),
      menuItem("Taxonomic Resolution", tabName = "taxonomy", icon = icon("leaf")),
      menuItem("Validation Report", tabName = "validation", icon = icon("check-circle")),
      menuItem("Review & Export", tabName = "export", icon = icon("download")),
      hr(),
      menuItem("Help", tabName = "help", icon = icon("question-circle"))
    )
  ),
  
  dashboardBody(
    useShinyjs(),
    useFeedback(),
    
    tabItems(
      # ======================================================================
      # TAB 1: UPLOAD FILES
      # ======================================================================
      tabItem(
        tabName = "upload",
        h2("Step 1: Upload Your Data Files"),
        
        fluidRow(
          box(
            title = "File Upload", status = "primary", solidHeader = TRUE, width = 12,
            p("Upload CSV or Excel files containing your historical observation data. 
              You can upload multiple files at once."),
            
            fileInput(
              "uploaded_files",
              label = "Select files (CSV or XLSX)",
              multiple = TRUE,
              accept = c(".csv", ".xlsx", ".xls")
            ),
            
            actionButton("process_uploads", "Process Files", 
                        class = "btn-primary", size = "lg"),
            
            br(), br(),
            
            conditionalPanel(
              condition = "output.files_processed",
              
              h3("Uploaded Files"),
              DT::dataTableOutput("upload_summary_table"),
              
              br(),
              
              h3("File Preview"),
              uiOutput("file_preview_tabs")
            )
          )
        )
      ),
      
      # ======================================================================
      # TAB 2: LINK FILES
      # ======================================================================
      tabItem(
        tabName = "link",
        h2("Step 2: Link Related Files"),
        
        fluidRow(
          box(
            title = "Join Strategy", status = "primary", solidHeader = TRUE, width = 12,
            p("Connect your files using ID columns (e.g., plotID, siteID). 
              The app will suggest likely matches based on column names."),
            
            # Show file options for primary table
            selectInput("link_primary_table", 
                       label = "Primary table (usually observations):",
                       choices = character(0)),
            
            # Show detected join keys
            uiOutput("detected_join_keys_ui"),
            
            # Preview of joined result
            conditionalPanel(
              condition = "output.join_preview_ready",
              h4("Join Preview"),
              DT::dataTableOutput("join_preview_table")
            )
          )
        )
      ),
      
      # ======================================================================
      # TAB 3: SCHEMA MAPPING
      # ======================================================================
      tabItem(
        tabName = "schema",
        h2("Step 3: Map Columns to Darwin Core"),
        
        fluidRow(
          box(
            title = "Column Mapping", status = "primary", solidHeader = TRUE, width = 12,
            p("Map your data columns to the Darwin Core standard fields. 
              Required fields are marked with an asterisk (*)."),
            
            h4("Required Fields"),
            uiOutput("schema_mapping_required"),
            
            br(),
            
            h4("Optional Fields"),
            collapse = TRUE,
            uiOutput("schema_mapping_optional"),
            
            br(),
            
            # Mapping preview
            h4("Mapping Summary"),
            DT::dataTableOutput("mapping_summary_table")
          )
        )
      ),
      
      # ======================================================================
      # TAB 4: TAXONOMY
      # ======================================================================
      tabItem(
        tabName = "taxonomy",
        h2("Step 4: Resolve Species Names"),
        
        fluidRow(
          box(
            title = "Taxonomic Reconciliation", status = "primary", solidHeader = TRUE, 
            width = 12,
            
            p("Check species names against GBIF Backbone Taxonomy. 
              Names that don't match exactly will be flagged for review."),
            
            selectInput("taxonomy_backbone", 
                       label = "Taxonomic backbone:",
                       choices = c("GBIF Backbone (v2024-11)" = "gbif_2024-11",
                                  "Catalogue of Life (2024)" = "col_2024"),
                       selected = "gbif_2024-11"),
            
            actionButton("run_taxonomy_check", 
                        "Check Species Names", 
                        class = "btn-primary"),
            
            br(), br(),
            
            conditionalPanel(
              condition = "output.taxonomy_results_ready",
              
              h4("Reconciliation Results"),
              uiOutput("taxonomy_summary_ui"),
              
              br(),
              
              h4("Names Requiring Review"),
              DT::dataTableOutput("taxonomy_unresolved_table"),
              
              br(),
              
              h4("All Names"),
              DT::dataTableOutput("taxonomy_reconciliation_table")
            )
          )
        )
      ),
      
      # ======================================================================
      # TAB 5: VALIDATION
      # ======================================================================
      tabItem(
        tabName = "validation",
        h2("Step 5: Quality Validation Report"),
        
        fluidRow(
          box(
            title = "Data Quality Checks", status = "primary", solidHeader = TRUE, 
            width = 12,
            
            actionButton("run_validation", 
                        "Run Validation", 
                        class = "btn-primary"),
            
            br(), br(),
            
            conditionalPanel(
              condition = "output.validation_ready",
              
              h4("Validation Summary"),
              uiOutput("validation_summary_ui"),
              
              br(),
              
              # Tier 1: Blocking errors
              h4("Tier 1: Blocking Errors (must fix)"),
              DT::dataTableOutput("validation_tier1_table"),
              
              br(),
              
              # Tier 2: Warnings
              h4("Tier 2: Warnings (review)"),
              DT::dataTableOutput("validation_tier2_table"),
              
              br(),
              
              # Tier 3: Info
              h4("Tier 3: Information"),
              DT::dataTableOutput("validation_tier3_table"),
              
              br(),
              
              # Map of coordinates
              h4("Geographic Distribution"),
              leafletOutput("validation_map")
            )
          )
        )
      ),
      
      # ======================================================================
      # TAB 6: EXPORT
      # ======================================================================
      tabItem(
        tabName = "export",
        h2("Step 6: Review & Export"),
        
        fluidRow(
          box(
            title = "Pre-Submission Review", status = "primary", solidHeader = TRUE, 
            width = 12,
            
            h4("Data Summary"),
            uiOutput("export_summary_ui"),
            
            br(),
            
            h4("Metadata"),
            textInput("metadata_dataset_name", 
                     label = "Dataset name:",
                     placeholder = "e.g., 'Historical observations from Smith et al. (2010)'"),
            textInput("metadata_citation", 
                     label = "Citation:",
                     placeholder = "Author, Pub, DOI..."),
            selectInput("metadata_license", 
                       label = "Data license:",
                       choices = c("CC0 (Public Domain)" = "CC0",
                                  "CC-BY 4.0 (Attribution)" = "CC-BY-4.0",
                                  "CC-BY-SA 4.0" = "CC-BY-SA-4.0",
                                  "CC-BY-NC 4.0" = "CC-BY-NC-4.0")),
            
            br(),
            
            h4("Download"),
            p("Your data will be exported as Darwin Core-compliant TSV files, ready for BIEN submission."),
            
            downloadButton("download_darwin_core", "Download Darwin Core TSV", 
                          class = "btn-success btn-lg"),
            
            downloadButton("download_metadata", "Download Metadata YAML", 
                          class = "btn-info btn-lg")
          )
        )
      ),
      
      # ======================================================================
      # TAB 7: HELP
      # ======================================================================
      tabItem(
        tabName = "help",
        h2("Help & Documentation"),
        
        fluidRow(
          box(
            title = "How This App Works", width = 12,
            
            h4("Overview"),
            p("This app helps you prepare multi-file historical observation data for submission to BIEN. 
              It handles file linking, schema mapping, quality validation, and Darwin Core formatting."),
            
            h4("Step-by-Step Workflow"),
            tags$ol(
              tags$li("Upload your CSV/Excel files containing plot metadata, locations, and observations"),
              tags$li("Define how to link/join your files using ID columns"),
              tags$li("Map your column names to Darwin Core fields"),
              tags$li("Resolve species names against a taxonomic backbone"),
              tags$li("Review quality validation report; fix errors"),
              tags$li("Download Darwin Core-formatted data and metadata")
            ),
            
            h4("Common Formats We Expect"),
            
            h5("Plot Metadata File"),
            p("Columns: plotID, date, plotSize_m2, samplingProtocol, recordedBy, eventRemarks"),
            
            h5("Location/Site File"),
            p("Columns: siteID, siteName, decimalLatitude, decimalLongitude, elevation_m, habitat"),
            
            h5("Observations File"),
            p("Columns: occurrenceID, plotID, siteID, scientificName, individualCount, identificationRemarks"),
            
            h4("Darwin Core Standard"),
            p("See the 'Schema Mapping' tab for complete field definitions or visit:"),
            tags$a(href="https://dwc.tdwg.org/", "Darwin Core Terms ↗")
          )
        )
      )
    )
  )
)

# =============================================================================
# SERVER DEFINITION
# =============================================================================

server <- function(input, output, session) {
  
  # Reactive storage for uploaded data
  uploaded_data <- reactiveVal(NULL)
  file_metadata <- reactiveVal(NULL)
  joined_data <- reactiveVal(NULL)
  schema_mapping <- reactiveVal(NULL)
  taxonomy_results <- reactiveVal(NULL)
  validation_results <- reactiveVal(NULL)
  
  # -----------------------------------------------------------------------
  # TAB 1 SERVER: UPLOAD FILES
  # -----------------------------------------------------------------------
  
  observeEvent(input$process_uploads, {
    req(input$uploaded_files)
    
    files <- input$uploaded_files
    file_list <- list()
    metadata_list <- list()
    
    for (i in seq_len(nrow(files))) {
      filepath <- files$datapath[i]
      filename <- files$name[i]
      
      # Detect format and read
      if (str_ends(filename, "\\.xlsx") || str_ends(filename, "\\.xls")) {
        data <- read_excel(filepath)
        format <- "Excel"
      } else {
        data <- fread(filepath) %>% as.data.frame()
        format <- "CSV"
      }
      
      # Store data
      file_list[[filename]] <- data
      
      # Metadata
      metadata_list[[filename]] <- data.frame(
        filename = filename,
        format = format,
        nrow = nrow(data),
        ncol = ncol(data),
        colnames = paste(names(data), collapse = "; ")
      )
    }
    
    uploaded_data(file_list)
    file_metadata(do.call(rbind, metadata_list))
    
    # Update file selector in "Link Files" tab
    updateSelectInput(session, "link_primary_table",
                     choices = names(file_list))
  })
  
  output$files_processed <- reactive({
    !is.null(uploaded_data())
  })
  outputOptions(output, "files_processed", suspendWhenHidden = FALSE)
  
  output$upload_summary_table <- DT::renderDataTable({
    req(file_metadata())
    file_metadata()
  }, options = list(paging = FALSE, searching = FALSE, info = FALSE))
  
  output$file_preview_tabs <- renderUI({
    req(uploaded_data())
    
    tabs <- lapply(names(uploaded_data()), function(filename) {
      tabPanel(
        filename,
        br(),
        DT::dataTableOutput(paste0("preview_", filename))
      )
    })
    
    do.call(tabsetPanel, tabs)
  })
  
  # Create preview tables for each uploaded file
  observe({
    req(uploaded_data())
    
    for (filename in names(uploaded_data())) {
      local({
        local_filename <- filename
        output[[paste0("preview_", local_filename)]] <- 
          DT::renderDataTable({
            uploaded_data()[[local_filename]] %>% 
              slice(1:min(100, n()))  # Show first 100 rows
          }, options = list(scrollX = TRUE, pageLength = 10))
      })
    }
  })
  
  # -----------------------------------------------------------------------
  # TAB 2 SERVER: LINK FILES
  # -----------------------------------------------------------------------
  
  output$detected_join_keys_ui <- renderUI({
    req(input$link_primary_table, uploaded_data())
    
    primary <- uploaded_data()[[input$link_primary_table]]
    other_files <- setdiff(names(uploaded_data()), input$link_primary_table)
    
    if (length(other_files) == 0) {
      return(p("Only one file uploaded. No linking needed."))
    }
    
    lapply(other_files, function(secondary_file) {
      keys <- detect_join_keys(names(primary), 
                               names(uploaded_data()[[secondary_file]]))
      
      tagList(
        h4(paste("Join with:", secondary_file)),
        
        if (length(keys$likely_matches) > 0) {
          tagList(
            p(strong("Suggested join keys:"),
              paste(keys$likely_matches, collapse = ", ")),
            selectInput(
              paste0("join_key_", input$link_primary_table, "_", secondary_file),
              label = "Select join key:",
              choices = keys$likely_matches
            )
          )
        } else {
          selectInput(
            paste0("join_key_", input$link_primary_table, "_", secondary_file),
            label = "Select column from primary table:",
            choices = names(primary)
          )
        }
      )
    })
  })
  
  output$join_preview_ready <- reactive({
    !is.null(joined_data())
  })
  outputOptions(output, "join_preview_ready", suspendWhenHidden = FALSE)
  
  output$join_preview_table <- DT::renderDataTable({
    req(joined_data())
    joined_data() %>% slice(1:min(50, n()))
  }, options = list(scrollX = TRUE, pageLength = 10))
  
  # -----------------------------------------------------------------------
  # TAB 3 SERVER: SCHEMA MAPPING
  # -----------------------------------------------------------------------
  
  output$schema_mapping_required <- renderUI({
    req(joined_data())
    
    colnames_available <- names(joined_data())
    
    lapply(names(darwin_core_spec$required), function(dc_field) {
      selectInput(
        paste0("map_", dc_field),
        label = paste0(dc_field, " *"),
        choices = c("(Not mapped)" = "", colnames_available),
        selected = ""
      )
    })
  })
  
  output$schema_mapping_optional <- renderUI({
    req(joined_data())
    
    colnames_available <- names(joined_data())
    
    lapply(names(darwin_core_spec$optional), function(dc_field) {
      selectInput(
        paste0("map_", dc_field),
        label = dc_field,
        choices = c("(Not mapped)" = "", colnames_available),
        selected = ""
      )
    })
  })
  
  output$mapping_summary_table <- DT::renderDataTable({
    # Collect all mapping inputs
    all_dc_fields <- c(names(darwin_core_spec$required), 
                       names(darwin_core_spec$optional))
    
    mapping_df <- data.frame(
      darwin_core_field = all_dc_fields,
      your_column = sapply(all_dc_fields, function(f) {
        input[[paste0("map_", f)]] %||% "(Not mapped)"
      }),
      required = c(rep("Yes", length(darwin_core_spec$required)),
                   rep("No", length(darwin_core_spec$optional))),
      row.names = NULL
    )
    
    mapping_df
  }, options = list(paging = FALSE, searching = FALSE))
  
  # -----------------------------------------------------------------------
  # TAB 5 SERVER: VALIDATION
  # -----------------------------------------------------------------------
  
  observeEvent(input$run_validation, {
    req(joined_data())
    
    data <- joined_data()
    issues <- list(tier1 = list(), tier2 = list(), tier3 = list())
    
    # TIER 1: Required fields missing
    required_fields <- c("scientificName", "eventDate", "decimalLatitude", 
                        "decimalLongitude", "basisOfRecord", "occurrenceID")
    
    for (field in required_fields) {
      if (! field %in% names(data)) {
        issues$tier1[[length(issues$tier1) + 1]] <- 
          list(issue = "MISSING FIELD", field = field, count = NA, severity = "BLOCKING")
      } else {
        missing_count <- sum(is.na(data[[field]]))
        if (missing_count > 0) {
          issues$tier1[[length(issues$tier1) + 1]] <- 
            list(issue = "MISSING VALUES", field = field, count = missing_count, 
                 severity = "BLOCKING")
        }
      }
    }
    
    # TIER 1: Coordinate validation
    if ("decimalLatitude" %in% names(data) && "decimalLongitude" %in% names(data)) {
      coord_check <- validate_coordinates(data$decimalLatitude, data$decimalLongitude)
      if (!coord_check$valid) {
        issues$tier1[[length(issues$tier1) + 1]] <- 
          list(issue = "COORDINATE ERROR", field = "coordinates", 
               count = length(coord_check$errors), severity = "BLOCKING")
      }
    }
    
    # TIER 2: Warnings
    if ("eventDate" %in% names(data)) {
      date_check <- validate_dates(data$eventDate)
      if (!date_check$valid) {
        issues$tier2[[length(issues$tier2) + 1]] <- 
          list(issue = "DATE WARNING", field = "eventDate", count = 1, severity = "WARNING")
      }
    }
    
    # Store results
    validation_results(list(
      tier1 = do.call(rbind, c(issues$tier1, list(stringsAsFactors = FALSE))),
      tier2 = do.call(rbind, c(issues$tier2, list(stringsAsFactors = FALSE))),
      tier3 = do.call(rbind, c(issues$tier3, list(stringsAsFactors = FALSE)))
    ))
  })
  
  output$validation_ready <- reactive({
    !is.null(validation_results())
  })
  outputOptions(output, "validation_ready", suspendWhenHidden = FALSE)
  
  output$validation_summary_ui <- renderUI({
    req(validation_results())
    
    results <- validation_results()
    n_tier1 <- if (!is.null(results$tier1)) nrow(results$tier1) else 0
    n_tier2 <- if (!is.null(results$tier2)) nrow(results$tier2) else 0
    n_tier3 <- if (!is.null(results$tier3)) nrow(results$tier3) else 0
    
    tagList(
      if (n_tier1 == 0) {
        tags$span(style = "color: green;", icon("check-circle"), " No blocking errors")
      } else {
        tags$span(style = "color: red;", 
                 icon("exclamation-triangle"), paste(n_tier1, "blocking errors"))
      },
      br(),
      if (n_tier2 > 0) {
        tags$span(style = "color: orange;", 
                 icon("exclamation-circle"), paste(n_tier2, "warnings"))
      }
    )
  })
  
  output$validation_tier1_table <- DT::renderDataTable({
    req(validation_results())
    validation_results()$tier1
  }, options = list(paging = FALSE))
  
  output$validation_tier2_table <- DT::renderDataTable({
    req(validation_results())
    validation_results()$tier2
  }, options = list(paging = FALSE))
  
  output$validation_tier3_table <- DT::renderDataTable({
    req(validation_results())
    validation_results()$tier3
  }, options = list(paging = FALSE))
  
  output$validation_map <- renderLeaflet({
    req(joined_data())
    
    data <- joined_data()
    
    if ("decimalLatitude" %in% names(data) && "decimalLongitude" %in% names(data)) {
      data_mapped <- data %>%
        filter(!is.na(decimalLatitude), !is.na(decimalLongitude)) %>%
        filter(decimalLatitude >= -90, decimalLatitude <= 90,
               decimalLongitude >= -180, decimalLongitude <= 180)
      
      if (nrow(data_mapped) > 0) {
        leaflet(data_mapped) %>%
          addTiles() %>%
          addCircleMarkers(
            ~decimalLongitude, ~decimalLatitude,
            radius = 5, opacity = 0.7,
            popup = ~paste0("<b>", scientificName, "</b><br>",
                           eventDate)
          )
      } else {
        leaflet() %>% addTiles() %>%
          setView(lng = 0, lat = 0, zoom = 2)
      }
    } else {
      leaflet() %>% addTiles() %>%
        setView(lng = 0, lat = 0, zoom = 2)
    }
  })
}

# Run the application
shinyApp(ui, server)
