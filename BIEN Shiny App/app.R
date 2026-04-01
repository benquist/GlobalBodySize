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

# Query BIEN occurrences with the same biological filters used by the BIEN helper,
# but (1) exclude trait-linked rows that belong in the Traits tab rather than the
# occurrence map and (2) randomize the returned row order on the BIEN side so
# widespread species are less likely to be dominated by whichever datasource
# happens to come first in the backend table (for example FIA plot rows).
query_occurrence_randomized <- function(species_name, cultivated = FALSE, natives_only = TRUE, only_geovalid = TRUE, limit = 1000, record_limit = 500) {
  cultivated_ <- BIEN:::.cultivated_check(cultivated)
  newworld_ <- BIEN:::.newworld_check(NULL)
  taxonomy_ <- BIEN:::.taxonomy_check(TRUE)
  native_ <- BIEN:::.native_check(TRUE)
  observation_ <- BIEN:::.observation_check(TRUE)
  political_ <- BIEN:::.political_check(FALSE)
  natives_ <- BIEN:::.natives_check(natives_only)
  collection_ <- BIEN:::.collection_check(FALSE)
  geovalid_ <- BIEN:::.geovalid_check(only_geovalid)

  query <- paste(
    "SELECT scrubbed_species_binomial", taxonomy_$select,
    native_$select, political_$select,
    ",latitude, longitude,date_collected,",
    "datasource,dataset,dataowner,custodial_institution_codes,collection_code,view_full_occurrence_individual.datasource_id",
    collection_$select, cultivated_$select, newworld_$select,
    observation_$select, geovalid_$select,
    "FROM view_full_occurrence_individual",
    "WHERE scrubbed_species_binomial in (", paste(shQuote(species_name, type = "sh"), collapse = ", "), ")",
    cultivated_$query, newworld_$query, natives_$query,
    observation_$query, geovalid_$query,
    "AND higher_plant_group NOT IN ('Algae','Bacteria','Fungi')",
    "AND (georef_protocol is NULL OR georef_protocol<>'county centroid')",
    "AND (is_centroid IS NULL OR is_centroid=0)",
    "AND scrubbed_species_binomial IS NOT NULL",
    "AND lower(coalesce(observation_type, '')) NOT LIKE '%trait%'",
    "AND lower(coalesce(observation_type, '')) NOT LIKE '%measurement%'",
    "ORDER BY random() LIMIT", as.integer(limit), ";"
  )

  BIEN:::.BIEN_sql(
    query,
    fetch.query = FALSE,
    record_limit = record_limit
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

  # Try the user-requested interpretation first, then relax native-only and finally
  # geovalid constraints if needed so the app can still show some BIEN evidence.
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
        query_occurrence_randomized(
          species_name = species_name,
          cultivated = include_cultivated,
          natives_only = plan$natives.only,
          only_geovalid = plan$only.geovalid,
          limit = plan$limit,
          record_limit = plan$record_limit
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
      err_msg <- conditionMessage(res$result)
      notes <- c(notes, paste("occ_error:", err_msg))

      if (is_bien_connection_error(err_msg)) {
        break
      }
    }
  }

  final_strategy <- if (is_bien_connection_error(notes)) "backend_connection_error" else "none"
  list(data = last_result, strategy = final_strategy, notes = notes, limit_used = fast_limit)
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

# Run a BIEN-side COUNT(*) query so the app can report how many matching occurrence
# records exist in BIEN without downloading all rows into the Shiny session.
count_occurrence_records <- function(species_name, cultivated = FALSE, natives_only = TRUE, only_geovalid = TRUE, timeout_sec = 30) {
  count_res <- safe_bien_call({
    cultivated_ <- BIEN:::.cultivated_check(cultivated)
    newworld_ <- BIEN:::.newworld_check(NULL)
    natives_ <- BIEN:::.natives_check(natives_only)
    observation_ <- BIEN:::.observation_check(TRUE)
    geovalid_ <- BIEN:::.geovalid_check(only_geovalid)

    count_query <- paste(
      "SELECT COUNT(*) AS bien_total_records",
      "FROM view_full_occurrence_individual",
      "WHERE scrubbed_species_binomial in (", paste(shQuote(species_name, type = "sh"), collapse = ", "), ")",
      cultivated_$query, newworld_$query, natives_$query, observation_$query, geovalid_$query,
      "AND higher_plant_group NOT IN ('Algae','Bacteria','Fungi')",
      "AND (georef_protocol is NULL OR georef_protocol<>'county centroid')",
      "AND (is_centroid IS NULL OR is_centroid=0)",
      "AND scrubbed_species_binomial IS NOT NULL ;"
    )

    BIEN:::.BIEN_sql(count_query, fetch.query = FALSE)
  }, timeout_sec = min(timeout_sec, 8))

  if (inherits(count_res, "error")) {
    return(list(total = NA_real_, note = conditionMessage(count_res)))
  }

  count_col <- find_first_col(count_res, c("bien_total_records", "count"))
  if (!is.data.frame(count_res) || is.null(count_col) || nrow(count_res) == 0) {
    return(list(total = NA_real_, note = "Count query did not return a usable total."))
  }

  list(
    total = suppressWarnings(as.numeric(count_res[[count_col]][1])),
    note = "count_only_query"
  )
}

# Run a BIEN-side grouped count query so the Overview can report what fraction of
# the total matching occurrence records appear to be specimens, iNaturalist records,
# plots/surveys, trait-linked rows, or other provenance classes.
count_occurrence_source_mix <- function(species_name, cultivated = FALSE, natives_only = TRUE, only_geovalid = TRUE, timeout_sec = 30) {
  mix_res <- safe_bien_call({
    cultivated_ <- BIEN:::.cultivated_check(cultivated)
    newworld_ <- BIEN:::.newworld_check(NULL)
    natives_ <- BIEN:::.natives_check(natives_only)
    observation_ <- BIEN:::.observation_check(TRUE)
    geovalid_ <- BIEN:::.geovalid_check(only_geovalid)

    combined_sql <- "lower(coalesce(observation_type, '') || ' ' || coalesce(datasource, '') || ' ' || coalesce(dataset, ''))"
    mix_query <- paste(
      "SELECT CASE",
      paste0("WHEN ", combined_sql, " LIKE '%inaturalist%' THEN 'iNaturalist'"),
      paste0("WHEN ", combined_sql, " LIKE '%trait%' OR ", combined_sql, " LIKE '%measurement%' THEN 'Traits'"),
      paste0("WHEN ", combined_sql, " LIKE '%plot%' OR ", combined_sql, " LIKE '%survey%' OR ", combined_sql, " LIKE '%inventory%' OR ", combined_sql, " LIKE '%monitoring%' THEN 'Plots'"),
      paste0("WHEN ", combined_sql, " LIKE '%specimen%' OR ", combined_sql, " LIKE '%herb%' OR ", combined_sql, " LIKE '%preserved specimen%' OR ", combined_sql, " LIKE '%preservedspecimen%' OR ", combined_sql, " LIKE '%museum%' THEN 'Specimens'"),
      "ELSE 'Other' END AS source_group, COUNT(*) AS n_records",
      "FROM view_full_occurrence_individual",
      "WHERE scrubbed_species_binomial in (", paste(shQuote(species_name, type = "sh"), collapse = ", "), ")",
      cultivated_$query, newworld_$query, natives_$query, observation_$query, geovalid_$query,
      "AND higher_plant_group NOT IN ('Algae','Bacteria','Fungi')",
      "AND (georef_protocol is NULL OR georef_protocol<>'county centroid')",
      "AND (is_centroid IS NULL OR is_centroid=0)",
      "AND scrubbed_species_binomial IS NOT NULL",
      "GROUP BY source_group ORDER BY n_records DESC;"
    )

    BIEN:::.BIEN_sql(mix_query, fetch.query = FALSE)
  }, timeout_sec = min(timeout_sec, 8))

  if (inherits(mix_res, "error") || !is.data.frame(mix_res) || nrow(mix_res) == 0) {
    return(NULL)
  }

  source_col <- find_first_col(mix_res, c("source_group"))
  count_col <- find_first_col(mix_res, c("n_records", "count"))
  if (is.null(source_col) || is.null(count_col)) {
    return(NULL)
  }

  tibble(
    source_group = as.character(mix_res[[source_col]]),
    n_records = suppressWarnings(as.numeric(mix_res[[count_col]]))
  )
}

# Format the BIEN-side grouped counts into a fixed-order fraction summary for the
# Overview text so users can quickly compare major provenance classes.
format_occurrence_source_mix <- function(source_tbl, expected_total = NULL) {
  categories <- c("Specimens", "iNaturalist", "Plots", "Traits", "Other")

  if (!is.data.frame(source_tbl) || nrow(source_tbl) == 0) {
    return("Not available")
  }

  counts <- stats::setNames(rep(0, length(categories)), categories)
  source_tbl$source_group <- as.character(source_tbl$source_group)
  source_tbl$n_records <- suppressWarnings(as.numeric(source_tbl$n_records))

  for (cat in categories) {
    hit <- which(source_tbl$source_group == cat)
    if (length(hit) > 0) {
      counts[[cat]] <- sum(source_tbl$n_records[hit], na.rm = TRUE)
    }
  }

  total_n <- if (!is.null(expected_total) && !is.na(expected_total) && expected_total > 0) expected_total else sum(counts, na.rm = TRUE)
  if (!isTRUE(total_n > 0)) {
    return("Not available")
  }

  paste(
    vapply(categories, function(cat) {
      n <- counts[[cat]]
      pct <- 100 * n / total_n
      paste0(cat, " ", sprintf("%.1f", pct), "% (", format(n, big.mark = ",", scientific = FALSE, trim = TRUE), ")")
    }, character(1)),
    collapse = " | "
  )
}

# Extract a numeric value only from simple one-number trait strings. Values that
# look like ranges, dates, or dimensions are left as NA so the plots stay aligned
# with the table summaries and do not imply false precision.
extract_single_numeric_value <- function(x) {
  x <- trimws(as.character(x))
  x[x == ""] <- NA_character_

  token_list <- stringr::str_extract_all(
    x,
    "-?[0-9]*\\.?[0-9]+(?:[eE][+-]?[0-9]+)?"
  )
  token_n <- lengths(token_list)

  lower_x <- tolower(ifelse(is.na(x), "", x))
  ambiguous_value <- stringr::str_detect(lower_x, "[0-9][[:space:]]*[-–/][[:space:]]*[0-9]") |
    stringr::str_detect(lower_x, "\\bto\\b|×| x | by ")

  parsed <- rep(NA_real_, length(x))
  keep <- !is.na(x) & token_n == 1 & !ambiguous_value
  if (any(keep)) {
    parsed[keep] <- suppressWarnings(as.numeric(vapply(token_list[keep], function(val) val[[1]], character(1))))
  }

  parsed
}

# Prepare trait values for plotting by keeping only clean, unit-consistent numeric
# measurements for continuous graphics while still summarizing categorical traits.
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
      unit_std = if (!is.null(unit_col)) as.character(.data[[unit_col]]) else "unspecified"
    ) %>%
    filter(!is.na(trait_name_std), trait_name_std != "", !is.na(trait_value_std), trait_value_std != "") %>%
    mutate(
      unit_std = ifelse(is.na(unit_std) | unit_std == "", "unspecified", unit_std),
      trait_value_num = extract_single_numeric_value(trait_value_std),
      n_numeric_tokens = lengths(stringr::str_extract_all(trait_value_std, "-?[0-9]*\\.?[0-9]+(?:[eE][+-]?[0-9]+)?")),
      parse_status = case_when(
        !is.na(trait_value_num) ~ "single_numeric",
        n_numeric_tokens > 1 ~ "complex_value_excluded",
        TRUE ~ "non_numeric"
      )
    )

  if (nrow(plot_df) == 0) {
    return(NULL)
  }

  summary_tbl <- plot_df %>%
    group_by(trait_name_std, unit_std) %>%
    group_modify(~ {
      df <- .x
      n_numeric_used <- sum(!is.na(df$trait_value_num))
      n_non_numeric_excluded <- sum(is.na(df$trait_value_num))
      num_vals <- df$trait_value_num[!is.na(df$trait_value_num)]
      is_continuous <- n_numeric_used >= max(3, ceiling(0.6 * nrow(df))) && length(unique(num_vals)) > 1

      if (is_continuous) {
        tibble(
          value_type = "continuous",
          n_records = nrow(df),
          n_numeric_used = n_numeric_used,
          n_non_numeric_excluded = n_non_numeric_excluded,
          mean_value = round(mean(num_vals), 4),
          min_value = round(min(num_vals), 4),
          max_value = round(max(num_vals), 4),
          modal_value = NA_character_,
          summary_note = paste0(
            "mean=", round(mean(num_vals), 3),
            "; range=", round(min(num_vals), 3), " to ", round(max(num_vals), 3),
            "; numeric used=", n_numeric_used, "/", nrow(df)
          )
        )
      } else {
        val_tbl <- sort(table(df$trait_value_std), decreasing = TRUE)
        mode_val <- names(val_tbl)[1]
        tibble(
          value_type = "categorical",
          n_records = nrow(df),
          n_numeric_used = n_numeric_used,
          n_non_numeric_excluded = n_non_numeric_excluded,
          mean_value = NA_real_,
          min_value = NA_real_,
          max_value = NA_real_,
          modal_value = mode_val,
          summary_note = paste0("mode=", mode_val, " (n=", unname(val_tbl[1]), "); numeric used=", n_numeric_used, "/", nrow(df))
        )
      }
    }) %>%
    ungroup() %>%
    arrange(desc(n_records), trait_name_std, unit_std)

  list(data = plot_df, summary = summary_tbl)
}

describe_sampling_mode <- function(sample_method) {
  switch(
    sample_method,
    datasource = "balanced sample stratified by datasource",
    observation_type = "balanced sample stratified by BIEN observation type",
    observation_category = "balanced sample stratified by broader observation category",
    head = "first returned BIEN rows",
    "randomized BIEN sample of matching occurrence rows (to reduce source-order bias)"
  )
}

is_bien_connection_error <- function(messages) {
  if (length(messages) == 0 || all(is.na(messages))) {
    return(FALSE)
  }

  any(grepl(
    "could not connect|remaining connection slots|error connecting to the BIEN database",
    messages,
    ignore.case = TRUE
  ))
}

sample_occurrence_rows <- function(df, target_n, sample_method = "random") {
  valid_methods <- c("random", "head", "datasource", "observation_type", "observation_category")
  sample_method <- if (!is.null(sample_method) && sample_method %in% valid_methods) sample_method else "random"

  if (!is.data.frame(df) || nrow(df) == 0 || nrow(df) <= target_n) {
    return(df)
  }

  if (sample_method == "head") {
    return(df %>% slice_head(n = target_n))
  }

  if (sample_method == "random") {
    return(df %>% slice_sample(n = target_n))
  }

  if (!"observation_category" %in% names(df)) {
    df <- categorize_observation_records(df)
  }

  stratify_col <- switch(
    sample_method,
    datasource = find_first_col(df, c("datasource", "data_source", "collection", "source")),
    observation_type = find_first_col(df, c("observation_type", "observation.type")),
    observation_category = find_first_col(df, c("observation_category")),
    NULL
  )

  if (is.null(stratify_col) || !stratify_col %in% names(df)) {
    return(df %>% slice_sample(n = target_n))
  }

  group_values <- trimws(as.character(df[[stratify_col]]))
  group_values[is.na(group_values) | group_values == ""] <- "unknown"
  group_index <- split(seq_len(nrow(df)), group_values)

  if (length(group_index) <= 1) {
    return(df %>% slice_sample(n = target_n))
  }

  group_index <- group_index[order(vapply(group_index, length, integer(1)), decreasing = TRUE)]
  base_quota <- max(1L, floor(target_n / length(group_index)))

  selected <- unlist(lapply(group_index, function(idx) {
    draw_n <- min(length(idx), base_quota)
    idx[sample.int(length(idx), size = draw_n, replace = FALSE)]
  }), use.names = FALSE)
  selected <- unique(selected)

  if (length(selected) < target_n) {
    leftovers <- lapply(group_index, function(idx) setdiff(idx, selected))

    while (length(selected) < target_n && any(lengths(leftovers) > 0)) {
      for (i in seq_along(leftovers)) {
        if (length(selected) >= target_n) {
          break
        }
        if (length(leftovers[[i]]) == 0) {
          next
        }
        add_pos <- sample.int(length(leftovers[[i]]), size = 1)
        add_idx <- leftovers[[i]][add_pos]
        selected <- c(selected, add_idx)
        leftovers[[i]] <- setdiff(leftovers[[i]], add_idx)
      }
    }
  }

  selected <- selected[seq_len(min(length(selected), target_n))]
  df[selected, , drop = FALSE]
}

# Standardize, QA, de-duplicate, and optionally thin occurrence records before mapping.
prepare_occurrences <- function(occ, map_point_cap = 800, sample_method = "random") {
  valid_methods <- c("random", "head", "datasource", "observation_type", "observation_category")
  sample_method <- if (!is.null(sample_method) && sample_method %in% valid_methods) sample_method else "random"

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
    occ <- sample_occurrence_rows(occ, target_n = map_point_cap, sample_method = sample_method)
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

# Build a transparent BIEN-returned name summary for the app. This is a provisional
# reconciliation aid for users, not a formal synonym or accepted-name adjudication.
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
    match_confidence = ifelse(is.na(matched_species), "low", "provisional"),
    decision_note = paste(
      c(
        "BIEN-returned name only; not a formal synonym or accepted-name resolution.",
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
      tags$div(
        style = "font-size:0.92em;color:#555;margin:6px 0 10px 0;",
        "Occurrence records load first for speed. Optional BIEN total counts can be loaded manually from the Summary Statistics tab, while traits and range layers are fetched only when those tabs are opened."
      ),
      tags$hr(),
      tags$div(
        style = "background:#fff3cd;border:1px solid #ffe69c;color:#664d03;padding:8px 10px;border-radius:6px;margin:0 0 10px 0;font-size:0.92em;",
        tags$strong("Important: "),
        "If you change any of the filters below, click ", tags$code("Query BIEN"), " again to refresh the occurrence records and summaries."
      ),
      checkboxInput("use_introduced_filter", "Use BIEN native vs introduced status (turn off to show records regardless of introduced status)", value = TRUE),
      conditionalPanel(
        condition = "input.use_introduced_filter == true",
        checkboxInput("natives_only", "Keep native records only and hide introduced records", value = TRUE)
      ),
      checkboxInput("use_cultivated_filter", "Use BIEN cultivated vs wild status (turn off to show both cultivated and non-cultivated records)", value = TRUE),
      conditionalPanel(
        condition = "input.use_cultivated_filter == true",
        checkboxInput("include_cultivated", "Include cultivated records (turn off to hide them)", value = FALSE)
      ),
      checkboxInput("only_geovalid", "Keep only BIEN geovalid coordinates (hide flagged / non-geovalid points)", value = TRUE),
      uiOutput("filter_selection_summary"),
      numericInput("occurrence_limit", "Occurrence records to keep in app sample", value = 1000, min = 200, max = 50000, step = 200),
      checkboxInput("randomize_occurrence_sample", "Allow randomized or balanced subsampling for the displayed app sample (turn off to keep the returned BIEN sample as-is)", value = TRUE),
      selectInput("map_sampling_method", "If too many occurrence records are available, balance the display using", choices = c("Balanced by datasource" = "datasource", "Balanced by observation type" = "observation_type", "Balanced by broader observation category" = "observation_category", "Random sample" = "random", "First returned" = "head"), selected = "datasource"),
      selectInput("map_color_by", "Color map points by", choices = c("Observation category" = "category", "Raw BIEN observation_type" = "type"), selected = "category"),
      numericInput("trait_limit", "Max trait records (sample)", value = 1000, min = 100, max = 50000, step = 100),
      checkboxInput("include_range_query", "Load BIEN range layers when the Range tab is opened (slower)", value = FALSE),
      numericInput("query_timeout", "Per-step timeout (seconds)", value = 30, min = 15, max = 300, step = 15),
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
        id = "main_tabs",
        tabPanel(
          "Occurrence Map",
          br(),
          uiOutput("overview_notice"),
          leafletOutput("occurrence_map", height = 550)
        ),
        tabPanel(
          "Summary Statistics",
          br(),
          tags$p(
            style = "color:#555;max-width:900px;",
            "Returned-record summaries appear below immediately. Optional BIEN count-only totals and source fractions can take longer, so they are loaded only if you request them."
          ),
          actionButton("load_summary_counts", "Load BIEN total counts and source mix (slower)", class = "btn-default btn-sm"),
          br(), br(),
          htmlOutput("query_summary")
        ),
        tabPanel("Observation Table", br(), DTOutput("occurrence_table")),
        tabPanel("Observation Sources", br(), DTOutput("observation_source_table")),
        tabPanel("Traits", br(), DTOutput("trait_table")),
        tabPanel("Trait Summary", br(), DTOutput("trait_summary_table")),
        tabPanel(
          "Trait Graphics",
          br(),
          tags$p(
            style = "color:#555;max-width:900px;",
            "Continuous traits only. Histograms are built from parsed single-number values and are kept separate by unit; categorical or mixed-format BIEN values stay in the tables below."
          ),
          plotOutput("trait_plot", height = 800),
          br(),
          DTOutput("trait_visual_table")
        ),
        tabPanel("Range", br(), verbatimTextOutput("range_text"), leafletOutput("range_map", height = 500), br(), DTOutput("range_table")),
        tabPanel("Reconciliation", br(), DTOutput("reconciliation_table"), br(), verbatimTextOutput("error_log"))
      ),
      width = 9
    )
  )
)

# Server logic: query BIEN, prepare outputs, and render maps/tables/plots for the current species.
server <- function(input, output, session) {
  # Cache repeated species/filter requests within the current app session so reruns
  # of the same query return much faster without re-contacting BIEN.
  query_cache <- new.env(parent = emptyenv())
  summary_cache <- new.env(parent = emptyenv())
  trait_cache <- new.env(parent = emptyenv())
  range_cache <- new.env(parent = emptyenv())

  get_cached_result <- function(cache_env, cache_key) {
    if (is.null(cache_key) || !exists(cache_key, envir = cache_env, inherits = FALSE)) {
      return(NULL)
    }
    get(cache_key, envir = cache_env, inherits = FALSE)
  }

  bien_results <- eventReactive(input$run_query, {
    req(nchar(str_trim(input$species)) > 0)

    species_name <- str_squish(input$species)
    include_range_query <- if (is.null(input$include_range_query)) FALSE else isTRUE(input$include_range_query)
    timeout_sec <- max(15, as.numeric(input$query_timeout))
    occ_limit <- max(200, as.numeric(input$occurrence_limit))
    trait_limit <- max(100, as.numeric(input$trait_limit))
    sample_random <- if (is.null(input$randomize_occurrence_sample)) TRUE else isTRUE(input$randomize_occurrence_sample)
    map_sampling_method <- if (is.null(input$map_sampling_method)) "datasource" else input$map_sampling_method
    display_sampling_method <- if (sample_random) map_sampling_method else "head"
    occ_page_size <- min(1000, max(occ_limit, 500))
    trait_page_size <- min(500, trait_limit)
    occ_fetch_limit <- min(if (identical(display_sampling_method, "head")) occ_limit else max(occ_limit * 2, 1000), 2000)
    trait_fetch_limit <- min(trait_limit, 1000)
    range_dir <- file.path(tempdir(), "bien_ranges_cache", gsub("\\s+", "_", species_name))
    dir.create(range_dir, recursive = TRUE, showWarnings = FALSE)

    cache_key <- paste(
      species_name,
      include_range_query,
      timeout_sec,
      occ_limit,
      trait_limit,
      sample_random,
      map_sampling_method,
      if (is.null(input$use_cultivated_filter)) TRUE else isTRUE(input$use_cultivated_filter),
      if (is.null(input$include_cultivated)) FALSE else isTRUE(input$include_cultivated),
      if (is.null(input$use_introduced_filter)) TRUE else isTRUE(input$use_introduced_filter),
      if (is.null(input$natives_only)) TRUE else isTRUE(input$natives_only),
      if (is.null(input$only_geovalid)) TRUE else isTRUE(input$only_geovalid),
      sep = "||"
    )

    if (exists(cache_key, envir = query_cache, inherits = FALSE)) {
      cached_res <- get(cache_key, envir = query_cache, inherits = FALSE)
      cached_res$cache_hit <- TRUE
      cached_res$query_elapsed_sec <- 0
      return(cached_res)
    }

    query_started <- Sys.time()

    withProgress(message = paste("Querying BIEN for", species_name), detail = "Connecting to BIEN...", value = 0, {
      incProgress(0.15, detail = "Occurrences: retrieving records from BIEN (large or widespread species can take longer)")
      occ_bundle <- query_occurrence_with_fallback(species_name, input, occ_fetch_limit, occ_page_size, timeout_sec)
      occ <- occ_bundle$data
      occ_strategy <- occ_bundle$strategy
      occ_limit_used <- occ_bundle$limit_used
      occ_error <- if (inherits(occ, "error")) conditionMessage(occ) else NULL
      occ_returned_n <- if (is.data.frame(occ)) nrow(occ) else 0

      incProgress(0.4, detail = "Preparing the first occurrence view")

      if (is.data.frame(occ)) {
        occ <- categorize_observation_records(occ)
        if (nrow(occ) > occ_limit) {
          occ <- sample_occurrence_rows(occ, target_n = occ_limit, sample_method = display_sampling_method)
        }
      }

      incProgress(0.85, detail = "Preparing map and QA summary")
      occ_prepared <- if (is.data.frame(occ)) prepare_occurrences(occ, map_point_cap = 800, sample_method = display_sampling_method) else list(data = NULL, lat_col = NULL, lon_col = NULL, qa = list(total = 0, coord_valid = 0, kept = 0, removed = 0, removed_invalid = 0, duplicates_removed = 0), map_cap_applied = FALSE, map_cap = 800, original_kept = 0, sample_method = display_sampling_method)
      family_name <- extract_primary_value(occ, c("scrubbed_family", "family", "verbatim_family"))

      query_errors <- c(occ_bundle$notes, occ_error)
      query_errors <- query_errors[!is.na(query_errors)]
      reconciliation_tbl <- build_reconciliation_table(species_name, occ, NULL, query_errors, NULL)

      incProgress(1, detail = "Done")

      result <- list(
        species = species_name,
        family_name = family_name,
        occurrences = occ,
        occurrences_prepared = occ_prepared,
        occurrences_returned = occ_returned_n,
        occ_total_available = NA_real_,
        occ_total_note = "Click 'Load BIEN total counts and source mix (slower)' to fetch optional BIEN totals for this species.", 
        occ_source_mix = NULL,
        occurrence_sample_mode = display_sampling_method,
        traits = NULL,
        ranges = NULL,
        range_sf = NULL,
        range_dir = range_dir,
        include_range_query = include_range_query,
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
        query_cache_key = cache_key,
        query_elapsed_sec = round(as.numeric(difftime(Sys.time(), query_started, units = "secs")), 1),
        cache_hit = FALSE,
        query_errors = query_errors,
        reconciliation = reconciliation_tbl
      )

      assign(cache_key, result, envir = query_cache)
      result
    })
  }, ignoreInit = TRUE)

  # Lazy-load BIEN trait data only when the user opens one of the trait-focused tabs.
  trait_results <- reactive({
    res <- bien_results()
    req(res)
    req(!is.null(input$main_tabs), input$main_tabs %in% c("Traits", "Trait Summary", "Trait Graphics"))

    cache_key <- res$query_cache_key
    cached <- get_cached_result(trait_cache, cache_key)
    if (!is.null(cached)) {
      return(cached)
    }

    withProgress(message = paste("Querying BIEN traits for", res$species), detail = "Traits: checking BIEN trait records", value = 0, {
      incProgress(0.35, detail = "Fetching trait records from BIEN")
      traits <- safe_bien_call(
        BIEN_trait_species(
          species = res$species,
          all.taxonomy = TRUE,
          source.citation = TRUE,
          limit = res$trait_fetch_limit,
          record_limit = min(500, res$trait_limit),
          fetch.query = FALSE
        ),
        timeout_sec = min(res$timeout_sec, 20)
      )
      traits_error <- if (inherits(traits, "error")) conditionMessage(traits) else NULL
      if (is.data.frame(traits)) {
        names(traits) <- make.unique(names(traits))
      }

      out <- list(
        data = traits,
        error = traits_error,
        loaded = TRUE
      )
      assign(cache_key, out, envir = trait_cache)
      out
    })
  })

  # Lazy-load optional BIEN range artifacts only when the Range tab is opened.
  range_results <- reactive({
    res <- bien_results()
    req(res)
    req(!is.null(input$main_tabs), identical(input$main_tabs, "Range"))

    cache_key <- res$query_cache_key
    cached <- get_cached_result(range_cache, cache_key)
    if (!is.null(cached)) {
      return(cached)
    }

    if (!isTRUE(res$include_range_query)) {
      out <- list(
        data = data.frame(note = "Range query skipped by current setting. Turn on 'Load BIEN range layers when the Range tab is opened (slower)' and rerun the species query to fetch it."),
        error = NULL,
        range_sf = NULL,
        loaded = FALSE,
        skipped = TRUE
      )
      assign(cache_key, out, envir = range_cache)
      return(out)
    }

    withProgress(message = paste("Querying BIEN range for", res$species), detail = "Range layers: optional BIEN range lookup in progress (can be slower)", value = 0, {
      incProgress(0.35, detail = "Fetching BIEN range artifacts")
      ranges <- safe_bien_call(
        BIEN_ranges_species(
          species = res$species,
          directory = res$range_dir,
          matched = TRUE,
          match_names_only = FALSE,
          include.gid = TRUE,
          limit = 25,
          record_limit = 25,
          fetch.query = FALSE
        ),
        timeout_sec = min(res$timeout_sec, 20)
      )
      range_error <- if (inherits(ranges, "error")) conditionMessage(ranges) else NULL
      range_sf <- read_downloaded_range_sf(res$range_dir, res$species)

      out <- list(
        data = ranges,
        error = range_error,
        range_sf = range_sf,
        loaded = TRUE,
        skipped = FALSE
      )
      assign(cache_key, out, envir = range_cache)
      out
    })
  })

  # Keep the potentially slower BIEN total-count and source-mix queries manual so
  # opening Summary Statistics does not block the whole app.
  summary_results <- eventReactive(input$load_summary_counts, {
    res <- bien_results()
    req(res)
    req(!is.null(input$main_tabs), identical(input$main_tabs, "Summary Statistics"))

    cache_key <- paste0(res$query_cache_key, "||summary")
    cached <- get_cached_result(summary_cache, cache_key)
    if (!is.null(cached)) {
      return(cached)
    }

    withProgress(message = paste("Querying BIEN summary counts for", res$species), detail = "Summary statistics: estimating total matches and source mix", value = 0, {
      use_cultivated_filter <- if (is.null(input$use_cultivated_filter)) TRUE else isTRUE(input$use_cultivated_filter)
      use_introduced_filter <- if (is.null(input$use_introduced_filter)) TRUE else isTRUE(input$use_introduced_filter)
      count_include_cultivated <- if (use_cultivated_filter) isTRUE(input$include_cultivated) else TRUE
      count_natives_only <- if (identical(res$occ_strategy, "fallback_relaxed_native") || identical(res$occ_strategy, "fallback_relaxed_geo")) {
        FALSE
      } else if (use_introduced_filter) {
        if (is.null(input$natives_only)) TRUE else isTRUE(input$natives_only)
      } else {
        FALSE
      }
      count_only_geovalid <- if (identical(res$occ_strategy, "fallback_relaxed_geo")) {
        FALSE
      } else {
        if (is.null(input$only_geovalid)) TRUE else isTRUE(input$only_geovalid)
      }

      incProgress(0.4, detail = "Counting total BIEN matches")
      occ_total_info <- count_occurrence_records(
        species_name = res$species,
        cultivated = count_include_cultivated,
        natives_only = count_natives_only,
        only_geovalid = count_only_geovalid,
        timeout_sec = res$timeout_sec
      )

      incProgress(0.8, detail = "Estimating BIEN source mix")
      occ_source_mix <- count_occurrence_source_mix(
        species_name = res$species,
        cultivated = count_include_cultivated,
        natives_only = count_natives_only,
        only_geovalid = count_only_geovalid,
        timeout_sec = res$timeout_sec
      )

      out <- list(
        total = occ_total_info$total,
        note = occ_total_info$note,
        source_mix = occ_source_mix,
        loaded = TRUE
      )
      assign(cache_key, out, envir = summary_cache)
      out
    })
  }, ignoreInit = TRUE)

  output$query_summary <- renderUI({
    res <- bien_results()
    summary_event <- summary_results()
    summary_cache_key <- paste0(res$query_cache_key, "||summary")
    summary_bundle <- get_cached_result(summary_cache, summary_cache_key)
    if (is.null(summary_bundle) && !is.null(summary_event)) {
      summary_bundle <- summary_event
    }
    if (is.null(summary_bundle)) {
      summary_bundle <- list(
        total = NA_real_,
        note = "Click 'Load BIEN total counts and source mix (slower)' to fetch optional BIEN totals for this species.",
        source_mix = NULL,
        loaded = FALSE
      )
    }

    occ_n <- if (is.data.frame(res$occurrences)) nrow(res$occurrences) else 0
    occ_returned_n <- if (!is.null(res$occurrences_returned)) res$occurrences_returned else occ_n
    occ_total_available <- summary_bundle$total
    occ_total_note <- summary_bundle$note
    occ_total_txt <- if (!is.null(occ_total_available) && !is.na(occ_total_available)) {
      format(occ_total_available, big.mark = ",", scientific = FALSE, trim = TRUE)
    } else if (!is.null(occ_total_note) && nzchar(occ_total_note)) {
      paste0("Not available (", occ_total_note, ")")
    } else {
      "Not available"
    }
    cached_traits <- get_cached_result(trait_cache, res$query_cache_key)
    cached_range <- get_cached_result(range_cache, res$query_cache_key)
    cached_traits_df <- if (!is.null(cached_traits) && is.data.frame(cached_traits$data)) cached_traits$data else NULL
    cached_range_sf <- if (!is.null(cached_range)) cached_range$range_sf else NULL
    source_mix_line <- format_occurrence_source_mix(summary_bundle$source_mix, occ_total_available)
    mappable_n <- if (is.data.frame(res$occurrences_prepared$data)) nrow(res$occurrences_prepared$data) else 0
    trait_n <- if (is.data.frame(cached_traits_df)) {
      nrow(cached_traits_df)
    } else if (!is.null(cached_traits) && !is.null(cached_traits$error) && nzchar(cached_traits$error)) {
      paste0("Not available (", cached_traits$error, ")")
    } else {
      "Not loaded yet — open a Traits tab to fetch"
    }
    family_name <- if (!is.null(res$family_name)) res$family_name else "Not available"
    if (identical(family_name, "Not available") && is.data.frame(cached_traits_df)) {
      family_name <- extract_primary_value(cached_traits_df, c("scrubbed_family", "family", "verbatim_family"))
    }
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
    range_status <- if (is.null(cached_range)) {
      if (isTRUE(res$include_range_query)) {
        "Not loaded yet — open the Range tab to fetch the optional BIEN range layer"
      } else {
        "Skipped by current setting — turn on the optional range lookup and rerun to fetch"
      }
    } else if (isTRUE(cached_range$skipped)) {
      as.character(cached_range$data$note[[1]])
    } else if (inherits(cached_range$data, "error")) {
      "Range query returned an error"
    } else if (inherits(cached_range_sf, "sf") && nrow(cached_range_sf) > 0) {
      paste("Range polygon loaded from", res$range_dir)
    } else {
      paste("Range result type:", paste(class(cached_range$data), collapse = ", "))
    }
    query_elapsed_txt <- if (!is.null(res$query_elapsed_sec) && !is.na(res$query_elapsed_sec)) {
      paste0(res$query_elapsed_sec, " sec")
    } else {
      "Not available"
    }
    query_source_txt <- if (isTRUE(res$cache_hit)) {
      "cached previous result for this species and filter combination"
    } else {
      "fresh BIEN query"
    }
    connection_issue <- is_bien_connection_error(res$query_errors)

    map_status <- if (connection_issue) {
      "BIEN connection failed during this query, so no occurrence records could be retrieved"
    } else if (mappable_n > 0 && isTRUE(res$occurrences_prepared$map_cap_applied)) {
      paste("Showing", mappable_n, "sampled occurrence point(s) out of", res$occurrences_prepared$original_kept, "mappable records")
    } else if (mappable_n > 0) {
      paste("Showing", mappable_n, "occurrence point(s)")
    } else if (occ_n > 0 && inherits(cached_range_sf, "sf") && nrow(cached_range_sf) > 0) {
      "No usable BIEN occurrence coordinates were returned; showing BIEN range polygon instead"
    } else if (occ_n > 0 && isTRUE(res$include_range_query)) {
      "Occurrence rows were returned, but no usable coordinates were available to map. Open the Range tab to load BIEN's optional range layer."
    } else if (occ_n > 0) {
      "Occurrence rows were returned, but no usable coordinates were available to map"
    } else {
      "No occurrence rows were returned"
    }

    HTML(paste0(
      "<strong>Species:</strong> ", res$species,
      "<br><strong>Family:</strong> ", family_name,
      "<br><strong>Total BIEN occurrence records matching current strategy (count only; not downloaded):</strong> ", occ_total_txt,
      "<br><strong>Fraction of total matching BIEN records by source class (derived from BIEN provenance):</strong> ", source_mix_line,
      "<br><strong>Observation records returned by BIEN:</strong> ", occ_returned_n,
      "<br><strong>Observation records kept in app sample:</strong> ", occ_n,
      "<br><strong>Observation sample mode:</strong> ", describe_sampling_mode(res$occurrence_sample_mode),
      "<br><strong>Query source:</strong> ", query_source_txt,
      if (connection_issue) {
        "<br><strong>BIEN server status:</strong> The public BIEN database is temporarily at capacity or refusing new connections. Please rerun the query in a minute or two."
      } else {
        ""
      },
      "<br><strong>Query elapsed time:</strong> ", query_elapsed_txt,
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
    cached_range <- get_cached_result(range_cache, res$query_cache_key)
    has_range <- !is.null(cached_range) && inherits(cached_range$range_sf, "sf") && nrow(cached_range$range_sf) > 0

    if (is_bien_connection_error(res$query_errors)) {
      return(tags$div(
        style = "background:#f8d7da;border:1px solid #f1aeb5;color:#842029;padding:10px 12px;border-radius:6px;margin:8px 0;",
        tags$strong("BIEN connection note: "),
        "The public BIEN database is temporarily at capacity or refusing new connections, so this query could not retrieve occurrence records right now. Please try `Query BIEN` again shortly."
      ))
    }

    if (occ_n > 0 && mappable_n == 0 && has_range) {
      return(tags$div(
        style = "background:#fff3cd;border:1px solid #ffe69c;color:#664d03;padding:10px 12px;border-radius:6px;margin:8px 0;",
        tags$strong("Overview note: "),
        "BIEN returned occurrence rows for this species, but not usable latitude/longitude coordinates in the current response. The map below is showing the BIEN range polygon instead."
      ))
    }

    if (occ_n > 0 && mappable_n == 0 && isTRUE(res$include_range_query)) {
      return(tags$div(
        style = "background:#cff4fc;border:1px solid #9eeaf9;color:#055160;padding:10px 12px;border-radius:6px;margin:8px 0;",
        tags$strong("Overview note: "),
        "Occurrence rows were returned without usable coordinates. Open the Range tab to load BIEN's optional range layer for this species."
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
    cached_range <- get_cached_result(range_cache, res$query_cache_key)
    cached_range_sf <- if (!is.null(cached_range)) cached_range$range_sf else NULL

    map <- leaflet() %>% addProviderTiles(providers$CartoDB.Positron)

    if (is.null(occ_info$data) || nrow(occ_info$data) == 0 || is.null(occ_info$lat_col) || is.null(occ_info$lon_col)) {
      if (inherits(cached_range_sf, "sf") && nrow(cached_range_sf) > 0) {
        sf_obj <- suppressWarnings(st_make_valid(cached_range_sf))
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

        map <- map %>% addLegend(
          position = "topright",
          colors = "#1B9E77",
          labels = "BIEN range polygon",
          title = "Overview map",
          opacity = 0.9
        )

        bbox <- st_bbox(sf_obj)
        return(map %>% fitBounds(bbox[["xmin"]], bbox[["ymin"]], bbox[["xmax"]], bbox[["ymax"]]))
      }
      return(map %>% setView(lng = 0, lat = 20, zoom = 2))
    }

    df <- occ_info$data
    lat_col <- occ_info$lat_col
    lon_col <- occ_info$lon_col

    map_scale <- if (is.null(input$map_scale) || !nzchar(input$map_scale)) "auto" else input$map_scale
    color_by <- if (is.null(input$map_color_by) || !nzchar(input$map_color_by)) "category" else input$map_color_by
    obs_type_col <- find_first_col(df, c("observation_type", "observation.type"))

    if (identical(color_by, "category") && "observation_category" %in% names(df)) {
      color_vals <- as.character(df$observation_category)
      legend_title <- "Observation category"
    } else {
      color_vals <- if (!is.null(obs_type_col)) as.character(df[[obs_type_col]]) else rep("unknown", nrow(df))
      legend_title <- "Observation type"
    }

    color_vals[is.na(color_vals) | color_vals == ""] <- "unknown"
    legend_vals <- sort(unique(color_vals))
    pal <- colorFactor(
      palette = c("#1b9e77", "#d95f02", "#7570b3", "#e7298a", "#66a61e", "#e6ab02", "#a6761d", "#666666"),
      domain = legend_vals
    )

    map <- map %>% addCircleMarkers(
      lng = df[[lon_col]],
      lat = df[[lat_col]],
      radius = 4,
      stroke = FALSE,
      fillColor = pal(color_vals),
      fillOpacity = 0.8,
      popup = make_popup_text(df),
      options = pathOptions(pane = "markerPane")
    ) %>%
      addLegend(
        position = "topright",
        colors = unname(pal(legend_vals)),
        labels = legend_vals,
        title = legend_title,
        opacity = 0.9
      )

    if (map_scale == "world") {
      map %>% setView(lng = 0, lat = 20, zoom = 2)
    } else if (map_scale == "regional") {
      map %>% setView(
        lng = mean(df[[lon_col]], na.rm = TRUE),
        lat = mean(df[[lat_col]], na.rm = TRUE),
        zoom = 4
      )
    } else if (map_scale == "local") {
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

  # Summarize the currently selected biological filters in plain language so users
  # can see immediately what kind of occurrence evidence is being requested.
  output$filter_selection_summary <- renderUI({
    default_mode <- isTRUE(input$use_introduced_filter) && isTRUE(input$natives_only) &&
      isTRUE(input$use_cultivated_filter) && !isTRUE(input$include_cultivated) &&
      isTRUE(input$only_geovalid)

    intro_txt <- if (isTRUE(input$use_introduced_filter) && isTRUE(input$natives_only)) {
      "BIEN-classified native / not introduced records only"
    } else if (isTRUE(input$use_introduced_filter)) {
      "records shown with BIEN native / introduced status available"
    } else {
      "records shown regardless of BIEN native / introduced status"
    }

    cultivated_txt <- if (isTRUE(input$use_cultivated_filter) && !isTRUE(input$include_cultivated)) {
      "cultivated records hidden"
    } else if (isTRUE(input$use_cultivated_filter) && isTRUE(input$include_cultivated)) {
      "cultivated and non-cultivated records both shown"
    } else {
      "records shown regardless of BIEN cultivated status"
    }

    geo_txt <- if (isTRUE(input$only_geovalid)) {
      "only BIEN geovalid coordinates shown"
    } else {
      "both geovalid and flagged / non-geovalid coordinates shown"
    }

    tags$div(
      style = if (default_mode) {
        "background:#e8f5e9;border:1px solid #b7dfb9;color:#1b5e20;padding:8px 10px;border-radius:6px;margin:8px 0 10px 0;font-size:0.92em;"
      } else {
        "background:#f8f9fa;border:1px solid #d0d7de;color:#333;padding:8px 10px;border-radius:6px;margin:8px 0 10px 0;font-size:0.92em;"
      },
      tags$strong(if (default_mode) "Default (conservative ecological view): " else "Current requested filter view: "),
      paste0(
        "Showing ", intro_txt, "; ", cultivated_txt, "; and ", geo_txt, "."
      ),
      tags$br(),
      tags$span(
        style = "color:#555;",
        if (default_mode) {
          "This is the app's default starting view for biodiversity screening. If BIEN finds no records under these strict settings, the Summary Statistics tab will report whether the app had to broaden the actual query strategy."
        } else {
          "The Summary Statistics tab reports the actual BIEN query strategy used, including any fallback broadening if strict filters returned no records."
        }
      )
    )
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
    trait_bundle <- trait_results()
    traits_df <- trait_bundle$data
    if (inherits(traits_df, "error")) {
      return(datatable(data.frame(message = paste("Trait query error:", conditionMessage(traits_df))), options = list(dom = "t"), rownames = FALSE))
    }
    if (!is.data.frame(traits_df)) {
      return(datatable(data.frame(message = "No trait table returned."), options = list(dom = "t"), rownames = FALSE))
    }
    datatable(traits_df, filter = "top", options = list(pageLength = 10, scrollX = TRUE))
  })

  output$trait_summary_table <- renderDT({
    trait_bundle <- trait_results()
    traits_df <- trait_bundle$data
    if (!is.data.frame(traits_df) || nrow(traits_df) == 0) {
      return(datatable(data.frame(message = "No trait records available for summary."), options = list(dom = "t"), rownames = FALSE))
    }

    trait_name_col <- find_first_col(traits_df, c("trait_name", "trait"))
    trait_value_col <- find_first_col(traits_df, c("trait_value", "value"))
    unit_col <- find_first_col(traits_df, c("unit", "units"))

    if (is.null(trait_name_col) || is.null(trait_value_col)) {
      return(datatable(data.frame(message = "Trait schema not recognized."), options = list(dom = "t"), rownames = FALSE))
    }

    summary_tbl <- traits_df %>%
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
    trait_bundle <- trait_results()
    trait_vis <- prepare_trait_visual_data(trait_bundle$data)

    if (is.null(trait_vis) || !is.data.frame(trait_vis$summary) || nrow(trait_vis$summary) == 0) {
      return(datatable(data.frame(message = "No trait values available for graphical summary."), options = list(dom = "t"), rownames = FALSE))
    }

    datatable(trait_vis$summary, options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
  })

  output$trait_plot <- renderPlot({
    trait_bundle <- trait_results()
    trait_vis <- prepare_trait_visual_data(trait_bundle$data)

    if (is.null(trait_vis) || !is.data.frame(trait_vis$summary) || nrow(trait_vis$summary) == 0) {
      plot.new()
      text(0.5, 0.5, "No plottable trait values returned for this species.", cex = 1.1)
      return(invisible(NULL))
    }

    # Use the same trait+unit groupings in the plots that were used to build the
    # summary table, so the reported ranges and the histograms stay in sync.
    summary_tbl <- trait_vis$summary %>%
      filter(value_type == "continuous") %>%
      slice_head(n = 6)

    if (nrow(summary_tbl) == 0) {
      plot.new()
      text(
        0.5, 0.55,
        "No continuous trait variables are available to plot for this species.",
        cex = 1.05
      )
      text(
        0.5, 0.42,
        "Categorical traits such as flower color are summarized in the table below.",
        cex = 0.95
      )
      return(invisible(NULL))
    }

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
      unit_suffix <- if (!is.na(unit_txt) && nzchar(unit_txt) && unit_txt != "unspecified") paste0(" (", unit_txt, ")") else ""
      df <- plot_df %>%
        filter(trait_name_std == trait_name, unit_std == unit_txt)
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
    }
  })

  output$range_text <- renderText({
    range_bundle <- range_results()
    if (isTRUE(range_bundle$skipped)) {
      return(as.character(range_bundle$data$note[[1]]))
    }

    range_info <- summarize_range_object(range_bundle$data)

    if (range_info$kind == "error") {
      return(paste("Range query error:", range_info$text))
    }
    if (inherits(range_bundle$range_sf, "sf") && nrow(range_bundle$range_sf) > 0) {
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
    range_bundle <- range_results()
    map <- leaflet() %>% addProviderTiles(providers$CartoDB.Positron)

    if (!(inherits(range_bundle$range_sf, "sf") && nrow(range_bundle$range_sf) > 0)) {
      return(map %>% setView(lng = 0, lat = 20, zoom = 2))
    }

    sf_obj <- suppressWarnings(st_make_valid(range_bundle$range_sf))
    geom_type <- unique(as.character(st_geometry_type(sf_obj)))

    if (any(geom_type %in% c("POLYGON", "MULTIPOLYGON"))) {
      map <- map %>% addPolygons(
        data = sf_obj,
        fillOpacity = 0.25,
        weight = 2,
        color = "#2C7BB6",
        popup = bien_results()$species
      )
    } else {
      map <- map %>% addCircleMarkers(data = sf_obj, radius = 4, stroke = FALSE, fillOpacity = 0.7)
    }

    bbox <- st_bbox(sf_obj)
    map %>% fitBounds(bbox[["xmin"]], bbox[["ymin"]], bbox[["xmax"]], bbox[["ymax"]])
  })

  output$range_table <- renderDT({
    range_bundle <- range_results()
    if (isTRUE(range_bundle$skipped)) {
      return(datatable(as.data.frame(range_bundle$data), options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE))
    }
    if (inherits(range_bundle$data, "error")) {
      return(datatable(data.frame(message = paste("Range query error:", conditionMessage(range_bundle$data))), options = list(dom = "t"), rownames = FALSE))
    }
    range_info <- summarize_range_object(range_bundle$data)

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
    all_errors <- res$query_errors

    cached_traits <- get_cached_result(trait_cache, res$query_cache_key)
    cached_range <- get_cached_result(range_cache, res$query_cache_key)

    if (!is.null(cached_traits) && !is.null(cached_traits$error) && nzchar(cached_traits$error)) {
      all_errors <- c(all_errors, paste("trait_error:", cached_traits$error))
    }
    if (!is.null(cached_range) && !is.null(cached_range$error) && nzchar(cached_range$error)) {
      all_errors <- c(all_errors, paste("range_error:", cached_range$error))
    }

    all_errors <- unique(all_errors[!is.na(all_errors) & nzchar(all_errors)])
    if (length(all_errors) == 0) {
      return("No BIEN query errors captured for current species.")
    }
    paste(all_errors, collapse = "\n")
  })
}

shinyApp(ui = ui, server = server)
