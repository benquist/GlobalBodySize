suppressPackageStartupMessages({
  required_packages <- c("shiny", "BIEN", "dplyr", "stringr", "leaflet", "DT", "sf")
  missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing_packages) > 0) {
    install.packages(missing_packages, repos = "https://cloud.r-project.org")
  }

  library(shiny)
  library(BIEN)
  library(dplyr)
  library(stringr)
  library(leaflet)
  library(DT)
  library(sf)
})

safe_bien_call <- function(expr, timeout_sec = 90) {
  on.exit(setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE), add = TRUE)
  setTimeLimit(elapsed = timeout_sec, transient = TRUE)
  tryCatch(expr, error = function(e) e)
}

find_first_col <- function(df, candidates) {
  if (!is.data.frame(df) || nrow(df) == 0) {
    return(NULL)
  }

  hits <- candidates[candidates %in% names(df)]
  if (length(hits) > 0) {
    return(hits[[1]])
  }

  lower_names <- tolower(names(df))
  for (candidate in candidates) {
    idx <- which(lower_names == tolower(candidate))
    if (length(idx) > 0) {
      return(names(df)[idx[[1]]])
    }
  }

  NULL
}

prepare_occurrences <- function(occ) {
  if (!is.data.frame(occ) || nrow(occ) == 0) {
    return(list(data = NULL, lat_col = NULL, lon_col = NULL, qa = list(total = 0, kept = 0, removed = 0)))
  }

  lat_col <- find_first_col(occ, c("latitude", "decimal_latitude", "lat"))
  lon_col <- find_first_col(occ, c("longitude", "decimal_longitude", "lon", "long"))

  if (is.null(lat_col) || is.null(lon_col)) {
    return(list(data = occ, lat_col = NULL, lon_col = NULL, qa = list(total = nrow(occ), kept = nrow(occ), removed = 0)))
  }

  occ[[lat_col]] <- suppressWarnings(as.numeric(occ[[lat_col]]))
  occ[[lon_col]] <- suppressWarnings(as.numeric(occ[[lon_col]]))

  total_n <- nrow(occ)

  occ <- occ %>%
    filter(!is.na(.data[[lat_col]]), !is.na(.data[[lon_col]])) %>%
    filter(.data[[lat_col]] >= -90, .data[[lat_col]] <= 90) %>%
    filter(.data[[lon_col]] >= -180, .data[[lon_col]] <= 180)

  species_col <- find_first_col(occ, c("scrubbed_species_binomial", "species", "scientific_name", "taxon"))
  if (!is.null(species_col)) {
    occ <- occ %>% distinct(.data[[species_col]], .data[[lat_col]], .data[[lon_col]], .keep_all = TRUE)
  } else {
    occ <- occ %>% distinct(.data[[lat_col]], .data[[lon_col]], .keep_all = TRUE)
  }

  kept_n <- nrow(occ)

  list(data = occ, lat_col = lat_col, lon_col = lon_col, qa = list(total = total_n, kept = kept_n, removed = total_n - kept_n))
}

make_popup_text <- function(df) {
  species_col <- find_first_col(df, c("scrubbed_species_binomial", "species", "scientific_name", "taxon"))
  country_col <- find_first_col(df, c("country", "country_name"))
  state_col <- find_first_col(df, c("state_province", "state"))
  source_col <- find_first_col(df, c("datasource", "data_source", "collection", "source"))

  species_txt <- if (!is.null(species_col)) df[[species_col]] else "record"
  country_txt <- if (!is.null(country_col)) df[[country_col]] else NA_character_
  state_txt <- if (!is.null(state_col)) df[[state_col]] else NA_character_
  source_txt <- if (!is.null(source_col)) df[[source_col]] else NA_character_

  paste0(
    "<strong>", species_txt, "</strong>",
    ifelse(!is.na(country_txt), paste0("<br>Country: ", country_txt), ""),
    ifelse(!is.na(state_txt), paste0("<br>Region: ", state_txt), ""),
    ifelse(!is.na(source_txt), paste0("<br>Source: ", source_txt), "")
  )
}

summarize_range_object <- function(x) {
  if (inherits(x, "error")) {
    return(list(kind = "error", text = conditionMessage(x), data = NULL))
  }

  if (is.null(x)) {
    return(list(kind = "empty", text = "No range object returned.", data = NULL))
  }

  if (inherits(x, "sf")) {
    return(list(kind = "sf", text = NULL, data = x))
  }

  if (is.data.frame(x)) {
    return(list(kind = "table", text = NULL, data = x))
  }

  if (is.list(x)) {
    return(list(kind = "list", text = paste(capture.output(str(x, max.level = 1)), collapse = "\n"), data = x))
  }

  list(kind = "other", text = paste(capture.output(str(x)), collapse = "\n"), data = x)
}

read_downloaded_range_sf <- function(range_dir, species_name) {
  if (is.null(range_dir) || !dir.exists(range_dir)) {
    return(NULL)
  }

  species_key <- gsub("\\s+", "_", species_name)
  shp_files <- list.files(range_dir, pattern = "\\.shp$", full.names = TRUE)
  specific <- shp_files[grepl(species_key, basename(shp_files), fixed = TRUE)]
  if (length(specific) > 0) {
    shp_files <- specific
  }
  if (length(shp_files) == 0) {
    return(NULL)
  }

  sf_obj <- tryCatch(st_read(shp_files[[1]], quiet = TRUE), error = function(e) NULL)
  if (!is.null(sf_obj)) {
    sf_obj <- tryCatch(st_transform(sf_obj, 4326), error = function(e) sf_obj)
  }
  sf_obj
}

build_reconciliation_table <- function(species_name, occ, traits, query_errors, range_obj) {
  occ_sp_col <- if (is.data.frame(occ)) find_first_col(occ, c("scrubbed_species_binomial", "species", "scientific_name")) else NULL
  trait_sp_col <- if (is.data.frame(traits)) find_first_col(traits, c("scrubbed_species_binomial", "species", "scientific_name")) else NULL

  occ_species <- if (!is.null(occ_sp_col)) unique(na.omit(as.character(occ[[occ_sp_col]]))) else character()
  trait_species <- if (!is.null(trait_sp_col)) unique(na.omit(as.character(traits[[trait_sp_col]]))) else character()
  matched_species <- unique(c(occ_species, trait_species))

  if (length(matched_species) == 0) matched_species <- NA_character_

  tibble(
    input_name_verbatim = species_name,
    input_name_normalized = str_squish(species_name),
    matched_name = matched_species,
    matched_authorship = NA_character_,
    matched_rank = "species",
    matched_taxon_id = NA_character_,
    matched_backbone = "BIEN",
    matched_status = case_when(
      length(query_errors) > 0 ~ "error",
      is.na(matched_species) ~ "unresolved",
      matched_species == str_squish(species_name) ~ "accepted_or_exact",
      TRUE ~ "matched_non_exact"
    ),
    accepted_name = matched_species,
    accepted_taxon_id = NA_character_,
    synonym_type = NA_character_,
    match_method = ifelse(is.na(matched_species), "none", "BIEN_returned_taxon"),
    match_confidence = ifelse(is.na(matched_species), "low", "medium"),
    decision_note = paste(
      c(
        if (inherits(range_obj, "error")) paste("Range error:", conditionMessage(range_obj)) else NULL,
        if (length(query_errors) > 0) paste("Query error(s):", paste(query_errors, collapse = " | ")) else NULL
      ),
      collapse = " ; "
    ),
    query_timestamp_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    backbone_version_or_release = as.character(utils::packageVersion("BIEN"))
  )
}

ui <- fluidPage(
  titlePanel("BIEN Shiny App: Species-Level Observation Explorer"),
  sidebarLayout(
    sidebarPanel(
      textInput("species", "Species name", value = "Eschscholzia californica", placeholder = "Genus species"),
      actionButton("run_query", "Query BIEN", class = "btn-primary"),
      tags$hr(),
      checkboxInput("natives_only", "Native records only", value = TRUE),
      checkboxInput("include_cultivated", "Include cultivated records", value = FALSE),
      checkboxInput("only_geovalid", "Only geovalid coordinates", value = TRUE),
      numericInput("occurrence_limit", "Max occurrence records", value = 5000, min = 500, max = 50000, step = 500),
      numericInput("trait_limit", "Max trait records", value = 5000, min = 200, max = 50000, step = 200),
      checkboxInput("include_range_query", "Run range query (can be slower)", value = TRUE),
      numericInput("query_timeout", "Query timeout (seconds)", value = 60, min = 15, max = 300, step = 15),
      selectInput(
        "map_scale",
        "Map scale",
        choices = c("Auto fit" = "auto", "World" = "world", "Regional" = "regional", "Local" = "local"),
        selected = "auto"
      ),
      width = 3,
      tags$hr(),
      h4("Useful species-level exploration questions"),
      tags$ul(
        tags$li("Where are the known observation records, and how clustered or sparse are they?"),
        tags$li("Which traits are available for this species, and from how many records or sources?"),
        tags$li("Do occurrence records span multiple geographic scales, countries, or habitats?"),
        tags$li("Is BIEN returning a geographic range object or only occurrence-level evidence?"),
        tags$li("Which observations might require QA for outliers or questionable coordinates?")
      )
    ),
    mainPanel(
      tabsetPanel(
        tabPanel(
          "Overview",
          br(),
          htmlOutput("query_summary"),
          br(),
          leafletOutput("occurrence_map", height = 550)
        ),
        tabPanel("Observation Table", br(), DTOutput("occurrence_table")),
        tabPanel("Traits", br(), DTOutput("trait_table")),
        tabPanel("Trait Summary", br(), DTOutput("trait_summary_table")),
        tabPanel("Range", br(), verbatimTextOutput("range_text"), leafletOutput("range_map", height = 500), br(), DTOutput("range_table")),
        tabPanel("Reconciliation", br(), DTOutput("reconciliation_table"), br(), verbatimTextOutput("error_log"))
      ),
      width = 9
    )
  )
)

server <- function(input, output, session) {
  bien_results <- eventReactive(input$run_query, {
    req(nchar(str_trim(input$species)) > 0)

    species_name <- str_squish(input$species)
    timeout_sec <- max(15, as.numeric(input$query_timeout))
    occ_limit <- max(500, as.numeric(input$occurrence_limit))
    trait_limit <- max(200, as.numeric(input$trait_limit))
    occ_page_size <- min(2000, occ_limit)
    trait_page_size <- min(2000, trait_limit)
    range_dir <- file.path(tempdir(), "bien_ranges_cache", gsub("\\s+", "_", species_name))
    dir.create(range_dir, recursive = TRUE, showWarnings = FALSE)

    withProgress(message = paste("Querying BIEN for", species_name), value = 0, {
      incProgress(0.2, detail = "Occurrences")
      occ <- safe_bien_call(
        BIEN_occurrence_species(
          species = species_name,
          cultivated = input$include_cultivated,
          all.taxonomy = TRUE,
          native.status = TRUE,
          natives.only = input$natives_only,
          political.boundaries = FALSE,
          collection.info = FALSE,
          only.geovalid = input$only_geovalid,
          limit = occ_limit,
          record_limit = occ_page_size,
          fetch.query = FALSE
        ),
        timeout_sec = timeout_sec
      )
      occ_error <- if (inherits(occ, "error")) conditionMessage(occ) else NULL

      incProgress(0.5, detail = "Traits")
      traits <- safe_bien_call(
        BIEN_trait_species(
          species = species_name,
          all.taxonomy = TRUE,
          source.citation = TRUE,
          limit = trait_limit,
          record_limit = trait_page_size,
          fetch.query = FALSE
        ),
        timeout_sec = timeout_sec
      )
      traits_error <- if (inherits(traits, "error")) conditionMessage(traits) else NULL
      if (is.data.frame(traits)) {
        names(traits) <- make.unique(names(traits))
      }

      incProgress(0.8, detail = "Ranges")
      ranges <- if (isTRUE(input$include_range_query)) {
        safe_bien_call(
          BIEN_ranges_species(
            species = species_name,
            directory = range_dir,
            matched = TRUE,
            match_names_only = FALSE,
            include.gid = TRUE,
            limit = 25,
            record_limit = 25,
            fetch.query = FALSE
          ),
          timeout_sec = timeout_sec
        )
      } else {
        data.frame(note = "Range query skipped by user setting")
      }
      range_error <- if (inherits(ranges, "error")) conditionMessage(ranges) else NULL

      range_sf <- read_downloaded_range_sf(range_dir, species_name)
      occ_prepared <- if (is.data.frame(occ)) prepare_occurrences(occ) else list(data = NULL, lat_col = NULL, lon_col = NULL, qa = list(total = 0, kept = 0, removed = 0))

      query_errors <- c(occ_error, traits_error, range_error)
      query_errors <- query_errors[!is.na(query_errors)]
      reconciliation_tbl <- build_reconciliation_table(species_name, occ, traits, query_errors, ranges)

      incProgress(1, detail = "Done")

      list(
        species = species_name,
        occurrences = occ,
        occurrences_prepared = occ_prepared,
        traits = traits,
        ranges = ranges,
        range_sf = range_sf,
        range_dir = range_dir,
        timeout_sec = timeout_sec,
        occ_limit = occ_limit,
        trait_limit = trait_limit,
        query_errors = query_errors,
        reconciliation = reconciliation_tbl
      )
    })
  }, ignoreNULL = FALSE)

  output$query_summary <- renderUI({
    res <- bien_results()

    occ_n <- if (is.data.frame(res$occurrences)) nrow(res$occurrences) else 0
    trait_n <- if (is.data.frame(res$traits)) nrow(res$traits) else 0
    range_status <- if (inherits(res$ranges, "error")) {
      "Range query returned an error"
    } else if (is.null(res$ranges)) {
      "No range result returned"
    } else if (inherits(res$range_sf, "sf") && nrow(res$range_sf) > 0) {
      paste("Range polygon loaded from", res$range_dir)
    } else {
      paste("Range result type:", paste(class(res$ranges), collapse = ", "))
    }

    HTML(paste0(
      "<strong>Species:</strong> ", res$species,
      "<br><strong>Observation records:</strong> ", occ_n,
      "<br><strong>Observation records after QA:</strong> ", res$occurrences_prepared$qa$kept,
      "<br><strong>Observation records removed by QA:</strong> ", res$occurrences_prepared$qa$removed,
      "<br><strong>Trait records:</strong> ", trait_n,
      "<br><strong>Query timeout:</strong> ", res$timeout_sec, " sec",
      "<br><strong>Occurrence limit:</strong> ", res$occ_limit,
      "<br><strong>Trait limit:</strong> ", res$trait_limit,
      "<br><strong>Range query status:</strong> ", range_status
    ))
  })

  output$occurrence_map <- renderLeaflet({
    res <- bien_results()
    occ_info <- res$occurrences_prepared

    map <- leaflet() %>% addProviderTiles(providers$CartoDB.Positron)

    if (is.null(occ_info$data) || nrow(occ_info$data) == 0 || is.null(occ_info$lat_col) || is.null(occ_info$lon_col)) {
      return(map %>% setView(lng = 0, lat = 20, zoom = 2))
    }

    df <- occ_info$data
    lat_col <- occ_info$lat_col
    lon_col <- occ_info$lon_col

    map <- map %>% addCircleMarkers(
      lng = df[[lon_col]],
      lat = df[[lat_col]],
      radius = 4,
      stroke = FALSE,
      fillOpacity = 0.7,
      popup = make_popup_text(df)
    )

    if (input$map_scale == "world") {
      map %>% setView(lng = 0, lat = 20, zoom = 2)
    } else if (input$map_scale == "regional") {
      map %>% setView(
        lng = mean(df[[lon_col]], na.rm = TRUE),
        lat = mean(df[[lat_col]], na.rm = TRUE),
        zoom = 4
      )
    } else if (input$map_scale == "local") {
      map %>% setView(
        lng = mean(df[[lon_col]], na.rm = TRUE),
        lat = mean(df[[lat_col]], na.rm = TRUE),
        zoom = 7
      )
    } else {
      map %>% fitBounds(
        lng1 = min(df[[lon_col]], na.rm = TRUE),
        lat1 = min(df[[lat_col]], na.rm = TRUE),
        lng2 = max(df[[lon_col]], na.rm = TRUE),
        lat2 = max(df[[lat_col]], na.rm = TRUE)
      )
    }
  })

  output$occurrence_table <- renderDT({
    res <- bien_results()
    if (inherits(res$occurrences, "error")) {
      return(datatable(data.frame(message = paste("Occurrence query error:", conditionMessage(res$occurrences))), options = list(dom = "t"), rownames = FALSE))
    }
    if (!is.data.frame(res$occurrences)) {
      return(datatable(data.frame(message = "No occurrence table returned."), options = list(dom = "t"), rownames = FALSE))
    }
    datatable(res$occurrences, filter = "top", options = list(pageLength = 10, scrollX = TRUE))
  })

  output$trait_table <- renderDT({
    res <- bien_results()
    if (inherits(res$traits, "error")) {
      return(datatable(data.frame(message = paste("Trait query error:", conditionMessage(res$traits))), options = list(dom = "t"), rownames = FALSE))
    }
    if (!is.data.frame(res$traits)) {
      return(datatable(data.frame(message = "No trait table returned."), options = list(dom = "t"), rownames = FALSE))
    }
    datatable(res$traits, filter = "top", options = list(pageLength = 10, scrollX = TRUE))
  })

  output$trait_summary_table <- renderDT({
    res <- bien_results()
    if (!is.data.frame(res$traits) || nrow(res$traits) == 0) {
      return(datatable(data.frame(message = "No trait records available for summary."), options = list(dom = "t"), rownames = FALSE))
    }

    trait_name_col <- find_first_col(res$traits, c("trait_name", "trait"))
    trait_value_col <- find_first_col(res$traits, c("trait_value", "value"))
    unit_col <- find_first_col(res$traits, c("unit", "units"))

    if (is.null(trait_name_col) || is.null(trait_value_col)) {
      return(datatable(data.frame(message = "Trait schema not recognized."), options = list(dom = "t"), rownames = FALSE))
    }

    summary_tbl <- res$traits %>%
      mutate(
        trait_name_std = .data[[trait_name_col]],
        trait_value_std = as.character(.data[[trait_value_col]]),
        unit_std = if (!is.null(unit_col)) as.character(.data[[unit_col]]) else NA_character_
      ) %>%
      group_by(trait_name_std, unit_std) %>%
      summarise(
        n_records = n(),
        example_values = paste(utils::head(unique(trait_value_std), 5), collapse = " | "),
        .groups = "drop"
      ) %>%
      arrange(desc(n_records), trait_name_std)

    datatable(summary_tbl, options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
  })

  output$range_text <- renderText({
    res <- bien_results()
    range_info <- summarize_range_object(res$ranges)

    if (range_info$kind == "error") {
      return(paste("Range query error:", range_info$text))
    }
    if (inherits(res$range_sf, "sf") && nrow(res$range_sf) > 0) {
      return("Range shapefile downloaded and mapped below. You can zoom/pan to inspect extent.")
    }
    if (range_info$kind == "sf") {
      return("A spatial range object was returned. Attributes are listed below.")
    }
    if (range_info$kind == "table") {
      return("A tabular range result was returned. BIEN may also have downloaded shapefiles in the range cache directory shown in Overview.")
    }
    range_info$text
  })

  output$range_map <- renderLeaflet({
    res <- bien_results()
    map <- leaflet() %>% addProviderTiles(providers$CartoDB.Positron)

    if (!(inherits(res$range_sf, "sf") && nrow(res$range_sf) > 0)) {
      return(map %>% setView(lng = 0, lat = 20, zoom = 2))
    }

    sf_obj <- suppressWarnings(st_make_valid(res$range_sf))
    geom_type <- unique(as.character(st_geometry_type(sf_obj)))

    if (any(geom_type %in% c("POLYGON", "MULTIPOLYGON"))) {
      map <- map %>% addPolygons(
        data = sf_obj,
        fillOpacity = 0.25,
        weight = 2,
        color = "#2C7BB6",
        popup = res$species
      )
    } else {
      map <- map %>% addCircleMarkers(data = sf_obj, radius = 4, stroke = FALSE, fillOpacity = 0.7)
    }

    bbox <- st_bbox(sf_obj)
    map %>% fitBounds(bbox[["xmin"]], bbox[["ymin"]], bbox[["xmax"]], bbox[["ymax"]])
  })

  output$range_table <- renderDT({
    res <- bien_results()
    if (inherits(res$ranges, "error")) {
      return(datatable(data.frame(message = paste("Range query error:", conditionMessage(res$ranges))), options = list(dom = "t"), rownames = FALSE))
    }
    range_info <- summarize_range_object(res$ranges)

    if (range_info$kind %in% c("table", "sf")) {
      return(datatable(as.data.frame(range_info$data), options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE))
    }

    datatable(data.frame(message = "No tabular range output available."), options = list(dom = "t"), rownames = FALSE)
  })

  output$reconciliation_table <- renderDT({
    res <- bien_results()
    datatable(res$reconciliation, options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
  })

  output$error_log <- renderText({
    res <- bien_results()
    if (length(res$query_errors) == 0) {
      return("No BIEN query errors captured for current species.")
    }
    paste(res$query_errors, collapse = "\n")
  })
}

shinyApp(ui = ui, server = server)
