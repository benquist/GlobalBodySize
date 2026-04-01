# Load required packages, installing any missing CRAN dependencies on startup.
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

# Wrap BIEN calls in a timeout-aware `tryCatch` so slow API responses do not lock up the app.
safe_bien_call <- function(expr, timeout_sec = 90) {
  on.exit(setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE), add = TRUE)
  setTimeLimit(elapsed = timeout_sec, transient = TRUE)
  tryCatch(expr, error = function(e) e)
}

safe_bien_retry <- function(call_fn, timeout_sec = 90, attempts = 1) {
  last <- NULL
  for (i in seq_len(attempts)) {
    last <- safe_bien_call(call_fn(), timeout_sec = timeout_sec)
    if (is.data.frame(last) && nrow(last) > 0) {
      return(list(result = last, attempt = i, status = "ok"))
    }
    if (inherits(last, "error") && i < attempts) {
      Sys.sleep(1)
    }
  }
  list(
    result = last,
    attempt = attempts,
    status = if (inherits(last, "error")) "error" else "empty"
  )
}

query_occurrence_with_fallback <- function(species_name, input, occ_limit, occ_page_size, timeout_sec) {
  use_cultivated_filter <- if (is.null(input$use_cultivated_filter)) TRUE else isTRUE(input$use_cultivated_filter)
  use_introduced_filter <- if (is.null(input$use_introduced_filter)) TRUE else isTRUE(input$use_introduced_filter)
  include_cultivated <- if (use_cultivated_filter) isTRUE(input$include_cultivated) else TRUE
  natives_only <- if (use_introduced_filter) {
    if (is.null(input$natives_only)) TRUE else isTRUE(input$natives_only)
  } else {
    FALSE
  }
  only_geovalid <- if (is.null(input$only_geovalid)) TRUE else isTRUE(input$only_geovalid)

  fast_limit <- min(occ_limit, 2000)
  fast_page_size <- min(occ_page_size, 500, fast_limit)

  plans <- list(
    list(label = "strict", natives.only = natives_only, only.geovalid = only_geovalid, limit = fast_limit, record_limit = fast_page_size),
    list(label = "fallback_relaxed_native", natives.only = FALSE, only.geovalid = only_geovalid, limit = min(fast_limit, 500), record_limit = min(fast_page_size, 500)),
    list(label = "fallback_relaxed_geo", natives.only = FALSE, only.geovalid = FALSE, limit = min(fast_limit, 500), record_limit = min(fast_page_size, 500))
  )

  notes <- character()
  last_result <- NULL

  for (plan in plans) {
    res <- safe_bien_retry(
      function() {
        BIEN_occurrence_species(
          species = species_name,
          cultivated = include_cultivated,
          all.taxonomy = TRUE,
          native.status = TRUE,
          natives.only = plan$natives.only,
          observation.type = TRUE,
          political.boundaries = FALSE,
          collection.info = FALSE,
          only.geovalid = plan$only.geovalid,
          limit = plan$limit,
          record_limit = plan$record_limit,
          fetch.query = FALSE
        )
      },
      timeout_sec = min(timeout_sec, 25),
      attempts = 1
    )

    last_result <- res$result
    notes <- c(notes, paste0("occ_strategy=", plan$label, "; status=", res$status, "; attempts=", res$attempt, "; limit=", plan$limit))

    if (is.data.frame(res$result) && nrow(res$result) > 0) {
      return(list(data = res$result, strategy = plan$label, notes = notes, limit_used = plan$limit))
    }

    if (inherits(res$result, "error")) {
      notes <- c(notes, paste("occ_error:", conditionMessage(res$result)))
    }
  }

  list(data = last_result, strategy = "none", notes = notes, limit_used = fast_limit)
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

# Collapse raw BIEN provenance fields into broader scientist-readable record classes.
categorize_observation_records <- function(df) {
  if (!is.data.frame(df) || nrow(df) == 0) {
    return(df)
  }

  obs_type_col <- find_first_col(df, c("observation_type", "observation.type"))
  source_col <- find_first_col(df, c("datasource", "data_source", "collection", "source"))
  dataset_col <- find_first_col(df, c("dataset", "dataset_name"))
  basis_col <- find_first_col(df, c("basisOfRecord", "basis_of_record"))

  obs_txt <- if (!is.null(obs_type_col)) as.character(df[[obs_type_col]]) else rep("", nrow(df))
  source_txt <- if (!is.null(source_col)) as.character(df[[source_col]]) else rep("", nrow(df))
  dataset_txt <- if (!is.null(dataset_col)) as.character(df[[dataset_col]]) else rep("", nrow(df))
  basis_txt <- if (!is.null(basis_col)) as.character(df[[basis_col]]) else rep("", nrow(df))

  combined_txt <- tolower(paste(
    ifelse(is.na(obs_txt), "", obs_txt),
    ifelse(is.na(source_txt), "", source_txt),
    ifelse(is.na(dataset_txt), "", dataset_txt),
    ifelse(is.na(basis_txt), "", basis_txt)
  ))

  df$observation_category <- case_when(
    str_detect(combined_txt, "inaturalist") ~ "Citizen science (iNaturalist)",
    str_detect(combined_txt, "trait|measurement") ~ "Trait measurement",
    str_detect(combined_txt, "plot|survey|inventory|monitoring") ~ "Plot / survey",
    str_detect(combined_txt, "specimen|herb|preserved specimen|preservedspecimen|museum") ~ "Specimen / herbarium",
    str_detect(combined_txt, "human observation|human_observation|observation") & str_detect(combined_txt, "gbif") ~ "Citizen science / GBIF observation",
    str_detect(combined_txt, "gbif") ~ "GBIF / other aggregator",
    TRUE ~ "Other / unknown"
  )

  df
}

summarize_observation_sources <- function(df) {
  if (!is.data.frame(df) || nrow(df) == 0) {
    return(data.frame(message = "No observation records available for source summary."))
  }

  df <- categorize_observation_records(df)
  obs_type_col <- find_first_col(df, c("observation_type", "observation.type"))
  source_col <- find_first_col(df, c("datasource", "data_source", "collection", "source"))
  dataset_col <- find_first_col(df, c("dataset", "dataset_name"))

  df %>%
    mutate(
      observation_category = ifelse(is.na(observation_category) | observation_category == "", "Other / unknown", observation_category),
      observation_type_std = if (!is.null(obs_type_col)) as.character(.data[[obs_type_col]]) else NA_character_,
      source_std = if (!is.null(source_col)) as.character(.data[[source_col]]) else NA_character_,
      dataset_std = if (!is.null(dataset_col)) as.character(.data[[dataset_col]]) else NA_character_
    ) %>%
    mutate(
      observation_type_std = ifelse(is.na(observation_type_std) | observation_type_std == "", "unknown", observation_type_std),
      source_std = ifelse(is.na(source_std) | source_std == "", "unknown", source_std),
      dataset_std = ifelse(is.na(dataset_std) | dataset_std == "", "unknown", dataset_std)
    ) %>%
    group_by(observation_category, observation_type_std, source_std, dataset_std) %>%
    summarise(n_records = n(), .groups = "drop") %>%
    arrange(desc(n_records), observation_category, observation_type_std)
}

extract_primary_value <- function(df, candidates, default = "Not available") {
  if (!is.data.frame(df) || nrow(df) == 0) {
    return(default)
  }

  col <- find_first_col(df, candidates)
  if (is.null(col)) {
    return(default)
  }

  vals <- unique(na.omit(as.character(df[[col]])))
  vals <- vals[vals != ""]

  if (length(vals) == 0) {
    return(default)
  }

  paste(utils::head(vals, 3), collapse = " | ")
}

summarize_status_counts <- function(df, candidates, missing_message = "Not returned by BIEN", value_map = NULL) {
  if (!is.data.frame(df) || nrow(df) == 0) {
    return("No mapped points")
  }

  col <- find_first_col(df, candidates)
  if (is.null(col)) {
    return(missing_message)
  }

  vals <- trimws(tolower(as.character(df[[col]])))
  vals[is.na(vals) | vals == ""] <- "unknown"

  if (!is.null(value_map)) {
    mapped_vals <- unname(value_map[vals])
    keep_original <- is.na(mapped_vals)
    vals[!keep_original] <- mapped_vals[!keep_original]
  }

  tbl <- sort(table(vals, useNA = "ifany"), decreasing = TRUE)
  paste(paste(names(tbl), as.integer(tbl), sep = ": "), collapse = " | ")
}

summarize_coordinate_quality <- function(occ_info) {
  qa <- occ_info$qa

  if (is.null(qa) || is.null(qa$total)) {
    return("Not available")
  }

  paste0(
    "valid coordinates: ", qa$coord_valid,
    " | missing/out-of-range: ", qa$removed_invalid,
    " | duplicate points removed: ", qa$duplicates_removed
  )
}

# Prepare trait values for plotting by separating continuous traits from categorical traits.
prepare_trait_visual_data <- function(traits) {
  if (!is.data.frame(traits) || nrow(traits) == 0) {
    return(NULL)
  }

  trait_name_col <- find_first_col(traits, c("trait_name", "trait"))
  trait_value_col <- find_first_col(traits, c("trait_value", "value"))
  unit_col <- find_first_col(traits, c("unit", "units"))

  if (is.null(trait_name_col) || is.null(trait_value_col)) {
    return(NULL)
  }

  plot_df <- traits %>%
    mutate(
      trait_name_std = as.character(.data[[trait_name_col]]),
      trait_value_std = as.character(.data[[trait_value_col]]),
      unit_std = if (!is.null(unit_col)) as.character(.data[[unit_col]]) else NA_character_
    ) %>%
    filter(!is.na(trait_name_std), trait_name_std != "", !is.na(trait_value_std), trait_value_std != "") %>%
    mutate(
      trait_value_num = suppressWarnings(as.numeric(stringr::str_extract(trait_value_std, "-?[0-9]*\\.?[0-9]+(?:[eE][+-]?[0-9]+)?")))
    )

  if (nrow(plot_df) == 0) {
    return(NULL)
  }

  summary_tbl <- plot_df %>%
    group_by(trait_name_std, unit_std) %>%
    group_modify(~ {
      df <- .x
      num_vals <- df$trait_value_num[!is.na(df$trait_value_num)]
      is_continuous <- length(num_vals) >= max(3, ceiling(0.6 * nrow(df))) && length(unique(num_vals)) > 1

      if (is_continuous) {
        tibble(
          value_type = "continuous",
          n_records = nrow(df),
          mean_value = round(mean(num_vals), 4),
          min_value = round(min(num_vals), 4),
          max_value = round(max(num_vals), 4),
          modal_value = NA_character_,
          summary_note = paste0("mean=", round(mean(num_vals), 3), "; range=", round(min(num_vals), 3), " to ", round(max(num_vals), 3))
        )
      } else {
        val_tbl <- sort(table(df$trait_value_std), decreasing = TRUE)
        mode_val <- names(val_tbl)[1]
        tibble(
          value_type = "categorical",
          n_records = nrow(df),
          mean_value = NA_real_,
          min_value = NA_real_,
          max_value = NA_real_,
          modal_value = mode_val,
          summary_note = paste0("mode=", mode_val, " (n=", unname(val_tbl[1]), ")")
        )
      }
    }) %>%
    ungroup() %>%
    arrange(desc(n_records), trait_name_std)

  list(data = plot_df, summary = summary_tbl)
}

# Standardize, QA, de-duplicate, and optionally thin occurrence records before mapping.
prepare_occurrences <- function(occ, map_point_cap = 800, sample_method = "random") {
  sample_method <- if (identical(sample_method, "head")) "head" else "random"

  if (!is.data.frame(occ) || nrow(occ) == 0) {
    return(list(data = NULL, lat_col = NULL, lon_col = NULL, qa = list(total = 0, coord_valid = 0, kept = 0, removed = 0, removed_invalid = 0, duplicates_removed = 0), map_cap_applied = FALSE, map_cap = map_point_cap, original_kept = 0, sample_method = sample_method))
  }

  occ <- categorize_observation_records(occ)
  lat_col <- find_first_col(occ, c("latitude", "decimal_latitude", "lat"))
  lon_col <- find_first_col(occ, c("longitude", "decimal_longitude", "lon", "long"))

  if (is.null(lat_col) || is.null(lon_col)) {
    return(list(data = occ, lat_col = NULL, lon_col = NULL, qa = list(total = nrow(occ), coord_valid = 0, kept = nrow(occ), removed = 0, removed_invalid = nrow(occ), duplicates_removed = 0), map_cap_applied = FALSE, map_cap = map_point_cap, original_kept = nrow(occ), sample_method = sample_method))
  }

  occ[[lat_col]] <- suppressWarnings(as.numeric(occ[[lat_col]]))
  occ[[lon_col]] <- suppressWarnings(as.numeric(occ[[lon_col]]))

  total_n <- nrow(occ)
  valid_coord_mask <- !is.na(occ[[lat_col]]) & !is.na(occ[[lon_col]]) &
    occ[[lat_col]] >= -90 & occ[[lat_col]] <= 90 &
    occ[[lon_col]] >= -180 & occ[[lon_col]] <= 180

  coord_valid_n <- sum(valid_coord_mask)
  removed_invalid_n <- total_n - coord_valid_n
  occ <- occ[valid_coord_mask, , drop = FALSE]

  species_col <- find_first_col(occ, c("scrubbed_species_binomial", "species", "scientific_name", "taxon"))
  obs_type_col <- find_first_col(occ, c("observation_type", "observation.type"))

  if (!is.null(species_col) && !is.null(obs_type_col)) {
    occ <- occ %>% distinct(.data[[species_col]], .data[[lat_col]], .data[[lon_col]], .data[[obs_type_col]], .keep_all = TRUE)
  } else if (!is.null(species_col)) {
    occ <- occ %>% distinct(.data[[species_col]], .data[[lat_col]], .data[[lon_col]], .keep_all = TRUE)
  } else {
    occ <- occ %>% distinct(.data[[lat_col]], .data[[lon_col]], .keep_all = TRUE)
  }

  kept_n <- nrow(occ)
  original_kept_n <- kept_n
  duplicates_removed_n <- coord_valid_n - original_kept_n

  if (kept_n > map_point_cap) {
    occ <- if (sample_method == "random") {
      occ %>% slice_sample(n = map_point_cap)
    } else {
      occ %>% slice_head(n = map_point_cap)
    }
    kept_n <- nrow(occ)
    map_cap_applied <- TRUE
  } else {
    map_cap_applied <- FALSE
  }

  list(
    data = occ,
    lat_col = lat_col,
    lon_col = lon_col,
    qa = list(total = total_n, coord_valid = coord_valid_n, kept = kept_n, removed = total_n - original_kept_n, removed_invalid = removed_invalid_n, duplicates_removed = duplicates_removed_n),
    map_cap_applied = map_cap_applied,
    map_cap = map_point_cap,
    original_kept = original_kept_n,
    sample_method = sample_method
  )
}

make_popup_text <- function(df) {
  species_col <- find_first_col(df, c("scrubbed_species_binomial", "species", "scientific_name", "taxon"))
  country_col <- find_first_col(df, c("country", "country_name"))
  state_col <- find_first_col(df, c("state_province", "state"))
  source_col <- find_first_col(df, c("datasource", "data_source", "collection", "source"))
  obs_type_col <- find_first_col(df, c("observation_type", "observation.type"))
  intro_col <- find_first_col(df, c("is_introduced"))
  category_txt <- if ("observation_category" %in% names(df)) as.character(df$observation_category) else NA_character_

  species_txt <- if (!is.null(species_col)) df[[species_col]] else "record"
  country_txt <- if (!is.null(country_col)) df[[country_col]] else NA_character_
  state_txt <- if (!is.null(state_col)) df[[state_col]] else NA_character_
  source_txt <- if (!is.null(source_col)) df[[source_col]] else NA_character_
  obs_type_txt <- if (!is.null(obs_type_col)) df[[obs_type_col]] else NA_character_
  intro_txt <- if (!is.null(intro_col)) as.character(df[[intro_col]]) else NA_character_

  paste0(
    "<strong>", species_txt, "</strong>",
    ifelse(!is.na(category_txt), paste0("<br>Observation category: ", category_txt), ""),
    ifelse(!is.na(obs_type_txt), paste0("<br>Observation type: ", obs_type_txt), ""),
    ifelse(!is.na(country_txt), paste0("<br>Country: ", country_txt), ""),
    ifelse(!is.na(state_txt), paste0("<br>Region: ", state_txt), ""),
    ifelse(!is.na(source_txt), paste0("<br>Source: ", source_txt), ""),
    ifelse(!is.na(intro_txt), paste0("<br>Introduced flag: ", intro_txt), "")
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

# Main Shiny user interface: query controls plus linked tabs for occurrence, trait, and range evidence.
ui <- fluidPage(
  titlePanel("BIEN Shiny App: Species-Level Observation Explorer"),
  sidebarLayout(
    sidebarPanel(
      textInput("species", "Species name", value = "Eschscholzia californica", placeholder = "Genus species"),
      actionButton("run_query", "Query BIEN", class = "btn-primary"),
      tags$script(HTML("$(document).on('keydown', '#species', function(e) { if (e.key === 'Enter') { $('#run_query').click(); return false; } });")),
      tags$hr(),
      checkboxInput("use_introduced_filter", "Use BIEN `is_introduced` filter", value = TRUE),
      checkboxInput("natives_only", "When used, keep native records only", value = TRUE),
      checkboxInput("use_cultivated_filter", "Use BIEN `is_cultivated` filter", value = TRUE),
      checkboxInput("include_cultivated", "When used, include cultivated records", value = FALSE),
      checkboxInput("only_geovalid", "Only geovalid coordinates", value = TRUE),
      numericInput("occurrence_limit", "Occurrence records to keep in app sample", value = 1000, min = 200, max = 50000, step = 200),
      checkboxInput("randomize_occurrence_sample", "Randomize occurrence sample before display", value = TRUE),
      selectInput("map_sampling_method", "If too many points for the map", choices = c("Random sample" = "random", "First returned" = "head"), selected = "random"),
      selectInput("map_color_by", "Color map points by", choices = c("Observation category" = "category", "Raw BIEN observation_type" = "type"), selected = "category"),
      numericInput("trait_limit", "Max trait records (sample)", value = 1000, min = 100, max = 50000, step = 100),
      checkboxInput("include_range_query", "Run range query (can be slower)", value = TRUE),
      numericInput("query_timeout", "Query timeout (seconds)", value = 45, min = 15, max = 300, step = 15),
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
          uiOutput("overview_notice"),
          br(),
          leafletOutput("occurrence_map", height = 550)
        ),
        tabPanel("Observation Table", br(), DTOutput("occurrence_table")),
        tabPanel("Observation Sources", br(), DTOutput("observation_source_table")),
        tabPanel("Traits", br(), DTOutput("trait_table")),
        tabPanel("Trait Summary", br(), DTOutput("trait_summary_table")),
        tabPanel("Trait Graphics", br(), plotOutput("trait_plot", height = 800), br(), DTOutput("trait_visual_table")),
        tabPanel("Range", br(), verbatimTextOutput("range_text"), leafletOutput("range_map", height = 500), br(), DTOutput("range_table")),
        tabPanel("Reconciliation", br(), DTOutput("reconciliation_table"), br(), verbatimTextOutput("error_log"))
      ),
      width = 9
    )
  )
)

# Server logic: query BIEN, prepare outputs, and render maps/tables/plots for the current species.
server <- function(input, output, session) {
  bien_results <- eventReactive(input$run_query, {
    req(nchar(str_trim(input$species)) > 0)

    species_name <- str_squish(input$species)
    include_range_query <- if (is.null(input$include_range_query)) TRUE else isTRUE(input$include_range_query)
    timeout_sec <- max(15, as.numeric(input$query_timeout))
    occ_limit <- max(200, as.numeric(input$occurrence_limit))
    trait_limit <- max(100, as.numeric(input$trait_limit))
    sample_random <- if (is.null(input$randomize_occurrence_sample)) TRUE else isTRUE(input$randomize_occurrence_sample)
    map_sampling_method <- if (is.null(input$map_sampling_method)) "random" else input$map_sampling_method
    occ_page_size <- min(1000, max(occ_limit, 500))
    trait_page_size <- min(500, trait_limit)
    occ_fetch_limit <- min(if (sample_random) max(occ_limit * 2, 1000) else occ_limit, 2000)
    trait_fetch_limit <- min(trait_limit, 1000)
    range_dir <- file.path(tempdir(), "bien_ranges_cache", gsub("\\s+", "_", species_name))
    dir.create(range_dir, recursive = TRUE, showWarnings = FALSE)

    withProgress(message = paste("Querying BIEN for", species_name), value = 0, {
      incProgress(0.2, detail = "Occurrences")
      occ_bundle <- query_occurrence_with_fallback(species_name, input, occ_fetch_limit, occ_page_size, timeout_sec)
      occ <- occ_bundle$data
      occ_strategy <- occ_bundle$strategy
      occ_limit_used <- occ_bundle$limit_used
      occ_error <- if (inherits(occ, "error")) conditionMessage(occ) else NULL
      occ_returned_n <- if (is.data.frame(occ)) nrow(occ) else 0

      if (is.data.frame(occ)) {
        occ <- categorize_observation_records(occ)
        if (nrow(occ) > occ_limit) {
          occ <- if (sample_random) {
            occ %>% slice_sample(n = occ_limit)
          } else {
            occ %>% slice_head(n = occ_limit)
          }
        }
      }

      incProgress(0.5, detail = "Traits")
      traits <- safe_bien_call(
        BIEN_trait_species(
          species = species_name,
          all.taxonomy = TRUE,
          source.citation = TRUE,
          limit = trait_fetch_limit,
          record_limit = trait_page_size,
          fetch.query = FALSE
        ),
        timeout_sec = min(timeout_sec, 20)
      )
      traits_error <- if (inherits(traits, "error")) conditionMessage(traits) else NULL
      if (is.data.frame(traits)) {
        names(traits) <- make.unique(names(traits))
      }

      incProgress(0.8, detail = "Ranges")
      ranges <- if (include_range_query) {
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
          timeout_sec = min(timeout_sec, 20)
        )
      } else {
        data.frame(note = "Range query skipped by user setting")
      }
      range_error <- if (inherits(ranges, "error")) conditionMessage(ranges) else NULL

      range_sf <- read_downloaded_range_sf(range_dir, species_name)
      occ_prepared <- if (is.data.frame(occ)) prepare_occurrences(occ, map_point_cap = 800, sample_method = map_sampling_method) else list(data = NULL, lat_col = NULL, lon_col = NULL, qa = list(total = 0, coord_valid = 0, kept = 0, removed = 0, removed_invalid = 0, duplicates_removed = 0), map_cap_applied = FALSE, map_cap = 800, original_kept = 0, sample_method = map_sampling_method)
      family_name <- extract_primary_value(occ, c("scrubbed_family", "family", "verbatim_family"))
      if (identical(family_name, "Not available")) {
        family_name <- extract_primary_value(traits, c("scrubbed_family", "family", "verbatim_family"))
      }

      query_errors <- c(occ_bundle$notes, occ_error, traits_error, range_error)
      query_errors <- query_errors[!is.na(query_errors)]
      reconciliation_tbl <- build_reconciliation_table(species_name, occ, traits, query_errors, ranges)

      incProgress(1, detail = "Done")

      list(
        species = species_name,
        family_name = family_name,
        occurrences = occ,
        occurrences_prepared = occ_prepared,
        occurrences_returned = occ_returned_n,
        occurrence_sample_mode = if (sample_random) "random" else "head",
        traits = traits,
        ranges = ranges,
        range_sf = range_sf,
        range_dir = range_dir,
        timeout_sec = timeout_sec,
        occ_limit = occ_limit,
        trait_limit = trait_limit,
        occ_fetch_limit = occ_limit_used,
        trait_fetch_limit = trait_fetch_limit,
        occ_strategy = occ_strategy,
        use_cultivated_filter = if (is.null(input$use_cultivated_filter)) TRUE else isTRUE(input$use_cultivated_filter),
        use_introduced_filter = if (is.null(input$use_introduced_filter)) TRUE else isTRUE(input$use_introduced_filter),
        include_cultivated = if (is.null(input$include_cultivated)) FALSE else isTRUE(input$include_cultivated),
        natives_only = if (is.null(input$natives_only)) TRUE else isTRUE(input$natives_only),
        query_errors = query_errors,
        reconciliation = reconciliation_tbl
      )
    })
  }, ignoreNULL = FALSE)

  output$query_summary <- renderUI({
    res <- bien_results()

    occ_n <- if (is.data.frame(res$occurrences)) nrow(res$occurrences) else 0
    occ_returned_n <- if (!is.null(res$occurrences_returned)) res$occurrences_returned else occ_n
    mappable_n <- if (is.data.frame(res$occurrences_prepared$data)) nrow(res$occurrences_prepared$data) else 0
    trait_n <- if (is.data.frame(res$traits)) nrow(res$traits) else 0
    family_name <- if (!is.null(res$family_name)) res$family_name else "Not available"
    mapped_df <- if (is.data.frame(res$occurrences_prepared$data)) res$occurrences_prepared$data else res$occurrences

    category_line <- if (is.data.frame(res$occurrences) && "observation_category" %in% names(res$occurrences)) {
      counts <- sort(table(res$occurrences$observation_category), decreasing = TRUE)
      paste(paste(names(counts), as.integer(counts), sep = ": "), collapse = " | ")
    } else {
      "Not available"
    }
    introduced_line <- summarize_status_counts(
      mapped_df,
      c("native_status", "is_introduced"),
      missing_message = "Not returned by BIEN",
      value_map = c(
        "true" = "introduced", "false" = "native / not introduced",
        "t" = "introduced", "f" = "native / not introduced",
        "1" = "introduced", "0" = "native / not introduced",
        "i" = "introduced", "n" = "native / not introduced",
        "introduced" = "introduced", "native" = "native / not introduced"
      )
    )
    cultivated_line <- summarize_status_counts(
      mapped_df,
      c("is_cultivated", "cultivated"),
      missing_message = "Per-record cultivated status not returned by BIEN for this query",
      value_map = c(
        "true" = "cultivated", "false" = "not cultivated",
        "t" = "cultivated", "f" = "not cultivated",
        "1" = "cultivated", "0" = "not cultivated",
        "y" = "cultivated", "n" = "not cultivated",
        "yes" = "cultivated", "no" = "not cultivated"
      )
    )
    geovalid_line <- summarize_coordinate_quality(res$occurrences_prepared)
    range_status <- if (inherits(res$ranges, "error")) {
      "Range query returned an error"
    } else if (is.null(res$ranges)) {
      "No range result returned"
    } else if (inherits(res$range_sf, "sf") && nrow(res$range_sf) > 0) {
      paste("Range polygon loaded from", res$range_dir)
    } else {
      paste("Range result type:", paste(class(res$ranges), collapse = ", "))
    }

    map_status <- if (mappable_n > 0 && isTRUE(res$occurrences_prepared$map_cap_applied)) {
      paste("Showing", mappable_n, "sampled occurrence point(s) out of", res$occurrences_prepared$original_kept, "mappable records")
    } else if (mappable_n > 0) {
      paste("Showing", mappable_n, "occurrence point(s)")
    } else if (occ_n > 0 && inherits(res$range_sf, "sf") && nrow(res$range_sf) > 0) {
      "No usable BIEN occurrence coordinates were returned; showing BIEN range polygon instead"
    } else if (occ_n > 0) {
      "Occurrence rows were returned, but no usable coordinates were available to map"
    } else {
      "No occurrence rows were returned"
    }

    HTML(paste0(
      "<strong>Species:</strong> ", res$species,
      "<br><strong>Family:</strong> ", family_name,
      "<br><strong>Observation records returned by BIEN:</strong> ", occ_returned_n,
      "<br><strong>Observation records kept in app sample:</strong> ", occ_n,
      "<br><strong>Observation sample mode:</strong> ", ifelse(res$occurrence_sample_mode == "random", "random sample of returned BIEN rows", "first returned BIEN rows"),
      "<br><strong>Observation categories:</strong> ", category_line,
      "<br><strong>Mappable occurrence points:</strong> ", mappable_n,
      "<br><strong>Mapped-point native / introduced status:</strong> ", introduced_line,
      "<br><strong>Mapped-point cultivated status:</strong> ", cultivated_line,
      "<br><strong>Coordinate / geovalid summary:</strong> ", geovalid_line,
      "<br><strong>Overview map status:</strong> ", map_status,
      "<br><strong>Observation records after QA:</strong> ", res$occurrences_prepared$original_kept,
      "<br><strong>Observation records rendered on map:</strong> ", res$occurrences_prepared$qa$kept,
      "<br><strong>Observation records removed by QA:</strong> ", res$occurrences_prepared$qa$removed,
      "<br><strong>Trait records:</strong> ", trait_n,
      "<br><strong>Query timeout:</strong> ", res$timeout_sec, " sec",
      "<br><strong>Occurrence limit requested:</strong> ", res$occ_limit,
      "<br><strong>Occurrence fetch cap used:</strong> ", res$occ_fetch_limit,
      "<br><strong>Trait limit requested:</strong> ", res$trait_limit,
      "<br><strong>Trait fetch cap used:</strong> ", res$trait_fetch_limit,
      "<br><strong>Use BIEN is_cultivated filter:</strong> ", ifelse(res$use_cultivated_filter, paste0("yes (include cultivated = ", tolower(as.character(res$include_cultivated)), ")"), "no"),
      "<br><strong>Use BIEN is_introduced filter:</strong> ", ifelse(res$use_introduced_filter, paste0("yes (native only = ", tolower(as.character(res$natives_only)), ")"), "no"),
      "<br><strong>Occurrence strategy:</strong> ", res$occ_strategy,
      if (occ_n > 0 && mappable_n == 0) {
        "<br><strong>Map note:</strong> This is a BIEN data-response limitation for the current species/query, not necessarily an app error."
      } else {
        ""
      },
      if (any(grepl("elapsed time limit", res$query_errors, fixed = TRUE))) {
        "<br><strong>Performance note:</strong> BIEN timed out for at least one endpoint; try the default sample sizes or rerun the query."
      } else {
        ""
      },
      "<br><strong>Range query status:</strong> ", range_status
    ))
  })

  output$overview_notice <- renderUI({
    res <- bien_results()
    occ_n <- if (is.data.frame(res$occurrences)) nrow(res$occurrences) else 0
    mappable_n <- if (is.data.frame(res$occurrences_prepared$data)) nrow(res$occurrences_prepared$data) else 0
    has_range <- inherits(res$range_sf, "sf") && nrow(res$range_sf) > 0

    if (occ_n > 0 && mappable_n == 0 && has_range) {
      return(tags$div(
        style = "background:#fff3cd;border:1px solid #ffe69c;color:#664d03;padding:10px 12px;border-radius:6px;margin:8px 0;",
        tags$strong("Overview note: "),
        "BIEN returned occurrence rows for this species, but not usable latitude/longitude coordinates in the current response. The map below is showing the BIEN range polygon instead."
      ))
    }

    if (occ_n > 0 && mappable_n == 0) {
      return(tags$div(
        style = "background:#f8d7da;border:1px solid #f1aeb5;color:#842029;padding:10px 12px;border-radius:6px;margin:8px 0;",
        tags$strong("Overview note: "),
        "Occurrence rows were returned, but no usable coordinates are available to map for this species in the current BIEN response."
      ))
    }

    NULL
  })

  output$occurrence_map <- renderLeaflet({
    res <- bien_results()
    occ_info <- res$occurrences_prepared

    map <- leaflet() %>% addProviderTiles(providers$CartoDB.Positron)

    if (is.null(occ_info$data) || nrow(occ_info$data) == 0 || is.null(occ_info$lat_col) || is.null(occ_info$lon_col)) {
      if (inherits(res$range_sf, "sf") && nrow(res$range_sf) > 0) {
        sf_obj <- suppressWarnings(st_make_valid(res$range_sf))
        geom_type <- unique(as.character(st_geometry_type(sf_obj)))

        if (any(geom_type %in% c("POLYGON", "MULTIPOLYGON"))) {
          map <- map %>% addPolygons(
            data = sf_obj,
            fillOpacity = 0.2,
            weight = 2,
            color = "#1B9E77",
            popup = paste0(res$species, " (range polygon)")
          )
        } else {
          map <- map %>% addCircleMarkers(data = sf_obj, radius = 4, stroke = FALSE, fillOpacity = 0.7)
        }

        bbox <- st_bbox(sf_obj)
        return(map %>% fitBounds(bbox[["xmin"]], bbox[["ymin"]], bbox[["xmax"]], bbox[["ymax"]]))
      }
      return(map %>% setView(lng = 0, lat = 20, zoom = 2))
    }

    df <- occ_info$data
    lat_col <- occ_info$lat_col
    lon_col <- occ_info$lon_col

    color_by <- if (is.null(input$map_color_by)) "category" else input$map_color_by
    obs_type_col <- find_first_col(df, c("observation_type", "observation.type"))

    if (identical(color_by, "category") && "observation_category" %in% names(df)) {
      color_vals <- as.character(df$observation_category)
      legend_title <- "Observation category"
    } else {
      color_vals <- if (!is.null(obs_type_col)) as.character(df[[obs_type_col]]) else rep("unknown", nrow(df))
      legend_title <- "Observation type"
    }

    color_vals[is.na(color_vals) | color_vals == ""] <- "unknown"
    pal <- colorFactor(
      palette = c("#1b9e77", "#d95f02", "#7570b3", "#e7298a", "#66a61e", "#e6ab02", "#a6761d", "#666666"),
      domain = sort(unique(color_vals))
    )

    map <- map %>% addCircleMarkers(
      lng = df[[lon_col]],
      lat = df[[lat_col]],
      radius = 4,
      stroke = FALSE,
      color = pal(color_vals),
      fillColor = pal(color_vals),
      fillOpacity = 0.75,
      popup = make_popup_text(df),
      options = pathOptions(pane = "markerPane")
    ) %>%
      addLegend(
        position = "bottomright",
        pal = pal,
        values = color_vals,
        title = legend_title,
        opacity = 0.9
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

    occ_tbl <- res$occurrences
    if ("observation_category" %in% names(occ_tbl)) {
      occ_tbl <- occ_tbl %>% select(observation_category, everything())
    }

    datatable(occ_tbl, filter = "top", options = list(pageLength = 10, scrollX = TRUE))
  })

  output$observation_source_table <- renderDT({
    res <- bien_results()
    summary_tbl <- summarize_observation_sources(res$occurrences)
    datatable(summary_tbl, filter = "top", options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
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

  output$trait_visual_table <- renderDT({
    res <- bien_results()
    trait_vis <- prepare_trait_visual_data(res$traits)

    if (is.null(trait_vis) || !is.data.frame(trait_vis$summary) || nrow(trait_vis$summary) == 0) {
      return(datatable(data.frame(message = "No trait values available for graphical summary."), options = list(dom = "t"), rownames = FALSE))
    }

    datatable(trait_vis$summary, options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
  })

  output$trait_plot <- renderPlot({
    res <- bien_results()
    trait_vis <- prepare_trait_visual_data(res$traits)

    if (is.null(trait_vis) || !is.data.frame(trait_vis$summary) || nrow(trait_vis$summary) == 0) {
      plot.new()
      text(0.5, 0.5, "No plottable trait values returned for this species.", cex = 1.1)
      return(invisible(NULL))
    }

    summary_tbl <- trait_vis$summary %>% slice_head(n = min(6, nrow(trait_vis$summary)))
    plot_df <- trait_vis$data

    n_panels <- nrow(summary_tbl)
    n_col <- if (n_panels <= 1) 1 else 2
    n_row <- ceiling(n_panels / n_col)

    old_par <- par(no.readonly = TRUE)
    on.exit(par(old_par), add = TRUE)
    par(mfrow = c(n_row, n_col), mar = c(7, 4, 4, 1) + 0.1)

    for (i in seq_len(n_panels)) {
      trait_row <- summary_tbl[i, , drop = FALSE]
      trait_name <- trait_row$trait_name_std[[1]]
      unit_txt <- trait_row$unit_std[[1]]
      unit_suffix <- if (!is.na(unit_txt) && nzchar(unit_txt)) paste0(" (", unit_txt, ")") else ""
      df <- plot_df %>% filter(trait_name_std == trait_name)

      if (trait_row$value_type[[1]] == "continuous") {
        num_vals <- df$trait_value_num[!is.na(df$trait_value_num)]
        hist(
          num_vals,
          main = paste0(trait_name, unit_suffix),
          xlab = "Trait value",
          col = "#66c2a5",
          border = "white"
        )
        abline(v = mean(num_vals), col = "#d73027", lwd = 2)
        mtext(trait_row$summary_note[[1]], side = 3, line = 0.2, cex = 0.8)
      } else {
        counts <- sort(table(df$trait_value_std), decreasing = TRUE)
        top_counts <- head(counts, 6)
        barplot(
          top_counts,
          las = 2,
          col = "#8da0cb",
          main = paste0(trait_name, unit_suffix),
          ylab = "Count",
          cex.names = 0.8
        )
        mtext(trait_row$summary_note[[1]], side = 3, line = 0.2, cex = 0.8)
      }
    }
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
