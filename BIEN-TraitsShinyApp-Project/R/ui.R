app_ui <- fluidPage(
  titlePanel("BIEN Traits Shiny App Project"),
  sidebarLayout(
    sidebarPanel(
      textAreaInput(
        "species_text",
        "Species list (one per line)",
        value = "Pinus ponderosa",
        rows = 8
      ),
      numericInput("max_records", "Max records per species", value = 5000, min = 100, max = 50000, step = 100),
      actionButton("run_query", "Query BIEN", class = "btn-primary"),
      tags$hr(),
      downloadButton("download_traits", "Download traits CSV")
    ),
    mainPanel(
      tabsetPanel(
        tabPanel("Status", verbatimTextOutput("query_status")),
        tabPanel("Traits", DTOutput("trait_table")),
        tabPanel("Map", leafletOutput("trait_map", height = 520)),
        tabPanel("Help", tags$p("Starter project scaffold. Extend this with full coverage/citations/reproducibility workflows."))
      )
    )
  )
)
