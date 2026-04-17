suppressPackageStartupMessages({
  required_packages <- c("shiny", "BIEN", "dplyr", "stringr", "leaflet", "DT", "jsonlite")
  missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing_packages) > 0) {
    stop(
      paste0(
        "Missing required packages at app startup: ",
        paste(missing_packages, collapse = ", "),
        ". Install these packages before launching the app."
      )
    )
  }

  library(shiny)
  library(BIEN)
  library(dplyr)
  library(stringr)
  library(leaflet)
  library(DT)
  library(jsonlite)
})

# Safe wrapper: runs call_fn() (a zero-arg function) and captures errors.
# setTimeLimit is intentionally NOT used here because R evaluates function
# arguments eagerly before entering the callee, making it impossible to apply
# setTimeLimit to a call passed as an argument. Shinyapps.io manages session
# timeouts at the server level.
safe_bien_call <- function(call_fn) {
  tryCatch(call_fn(), error = function(e) e)
}

safe_bien_retry <- function(call_fn, attempts = 3, sleep_sec = 2) {
  last <- NULL
  for (i in seq_len(attempts)) {
    last <- safe_bien_call(call_fn)
    if (!inherits(last, "error")) {
      return(last)
    }
    if (i < attempts) {
      Sys.sleep(sleep_sec * i)
    }
  }
  last
}

first_existing_col <- function(df, candidates) {
  if (!is.data.frame(df)) return(NULL)
  nm <- names(df)
  idx <- match(tolower(candidates), tolower(nm))
  idx <- idx[!is.na(idx)]
  if (length(idx) == 0) return(NULL)
  nm[idx[1]]
}

first_value_or <- function(df, col_name, default = NA_character_) {
  if (!is.data.frame(df) || is.null(col_name) || !(col_name %in% names(df)) || nrow(df) == 0) {
    return(default)
  }
  val <- df[[col_name]][1]
  if (is.null(val) || length(val) == 0 || (length(val) == 1 && is.na(val))) {
    return(default)
  }
  as.character(val)
}

normalize_species_name <- function(x) {
  x <- str_squish(as.character(x))
  x <- x[nzchar(x)]
  if (length(x) == 0) return(character(0))

  vapply(x, function(one) {
    # If users paste common + scientific names on one line, extract the first
    # genus-species binomial-looking pair (for example "Ponderosa Pine Pinus ponderosa").
    latin_match <- str_match(one, "\\b([A-Z][a-z]+)\\s+([a-z][a-z-]+)\\b")
    if (!is.na(latin_match[1, 1])) {
      one <- paste(latin_match[1, 2], latin_match[1, 3])
    }

    parts <- strsplit(one, "\\s+")[[1]]
    if (length(parts) >= 1) {
      genus <- parts[1]
      parts[1] <- paste0(str_to_upper(substr(genus, 1, 1)), str_to_lower(substr(genus, 2, nchar(genus))))
    }
    if (length(parts) >= 2) {
      parts[2] <- str_to_lower(parts[2])
    }
    paste(parts, collapse = " ")
  }, character(1))
}

parse_species_input <- function(text_input, upload_path = NULL) {
  if (is.null(text_input)) {
    text_input <- ""
  }
  # Split only on line breaks, commas, or semicolons (not on letter 'n').
  from_text <- unlist(strsplit(text_input, "(\\r?\\n|[,;])+", perl = TRUE), use.names = FALSE)
  from_text <- normalize_species_name(from_text)

  from_file <- character(0)
  if (!is.null(upload_path) && nzchar(upload_path) && file.exists(upload_path)) {
    file_df <- tryCatch(read.csv(upload_path, stringsAsFactors = FALSE), error = function(e) NULL)
    if (is.data.frame(file_df) && nrow(file_df) > 0) {
      sp_col <- first_existing_col(file_df, c("species", "scientific_name", "taxon", "scrubbed_species_binomial"))
      if (!is.null(sp_col)) {
        from_file <- normalize_species_name(file_df[[sp_col]])
      } else {
        from_file <- normalize_species_name(file_df[[1]])
      }
    }
  }

  unique(c(from_text, from_file))
}

collect_trait_data <- function(
  species_vec,
  trait_filter = NULL,
  max_records = 5000
) {
  out <- list()
  errors <- character(0)
  for (i in seq_along(species_vec)) {
    sp <- species_vec[[i]]
    local_sp <- sp
    dat <- safe_bien_retry(
      function() {
        BIEN_trait_species(
          species = local_sp,
          all.taxonomy = TRUE,
          source.citation = TRUE,
          limit = as.integer(max_records)
        )
      },
      attempts = 3,
      sleep_sec = 2
    )

    if (inherits(dat, "error")) {
      errors <- c(errors, paste0("Error querying ", sp, ": ", conditionMessage(dat)))
    } else if (is.data.frame(dat) && nrow(dat) > 0) {
      dat$input_species <- sp
      out[[length(out) + 1]] <- dat
    }
  }

  if (length(out) == 0) {
    result <- data.frame()
  } else {
    result <- bind_rows(out)
    trait_col <- first_existing_col(result, c("trait_name", "trait", "measurementType"))
    if (!is.null(trait_col) && !is.null(trait_filter) && length(trait_filter) > 0) {
      result <- result %>% filter(.data[[trait_col]] %in% trait_filter)
    }
  }

  attr(result, "errors") <- errors
  result
}

apply_trait_filters <- function(
  traits,
  include_cultivated = FALSE,
  natives_only = FALSE,
  geovalid_only = FALSE
) {
  if (!is.data.frame(traits) || nrow(traits) == 0) {
    return(traits)
  }

  cultivated_col <- first_existing_col(traits, c("cultivated", "is_cultivated"))
  introduced_col <- first_existing_col(traits, c("is_introduced", "introduced"))
  geovalid_col <- first_existing_col(traits, c("geovalid", "is_geovalid"))

  if (!include_cultivated && !is.null(cultivated_col)) {
    cultivated_vals <- suppressWarnings(as.numeric(as.character(traits[[cultivated_col]])))
    keep <- is.na(cultivated_vals) | cultivated_vals == 0
    traits <- traits[keep, , drop = FALSE]
  }

  if (natives_only && !is.null(introduced_col)) {
    introduced_vals <- suppressWarnings(as.numeric(as.character(traits[[introduced_col]])))
    keep <- is.na(introduced_vals) | introduced_vals == 0
    traits <- traits[keep, , drop = FALSE]
  }

  if (geovalid_only && !is.null(geovalid_col)) {
    geovalid_vals <- suppressWarnings(as.numeric(as.character(traits[[geovalid_col]])))
    keep <- is.na(geovalid_vals) | geovalid_vals == 1
    traits <- traits[keep, , drop = FALSE]
  }

  traits
}

compute_trait_counts <- function(traits) {
  if (!is.data.frame(traits) || nrow(traits) == 0) {
    return(list(
      total = 0,
      cultivated = 0,
      native = 0,
      geovalid_yes = 0,
      geovalid_no = 0,
      cultivated_native = 0,
      cultivated_geovalid = 0,
      native_geovalid = 0,
      all_filters = 0
    ))
  }

  cultivated_col <- first_existing_col(traits, c("cultivated", "is_cultivated"))
  introduced_col <- first_existing_col(traits, c("is_introduced", "introduced"))
  geovalid_col <- first_existing_col(traits, c("geovalid", "is_geovalid"))

  is_cultivated <- rep(FALSE, nrow(traits))
  is_native <- rep(TRUE, nrow(traits))
  is_geovalid_yes <- rep(TRUE, nrow(traits))

  if (!is.null(cultivated_col)) {
    val <- suppressWarnings(as.numeric(as.character(traits[[cultivated_col]])))
    is_cultivated <- !is.na(val) & val == 1
  }

  if (!is.null(introduced_col)) {
    val <- suppressWarnings(as.numeric(as.character(traits[[introduced_col]])))
    is_native <- is.na(val) | val == 0
  }

  if (!is.null(geovalid_col)) {
    val <- suppressWarnings(as.numeric(as.character(traits[[geovalid_col]])))
    is_geovalid_yes <- is.na(val) | val == 1
  }

  list(
    total = nrow(traits),
    cultivated = sum(is_cultivated),
    native = sum(is_native),
    geovalid_yes = sum(is_geovalid_yes),
    geovalid_no = nrow(traits) - sum(is_geovalid_yes),
    cultivated_native = sum(is_cultivated & is_native),
    cultivated_geovalid = sum(is_cultivated & is_geovalid_yes),
    native_geovalid = sum(is_native & is_geovalid_yes),
    all_filters = sum(is_cultivated == FALSE & is_native & is_geovalid_yes)
  )
}

reconcile_species <- function(species_vec, timeout_sec = 60) {
  if (length(species_vec) == 0) {
    return(data.frame())
  }

  out <- lapply(species_vec, function(sp) {
    local_sp2 <- sp
    tax <- safe_bien_call(function() BIEN_taxonomy_species(local_sp2))
    if (inherits(tax, "error") || !is.data.frame(tax) || nrow(tax) == 0) {
      return(data.frame(
        input_name = sp,
        matched_name = NA_character_,
        accepted_name = NA_character_,
        match_status = "unresolved",
        stringsAsFactors = FALSE
      ))
    }

    matched_col <- first_existing_col(tax, c("scrubbed_species_binomial", "species", "scientific_name"))
    accepted_col <- first_existing_col(tax, c("accepted_species_name", "accepted_name", "accepted_scientific_name"))
    status_col <- first_existing_col(tax, c("scrubbed_taxonomic_status", "taxonomic_status", "status"))

    data.frame(
      input_name = sp,
      matched_name = first_value_or(tax, matched_col, NA_character_),
      accepted_name = first_value_or(tax, accepted_col, NA_character_),
      match_status = first_value_or(tax, status_col, "matched"),
      stringsAsFactors = FALSE
    )
  })

  bind_rows(out)
}

build_query_script <- function(species_vec, selected_traits, max_records, include_cultivated, natives_only, geovalid_only) {
  species_lines <- paste(sprintf("  \"%s\"", species_vec), collapse = ",\n")
  trait_lines <- if (length(selected_traits) > 0) {
    paste(sprintf("  \"%s\"", selected_traits), collapse = ",\n")
  } else {
    ""
  }

  paste(
    "# BIEN Traits query script generated by BIEN Traits Shiny App",
    sprintf("# Generated UTC: %s", format(Sys.time(), tz = "UTC", usetz = TRUE)),
    "library(BIEN)",
    "library(dplyr)",
    "",
    "species_vec <- c(",
    species_lines,
    ")",
    if (nchar(trait_lines) > 0) {
      paste("selected_traits <- c(\n", trait_lines, "\n)")
    } else {
      "selected_traits <- character(0)"
    },
    sprintf("max_records <- %d", as.integer(max_records)),
    sprintf("include_cultivated <- %s", tolower(as.character(include_cultivated))),
    sprintf("natives_only <- %s", tolower(as.character(natives_only))),
    sprintf("geovalid_only <- %s", tolower(as.character(geovalid_only))),
    "",
    "trait_out <- lapply(species_vec, function(sp) {",
    "  dat <- BIEN_trait_species(",
    "    species = sp,",
    "    all.taxonomy = TRUE,",
    "    source.citation = TRUE",
    "  )",
    "  if (!is.data.frame(dat) || nrow(dat) == 0) return(NULL)",
    "  dat$input_species <- sp",
    "  dat",
    "})",
    "",
    "traits <- dplyr::bind_rows(trait_out)",
    "trait_col <- intersect(names(traits), c('trait_name', 'trait', 'measurementType'))[1]",
    "if (!is.na(trait_col) && length(selected_traits) > 0) {",
    "  traits <- dplyr::filter(traits, .data[[trait_col]] %in% selected_traits)",
    "}",
    "",
    "write.csv(traits, 'bien_traits_observations.csv', row.names = FALSE)",
    "message('Rows written: ', nrow(traits))",
    sep = "\n"
  )
}

app_ui <- fluidPage(
  tags$head(
    tags$style(HTML(
      "
      .query-busy-overlay {
        position: fixed;
        inset: 0;
        background: rgba(255, 255, 255, 0.78);
        z-index: 3000;
        display: flex;
        align-items: center;
        justify-content: center;
      }
      .query-busy-card {
        background: #ffffff;
        border: 1px solid #d8e2ea;
        border-radius: 12px;
        padding: 18px 22px;
        min-width: 280px;
        box-shadow: 0 10px 25px rgba(0, 0, 0, 0.12);
        text-align: center;
      }
      .query-busy-spinner {
        width: 52px;
        height: 52px;
        border: 6px solid #d5e6f4;
        border-top-color: #1b6ca8;
        border-radius: 50%;
        margin: 0 auto 10px auto;
        animation: query-spin 0.9s linear infinite;
      }
      .query-busy-title {
        font-size: 16px;
        font-weight: 700;
        color: #17486d;
      }
      .query-busy-subtitle {
        margin-top: 4px;
        font-size: 13px;
        color: #4c6272;
      }
      @keyframes query-spin {
        to { transform: rotate(360deg); }
      }
      "
    ))
  ),
  uiOutput("query_busy_overlay"),
  titlePanel("BIEN Traits ShinyApp"),
  sidebarLayout(
    sidebarPanel(
      tags$p("Query BIEN traits for one or many species. Use filters to refine downloads."),
      textAreaInput(
        "species_text",
        "Species list (one per line, or comma-separated)",
        value = "",
        rows = 8,
        placeholder = "e.g.\nQuercus agrifolia\nPinus ponderosa"
      ),
      fileInput("species_file", "Upload CSV of species", accept = c(".csv")),
      tags$hr(),
      tags$strong("Download filters (applied to downloads only):"),
      checkboxInput("use_cultivated", "Include cultivated records", value = FALSE),
      checkboxInput("natives_only", "Native records only", value = FALSE),
      checkboxInput("geovalid_only", "Geovalid coordinates only", value = FALSE),
      tags$small("(See 'Coverage' tab to view trait counts by filter)"),
      numericInput("max_records", "Max trait records per species", value = 5000, min = 100, max = 50000, step = 100),
      actionButton("run_query", "Query BIEN", class = "btn-primary"),
      actionButton("reset_query", "Reset"),
      tags$hr(),
      uiOutput("trait_selector_ui"),
      tags$hr(),
      h4("Downloads"),
      downloadButton("download_traits", "Trait observations CSV"),
      downloadButton("download_summary", "Trait summary CSV"),
      downloadButton("download_citations", "Citations CSV"),
      downloadButton("download_code", "Query code (.R)")
    ),
    mainPanel(
      tabsetPanel(
        id = "main_tabs",
        tabPanel("Query",
          h4("Query status"),
          verbatimTextOutput("query_status"),
          h4("Taxonomy reconciliation"),
          DTOutput("taxonomy_table")
        ),
        tabPanel("Coverage",
          h4("All trait observations (unfiltered) - counts by filter option:"),
          DTOutput("filter_coverage_table"),
          tags$p("Use the checkboxes in the sidebar to filter downloads. The Coverage tab shows how many traits match each filter combination.")
        ),
        tabPanel("Trait Data",
          h4("Trait observations (showing unfiltered data)"),
          DTOutput("trait_table"),
          h4("Trait summary by species, trait, and unit"),
          DTOutput("trait_summary_table")
        ),
        tabPanel("Map",
          fluidRow(
            column(6, uiOutput("map_trait_ui")),
            column(6, uiOutput("map_unit_ui"))
          ),
          tags$p("Map shows trait observation locations when coordinates are available. Absence of points does not imply no data."),
          leafletOutput("trait_map", height = 520)
        ),
        tabPanel("Provenance and citations",
          h4("Observation-level provenance"),
          DTOutput("provenance_table"),
          h4("Citation fields"),
          DTOutput("citation_table")
        ),
        tabPanel("Reproducible code",
          tags$p("Use this script to reproduce your BIEN trait query outside the app."),
          textAreaInput("query_code", "R query script", value = "", rows = 20, width = "100%")
        ),
        tabPanel("Help",
          h3("How to use this app"),
          tags$ol(
            tags$li("Enter species names or upload a CSV."),
            tags$li("Click Query BIEN to fetch ALL available trait observations."),
            tags$li("Use Coverage tab to see trait counts by filter option."),
            tags$li("Check sidebar filters if you want to download only a subset (e.g., native records only)."),
            tags$li("Inspect trait rows, provenance, and map output."),
            tags$li("Download data tables (which will be filtered per your selections), citations, and reproducible code.")
          ),
          h4("Understanding the filters"),
          tags$ul(
            tags$li("By default, all traits are displayed. Sidebar filters control what gets downloaded."),
            tags$li("'Include cultivated records' - if unchecked, download excludes cultivated occurrences."),
            tags$li("'Native records only' - if checked, download includes only native occurrences."),
            tags$li("'Geovalid coordinates only' - if checked, download includes only records with valid coordinates.")
          ),
          h4("Ecological interpretation caveats"),
          tags$ul(
            tags$li("Trait availability varies by species and trait. Check Coverage tab for details."),
            tags$li("Trait maps reflect sampling effort and data availability, not full species ranges."),
            tags$li("Do not merge incompatible units without explicit conversion rules."),
            tags$li("Within-species variation can be large; avoid over-interpreting single summary values."),
            tags$li("Taxonomic reconciliation can be uncertain; unresolved names are retained and flagged.")
          )
        )
      )
    )
  )
)

app_server <- function(input, output, session) {
  state <- reactiveValues(
    species = character(0),
    taxonomy = data.frame(),
    traits = data.frame(),
    status = "Enter species and click Query BIEN.",
    available_traits = data.frame(),
    query_script = "",
    query_running = FALSE
  )

  output$query_busy_overlay <- renderUI({
    if (!isTRUE(state$query_running)) {
      return(NULL)
    }

    tags$div(
      class = "query-busy-overlay",
      tags$div(
        class = "query-busy-card",
        tags$div(class = "query-busy-spinner"),
        tags$div(class = "query-busy-title", "Fetching BIEN data..."),
        tags$div(class = "query-busy-subtitle", "Query is running. Please wait for completion.")
      )
    )
  })

  observeEvent(input$reset_query, {
    updateTextAreaInput(session, "species_text", value = "")
    updateTextAreaInput(session, "query_code", value = "")
    state$species <- character(0)
    state$taxonomy <- data.frame()
    state$traits <- data.frame()
    state$available_traits <- data.frame()
    state$status <- "Reset complete. Enter species and click Query BIEN."
  })

  observeEvent(input$run_query, {
    species_vec <- parse_species_input(
      text_input = input$species_text,
      upload_path = if (!is.null(input$species_file$datapath)) input$species_file$datapath else NULL
    )

    if (length(species_vec) == 0) {
      state$status <- "No valid species names found. Add at least one species."
      showNotification("No valid species names found.", type = "error")
      return(NULL)
    }

    state$species <- species_vec
    state$query_running <- TRUE
    on.exit({ state$query_running <- FALSE }, add = TRUE)

    withProgress(message = "Querying BIEN", value = 0, {
      incProgress(0.2, detail = "Reconciling taxonomy")
      tax_tbl <- reconcile_species(species_vec)
      state$taxonomy <- tax_tbl

      incProgress(0.2, detail = "Loading trait catalog")
      trait_list <- safe_bien_call(function() BIEN_trait_list())
      if (is.data.frame(trait_list)) {
        state$available_traits <- trait_list
      } else {
        state$available_traits <- data.frame()
      }

      selected_traits <- input$trait_selector
      if (is.null(selected_traits) || length(selected_traits) == 0) {
        selected_traits <- NULL
      }

      incProgress(0.5, detail = "Fetching trait observations")
      trait_tbl <- collect_trait_data(
        species_vec = species_vec,
        trait_filter = selected_traits,
        max_records = input$max_records
      )
      state$traits <- trait_tbl

      errs <- attr(trait_tbl, "errors")
      if (length(errs) > 0) {
        showNotification(
          HTML(paste(c("Errors during query:", errs), collapse = "<br/>")),
          type = "warning",
          duration = 10
        )
      }

      state$query_script <- build_query_script(
        species_vec = species_vec,
        selected_traits = if (is.null(selected_traits)) character(0) else selected_traits,
        max_records = input$max_records,
        include_cultivated = input$use_cultivated,
        natives_only = input$natives_only,
        geovalid_only = input$geovalid_only
      )
      updateTextAreaInput(session, "query_code", value = state$query_script)

      n_rows <- if (is.data.frame(trait_tbl)) nrow(trait_tbl) else 0
      state$status <- paste0(
        "Completed query for ", length(species_vec), " species. ",
        "Trait rows returned: ", n_rows, ". ",
        if (length(errs) > 0) paste0("(With ", length(errs), " query error(s) - see notification above)") else "(No errors)"
      )
    })
  })

  output$query_status <- renderText({
    state$status
  })

  output$trait_selector_ui <- renderUI({
    tr <- state$available_traits
    if (!is.data.frame(tr) || nrow(tr) == 0) {
      return(helpText("Trait selector appears after BIEN trait catalog is loaded."))
    }

    tr_col <- first_existing_col(tr, c("trait_name", "trait", "trait"))
    if (is.null(tr_col)) {
      return(helpText("Trait list loaded, but trait-name column was not found."))
    }

    choices <- sort(unique(as.character(tr[[tr_col]])))
    selectizeInput("trait_selector", "Filter to traits (optional)", choices = choices, multiple = TRUE)
  })

  output$taxonomy_table <- renderDT({
    datatable(state$taxonomy, options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
  })

  filtered_traits_reactive <- reactive({
    apply_trait_filters(
      traits = state$traits,
      include_cultivated = input$use_cultivated,
      natives_only = input$natives_only,
      geovalid_only = input$geovalid_only
    )
  })

  output$filter_coverage_table <- renderDT({
    tr <- state$traits
    if (!is.data.frame(tr) || nrow(tr) == 0) {
      return(datatable(data.frame(message = "No trait observations to analyze."), options = list(dom = "t"), rownames = FALSE))
    }

    counts <- compute_trait_counts(tr)
    cov_df <- data.frame(
      Filter_Combination = c(
        "All observations (no filters)",
        "No cultivated records",
        "Native records only",
        "Geovalid only",
        "Geovalid + No cultivated",
        "Geovalid + Native only",
        "No cultivated + Native only",
        "All filters (no cultivated + native + geovalid)"
      ),
      Trait_Count = c(
        counts$total,
        counts$total - counts$cultivated,
        counts$native,
        counts$geovalid_yes,
        counts$geovalid_yes - counts$cultivated_geovalid,
        counts$native_geovalid,
        counts$total - counts$cultivated - (counts$total - counts$native),
        counts$all_filters
      ),
      stringsAsFactors = FALSE
    )
    datatable(cov_df, options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
  })

  output$available_traits_table <- renderDT({
    tr <- state$available_traits
    if (!is.data.frame(tr) || nrow(tr) == 0) {
      return(datatable(data.frame(message = "No BIEN trait catalog returned in this session."), options = list(dom = "t"), rownames = FALSE))
    }

    trait_name_col <- first_existing_col(tr, c("trait_name", "trait", "measurementType"))
    query_trait_col <- first_existing_col(state$traits, c("trait_name", "trait", "measurementType"))

    out <- tr
    if (!is.null(trait_name_col) && !is.null(query_trait_col) && is.data.frame(state$traits) && nrow(state$traits) > 0) {
      counts <- state$traits %>%
        group_by(.data[[query_trait_col]]) %>%
        summarise(query_observation_count = n(), .groups = "drop")
      names(counts)[1] <- trait_name_col
      out <- left_join(out, counts, by = trait_name_col)
      out$query_observation_count[is.na(out$query_observation_count)] <- 0L
    }

    datatable(out, options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
  })

  output$trait_table <- renderDT({
    tr <- state$traits
    if (!is.data.frame(tr) || nrow(tr) == 0) {
      return(datatable(data.frame(message = "No trait observations to display."), options = list(dom = "t"), rownames = FALSE))
    }
    datatable(tr, options = list(pageLength = 15, scrollX = TRUE), rownames = FALSE)
  })

  output$trait_summary_table <- renderDT({
    tr <- state$traits
    if (!is.data.frame(tr) || nrow(tr) == 0) {
      return(datatable(data.frame(message = "No trait summary available."), options = list(dom = "t"), rownames = FALSE))
    }

    species_col <- first_existing_col(tr, c("input_species", "scrubbed_species_binomial", "species"))
    trait_col <- first_existing_col(tr, c("trait_name", "trait", "measurementType"))
    unit_col <- first_existing_col(tr, c("unit", "measurementUnit"))
    value_col <- first_existing_col(tr, c("trait_value", "value", "measurementValue"))

    if (is.null(species_col) || is.null(trait_col)) {
      return(datatable(data.frame(message = "Missing key summary columns."), options = list(dom = "t"), rownames = FALSE))
    }

    if (is.null(unit_col)) {
      tr$unit_auto <- NA_character_
      unit_col <- "unit_auto"
    }

    if (is.null(value_col)) {
      tr$value_auto <- NA_character_
      value_col <- "value_auto"
    }

    tr_num <- suppressWarnings(as.numeric(as.character(tr[[value_col]])))

    sm <- tr %>%
      mutate(value_numeric = tr_num) %>%
      group_by(.data[[species_col]], .data[[trait_col]], .data[[unit_col]]) %>%
      summarise(
        n = n(),
        n_numeric = sum(!is.na(.data$value_numeric)),
        mean_value = ifelse(sum(!is.na(.data$value_numeric)) > 0, mean(.data$value_numeric, na.rm = TRUE), NA_real_),
        sd_value = ifelse(sum(!is.na(.data$value_numeric)) > 1, stats::sd(.data$value_numeric, na.rm = TRUE), NA_real_),
        .groups = "drop"
      ) %>%
      arrange(desc(n))

    datatable(sm, options = list(pageLength = 15, scrollX = TRUE), rownames = FALSE)
  })

  output$map_trait_ui <- renderUI({
    tr <- state$traits
    if (!is.data.frame(tr) || nrow(tr) == 0) return(NULL)
    trait_col <- first_existing_col(tr, c("trait_name", "trait", "measurementType"))
    if (is.null(trait_col)) return(NULL)
    choices <- sort(unique(as.character(tr[[trait_col]])))
    selectInput("map_trait", "Trait for map", choices = choices, selected = choices[1])
  })

  output$map_unit_ui <- renderUI({
    tr <- state$traits
    if (!is.data.frame(tr) || nrow(tr) == 0) return(NULL)

    trait_col <- first_existing_col(tr, c("trait_name", "trait", "measurementType"))
    unit_col <- first_existing_col(tr, c("unit", "measurementUnit"))
    if (is.null(trait_col) || is.null(unit_col) || is.null(input$map_trait)) return(NULL)

    u <- tr %>%
      filter(.data[[trait_col]] == input$map_trait) %>%
      pull(.data[[unit_col]]) %>%
      as.character() %>%
      unique() %>%
      sort()

    selectInput("map_unit", "Unit", choices = c("All", u), selected = "All")
  })

  output$trait_map <- renderLeaflet({
    tr <- state$traits
    req(is.data.frame(tr))

    lat_col <- first_existing_col(tr, c("latitude", "lat", "decimalLatitude"))
    lon_col <- first_existing_col(tr, c("longitude", "long", "lon", "decimalLongitude"))
    trait_col <- first_existing_col(tr, c("trait_name", "trait", "measurementType"))
    value_col <- first_existing_col(tr, c("trait_value", "value", "measurementValue"))

    if (is.null(lat_col) || is.null(lon_col) || is.null(trait_col)) {
      return(
        leaflet() %>%
          addProviderTiles(providers$CartoDB.Positron) %>%
          addPopups(0, 0, "No coordinate fields were found in BIEN trait output for this query.")
      )
    }

    map_df <- tr
    if (!is.null(input$map_trait) && nzchar(input$map_trait)) {
      map_df <- map_df %>% filter(.data[[trait_col]] == input$map_trait)
    }
    unit_col <- first_existing_col(map_df, c("unit", "measurementUnit"))
    if (!is.null(unit_col) && !is.null(input$map_unit) && input$map_unit != "All") {
      map_df <- map_df %>% filter(as.character(.data[[unit_col]]) == input$map_unit)
    }

    map_df[[lat_col]] <- suppressWarnings(as.numeric(map_df[[lat_col]]))
    map_df[[lon_col]] <- suppressWarnings(as.numeric(map_df[[lon_col]]))
    map_df <- map_df %>% filter(!is.na(.data[[lat_col]]), !is.na(.data[[lon_col]]))

    if (nrow(map_df) == 0) {
      return(
        leaflet() %>%
          addProviderTiles(providers$CartoDB.Positron) %>%
          addPopups(0, 0, "No mappable trait points after current filters.")
      )
    }

    if (!is.null(value_col)) {
      val_num <- suppressWarnings(as.numeric(map_df[[value_col]]))
      pal <- colorNumeric("YlGnBu", domain = val_num, na.color = "#808080")
      point_col <- pal(val_num)
    } else {
      point_col <- "#2C7FB8"
    }

    species_vals <- if ("input_species" %in% names(map_df)) map_df$input_species else NA_character_

    popup_txt <- paste0(
      "<b>Species:</b> ", species_vals, "<br/>",
      "<b>Trait:</b> ", map_df[[trait_col]], "<br/>",
      if (!is.null(value_col)) paste0("<b>Value:</b> ", map_df[[value_col]], "<br/>") else "",
      if (!is.null(unit_col)) paste0("<b>Unit:</b> ", map_df[[unit_col]], "<br/>") else ""
    )

    leaflet(map_df) %>%
      addProviderTiles(providers$CartoDB.Positron) %>%
      addCircleMarkers(
        lng = ~.data[[lon_col]],
        lat = ~.data[[lat_col]],
        radius = 4,
        stroke = FALSE,
        fillOpacity = 0.75,
        color = point_col,
        popup = popup_txt
      )
  })

  output$provenance_table <- renderDT({
    tr <- state$traits
    if (!is.data.frame(tr) || nrow(tr) == 0) {
      return(datatable(data.frame(message = "No provenance rows available."), options = list(dom = "t"), rownames = FALSE))
    }

    prov_cols <- unique(c(
      first_existing_col(tr, c("input_species", "scrubbed_species_binomial", "species")),
      first_existing_col(tr, c("trait_name", "trait", "measurementType")),
      first_existing_col(tr, c("trait_value", "value", "measurementValue")),
      first_existing_col(tr, c("unit", "measurementUnit")),
      first_existing_col(tr, c("datasource", "data_source", "collection", "source")),
      first_existing_col(tr, c("dataset", "dataset_name")),
      first_existing_col(tr, c("observation_type", "basisOfRecord")),
      first_existing_col(tr, c("latitude", "longitude", "decimalLatitude", "decimalLongitude"))
    ))

    prov_cols <- prov_cols[!is.na(prov_cols) & nzchar(prov_cols)]
    prov <- tr[, unique(prov_cols), drop = FALSE]
    datatable(prov, options = list(pageLength = 15, scrollX = TRUE), rownames = FALSE)
  })

  output$citation_table <- renderDT({
    tr <- state$traits
    if (!is.data.frame(tr) || nrow(tr) == 0) {
      return(datatable(data.frame(message = "No citation rows available."), options = list(dom = "t"), rownames = FALSE))
    }

    citation_cols <- names(tr)[str_detect(tolower(names(tr)), "citation|reference|doi|source")]
    citation_cols <- unique(c(first_existing_col(tr, c("input_species", "scrubbed_species_binomial", "species")), citation_cols))
    citation_cols <- citation_cols[!is.na(citation_cols) & nzchar(citation_cols)]

    if (length(citation_cols) == 0) {
      return(datatable(data.frame(message = "No citation-like fields found in BIEN trait output."), options = list(dom = "t"), rownames = FALSE))
    }

    cite <- tr[, unique(citation_cols), drop = FALSE] %>% distinct()
    datatable(cite, options = list(pageLength = 15, scrollX = TRUE), rownames = FALSE)
  })

  output$download_traits <- downloadHandler(
    filename = function() sprintf("bien_traits_observations_%s.csv", format(Sys.Date(), "%Y%m%d")),
    content = function(file) {
      write.csv(filtered_traits_reactive(), file, row.names = FALSE)
    }
  )

  output$download_summary <- downloadHandler(
    filename = function() sprintf("bien_traits_summary_%s.csv", format(Sys.Date(), "%Y%m%d")),
    content = function(file) {
      tr <- filtered_traits_reactive()
      if (!is.data.frame(tr) || nrow(tr) == 0) {
        write.csv(data.frame(), file, row.names = FALSE)
        return(NULL)
      }

      species_col <- first_existing_col(tr, c("input_species", "scrubbed_species_binomial", "species"))
      trait_col <- first_existing_col(tr, c("trait_name", "trait", "measurementType"))
      unit_col <- first_existing_col(tr, c("unit", "measurementUnit"))

      if (is.null(species_col) || is.null(trait_col)) {
        write.csv(data.frame(), file, row.names = FALSE)
        return(NULL)
      }

      if (is.null(unit_col)) {
        tr$unit_auto <- NA_character_
        unit_col <- "unit_auto"
      }

      out <- tr %>%
        group_by(.data[[species_col]], .data[[trait_col]], .data[[unit_col]]) %>%
        summarise(observation_count = n(), .groups = "drop")

      write.csv(out, file, row.names = FALSE)
    }
  )

  output$download_citations <- downloadHandler(
    filename = function() sprintf("bien_trait_citations_%s.csv", format(Sys.Date(), "%Y%m%d")),
    content = function(file) {
      tr <- filtered_traits_reactive()
      if (!is.data.frame(tr) || nrow(tr) == 0) {
        write.csv(data.frame(), file, row.names = FALSE)
        return(NULL)
      }

      citation_cols <- names(tr)[str_detect(tolower(names(tr)), "citation|reference|doi|source")]
      citation_cols <- unique(c(first_existing_col(tr, c("input_species", "scrubbed_species_binomial", "species")), citation_cols))
      citation_cols <- citation_cols[!is.na(citation_cols) & nzchar(citation_cols)]

      if (length(citation_cols) == 0) {
        write.csv(data.frame(), file, row.names = FALSE)
      } else {
        write.csv(unique(tr[, citation_cols, drop = FALSE]), file, row.names = FALSE)
      }
    }
  )

  output$download_code <- downloadHandler(
    filename = function() sprintf("bien_traits_query_%s.R", format(Sys.Date(), "%Y%m%d")),
    content = function(file) {
      code <- state$query_script
      if (is.null(code)) code <- ""
      writeLines(code, file)
    }
  )
}

shinyApp(ui = app_ui, server = app_server)
