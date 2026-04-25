# BIEN Trait Data Gateway - Modular Shiny App
# Build: April 20, 2026
# Features: 4 query modes (species/genus/family/trait-only), availability-first gating,
#           mandatory pre-download checklist, full provenance tracking

suppressPackageStartupMessages({
  required_packages <- c("shiny", "BIEN", "dplyr", "tidyr", "stringr", "DT", "jsonlite", "leaflet")
  missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing_packages) > 0) {
    stop(paste0("Missing packages: ", paste(missing_packages, collapse = ", ")))
  }

  library(shiny)
  library(BIEN)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(DT)
  library(jsonlite)
  library(leaflet)
})

.bien_trait_catalog_cache <- NULL
.bien_taxon_suggestion_cache <- list()

.bien_taxon_suggestion_fallback <- list(
  genus = c("Pinus", "Quercus", "Abies", "Picea", "Populus", "Salix", "Acer", "Arctostaphylos"),
  species = c("Pinus ponderosa", "Quercus agrifolia", "Populus tremuloides"),
  family = c("Pinaceae", "Fagaceae", "Salicaceae")
)

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
  timeout_sec <- suppressWarnings(as.numeric(timeout_sec))
  if (is.na(timeout_sec) || !is.finite(timeout_sec) || timeout_sec <= 0) {
    timeout_sec <- 120
  }

  setTimeLimit(elapsed = timeout_sec, transient = TRUE)
  on.exit(setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE), add = TRUE)

  tryCatch(expr, error = function(e) {
    structure(list(error = conditionMessage(e)), class = "bien_error")
  })
}

is_bien_connection_slot_error <- function(msg) {
  if (is.null(msg) || !length(msg)) return(FALSE)
  msg <- paste(as.character(msg), collapse = " ")
  if (!nzchar(msg)) return(FALSE)

  patterns <- c(
    "remaining connection slots are reserved",
    "too many connections",
    "too many clients already"
  )

  any(vapply(patterns, function(p) grepl(p, msg, ignore.case = TRUE), logical(1)))
}

format_bien_error <- function(err_msg, context = c("query", "suggestions")) {
  context <- match.arg(context)
  if (is_bien_connection_slot_error(err_msg)) {
    if (identical(context, "query")) {
      return("BIEN database is temporarily at connection capacity. Please retry in 1-2 minutes.")
    }
    return("Taxon suggestions are temporarily unavailable (BIEN database is busy). You can still type and submit a taxon name directly.")
  }
  as.character(err_msg)
}

safe_bien_retry <- function(call_fn, timeout_sec = 120, attempts = 3, sleep_sec = 1) {
  last <- NULL
  for (i in seq_len(attempts)) {
    last <- safe_bien_call(call_fn(), timeout_sec = timeout_sec)
    if (!inherits(last, "bien_error")) {
      return(last)
    }
    if (is_bien_connection_slot_error(last$error)) {
      break
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

sanitize_for_dt <- function(df) {
  if (!is.data.frame(df)) {
    return(data.frame())
  }

  df <- ensure_unique_names(df)
  nm <- names(df)
  blank_idx <- is.na(nm) | !nzchar(nm)
  if (any(blank_idx)) {
    nm[blank_idx] <- paste0("col_", which(blank_idx))
    names(df) <- make.unique(nm, sep = "__dup")
  }

  # DT fails on list columns for some BIEN responses; coerce safely to character.
  for (i in seq_along(df)) {
    col <- df[[i]]
    if (inherits(col, "POSIXlt")) {
      df[[i]] <- as.POSIXct(col)
      next
    }
    if (is.list(col) && !is.data.frame(col)) {
      df[[i]] <- vapply(col, function(x) {
        if (is.null(x)) return("")
        if (length(x) == 0) return("")
        if (length(x) == 1 && !is.list(x)) {
          return(as.character(x))
        }
        out <- tryCatch(jsonlite::toJSON(x, auto_unbox = TRUE), error = function(e) NA_character_)
        if (is.na(out)) paste(as.character(unlist(x, use.names = FALSE)), collapse = "; ") else as.character(out)
      }, character(1))
    }
  }

  df
}

load_trait_suggestions <- function(timeout_sec = 120) {
  if (is.null(.bien_trait_catalog_cache)) {
    trait_catalog <- safe_bien_retry(function() {
      BIEN_trait_list()
    }, timeout_sec = timeout_sec, attempts = 2)
    if (!inherits(trait_catalog, "bien_error") && is.data.frame(trait_catalog) && nrow(trait_catalog) > 0) {
      .bien_trait_catalog_cache <<- trait_catalog
    }
  } else {
    trait_catalog <- .bien_trait_catalog_cache
  }

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
  
  if (is.null(.bien_trait_catalog_cache)) {
    trait_catalog <- safe_bien_retry(function() {
      BIEN_trait_list()
    }, timeout_sec = timeout_sec, attempts = 2)
    if (!inherits(trait_catalog, "bien_error") && is.data.frame(trait_catalog) && nrow(trait_catalog) > 0) {
      .bien_trait_catalog_cache <<- trait_catalog
    }
  } else {
    trait_catalog <- .bien_trait_catalog_cache
  }
  
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
        "SELECT DISTINCT b.scrubbed_species_binomial AS taxon ",
        "FROM bien_taxonomy b ",
        "WHERE b.scrubbed_taxonomic_status = 'Accepted' ",
        "AND b.scrubbed_species_binomial IS NOT NULL ",
        "AND b.scrubbed_species_binomial <> '' ",
        "ORDER BY b.scrubbed_species_binomial ",
        "LIMIT %d;"
      ),
      as.integer(max_choices)
    ),
    genus = sprintf(
      paste0(
        "SELECT DISTINCT b.scrubbed_genus AS taxon ",
        "FROM bien_taxonomy b ",
        "WHERE b.scrubbed_taxonomic_status = 'Accepted' ",
        "AND b.scrubbed_genus IS NOT NULL ",
        "AND b.scrubbed_genus <> '' ",
        "ORDER BY b.scrubbed_genus ",
        "LIMIT %d;"
      ),
      as.integer(max_choices)
    ),
    family = sprintf(
      paste0(
        "SELECT DISTINCT b.scrubbed_family AS taxon ",
        "FROM bien_taxonomy b ",
        "WHERE b.scrubbed_taxonomic_status = 'Accepted' ",
        "AND b.scrubbed_family IS NOT NULL ",
        "AND b.scrubbed_family <> '' ",
        "ORDER BY b.scrubbed_family ",
        "LIMIT %d;"
      ),
      as.integer(max_choices)
    ),
    NULL
  )
  if (is.null(sql)) return(character(0))

  bien_sql <- tryCatch(
    get(".BIEN_sql", envir = asNamespace("BIEN")),
    error = function(e) NULL
  )
  if (is.null(bien_sql)) return(character(0))
  out <- safe_bien_retry(function() {
    bien_sql(query = sql, fetch.query = FALSE)
  }, timeout_sec = timeout_sec, attempts = 2)

  fallback_vals <- .bien_taxon_suggestion_fallback[[rank]]
  if (is.null(fallback_vals)) fallback_vals <- character(0)

  cached_vals <- .bien_taxon_suggestion_cache[[rank]]
  if (is.null(cached_vals)) cached_vals <- character(0)

  if (inherits(out, "bien_error") || !is.data.frame(out) || nrow(out) == 0 || !"taxon" %in% names(out)) {
    if (length(cached_vals) > 0) {
      return(cached_vals)
    }
    return(fallback_vals)
  }

  vals <- unique(as.character(out$taxon))
  vals <- vals[!is.na(vals) & nzchar(vals)]
  if (length(vals) > 0) {
    .bien_taxon_suggestion_cache[[rank]] <<- vals
    return(vals)
  }

  if (length(cached_vals) > 0) {
    return(cached_vals)
  }

  fallback_vals
}

suggestion_cap_for_rank <- function(rank) {
  if (identical(rank, "species")) return(1500L)
  if (identical(rank, "genus")) return(2500L)
  if (identical(rank, "family")) return(300L)
  500L
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
      if (nrow(dat) > max_records) dat <- dat[seq_len(max_records), , drop = FALSE]
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

  if (identical(rank, "trait-only")) {
    trait_names <- expand_trait_name(taxon, timeout_sec = timeout_sec)
    if (length(trait_names) == 0) trait_names <- taxon
    total <- 0L
    for (tn in trait_names) {
      sql_fn <- safe_bien_retry(function() {
        BIEN_trait_trait(trait = tn, all.taxonomy = TRUE, source.citation = TRUE, return.query = TRUE)
      }, timeout_sec = timeout_sec, attempts = 2)
      if (inherits(sql_fn, "bien_error") || !is.character(sql_fn) || !nzchar(sql_fn)) next
      sql_clean <- gsub(";\\s*$", "", sql_fn)
      count_sql <- sprintf("SELECT COUNT(*) AS total_records FROM (%s) t", sql_clean)
      bien_sql <- tryCatch(
        get(".BIEN_sql", envir = asNamespace("BIEN")),
        error = function(e) NULL
      )
      if (is.null(bien_sql)) return(NA_integer_)
      cnt <- safe_bien_retry(function() {
        bien_sql(query = count_sql, fetch.query = FALSE)
      }, timeout_sec = timeout_sec, attempts = 2)
      if (!inherits(cnt, "bien_error") && is.data.frame(cnt) && nrow(cnt) > 0 && "total_records" %in% names(cnt)) {
        total <- total + as.integer(cnt$total_records[[1]])
      }
    }
    return(total)
  }

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

  bien_sql <- tryCatch(
    get(".BIEN_sql", envir = asNamespace("BIEN")),
    error = function(e) NULL
  )
  if (is.null(bien_sql)) return(NA_integer_)
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
      query_rank = query_rank,
      query_taxon = query_taxon,
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
        conditionalPanel(
          condition = sprintf("input['%s'] == 'single'", ns("input_mode")),
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
                  create = TRUE,
                  createOnBlur = TRUE,
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
        )
      ),
      div(class = "row",
        div(class = "col-sm-12",
          div(class = "form-group",
            radioButtons(ns("input_mode"), "Input mode:",
              choices = c("Single taxon (autocomplete)" = "single",
                         "Batch species list (paste or upload CSV)" = "batch"),
              selected = "single", inline = TRUE)
          )
        )
      ),
      conditionalPanel(
        condition = sprintf("input['%s'] == 'batch'", ns("input_mode")),
        div(class = "row",
          div(class = "col-sm-6",
            div(class = "form-group",
              tags$label("Paste species names (one per line, comma, or semicolon):"),
              tags$textarea(id = ns("batch_text"),
                class = "form-control", rows = "6",
                placeholder = "Pinus ponderosa\nAbies concolor\nQuercus agrifolia"
              )
            )
          ),
          div(class = "col-sm-6",
            div(class = "form-group",
              tags$label("Or upload a CSV (one column, species names):"),
              fileInput(ns("batch_csv"), NULL, accept = ".csv", width = "100%"),
              p(class = "text-muted",
                "CSV should have one species name per row. First row treated as header if it contains no spaces.")
            )
          )
        )
      ),
      uiOutput(ns("trait_scope_preview")),
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
      suggestion_cache = list(),
      needs_count_refresh = FALSE,
      batch_species = character(0),
      effective_taxon = ""
    ) -> rv

    observeEvent(list(input$suggest_mode, input$rank, input$input_mode), {
      if (!identical(input$input_mode, "single")) {
        return()
      }

      mode <- if (is.null(input$suggest_mode) || !nzchar(input$suggest_mode)) "taxa" else input$suggest_mode
      rank <- if (is.null(input$rank) || !nzchar(input$rank)) "species" else input$rank

      # Prevent a transient taxa refresh when rank switches to trait-only.
      # That transient state can make the selectize control feel unresponsive.
      if (identical(rank, "trait-only") && !identical(mode, "traits")) {
        mode <- "traits"
        updateRadioButtons(session, "suggest_mode", selected = "traits")
      } else if (!identical(rank, "trait-only") && !identical(mode, "taxa")) {
        mode <- "taxa"
        updateRadioButtons(session, "suggest_mode", selected = "taxa")
      }

      key <- paste(mode, if (identical(mode, "taxa")) rank else "traits", sep = "::")

      choices <- rv$suggestion_cache[[key]]
      if (is.null(choices) || length(choices) == 0) {
        choices <- if (identical(mode, "traits")) {
          load_trait_suggestions()
        } else {
          # Keep suggestion payloads small enough to avoid blocking rank switches.
          load_taxon_suggestions(rank = rank, max_choices = suggestion_cap_for_rank(rank))
        }
        if (length(choices) > 0) {
          rv$suggestion_cache[[key]] <- choices
        }
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
        server = !identical(mode, "traits"),
        options = list(
          create = TRUE,
          createOnBlur = TRUE,
          maxOptions = 2000,
          openOnFocus = TRUE,
          minChars = 2,
          placeholder = placeholder
        )
      )
    }, ignoreInit = FALSE)
    
    batch_species_list <- reactive({
      mode <- input$input_mode
      if (!identical(mode, "batch")) return(character(0))
      
      # CSV upload takes precedence over pasted text
      csv_path <- input$batch_csv$datapath
      if (!is.null(csv_path) && file.exists(csv_path)) {
        first_line <- tryCatch(readLines(csv_path, n = 1, warn = FALSE), error = function(e) "")
        has_header <- !grepl("\\s", trimws(first_line[[1]])) && !grepl(",.*,", first_line[[1]])
        tbl <- tryCatch(read.csv(csv_path, stringsAsFactors = FALSE, header = has_header), error = function(e) NULL)
        if (!is.null(tbl) && ncol(tbl) >= 1) {
          vals <- as.character(tbl[[1]])
          vals <- vals[!is.na(vals) & nzchar(str_squish(vals))]
          return(normalize_taxon_name(vals))
        }
      }
      
      # Pasted text
      txt <- input$batch_text
      if (is.null(txt) || !nzchar(str_squish(txt))) return(character(0))
      parts <- unlist(strsplit(txt, "[,;\n]+"))
      parts <- str_squish(parts)
      parts <- parts[nzchar(parts)]
      normalize_taxon_name(parts)
    })

    observeEvent(input$query_btn, {
      rv$error_msg <- ""
      mode <- if (is.null(input$input_mode)) "single" else input$input_mode
      taxon_input <- ""
      species_vec <- character(0)
      
      if (identical(mode, "batch")) {
        species_vec <- batch_species_list()
        if (length(species_vec) == 0) {
          rv$error_msg <- "Batch mode: enter at least one species name or upload a CSV."
          return()
        }
      } else {
        taxon_input <- if (is.null(input$taxon)) "" else str_squish(as.character(input$taxon))
        if (!nzchar(taxon_input)) {
          rv$error_msg <- "Enter a taxon or trait name before querying BIEN."
          return()
        }
      }

      rv$is_querying <- TRUE
      refresh_counts <- FALSE

      # Visually disable button and show spinner via plain JS message
      session$sendCustomMessage("queryBtnState", list(
        btnId    = session$ns("query_btn"),
        spinnerId = session$ns("query_btn_spinner"),
        loading  = TRUE
      ))

      on.exit({
        session$sendCustomMessage("queryBtnState", list(
          btnId    = session$ns("query_btn"),
          spinnerId = session$ns("query_btn_spinner"),
          loading  = FALSE
        ))
        rv$is_querying <- FALSE
        rv$needs_count_refresh <- isTRUE(refresh_counts)
      }, add = TRUE)

      if (identical(mode, "batch")) {
        # Query each species and bind rows
        max_records <- suppressWarnings(as.integer(input$max_records))
        if (is.na(max_records) || max_records < 100) max_records <- 5000
        max_records <- min(max_records, 50000)
        per_species_limit <- max(100L, as.integer(max_records / length(species_vec)))
        
        all_results <- list()
        withProgress(message = "Querying BIEN (batch)...", value = 0, {
          for (i in seq_along(species_vec)) {
            sp <- species_vec[[i]]
            incProgress(1 / length(species_vec), detail = sp)
            res <- query_bien_traits(rank = "species", taxon = sp,
                                     max_records = per_species_limit, timeout_sec = 120)
            if (is.data.frame(res) && nrow(res) > 0) {
              all_results[[sp]] <- res
            }
          }
        })
        
        dat <- if (length(all_results) > 0) dplyr::bind_rows(all_results) else data.frame()
        dat <- ensure_unique_names(dat)
        rv$effective_taxon <- paste(species_vec, collapse = "; ")
        rv$query_data <- dat
        rv$diagnostics <- compute_diagnostics(dat, "species", paste(species_vec, collapse = "; "),
                                              total_available = NA_integer_, max_records = max_records)
        rv$error_msg <- if (nrow(dat) == 0) "No records returned for any of the provided species." else ""
        refresh_counts <- FALSE
        return()
      }

      tryCatch({
        taxon_clean <- if (identical(input$rank, "trait-only")) {
          str_squish(as.character(taxon_input))
        } else {
          normalize_taxon_name(taxon_input)
        }
        max_records <- suppressWarnings(as.integer(input$max_records))
        if (is.na(max_records) || max_records < 100) max_records <- 5000
        max_records <- min(max_records, 50000)

        withProgress(message = "Querying BIEN...",
                     detail = "This may take 30\u201360 seconds",
                     value = 0.3, {
          dat <- query_bien_traits(rank = input$rank, taxon = taxon_clean,
                                   max_records = max_records, timeout_sec = 120)
          bien_err <- attr(dat, "bien_error", exact = TRUE)
          incProgress(0.7, message = "Processing results...")
          rv$effective_taxon <- taxon_clean
          rv$query_data <- dat
          rv$diagnostics <- compute_diagnostics(
            dat,
            input$rank,
            taxon_clean,
            total_available = NA_integer_,
            max_records = max_records
          )
          rv$error_msg <- if (is.character(bien_err) && nzchar(bien_err)) {
            paste("BIEN query error:", format_bien_error(bien_err, context = "query"))
          } else if (nrow(dat) == 0) {
            "No trait records found for this query. For genus/family mode, try a plain name (for example: Prunus)."
          } else {
            ""
          }
        })
        refresh_counts <- TRUE
      }, error = function(e) {
        rv$query_data <- data.frame()
        rv$diagnostics <- NULL
        rv$effective_taxon <- ""
        rv$error_msg <- paste("Error:", conditionMessage(e))
      })
    })

    observe({
      req(rv$needs_count_refresh)
      rv$needs_count_refresh <- FALSE
      qr <- rv$query_data
      diag <- rv$diagnostics
      if (!is.data.frame(qr) || nrow(qr) == 0 || is.null(diag)) return()
      total_available <- query_bien_total_records(
        rank = diag$query_rank,
        taxon = diag$query_taxon,
        timeout_sec = 25
      )
      rv$diagnostics <- compute_diagnostics(
        qr,
        diag$query_rank,
        diag$query_taxon,
        total_available = total_available,
        max_records = diag$limit_used
      )
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

    output$trait_scope_preview <- renderUI({
      req(input$rank, input$suggest_mode)
      if (!identical(input$rank, "trait-only")) return(NULL)
      taxon_val <- input$taxon
      if (is.null(taxon_val) || !nzchar(str_squish(as.character(taxon_val)))) return(NULL)
      
      expanded <- expand_trait_name(str_squish(as.character(taxon_val)))
      if (length(expanded) == 0) return(NULL)
      
      if (length(expanded) == 1 && identical(expanded, taxon_val)) {
        return(div(class = "alert alert-info", style = "margin-top: 8px;",
          strong("Trait query: "), expanded[[1]]))
      }
      
      div(class = "alert alert-info", style = "margin-top: 8px;",
        strong(sprintf("Trait-only query will expand to %d exact BIEN trait names:", length(expanded))),
        tags$ul(lapply(expanded, function(t) tags$li(t)))
      )
    })
    
    reactive({
      list(
        data = rv$query_data,
        diagnostics = rv$diagnostics,
        rank = input$rank,
        taxon = rv$effective_taxon,
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
      if (is.null(diag)) return(p("Diagnostics not yet available.", style = "color: #666;"))
      
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
        ,
        div(class = "panel panel-default",
          div(class = "panel-heading", strong("Quick Insights")),
          div(class = "panel-body",
            {
              trait_col_i <- first_existing_col(qr$data, c("trait_name", "trait", "measurementType"))
              source_col_i <- first_existing_col(qr$data, c("source_citation", "datasource", "dataset"))
              unit_col_i <- first_existing_col(qr$data, c("trait_unit", "unit", "units", "measurement_unit"))
              
              # Top 3 traits
              top_traits_ui <- if (!is.null(trait_col_i)) {
                top3 <- diag$coverage_by_trait
                if (is.data.frame(top3) && nrow(top3) > 0) {
                  top3 <- head(top3, 3)
                  tags$p(strong("Top traits: "),
                    paste(apply(top3, 1, function(r) paste0(r[[1]], " (", r[[2]], " records)")),
                          collapse = "; "))
                }
              }
              
              # Source concentration
              source_conc_ui <- if (!is.null(source_col_i)) {
                src_counts <- sort(table(as.character(qr$data[[source_col_i]])), decreasing = TRUE)
                src_counts <- src_counts[names(src_counts) != "" & !is.na(names(src_counts))]
                if (length(src_counts) > 0) {
                  top_src <- names(src_counts)[[1]]
                  top_pct <- round(100 * src_counts[[1]] / sum(src_counts), 1)
                  tags$p(strong("Source concentration: "),
                    sprintf("Top source accounts for %.1f%% of records.", top_pct),
                    if (top_pct > 60) tags$span(class = "label label-warning", "Dominated by one source"))
                }
              }
              
              # Unit heterogeneity (O(N) group-by instead of O(T*N) per-trait subsetting)
              unit_het_ui <- if (!is.null(trait_col_i) && !is.null(unit_col_i)) {
                n_mixed <- qr$data |>
                  dplyr::mutate(.unit_clean = tolower(str_squish(as.character(.data[[unit_col_i]])))) |>
                  dplyr::filter(!is.na(.unit_clean), nzchar(.unit_clean)) |>
                  dplyr::group_by(.data[[trait_col_i]]) |>
                  dplyr::summarise(.n_units = dplyr::n_distinct(.unit_clean), .groups = "drop") |>
                  dplyr::filter(.n_units > 1) |>
                  nrow()
                if (n_mixed > 0) {
                  tags$p(strong("Unit heterogeneity: "),
                    sprintf("%d trait(s) have mixed units \u2014 check before pooling values.", n_mixed),
                    tags$span(class = "label label-danger", "Review units"))
                } else {
                  tags$p(strong("Unit heterogeneity: "), "All traits appear to use consistent units.")
                }
              }
              
              # Truncation risk
              trunc_ui <- if (!is.null(diag$records_not_returned) && !is.na(diag$records_not_returned) &&
                               diag$records_not_returned > 0) {
                pct_missing <- round(100 * diag$records_not_returned /
                                      max(diag$total_available_records, 1), 1)
                tags$p(strong("Truncation risk: "),
                  sprintf("%.1f%% of matching BIEN records were not returned (increase limit in Step 1 or use the R script to fetch all).", pct_missing),
                  if (pct_missing > 50) tags$span(class = "label label-danger", "High truncation"))
              }
              
              tagList(top_traits_ui, source_conc_ui, unit_het_ui, trunc_ui)
            }
          )
        )
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
    div(class = "panel-heading", h3("Step 5: Diagnostics & Preview")),
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
      if (is.null(diag)) return(p("Diagnostics not yet available.", style = "color: #666;"))
      
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
    div(class = "panel-heading", h3("Step 6: Complete Record Set")),
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
      dat <- sanitize_for_dt(query_result()$data)
      req(nrow(dat) > 0)
      datatable(
        dat,
        options = list(
          scrollX = TRUE,
          pageLength = 25,
          dom = "frtip"
        ),
        rownames = FALSE
      )
    }, server = TRUE)
    
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
    div(class = "panel-heading", h3("Step 7: Provenance & Reproducibility")),
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
      ts <- format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%d %H:%M:%S UTC")
      
      diag <- qr$diagnostics
      manifest <- list(
        query_rank = qr$rank,
        query_taxon = qr$taxon,
        max_records = qr$max_records,
        timestamp_utc = ts,
        app_version = "BIEN Trait Gateway v1.0",
        records = nrow(qr$data),
        total_available_records = if (!is.null(diag)) diag$total_available_records else NA_integer_,
        records_not_returned = if (!is.null(diag)) diag$records_not_returned else NA_integer_,
        unique_species = if (!is.null(diag)) diag$unique_species else NA_integer_,
        unique_traits = if (!is.null(diag)) diag$unique_traits else NA_integer_,
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
      diag <- query_result()$diagnostics
      manifest <- list(
        query_rank = query_result()$rank,
        query_taxon = query_result()$taxon,
        max_records = query_result()$max_records,
        timestamp_utc = format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%d %H:%M:%S UTC"),
        app_version = "BIEN Trait Gateway v1.0",
        records = nrow(query_result()$data),
        total_available_records = if (!is.null(diag)) diag$total_available_records else NA_integer_,
        records_not_returned = if (!is.null(diag)) diag$records_not_returned else NA_integer_,
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
        ts <- format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%d %H:%M:%S UTC")
        diag <- query_result()$diagnostics
        manifest <- list(
          query_rank = query_result()$rank,
          query_taxon = query_result()$taxon,
          max_records = query_result()$max_records,
          timestamp_utc = ts,
          app_version = "BIEN Trait Gateway v1.0",
          records = nrow(query_result()$data),
          total_available_records = if (!is.null(diag)) diag$total_available_records else NA_integer_,
          records_not_returned = if (!is.null(diag)) diag$records_not_returned else NA_integer_,
          unique_species = if (!is.null(diag)) diag$unique_species else NA_integer_,
          unique_traits = if (!is.null(diag)) diag$unique_traits else NA_integer_,
          download_all_traits = isTRUE(query_result()$download_all),
          selected_traits = query_result()$selected_traits,
          diagnostics = if (!is.null(diag)) diag else list()
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
        ts <- format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%d %H:%M:%S UTC")
        rank <- if (!is.null(query_result()$rank)) query_result()$rank else "species"
        taxon <- if (!is.null(query_result()$taxon)) query_result()$taxon else ""
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
          queried_traits <- query_result()$queried_traits
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
          sprintf("# Generated: %s", ts),
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
    div(class = "panel-heading", h3("Step 8: Data Use Acknowledgement")),
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
      if (sum(keep) == 0) return(data.frame())

      counts <- data.frame(sp = sp[keep], tr = tr[keep], stringsAsFactors = FALSE)
      counts <- counts |>
        dplyr::count(sp, tr, name = "n")

      sp_totals <- counts |>
        dplyr::group_by(sp) |>
        dplyr::summarise(total_records = sum(n), .groups = "drop") |>
        dplyr::slice_max(total_records, n = 50, with_ties = FALSE)

      top_counts <- counts |>
        dplyr::filter(sp %in% sp_totals$sp)

      wide <- top_counts |>
        tidyr::pivot_wider(names_from = tr, values_from = n, values_fill = 0L)

      out <- sp_totals |>
        dplyr::left_join(wide, by = "sp") |>
        dplyr::rename(species = sp) |>
        dplyr::arrange(dplyr::desc(total_records))

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

    base_diagnostics <- reactive({
      req(query_result())
      base <- query_result()
      dat <- base$data
      base_rank <- if (!is.null(base$rank)) base$rank else "species"
      base_taxon <- if (!is.null(base$taxon)) base$taxon else ""
      diag <- base$diagnostics
      total_avail <- if (!is.null(diag) && !is.null(diag$total_available_records)) diag$total_available_records else NA_integer_
      max_rec <- if (!is.null(base$max_records)) suppressWarnings(as.integer(base$max_records)) else NA_integer_
      compute_diagnostics(dat, base_rank, base_taxon,
                          total_available = total_avail,
                          max_records = max_rec)
    })

    reactive({
      req(query_result())
      base <- query_result()
      base_rank <- if (!is.null(base$rank)) base$rank else "species"
      base_taxon <- if (!is.null(base$taxon)) base$taxon else ""
      dat <- query_result()$data
      qt <- attr(dat, "queried_traits")
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
          base = base,
          queried_traits = NULL
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
          diagnostics = compute_diagnostics(data.frame(), base_rank, base_taxon),
          is_loading = isTRUE(base$is_loading),
          base = base,
          queried_traits = NULL
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
        diagnostics = base_diagnostics(),
        is_loading = isTRUE(base$is_loading),
        base = base,
        queried_traits = qt
      )
    })
  })
}

# ============================================================================
# SHINY MODULE: DistributionsUI & DistributionsServer
# ============================================================================

distributionsUI <- function(id) {
  ns <- NS(id)
  div(
    class = "panel panel-info",
    div(class = "panel-heading", h3("Step 4: Trait Distributions")),
    div(class = "panel-body",
      uiOutput(ns("caveat_banner")),
      fluidRow(
        div(class = "col-sm-4",
          uiOutput(ns("dist_controls")),
          uiOutput(ns("scope_badge")),
          h4("Summary Statistics"),
          tableOutput(ns("summary_stats"))
        ),
        div(class = "col-sm-8",
          plotOutput(ns("hist_plot"), height = "360px"),
          textOutput(ns("na_note"))
        )
      ),
      h4("Source Breakdown"),
      DTOutput(ns("source_breakdown"))
    )
  )
}

distributionsServer <- function(id, query_result) {
  moduleServer(id, function(input, output, session) {
    dist_payload <- reactive({
      req(query_result())
      dat <- query_result()$data
      if (!is.data.frame(dat) || nrow(dat) == 0) {
        return(list(ok = FALSE, message = "Run a query first to view distributions."))
      }

      trait_col <- first_existing_col(dat, c("trait_name", "trait", "measurementType"))
      value_col <- first_existing_col(dat, c("trait_value", "value", "measurement", "trait_value_original"))
      unit_col <- first_existing_col(dat, c("trait_unit", "unit", "units", "measurement_unit"))
      source_col <- first_existing_col(dat, c("source_citation", "datasource", "dataset", "dataset_name"))

      if (is.null(trait_col) || is.null(value_col)) {
        return(list(ok = FALSE, message = "Trait name/value columns were not detected in this query."))
      }

      trait_vals <- as.character(dat[[trait_col]])
      trait_vals <- trait_vals[!is.na(trait_vals) & nzchar(trait_vals)]
      trait_choices <- sort(unique(trait_vals))

      list(
        ok = TRUE,
        dat = dat,
        trait_col = trait_col,
        value_col = value_col,
        unit_col = unit_col,
        source_col = source_col,
        trait_choices = trait_choices
      )
    })

    output$dist_controls <- renderUI({
      payload <- dist_payload()
      if (!isTRUE(payload$ok)) {
        return(div(class = "alert alert-warning", payload$message))
      }

      selected_trait <- if (!is.null(input$dist_trait) && input$dist_trait %in% payload$trait_choices) {
        input$dist_trait
      } else if (length(payload$trait_choices) > 0) {
        payload$trait_choices[[1]]
      } else {
        ""
      }

      tagList(
        selectInput(
          session$ns("dist_trait"),
          "Trait:",
          choices = payload$trait_choices,
          selected = selected_trait,
          width = "100%"
        ),
        sliderInput(
          session$ns("dist_bins"),
          "Histogram bins:",
          min = 10,
          max = 80,
          value = 30,
          step = 1,
          width = "100%"
        ),
        checkboxInput(session$ns("dist_show_density"), "Show density overlay", value = TRUE),
        checkboxInput(session$ns("dist_log10"), "Use log10 scale (positive values only)", value = FALSE),
        if (length(payload$trait_choices) > 0 && !is.null(input$dist_trait) && nzchar(input$dist_trait)) {
          sub_units <- {
            dat <- payload$dat
            sub <- dat[as.character(dat[[payload$trait_col]]) == input$dist_trait, , drop = FALSE]
            if (!is.null(payload$unit_col)) {
              u <- tolower(str_squish(as.character(sub[[payload$unit_col]])))
              sort(unique(u[!is.na(u) & nzchar(u)]))
            } else character(0)
          }
          if (length(sub_units) > 1) {
            selectInput(
              session$ns("dist_unit_filter"),
              "Filter to unit:",
              choices = sub_units,
              selected = sub_units[[1]],
              width = "100%"
            )
          }
        }
      )
    })

    dist_selected <- reactive({
      payload <- dist_payload()
      req(isTRUE(payload$ok))
      req(!is.null(input$dist_trait), nzchar(input$dist_trait))

      dat <- payload$dat
      trait_col <- payload$trait_col
      value_col <- payload$value_col
      unit_col <- payload$unit_col
      source_col <- payload$source_col

      sub <- dat[as.character(dat[[trait_col]]) == input$dist_trait, , drop = FALSE]
      # Apply unit filter when multiple units are present and user has selected one
      unit_filter_val <- if (!is.null(input$dist_unit_filter) && nzchar(input$dist_unit_filter) &&
                              !is.null(unit_col)) input$dist_unit_filter else NULL
      if (!is.null(unit_filter_val) && !is.null(unit_col)) {
        unit_vals_sub <- tolower(str_squish(as.character(sub[[unit_col]])))
        sub <- sub[!is.na(unit_vals_sub) & unit_vals_sub == unit_filter_val, , drop = FALSE]
      }
      raw_vals <- suppressWarnings(as.numeric(as.character(sub[[value_col]])))
      keep <- !is.na(raw_vals) & is.finite(raw_vals)
      vals <- raw_vals[keep]
      total_n <- length(raw_vals)
      used_n <- length(vals)
      missing_n <- total_n - used_n
      missing_pct <- if (total_n > 0) 100 * missing_n / total_n else 100

      unit_vals <- character(0)
      if (!is.null(unit_col)) {
        unit_vals <- tolower(str_squish(as.character(sub[[unit_col]])))
        unit_vals <- unit_vals[!is.na(unit_vals) & nzchar(unit_vals)]
      }
      unique_units <- sort(unique(unit_vals))

      source_tbl <- data.frame()
      if (!is.null(source_col)) {
        source_tbl <- sub %>%
          mutate(source_clean = ifelse(is.na(.data[[source_col]]) | !nzchar(as.character(.data[[source_col]])),
                                       "Unknown/Not provided", as.character(.data[[source_col]]))) %>%
          count(source_clean, name = "n_records") %>%
          mutate(percent = round(100 * n_records / sum(n_records), 1)) %>%
          arrange(desc(n_records))
      }

      q <- stats::quantile(vals, probs = c(0.25, 0.75), na.rm = TRUE, names = FALSE)
      iqr_val <- if (length(vals) > 0) diff(q) else NA_real_
      outlier_n <- if (length(vals) > 0 && is.finite(iqr_val)) {
        lo <- q[1] - 1.5 * iqr_val
        hi <- q[2] + 1.5 * iqr_val
        sum(vals < lo | vals > hi, na.rm = TRUE)
      } else {
        0L
      }

      list(
        vals = vals,
        total_n = total_n,
        used_n = used_n,
        missing_n = missing_n,
        missing_pct = missing_pct,
        unique_units = unique_units,
        source_tbl = source_tbl,
        outlier_n = outlier_n
      )
    })

    output$caveat_banner <- renderUI({
      payload <- dist_payload()
      if (!isTRUE(payload$ok)) return(NULL)

      sel <- tryCatch(dist_selected(), error = function(e) NULL)
      if (is.null(sel)) return(NULL)

      alerts <- list(
        div(
          class = "alert alert-info",
          strong("Warning: "),
          "This figure summarizes available BIEN-linked trait records, not a complete or unbiased sample of species biology. Differences may reflect sampling effort, taxonomic coverage, or data harmonization decisions."
        )
      )

      if (length(sel$unique_units) > 1) {
        alerts[[length(alerts) + 1]] <- div(
          class = "alert alert-danger",
          strong("Warning: "),
          "Multiple trait units were detected. Values are not directly comparable until converted to a common unit. Summary statistics may be misleading."
        )
      }

      if (is.finite(sel$missing_pct) && sel$missing_pct > 20) {
        alerts[[length(alerts) + 1]] <- div(
          class = "alert alert-warning",
          strong("Warning: "),
          "Missing trait values exceed 20 percent for the current filter. Distribution shape and summary statistics may be unstable and should be interpreted cautiously."
        )
      }

      if (sel$used_n > 0 && sel$used_n < 30) {
        alerts[[length(alerts) + 1]] <- div(
          class = "alert alert-warning",
          strong("Warning: "),
          "Fewer than 30 non-missing observations are available. Treat distribution patterns as exploratory, not confirmatory."
        )
      }

      do.call(tagList, alerts)
    })

    output$scope_badge <- renderUI({
      req(query_result())
      qr <- query_result()
      diag <- qr$diagnostics
      species_n <- if (!is.null(diag$unique_species)) diag$unique_species else NA_integer_
      record_n <- if (is.data.frame(qr$data)) nrow(qr$data) else 0

      div(
        class = "alert alert-info",
        style = "margin-top: 8px;",
        strong("Scope: "),
        sprintf("%s: %s | %s species | %s observations",
                str_to_title(qr$rank), qr$taxon, species_n, record_n)
      )
    })

    output$summary_stats <- renderTable({
      sel <- dist_selected()
      vals <- sel$vals
      req(length(vals) > 0)

      data.frame(
        metric = c("N (non-missing)", "Mean", "Median", "SD", "IQR", "Min", "Max", "5th percentile", "95th percentile", "Outliers (1.5*IQR)"),
        value = c(
          length(vals),
          round(mean(vals, na.rm = TRUE), 4),
          round(median(vals, na.rm = TRUE), 4),
          round(stats::sd(vals, na.rm = TRUE), 4),
          round(stats::IQR(vals, na.rm = TRUE), 4),
          round(min(vals, na.rm = TRUE), 4),
          round(max(vals, na.rm = TRUE), 4),
          round(stats::quantile(vals, 0.05, na.rm = TRUE, names = FALSE), 4),
          round(stats::quantile(vals, 0.95, na.rm = TRUE, names = FALSE), 4),
          sel$outlier_n
        ),
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
    }, striped = TRUE, bordered = TRUE, width = "100%")

    output$na_note <- renderText({
      sel <- dist_selected()
      unit_msg <- if (length(sel$unique_units) == 0) {
        "Units: unknown"
      } else if (length(sel$unique_units) == 1) {
        paste("Units:", sel$unique_units[[1]])
      } else {
        paste("Units detected:", paste(sel$unique_units, collapse = ", "))
      }
      sprintf("Used %d of %d rows (%d missing/non-numeric excluded; %.1f%% missing). %s",
              sel$used_n, sel$total_n, sel$missing_n, sel$missing_pct, unit_msg)
    })

    output$hist_plot <- renderPlot({
      sel <- dist_selected()
      vals <- sel$vals

      if (length(vals) == 0) {
        plot.new()
        text(0.5, 0.5, "No numeric values available for this trait.")
        return(invisible(NULL))
      }

      if (isTRUE(input$dist_log10)) {
        vals <- vals[vals > 0]
        if (length(vals) == 0) {
          plot.new()
          text(0.5, 0.5, "No positive values available for log10 display.")
          return(invisible(NULL))
        }
        vals <- log10(vals)
      }

      h <- hist(
        vals,
        breaks = input$dist_bins,
        col = "#7fb8e6",
        border = "#2f79b7",
        main = paste("Distribution:", input$dist_trait),
        xlab = if (isTRUE(input$dist_log10)) "log10(trait value)" else "Trait value",
        ylab = "Frequency"
      )

      rug(vals, col = "#1f5b8f")

      if (isTRUE(input$dist_show_density) && length(vals) > 1) {
        d <- density(vals, na.rm = TRUE)
        bw <- if (length(h$breaks) > 1) diff(h$breaks[1:2]) else 1
        lines(d$x, d$y * length(vals) * bw, col = "#d9534f", lwd = 2)
      }
    })

    output$source_breakdown <- renderDT({
      sel <- dist_selected()
      tbl <- sel$source_tbl
      if (!is.data.frame(tbl) || nrow(tbl) == 0) {
        return(datatable(data.frame(note = "No source citation column was detected."), rownames = FALSE,
                        options = list(dom = "t", paging = FALSE, searching = FALSE)))
      }
      datatable(tbl, rownames = FALSE, options = list(pageLength = 8))
    })

    reactive(list(ok = TRUE))
  })
}

downloadGateServer <- function(id, query_result) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
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
        div(class = "alert alert-info", strong(download_mode)),
        div(
          class = "alert alert-warning",
          style = "border-left: 5px solid #d9534f; background: #fff8f8;",
          tags$h4(
            style = "margin-top: 0; color: #a94442;",
            tags$span(class = "glyphicon glyphicon-exclamation-sign"), " Data Use Acknowledgement"
          ),
          tags$p("By downloading, you confirm that you understand and accept all of the following:"),
          tags$ul(
            style = "margin-bottom: 8px;",
            tags$li("Availability (records in database) ≠ abundance (prevalence in nature)."),
            tags$li("You have reviewed taxonomic reconciliation results for your query and confirmed they are appropriate for your use case."),
            tags$li("These data represent biased sampling across studies, regions, and taxa; BIEN coverage is uneven."),
            tags$li("Trait measurement methods, instruments, and protocols vary across sources and may reduce direct comparability."),
            tags$li("You have checked for missing data and small sample sizes before interpretation."),
            tags$li(
              tags$strong("You will cite the original data sources"),
              " using the source_citation and url_source columns in your downloaded CSV to trace each observation back to its original data source."
            )
          ),
          div(class = "checkbox", style = "margin-top: 10px; font-weight: 600;",
            tags$label(
              checkboxInput(ns("acknowledged"), NULL, value = FALSE),
              "I have read and accept the above conditions."
            )
          )
        ),
        div(style = "margin-top: 12px;",
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

        if (!isTRUE(input$acknowledged)) {
          stop("Please check the acknowledgement box before downloading.")
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
        can_download = isTRUE(input$acknowledged)
      )
    })
  })
}

# ============================================================================
# SHINY MODULE: MapUI & MapServer
# ============================================================================

mapUI <- function(id) {
  ns <- NS(id)
  div(
    class = "panel panel-info",
    div(class = "panel-heading", h3("Map: Trait Observations")),
    div(class = "panel-body",
      uiOutput(ns("map_controls")),
      leaflet::leafletOutput(ns("map_plot"), height = "500px"),
      uiOutput(ns("map_summary"))
    )
  )
}

mapServer <- function(id, query_result) {
  moduleServer(id, function(input, output, session) {
    MAP_MARKER_CAP <- 5000L

    map_data <- reactive({
      req(query_result())
      dat <- query_result()$data
      if (!is.data.frame(dat) || nrow(dat) == 0) return(NULL)
      
      lat_col <- first_existing_col(dat, c("latitude", "lat", "decimalLatitude"))
      lon_col <- first_existing_col(dat, c("longitude", "lon", "long", "decimalLongitude"))
      trait_col <- first_existing_col(dat, c("trait_name", "trait", "measurementType"))
      value_col <- first_existing_col(dat, c("trait_value", "value", "measurement"))
      species_col <- first_existing_col(dat, c("scrubbed_species_binomial", "species", "scientific_name"))
      cite_col <- first_existing_col(dat, c("source_citation", "datasource"))
      
      if (is.null(lat_col) || is.null(lon_col)) return(NULL)
      
      mapped <- dat
      mapped$.lat <- suppressWarnings(as.numeric(as.character(mapped[[lat_col]])))
      mapped$.lon <- suppressWarnings(as.numeric(as.character(mapped[[lon_col]])))
      mapped <- mapped[!is.na(mapped$.lat) & !is.na(mapped$.lon), , drop = FALSE]
      mapped <- mapped[mapped$.lat >= -90 & mapped$.lat <= 90 &
                       mapped$.lon >= -180 & mapped$.lon <= 180, , drop = FALSE]
      if (nrow(mapped) == 0) return(NULL)
      
      list(dat = mapped, trait_col = trait_col, value_col = value_col,
           species_col = species_col, cite_col = cite_col)
    })
    
    output$map_controls <- renderUI({
      md <- map_data()
      if (is.null(md)) {
        return(div(class = "alert alert-warning",
          "No coordinate data available for this query. Latitude/longitude columns were not found or all values are missing."))
      }
      trait_choices <- if (!is.null(md$trait_col)) {
        sort(unique(as.character(md$dat[[md$trait_col]])))
      } else character(0)
      
      tagList(
        div(class = "alert alert-info",
          sprintf("Mapping %d observations with valid coordinates.", nrow(md$dat))),
        if (length(trait_choices) > 1) {
          selectInput(session$ns("map_trait"), "Color by trait:",
            choices = c("All traits" = "", trait_choices), selected = "", width = "320px")
        }
      )
    })
    
    output$map_plot <- leaflet::renderLeaflet({
      md <- map_data()
      if (is.null(md)) {
        return(leaflet::leaflet() |>
          leaflet::addTiles() |>
          leaflet::setView(lng = -100, lat = 20, zoom = 2))
      }
      
      dat <- md$dat
      
      # Filter to selected trait if chosen
      trait_filter <- input$map_trait
      if (!is.null(trait_filter) && nzchar(trait_filter) && !is.null(md$trait_col)) {
        dat <- dat[as.character(dat[[md$trait_col]]) == trait_filter, , drop = FALSE]
      }
      
      if (nrow(dat) == 0) {
        return(leaflet::leaflet() |> leaflet::addTiles() |> leaflet::setView(-100, 20, 2))
      }
      
      if (nrow(dat) > MAP_MARKER_CAP) {
        dat <- dat[sample.int(nrow(dat), MAP_MARKER_CAP), , drop = FALSE]
      }
      
      # Build popup text (vectorized: avoids per-row data frame extraction)
      sp_esc <- htmltools::htmlEscape(if (!is.null(md$species_col)) as.character(dat[[md$species_col]]) else rep("unknown", nrow(dat)))
      tr_esc <- htmltools::htmlEscape(if (!is.null(md$trait_col))   as.character(dat[[md$trait_col]])   else rep("", nrow(dat)))
      vl_esc <- htmltools::htmlEscape(if (!is.null(md$value_col))   as.character(dat[[md$value_col]])   else rep("", nrow(dat)))
      ct_esc <- htmltools::htmlEscape(if (!is.null(md$cite_col))    as.character(dat[[md$cite_col]])    else rep("", nrow(dat)))
      popup_txt <- paste0(
        "<b>", sp_esc, "</b><br/>",
        ifelse(nzchar(tr_esc), paste0("Trait: ", tr_esc, "<br/>"), ""),
        ifelse(nzchar(vl_esc), paste0("Value: ", vl_esc, "<br/>"), ""),
        ifelse(nzchar(ct_esc), paste0("<small>", ct_esc, "</small>"), "")
      )
      
      leaflet::leaflet(dat) |>
        leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron) |>
        leaflet::addCircleMarkers(
          lng = ~.lon, lat = ~.lat,
          radius = 5,
          color = "#2f79b7",
          fillColor = "#2f79b7",
          fillOpacity = 0.65,
          stroke = TRUE,
          weight = 1,
          popup = popup_txt
        )
    })
    
    output$map_summary <- renderUI({
      md <- map_data()
      if (is.null(md)) return(NULL)
      total_obs <- nrow(query_result()$data)
      mapped_obs <- nrow(md$dat)
      pct <- round(100 * mapped_obs / total_obs, 1)
      cap_note <- if (mapped_obs > MAP_MARKER_CAP) {
        sprintf(" A random sample of %s is displayed on the map.", format(MAP_MARKER_CAP, big.mark = ","))
      } else ""
      div(class = "alert alert-info", style = "margin-top: 10px;",
        sprintf("%d of %d observations (%s%%) have valid coordinates.%s",
                mapped_obs, total_obs, pct, cap_note))
    })
    
    reactive(list(ok = TRUE))
  })
}

# ============================================================================
# SHINY MODULE: HelpUI & HelpServer
# ============================================================================

helpUI <- function(id) {
  ns <- NS(id)
  div(
    class = "panel panel-default",
    div(class = "panel-heading", h3("Help & Ecological Caveats")),
    div(class = "panel-body",
      h4("About This App"),
      p("This app queries the Botanical Information and Ecology Network (BIEN) trait database and guides you through data inspection, quality assessment, and reproducible export. Each workflow step corresponds to a tab above."),
      tags$ol(
        tags$li(tags$b("Query:"), " Select a query rank (species, genus, family, or trait type) and enter a name. Use batch mode to query multiple species at once."),
        tags$li(tags$b("Scope:"), " Review how many records BIEN contains vs. how many were returned given your record limit."),
        tags$li(tags$b("Traits:"), " Choose which traits to include in your download. The species-by-trait matrix shows data coverage at a glance."),
        tags$li(tags$b("Distributions:"), " Explore numeric trait distributions. Use the unit filter when multiple units are present."),
        tags$li(tags$b("Map:"), " View coordinate-bearing observations on an interactive map."),
        tags$li(tags$b("Diagnostics:"), " Summary statistics for the returned dataset."),
        tags$li(tags$b("Records:"), " Browse the complete record set."),
        tags$li(tags$b("Provenance:"), " Download a query manifest and reproducible R script."),
        tags$li(tags$b("Download:"), " Review the data-use acknowledgement and export your CSV.")
      ),
      hr(),
      h4("Key Ecological Caveats"),
      tags$ul(
        tags$li(tags$b("Availability \u2260 Abundance: "), "BIEN records reflect which species and traits have been measured and submitted to the database \u2014 not the ecological prevalence or abundance of those traits in nature."),
        tags$li(tags$b("Sampling Bias: "), "Coverage is uneven across taxa, geographic regions, and trait types. Well-studied clades and traits are over-represented."),
        tags$li(tags$b("Taxonomic Scope: "), "Queries are matched against BIEN's taxonomic scrubbing layer. Results are filtered to accepted names where possible, but ambiguous or synonym cases may affect completeness."),
        tags$li(tags$b("Mixed Units: "), "Trait values from different studies may use different units. The Distributions tab warns you when this occurs and provides a unit filter. Do not pool values across units."),
        tags$li(tags$b("Genus and Family Queries: "), "These return data across many species and may combine heterogeneous measurement methods. Interpret distributions cautiously."),
        tags$li(tags$b("Record Limits: "), "The app imposes a cap on returned records. If total available records exceed your limit, the Scope tab will warn you. Increase the limit in Step 1 or use the reproducible R script to fetch the full dataset locally.")
      ),
      hr(),
      h4("How to Cite"),
      p("When using BIEN trait data in publications:"),
      tags$ol(
        tags$li("Cite the BIEN R package: Maitner et al. (2018). The bien r package: A tool to access the Botanical Information and Ecology Network (BIEN) database. Methods in Ecology and Evolution, 9(2), 373\u2013379."),
        tags$li("Cite individual data sources using the ", tags$code("source_citation"), " and ", tags$code("url_source"), " columns in your downloaded CSV."),
        tags$li("Include the query manifest (downloaded from the Provenance tab) as a supplementary data file to document your exact query parameters.")
      ),
      hr(),
      p(class = "text-muted",
        "Learn more about BIEN at ", tags$a(href = "https://biendata.org", target = "_blank", "biendata.org"), ".")
    )
  )
}

helpServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    reactive(list(ok = TRUE))
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
          h1("Trait Data Portal: Data Visualizer & Download"),
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
      tabPanel("Step 4: Distributions", distributionsUI("distributions")),
      tabPanel("Map", mapUI("map")),
      tabPanel("Step 5: Diagnostics", diagnosticsUI("diagnostics")),
      tabPanel("Step 6: Records", recordsUI("records")),
      tabPanel("Step 7: Provenance", provenanceUI("provenance")),
      tabPanel("Step 8: Download", downloadGateUI("downloadGate")),
      tabPanel("Help", helpUI("help"))
    ),
    
    hr(),
    p(class = "text-muted", 
      "Built with BIEN R package. All data subject to BIEN terms of use.",
      " | Query timestamp: ", format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%d %H:%M:%S UTC"))
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
      margin-bottom: 12px;
      border-bottom: 0;
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      padding: 2px;
    }
    .nav-tabs > li {
      float: none;
      margin-bottom: 0;
    }
    .nav-tabs > li > a {
      font-weight: 700;
      color: #1f4f73;
      border: 2px solid #b8cee2;
      border-radius: 12px;
      background: linear-gradient(180deg, #f8fcff 0%, #edf6ff 100%);
      padding: 10px 14px;
      transition: transform 0.08s ease, box-shadow 0.12s ease, filter 0.2s ease;
      box-shadow: 0 1px 0 #d7e6f4, 0 3px 8px rgba(27, 75, 111, 0.08);
    }
    .nav-tabs > li > a:hover,
    .nav-tabs > li > a:focus {
      filter: brightness(1.03);
      transform: translateY(-1px);
      box-shadow: 0 1px 0 #d7e6f4, 0 5px 10px rgba(27, 75, 111, 0.14);
      border-color: #92b7d6;
      color: #163d5a;
    }
    .nav-tabs > li:nth-child(1) > a { border-left: 6px solid #2f79b7; }
    .nav-tabs > li:nth-child(2) > a { border-left: 6px solid #49a078; }
    .nav-tabs > li:nth-child(3) > a { border-left: 6px solid #69b34c; }
    .nav-tabs > li:nth-child(4) > a { border-left: 6px solid #d4a537; }
    .nav-tabs > li:nth-child(5) > a { border-left: 6px solid #e07a5f; }
    .nav-tabs > li:nth-child(6) > a { border-left: 6px solid #7b8ec8; }
    .nav-tabs > li:nth-child(7) > a { border-left: 6px solid #4e8c2c; }
    .nav-tabs > li.active > a,
    .nav-tabs > li.active > a:focus,
    .nav-tabs > li.active > a:hover {
      color: #ffffff;
      background: linear-gradient(180deg, #3d89c8 0%, #1f5b8f 100%);
      border: 2px solid #1f5b8f;
      box-shadow: 0 2px 0 #18456f, 0 7px 14px rgba(31, 91, 143, 0.25);
      transform: translateY(-1px);
    }
    .nav-tabs > li.active:nth-child(2) > a,
    .nav-tabs > li.active:nth-child(2) > a:focus,
    .nav-tabs > li.active:nth-child(2) > a:hover,
    .nav-tabs > li.active:nth-child(3) > a,
    .nav-tabs > li.active:nth-child(3) > a:focus,
    .nav-tabs > li.active:nth-child(3) > a:hover,
    .nav-tabs > li.active:nth-child(7) > a,
    .nav-tabs > li.active:nth-child(7) > a:focus,
    .nav-tabs > li.active:nth-child(7) > a:hover {
      background: linear-gradient(180deg, #87c95d 0%, #4e8c2c 100%);
      border-color: #4e8c2c;
      box-shadow: 0 2px 0 #386620, 0 7px 14px rgba(62, 112, 36, 0.22);
    }
    .tab-content {
      background: #fff;
      border: 2px solid #b8cee2;
      border-radius: 12px;
      padding: 16px;
      box-shadow: 0 6px 16px rgba(33, 82, 120, 0.08);
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
  distributions_result <- distributionsServer("distributions", trait_result)
  diag_result <- diagnosticsServer("diagnostics", trait_result)
  records_result <- recordsServer("records", trait_result)
  prov_result <- provenanceServer("provenance", trait_result)
  download_result <- downloadGateServer("downloadGate", trait_result)
  map_result <- mapServer("map", trait_result)
  help_result <- helpServer("help")
}

# ============================================================================
# RUN APP
# ============================================================================

shinyApp(ui, server)
