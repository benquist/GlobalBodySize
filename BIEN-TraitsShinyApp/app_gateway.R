# BIEN Trait Data Gateway - Modular Shiny App
# Build: April 20, 2026
# Features: 4 query modes (species/genus/family/trait-only), availability-first gating,
#           mandatory pre-download checklist, full provenance tracking

suppressPackageStartupMessages({
  required_packages <- c("shiny", "BIEN", "dplyr", "stringr", "DT", "jsonlite")
  missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing_packages) > 0) {
    stop(paste0("Missing packages: ", paste(missing_packages, collapse = ", ")))
  }

  library(shiny)
  library(BIEN)
  library(dplyr)
  library(stringr)
  library(DT)
  library(jsonlite)
})

# ============================================================================
# HELPER FUNCTIONS - DATA COLLECTION & NORMALIZATION
# ============================================================================

normalize_taxon_name <- function(x) {
  x <- str_squish(as.character(x))
  x <- x[nzchar(x)]
  if (length(x) == 0) return(character(0))

  vapply(x, function(one) {
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

extract_rank_token <- function(rank, taxon) {
  taxon <- str_squish(as.character(taxon))
  if (!nzchar(taxon)) return(taxon)

  # Genus/family queries should use a single cleaned token.
  if (rank %in% c("genus", "family")) {
    token <- strsplit(taxon, "\\s+")[[1]][1]
    token <- gsub("[^A-Za-z-]", "", token)
    if (!nzchar(token)) return(taxon)
    token <- paste0(str_to_upper(substr(token, 1, 1)), str_to_lower(substr(token, 2, nchar(token))))
    return(token)
  }

  taxon
}

safe_bien_call <- function(expr, timeout_sec = 120) {
  tryCatch(expr, error = function(e) {
    structure(list(error = conditionMessage(e)), class = "bien_error")
  })
}

safe_bien_retry <- function(call_fn, timeout_sec = 120, attempts = 3, sleep_sec = 1) {
  last <- NULL
  for (i in seq_len(attempts)) {
    last <- safe_bien_call(call_fn(), timeout_sec = timeout_sec)
    if (!inherits(last, "bien_error")) {
      return(last)
    }
    if (i < attempts) Sys.sleep(sleep_sec * i)
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

ensure_unique_names <- function(df) {
  if (!is.data.frame(df) || ncol(df) == 0) {
    return(df)
  }
  names(df) <- make.unique(names(df), sep = "__dup")
  df
}

load_trait_suggestions <- function(timeout_sec = 120) {
  trait_catalog <- safe_bien_retry(function() {
    BIEN_trait_list()
  }, timeout_sec = timeout_sec, attempts = 2)

  if (inherits(trait_catalog, "bien_error") || !is.data.frame(trait_catalog) || nrow(trait_catalog) == 0) {
    return(character(0))
  }

  trait_col <- first_existing_col(trait_catalog, c("trait_name", "trait", "measurementType"))
  if (is.null(trait_col)) return(character(0))

  vals <- unique(as.character(trait_catalog[[trait_col]]))
  vals <- vals[!is.na(vals) & nzchar(vals)]
  sort(vals)
}

# Expand partial trait name (e.g. "leaf phosphorus") to all matching exact BIEN trait names
expand_trait_name <- function(partial_trait, timeout_sec = 120) {
  if (!nzchar(partial_trait)) return(character(0))
  
  trait_catalog <- safe_bien_retry(function() {
    BIEN_trait_list()
  }, timeout_sec = timeout_sec, attempts = 2)
  
  if (inherits(trait_catalog, "bien_error") || !is.data.frame(trait_catalog) || nrow(trait_catalog) == 0) {
    return(partial_trait)
  }
  
  trait_col <- first_existing_col(trait_catalog, c("trait_name", "trait", "measurementType"))
  if (is.null(trait_col)) return(partial_trait)
  
  # Find all trait names that contain the partial trait term
  trait_names <- unique(as.character(trait_catalog[[trait_col]]))
  trait_names <- trait_names[!is.na(trait_names) & nzchar(trait_names)]
  
  # Match using case-insensitive substring search
  partial_lower <- tolower(str_squish(partial_trait))
  matching_traits <- trait_names[grepl(partial_lower, tolower(trait_names), fixed = TRUE)]
  
  if (length(matching_traits) > 0) {
    sort(matching_traits)
  } else {
    partial_trait  # Return original if no matches found
  }
}

load_taxon_suggestions <- function(rank, max_choices = 50000, timeout_sec = 120) {
  sql <- switch(rank,
    species = sprintf(
      paste0(
        "SELECT a.scrubbed_species_binomial AS taxon, COUNT(*) AS n_rec ",
        "FROM agg_traits a ",
        "WHERE a.scrubbed_species_binomial IS NOT NULL AND a.scrubbed_species_binomial <> '' ",
        "AND EXISTS (",
        "  SELECT 1 FROM bien_taxonomy b ",
        "  WHERE b.scrubbed_species_binomial = a.scrubbed_species_binomial ",
        "  AND b.scrubbed_taxonomic_status = 'Accepted'",
        ") ",
        "GROUP BY a.scrubbed_species_binomial ",
        "ORDER BY n_rec DESC, a.scrubbed_species_binomial ",
        "LIMIT %d;"
      ),
      as.integer(max_choices)
    ),
    genus = sprintf(
      paste0(
        "SELECT a.scrubbed_genus AS taxon, COUNT(*) AS n_rec ",
        "FROM agg_traits a ",
        "WHERE a.scrubbed_genus IS NOT NULL AND a.scrubbed_genus <> '' ",
        "AND EXISTS (",
        "  SELECT 1 FROM bien_taxonomy b ",
        "  WHERE b.scrubbed_genus = a.scrubbed_genus ",
        "  AND b.scrubbed_taxonomic_status = 'Accepted'",
        ") ",
        "GROUP BY a.scrubbed_genus ",
        "ORDER BY n_rec DESC, a.scrubbed_genus ",
        "LIMIT %d;"
      ),
      as.integer(max_choices)
    ),
    family = sprintf(
      paste0(
        "SELECT a.scrubbed_family AS taxon, COUNT(*) AS n_rec ",
        "FROM agg_traits a ",
        "WHERE a.scrubbed_family IS NOT NULL AND a.scrubbed_family <> '' ",
        "AND EXISTS (",
        "  SELECT 1 FROM bien_taxonomy b ",
        "  WHERE b.scrubbed_family = a.scrubbed_family ",
        "  AND b.scrubbed_taxonomic_status = 'Accepted'",
        ") ",
        "GROUP BY a.scrubbed_family ",
        "ORDER BY n_rec DESC, a.scrubbed_family ",
        "LIMIT %d;"
      ),
      as.integer(max_choices)
    ),
    NULL
  )
  if (is.null(sql)) return(character(0))

  bien_sql <- get(".BIEN_sql", envir = asNamespace("BIEN"))
  out <- safe_bien_retry(function() {
    bien_sql(query = sql, fetch.query = FALSE)
  }, timeout_sec = timeout_sec, attempts = 2)

  if (inherits(out, "bien_error") || !is.data.frame(out) || nrow(out) == 0 || !"taxon" %in% names(out)) {
    return(character(0))
  }

  vals <- unique(as.character(out$taxon))
  vals <- vals[!is.na(vals) & nzchar(vals)]
  vals
}

# Identify plot-based traits and enrich with available source metadata
# Plot traits: stem diameter, height, basal area, crown metrics, wood density from plots
# NOTE: BIEN trait API returns observations but not plot-level metadata directly.
# Use url_source and source_citation to access full plot details.
enrich_plot_metadata <- function(dat) {
  if (!is.data.frame(dat) || nrow(dat) == 0) return(dat)

  trait_col <- first_existing_col(dat, c("trait_name", "trait", "measurementType"))
  
  # Keywords indicating plot-based trait data
  plot_trait_keywords <- c("diameter", "dbh", "height", "basal area", "crown",
                          "wood density", "biomass", "age", "growth", "increment")
  
  is_plot_trait <- if (!is.null(trait_col)) {
    grepl(paste(plot_trait_keywords, collapse = "|"), 
          tolower(dat[[trait_col]]), perl = TRUE)
  } else {
    rep(FALSE, nrow(dat))
  }
  
  # Add a marker column so users can filter to plot-sourced traits
  dat$is_plot_trait <- is_plot_trait
  
  dat
}

# Reorganize columns to surface plot metadata for plot-based traits
organize_columns_for_export <- function(dat) {
  if (!is.data.frame(dat) || nrow(dat) == 0) return(dat)
  
  # Standard priority columns: species, trait info, value
  core_cols <- c("scrubbed_species_binomial", "trait_name", "trait_value", "unit", "method")
  
  # Source/citation first (especially important for plot traits to access metadata)
  source_cols <- c("url_source", "source_citation", "project_pi")
  
  # Location columns
  location_cols <- c("latitude", "longitude", "elevation_m")
  
  # Plot trait marker
  marker_cols <- c("is_plot_trait")
  
  # Taxonomy columns
  tax_cols <- names(dat)[which(grepl("^scrubbed_", names(dat)) & !grepl("binomial|species", names(dat)))]
  
  # Query metadata
  query_cols <- c("query_rank", "query_taxon", "query_timestamp")
  
  # Build column order: core → source → location → marker → taxonomy → query → other
  col_order <- c()
  for (col_set in list(core_cols, source_cols, location_cols, marker_cols, tax_cols, query_cols)) {
    col_order <- c(col_order, col_set[col_set %in% names(dat)])
  }
  
  # Add any remaining columns at end
  remaining <- setdiff(names(dat), col_order)
  col_order <- c(col_order, remaining)
  
  dat[, col_order, drop = FALSE]
}

# Query trait data by rank (species/genus/family/trait-only)
query_bien_traits <- function(rank, taxon, max_records = 5000, timeout_sec = 120) {
  taxon <- extract_rank_token(rank, taxon)

  if (rank == "species") {
    dat <- safe_bien_retry(function() {
      BIEN_trait_species(species = taxon, all.taxonomy = TRUE, 
                        source.citation = TRUE, limit = max_records)
    }, timeout_sec = timeout_sec, attempts = 3)
  } else if (rank == "genus") {
    dat <- safe_bien_retry(function() {
      BIEN_trait_genus(genus = taxon, all.taxonomy = TRUE, 
                      source.citation = TRUE, limit = max_records)
    }, timeout_sec = timeout_sec, attempts = 3)

    # Fallback for genus inputs that include extra text/punctuation.
    if (!inherits(dat, "bien_error") && is.data.frame(dat) && nrow(dat) == 0) {
      genus_token <- extract_rank_token("genus", taxon)
      if (!identical(genus_token, taxon)) {
        dat <- safe_bien_retry(function() {
          BIEN_trait_genus(genus = genus_token, all.taxonomy = TRUE,
                          source.citation = TRUE, limit = max_records)
        }, timeout_sec = timeout_sec, attempts = 2)
      }
    }
  } else if (rank == "family") {
    dat <- safe_bien_retry(function() {
      BIEN_trait_family(family = taxon, all.taxonomy = TRUE, 
                       source.citation = TRUE, limit = max_records)
    }, timeout_sec = timeout_sec, attempts = 3)
  } else {
    # trait-only: expand partial trait name to exact BIEN trait names and query each
    trait_names <- expand_trait_name(taxon, timeout_sec = timeout_sec)
    
    # Query each matching trait and combine results
    trait_results <- list()
    for (trait_name in trait_names) {
      trait_dat <- safe_bien_retry(function() {
        BIEN_trait_trait(trait = trait_name, all.taxonomy = TRUE,
                        source.citation = TRUE, limit = max_records)
      }, timeout_sec = timeout_sec, attempts = 3)
      
      if (is.data.frame(trait_dat) && nrow(trait_dat) > 0) {
        trait_results[[trait_name]] <- trait_dat
      }
    }
    
    # Combine all trait results into a single dataframe
    if (length(trait_results) > 0) {
      dat <- dplyr::bind_rows(trait_results)
      # Store which traits were queried for later reference
      attr(dat, "queried_traits") <- names(trait_results)
    } else {
      dat <- data.frame()
    }
  }
  
  if (inherits(dat, "bien_error")) {
    out <- data.frame()
    attr(out, "bien_error") <- dat$error
    return(out)
  }
  if (!is.data.frame(dat)) {
    out <- data.frame()
    attr(out, "bien_error") <- "BIEN returned an unexpected response format"
    return(out)
  }

  # BIEN can return duplicated names (for example scrubbed_genus).
  # Repair once at ingest so downstream dplyr verbs are stable.
  dat <- ensure_unique_names(dat)
  
  # Enrich with plot metadata where available
  dat <- enrich_plot_metadata(dat)
  
  dat$query_rank <- rank
  dat$query_taxon <- taxon
  dat$query_timestamp <- Sys.time()
  dat
}

# Query exact total number of matching BIEN trait rows (without limit)
query_bien_total_records <- function(rank, taxon, timeout_sec = 120) {
  taxon <- extract_rank_token(rank, taxon)

  build_sql <- function() {
    if (rank == "species") {
      BIEN_trait_species(species = taxon, all.taxonomy = TRUE, source.citation = TRUE, return.query = TRUE)
    } else if (rank == "genus") {
      BIEN_trait_genus(genus = taxon, all.taxonomy = TRUE, source.citation = TRUE, return.query = TRUE)
    } else if (rank == "family") {
      BIEN_trait_family(family = taxon, all.taxonomy = TRUE, source.citation = TRUE, return.query = TRUE)
    } else {
      BIEN_trait_trait(trait = taxon, all.taxonomy = TRUE, source.citation = TRUE, return.query = TRUE)
    }
  }

  sql <- safe_bien_retry(build_sql, timeout_sec = timeout_sec, attempts = 2)
  if (inherits(sql, "bien_error") || !is.character(sql) || !nzchar(sql)) return(NA_integer_)

  sql_clean <- gsub(";\\s*$", "", sql)
  count_sql <- sprintf("SELECT COUNT(*) AS total_records FROM (%s) bien_trait_query", sql_clean)

  bien_sql <- get(".BIEN_sql", envir = asNamespace("BIEN"))
  cnt <- safe_bien_retry(function() {
    bien_sql(query = count_sql, fetch.query = FALSE)
  }, timeout_sec = timeout_sec, attempts = 2)

  if (inherits(cnt, "bien_error") || !is.data.frame(cnt) || nrow(cnt) == 0 || !"total_records" %in% names(cnt)) {
    return(NA_integer_)
  }

  as.integer(cnt$total_records[[1]])
}

# Add diagnostic summary statistics
compute_diagnostics <- function(dat, query_rank, query_taxon, total_available = NA_integer_, max_records = NA_integer_) {
  if (!is.data.frame(dat) || nrow(dat) == 0) {
    return(list(
      total_records = 0,
      total_available_records = if (is.na(total_available)) NA_integer_ else as.integer(total_available),
      records_not_returned = if (is.na(total_available)) NA_integer_ else max(as.integer(total_available), 0L),
      limit_used = if (is.na(max_records)) NA_integer_ else as.integer(max_records),
      unique_species = 0,
      unique_traits = 0,
      coverage_by_trait = data.frame(),
      missingness_summary = data.frame(),
      warnings = "No data returned for query"
    ))
  }
  
  trait_col <- first_existing_col(dat, c("trait_name", "trait", "measurementType"))
  species_col <- first_existing_col(dat, c("scrubbed_species_binomial", "species", "scientific_name"))
  value_col <- first_existing_col(dat, c("trait_value", "value", "measurement"))
  
  # Trait coverage
  coverage <- if (!is.null(trait_col)) {
    dat %>% 
      group_by(.data[[trait_col]]) %>% 
      summarise(n_records = n(), .groups = "drop") %>%
      arrange(desc(n_records))
  } else {
    data.frame(n_records = nrow(dat))
  }
  
  warnings <- c()
  if (nrow(dat) < 50) {
    warnings <- c(warnings, "Small sample size (< 50 records); results may not be representative")
  }
  if (query_rank %in% c("genus", "family")) {
    warnings <- c(warnings, "Genus/family-level queries may mix heterogeneous species and trait methods")
  }
  if (query_rank == "trait-only") {
    warnings <- c(warnings, "Trait-only queries combine all species; verify meaningful comparisons")
  }

  total_available_i <- if (is.na(total_available)) NA_integer_ else as.integer(total_available)
  max_records_i <- if (is.na(max_records)) NA_integer_ else as.integer(max_records)
  records_not_returned <- if (is.na(total_available_i)) NA_integer_ else max(total_available_i - nrow(dat), 0L)

  if (!is.na(total_available_i) && records_not_returned > 0) {
    limit_txt <- if (is.na(max_records_i)) "an active limit" else paste0("limit = ", max_records_i)
    warnings <- c(warnings, sprintf(
      "BIEN contains %d matching trait records; app returned %d (%d more available due to %s).",
      total_available_i,
      nrow(dat),
      records_not_returned,
      limit_txt
    ))
  }
  
  # Check for plot-based traits and highlight plot metadata availability
  plot_trait_col <- first_existing_col(dat, c("is_plot_trait"))
  n_plot_traits <- if (!is.null(plot_trait_col)) sum(dat[[plot_trait_col]], na.rm = TRUE) else 0
  
  if (n_plot_traits > 0) {
    pct_plot <- round(100 * n_plot_traits / nrow(dat), 1)
    warnings <- c(warnings, sprintf(
      "Plot-based traits detected (%.1f%% of records). For full plot metadata (name, sampling protocol, dataset, project details), click the 'url_source' or 'source_citation' links in the download.", 
      pct_plot
    ))
  }
  
  list(
    total_records = nrow(dat),
    total_available_records = total_available_i,
    records_not_returned = records_not_returned,
    limit_used = max_records_i,
    unique_species = if (!is.null(species_col)) n_distinct(dat[[species_col]]) else 0,
    unique_traits = if (!is.null(trait_col)) n_distinct(dat[[trait_col]]) else 0,
    coverage_by_trait = coverage,
    query_rank = query_rank,
    query_taxon = query_taxon,
    warnings = warnings
  )
}

# ============================================================================
# SHINY MODULE: QueryUI & QueryServer
# ============================================================================

queryUI <- function(id) {
  ns <- NS(id)
  div(
    class = "panel panel-primary",
    div(class = "panel-heading", h3("Step 1: Query Builder")),
    div(class = "panel-body",
      div(class = "row",
        div(class = "col-sm-6",
          div(class = "form-group",
            tags$label("Query Rank:", `for` = ns("rank")),
            selectInput(ns("rank"), NULL, 
              choices = c("Species" = "species", "Genus" = "genus", 
                         "Family" = "family", "Trait Only" = "trait-only"),
              selected = "species", width = "100%")
          )
        ),
        div(class = "col-sm-6",
          div(class = "form-group",
            tags$label("Taxon / Trait Name:", `for` = ns("taxon")),
            radioButtons(
              ns("suggest_mode"), NULL,
              choices = c("Suggest taxa" = "taxa", "Suggest traits" = "traits"),
              selected = "taxa",
              inline = TRUE
            ),
            selectizeInput(
              ns("taxon"), NULL,
              choices = NULL,
              selected = "",
              options = list(
                placeholder = "Start typing to search BIEN suggestions...",
                create = FALSE,
                maxOptions = 2000
              ),
              width = "100%"
            ),
            p(
              class = "text-muted",
              style = "margin-top: 6px;",
              "Autocomplete uses BIEN-backed suggestions. You can still type custom values."
            )
          )
        )
      ),
      div(class = "row",
        div(class = "col-sm-6",
          div(class = "form-group",
            tags$label("Max records to sample:", `for` = ns("max_records")),
            numericInput(ns("max_records"), NULL,
                         value = 5000, min = 100, max = 50000, step = 500,
                         width = "100%")
          )
        ),
        div(class = "col-sm-6",
          p(class = "text-muted", style = "margin-top: 28px;",
            "Higher limits may take longer and can increase BIEN timeout risk.")
        )
      ),
      div(
        actionButton(ns("query_btn"), 
                    label = tagList(span(id = ns("query_btn_spinner"), class = "fa fa-spinner fa-spin", style = "display:none; margin-right:6px;"), "Query BIEN"),
                    class = "btn btn-primary btn-lg bien-query-btn", 
                    style = "margin-top: 10px;"),
        textOutput(ns("query_status"))
      )
    )
  )
}

queryServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    reactiveValues(
      query_data = data.frame(),
      diagnostics = NULL,
      is_querying = FALSE,
      error_msg = "",
      suggestion_cache = list()
    ) -> rv

    observeEvent(input$rank, {
      if (!is.null(input$rank) && identical(input$rank, "trait-only") && !identical(input$suggest_mode, "traits")) {
        updateRadioButtons(session, "suggest_mode", selected = "traits")
      }
    }, ignoreInit = TRUE)

    observeEvent(list(input$suggest_mode, input$rank), {
      mode <- if (is.null(input$suggest_mode) || !nzchar(input$suggest_mode)) "taxa" else input$suggest_mode
      rank <- if (is.null(input$rank) || !nzchar(input$rank)) "species" else input$rank
      key <- paste(mode, if (identical(mode, "taxa")) rank else "traits", sep = "::")

      choices <- rv$suggestion_cache[[key]]
      if (is.null(choices)) {
        choices <- if (identical(mode, "traits")) {
          load_trait_suggestions()
        } else {
          cap <- if (identical(rank, "species")) 75000 else if (identical(rank, "genus")) 25000 else 5000
          load_taxon_suggestions(rank = rank, max_choices = cap)
        }
        rv$suggestion_cache[[key]] <- choices
      }

      current <- input$taxon
      selected <- if (!is.null(current) && nzchar(current) && current %in% choices) current else ""
      placeholder <- if (identical(mode, "traits")) {
        "Type to find BIEN trait names (accepted list)."
      } else {
        sprintf("Type to find accepted BIEN %s names.", rank)
      }

      updateSelectizeInput(
        session,
        "taxon",
        choices = choices,
        selected = selected,
        server = TRUE,
        options = list(
          create = FALSE,
          maxOptions = 2000,
          placeholder = placeholder
        )
      )
    }, ignoreInit = FALSE)
    
    observeEvent(input$query_btn, {
      req(input$taxon, nzchar(str_trim(input$taxon)))

      rv$is_querying <- TRUE
      rv$error_msg <- ""

      # Visually disable button and show spinner via plain JS message
      session$sendCustomMessage("queryBtnState", list(
        btnId    = session$ns("query_btn"),
        spinnerId = session$ns("query_btn_spinner"),
        loading  = TRUE
      ))

      tryCatch({
        taxon_clean <- normalize_taxon_name(input$taxon)
        max_records <- suppressWarnings(as.integer(input$max_records))
        if (is.na(max_records) || max_records < 100) max_records <- 5000
        max_records <- min(max_records, 50000)

        withProgress(message = "Querying BIEN...",
                     detail = "This may take 30\u201360 seconds",
                     value = 0.3, {
          dat <- query_bien_traits(rank = input$rank, taxon = taxon_clean,
                                   max_records = max_records, timeout_sec = 120)
          total_available <- query_bien_total_records(rank = input$rank, taxon = taxon_clean,
                                                     timeout_sec = 120)
          bien_err <- attr(dat, "bien_error", exact = TRUE)
          incProgress(0.7, message = "Processing results...")
          rv$query_data <- dat
          rv$diagnostics <- compute_diagnostics(
            dat,
            input$rank,
            taxon_clean,
            total_available = total_available,
            max_records = max_records
          )
          rv$error_msg <- if (is.character(bien_err) && nzchar(bien_err)) {
            paste("BIEN query error:", bien_err)
          } else if (nrow(dat) == 0) {
            "No trait records found for this query. For genus/family mode, try a plain name (for example: Prunus)."
          } else {
            ""
          }
        })
      }, error = function(e) {
        rv$query_data <- data.frame()
        rv$diagnostics <- NULL
        rv$error_msg <- paste("Error:", conditionMessage(e))
      })

      # Restore button
      session$sendCustomMessage("queryBtnState", list(
        btnId    = session$ns("query_btn"),
        spinnerId = session$ns("query_btn_spinner"),
        loading  = FALSE
      ))
      rv$is_querying <- FALSE
    })
    
    output$query_status <- renderText({
      if (rv$is_querying) {
        "Querying BIEN (this may take 30-60 seconds)..."
      } else if (nzchar(rv$error_msg)) {
        paste("Status:", rv$error_msg)
      } else if (nrow(rv$query_data) > 0) {
        if (!is.null(rv$diagnostics$total_available_records) && !is.na(rv$diagnostics$total_available_records)) {
          paste(
            "✓ Returned", nrow(rv$query_data), "of", rv$diagnostics$total_available_records,
            "BIEN records across", rv$diagnostics$unique_species, "species",
            "(limit:", input$max_records, ")"
          )
        } else {
          paste("✓ Found", nrow(rv$query_data), "records across",
                rv$diagnostics$unique_species, "species",
                "(limit:", input$max_records, ")")
        }
      } else {
        ""
      }
    })
    
    reactive({
      list(
        data = rv$query_data,
        diagnostics = rv$diagnostics,
        rank = input$rank,
        taxon = input$taxon,
        max_records = input$max_records,
        is_loading = rv$is_querying
      )
    })
  })
}

# ============================================================================
# SHINY MODULE: ScopeUI & ScopeServer
# ============================================================================

scopeUI <- function(id) {
  ns <- NS(id)
  div(
    class = "panel panel-info",
    div(class = "panel-heading", h3("Step 2: Availability & Scope")),
    div(class = "panel-body",
      uiOutput(ns("scope_display")),
      h4("Trait Coverage:"),
      DTOutput(ns("scope_coverage"))
    )
  )
}

scopeServer <- function(id, query_result) {
  moduleServer(id, function(input, output, session) {
    output$scope_display <- renderUI({
      req(query_result())
      qr <- query_result()
      
      if (nrow(qr$data) == 0) {
        return(p("Query data first to see availability.", style = "color: #666;"))
      }
      
      diag <- qr$diagnostics
      
      tagList(
        div(class = "alert alert-info",
          span(class = "glyphicon glyphicon-info-sign"),
          strong(" Data Availability:"),
          p(paste("Found", diag$total_records, "trait observations across",
                  diag$unique_species, "species with", diag$unique_traits, "trait types"))
        ),
        if (!is.null(diag$total_available_records) && !is.na(diag$total_available_records)) {
          div(class = if (isTRUE(diag$records_not_returned > 0)) "alert alert-warning" else "alert alert-success",
            span(class = "glyphicon glyphicon-stats"),
            strong(" BIEN Total Match Count:"),
            p(paste0(
              "Returned ", diag$total_records,
              " of ", diag$total_available_records,
              " matching BIEN records",
              if (!is.na(diag$records_not_returned) && diag$records_not_returned > 0) {
                paste0(" (", diag$records_not_returned, " more available).")
              } else {
                "."
              }
            ))
          )
        },
        if (length(diag$warnings) > 0) {
          div(class = "alert alert-warning",
            span(class = "glyphicon glyphicon-warning-sign"),
            strong(" Scope Warnings:"),
            tags$ul(lapply(diag$warnings, function(w) tags$li(w)))
          )
        }
      )
    })

    output$scope_coverage <- renderDT({
      req(query_result())
      diag <- query_result()$diagnostics
      req(!is.null(diag$coverage_by_trait))
      datatable(diag$coverage_by_trait, options = list(pageLength = 5), rownames = FALSE)
    })
    
    reactive({
      req(query_result())
      list(
        confirmed = TRUE,
        diagnostics = query_result()$diagnostics
      )
    })
  })
}

# ============================================================================
# SHINY MODULE: DiagnosticsUI & DiagnosticsServer
# ============================================================================

diagnosticsUI <- function(id) {
  ns <- NS(id)
  div(
    class = "panel panel-warning",
    div(class = "panel-heading", h3("Step 4: Diagnostics & Preview")),
    div(class = "panel-body",
      uiOutput(ns("diagnostics_display")),
      h4("Data Preview (first 10 rows):"),
      DTOutput(ns("diagnostics_preview"))
    )
  )
}

diagnosticsServer <- function(id, query_result) {
  moduleServer(id, function(input, output, session) {
    output$diagnostics_display <- renderUI({
      req(query_result())
      qr <- query_result()
      
      if (nrow(qr$data) == 0) {
        return(p("Run query first to see diagnostics.", style = "color: #666;"))
      }
      
      diag <- qr$diagnostics
      
      tagList(
        div(class = "row",
          div(class = "col-sm-4",
            div(class = "panel panel-default",
              div(class = "panel-heading", "Total Records"),
              div(class = "panel-body", h3(diag$total_records, style = "margin: 0;"))
            )
          ),
          div(class = "col-sm-4",
            div(class = "panel panel-default",
              div(class = "panel-heading", "Unique Species"),
              div(class = "panel-body", h3(diag$unique_species, style = "margin: 0;"))
            )
          ),
          div(class = "col-sm-4",
            div(class = "panel panel-default",
              div(class = "panel-heading", "Trait Types"),
              div(class = "panel-body", h3(diag$unique_traits, style = "margin: 0;"))
            )
          )
        )
      )
    })

    output$diagnostics_preview <- renderDT({
      req(query_result())
      qr <- query_result()
      req(nrow(qr$data) > 0)
      datatable(head(qr$data, 10), options = list(
        scrollX = TRUE,
        pageLength = 5,
        columnDefs = list(list(width = "100px", targets = "_all"))
      ), rownames = FALSE)
    })
    
    reactive({
      req(query_result())
      list(
        data = query_result()$data,
        diagnostics = query_result()$diagnostics
      )
    })
  })
}

# ============================================================================
# SHINY MODULE: RecordsUI & RecordsServer
# ============================================================================

recordsUI <- function(id) {
  ns <- NS(id)
  div(
    class = "panel panel-default",
    div(class = "panel-heading", h3("Step 5: Complete Record Set")),
    div(class = "panel-body",
      uiOutput(ns("records_display")),
      DTOutput(ns("records_table"))
    )
  )
}

recordsServer <- function(id, query_result) {
  moduleServer(id, function(input, output, session) {
    output$records_display <- renderUI({
      req(query_result())
      dat <- query_result()$data
      
      if (nrow(dat) == 0) {
        return(p("No records to display.", style = "color: #666;"))
      }
      
      tagList(p(strong(paste("Showing all", nrow(dat), "records"))))
    })

    output$records_table <- renderDT({
      req(query_result())
      dat <- query_result()$data
      req(nrow(dat) > 0)
      datatable(dat, options = list(
        scrollX = TRUE,
        pageLength = 10,
        columnDefs = list(list(width = "100px", targets = "_all")),
        dom = "frtip"
      ), rownames = FALSE)
    })
    
    reactive({
      req(query_result())
      query_result()$data
    })
  })
}

# ============================================================================
# SHINY MODULE: ProvenanceUI & ProvenanceServer
# ============================================================================

provenanceUI <- function(id) {
  ns <- NS(id)
  div(
    class = "panel panel-default",
    div(class = "panel-heading", h3("Step 6: Provenance & Reproducibility")),
    div(class = "panel-body",
      uiOutput(ns("provenance_display"))
    )
  )
}

provenanceServer <- function(id, query_result) {
  moduleServer(id, function(input, output, session) {
    output$provenance_display <- renderUI({
      req(query_result())
      qr <- query_result()
      
      manifest <- list(
        query_rank = qr$rank,
        query_taxon = qr$taxon,
        max_records = qr$max_records,
        timestamp_utc = format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC"),
        app_version = "BIEN Trait Gateway v1.0",
        records = nrow(qr$data),
        total_available_records = qr$diagnostics$total_available_records,
        records_not_returned = qr$diagnostics$records_not_returned,
        unique_species = qr$diagnostics$unique_species,
        unique_traits = qr$diagnostics$unique_traits,
        download_all_traits = isTRUE(qr$download_all),
        selected_traits = qr$selected_traits
      )
      
      manifest_json <- toJSON(manifest, pretty = TRUE)
      
      tagList(
        div(
          h4("Query Manifest:"),
          p("Use this for reproducibility and citation:"),
          tags$pre(manifest_json, style = "background: #f5f5f5; padding: 10px;"),
          downloadButton(session$ns("dl_manifest"), "Download Manifest"),
          downloadButton(session$ns("dl_script"), "Download R Script")
        )
      )
    })
    
    reactive({
      req(query_result())
      manifest <- list(
        query_rank = query_result()$rank,
        query_taxon = query_result()$taxon,
        max_records = query_result()$max_records,
        timestamp_utc = format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC"),
        app_version = "BIEN Trait Gateway v1.0",
        records = nrow(query_result()$data),
        total_available_records = query_result()$diagnostics$total_available_records,
        records_not_returned = query_result()$diagnostics$records_not_returned,
        download_all_traits = isTRUE(query_result()$download_all),
        selected_traits = query_result()$selected_traits
      )
      manifest
    })

    output$dl_manifest <- downloadHandler(
      filename = function() {
        sprintf("bien_query_manifest_%s.json", format(Sys.time(), "%Y%m%d_%H%M%S"))
      },
      content = function(file) {
        req(query_result())
        manifest <- list(
          query_rank = query_result()$rank,
          query_taxon = query_result()$taxon,
          max_records = query_result()$max_records,
          timestamp_utc = format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC"),
          app_version = "BIEN Trait Gateway v1.0",
          records = nrow(query_result()$data),
          total_available_records = query_result()$diagnostics$total_available_records,
          records_not_returned = query_result()$diagnostics$records_not_returned,
          download_all_traits = isTRUE(query_result()$download_all),
          selected_traits = query_result()$selected_traits,
          diagnostics = query_result()$diagnostics
        )
        writeLines(toJSON(manifest, pretty = TRUE, auto_unbox = TRUE), con = file)
      }
    )

    output$dl_script <- downloadHandler(
      filename = function() {
        sprintf("bien_gateway_repro_%s.R", format(Sys.time(), "%Y%m%d_%H%M%S"))
      },
      content = function(file) {
        req(query_result())
        rank <- query_result()$rank
        taxon <- query_result()$taxon
        max_records <- suppressWarnings(as.integer(query_result()$max_records))
        if (is.na(max_records) || max_records < 100) max_records <- 5000
        max_records <- min(max_records, 50000)
        
        # Build the query call line
        call_line <- if (rank == "species") {
          sprintf("BIEN::BIEN_trait_species(species = \"%s\", all.taxonomy = TRUE, source.citation = TRUE, limit = %d)", taxon, max_records)
        } else if (rank == "genus") {
          sprintf("BIEN::BIEN_trait_genus(genus = \"%s\", all.taxonomy = TRUE, source.citation = TRUE, limit = %d)", taxon, max_records)
        } else if (rank == "family") {
          sprintf("BIEN::BIEN_trait_family(family = \"%s\", all.taxonomy = TRUE, source.citation = TRUE, limit = %d)", taxon, max_records)
        } else {
          # For trait-only: use expanded trait names if available
          queried_traits <- attr(query_result()$data, "queried_traits")
          if (length(queried_traits) > 1) {
            traits_str <- paste0(sprintf("\"%s\"", queried_traits), collapse = ", ")
            sprintf("dplyr::bind_rows(lapply(c(%s), function(t) BIEN::BIEN_trait_trait(trait = t, all.taxonomy = TRUE, source.citation = TRUE, limit = %d)))", 
                   traits_str, max_records)
          } else if (length(queried_traits) == 1) {
            sprintf("BIEN::BIEN_trait_trait(trait = \"%s\", all.taxonomy = TRUE, source.citation = TRUE, limit = %d)", 
                   queried_traits[1], max_records)
          } else {
            sprintf("BIEN::BIEN_trait_trait(trait = \"%s\", all.taxonomy = TRUE, source.citation = TRUE, limit = %d)", 
                   taxon, max_records)
          }
        }

        script <- c(
          "# Reproducible BIEN query script generated by BIEN Trait Data Gateway",
          sprintf("# Generated: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC")),
          "library(BIEN)",
          "library(dplyr)",
          "",
          sprintf("query_rank <- \"%s\"", rank),
          sprintf("query_taxon <- \"%s\"", taxon),
          sprintf("max_records <- %d", max_records),
          "",
          sprintf("dat <- %s", call_line),
          "write.csv(dat, 'bien_gateway_export.csv', row.names = FALSE)",
          "cat('Rows:', nrow(dat), '\\n')"
        )
        writeLines(script, con = file)
      }
    )
  })
}

# ============================================================================
# SHINY MODULE: DownloadGateUI & DownloadGateServer
# ============================================================================

downloadGateUI <- function(id) {
  ns <- NS(id)
  div(
    class = "panel panel-success",
    div(class = "panel-heading", h3("Step 7: Pre-Download Checklist")),
    div(class = "panel-body",
      uiOutput(ns("checklist_display"))
    )
  )
}

# ============================================================================
# SHINY MODULE: TraitSelectUI & TraitSelectServer
# ============================================================================

traitSelectUI <- function(id) {
  ns <- NS(id)
  div(
    class = "panel panel-primary",
    div(class = "panel-heading", h3("Step 3: Select Traits To Download")),
    div(class = "panel-body",
      uiOutput(ns("selector_controls")),
      h4("Traits Returned By Query:"),
      DTOutput(ns("trait_summary")),
      h4("Species x Trait Coverage Matrix (top 50 species):"),
      DTOutput(ns("species_trait_matrix"))
    )
  )
}

traitSelectServer <- function(id, query_result) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    trait_summary_tbl <- reactive({
      req(query_result())
      dat <- query_result()$data
      if (!is.data.frame(dat) || nrow(dat) == 0) return(data.frame())

      trait_col <- first_existing_col(dat, c("trait_name", "trait", "measurementType"))
      if (is.null(trait_col)) return(data.frame())

      species_col <- first_existing_col(dat, c("scrubbed_species_binomial", "species", "scientific_name"))
      out <- dat %>%
        group_by(.data[[trait_col]]) %>%
        summarise(
          n_records = n(),
          n_species = if (!is.null(species_col)) n_distinct(.data[[species_col]]) else NA_integer_,
          .groups = "drop"
        ) %>%
        rename(trait_name = 1) %>%
        arrange(desc(n_records))
      out
    })

    observeEvent(trait_summary_tbl(), {
      tbl <- trait_summary_tbl()
      choices <- if (nrow(tbl) > 0) tbl$trait_name else character(0)
      updateSelectInput(session, "selected_traits", choices = choices, selected = choices)
      updateCheckboxInput(session, "download_all", value = FALSE)
    }, ignoreInit = FALSE)

    # Auto-uncheck "download all" when user deselects traits in the picker
    observeEvent(input$selected_traits, {
      tbl <- trait_summary_tbl()
      if (nrow(tbl) == 0) return()
      all_choices <- tbl$trait_name
      if (!isTRUE(input$download_all)) return()  # already unchecked, nothing to do
      if (!setequal(input$selected_traits, all_choices)) {
        updateCheckboxInput(session, "download_all", value = FALSE)
      }
    }, ignoreNULL = FALSE, ignoreInit = TRUE)

    # Clicking rows in the trait table should drive the same selection used for download.
    observeEvent(input$trait_summary_rows_selected, {
      idx <- input$trait_summary_rows_selected
      if (is.null(idx) || length(idx) == 0) return()
      tbl <- trait_summary_tbl()
      if (nrow(tbl) == 0) return()
      idx <- idx[idx >= 1 & idx <= nrow(tbl)]
      if (length(idx) == 0) return()
      picked_from_table <- as.character(tbl$trait_name[idx])
      updateSelectInput(session, "selected_traits", selected = picked_from_table)
      updateCheckboxInput(session, "download_all", value = FALSE)
    }, ignoreInit = TRUE)

    # When user re-checks "download all", re-select all traits
    observeEvent(input$download_all, {
      if (isTRUE(input$download_all)) {
        tbl <- trait_summary_tbl()
        choices <- if (nrow(tbl) > 0) tbl$trait_name else character(0)
        updateSelectInput(session, "selected_traits", choices = choices, selected = choices)
      }
    }, ignoreInit = TRUE)

    output$selector_controls <- renderUI({
      req(query_result())
      dat <- query_result()$data

      if (!is.data.frame(dat) || nrow(dat) == 0) {
        return(p("Run a query first to choose traits.", style = "color: #666;"))
      }

      tbl <- trait_summary_tbl()
      if (nrow(tbl) == 0) {
        return(div(
          class = "alert alert-warning",
          strong("Trait column not detected in returned data."),
          p("All rows will be kept for preview and download.")
        ))
      }

      tagList(
        div(
          class = "alert alert-warning",
          strong("Important: "),
          "If this box is checked, your CSV will include all returned traits, even if only some traits are selected below."
        ),
        checkboxInput(
          ns("download_all"),
          "Download all returned traits (override trait picker below)",
          value = FALSE
        ),
        selectInput(
          ns("selected_traits"),
          "Choose one or more traits:",
          choices = tbl$trait_name,
          selected = tbl$trait_name,
          multiple = TRUE,
          width = "100%"
        ),
        p(
          class = "text-muted",
          "Tip: uncheck the box above to download only the selected traits."
        )
      )
    })

    output$trait_summary <- renderDT({
      tbl <- trait_summary_tbl()
      req(nrow(tbl) > 0)
      datatable(
        tbl,
        options = list(pageLength = 8),
        selection = list(mode = "multiple", target = "row"),
        rownames = FALSE
      )
    })

    species_trait_matrix_tbl <- reactive({
      req(query_result())
      dat <- query_result()$data
      if (!is.data.frame(dat) || nrow(dat) == 0) return(data.frame())

      trait_col <- first_existing_col(dat, c("trait_name", "trait", "measurementType"))
      species_col <- first_existing_col(dat, c("scrubbed_species_binomial", "species", "scientific_name"))
      if (is.null(trait_col) || is.null(species_col)) return(data.frame())

      sp <- as.character(dat[[species_col]])
      tr <- as.character(dat[[trait_col]])
      keep <- !is.na(sp) & nzchar(sp) & !is.na(tr) & nzchar(tr)
      sp <- sp[keep]
      tr <- tr[keep]
      if (length(sp) == 0) return(data.frame())

      mat <- table(sp, tr)
      if (nrow(mat) == 0 || ncol(mat) == 0) return(data.frame())

      # Keep matrix compact for UI performance/readability.
      top_idx <- order(rowSums(mat), decreasing = TRUE)
      top_idx <- head(top_idx, 50)
      mat_top <- mat[top_idx, , drop = FALSE]

      out <- as.data.frame.matrix(mat_top)
      out$species <- rownames(out)
      out$total_records <- rowSums(mat_top)
      out <- out[, c("species", "total_records", setdiff(names(out), c("species", "total_records"))), drop = FALSE]
      rownames(out) <- NULL
      out
    })

    output$species_trait_matrix <- renderDT({
      mat_tbl <- species_trait_matrix_tbl()
      req(nrow(mat_tbl) > 0)
      datatable(
        mat_tbl,
        options = list(
          pageLength = 10,
          scrollX = TRUE,
          autoWidth = TRUE
        ),
        rownames = FALSE
      )
    })

    reactive({
      req(query_result())
      base <- query_result()
      base_rank <- if (!is.null(base$rank)) base$rank else "species"
      base_taxon <- if (!is.null(base$taxon)) base$taxon else ""
      dat <- query_result()$data
      if (!is.data.frame(dat) || nrow(dat) == 0) {
        return(list(
          data = data.frame(),
          selected_traits = character(0),
          all_traits = character(0),
          download_all = TRUE,
          trait_col = NULL,
          rank = base_rank,
          taxon = base_taxon,
          max_records = base$max_records,
          diagnostics = compute_diagnostics(data.frame(), base_rank, base_taxon),
          is_loading = isTRUE(base$is_loading),
          base = base
        ))
      }

      trait_col <- first_existing_col(dat, c("trait_name", "trait", "measurementType"))
      if (is.null(trait_col)) {
        return(list(
          data = dat,
          selected_traits = character(0),
          all_traits = character(0),
          download_all = TRUE,
          trait_col = NULL,
          rank = base_rank,
          taxon = base_taxon,
          max_records = base$max_records,
          diagnostics = compute_diagnostics(dat, base_rank, base_taxon),
          is_loading = isTRUE(base$is_loading),
          base = base
        ))
      }

      all_traits <- unique(as.character(dat[[trait_col]]))
      all_traits <- all_traits[!is.na(all_traits) & nzchar(all_traits)]

      is_all <- isTRUE(input$download_all)
      picked <- input$selected_traits

      # Prefer explicit table-row selections when present.
      row_idx <- input$trait_summary_rows_selected
      if (!is.null(row_idx) && length(row_idx) > 0) {
        tbl <- trait_summary_tbl()
        row_idx <- row_idx[row_idx >= 1 & row_idx <= nrow(tbl)]
        if (length(row_idx) > 0) {
          picked <- as.character(tbl$trait_name[row_idx])
        }
      }

      if (is.null(picked)) picked <- character(0)

      filtered <- if (is_all) {
        dat
      } else if (length(picked) == 0) {
        dat[0, , drop = FALSE]
      } else {
        dat %>% filter(.data[[trait_col]] %in% picked)
      }

      list(
        data = filtered,
        selected_traits = if (is_all) all_traits else picked,
        all_traits = all_traits,
        download_all = is_all,
        trait_col = trait_col,
        rank = base_rank,
        taxon = base_taxon,
        max_records = base$max_records,
        diagnostics = compute_diagnostics(filtered, base_rank, base_taxon),
        is_loading = isTRUE(base$is_loading),
        base = base
      )
    })
  })
}

downloadGateServer <- function(id, query_result) {
  moduleServer(id, function(input, output, session) {
    ns <- NS(id)
    
    checklist_items <- c(
      "I understand availability (records in database) ≠ abundance (prevalence in nature)",
      "I have reviewed the taxonomic reconciliation for my queries",
      "I acknowledge this data represents biased sampling across studies",
      "I understand trait measurement methods vary across sources",
      "I have checked for missing data and small sample sizes",
      "I will cite this data with the provided provenance manifest"
    )
    
    output$checklist_display <- renderUI({
      req(query_result())
      
      if (nrow(query_result()$data) == 0) {
        return(p("Query data first.", style = "color: #666;"))
      }

      download_mode <- if (isTRUE(query_result()$download_all)) {
        "Download mode: ALL returned traits"
      } else {
        sprintf("Download mode: %d selected trait(s)", length(query_result()$selected_traits))
      }
      
      tagList(
        div(
          class = "alert alert-info",
          strong(download_mode)
        ),
        div(class = "alert alert-danger",
          span(class = "glyphicon glyphicon-exclamation-sign"),
          strong(" Important:"), p("Before downloading, confirm you understand the following:")
        ),
        div(
          lapply(seq_along(checklist_items), function(i) {
            div(class = "checkbox",
              tags$label(
                checkboxInput(ns(paste0("check_", i)), NULL, value = FALSE),
                checklist_items[[i]]
              )
            )
          })
        ),
        div(style = "margin-top: 20px;",
          downloadButton(ns("download_data"), "Download Data as CSV", 
                        class = "btn btn-success btn-lg bien-download-btn")
        )
      )
    })
    
    output$download_data <- downloadHandler(
      filename = function() {
        sprintf("BIEN_traits_%s.csv", format(Sys.time(), "%Y%m%d_%H%M%S"))
      },
      content = function(file) {
        req(query_result())
        all_checked <- all(vapply(seq_along(checklist_items), function(i) {
          isTRUE(input[[paste0("check_", i)]])
        }, logical(1)))
        
        if (!all_checked) {
          stop("Please check all checklist items before downloading.")
        }

        # Final safety filter so download always matches the Step 3 selection.
        qr <- query_result()
        dat <- qr$data
        trait_col <- qr$trait_col
        selected_traits <- qr$selected_traits

        if (!isTRUE(qr$download_all) && !is.null(trait_col) && is.data.frame(dat)) {
          if (is.null(selected_traits) || length(selected_traits) == 0) {
            dat <- dat[0, , drop = FALSE]
          } else {
            dat <- dat %>% filter(.data[[trait_col]] %in% selected_traits)
          }
        }
        
        # Reorganize columns to surface plot metadata where present
        dat <- organize_columns_for_export(dat)

        write.csv(dat, file, row.names = FALSE)
      }
    )
    
    reactive({
      list(
        can_download = all(vapply(seq_along(checklist_items), 
                                 function(i) isTRUE(input[[paste0("check_", i)]]), 
                                 logical(1)))
      )
    })
  })
}

# ============================================================================
# MAIN UI
# ============================================================================

ui <- fluidPage(
  tags$head(
    tags$link(rel = "stylesheet",
      href = "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/4.7.0/css/font-awesome.min.css"),
    tags$script(HTML("
      Shiny.addCustomMessageHandler('queryBtnState', function(msg) {
        var btn = $('#' + msg.btnId);
        var spinner = $('#' + msg.spinnerId);
        if (msg.loading) {
          btn.prop('disabled', true)
             .removeClass('btn-primary').addClass('btn-warning');
          spinner.show();
        } else {
          btn.prop('disabled', false)
             .removeClass('btn-warning').addClass('btn-primary');
          spinner.hide();
        }
      });
    "))
  ),
  div(class = "container-fluid",
    div(class = "page-header",
      div(class = "bien-header-brand",
        tags$img(src = "bien.png", alt = "BIEN logo", class = "bien-logo"),
        div(
          h1("BIEN Trait Data Gateway", tags$small("Availability-First Access to Trait Observations")),
          p("Query traits by species, genus, family, or trait type with full provenance tracking")
        )
      )
    ),

    tabsetPanel(
      id = "workflow_tabs",
      type = "tabs",
      tabPanel("Step 1: Query", queryUI("query")),
      tabPanel("Step 2: Scope", scopeUI("scope")),
      tabPanel("Step 3: Traits", traitSelectUI("traitSelect")),
      tabPanel("Step 4: Diagnostics", diagnosticsUI("diagnostics")),
      tabPanel("Step 5: Records", recordsUI("records")),
      tabPanel("Step 6: Provenance", provenanceUI("provenance")),
      tabPanel("Step 7: Download", downloadGateUI("downloadGate"))
    ),
    
    hr(),
    p(class = "text-muted", 
      "Built with BIEN R package. All data subject to BIEN terms of use.",
      " | Query timestamp: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S UTC"))
  ),
  tags$head(tags$style(HTML("
    :root {
      --bien-blue: #2f79b7;
      --bien-blue-deep: #1f5b8f;
      --bien-green: #74b64a;
      --bien-green-deep: #4e8c2c;
      --panel-border: #cfe2f3;
    }
    body {
      padding: 20px 0;
      background: linear-gradient(180deg, #f7fbff 0%, #fbfef9 100%);
      color: #24445f;
    }
    .page-header {
      padding: 20px;
      background: linear-gradient(180deg, #ffffff 0%, #f2f9ff 100%);
      border-bottom: 1px solid var(--panel-border);
      margin: -20px 0 20px 0;
      box-shadow: 0 3px 12px rgba(31, 91, 143, 0.08);
    }
    .bien-header-brand {
      display: flex;
      align-items: center;
      gap: 16px;
      flex-wrap: wrap;
    }
    .bien-logo {
      height: 62px;
      width: auto;
      filter: drop-shadow(0 2px 4px rgba(0, 0, 0, 0.12));
    }
    .page-header h1 {
      color: var(--bien-blue-deep);
      margin-top: 0;
      margin-bottom: 8px;
    }
    .page-header p {
      color: #426988;
      margin-bottom: 0;
      max-width: 920px;
    }
    .panel {
      margin-bottom: 20px;
      border-color: var(--panel-border);
      box-shadow: 0 2px 8px rgba(47, 121, 183, 0.08);
    }
    .panel-primary > .panel-heading {
      background: linear-gradient(90deg, var(--bien-blue), var(--bien-green));
      border-color: var(--bien-blue-deep);
      color: #fff;
    }
    .panel-info > .panel-heading,
    .panel-warning > .panel-heading,
    .panel-success > .panel-heading,
    .panel-default > .panel-heading {
      background: linear-gradient(180deg, #ecf6ff 0%, #f4fbef 100%);
      color: var(--bien-blue-deep);
      border-color: var(--panel-border);
    }
    .nav-tabs {
      margin-bottom: 15px;
      border-bottom: 1px solid var(--panel-border);
    }
    .nav-tabs > li > a {
      font-weight: 600;
      color: #2f5f86;
      border-radius: 8px 8px 0 0;
    }
    .nav-tabs > li.active > a,
    .nav-tabs > li.active > a:focus,
    .nav-tabs > li.active > a:hover {
      color: var(--bien-blue-deep);
      background: linear-gradient(180deg, #ecf6ff 0%, #f4fbef 100%);
      border: 1px solid var(--panel-border);
      border-bottom-color: #fff;
    }
    .tab-content {
      background: #fff;
      border: 1px solid var(--panel-border);
      border-top: 0;
      padding: 15px;
    }
    .bien-query-btn {
      min-width: 180px;
      width: auto;
      border-radius: 10px;
      padding: 11px 18px;
      border: 1px solid var(--bien-blue-deep);
      background: linear-gradient(180deg, #4f98d8 0%, var(--bien-blue) 55%, var(--bien-blue-deep) 100%);
      box-shadow: 0 4px 0 #18456f, 0 8px 16px rgba(31, 91, 143, 0.25);
      text-shadow: 0 1px 0 rgba(0, 0, 0, 0.2);
      transition: transform 0.08s ease, box-shadow 0.08s ease, filter 0.2s ease;
    }
    .bien-query-btn:hover,
    .bien-query-btn:focus {
      filter: brightness(1.04);
      transform: translateY(-1px);
      box-shadow: 0 5px 0 #18456f, 0 10px 16px rgba(31, 91, 143, 0.24);
    }
    .bien-query-btn:active {
      transform: translateY(2px);
      box-shadow: 0 2px 0 #18456f, 0 4px 8px rgba(31, 91, 143, 0.2);
    }
    .btn-warning.bien-query-btn {
      border-color: #a97816;
      background: linear-gradient(180deg, #ffdd8f 0%, #f1b84f 55%, #bf7f12 100%);
      box-shadow: 0 4px 0 #85580d, 0 8px 14px rgba(145, 103, 28, 0.22);
      color: #3f2a00;
      text-shadow: none;
    }
    .bien-download-btn {
      min-width: 220px;
      width: auto;
      border-radius: 10px;
      padding: 11px 18px;
      border: 1px solid var(--bien-green-deep);
      background: linear-gradient(180deg, #9acf6d 0%, var(--bien-green) 55%, var(--bien-green-deep) 100%);
      box-shadow: 0 4px 0 #386620, 0 8px 16px rgba(62, 112, 36, 0.24);
      text-shadow: 0 1px 0 rgba(0, 0, 0, 0.2);
      transition: transform 0.08s ease, box-shadow 0.08s ease, filter 0.2s ease;
    }
    .bien-download-btn:hover,
    .bien-download-btn:focus {
      filter: brightness(1.04);
      transform: translateY(-1px);
      box-shadow: 0 5px 0 #386620, 0 10px 16px rgba(62, 112, 36, 0.24);
    }
    .bien-download-btn:active {
      transform: translateY(2px);
      box-shadow: 0 2px 0 #386620, 0 4px 8px rgba(62, 112, 36, 0.2);
    }
  ")))
)

# ============================================================================
# MAIN SERVER
# ============================================================================

server <- function(input, output, session) {
  query_result <- queryServer("query")
  scope_result <- scopeServer("scope", query_result)
  trait_result <- traitSelectServer("traitSelect", query_result)
  diag_result <- diagnosticsServer("diagnostics", trait_result)
  records_result <- recordsServer("records", trait_result)
  prov_result <- provenanceServer("provenance", trait_result)
  download_result <- downloadGateServer("downloadGate", trait_result)
}

# ============================================================================
# RUN APP
# ============================================================================

shinyApp(ui, server)
