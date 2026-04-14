for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) {
  source(f, local = TRUE)
}

library(shiny)

ui <- fluidPage(
  titlePanel("Loading Historical Observation Data into BIEN"),
  sidebarLayout(
    sidebarPanel(
      fileInput("input_csv", "Upload Historical Observation CSV", accept = ".csv"),
      actionButton("suggest_btn", "Suggest Mapping"),
      tags$hr(),
      fileInput("mapping_csv", "Optional Mapping Override CSV", accept = ".csv"),
      actionButton("build_btn", "Build BIEN Outputs"),
      tags$hr(),
      downloadButton("download_bien", "Download BIEN Loading Table"),
      downloadButton("download_tnrs", "Download TNRS Handoff"),
      downloadButton("download_gnrs", "Download GNRS Handoff"),
      downloadButton("download_gvs", "Download GVS Handoff"),
      downloadButton("download_nsr", "Download NSR Handoff")
    ),
    mainPanel(
      h4("Mapping Suggestions"),
      tableOutput("mapping_table"),
      h4("Build Summary"),
      verbatimTextOutput("summary_text"),
      h4("BIEN Loading Preview"),
      tableOutput("bien_preview")
    )
  )
)

server <- function(input, output, session) {
  raw_df <- reactive({
    req(input$input_csv)
    read_historical_csv(input$input_csv$datapath)
  })

  suggested_mapping <- eventReactive(input$suggest_btn, {
    suggest_dwc_mapping(raw_df(), dictionary_path = "inst/dictionaries/header_synonyms.csv")
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

  dwc_df <- eventReactive(input$build_btn, {
    apply_dwc_mapping(raw_df(), active_mapping())
  })

  bien_df <- eventReactive(input$build_btn, {
    build_bien_loading_table(dwc_df())
  })

  handoff <- eventReactive(input$build_btn, {
    build_bien_handoff_tables(dwc_df())
  })

  output$mapping_table <- renderTable({
    req(suggested_mapping())
    suggested_mapping()
  }, striped = TRUE, bordered = TRUE)

  output$summary_text <- renderText({
    req(bien_df())
    req(active_mapping())

    req_terms <- required_dwc_terms()
    missing <- setdiff(req_terms, names(dwc_df()))

    paste(
      paste0("Input rows: ", nrow(raw_df())),
      paste0("Mapped Darwin Core columns: ", ncol(dwc_df())),
      if (length(missing) == 0) "Required Darwin Core terms present: yes" else paste0("Missing required terms: ", paste(missing, collapse = ", ")),
      "TNRS/GNRS/GVS/NSR handoff tables generated.",
      sep = "\n"
    )
  })

  output$bien_preview <- renderTable({
    req(bien_df())
    utils::head(bien_df(), 10)
  }, striped = TRUE, bordered = TRUE)

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
