# Load required packages, installing any missing CRAN dependencies on startup.
suppressPackageStartupMessages({
  required_packages <- c("shiny", "BIEN", "dplyr", "stringr", "leaflet", "DT", "sf", "ggplot2")
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
  library(sf)
  library(ggplot2)
})

# Wrap BIEN calls in a timeout-aware `tryCatch` so slow API responses do not lock up the app.
safe_bien_call <- function(expr, timeout_sec = 90) {
  on.exit(setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE), add = TRUE)
  setTimeLimit(elapsed = timeout_sec, transient = TRUE)
  tryCatch(expr, error = function(e) e)
}

safe_bien_retry <- function(call_fn, timeout_sec = 90, attempts = 1, sleep_sec = 1, exponential_backoff = FALSE, max_sleep_sec = 8) {
  last <- NULL
  for (i in seq_len(attempts)) {
    last <- safe_bien_call(call_fn(), timeout_sec = timeout_sec)
    if (is.data.frame(last) && nrow(last) > 0) {
      return(list(result = last, attempt = i, status = "ok"))
    }
    if (inherits(last, "error") && i < attempts) {
      wait_sec <- if (isTRUE(exponential_backoff)) {
        min(max_sleep_sec, sleep_sec * (2 ^ (i - 1)))
      } else {
        sleep_sec
      }
      Sys.sleep(wait_sec)
    }
  }
  list(
    result = last,
    attempt = attempts,
    status = if (inherits(last, "error")) "error" else "empty"
  )
}

# Normalize user-entered species strings so BIEN queries are robust to case.
normalize_species_name <- function(x) {
  x <- str_squish(x)
  if (!nzchar(x)) {
    return(x)
  }

  parts <- strsplit(x, "\\s+")[[1]]
  if (length(parts) >= 1) {
    genus <- parts[1]
    parts[1] <- paste0(str_to_upper(substr(genus, 1, 1)), str_to_lower(substr(genus, 2, nchar(genus))))
  }
  if (length(parts) >= 2) {
    parts[2] <- str_to_lower(parts[2])
  }
  if (length(parts) >= 3) {
    # Keep infraspecific epithets normalized while leaving author strings as entered.
    epithet_idx <- which(str_detect(str_to_lower(parts), "^(subsp\\.?|var\\.?|f\\.?)$")) + 1
    epithet_idx <- epithet_idx[epithet_idx <= length(parts)]
    if (length(epithet_idx) > 0) {
      parts[epithet_idx] <- str_to_lower(parts[epithet_idx])
    }
  }

  paste(parts, collapse = " ")
}

# Build a cached AsianPlant species index so we only show links when the
# requested species is listed on asianplant.net.
asianplant_species_index_cache <- new.env(parent = emptyenv())
asianplant_species_index_cache$loaded <- FALSE
asianplant_species_index_cache$index <- setNames(character(0), character(0))

load_asianplant_species_index <- function(timeout_sec = 8, refresh = FALSE) {
  if (isTRUE(asianplant_species_index_cache$loaded) && !isTRUE(refresh)) {
    return(asianplant_species_index_cache$index)
  }

  fetch_res <- safe_bien_call(
    readLines("https://www.asianplant.net/Species.htm", warn = FALSE, encoding = "UTF-8"),
    timeout_sec = timeout_sec
  )

  if (inherits(fetch_res, "error") || !is.character(fetch_res) || length(fetch_res) == 0) {
    asianplant_species_index_cache$loaded <- TRUE
    asianplant_species_index_cache$index <- setNames(character(0), character(0))
    return(asianplant_species_index_cache$index)
  }

  html_txt <- paste(fetch_res, collapse = "\n")
  link_pattern <- "<a\\s+[^>]*href\\s*=\\s*\"([^\"]+)\"[^>]*>([^<]+)</a>"
  link_nodes <- unlist(regmatches(html_txt, gregexpr(link_pattern, html_txt, perl = TRUE)), use.names = FALSE)

  if (length(link_nodes) == 0) {
    asianplant_species_index_cache$loaded <- TRUE
    asianplant_species_index_cache$index <- setNames(character(0), character(0))
    return(asianplant_species_index_cache$index)
  }

  hrefs <- sub(link_pattern, "\\1", link_nodes, perl = TRUE)
  labels <- sub(link_pattern, "\\2", link_nodes, perl = TRUE)
  labels <- vapply(labels, normalize_species_name, character(1))
  is_binomial <- str_detect(labels, "^[A-Z][a-z-]+\\s+[a-z-]+$")

  hrefs <- hrefs[is_binomial]
  labels <- labels[is_binomial]

  hrefs <- ifelse(
    str_detect(hrefs, "^https?://"),
    hrefs,
    paste0("https://www.asianplant.net/", sub("^/+", "", hrefs))
  )

  idx <- hrefs
  names(idx) <- labels
  idx <- idx[!duplicated(names(idx))]

  asianplant_species_index_cache$loaded <- TRUE
  asianplant_species_index_cache$index <- idx
  idx
}

get_asianplant_species_url <- function(species_name) {
  species_name <- normalize_species_name(species_name)
  if (!nzchar(species_name)) {
    return(NA_character_)
  }

  parts <- strsplit(species_name, "\\s+")[[1]]
  if (length(parts) < 2) {
    return(NA_character_)
  }
  binomial <- paste(parts[1:2], collapse = " ")

  idx <- load_asianplant_species_index()
  if (length(idx) == 0 || !(binomial %in% names(idx))) {
    return(NA_character_)
  }

  unname(idx[[binomial]])
}

# Suggest a likely intended species spelling by searching BIEN species names within
# the same genus and ranking by edit distance.
find_best_species_spelling <- function(species_name, timeout_sec = 20) {
  species_name <- normalize_species_name(species_name)
  parts <- strsplit(species_name, "\\s+")[[1]]

  if (length(parts) < 2) {
    return(list(status = "insufficient_input"))
  }

  genus <- parts[1]
  genus_rows <- safe_bien_call(BIEN_taxonomy_genus(genus), timeout_sec = min(timeout_sec, 20))

  if (inherits(genus_rows, "error")) {
    return(list(status = "lookup_error", message = conditionMessage(genus_rows)))
  }

  if (!is.data.frame(genus_rows) || nrow(genus_rows) == 0) {
    return(list(status = "no_genus_candidates"))
  }

  species_col <- find_first_col(genus_rows, c("scrubbed_species_binomial", "species", "scientific_name"))
  if (is.null(species_col)) {
    return(list(status = "no_species_column"))
  }

  candidates <- unique(str_squish(as.character(genus_rows[[species_col]])))
  candidates <- candidates[!is.na(candidates) & nzchar(candidates)]
  candidates <- unique(vapply(candidates, normalize_species_name, character(1)))

  if (any(tolower(candidates) == tolower(species_name))) {
    return(list(status = "exact_match_found"))
  }

  candidates <- candidates[tolower(candidates) != tolower(species_name)]

  if (length(candidates) == 0) {
    return(list(status = "no_alternative_candidates"))
  }

  d <- as.integer(utils::adist(tolower(species_name), tolower(candidates))[1, ])
  best_idx <- which.min(d)
  best_name <- candidates[[best_idx]]
  best_dist <- d[[best_idx]]
  max_len <- max(1L, nchar(species_name), nchar(best_name))
  norm_dist <- best_dist / max_len

  confidence <- if (norm_dist <= 0.15) {
    "high"
  } else if (norm_dist <= 0.30) {
    "medium"
  } else {
    "low"
  }

  if (best_dist > 4 && norm_dist > 0.35) {
    return(list(status = "low_quality_match", suggested_name = best_name, confidence = confidence, edit_distance = best_dist))
  }

  list(
    status = "suggested",
    suggested_name = best_name,
    confidence = confidence,
    edit_distance = best_dist,
    candidate_count = length(candidates)
  )
}

load_accepted_species_suggestions <- function(timeout_sec = 60) {
  sql <- paste0(
    "SELECT DISTINCT b.scrubbed_species_binomial AS taxon ",
    "FROM bien_taxonomy b ",
    "WHERE b.scrubbed_taxonomic_status = 'Accepted' ",
    "AND b.scrubbed_species_binomial IS NOT NULL ",
    "AND b.scrubbed_species_binomial <> '' ",
    "ORDER BY b.scrubbed_species_binomial;"
  )

  out <- safe_bien_call(BIEN:::.BIEN_sql(sql, fetch.query = FALSE), timeout_sec = timeout_sec)
  if (inherits(out, "error") || !is.data.frame(out) || nrow(out) == 0 || !"taxon" %in% names(out)) {
    return(character(0))
  }

  vals <- unique(str_squish(as.character(out$taxon)))
  vals <- vals[!is.na(vals) & nzchar(vals)]
  vals
}

sql_quote_literal <- function(x) {
  x <- as.character(x)
  x <- gsub("'", "''", x, fixed = TRUE)
  paste0("'", x, "'")
}

# Custom native status filter that handles NULL values properly.
# BIEN's internal :::natives_check() checks `is_introduced`column and excludes NULLs,
# which causes species with missing is_introduced data to return zero records.
# This version includes NULL as a valid case since absence of classification
# shouldn't exclude a species from a 'natives only' query.
natives_check_with_null_fallback <- function(natives_only = TRUE) {
  if (isTRUE(natives_only)) {
    # Include records where is_introduced = 0 (native) OR is_introduced IS NULL (unknown)
    list(query = "AND (is_introduced=0 OR is_introduced IS NULL) ")
  } else {
    # Include all records regardless of native/introduced status
    list(query = "")
  }
}

# Query BIEN occurrences with the same biological filters used by the BIEN helper,
# but (1) exclude trait-linked rows that belong in the Traits tab rather than the
# occurrence map and (2) randomize the returned row order on the BIEN side so
# widespread species are less likely to be dominated by whichever datasource
# happens to come first in the backend table (for example FIA plot rows).
query_occurrence_randomized <- function(species_name, cultivated = FALSE, natives_only = TRUE, only_geovalid = TRUE, limit = 1000, record_limit = 500, randomize_order = TRUE) {
  cultivated_ <- BIEN:::.cultivated_check(cultivated)
  newworld_ <- BIEN:::.newworld_check(NULL)
  taxonomy_ <- BIEN:::.taxonomy_check(TRUE)
  native_ <- BIEN:::.native_check(TRUE)
  observation_ <- BIEN:::.observation_check(TRUE)
  political_ <- BIEN:::.political_check(FALSE)
  natives_ <- natives_check_with_null_fallback(natives_only)
  collection_ <- BIEN:::.collection_check(FALSE)
  geovalid_ <- BIEN:::.geovalid_check(only_geovalid)

  # Skip randomization for large fetches and also for very small-limit fallback plans.
  # ORDER BY random() LIMIT N requires scoring all matching rows even for tiny N,
  # which can take minutes on species with 500k+ occurrences (e.g. Solidago canadensis).
  # For limit <= 500, natural table order + R-side stratified sampling is sufficient.
  use_randomize <- isTRUE(randomize_order) && limit > 500 && limit <= 10000
  order_clause <- if (use_randomize) "ORDER BY random()" else ""

  query <- paste(
    "SELECT scrubbed_species_binomial", taxonomy_$select,
    native_$select, political_$select,
    ",latitude, longitude,date_collected,",
    "datasource,dataset,dataowner,custodial_institution_codes,collection_code,view_full_occurrence_individual.datasource_id",
    collection_$select, cultivated_$select, newworld_$select,
    observation_$select, geovalid_$select,
    "FROM view_full_occurrence_individual",
    "WHERE scrubbed_species_binomial in (", paste(sql_quote_literal(species_name), collapse = ", "), ")",
    cultivated_$query, newworld_$query, natives_$query,
    observation_$query, geovalid_$query,
    "AND higher_plant_group NOT IN ('Algae','Bacteria','Fungi')",
    "AND (georef_protocol is NULL OR georef_protocol<>'county centroid')",
    "AND (is_centroid IS NULL OR is_centroid=0)",
    "AND scrubbed_species_binomial IS NOT NULL",
    "AND lower(coalesce(observation_type, '')) NOT LIKE '%trait%'",
    "AND lower(coalesce(observation_type, '')) NOT LIKE '%measurement%'",
    order_clause,
    "LIMIT", as.integer(limit), ";"
  )

  BIEN:::.BIEN_sql(
    query,
    fetch.query = FALSE,
    record_limit = record_limit
  )
}

resolve_filter_profile <- function(input) {
  use_default_profile <- if (is.null(input$use_default_bien_filter_profile)) TRUE else isTRUE(input$use_default_bien_filter_profile)

  if (use_default_profile) {
    return(list(
      use_default_profile = TRUE,
      use_introduced_filter = TRUE,
      natives_only = TRUE,
      use_cultivated_filter = TRUE,
      include_cultivated = FALSE,
      only_geovalid = TRUE,
      exclude_human_observation_records = FALSE,
      only_plot_observations = FALSE
    ))
  }

  list(
    use_default_profile = FALSE,
    use_introduced_filter = if (is.null(input$use_introduced_filter)) TRUE else isTRUE(input$use_introduced_filter),
    natives_only = if (is.null(input$natives_only)) TRUE else isTRUE(input$natives_only),
    use_cultivated_filter = if (is.null(input$use_cultivated_filter)) TRUE else isTRUE(input$use_cultivated_filter),
    include_cultivated = if (is.null(input$include_cultivated)) FALSE else isTRUE(input$include_cultivated),
    only_geovalid = if (is.null(input$only_geovalid)) TRUE else isTRUE(input$only_geovalid),
    exclude_human_observation_records = if (is.null(input$exclude_human_observation_records)) FALSE else isTRUE(input$exclude_human_observation_records),
    only_plot_observations = if (is.null(input$only_plot_observations)) FALSE else isTRUE(input$only_plot_observations)
  )
}

query_occurrence_with_fallback <- function(species_name, input, occ_limit, occ_page_size, timeout_sec, connection_retry = FALSE, max_plans = 3, per_plan_timeout = 25, randomize_order = TRUE) {
  filter_cfg <- resolve_filter_profile(input)
  include_cultivated <- if (filter_cfg$use_cultivated_filter) filter_cfg$include_cultivated else TRUE
  natives_only <- if (filter_cfg$use_introduced_filter) filter_cfg$natives_only else FALSE
  only_geovalid <- filter_cfg$only_geovalid

  # Respect larger user-requested sample sizes while keeping an upper guardrail for server stability.
  fast_limit <- min(occ_limit, 50000)
  fast_page_size <- min(occ_page_size, 5000, fast_limit)

  # Try the user-requested interpretation first, then relax native-only and finally
  # geovalid constraints if needed so the app can still show some BIEN evidence.
  plans <- list(
    list(label = "strict", natives.only = natives_only, only.geovalid = only_geovalid, limit = fast_limit, record_limit = fast_page_size),
    list(label = "fallback_relaxed_native", natives.only = FALSE, only.geovalid = only_geovalid, limit = min(fast_limit, 500), record_limit = min(fast_page_size, 500)),
    list(label = "fallback_relaxed_geo", natives.only = FALSE, only.geovalid = FALSE, limit = min(fast_limit, 500), record_limit = min(fast_page_size, 500))
  )
  plans <- plans[seq_len(max(1, min(length(plans), as.integer(max_plans))))]

  notes <- character()
  last_result <- NULL
  attempts_n <- if (isTRUE(connection_retry)) 3 else 1
  query_started <- Sys.time()
  deadline <- query_started + as.numeric(timeout_sec)
  skip_to_relaxed_geo <- FALSE

  for (plan in plans) {
    if (isTRUE(skip_to_relaxed_geo) && !identical(plan$label, "fallback_relaxed_geo")) {
      next
    }

    remaining_sec <- as.numeric(difftime(deadline, Sys.time(), units = "secs"))
    if (!is.finite(remaining_sec) || remaining_sec <= 1) {
      notes <- c(notes, "occ_timeout_budget_exhausted")
      break
    }

    # Keep strict plan bounded so relaxed fallback plans still get a chance within timeout budget.
    plan_timeout_cap <- if (identical(plan$label, "strict")) min(per_plan_timeout, 25) else per_plan_timeout
    plan_timeout_sec <- max(2, min(plan_timeout_cap, remaining_sec))

    res <- safe_bien_retry(
      function() {
        query_occurrence_randomized(
          species_name = species_name,
          cultivated = include_cultivated,
          natives_only = plan$natives.only,
          only_geovalid = plan$only.geovalid,
          limit = plan$limit,
          record_limit = plan$record_limit,
          randomize_order = randomize_order
        )
      },
      timeout_sec = plan_timeout_sec,
      attempts = attempts_n,
      sleep_sec = 1,
      exponential_backoff = isTRUE(connection_retry),
      max_sleep_sec = 8
    )

    last_result <- res$result
    notes <- c(notes, paste0("occ_strategy=", plan$label, "; status=", res$status, "; attempts=", res$attempt, "; limit=", plan$limit))

    if (is.data.frame(res$result) && nrow(res$result) > 0) {
      if (identical(plan$label, "strict") && isTRUE(plan$only.geovalid)) {
        strict_mappable_n <- count_mappable_occurrences(res$result)
        notes <- c(notes, paste0("strict_mappable=", strict_mappable_n))

        if (strict_mappable_n == 0 && any(vapply(plans, function(p) identical(p$label, "fallback_relaxed_geo"), logical(1)))) {
          notes <- c(notes, "strict_zero_mappable_triggered_relaxed_geo_pass")
          skip_to_relaxed_geo <- TRUE
          next
        }
      }

      return(list(data = res$result, strategy = plan$label, notes = notes, limit_used = plan$limit))
    }

    if (inherits(res$result, "error")) {
      err_msg <- conditionMessage(res$result)
      notes <- c(notes, paste("occ_error:", err_msg))

      # Connection saturation usually won't improve within the same query cycle.
      if (is_bien_connection_error(err_msg)) {
        break
      }

      # Timeouts on strict filters are common for large species; continue to relaxed plans.
      if (is_bien_timeout_error(err_msg)) {
        skip_to_relaxed_geo <- TRUE
        next
      }
    }
  }

  final_strategy <- if (is_bien_connection_error(notes)) {
    "backend_connection_error"
  } else if (is_bien_timeout_error(notes)) {
    "backend_timeout_error"
  } else {
    "none"
  }
  list(data = last_result, strategy = final_strategy, notes = notes, limit_used = fast_limit)
}


find_lucky_species_with_mappable_points <- function(input, min_mappable_points = 30, max_attempts = 3, timeout_sec = 12, min_observations = 10) {
  starter_pool <- c(
    "Chimarrhis hookeri",
    "Cedrela angustifolia",
    "Hevea brasiliensis",
    "Clusia alata",
    "Annona montana",
    "Bunchosia armeniaca",
    "Guatteria excelsa",
    "Miconia calophylla",
    "Ficus pallida",
    "Capparis micracantha",
    "Clappertonia ficifolia",
    "Dacryodes costata",
    "Ilex cymosa",
    "Lasianthus attenuatus",
    "Ochrosia elliptica",
    "Popowia pisocarpa",
    "Quassia indica",
    "Aquilegia coerulea"
  )

  fetch_random_bien_species_pool <- function(min_observations = 10, pool_size = 180, timeout_sec = 12) {
    query <- paste(
      "SELECT scrubbed_species_binomial, COUNT(*) AS bien_total_records",
      "FROM view_full_occurrence_individual",
      "WHERE scrubbed_species_binomial IS NOT NULL",
      "AND higher_plant_group NOT IN ('Algae','Bacteria','Fungi')",
      "AND lower(coalesce(observation_type, '')) NOT LIKE '%trait%'",
      "AND lower(coalesce(observation_type, '')) NOT LIKE '%measurement%'",
      "GROUP BY scrubbed_species_binomial",
      "HAVING COUNT(*) >=", as.integer(min_observations),
      "ORDER BY random()",
      "LIMIT", as.integer(pool_size), ";"
    )

    res <- safe_bien_call(
      BIEN:::.BIEN_sql(query, fetch.query = FALSE),
      timeout_sec = min(15, max(8, as.numeric(timeout_sec)))
    )

    if (inherits(res, "error") || !is.data.frame(res) || nrow(res) == 0) {
      return(data.frame(species = character(0), n_obs = numeric(0), stringsAsFactors = FALSE))
    }

    species_col <- find_first_col(res, c("scrubbed_species_binomial", "species"))
    count_col <- find_first_col(res, c("bien_total_records", "count"))
    if (is.null(species_col)) {
      return(data.frame(species = character(0), n_obs = numeric(0), stringsAsFactors = FALSE))
    }

    out <- data.frame(
      species = as.character(res[[species_col]]),
      n_obs = if (!is.null(count_col)) suppressWarnings(as.numeric(res[[count_col]])) else NA_real_,
      stringsAsFactors = FALSE
    )
    out <- out[!is.na(out$species) & nzchar(out$species), , drop = FALSE]
    out <- out[!duplicated(tolower(out$species)), , drop = FALSE]
    out
  }

  has_verified_range <- function(candidate) {
    candidate_dir <- file.path(tempdir(), "bien_lucky_ranges", gsub("\\s+", "_", candidate))
    dir.create(candidate_dir, recursive = TRUE, showWarnings = FALSE)
    on.exit(unlink(candidate_dir, recursive = TRUE), add = TRUE)

    range_obj <- safe_bien_call(
      BIEN_ranges_species(
        species = candidate,
        directory = candidate_dir,
        matched = TRUE,
        match_names_only = FALSE,
        include.gid = TRUE,
        limit = 10,
        record_limit = 10,
        fetch.query = FALSE
      ),
      timeout_sec = min(12, max(6, as.numeric(timeout_sec)))
    )
    downloaded_range_sf <- read_downloaded_range_sf(candidate_dir, candidate)

    (is.data.frame(range_obj) && nrow(range_obj) > 0) ||
      (inherits(range_obj, "sf") && nrow(range_obj) > 0) ||
      (inherits(downloaded_range_sf, "sf") && nrow(downloaded_range_sf) > 0)
  }

  current_species <- normalize_species_name(if (is.null(input$species)) "" else as.character(input$species))
  norm_name <- function(x) normalize_species_name(gsub("\\s*\\(.*\\)\\s*$", "", as.character(x)))

  starter_pool <- unique(vapply(starter_pool, norm_name, FUN.VALUE = character(1)))
  if (nzchar(current_species)) {
    starter_pool <- starter_pool[tolower(starter_pool) != tolower(current_species)]
  }

  if (length(starter_pool) > 0) {
    starter_candidates <- sample(starter_pool, size = length(starter_pool), replace = FALSE)
    for (i in seq_along(starter_candidates)) {
      candidate <- starter_candidates[[i]]
      total_info <- count_occurrence_records(
        species_name = candidate,
        cultivated = FALSE,
        natives_only = TRUE,
        only_geovalid = TRUE,
        timeout_sec = min(12, max(8, as.numeric(timeout_sec)))
      )
      total_n <- suppressWarnings(as.numeric(total_info$total))

      if (!is.na(total_n) && total_n >= as.numeric(min_observations) && isTRUE(has_verified_range(candidate))) {
        return(list(status = "ok", species = candidate, mappable_n = NA_integer_, attempts = i, precheck = "starter_pool_range_verified"))
      }
    }
  }

  random_pool <- fetch_random_bien_species_pool(
    min_observations = min_observations,
    pool_size = max(120, 20 * max(1L, as.integer(max_attempts))),
    timeout_sec = timeout_sec
  )

  if (!is.data.frame(random_pool) || nrow(random_pool) == 0) {
    return(list(status = "not_found", species = NULL, mappable_n = NA_integer_, attempts = 0, precheck = "no_random_pool"))
  }

  if (nzchar(current_species)) {
    random_pool <- random_pool[tolower(random_pool$species) != tolower(current_species), , drop = FALSE]
  }
  if (nrow(random_pool) == 0) {
    return(list(status = "not_found", species = NULL, mappable_n = NA_integer_, attempts = 0, precheck = "random_pool_exhausted"))
  }

  attempts_cap <- min(nrow(random_pool), max(1L, as.integer(max_attempts)))
  pick_order <- sample(seq_len(nrow(random_pool)), size = attempts_cap, replace = FALSE)
  for (j in seq_along(pick_order)) {
    row_idx <- pick_order[[j]]
    candidate <- as.character(random_pool$species[[row_idx]])
    n_obs <- suppressWarnings(as.numeric(random_pool$n_obs[[row_idx]]))

    if (!is.na(n_obs) && n_obs >= as.numeric(min_observations) && isTRUE(has_verified_range(candidate))) {
      return(list(status = "ok", species = candidate, mappable_n = NA_integer_, attempts = j, precheck = "bien_random_pool_range_verified"))
    }
  }

  list(status = "not_found", species = NULL, mappable_n = NA_integer_, attempts = attempts_cap, precheck = "no_range_found")
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

  obs_txt_lower <- tolower(obs_txt)
  source_txt_lower <- tolower(source_txt)
  dataset_txt_lower <- tolower(dataset_txt)
  basis_txt_lower <- tolower(basis_txt)

  combined_txt <- tolower(paste(obs_txt_lower, source_txt_lower, dataset_txt_lower, basis_txt_lower))

  df$observation_category <- case_when(
    # Preserved specimens (Darwin Core basisOfRecord ~ PreservedSpecimen)
    str_detect(combined_txt, "specimen|herb|preserved|museum|preservedspecimen") ~ "Specimen / herbarium",

    # Plot / survey records (formal sampling)
    str_detect(combined_txt, "\\bplot\\b|\\bsurvey\\b|\\binventory\\b|\\bmonitoring\\b") ~ "Plot / survey",

    # iNaturalist citizen science (highest priority for citizen science detection)
    str_detect(combined_txt, "inaturalist") ~ "Citizen science (iNaturalist)",

    # Darwin Core HumanObservation (general field observations)
    # Use word boundary to avoid false positives from "observational_plots", "observation_id", etc.
    (str_detect(basis_txt_lower, "humanobservation|human observation") |
     (str_detect(combined_txt, "\\bhuman\\s+observation\\b|\\bhuman_observation\\b") & !str_detect(combined_txt, "specimen|museum|herb"))) ~ "Field observation (HumanObservation)",

    # GBIF-aggregated records (various sources, not specifically citizen science)
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
    natives_ <- natives_check_with_null_fallback(natives_only)
    observation_ <- BIEN:::.observation_check(TRUE)
    geovalid_ <- BIEN:::.geovalid_check(only_geovalid)

    count_query <- paste(
      "SELECT COUNT(*) AS bien_total_records",
      "FROM view_full_occurrence_individual",
      "WHERE scrubbed_species_binomial in (", paste(sql_quote_literal(species_name), collapse = ", "), ")",
      cultivated_$query, newworld_$query, natives_$query, observation_$query, geovalid_$query,
      "AND higher_plant_group NOT IN ('Algae','Bacteria','Fungi')",
      "AND (georef_protocol is NULL OR georef_protocol<>'county centroid')",
      "AND (is_centroid IS NULL OR is_centroid=0)",
      "AND scrubbed_species_binomial IS NOT NULL ;"
    )

    BIEN:::.BIEN_sql(count_query, fetch.query = FALSE)
  }, timeout_sec = min(timeout_sec, 20))

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
  cultivated_ <- BIEN:::.cultivated_check(cultivated)
  newworld_ <- BIEN:::.newworld_check(NULL)
  natives_ <- natives_check_with_null_fallback(natives_only)
  observation_ <- BIEN:::.observation_check(TRUE)
  geovalid_ <- BIEN:::.geovalid_check(only_geovalid)

  build_mix_query <- function(combined_sql) {
    # Wrap in a LIMIT-capped subquery to prevent multi-minute full-table GROUP BY
    # scans on very large species (e.g. Solidago canadensis 880 k+ rows).
    # Source-mix fractions are approximate for species with > 50 000 filtered rows.
    paste(
      "SELECT source_group, COUNT(*) AS n_records",
      "FROM (",
      "  SELECT CASE",
      paste0("  WHEN ", combined_sql, " LIKE '%inaturalist%' THEN 'iNaturalist'"),
      paste0("  WHEN ", combined_sql, " LIKE '%trait%' OR ", combined_sql, " LIKE '%measurement%' THEN 'Traits'"),
      paste0("  WHEN ", combined_sql, " LIKE '%plot%' OR ", combined_sql, " LIKE '%survey%' OR ", combined_sql, " LIKE '%inventory%' OR ", combined_sql, " LIKE '%monitoring%' THEN 'Plots'"),
      paste0("  WHEN ", combined_sql, " LIKE '%specimen%' OR ", combined_sql, " LIKE '%herb%' OR ", combined_sql, " LIKE '%preserved specimen%' OR ", combined_sql, " LIKE '%preservedspecimen%' OR ", combined_sql, " LIKE '%museum%' THEN 'Specimens'"),
      "  ELSE 'Other' END AS source_group",
      "  FROM view_full_occurrence_individual",
      "  WHERE scrubbed_species_binomial in (", paste(sql_quote_literal(species_name), collapse = ", "), ")",
      cultivated_$query, newworld_$query, natives_$query, observation_$query, geovalid_$query,
      "  AND higher_plant_group NOT IN ('Algae','Bacteria','Fungi')",
      "  AND (georef_protocol is NULL OR georef_protocol<>'county centroid')",
      "  AND (is_centroid IS NULL OR is_centroid=0)",
      "  AND scrubbed_species_binomial IS NOT NULL",
      "  LIMIT 50000",
      ") AS mix_subquery",
      "GROUP BY source_group ORDER BY n_records DESC;"
    )
  }

  combined_sql <- "lower(coalesce(observation_type, '') || ' ' || coalesce(datasource, '') || ' ' || coalesce(dataset, ''))"

  mix_res <- safe_bien_call(
    BIEN:::.BIEN_sql(build_mix_query(combined_sql), fetch.query = FALSE),
    timeout_sec = min(timeout_sec, 8)
  )

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
      embedded_unit_tag = case_when(
        stringr::str_detect(stringr::str_to_lower(trait_value_std), "%|percent") ~ "percent",
        stringr::str_detect(stringr::str_to_lower(trait_value_std), "mg\\s*/\\s*g") ~ "mg/g",
        stringr::str_detect(stringr::str_to_lower(trait_value_std), "g\\s*/\\s*kg") ~ "g/kg",
        stringr::str_detect(stringr::str_to_lower(trait_value_std), "mg\\s*/\\s*kg") ~ "mg/kg",
        stringr::str_detect(stringr::str_to_lower(trait_value_std), "ug\\s*/\\s*g|µg\\s*/\\s*g") ~ "ug/g",
        stringr::str_detect(stringr::str_to_lower(trait_value_std), "ppm") ~ "ppm",
        TRUE ~ "unknown"
      ),
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

  trait_unit_profile <- plot_df %>%
    group_by(trait_name_std) %>%
    summarise(
      n_distinct_units = n_distinct(unit_std),
      units_present = paste(sort(unique(unit_std)), collapse = " | "),
      .groups = "drop"
    )

  summary_tbl <- plot_df %>%
    group_by(trait_name_std, unit_std) %>%
    group_modify(~ {
      df <- .x
      n_numeric_used <- sum(!is.na(df$trait_value_num))
      n_non_numeric_excluded <- sum(is.na(df$trait_value_num))
      num_vals <- df$trait_value_num[!is.na(df$trait_value_num)]
      is_continuous <- n_numeric_used >= max(3, ceiling(0.6 * nrow(df))) && length(unique(num_vals)) > 1
      embedded_units <- sort(unique(df$embedded_unit_tag[df$embedded_unit_tag != "unknown"]))
      n_embedded_units <- length(embedded_units)
      unit_qc_flag <- if (unique(df$unit_std) == "unspecified" && n_embedded_units > 1) {
        paste0("possible mixed implicit units (", paste(embedded_units, collapse = " | "), ")")
      } else if (unique(df$unit_std) == "unspecified" && n_embedded_units == 1) {
        paste0("unit missing in BIEN; value strings suggest ", embedded_units)
      } else {
        "none"
      }

      if (is_continuous) {
        tibble(
          value_type = "continuous",
          n_records = nrow(df),
          n_numeric_used = n_numeric_used,
          n_non_numeric_excluded = n_non_numeric_excluded,
          unit_qc_flag = unit_qc_flag,
          mean_value = round(mean(num_vals), 4),
          min_value = round(min(num_vals), 4),
          max_value = round(max(num_vals), 4),
          modal_value = NA_character_,
          summary_note = paste0(
            "mean=", round(mean(num_vals), 3),
            "; range=", round(min(num_vals), 3), " to ", round(max(num_vals), 3),
            "; numeric used=", n_numeric_used, "/", nrow(df),
            ifelse(unit_qc_flag != "none", paste0("; QC=", unit_qc_flag), "")
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
          unit_qc_flag = unit_qc_flag,
          mean_value = NA_real_,
          min_value = NA_real_,
          max_value = NA_real_,
          modal_value = mode_val,
          summary_note = paste0(
            "mode=", mode_val, " (n=", unname(val_tbl[1]), "); numeric used=", n_numeric_used, "/", nrow(df),
            ifelse(unit_qc_flag != "none", paste0("; QC=", unit_qc_flag), "")
          )
        )
      }
    }) %>%
    ungroup() %>%
    left_join(trait_unit_profile, by = "trait_name_std") %>%
    mutate(
      trait_level_unit_note = ifelse(
        n_distinct_units > 1,
        paste0("multiple BIEN units for this trait: ", units_present),
        "single BIEN unit for this trait"
      )
    ) %>%
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

is_bien_timeout_error <- function(messages) {
  if (length(messages) == 0 || all(is.na(messages))) {
    return(FALSE)
  }

  any(grepl(
    "elapsed time limit|timeout|time limit|pending rows|could not create execute|statement timeout",
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

    need <- target_n - length(selected)
    extra_buf <- integer(need)
    ptr <- 0L

    while (ptr < need && any(lengths(leftovers) > 0)) {
      for (i in seq_along(leftovers)) {
        if (ptr >= need) break
        if (length(leftovers[[i]]) == 0) next
        add_pos <- sample.int(length(leftovers[[i]]), size = 1)
        add_idx <- leftovers[[i]][add_pos]
        ptr <- ptr + 1L
        extra_buf[ptr] <- add_idx
        leftovers[[i]] <- setdiff(leftovers[[i]], add_idx)
      }
    }
    selected <- c(selected, extra_buf[seq_len(ptr)])
  }

  selected <- selected[seq_len(min(length(selected), target_n))]
  df[selected, , drop = FALSE]
}

count_mappable_occurrences <- function(occ) {
  if (!is.data.frame(occ) || nrow(occ) == 0) {
    return(0L)
  }

  lat_col <- find_first_col(occ, c("latitude", "decimal_latitude", "lat"))
  lon_col <- find_first_col(occ, c("longitude", "decimal_longitude", "lon", "long"))
  if (is.null(lat_col) || is.null(lon_col)) {
    return(0L)
  }

  lat <- suppressWarnings(as.numeric(occ[[lat_col]]))
  lon <- suppressWarnings(as.numeric(occ[[lon_col]]))
  valid <- !is.na(lat) & !is.na(lon) & lat >= -90 & lat <= 90 & lon >= -180 & lon <= 180
  as.integer(sum(valid, na.rm = TRUE))
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
  esc <- htmltools::htmlEscape
  species_col <- find_first_col(df, c("scrubbed_species_binomial", "species", "scientific_name", "taxon"))
  country_col <- find_first_col(df, c("country", "country_name"))
  state_col <- find_first_col(df, c("state_province", "state"))
  source_col <- find_first_col(df, c("datasource", "data_source", "collection", "source"))
  obs_type_col <- find_first_col(df, c("observation_type", "observation.type"))
  intro_col <- find_first_col(df, c("is_introduced"))
  category_txt <- if ("observation_category" %in% names(df)) as.character(df$observation_category) else NA_character_

  species_txt <- if (!is.null(species_col)) esc(as.character(df[[species_col]])) else "record"
  country_txt <- if (!is.null(country_col)) esc(as.character(df[[country_col]])) else NA_character_
  state_txt <- if (!is.null(state_col)) esc(as.character(df[[state_col]])) else NA_character_
  source_txt <- if (!is.null(source_col)) esc(as.character(df[[source_col]])) else NA_character_
  obs_type_txt <- if (!is.null(obs_type_col)) esc(as.character(df[[obs_type_col]])) else NA_character_
  intro_txt <- if (!is.null(intro_col)) esc(as.character(df[[intro_col]])) else NA_character_
  category_txt <- esc(as.character(category_txt))

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

compact_label <- function(text, tip = NULL) {
  if (is.null(tip) || !nzchar(tip)) {
    return(text)
  }
  tip_escaped <- htmltools::htmlEscape(tip, attribute = TRUE)
  HTML(paste0(
    text,
    " <span class=\"bien-inline-tip\" role=\"button\" tabindex=\"0\" data-bien-tip=\"", tip_escaped, "\" aria-label=\"Info: ", tip_escaped, "\">&#9432;</span>"
  ))
}

choose_startup_species_from_local_samples <- function(data_dir = file.path(getwd(), "sample_data")) {
  occ_files <- list.files(data_dir, pattern = "_occurrences\\.csv$", full.names = TRUE)
  if (length(occ_files) == 0) {
    return("Pinus ponderosa")
  }

  best_species <- "Pinus ponderosa"
  best_score <- -Inf

  for (occ_file in occ_files) {
    species_slug <- sub("_occurrences\\.csv$", "", basename(occ_file))
    trait_file <- file.path(data_dir, paste0(species_slug, "_traits.csv"))
    if (!file.exists(trait_file)) {
      next
    }

    occ <- tryCatch(read.csv(occ_file, stringsAsFactors = FALSE), error = function(e) data.frame())
    traits <- tryCatch(read.csv(trait_file, stringsAsFactors = FALSE), error = function(e) data.frame())
    if (!is.data.frame(occ) || nrow(occ) == 0 || !is.data.frame(traits) || nrow(traits) == 0) {
      next
    }

    occ_cat <- categorize_observation_records(occ)
    n_obs_classes <- if ("observation_category" %in% names(occ_cat)) {
      length(unique(occ_cat$observation_category[!is.na(occ_cat$observation_category) & nzchar(occ_cat$observation_category)]))
    } else {
      0
    }

    trait_value_col <- find_first_col(traits, c("trait_value", "value"))
    if (is.null(trait_value_col)) {
      next
    }
    trait_vals <- trimws(as.character(traits[[trait_value_col]]))
    trait_vals <- trait_vals[!is.na(trait_vals) & nzchar(trait_vals)]
    if (length(trait_vals) == 0) {
      next
    }
    trait_num <- suppressWarnings(as.numeric(trait_vals))
    has_numeric_trait <- any(!is.na(trait_num))
    has_non_numeric_trait <- any(is.na(trait_num))

    score <- 0
    score <- score + ifelse(has_numeric_trait, 1, 0)
    score <- score + ifelse(has_non_numeric_trait, 1, 0)
    score <- score + min(n_obs_classes, 5) / 5
    score <- score + log1p(nrow(occ)) / 12
    if (n_obs_classes >= 3 && has_numeric_trait && has_non_numeric_trait) {
      score <- score + 2
    }

    if (score > best_score) {
      best_score <- score
      best_species <- gsub("_", " ", species_slug)
    }
  }

  normalize_species_name(best_species)
}

STARTUP_SPECIES <- "Pinus ponderosa"
STARTUP_SPECIES_SLUG <- gsub("\\s+", "_", tolower(STARTUP_SPECIES))
STARTUP_CACHE_KEY <- paste0("startup_preloaded_", STARTUP_SPECIES_SLUG)

parse_collection_year <- function(date_str) {
  if (is.null(date_str) || is.na(date_str) || !nzchar(as.character(date_str))) {
    return(NA_integer_)
  }
  suppressWarnings(as.integer(substr(as.character(date_str), 1, 4)))
}

bin_temporal_data <- function(occ_df, year_min = 1700, year_max = NULL) {
  if (!is.data.frame(occ_df) || nrow(occ_df) == 0 || !"date_collected" %in% names(occ_df)) {
    return(NULL)
  }

  if (!"observation_category" %in% names(occ_df)) {
    occ_df <- categorize_observation_records(occ_df)
  }

  occ_df$collection_year <- vapply(occ_df$date_collected, parse_collection_year, integer(1))
  occ_valid <- occ_df[!is.na(occ_df$collection_year), , drop = FALSE]
  if (nrow(occ_valid) == 0) {
    return(NULL)
  }

  if (is.null(year_max)) {
    year_max <- max(occ_valid$collection_year, na.rm = TRUE)
  }

  occ_valid <- occ_valid[
    occ_valid$collection_year >= year_min & occ_valid$collection_year <= year_max,
    ,
    drop = FALSE
  ]
  if (nrow(occ_valid) == 0) {
    return(NULL)
  }

  occ_valid$decade_bin <- as.integer(floor(occ_valid$collection_year / 10) * 10)

  occ_valid %>%
    group_by(decade_bin, observation_category) %>%
    summarise(count = n(), .groups = "drop") %>%
    arrange(decade_bin, observation_category)
}

summarize_temporal_stats <- function(occ_df) {
  if (!is.data.frame(occ_df) || nrow(occ_df) == 0 || !"date_collected" %in% names(occ_df)) {
    return(list(total_records = if (is.data.frame(occ_df)) nrow(occ_df) else 0, records_with_dates = 0, earliest_year = NA_integer_, latest_year = NA_integer_, median_year = NA_integer_, span_years = NA_integer_))
  }

  years_valid <- vapply(occ_df$date_collected, parse_collection_year, integer(1))
  years_valid <- years_valid[!is.na(years_valid)]

  if (length(years_valid) == 0) {
    return(list(total_records = nrow(occ_df), records_with_dates = 0, earliest_year = NA_integer_, latest_year = NA_integer_, median_year = NA_integer_, span_years = NA_integer_))
  }

  earliest <- min(years_valid, na.rm = TRUE)
  latest <- max(years_valid, na.rm = TRUE)

  list(
    total_records = nrow(occ_df),
    records_with_dates = length(years_valid),
    earliest_year = earliest,
    latest_year = latest,
    median_year = as.integer(stats::median(years_valid, na.rm = TRUE)),
    span_years = as.integer(latest - earliest)
  )
}

normalize_field_name <- function(x) {
  x <- trimws(tolower(as.character(x)))
  gsub("[^a-z0-9]", "", x)
}

drop_empty_rows <- function(df) {
  if (!is.data.frame(df) || nrow(df) == 0) {
    return(df)
  }

  keep_idx <- apply(df, 1, function(row_vals) {
    vals <- trimws(as.character(row_vals))
    any(!is.na(vals) & nzchar(vals))
  })

  df[keep_idx, , drop = FALSE]
}

get_dwc_aliases <- function() {
  list(
    scientificName = c("scientificName", "species", "species_name", "taxon", "taxon_name", "organism"),
    decimalLatitude = c("decimalLatitude", "latitude", "lat", "y", "lat_dd"),
    decimalLongitude = c("decimalLongitude", "longitude", "long", "lon", "x", "long_dd"),
    plotName = c("plotName", "plot_name", "plot", "site", "site_name", "location"),
    eventDate = c("eventDate", "date", "date_collected", "collection_date", "sample_date"),
    occurrenceID = c("occurrenceID", "record_id", "id", "sample_id", "observation_id"),
    basisOfRecord = c("basisOfRecord", "observation_type", "record_type"),
    measurementType = c("measurementType", "trait", "trait_name", "variable", "measurement_name"),
    measurementValue = c("measurementValue", "value", "trait_value", "dbh", "diameter", "measurement"),
    measurementUnit = c("measurementUnit", "unit", "units", "trait_unit")
  )
}

get_bien_reference_fields <- function(timeout_sec = 12) {
  occ_fields <- character(0)
  trait_fields <- character(0)

  occ <- safe_bien_call(
    BIEN_occurrence_species(
      "Pinus ponderosa",
      cultivated = FALSE,
      natives.only = TRUE,
      only.geovalid = TRUE,
      all.taxonomy = TRUE,
      limit = 1,
      record_limit = 1,
      fetch.query = FALSE
    ),
    timeout_sec = timeout_sec
  )
  if (is.data.frame(occ)) {
    occ_fields <- names(occ)
  }

  traits <- safe_bien_call(
    BIEN_trait_species(
      "Pinus ponderosa",
      all.taxonomy = TRUE,
      source.citation = TRUE,
      limit = 1,
      record_limit = 1,
      fetch.query = FALSE
    ),
    timeout_sec = timeout_sec
  )
  if (is.data.frame(traits)) {
    trait_fields <- names(traits)
  }

  fallback_fields <- c(
    "scrubbed_species_binomial", "scrubbed_family", "scrubbed_genus", "latitude", "longitude",
    "date_collected", "datasource", "dataset", "dataowner", "collection_code", "trait_name",
    "trait_value", "unit", "method", "elevation_m", "url_source", "project_pi", "id",
    "plot_name", "occurrence_id"
  )

  unique(c(occ_fields, trait_fields, fallback_fields))
}

lookup_alias_term <- function(col_name, alias_map) {
  col_norm <- normalize_field_name(col_name)
  for (term in names(alias_map)) {
    aliases <- unique(c(term, alias_map[[term]]))
    alias_norm <- normalize_field_name(aliases)
    if (col_norm %in% alias_norm) {
      return(term)
    }
  }
  NA_character_
}

build_column_mapping <- function(df, source_file, bien_reference_fields) {
  if (!is.data.frame(df)) {
    return(data.frame())
  }

  dwc_alias <- get_dwc_aliases()
  bien_alias <- list(
    scrubbed_species_binomial = c("species", "scientific_name", "scientificname", "scientificName", "taxon"),
    latitude = c("decimalLatitude", "latitude", "lat"),
    longitude = c("decimalLongitude", "longitude", "long", "lon"),
    date_collected = c("eventDate", "date", "date_collected", "collection_date"),
    trait_name = c("measurementType", "trait_name", "trait", "variable", "measurement_name", "dbh"),
    trait_value = c("measurementValue", "trait_value", "value", "dbh", "diameter"),
    unit = c("measurementUnit", "trait_unit", "unit", "units"),
    dataset = c("dataset", "project", "survey", "study")
  )

  bien_norm <- normalize_field_name(bien_reference_fields)
  col_names <- names(df)
  col_norm <- normalize_field_name(col_names)

  mapped_dwc <- vapply(col_names, function(x) lookup_alias_term(x, dwc_alias), character(1))
  mapped_bien <- vapply(col_names, function(x) {
    alias_hit <- lookup_alias_term(x, bien_alias)
    if (!is.na(alias_hit)) {
      return(alias_hit)
    }

    this_norm <- normalize_field_name(x)
    hit_idx <- which(bien_norm == this_norm)
    if (length(hit_idx) > 0) {
      return(bien_reference_fields[[hit_idx[[1]]]])
    }

    NA_character_
  }, character(1))

  data.frame(
    source_file = source_file,
    input_column = col_names,
    normalized_column = col_norm,
    mapped_dwc_term = mapped_dwc,
    mapped_bien_field = mapped_bien,
    bien_exact_name_match = col_norm %in% bien_norm,
    stringsAsFactors = FALSE
  )
}

suggest_merge_key <- function(mapped_tables, standardized_tables) {
  if (length(standardized_tables) < 2) {
    return(list(key = NULL, candidates = data.frame()))
  }

  all_cols <- unique(unlist(lapply(standardized_tables, names), use.names = FALSE))
  key_candidates <- all_cols[all_cols %in% c("plotName", "occurrenceID", "scientificName", "scrubbed_species_binomial", "eventDate")]
  if (length(key_candidates) == 0) {
    key_candidates <- all_cols
  }

  cand_tbl <- lapply(key_candidates, function(k) {
    present_in <- vapply(standardized_tables, function(df) k %in% names(df), logical(1))
    if (sum(present_in) < 2) {
      return(NULL)
    }

    non_missing <- vapply(standardized_tables[present_in], function(df) {
      vals <- trimws(as.character(df[[k]]))
      mean(!is.na(vals) & nzchar(vals))
    }, numeric(1))

    uniqueness <- vapply(standardized_tables[present_in], function(df) {
      vals <- trimws(as.character(df[[k]]))
      vals <- vals[!is.na(vals) & nzchar(vals)]
      if (length(vals) == 0) return(0)
      length(unique(vals)) / length(vals)
    }, numeric(1))

    data.frame(
      candidate_key = k,
      files_present = sum(present_in),
      mean_non_missing = round(mean(non_missing), 3),
      mean_uniqueness = round(mean(uniqueness), 3),
      score = round(sum(present_in) * mean(non_missing) * mean(uniqueness), 4),
      stringsAsFactors = FALSE
    )
  })

  cand_tbl <- dplyr::bind_rows(cand_tbl)
  if (!is.data.frame(cand_tbl) || nrow(cand_tbl) == 0) {
    return(list(key = NULL, candidates = data.frame()))
  }

  cand_tbl <- cand_tbl %>% arrange(desc(score), desc(files_present), desc(mean_non_missing))
  list(key = cand_tbl$candidate_key[[1]], candidates = cand_tbl)
}

standardize_table_columns <- function(df, map_tbl, source_file) {
  if (!is.data.frame(df) || nrow(df) == 0) {
    return(df)
  }

  rename_to <- ifelse(
    !is.na(map_tbl$mapped_dwc_term) & nzchar(map_tbl$mapped_dwc_term),
    map_tbl$mapped_dwc_term,
    ifelse(!is.na(map_tbl$mapped_bien_field) & nzchar(map_tbl$mapped_bien_field), map_tbl$mapped_bien_field, map_tbl$input_column)
  )

  names(df) <- make.unique(rename_to, sep = "_")
  df$source_file <- source_file
  df$source_row_id <- seq_len(nrow(df))

  if ("measurementValue" %in% names(df) && !"measurementType" %in% names(df)) {
    df$measurementType <- "diameter_at_breast_height"
  }
  if ("measurementValue" %in% names(df) && !"measurementUnit" %in% names(df)) {
    df$measurementUnit <- "cm"
  }

  df
}

merge_standardized_tables <- function(std_tables, merge_key) {
  if (length(std_tables) == 0) {
    return(data.frame())
  }

  merged <- std_tables[[1]]
  if (length(std_tables) == 1) {
    return(merged)
  }

  for (i in 2:length(std_tables)) {
    next_tbl <- std_tables[[i]]
    common_cols <- intersect(names(merged), names(next_tbl))

    by_cols <- character(0)
    if (!is.null(merge_key) && nzchar(merge_key) && merge_key %in% common_cols) {
      by_cols <- merge_key
    } else if (length(common_cols) > 0) {
      by_cols <- common_cols[common_cols %in% c("plotName", "occurrenceID", "scientificName", "scrubbed_species_binomial")]
      if (length(by_cols) > 1) {
        by_cols <- by_cols[[1]]
      }
    }

    if (length(by_cols) == 0) {
      merged <- dplyr::bind_rows(merged, next_tbl)
    } else {
      merged <- dplyr::full_join(merged, next_tbl, by = by_cols)
    }
  }

  merged
}

augment_tnrs_and_coordinates <- function(df, timeout_sec = 8, taxon_cap = 40) {
  if (!is.data.frame(df) || nrow(df) == 0) {
    return(df)
  }

  taxon_col <- find_first_col(df, c("scientificName", "scrubbed_species_binomial", "species", "taxon"))
  if (!is.null(taxon_col)) {
    taxa <- unique(trimws(as.character(df[[taxon_col]])))
    taxa <- taxa[!is.na(taxa) & nzchar(taxa)]
    taxa <- utils::head(taxa, taxon_cap)

    tax_lookup <- lapply(taxa, function(sp) {
      tax_res <- safe_bien_call(BIEN_taxonomy_species(sp), timeout_sec = timeout_sec)
      if (is.data.frame(tax_res) && nrow(tax_res) > 0) {
        return(data.frame(
          taxon_submitted = sp,
          taxon_matched = as.character(tax_res$scrubbed_species_binomial[[1]]),
          taxon_family = as.character(tax_res$scrubbed_family[[1]]),
          taxon_match_status = "exact_or_backbone_match",
          stringsAsFactors = FALSE
        ))
      }

      suggestion <- find_best_species_spelling(sp, timeout_sec = timeout_sec)
      if (is.list(suggestion) && identical(suggestion$status, "suggested")) {
        return(data.frame(
          taxon_submitted = sp,
          taxon_matched = as.character(suggestion$suggested_name),
          taxon_family = NA_character_,
          taxon_match_status = paste0("suggested_", suggestion$confidence),
          stringsAsFactors = FALSE
        ))
      }

      data.frame(
        taxon_submitted = sp,
        taxon_matched = NA_character_,
        taxon_family = NA_character_,
        taxon_match_status = "unresolved",
        stringsAsFactors = FALSE
      )
    })

    tax_lookup <- dplyr::bind_rows(tax_lookup)
    df$taxon_submitted <- as.character(df[[taxon_col]])
    df <- dplyr::left_join(df, tax_lookup, by = "taxon_submitted")
  } else {
    df$taxon_submitted <- NA_character_
    df$taxon_matched <- NA_character_
    df$taxon_family <- NA_character_
    df$taxon_match_status <- "no_taxon_column"
  }

  lat_col <- find_first_col(df, c("decimalLatitude", "latitude", "lat"))
  lon_col <- find_first_col(df, c("decimalLongitude", "longitude", "long", "lon"))

  lat_vals <- if (!is.null(lat_col)) suppressWarnings(as.numeric(df[[lat_col]])) else rep(NA_real_, nrow(df))
  lon_vals <- if (!is.null(lon_col)) suppressWarnings(as.numeric(df[[lon_col]])) else rep(NA_real_, nrow(df))

  coord_valid <- !is.na(lat_vals) & !is.na(lon_vals) & lat_vals >= -90 & lat_vals <= 90 & lon_vals >= -180 & lon_vals <= 180
  coord_issue <- ifelse(is.na(lat_vals) | is.na(lon_vals), "missing_coordinates", ifelse(coord_valid, NA_character_, "out_of_bounds"))

  df$decimalLatitude <- lat_vals
  df$decimalLongitude <- lon_vals
  df$coordinate_valid_basic <- coord_valid
  df$coordinate_issue <- coord_issue

  df
}

build_staging_table <- function(df) {
  if (!is.data.frame(df) || nrow(df) == 0) {
    return(data.frame())
  }

  event_col <- find_first_col(df, c("eventDate", "date_collected", "date", "collection_date"))
  basis_col <- find_first_col(df, c("basisOfRecord", "observation_type", "record_type"))
  occ_id_col <- find_first_col(df, c("occurrenceID", "occurrence_id", "record_id", "id"))
  dataset_col <- find_first_col(df, c("dataset", "project", "survey"))
  trait_name_col <- find_first_col(df, c("measurementType", "trait_name", "trait", "variable"))
  trait_val_col <- find_first_col(df, c("measurementValue", "trait_value", "value", "dbh", "diameter"))
  trait_unit_col <- find_first_col(df, c("measurementUnit", "unit", "units", "trait_unit"))
  plot_col <- find_first_col(df, c("plotName", "plot_name", "plot", "site_name"))

  staging <- data.frame(
    staging_record_id = seq_len(nrow(df)),
    source_file = if ("source_file" %in% names(df)) as.character(df$source_file) else NA_character_,
    source_row_id = if ("source_row_id" %in% names(df)) suppressWarnings(as.integer(df$source_row_id)) else NA_integer_,
    plotName = if (!is.null(plot_col)) as.character(df[[plot_col]]) else NA_character_,
    scientificName_submitted = if ("taxon_submitted" %in% names(df)) as.character(df$taxon_submitted) else NA_character_,
    scientificName_matched = if ("taxon_matched" %in% names(df)) as.character(df$taxon_matched) else NA_character_,
    scientificName_match_status = if ("taxon_match_status" %in% names(df)) as.character(df$taxon_match_status) else NA_character_,
    scientificFamily_matched = if ("taxon_family" %in% names(df)) as.character(df$taxon_family) else NA_character_,
    decimalLatitude = if ("decimalLatitude" %in% names(df)) suppressWarnings(as.numeric(df$decimalLatitude)) else NA_real_,
    decimalLongitude = if ("decimalLongitude" %in% names(df)) suppressWarnings(as.numeric(df$decimalLongitude)) else NA_real_,
    coordinate_valid_basic = if ("coordinate_valid_basic" %in% names(df)) as.logical(df$coordinate_valid_basic) else NA,
    coordinate_issue = if ("coordinate_issue" %in% names(df)) as.character(df$coordinate_issue) else NA_character_,
    eventDate = if (!is.null(event_col)) as.character(df[[event_col]]) else NA_character_,
    basisOfRecord = if (!is.null(basis_col)) as.character(df[[basis_col]]) else NA_character_,
    occurrenceID = if (!is.null(occ_id_col)) as.character(df[[occ_id_col]]) else NA_character_,
    dataset = if (!is.null(dataset_col)) as.character(df[[dataset_col]]) else NA_character_,
    measurementType = if (!is.null(trait_name_col)) as.character(df[[trait_name_col]]) else NA_character_,
    measurementValue = if (!is.null(trait_val_col)) as.character(df[[trait_val_col]]) else NA_character_,
    measurementUnit = if (!is.null(trait_unit_col)) as.character(df[[trait_unit_col]]) else NA_character_,
    ingestion_timestamp_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    stringsAsFactors = FALSE
  )

  staging
}

run_ingest_workflow <- function(file_info) {
  if (is.null(file_info) || nrow(file_info) == 0) {
    return(NULL)
  }

  bien_fields <- get_bien_reference_fields(timeout_sec = 12)

  tables <- lapply(seq_len(nrow(file_info)), function(i) {
    this_path <- file_info$datapath[[i]]
    this_name <- file_info$name[[i]]
    df <- tryCatch(
      read.csv(this_path, stringsAsFactors = FALSE, strip.white = TRUE, na.strings = c("", "NA", "NULL")),
      error = function(e) data.frame()
    )
    df <- drop_empty_rows(df)
    list(name = this_name, data = df)
  })

  valid_tables <- tables[vapply(tables, function(x) is.data.frame(x$data) && nrow(x$data) > 0, logical(1))]
  if (length(valid_tables) == 0) {
    return(NULL)
  }

  map_list <- lapply(valid_tables, function(tbl) {
    build_column_mapping(tbl$data, tbl$name, bien_reference_fields = bien_fields)
  })
  map_df <- dplyr::bind_rows(map_list)

  std_tables <- lapply(seq_along(valid_tables), function(i) {
    standardize_table_columns(valid_tables[[i]]$data, map_list[[i]], valid_tables[[i]]$name)
  })
  names(std_tables) <- vapply(valid_tables, function(x) x$name, character(1))

  merge_info <- suggest_merge_key(map_list, std_tables)
  merged <- merge_standardized_tables(std_tables, merge_info$key)
  merged_aug <- augment_tnrs_and_coordinates(merged, timeout_sec = 8, taxon_cap = 40)
  staging <- build_staging_table(merged_aug)

  file_summary <- data.frame(
    source_file = vapply(valid_tables, function(x) x$name, character(1)),
    n_rows = vapply(valid_tables, function(x) nrow(x$data), numeric(1)),
    n_columns = vapply(valid_tables, function(x) ncol(x$data), numeric(1)),
    dwc_mapped_columns = vapply(map_list, function(x) sum(!is.na(x$mapped_dwc_term)), numeric(1)),
    bien_mapped_columns = vapply(map_list, function(x) sum(!is.na(x$mapped_bien_field)), numeric(1)),
    bien_exact_name_matches = vapply(map_list, function(x) sum(isTRUE(x$bien_exact_name_match)), numeric(1)),
    stringsAsFactors = FALSE
  )

  bien_schema_check <- tryCatch(
    BIEN_metadata_match_data(
      old = as.data.frame(merged_aug[0, , drop = FALSE]),
      new = as.data.frame(stats::setNames(as.list(rep(NA_character_, length(bien_fields))), bien_fields)),
      return = "logical"
    ),
    error = function(e) NA
  )

  list(
    file_summary = file_summary,
    column_map = map_df,
    merge_candidates = merge_info$candidates,
    merge_key = merge_info$key,
    merged = merged_aug,
    staging = staging,
    bien_schema_check = bien_schema_check
  )
}

# Main Shiny user interface: query controls plus linked tabs for occurrence, trait, and range evidence.
ui <- fluidPage(
  tags$head(
    tags$style(HTML("
      :root {
        --bien-blue: #2f79b7;
        --bien-blue-deep: #1f5b8f;
        --bien-green: #74b64a;
        --bien-green-deep: #4e8c2c;
        --bien-sky: #e9f4ff;
        --bien-mint: #eef9e8;
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
      .bien-header-copy {
        min-width: 0;
      }
      .bien-title {
        margin: 0;
        color: var(--bien-blue-deep);
        font-weight: 700;
        font-size: 2em;
        line-height: 1.2;
      }
      .bien-subtitle {
        margin: 8px 0 0 0;
        color: #426988;
        font-size: 1.05em;
        line-height: 1.4;
        max-width: 920px;
      }
      .bien-logo {
        height: 62px;
        width: auto;
        filter: drop-shadow(0 2px 4px rgba(0, 0, 0, 0.12));
      }
      .bien-logo-fallback {
        display: none;
      }
      .well {
        border: 1px solid var(--panel-border);
        background: linear-gradient(180deg, #f5fbf3 0%, #f7fcff 100%);
        box-shadow: 0 2px 8px rgba(47, 121, 183, 0.08);
      }
      .btn-primary {
        background: linear-gradient(90deg, var(--bien-blue), var(--bien-green));
        border-color: var(--bien-blue-deep);
      }
      .btn-warning {
        background: #f4f8ef;
        border-color: var(--bien-green-deep);
        color: #3a6520;
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
      .nav-tabs > li:nth-child(8) > a { border-left: 6px solid #2a83a8; }
      .nav-tabs > li:nth-child(9) > a { border-left: 6px solid #6f8f3f; }
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
      .nav-tabs > li.active:nth-child(7) > a:hover,
      .nav-tabs > li.active:nth-child(9) > a,
      .nav-tabs > li.active:nth-child(9) > a:focus,
      .nav-tabs > li.active:nth-child(9) > a:hover {
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
      .bien-overview-card {
        background: linear-gradient(180deg, #f0f7ff 0%, #f5fbef 100%);
        border: 1px solid #b7d2e8;
        border-radius: 8px;
        padding: 16px 20px;
        margin-bottom: 18px;
      }
      .bien-feature-icon { font-size: 1.6em; margin-right: 8px; }
      .bien-link-card {
        background: linear-gradient(180deg, #deefff 0%, #eaf7df 100%);
        border: 1px solid #9fc9e8;
        border-radius: 8px;
        padding: 14px 18px;
        margin-bottom: 12px;
      }
      .bien-pub-card {
        background: linear-gradient(180deg, #e7f4ff 0%, #eaf8df 100%);
        border: 1px solid #9fcca7;
        border-radius: 8px;
        padding: 14px 18px;
        margin-bottom: 12px;
        font-size: 0.97em;
      }
      .ponderosa-section {
        background: linear-gradient(180deg, #ffffff 0%, #f2f9ff 100%);
        border: 1px solid #a5d4a6;
        border-radius: 8px;
        padding: 18px 22px;
        margin-bottom: 18px;
      }
      .source-bar { height: 22px; border-radius: 4px; margin-bottom: 5px; display: inline-block; }
      .bien-inline-tip {
        cursor: help;
        color: #3f6582;
        font-weight: 700;
        margin-left: 4px;
        border-bottom: 1px dotted #7ca0ba;
      }
      .bien-inline-tip:focus {
        outline: 2px solid #7baed3;
        outline-offset: 1px;
      }
      .bien-tip-bubble {
        position: absolute;
        z-index: 3000;
        max-width: 320px;
        padding: 8px 10px;
        border-radius: 6px;
        border: 1px solid #9fc0d8;
        background: #f8fcff;
        color: #1f3f57;
        box-shadow: 0 3px 10px rgba(0, 0, 0, 0.14);
        font-size: 0.88em;
        line-height: 1.35;
      }
      .bien-species-input .selectize-input {
        min-height: 50px;
        padding: 10px 14px;
        font-size: 1.08em;
        line-height: 1.4;
      }
      .bien-species-input .selectize-input > input {
        font-size: 1.08em;
      }
      .bien-species-input .selectize-dropdown,
      .bien-species-input .selectize-dropdown-content {
        font-size: 1.02em;
      }
      .bien-action-btn {
        width: 100%;
        border-radius: 10px;
        padding: 11px 18px;
        font-weight: 700;
        border-width: 1px;
        text-shadow: 0 1px 0 rgba(0, 0, 0, 0.2);
        transition: transform 0.08s ease, box-shadow 0.08s ease, filter 0.2s ease;
      }
      .bien-action-btn:hover,
      .bien-action-btn:focus {
        filter: brightness(1.04);
        transform: translateY(-1px);
      }
      .bien-action-btn:active {
        transform: translateY(2px);
      }
      .bien-query-btn {
        color: #fff;
        border-color: var(--bien-blue-deep);
        background: linear-gradient(180deg, #4f98d8 0%, var(--bien-blue) 55%, var(--bien-blue-deep) 100%);
        box-shadow: 0 4px 0 #18456f, 0 8px 16px rgba(31, 91, 143, 0.25);
      }
      .bien-query-btn:hover,
      .bien-query-btn:focus {
        box-shadow: 0 5px 0 #18456f, 0 10px 16px rgba(31, 91, 143, 0.24);
      }
      .bien-query-btn:active {
        box-shadow: 0 2px 0 #18456f, 0 4px 8px rgba(31, 91, 143, 0.2);
      }
      .bien-random-btn {
        color: #fff;
        border-color: var(--bien-green-deep);
        background: linear-gradient(180deg, #9acf6d 0%, var(--bien-green) 55%, var(--bien-green-deep) 100%);
        box-shadow: 0 4px 0 #386620, 0 8px 16px rgba(62, 112, 36, 0.24);
      }
      .bien-random-btn:hover,
      .bien-random-btn:focus {
        box-shadow: 0 5px 0 #386620, 0 10px 16px rgba(62, 112, 36, 0.22);
      }
      .bien-random-btn:active {
        box-shadow: 0 2px 0 #386620, 0 4px 8px rgba(62, 112, 36, 0.18);
      }
      .bien-help-btn {
        color: #1f4f73;
        text-shadow: none;
        border-color: #92b7d6;
        background: linear-gradient(180deg, #f8fcff 0%, #edf6ff 100%);
        box-shadow: 0 3px 0 #bfd4e7, 0 8px 14px rgba(34, 88, 128, 0.12);
      }
      .bien-help-btn:hover,
      .bien-help-btn:focus {
        color: #163d5a;
        box-shadow: 0 4px 0 #bfd4e7, 0 10px 14px rgba(34, 88, 128, 0.14);
      }
      .bien-help-btn:active {
        box-shadow: 0 2px 0 #bfd4e7, 0 4px 8px rgba(34, 88, 128, 0.1);
      }
    "))
  ),
  tags$div(
    class = "page-header",
    tags$div(
      class = "bien-header-brand",
      tags$img(
        src = "bien.png",
        class = "bien-logo",
        alt = "BIEN logo",
        onerror = "this.style.display='none';"
      ),
      tags$div(
        class = "bien-header-copy",
        tags$h1(class = "bien-title", "Species-Level Observation Explorer"),
        tags$p(
          class = "bien-subtitle",
          "Query BIEN species occurrences, traits, and range evidence with the same visual language as the BIEN Traits portal."
        )
      )
    )
  ),
  sidebarLayout(
    sidebarPanel(
      div(
        class = "bien-species-input",
        selectizeInput(
          "species",
          "Species name",
          choices = STARTUP_SPECIES,
          selected = STARTUP_SPECIES,
          width = "100%",
          options = list(
            create = TRUE,
            createOnBlur = TRUE,
            maxOptions = 2000,
            placeholder = "Start typing accepted BIEN species names..."
          )
        )
      ),
      actionButton("feeling_lucky_species", "Random species", class = "btn btn-success btn-lg bien-action-btn bien-random-btn"),
      checkboxInput("enable_taxon_autocorrect", "Suggest closest BIEN taxon if no exact match", value = TRUE),
      uiOutput("spelling_suggestion_ui"),
      actionButton("run_query", "Query BIEN", class = "btn btn-primary btn-lg bien-action-btn bien-query-btn"),
      tags$div(
        style = "margin:10px 0 12px 0;",
        actionButton("open_tab_help", "Help", class = "btn btn-info btn-lg bien-action-btn bien-help-btn")
      ),
      uiOutput("retry_bien_ui"),
      tags$script(HTML("$(document).on('keydown', '#species-selectized', function(e) { if (e.key === 'Enter') { $('#run_query').click(); return false; } });")),
      tags$script(HTML(
        "(function() {
          function bindFallbackTip(el) {
            if (!el || el.dataset.bienTipBound === '1') return;

            function ensureBubble() {
              var bubble = document.getElementById('bien-inline-tip-bubble');
              if (!bubble) {
                bubble = document.createElement('div');
                bubble.id = 'bien-inline-tip-bubble';
                bubble.className = 'bien-tip-bubble';
                bubble.style.display = 'none';
                document.body.appendChild(bubble);
              }
              return bubble;
            }

            function showBubble() {
              var txt = el.getAttribute('data-bien-tip');
              if (!txt) return;
              var bubble = ensureBubble();
              bubble.textContent = txt;
              bubble.style.display = 'block';
              var rect = el.getBoundingClientRect();
              var top = window.scrollY + rect.top - 6;
              var left = window.scrollX + rect.right + 10;
              bubble.style.top = top + 'px';
              bubble.style.left = left + 'px';
            }

            function hideBubble() {
              var bubble = document.getElementById('bien-inline-tip-bubble');
              if (bubble) bubble.style.display = 'none';
            }

            el.addEventListener('mouseenter', showBubble);
            el.addEventListener('mouseleave', hideBubble);
            el.addEventListener('focus', showBubble);
            el.addEventListener('blur', hideBubble);
            el.addEventListener('click', function(e) {
              var bubble = document.getElementById('bien-inline-tip-bubble');
              if (bubble && bubble.style.display === 'block') {
                hideBubble();
              } else {
                showBubble();
              }
              e.preventDefault();
              e.stopPropagation();
            });
            el.addEventListener('keydown', function(e) {
              if (e.key === 'Escape') hideBubble();
            });

            el.dataset.bienTipBound = '1';
          }

          document.addEventListener('click', function(e) {
            if (!e.target.closest || !e.target.closest('.bien-inline-tip')) {
              var bubble = document.getElementById('bien-inline-tip-bubble');
              if (bubble) bubble.style.display = 'none';
            }
          });

          function initBienTooltips() {
            document.querySelectorAll('.bien-inline-tip').forEach(function(el) {
              bindFallbackTip(el);
            });
          }

          jQuery(document).on('shiny:connected', initBienTooltips);
          jQuery(document).on('shiny:value shiny:recalculated', initBienTooltips);
          jQuery(initBienTooltips);
        })();"
      )),
      tags$div(
        style = "font-size:0.92em;color:#555;margin:6px 0 10px 0;",
        "Change filters, then click Query BIEN."
      ),
      tags$hr(),
      tags$h4("Settings", style = "margin:0 0 8px 0;font-size:1.08em;"),
      tags$h5("Filters", style = "margin:6px 0 6px 0;font-size:0.98em;color:#444;"),
      checkboxInput("use_default_bien_filter_profile", compact_label("Conservative default profile", "Uses a biodiversity-conservative screen: keeps native and non-introduced records, excludes cultivated records, and keeps only BIEN geovalid coordinates."), value = TRUE),
      conditionalPanel(
        condition = "input.use_default_bien_filter_profile == false",
        checkboxInput("use_introduced_filter", compact_label("Filter by native vs introduced", "Controls whether establishment status is enforced. If disabled, records are kept regardless of native or introduced status."), value = TRUE),
        conditionalPanel(
          condition = "input.use_introduced_filter == true",
          checkboxInput("natives_only", compact_label("Keep native only", "When enabled, retains native records and excludes BIEN records marked introduced."), value = TRUE)
        ),
        checkboxInput("use_cultivated_filter", compact_label("Filter by cultivated vs wild", "Controls whether cultivation status is enforced. If disabled, both cultivated and non-cultivated records are retained."), value = TRUE),
        conditionalPanel(
          condition = "input.use_cultivated_filter == true",
          checkboxInput("include_cultivated", compact_label("Include cultivated records", "When disabled, ornamental or managed plantings are excluded so outputs emphasize wild occurrences."), value = FALSE)
        ),
        checkboxInput("only_plot_observations", compact_label("Show only plot/survey records", "Keeps only formal plot/survey observations and drops opportunistic records (for example, casual sightings)."), value = FALSE),
        checkboxInput("only_geovalid", compact_label("Keep only BIEN geovalid coordinates", "Excludes points BIEN flags as geospatially invalid (for example, swapped or out-of-range coordinates)."), value = TRUE),
        checkboxInput("exclude_human_observation_records", compact_label("Exclude HumanObservation + iNaturalist", "Removes human-observed and iNaturalist-sourced records, emphasizing curated plot/herbarium-style data streams."), value = FALSE)
      ),
      tags$h5("Sampling & map", style = "margin:10px 0 6px 0;font-size:0.98em;color:#444;"),
      checkboxInput("show_sampling_settings", compact_label("Show sampling & map settings", "Turn on to customize app-sample size, map cap, and balancing strategy."), value = FALSE),
      conditionalPanel(
        condition = "input.show_sampling_settings == true",
        numericInput("occurrence_limit", compact_label("App sample size", "Maximum occurrence rows retained in the app sample."), value = 1000, min = 200, max = 50000, step = 200),
        numericInput("map_point_cap", compact_label("Map point cap", "Maximum number of points rendered on the map."), value = 800, min = 100, max = 50000, step = 100),
        checkboxInput("fast_large_species_mode", compact_label("Fast mode for large species", "Uses shorter waits and smaller first-pass BIEN pulls."), value = TRUE),
        checkboxInput("randomize_occurrence_sample", compact_label("Use randomized/balanced subsampling", "If off, app keeps BIEN-returned order (head sampling)."), value = TRUE),
        conditionalPanel(
          condition = "input.randomize_occurrence_sample == true",
          selectInput("map_sampling_method", compact_label("Balancing method", "How to balance the app sample when many records are available."), choices = c("Datasource" = "datasource", "Observation type" = "observation_type", "Observation category" = "observation_category", "Random sample" = "random", "First returned" = "head"), selected = "datasource")
        ),
        selectInput("map_color_by", compact_label("Map color scheme", "Color points by broad category or raw BIEN observation_type."), choices = c("Observation category" = "category", "Raw BIEN observation_type" = "type"), selected = "category")
      ),
      tags$h5("Traits, range & runtime", style = "margin:10px 0 6px 0;font-size:0.98em;color:#444;"),
      checkboxInput("show_runtime_settings", compact_label("Show trait/range/runtime settings", "Turn on to customize trait limits, optional range query behavior, and timeout."), value = FALSE),
      conditionalPanel(
        condition = "input.show_runtime_settings == true",
        numericInput("trait_limit", compact_label("Trait sample cap", "Maximum trait rows requested for the current species."), value = 1000, min = 100, max = 50000, step = 100),
        checkboxInput("include_range_query", compact_label("Load BIEN range on Range tab", "Optional BIEN range retrieval when opening the Range tab."), value = TRUE),
        numericInput("query_timeout", compact_label("Per-step timeout (sec)", "Timeout budget per BIEN retrieval step."), value = 90, min = 30, max = 300, step = 15)
      ),
      width = 3
    ),
    mainPanel(
      tabsetPanel(
        id = "main_tabs",
        selected = "Occurrence",

        # ── Overview & About tab ──────────────────────────────────────────────
        tabPanel(
          "Overview & About",
          br(),

          # Hero intro
          tags$div(
            class = "bien-overview-card",
            tags$h3(style = "margin-top:0;color:#2c7a34;", "What can you learn from this app?"),
            tags$p(style = "max-width:900px;font-size:1.05em;",
              "This app lets you explore species-level biodiversity evidence from the ",
              tags$a("BIEN database", href = "https://biendata.org/", target = "_blank"),
              " — occurrence records, trait measurements, and mapped ranges — in one place,",
              " without writing any code. Type any plant species name and the app immediately surfaces",
              " where it has been observed, what traits BIEN has measured, and how confident that evidence is."
            ),
            tags$p(style = "max-width:900px;color:#555;",
              tags$strong("Live app: "),
              tags$a("https://benquist.shinyapps.io/bien-species-shinyapp/",
                     href = "https://benquist.shinyapps.io/bien-species-shinyapp/", target = "_blank")
            )
          ),

          # Pinus ponderosa worked example
          tags$div(
            class = "ponderosa-section",
            tags$h4(style = "color:#2c5f2e;margin-top:0;",
              tags$em("Pinus ponderosa"), " (Ponderosa Pine) — a worked example"
            ),
            tags$p(style = "color:#555;max-width:900px;",
              "Ponderosa Pine is one of the most widespread and ecologically important conifers in western North America,",
              " making it an excellent demonstration species for the app. Here is what a typical query returns:"
            ),
            fluidRow(
              column(4,
                tags$div(
                  class = "bien-overview-card", style = "height:190px;",
                  tags$span(class = "bien-feature-icon", "\U0001F5FA\uFE0F"),
                  tags$strong("Occurrence Map"),
                  tags$p(style = "font-size:0.93em;color:#444;margin-top:6px;",
                    "View species-level occurrence records - toggle to view geo-validated occurrence records, native and non-native records.",
                    " Records are colored by source class (plot surveys, herbarium specimens, iNaturalist citizen-science observations)."
                  )
                )
              ),
              column(4,
                tags$div(
                  class = "bien-overview-card", style = "height:190px;",
                  tags$span(class = "bien-feature-icon", "\U0001F4CA"),
                  tags$strong("Trait Distributions"),
                  tags$p(style = "font-size:0.93em;color:#444;margin-top:6px;",
                    "BIEN returns continuous traits including stem wood density (g/cm\U00B3),",
                    " leaf nitrogen content (mg/g), and seed mass (mg).",
                    " The Traits tab draws histograms per trait-unit combination so you can see the full measured range,",
                    " typical values, and outliers at a glance."
                  )
                )
              ),
              column(4,
                tags$div(
                  class = "bien-overview-card", style = "height:190px;",
                  tags$span(class = "bien-feature-icon", "\U0001F4CB"),
                  tags$strong("Observation Sources"),
                  tags$p(style = "font-size:0.93em;color:#444;margin-top:6px;",
                    "The Observations tab starts with a source-composition table that breaks down how many records come from each datasource.",
                    " For Ponderosa Pine, FIA forest inventory plots typically provide the largest share,",
                    " followed by herbarium collections and citizen-science platforms such as iNaturalist."
                  )
                )
              )
            ),

            # Simulated source-mix bar chart (static illustration)
            tags$h5(style = "margin-top:8px;color:#444;", "Example record-source composition (illustrative)"),
            tags$div(
              style = "max-width:580px;",
              tags$div(style = "margin-bottom:4px;font-size:0.9em;",
                tags$span(class = "source-bar", style = "width:210px;background:#4caf50;"),
                tags$span(style = "margin-left:8px;", "FIA / Forest inventory plots  ~42 %")
              ),
              tags$div(style = "margin-bottom:4px;font-size:0.9em;",
                tags$span(class = "source-bar", style = "width:140px;background:#2196f3;"),
                tags$span(style = "margin-left:8px;", "Herbarium specimens  ~28 %")
              ),
              tags$div(style = "margin-bottom:4px;font-size:0.9em;",
                tags$span(class = "source-bar", style = "width:95px;background:#ff9800;"),
                tags$span(style = "margin-left:8px;", "iNaturalist / citizen-science  ~19 %")
              ),
              tags$div(style = "margin-bottom:4px;font-size:0.9em;",
                tags$span(class = "source-bar", style = "width:50px;background:#9c27b0;"),
                tags$span(style = "margin-left:8px;", "Literature / checklists  ~11 %")
              ),
              tags$p(style = "font-size:0.8em;color:#888;margin-top:4px;",
                "Proportions are illustrative. Actual values depend on your filter settings and BIEN query date."
              )
            ),

            tags$hr(style = "margin:12px 0;"),
            tags$p(style = "font-size:0.93em;color:#555;max-width:900px;",
              tags$strong("Try it: "),
              "Type ", tags$code("Pinus ponderosa"), " in the Species name box on the left,",
              " leave filters at their defaults (native, non-cultivated, geovalid),",
              " and click ", tags$strong("Query BIEN"), ".",
              " Then explore the Occurrence Map, Observations, and Traits tabs."
            )
          ),

          # App features summary
          tags$div(
            class = "bien-overview-card",
            tags$h4(style = "margin-top:0;", "What the app gives you"),
            tags$table(
              style = "width:100%;border-collapse:collapse;font-size:0.97em;",
              tags$thead(
                tags$tr(
                  tags$th(style = "text-align:left;padding:6px 10px;background:#e9ecef;border-radius:4px;", "Tab"),
                  tags$th(style = "text-align:left;padding:6px 10px;background:#e9ecef;", "What you learn")
                )
              ),
              tags$tbody(
                tags$tr(tags$td(style = "padding:5px 10px;border-bottom:1px solid #eee;", tags$strong("Occurrence Map")),
                         tags$td(style = "padding:5px 10px;border-bottom:1px solid #eee;", "Where the species has been observed; which record types dominate; whether the map shows all points or a balanced sample")),
                tags$tr(tags$td(style = "padding:5px 10px;border-bottom:1px solid #eee;", tags$strong("Summary Statistics")),
                         tags$td(style = "padding:5px 10px;border-bottom:1px solid #eee;", "Total record counts, QA losses, active filter mode, and optional BIEN-wide totals")),
                tags$tr(tags$td(style = "padding:5px 10px;border-bottom:1px solid #eee;", tags$strong("Observations")),
                         tags$td(style = "padding:5px 10px;border-bottom:1px solid #eee;", "Source-composition summary at the top plus searchable raw occurrence records with provenance and coordinate columns")),
                tags$tr(tags$td(style = "padding:5px 10px;border-bottom:1px solid #eee;", tags$strong("Traits")),
                         tags$td(style = "padding:5px 10px;border-bottom:1px solid #eee;", "Raw trait measurements and a compact summary table by trait name and unit")),
                tags$tr(tags$td(style = "padding:5px 10px;border-bottom:1px solid #eee;", tags$strong("Range")),
                         tags$td(style = "padding:5px 10px;border-bottom:1px solid #eee;", "BIEN mapped range polygon when available, useful when occurrence coordinates are sparse")),
                tags$tr(tags$td(style = "padding:5px 10px;border-bottom:1px solid #eee;", tags$strong("Download")),
                         tags$td(style = "padding:5px 10px;border-bottom:1px solid #eee;", "Download occurrence and trait datasets and matching reproducible R code")),
                tags$tr(tags$td(style = "padding:5px 10px;", tags$strong("Reconciliation table")),
                         tags$td(style = "padding:5px 10px;", "Top section of the Occurrence tab showing BIEN name matching details for auditing"))
              )
            )
          ),

          # Learn more / links
          tags$div(
            class = "bien-overview-card",
            tags$h4(style = "margin-top:0;", "Learn more about BIEN"),
            tags$div(
              class = "bien-link-card",
              tags$strong("\U0001F30E BIEN Data Portal"),
              tags$br(),
              tags$a("https://biendata.org/", href = "https://biendata.org/", target = "_blank"),
              tags$p(style = "margin:4px 0 0 0;font-size:0.93em;color:#444;",
                "The main BIEN data portal — browse species, traits, and range data, and access the full BIEN occurrence database for the Americas.")
            ),
            tags$div(
              class = "bien-link-card",
              tags$strong("\U0001F4BB App source code (GitHub)"),
              tags$br(),
              tags$a("https://github.com/benquist/BIEN-SpeciesShinyApp",
                     href = "https://github.com/benquist/BIEN-SpeciesShinyApp", target = "_blank"),
              tags$p(style = "margin:4px 0 0 0;font-size:0.93em;color:#444;",
                "Full source code for this Shiny app, including workflow documentation, QA steps, and interpretation caveats.")
            ),
            tags$div(
              class = "bien-link-card",
              tags$strong("\U0001F52C BIEN Project — NCEAS"),
              tags$br(),
              tags$a("https://bien.nceas.ucsb.edu/bien/biendata/previous-bien-versions/bien-4/",
                     href = "https://bien.nceas.ucsb.edu/bien/biendata/previous-bien-versions/bien-4/", target = "_blank"),
              tags$p(style = "margin:4px 0 0 0;font-size:0.93em;color:#444;",
                "Overview of the BIEN research group at NCEAS, the BIEN 4 data release, methods, and contributing teams.")
            ),
            tags$div(
              class = "bien-link-card",
              tags$strong("\U0001F4F0 Methods Blog Feature"),
              tags$br(),
              tags$a("https://methodsblog.com/2026/03/30/building-the-infrastructure-for-reproducible-biodiversity-science/",
                     href = "https://methodsblog.com/2026/03/30/building-the-infrastructure-for-reproducible-biodiversity-science/", target = "_blank"),
              tags$p(style = "margin:4px 0 0 0;font-size:0.93em;color:#444;",
                "Methods in Ecology and Evolution blog post on building infrastructure for reproducible biodiversity science.")
            ),
            tags$div(
              class = "bien-pub-card",
              tags$strong("\U0001F4D6 Latest BIEN publication"),
              tags$br(),
              tags$em("Enquist et al. (2026). BIEN: Botanical Information and Ecology Network. Methods in Ecology and Evolution."),
              tags$br(),
              tags$a("https://besjournals.onlinelibrary.wiley.com/doi/abs/10.1111/2041-210x.70274",
                     href = "https://besjournals.onlinelibrary.wiley.com/doi/abs/10.1111/2041-210x.70274", target = "_blank"),
              tags$p(style = "margin:4px 0 0 0;font-size:0.93em;color:#444;",
                "Peer-reviewed methods paper describing the BIEN database, data standards, and workflow. Cite this when using BIEN data in publications.")
            )
          )
        ),
        # ─────────────────────────────────────────────────────────────────────

        tabPanel(
          "Occurrence",
          br(),
          leafletOutput("occurrence_map", height = 550),
          br(),
          uiOutput("overview_notice"),
          uiOutput("slow_query_alert"),
          br(),
          tags$p(
            style = "color:#555;max-width:900px;",
            "Summary statistics for the current map are shown below. Optional BIEN total counts and source fractions are loaded on demand."
          ),
          actionButton("load_summary_counts", "Load BIEN total counts and source mix (slower)", class = "btn-default btn-sm"),
          br(), br(),
          htmlOutput("query_summary")
        ),
        tabPanel(
          "Temporal Distribution",
          br(),
          tags$p(
            style = "color:#555;max-width:900px;",
            "Ten-year histogram of occurrence records by collection year and observation category. This is client-side only and does not trigger extra BIEN queries."
          ),
          fluidRow(
            column(
              3,
              tags$div(
                style = "background:#f9f9f9;padding:12px;border-radius:6px;",
                tags$h5(style = "margin-top:0;", "Temporal stats"),
                htmlOutput("temporal_stats"),
                br(),
                tags$h5(style = "margin-top:8px;", "Year range filter"),
                sliderInput(
                  "temporal_year_range",
                  "Filter by collection year",
                  min = 1700,
                  max = 2030,
                  value = c(1700, 2030),
                  step = 10
                )
              )
            ),
            column(9, plotOutput("temporal_histogram", height = 500))
          ),
          br(),
          tags$div(
            style = "font-size:0.9em;color:#666;background:#f0f4f8;padding:10px;border-radius:4px;",
            tags$strong("Note: "),
            "Rows without ", tags$code("date_collected"), " are excluded from this histogram but remain available in the observation table."
          )
        ),
        tabPanel(
          "Observations",
          br(),
          tags$h4("Reconciliation Table"),
          DTOutput("reconciliation_table"),
          br(),
          tags$h4("Observation Source Summary"),
          DTOutput("observation_source_table"),
          br(),
          tags$h4("Observation Records"),
          DTOutput("occurrence_table")
        ),
        tabPanel(
          "Traits",
          br(),
          tags$h4("Trait Summary"),
          DTOutput("trait_summary_table"),
          br(),
          tags$p(
            style = "color:#555;max-width:900px;",
            "Continuous traits only. Histograms are built from parsed single-number values and are kept separate by unit; categorical or mixed-format BIEN values stay in the tables below."
          ),
          plotOutput("trait_plot", height = 800),
          br(),
          tags$h4("Trait Visual Summary Table"),
          DTOutput("trait_visual_table"),
          br(),
          tags$h4("Trait Records"),
          DTOutput("trait_table")
        ),
        tabPanel(
          "Community",
          br(),
          tags$p(
            style = "color:#555;max-width:900px;",
            "Map shows records categorized as Plot / survey for the current species."
          ),
          uiOutput("community_notice"),
          uiOutput("community_map_ui"),
          br(),
          tags$h4("Plot Community Summary"),
          uiOutput("community_summary")
        ),
        tabPanel("Range", br(), verbatimTextOutput("range_text"), leafletOutput("range_map", height = 500)),
        tabPanel(
          "Download",
          br(),
          tags$style(HTML("#bien_query_code, #plot_query_code, #trait_query_code { max-height: 180px; overflow-y: auto; overflow-x: auto; }")),
          tags$h4("Occurrence Downloads"),
          tags$p(
            style = "color:#555;max-width:900px;",
            "This script reproduces the exact occurrence dataset currently shown in the Observations tab."
          ),
          downloadButton("download_occurrence_csv", "Download occurrence CSV", class = "btn btn-default btn-sm"),
          tags$span("\u00A0"),
          downloadButton("download_repro_script", "Download occurrence R code", class = "btn btn-default btn-sm"),
          br(), br(),
          verbatimTextOutput("bien_query_code"),
          br(),
          tags$h4("Plot Community Downloads"),
          tags$p(
            style = "color:#555;max-width:900px;",
            "Download all Plot / survey records for the current species and reproducible R code."
          ),
          downloadButton("download_plot_csv", "Download plot/community CSV", class = "btn btn-default btn-sm"),
          tags$span("\u00A0"),
          downloadButton("download_plot_repro_script", "Download plot/community R code", class = "btn btn-default btn-sm"),
          br(), br(),
          verbatimTextOutput("plot_query_code"),
          br(),
          tags$h4("Trait Downloads"),
          tags$p(
            style = "color:#555;max-width:900px;",
            "Download the current trait dataset and reproducible R code for the selected species."
          ),
          downloadButton("download_trait_csv", "Download trait CSV", class = "btn btn-default btn-sm"),
          tags$span("\u00A0"),
          downloadButton("download_trait_repro_script", "Download trait R code", class = "btn btn-default btn-sm"),
          br(), br(),
          verbatimTextOutput("trait_query_code")
        ),
        tabPanel(
          "Ingest to BIEN",
          br(),
          tags$p(
            style = "color:#555;max-width:980px;",
            "Upload multiple CSV files (for example, plot metadata + field survey records). The app maps columns to Darwin Core and BIEN-like fields, suggests a merge key, builds a flat merged table, runs TNRS-like taxon normalization and coordinate QA, then creates a staging-table preview for BIEN loading."
          ),
          fileInput(
            "ingest_files",
            "Select one or more CSV files",
            multiple = TRUE,
            accept = c("text/csv", ".csv")
          ),
          actionButton("analyze_ingest_files", "Analyze, Merge, and Build Staging Table", class = "btn-primary"),
          br(), br(),
          uiOutput("ingest_merge_suggestion"),
          br(),
          tags$h4("Uploaded File Summary"),
          DTOutput("ingest_file_summary"),
          br(),
          tags$h4("Column Mapping (Darwin Core + BIEN)"),
          DTOutput("ingest_column_map"),
          br(),
          tags$h4("Merge Candidate Keys"),
          DTOutput("ingest_merge_candidates"),
          br(),
          tags$h4("Merged Flat Table Preview"),
          DTOutput("ingest_merged_preview"),
          br(),
          tags$h4("BIEN Staging Table Preview"),
          DTOutput("ingest_staging_preview"),
          br(),
          downloadButton("download_ingest_merged", "Download merged flat CSV", class = "btn btn-default btn-sm"),
          tags$span("\u00A0"),
          downloadButton("download_ingest_staging", "Download staging CSV", class = "btn btn-default btn-sm")
        ),
        tabPanel(
          "Species External Links",
          br(),
          tags$p(
            style = "color:#555;max-width:900px;",
            "Use these links to open species pages in external reference resources. Links are generated from the species currently entered in the app."
          ),
          uiOutput("species_external_links")
        )
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
  summary_cache_nonce <- reactiveVal(0L)
  trait_cache <- new.env(parent = emptyenv())
  range_cache <- new.env(parent = emptyenv())
  taxonomy_presence_cache <- new.env(parent = emptyenv())
  manual_query_nonce <- reactiveVal(0L)
  last_lucky_species <- reactiveVal(NULL)
  ingest_bundle <- reactiveVal(NULL)
  species_select_choices <- reactiveVal(STARTUP_SPECIES)

  build_preloaded_startup_result <- function() {
    data_dir <- file.path(getwd(), "sample_data")
    occ_file <- file.path(data_dir, paste0(STARTUP_SPECIES_SLUG, "_occurrences.csv"))
    trait_file <- file.path(data_dir, paste0(STARTUP_SPECIES_SLUG, "_traits.csv"))
    range_file <- file.path(data_dir, paste0(STARTUP_SPECIES_SLUG, "_ranges.csv"))

    if (!file.exists(occ_file) || !file.exists(trait_file)) {
      return(NULL)
    }

    occ <- tryCatch(read.csv(occ_file, stringsAsFactors = FALSE), error = function(e) data.frame())
    traits <- tryCatch(read.csv(trait_file, stringsAsFactors = FALSE), error = function(e) data.frame())
    ranges <- tryCatch(read.csv(range_file, stringsAsFactors = FALSE), error = function(e) data.frame())
    startup_range_sf <- read_downloaded_range_sf(getwd(), STARTUP_SPECIES)

    if (!is.data.frame(occ) || nrow(occ) == 0) {
      return(NULL)
    }

    occ <- categorize_observation_records(occ)
    occ_prepared <- prepare_occurrences(occ, map_point_cap = 800, sample_method = "datasource")
    family_name <- extract_primary_value(occ, c("scrubbed_family", "family", "verbatim_family"))
    reconciliation_tbl <- build_reconciliation_table(STARTUP_SPECIES, occ, NULL, "startup_preloaded_local_dataset", NULL)

    list(
      species = STARTUP_SPECIES,
      family_name = family_name,
      occurrences = occ,
      occurrences_prepared = occ_prepared,
      occurrences_returned = nrow(occ),
      occ_total_available = NA_real_,
      occ_total_note = "Startup data loaded from local sample_data files. Click 'Query BIEN' for live BIEN retrieval.",
      occ_source_mix = NULL,
      occurrence_sample_mode = "datasource",
      traits = traits,
      ranges = ranges,
      range_sf = startup_range_sf,
      range_dir = getwd(),
      include_range_query = TRUE,
      timeout_sec = 90,
      occ_limit = 1000,
      map_point_cap = 800,
      trait_limit = 1000,
      occ_fetch_limit = nrow(occ),
      fast_large_species_mode = TRUE,
      trait_fetch_limit = nrow(traits),
      occ_strategy = "startup_preloaded_local_dataset",
      use_default_filter_profile = TRUE,
      use_cultivated_filter = TRUE,
      use_introduced_filter = TRUE,
      include_cultivated = FALSE,
      natives_only = TRUE,
      only_plot_observations = FALSE,
      only_geovalid = TRUE,
      exclude_human_observation_records = FALSE,
      query_cache_key = STARTUP_CACHE_KEY,
      is_startup_preloaded = TRUE,
      query_elapsed_sec = 0,
      cache_hit = TRUE,
      query_errors = "startup_preloaded_local_dataset",
      reconciliation = reconciliation_tbl,
      name_suggestion = NULL
    )
  }

  startup_preloaded_result <- build_preloaded_startup_result()

  update_species_select_input <- function(selected_species, choices = NULL) {
    selected_species <- normalize_species_name(selected_species)
    current_choices <- isolate(species_select_choices())

    if (is.null(choices) || length(choices) == 0) {
      choices <- current_choices
    }

    choices <- unique(c(selected_species, as.character(choices)))
    choices <- choices[!is.na(choices) & nzchar(choices)]
    species_select_choices(choices)

    updateSelectizeInput(
      session,
      "species",
      choices = choices,
      selected = selected_species,
      server = TRUE,
      options = list(
        create = FALSE,
        maxOptions = 2000,
        placeholder = "Start typing accepted BIEN species names..."
      )
    )
  }

  taxonomy_species_exists <- function(species_name, timeout_sec = 20) {
    species_key <- tolower(normalize_species_name(species_name))
    if (!nzchar(species_key)) {
      return(FALSE)
    }

    if (exists(species_key, envir = taxonomy_presence_cache, inherits = FALSE)) {
      return(get(species_key, envir = taxonomy_presence_cache, inherits = FALSE))
    }

    tax_res <- safe_bien_call(BIEN_taxonomy_species(species_name), timeout_sec = timeout_sec)
    found <- is.data.frame(tax_res) && nrow(tax_res) > 0
    assign(species_key, found, envir = taxonomy_presence_cache)
    found
  }

  observeEvent(TRUE, {
    choices <- load_accepted_species_suggestions(timeout_sec = 60)
    if (length(choices) == 0) {
      choices <- STARTUP_SPECIES
    }

    update_species_select_input(STARTUP_SPECIES, choices = choices)
  }, once = TRUE)

  observeEvent(input$open_tab_help, {
    active_tab <- if (is.null(input$main_tabs)) "Occurrence" else input$main_tabs

    help_text <- switch(
      active_tab,
      "Occurrence" = "Use this tab to inspect mapped points and the summary section below the map. Load BIEN total counts on demand for full-database context.",
      "Community" = "Map and summarize records categorized as Plot / survey for the current species.",
      "Observations" = "Review observation-source composition at the top, then inspect row-level occurrence fields, provenance columns, and coordinates below.",
      "Traits" = "See grouped trait counts and example values by trait name and unit at the top, with raw BIEN trait records below.",
      "Range" = "Load optional BIEN range artifacts and inspect mapped range layers when available.",
      "Download" = "Download occurrence, plot/community, and trait datasets plus matching reproducible R code.",
      "Species External Links" = "Open external species references generated from the current species name.",
      "Overview & About" = "Read app background, scope, and interpretation context.",
      "Use Query BIEN to run live retrieval."
    )

    showModal(modalDialog(
      title = paste("Help —", active_tab),
      tags$p(help_text),
      tags$div(
        style = "background:#e8f5e9;border:1px solid #b7dfb9;color:#1b5e20;padding:8px 10px;border-radius:6px;margin:10px 0 0 0;font-size:0.92em;",
        tags$strong("Default (conservative ecological view): "),
        "Showing BIEN-classified native / not introduced records only; cultivated records hidden; only BIEN geovalid coordinates shown; all observation-source categories retained (including field observation / citizen science); and all observation categories (plot + non-plot) retained.",
        tags$br(),
        "This is the app's default starting view for biodiversity screening. If BIEN finds no records under these strict settings, the summary section below the map will report whether the app had to broaden the actual query strategy."
      ),
      easyClose = TRUE,
      footer = modalButton("Close")
    ))
  })

  build_occurrence_repro_script <- function(res) {
    species_for_code <- if (!is.null(res$species) && nzchar(res$species)) res$species else "Pinus ponderosa"

    active_cultivated <- if (isTRUE(res$use_cultivated_filter)) isTRUE(res$include_cultivated) else TRUE
    requested_natives_only <- if (isTRUE(res$use_introduced_filter)) isTRUE(res$natives_only) else FALSE
    requested_only_geovalid <- isTRUE(res$only_geovalid)

    strategy <- if (!is.null(res$occ_strategy) && nzchar(res$occ_strategy)) res$occ_strategy else "strict"
    effective_natives_only <- switch(
      strategy,
      strict = requested_natives_only,
      fallback_relaxed_native = FALSE,
      fallback_relaxed_geo = FALSE,
      requested_natives_only
    )
    effective_only_geovalid <- switch(
      strategy,
      strict = requested_only_geovalid,
      fallback_relaxed_native = requested_only_geovalid,
      fallback_relaxed_geo = FALSE,
      requested_only_geovalid
    )

    occ_limit <- if (is.null(res$occ_limit) || !is.finite(res$occ_limit)) 1000 else as.integer(res$occ_limit)
    occ_fetch_limit <- if (is.null(res$occ_fetch_limit) || !is.finite(res$occ_fetch_limit)) max(occ_limit, 1000) else as.integer(res$occ_fetch_limit)
    occ_page_size <- min(1000L, max(500L, occ_limit))
    sample_method <- if (is.null(res$occurrence_sample_mode) || !nzchar(res$occurrence_sample_mode)) "head" else as.character(res$occurrence_sample_mode)
    exclude_human_obs <- isTRUE(res$exclude_human_observation_records)
    only_plot_obs <- isTRUE(res$only_plot_observations)

    paste(
      "# Reproducible BIEN occurrence dataset script",
      "#",
      "# Plain-language summary:",
      paste0("# - Species queried: ", species_for_code),
      paste0("# - App BIEN strategy used in this run: ", strategy),
      paste0("# - Effective BIEN query flags used here: cultivated=", tolower(as.character(active_cultivated)), ", natives.only=", tolower(as.character(effective_natives_only)), ", only.geovalid=", tolower(as.character(effective_only_geovalid))),
      paste0("# - App post-query filters: exclude_human_observation_records=", tolower(as.character(exclude_human_obs)), ", only_plot_observations=", tolower(as.character(only_plot_obs))),
      paste0("# - Sampling to match app table: method='", sample_method, "', final occurrence limit=", occ_limit),
      "#",
      "# Running this script writes the reproduced occurrence dataset to CSV.",
      "",
      "library(BIEN)",
      "library(dplyr)",
      "library(stringr)",
      "",
      paste0("species_name <- ", dQuote(species_for_code)),
      paste0("occ_limit <- ", occ_limit),
      paste0("occ_fetch_limit <- ", occ_fetch_limit),
      paste0("occ_page_size <- ", occ_page_size),
      paste0("sample_method <- ", dQuote(sample_method)),
      "",
      "find_first_col <- function(df, candidates) {",
      "  if (!is.data.frame(df) || nrow(df) == 0) return(NULL)",
      "  hit <- candidates[candidates %in% names(df)]",
      "  if (length(hit) > 0) return(hit[[1]])",
      "  lower_names <- tolower(names(df))",
      "  for (candidate in candidates) {",
      "    idx <- which(lower_names == tolower(candidate))",
      "    if (length(idx) > 0) return(names(df)[idx[[1]]])",
      "  }",
      "  NULL",
      "}",
      "",
      "categorize_observation_records <- function(df) {",
      "  if (!is.data.frame(df) || nrow(df) == 0) return(df)",
      "  obs_type_col <- find_first_col(df, c('observation_type', 'observation.type'))",
      "  source_col <- find_first_col(df, c('datasource', 'data_source', 'collection', 'source'))",
      "  dataset_col <- find_first_col(df, c('dataset', 'dataset_name'))",
      "  basis_col <- find_first_col(df, c('basisOfRecord', 'basis_of_record'))",
      "",
      "  obs_txt <- if (!is.null(obs_type_col)) as.character(df[[obs_type_col]]) else rep('', nrow(df))",
      "  source_txt <- if (!is.null(source_col)) as.character(df[[source_col]]) else rep('', nrow(df))",
      "  dataset_txt <- if (!is.null(dataset_col)) as.character(df[[dataset_col]]) else rep('', nrow(df))",
      "  basis_txt <- if (!is.null(basis_col)) as.character(df[[basis_col]]) else rep('', nrow(df))",
      "",
      "  combined_txt <- tolower(paste(obs_txt, source_txt, dataset_txt, basis_txt))",
      "  basis_txt_lower <- tolower(basis_txt)",
      "",
      "  df$observation_category <- dplyr::case_when(",
      "    stringr::str_detect(combined_txt, 'specimen|herb|preserved|museum|preservedspecimen') ~ 'Specimen / herbarium',",
      "    stringr::str_detect(combined_txt, '\\bplot\\b|\\bsurvey\\b|\\binventory\\b|\\bmonitoring\\b') ~ 'Plot / survey',",
      "    stringr::str_detect(combined_txt, 'inaturalist') ~ 'Citizen science (iNaturalist)',",
      "    (stringr::str_detect(basis_txt_lower, 'humanobservation|human observation') |",
      "      (stringr::str_detect(combined_txt, '\\bhuman\\s+observation\\b|\\bhuman_observation\\b') & !stringr::str_detect(combined_txt, 'specimen|museum|herb'))) ~ 'Field observation (HumanObservation)',",
      "    stringr::str_detect(combined_txt, 'gbif') ~ 'GBIF / other aggregator',",
      "    TRUE ~ 'Other / unknown'",
      "  )",
      "  df",
      "}",
      "",
      "sample_occurrence_rows <- function(df, target_n, sample_method = 'random') {",
      "  valid_methods <- c('random', 'head', 'datasource', 'observation_type', 'observation_category')",
      "  sample_method <- if (!is.null(sample_method) && sample_method %in% valid_methods) sample_method else 'random'",
      "  if (!is.data.frame(df) || nrow(df) == 0 || nrow(df) <= target_n) return(df)",
      "",
      "  if (sample_method == 'head') return(dplyr::slice_head(df, n = target_n))",
      "  if (sample_method == 'random') return(dplyr::slice_sample(df, n = target_n))",
      "",
      "  if (!'observation_category' %in% names(df)) df <- categorize_observation_records(df)",
      "  stratify_col <- switch(",
      "    sample_method,",
      "    datasource = find_first_col(df, c('datasource', 'data_source', 'collection', 'source')),",
      "    observation_type = find_first_col(df, c('observation_type', 'observation.type')),",
      "    observation_category = find_first_col(df, c('observation_category')),",
      "    NULL",
      "  )",
      "  if (is.null(stratify_col) || !stratify_col %in% names(df)) return(dplyr::slice_sample(df, n = target_n))",
      "",
      "  group_values <- trimws(as.character(df[[stratify_col]]))",
      "  group_values[is.na(group_values) | group_values == ''] <- 'unknown'",
      "  group_index <- split(seq_len(nrow(df)), group_values)",
      "  if (length(group_index) <= 1) return(dplyr::slice_sample(df, n = target_n))",
      "",
      "  group_index <- group_index[order(vapply(group_index, length, integer(1)), decreasing = TRUE)]",
      "  base_quota <- max(1L, floor(target_n / length(group_index)))",
      "  selected <- unlist(lapply(group_index, function(idx) {",
      "    draw_n <- min(length(idx), base_quota)",
      "    idx[sample.int(length(idx), size = draw_n, replace = FALSE)]",
      "  }), use.names = FALSE)",
      "  selected <- unique(selected)",
      "",
      "  if (length(selected) < target_n) {",
      "    leftovers <- lapply(group_index, function(idx) setdiff(idx, selected))",
      "    while (length(selected) < target_n && any(lengths(leftovers) > 0)) {",
      "      for (i in seq_along(leftovers)) {",
      "        if (length(selected) >= target_n) break",
      "        if (length(leftovers[[i]]) == 0) next",
      "        add_pos <- sample.int(length(leftovers[[i]]), size = 1)",
      "        add_idx <- leftovers[[i]][add_pos]",
      "        selected <- c(selected, add_idx)",
      "        leftovers[[i]] <- setdiff(leftovers[[i]], add_idx)",
      "      }",
      "    }",
      "  }",
      "",
      "  selected <- selected[seq_len(min(length(selected), target_n))]",
      "  df[selected, , drop = FALSE]",
      "}",
      "",
      "sql_quote_literal <- function(x) {",
      "  x <- as.character(x)",
      "  x <- gsub(\"'\", \"''\", x, fixed = TRUE)",
      "  paste0(\"'\", x, \"'\")",
      "}",
      "",
      "natives_check_with_null_fallback <- function(natives_only = TRUE) {",
      "  if (isTRUE(natives_only)) list(query = 'AND (is_introduced=0 OR is_introduced IS NULL) ') else list(query = '')",
      "}",
      "",
      "query_occurrence_randomized <- function(species_name, cultivated = FALSE, natives_only = TRUE, only_geovalid = TRUE, limit = 1000, record_limit = 500, randomize_order = FALSE) {",
      "  cultivated_ <- BIEN:::.cultivated_check(cultivated)",
      "  newworld_ <- BIEN:::.newworld_check(NULL)",
      "  taxonomy_ <- BIEN:::.taxonomy_check(TRUE)",
      "  native_ <- BIEN:::.native_check(TRUE)",
      "  observation_ <- BIEN:::.observation_check(TRUE)",
      "  political_ <- BIEN:::.political_check(FALSE)",
      "  natives_ <- natives_check_with_null_fallback(natives_only)",
      "  collection_ <- BIEN:::.collection_check(FALSE)",
      "  geovalid_ <- BIEN:::.geovalid_check(only_geovalid)",
      "  order_clause <- if (isTRUE(randomize_order) && limit <= 10000) 'ORDER BY random()' else ''",
      "",
      "  query <- paste(",
      "    'SELECT scrubbed_species_binomial', taxonomy_$select, native_$select, political_$select,",
      "    ',latitude, longitude,date_collected,',",
      "    'datasource,dataset,dataowner,custodial_institution_codes,collection_code,view_full_occurrence_individual.datasource_id',",
      "    collection_$select, cultivated_$select, newworld_$select, observation_$select, geovalid_$select,",
      "    'FROM view_full_occurrence_individual',",
      "    'WHERE scrubbed_species_binomial in (', paste(sql_quote_literal(species_name), collapse = ', '), ')',",
      "    cultivated_$query, newworld_$query, natives_$query, observation_$query, geovalid_$query,",
      "    \"AND higher_plant_group NOT IN ('Algae','Bacteria','Fungi')\",",
      "    \"AND (georef_protocol is NULL OR georef_protocol<>'county centroid')\",",
      "    'AND (is_centroid IS NULL OR is_centroid=0)',",
      "    'AND scrubbed_species_binomial IS NOT NULL',",
      "    \"AND lower(coalesce(observation_type, '')) NOT LIKE '%trait%'\",",
      "    \"AND lower(coalesce(observation_type, '')) NOT LIKE '%measurement%'\",",
      "    order_clause,",
      "    'LIMIT', as.integer(limit), ';'",
      "  )",
      "",
      "  BIEN:::.BIEN_sql(query, fetch.query = FALSE, record_limit = record_limit)",
      "}",
      "",
      "occ <- query_occurrence_randomized(",
      "  species_name = species_name,",
      paste0("  cultivated = ", tolower(as.character(active_cultivated)), ","),
      paste0("  natives_only = ", tolower(as.character(effective_natives_only)), ","),
      paste0("  only_geovalid = ", tolower(as.character(effective_only_geovalid)), ","),
      "  limit = occ_fetch_limit,",
      "  record_limit = occ_page_size,",
      "  randomize_order = FALSE",
      ")",
      "",
      "occ <- categorize_observation_records(occ)",
      if (isTRUE(exclude_human_obs)) {
        "occ <- occ %>% dplyr::filter(!observation_category %in% c('Citizen science (iNaturalist)', 'Field observation (HumanObservation)'))"
      } else {
        "# No HumanObservation/iNaturalist exclusion was active."
      },
      if (isTRUE(only_plot_obs)) {
        "occ <- occ %>% dplyr::filter(observation_category == 'Plot / survey')"
      } else {
        "# Plot-only filter was not active."
      },
      "",
      "if (nrow(occ) > occ_limit) {",
      "  occ <- sample_occurrence_rows(occ, target_n = occ_limit, sample_method = sample_method)",
      "}",
      "",
      "out_file <- paste0(gsub('\\\\s+', '_', species_name), '_occurrence_dataset_reproduced.csv')",
      "write.csv(occ, out_file, row.names = FALSE)",
      "cat('Rows written:', nrow(occ), '\\n')",
      "cat('Output file:', out_file, '\\n')",
      sep = "\n"
    )
  }

  build_trait_repro_script <- function(res) {
    species_for_code <- if (!is.null(res$species) && nzchar(res$species)) res$species else "Pinus ponderosa"
    trait_limit <- if (is.null(res$trait_limit) || !is.finite(res$trait_limit)) 1000 else as.integer(res$trait_limit)
    trait_fetch_limit <- if (is.null(res$trait_fetch_limit) || !is.finite(res$trait_fetch_limit)) min(trait_limit, 1000) else as.integer(res$trait_fetch_limit)
    trait_record_limit <- min(500L, trait_limit)

    paste(
      "# Reproducible BIEN trait dataset script",
      "library(BIEN)",
      "",
      paste0("species_name <- ", dQuote(species_for_code)),
      paste0("trait_limit <- ", trait_fetch_limit),
      paste0("trait_record_limit <- ", trait_record_limit),
      "",
      "traits <- BIEN_trait_species(",
      "  species = species_name,",
      "  all.taxonomy = TRUE,",
      "  source.citation = TRUE,",
      "  limit = trait_limit,",
      "  record_limit = trait_record_limit,",
      "  fetch.query = FALSE",
      ")",
      "",
      "if (!is.data.frame(traits)) {",
      "  stop('No trait table was returned by BIEN for this query.')",
      "}",
      "",
      "out_file <- paste0(gsub('\\\\s+', '_', species_name), '_trait_dataset_reproduced.csv')",
      "write.csv(traits, out_file, row.names = FALSE)",
      "cat('Rows written:', nrow(traits), '\\n')",
      "cat('Output file:', out_file, '\\n')",
      sep = "\n"
    )
  }

  build_plot_repro_script <- function(res) {
    species_for_code <- if (!is.null(res$species) && nzchar(res$species)) res$species else "Pinus ponderosa"

    paste(
      "# Reproducible BIEN plot/survey dataset script",
      "# This script recreates the app's occurrence dataset and then filters to Plot / survey records.",
      "",
      build_occurrence_repro_script(res),
      "",
      "occ <- read.csv(out_file, stringsAsFactors = FALSE)",
      "if (!'observation_category' %in% names(occ)) {",
      "  stop('Expected observation_category column was not found in the reproduced occurrence dataset.')",
      "}",
      "plot_occ <- dplyr::filter(occ, observation_category == 'Plot / survey')",
      paste0("plot_file <- paste0(gsub('\\\\s+', '_', ", dQuote(species_for_code), "), '_plot_dataset_reproduced.csv')"),
      "write.csv(plot_occ, plot_file, row.names = FALSE)",
      "cat('Plot/survey rows written:', nrow(plot_occ), '\\n')",
      "cat('Output file:', plot_file, '\\n')",
      sep = "\n"
    )
  }

  get_plot_community_bundle <- function(res) {
    occ <- res$occurrences
    if (!is.data.frame(occ) || nrow(occ) == 0) {
      return(list(raw = data.frame(), prepared = list(data = NULL, lat_col = NULL, lon_col = NULL)))
    }

    if (!"observation_category" %in% names(occ)) {
      occ <- categorize_observation_records(occ)
    }

    plot_rows <- occ %>%
      filter(observation_category == "Plot / survey")

    map_cap <- if (is.null(res$map_point_cap) || !is.finite(res$map_point_cap)) 800 else as.integer(res$map_point_cap)
    prepared <- prepare_occurrences(
      plot_rows,
      map_point_cap = map_cap,
      sample_method = "observation_category"
    )

    list(raw = plot_rows, prepared = prepared)
  }

  summarize_plot_community <- function(plot_df, prepared_info) {
    if (!is.data.frame(plot_df) || nrow(plot_df) == 0) {
      return(tags$div(style = "color:#666;", "No Plot / survey records are available for the current species and filter settings."))
    }

    source_col <- find_first_col(plot_df, c("datasource", "data_source", "collection", "source"))
    dataset_col <- find_first_col(plot_df, c("dataset", "dataset_name"))
    country_col <- find_first_col(plot_df, c("country", "country_name", "scrubbed_country"))
    date_col <- find_first_col(plot_df, c("date_collected", "eventDate", "event_date", "year"))

    n_mappable <- if (is.list(prepared_info) && is.data.frame(prepared_info$data)) nrow(prepared_info$data) else 0

    source_vals <- if (!is.null(source_col)) trimws(as.character(plot_df[[source_col]])) else character(0)
    source_vals <- source_vals[!is.na(source_vals) & nzchar(source_vals)]
    n_sources <- if (length(source_vals) > 0) length(unique(source_vals)) else NA_integer_

    dataset_vals <- if (!is.null(dataset_col)) trimws(as.character(plot_df[[dataset_col]])) else character(0)
    dataset_vals <- dataset_vals[!is.na(dataset_vals) & nzchar(dataset_vals)]
    n_datasets <- if (length(dataset_vals) > 0) length(unique(dataset_vals)) else NA_integer_

    country_vals <- if (!is.null(country_col)) trimws(as.character(plot_df[[country_col]])) else character(0)
    country_vals <- country_vals[!is.na(country_vals) & nzchar(country_vals)]
    n_countries <- if (length(country_vals) > 0) length(unique(country_vals)) else NA_integer_

    year_range <- {
      if (is.null(date_col)) {
        "Not available"
      } else {
        vals <- as.character(plot_df[[date_col]])
        years <- suppressWarnings(as.integer(sub("^.*?(\\d{4}).*$", "\\1", vals)))
        years <- years[!is.na(years) & years >= 1500 & years <= 2100]
        if (length(years) == 0) {
          "Not available"
        } else {
          paste0(min(years), " – ", max(years))
        }
      }
    }

    tags$ul(
      style = "margin-top:6px;",
      tags$li(tags$strong("Plot / survey records in app sample: "), format(nrow(plot_df), big.mark = ",", scientific = FALSE, trim = TRUE)),
      tags$li(tags$strong("Mappable plot points: "), format(n_mappable, big.mark = ",", scientific = FALSE, trim = TRUE)),
      tags$li(tags$strong("Unique data sources: "), ifelse(is.na(n_sources), "Not available", format(n_sources, big.mark = ",", scientific = FALSE, trim = TRUE))),
      tags$li(tags$strong("Unique datasets: "), ifelse(is.na(n_datasets), "Not available", format(n_datasets, big.mark = ",", scientific = FALSE, trim = TRUE))),
      tags$li(tags$strong("Countries represented: "), ifelse(is.na(n_countries), "Not available", format(n_countries, big.mark = ",", scientific = FALSE, trim = TRUE))),
      tags$li(tags$strong("Collection year range: "), year_range)
    )
  }

  forced_query_species <- reactiveVal(NULL)

  get_cached_result <- function(cache_env, cache_key) {
    if (is.null(cache_key) || !exists(cache_key, envir = cache_env, inherits = FALSE)) {
      return(NULL)
    }
    get(cache_key, envir = cache_env, inherits = FALSE)
  }

  set_summary_cache <- function(cache_key, value) {
    assign(cache_key, value, envir = summary_cache)
    summary_cache_nonce(isolate(summary_cache_nonce()) + 1L)
  }

  query_trigger <- reactiveVal("run")
  observeEvent(input$run_query, {
    query_trigger("run")
  }, ignoreInit = TRUE)
  observeEvent(input$retry_bien, {
    query_trigger("retry")
  }, ignoreInit = TRUE)

  observeEvent(input$feeling_lucky_species, {
    withProgress(message = "Finding a random BIEN species", detail = "Selecting and verifying range-map availability", value = 0, {
      incProgress(0.2, detail = "Picking candidate species")
      lucky <- find_lucky_species_with_mappable_points(
        input = input,
        min_mappable_points = 30,
        max_attempts = 8,
        timeout_sec = min(12, max(8, as.numeric(input$query_timeout)))
      )

      if (!identical(lucky$status, "ok") || is.null(lucky$species)) {
        showNotification(
          "Could not quickly find a random species with a verified BIEN range map. Try again in a moment.",
          type = "warning",
          duration = 8
        )
        return(NULL)
      }

      incProgress(0.8, detail = paste("Selected", lucky$species, "- updating query"))
      # Keep Lucky mode responsive even if the user previously requested very large samples.
      updateCheckboxInput(session, "fast_large_species_mode", value = TRUE)
      updateNumericInput(session, "occurrence_limit", value = min(2000, max(200, as.numeric(input$occurrence_limit))))
      updateNumericInput(session, "map_point_cap", value = min(1000, max(100, as.numeric(input$map_point_cap))))
      updateNumericInput(session, "query_timeout", value = min(15, max(10, as.numeric(input$query_timeout))))
      updateCheckboxInput(session, "only_plot_observations", value = FALSE)
      last_lucky_species(lucky$species)
      update_species_select_input(lucky$species)
      showNotification(
        paste0("Random species selected: ", lucky$species, " (range-map verified). Plot-only filtering was turned off for this run."),
        type = "message",
        duration = 6
      )
      incProgress(1)
    })
  }, ignoreInit = TRUE)

  bien_results_live <- eventReactive(list(input$run_query, input$retry_bien, manual_query_nonce()), {
    forced_species <- isolate(forced_query_species())
    species_input <- str_squish(if (!is.null(forced_species) && nzchar(forced_species)) forced_species else input$species)
    req(nzchar(species_input))
    species_name <- normalize_species_name(species_input)
    if (!is.null(forced_species) && nzchar(forced_species) && tolower(species_name) == tolower(normalize_species_name(forced_species))) {
      forced_query_species(NULL)
    }
    retry_mode <- identical(query_trigger(), "retry")
    include_range_query <- if (is.null(input$include_range_query)) TRUE else isTRUE(input$include_range_query)
    timeout_sec <- max(15, as.numeric(input$query_timeout))
    occ_limit <- max(200, as.numeric(input$occurrence_limit))
    map_point_cap <- max(100, as.numeric(input$map_point_cap))
    trait_limit <- max(100, as.numeric(input$trait_limit))
    sample_random <- if (is.null(input$randomize_occurrence_sample)) TRUE else isTRUE(input$randomize_occurrence_sample)
    filter_cfg <- resolve_filter_profile(input)
    map_sampling_method <- if (is.null(input$map_sampling_method)) "datasource" else input$map_sampling_method
    display_sampling_method <- if (sample_random) map_sampling_method else "head"
    fast_large_species_mode <- if (is.null(input$fast_large_species_mode)) TRUE else isTRUE(input$fast_large_species_mode)
    lucky_fast_mode <- {
      lucky_species <- isolate(last_lucky_species())
      !is.null(lucky_species) && nzchar(lucky_species) && tolower(lucky_species) == tolower(species_name)
    }
    if (isTRUE(lucky_fast_mode)) {
      timeout_sec <- min(timeout_sec, 12)
      occ_limit <- min(occ_limit, 1500)
      map_point_cap <- min(map_point_cap, 800)
    }
    occ_page_size <- min(1000, max(occ_limit, 500))
    base_occ_fetch_limit <- min(if (identical(display_sampling_method, "head")) occ_limit else max(occ_limit * 2, 1000), 50000)
    fast_mode_fetch_cap <- max(2000, min(10000, map_point_cap * 3))
    occ_fetch_limit <- if (isTRUE(fast_large_species_mode)) {
      min(base_occ_fetch_limit, fast_mode_fetch_cap)
    } else {
      base_occ_fetch_limit
    }
    trait_fetch_limit <- min(trait_limit, 1000)
    range_dir <- file.path(tempdir(), "bien_ranges_cache", gsub("\\s+", "_", species_name))
    dir.create(range_dir, recursive = TRUE, showWarnings = FALSE)

    cache_key <- paste(
      species_name,
      include_range_query,
      timeout_sec,
      occ_limit,
      map_point_cap,
      trait_limit,
      sample_random,
      map_sampling_method,
      fast_large_species_mode,
      filter_cfg$use_default_profile,
      filter_cfg$use_cultivated_filter,
      filter_cfg$include_cultivated,
      filter_cfg$use_introduced_filter,
      filter_cfg$natives_only,
      filter_cfg$only_plot_observations,
      filter_cfg$only_geovalid,
      filter_cfg$exclude_human_observation_records,
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
      if (retry_mode) {
        incProgress(0.1, detail = "Retry mode: re-attempting BIEN connection with backoff")
      } else {
        detail_msg <- "Occurrences: fast-loading records (database randomization disabled for speed)"
        incProgress(0.15, detail = detail_msg)
      }
      occ_bundle <- query_occurrence_with_fallback(
        species_name,
        input,
        occ_fetch_limit,
        occ_page_size,
        timeout_sec,
        connection_retry = retry_mode,
        # Even in Lucky mode, keep fallback plans enabled so a strict timeout can
        # still recover mappable records via relaxed native/geovalid strategies.
        max_plans = 3,
        per_plan_timeout = if (isTRUE(lucky_fast_mode)) 4 else 60,
        randomize_order = FALSE
      )
      occ <- occ_bundle$data
      occ_strategy <- occ_bundle$strategy
      occ_limit_used <- occ_bundle$limit_used
      occ_error <- if (inherits(occ, "error")) conditionMessage(occ) else NULL
      occ_returned_n <- if (is.data.frame(occ)) nrow(occ) else 0

      incProgress(0.4, detail = "Preparing the first occurrence view")

      if (is.data.frame(occ)) {
        occ <- categorize_observation_records(occ)
        if (isTRUE(filter_cfg$exclude_human_observation_records)) {
          occ <- occ %>%
            filter(!observation_category %in% c("Citizen science (iNaturalist)", "Field observation (HumanObservation)"))
        }
        if (isTRUE(filter_cfg$only_plot_observations)) {
          occ <- occ %>%
            filter(observation_category == "Plot / survey")
        }
        # Keep randomization client-side to avoid expensive ORDER BY random() on BIEN tables.
        if (isTRUE(sample_random) && identical(display_sampling_method, "head") && nrow(occ) > 1) {
          occ <- occ[sample.int(nrow(occ)), , drop = FALSE]
        }
        if (nrow(occ) > occ_limit) {
          occ <- sample_occurrence_rows(occ, target_n = occ_limit, sample_method = display_sampling_method)
        }
      }

      query_errors <- c(if (retry_mode) "retry_mode=connection_backoff" else NULL, occ_bundle$notes, occ_error)
      query_errors <- query_errors[!is.na(query_errors)]

      name_suggestion <- NULL
      if (isTRUE(input$enable_taxon_autocorrect) && is.data.frame(occ) && nrow(occ) == 0 && !is_bien_connection_error(query_errors)) {
        incProgress(0.6, detail = "No exact BIEN species records found; checking closest species spelling")
        name_suggestion <- find_best_species_spelling(species_name, timeout_sec = min(timeout_sec, 20))
      }

      incProgress(0.85, detail = "Preparing map and QA summary")
      occ_prepared <- if (is.data.frame(occ)) prepare_occurrences(occ, map_point_cap = map_point_cap, sample_method = display_sampling_method) else list(data = NULL, lat_col = NULL, lon_col = NULL, qa = list(total = 0, coord_valid = 0, kept = 0, removed = 0, removed_invalid = 0, duplicates_removed = 0), map_cap_applied = FALSE, map_cap = map_point_cap, original_kept = 0, sample_method = display_sampling_method)
      family_name <- extract_primary_value(occ, c("scrubbed_family", "family", "verbatim_family"))
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
        map_point_cap = map_point_cap,
        trait_limit = trait_limit,
        occ_fetch_limit = occ_limit_used,
        fast_large_species_mode = fast_large_species_mode,
        trait_fetch_limit = trait_fetch_limit,
        occ_strategy = occ_strategy,
        use_default_filter_profile = filter_cfg$use_default_profile,
        use_cultivated_filter = filter_cfg$use_cultivated_filter,
        use_introduced_filter = filter_cfg$use_introduced_filter,
        include_cultivated = filter_cfg$include_cultivated,
        natives_only = filter_cfg$natives_only,
        only_plot_observations = filter_cfg$only_plot_observations,
        only_geovalid = filter_cfg$only_geovalid,
        exclude_human_observation_records = filter_cfg$exclude_human_observation_records,
        query_cache_key = cache_key,
        query_elapsed_sec = round(as.numeric(difftime(Sys.time(), query_started, units = "secs")), 1),
        cache_hit = FALSE,
        query_errors = query_errors,
        reconciliation = reconciliation_tbl,
        name_suggestion = name_suggestion
      )

      assign(cache_key, result, envir = query_cache)
      result
    })
  }, ignoreInit = TRUE)

  bien_results <- reactive({
    has_user_query <- (!is.null(input$run_query) && input$run_query > 0) ||
      (!is.null(input$retry_bien) && input$retry_bien > 0) ||
      (manual_query_nonce() > 0)

    if (!has_user_query && !is.null(startup_preloaded_result)) {
      return(startup_preloaded_result)
    }

    bien_results_live()
  })

  observeEvent(bien_results_live(), {
    res <- bien_results_live()
    occ_n <- if (is.data.frame(res$occurrences)) nrow(res$occurrences) else 0
    mappable_n <- if (is.list(res$occurrences_prepared) && is.data.frame(res$occurrences_prepared$data)) nrow(res$occurrences_prepared$data) else 0

    if (isTRUE(res$use_default_filter_profile) && identical(res$occ_strategy, "fallback_relaxed_geo")) {
      showNotification(
        "Conservative default profile remained selected, but this query auto-relaxed geovalid/native constraints after strict timeout or zero-mappable results to recover map points.",
        type = "warning",
        duration = 10
      )
    }

    if (isTRUE(res$use_default_filter_profile) && identical(res$occ_strategy, "fallback_relaxed_native")) {
      showNotification(
        "Conservative default profile remained selected, but this query auto-relaxed native-only constraints after strict timeout to recover records.",
        type = "warning",
        duration = 10
      )
    }

    if (mappable_n == 0 && !is_bien_connection_error(res$query_errors) && isTRUE(taxonomy_species_exists(res$species, timeout_sec = 20))) {
      likely_filters <- character()
      if (isTRUE(res$use_default_filter_profile) || (isTRUE(res$use_introduced_filter) && isTRUE(res$natives_only))) {
        likely_filters <- c(likely_filters, "native-only")
      }
      if (isTRUE(res$use_default_filter_profile) || isTRUE(res$only_geovalid)) {
        likely_filters <- c(likely_filters, "geovalid-only coordinates")
      }
      if (isTRUE(res$use_cultivated_filter) && !isTRUE(res$include_cultivated)) {
        likely_filters <- c(likely_filters, "non-cultivated only")
      }

      filter_text <- if (length(likely_filters) > 0) {
        paste("Most likely filters excluding map points right now:", paste(likely_filters, collapse = ", "), ".")
      } else {
        "Current filters are excluding all mappable points."
      }

      map_hint <- if (occ_n == 0) {
        "Try relaxing native-only and/or geovalid filters, then query again."
      } else {
        "Records were returned, but none have map-valid coordinates under the current filters."
      }
      showNotification(
        paste(
          "Name found in BIEN taxonomy, but no mappable occurrence points under current filters.",
          filter_text,
          map_hint
        ),
        type = "warning",
        duration = 12
      )
    }

    elapsed <- suppressWarnings(as.numeric(res$query_elapsed_sec))
    if (isTRUE(res$cache_hit) || is.na(elapsed) || elapsed < 25) {
      return(NULL)
    }

    showNotification(
      paste0(
        "This query took ", elapsed, " seconds. For faster screening, keep Fast mode on, reduce sample limits, ",
        "or temporarily relax strict filters (native/geovalid)."
      ),
      type = "warning",
      duration = 10
    )
  }, ignoreInit = TRUE)

  observeEvent(input$apply_name_suggestion, {
    res <- bien_results()
    suggestion <- res$name_suggestion
    if (is.null(suggestion) || !identical(suggestion$status, "suggested")) {
      return(NULL)
    }

    forced_query_species(suggestion$suggested_name)
    update_species_select_input(suggestion$suggested_name)
    session$onFlushed(function() {
      manual_query_nonce(isolate(manual_query_nonce()) + 1L)
      query_trigger("run")
    }, once = TRUE)
  }, ignoreInit = TRUE)

  output$spelling_suggestion_ui <- renderUI({
    res <- req(bien_results())
    suggestion <- res$name_suggestion

    if (!isTRUE(input$enable_taxon_autocorrect) || is.null(suggestion)) {
      return(NULL)
    }

    if (!identical(suggestion$status, "suggested")) {
      return(NULL)
    }

    tags$div(
      style = "margin:6px 0 10px 0;padding:8px 10px;border:1px solid #b7d2e8;border-radius:6px;background:#eef6ff;",
      tags$div(
        style = "font-size:0.92em;color:#1e4f78;",
        tags$strong("Best BIEN spelling match: "),
        tags$span(suggestion$suggested_name),
        " (confidence: ", suggestion$confidence, ")"
      ),
      actionButton("apply_name_suggestion", "Use this name", class = "btn btn-default btn-sm", style = "margin-top:6px;")
    )
  })

  output$retry_bien_ui <- renderUI({
    if ((is.null(input$run_query) || input$run_query < 1) && (is.null(input$retry_bien) || input$retry_bien < 1)) {
      return(NULL)
    }

    res <- bien_results()
    if (is.null(res) || !is_bien_connection_error(res$query_errors)) {
      return(NULL)
    }

    actionButton("retry_bien", "Retry BIEN connection (with backoff)", class = "btn-warning btn-sm")
  })

  observeEvent(bien_results(), {
    updateTabsetPanel(session, "main_tabs", selected = "Occurrence")
  }, ignoreInit = TRUE)

  output$download_occurrence_csv <- downloadHandler(
    filename = function() {
      res <- bien_results()
      species_safe <- gsub("[^A-Za-z0-9_]+", "_", if (!is.null(res$species)) res$species else "species")
      paste0(species_safe, "_occurrence_dataset.csv")
    },
    content = function(file) {
      res <- bien_results()
      if (!is.data.frame(res$occurrences)) {
        write.csv(data.frame(message = "No occurrence dataset available for download."), file, row.names = FALSE)
        return(NULL)
      }
      write.csv(res$occurrences, file, row.names = FALSE)
    }
  )

  output$download_repro_script <- downloadHandler(
    filename = function() {
      res <- bien_results()
      species_safe <- gsub("[^A-Za-z0-9_]+", "_", if (!is.null(res$species)) res$species else "species")
      paste0(species_safe, "_reproduce_occurrence_dataset.R")
    },
    content = function(file) {
      res <- bien_results()
      writeLines(build_occurrence_repro_script(res), file, useBytes = TRUE)
    }
  )

  output$download_trait_csv <- downloadHandler(
    filename = function() {
      res <- bien_results()
      species_safe <- gsub("[^A-Za-z0-9_]+", "_", if (!is.null(res$species)) res$species else "species")
      paste0(species_safe, "_trait_dataset.csv")
    },
    content = function(file) {
      trait_bundle <- trait_results()
      traits_df <- trait_bundle$data
      if (!is.data.frame(traits_df)) {
        write.csv(data.frame(message = "No trait dataset available for download."), file, row.names = FALSE)
        return(NULL)
      }
      write.csv(traits_df, file, row.names = FALSE)
    }
  )

  output$download_plot_csv <- downloadHandler(
    filename = function() {
      res <- bien_results()
      species_safe <- gsub("[^A-Za-z0-9_]+", "_", if (!is.null(res$species)) res$species else "species")
      paste0(species_safe, "_plot_community_dataset.csv")
    },
    content = function(file) {
      res <- bien_results()
      bundle <- get_plot_community_bundle(res)
      plot_df <- bundle$raw
      if (!is.data.frame(plot_df) || nrow(plot_df) == 0) {
        write.csv(data.frame(message = "No Plot / survey dataset available for download under current filters."), file, row.names = FALSE)
        return(NULL)
      }
      write.csv(plot_df, file, row.names = FALSE)
    }
  )

  output$download_plot_repro_script <- downloadHandler(
    filename = function() {
      res <- bien_results()
      species_safe <- gsub("[^A-Za-z0-9_]+", "_", if (!is.null(res$species)) res$species else "species")
      paste0(species_safe, "_reproduce_plot_community_dataset.R")
    },
    content = function(file) {
      res <- bien_results()
      writeLines(build_plot_repro_script(res), file, useBytes = TRUE)
    }
  )

  output$download_trait_repro_script <- downloadHandler(
    filename = function() {
      res <- bien_results()
      species_safe <- gsub("[^A-Za-z0-9_]+", "_", if (!is.null(res$species)) res$species else "species")
      paste0(species_safe, "_reproduce_trait_dataset.R")
    },
    content = function(file) {
      res <- bien_results()
      writeLines(build_trait_repro_script(res), file, useBytes = TRUE)
    }
  )

  output$bien_query_code <- renderText({
    res <- bien_results()
    if (is.null(res) || !is.list(res)) {
      return("Run a BIEN query first to generate exact reproducible code for the current occurrence dataset.")
    }

    build_occurrence_repro_script(res)
  })

  output$trait_query_code <- renderText({
    res <- bien_results()
    if (is.null(res) || !is.list(res)) {
      return("Run a BIEN query first to generate exact reproducible code for the current trait dataset.")
    }

    build_trait_repro_script(res)
  })

  output$plot_query_code <- renderText({
    res <- bien_results()
    if (is.null(res) || !is.list(res)) {
      return("Run a BIEN query first to generate exact reproducible code for the current Plot / survey dataset.")
    }

    build_plot_repro_script(res)
  })

  observeEvent(input$analyze_ingest_files, {
    req(input$ingest_files)

    withProgress(message = "Running ingest pipeline", detail = "Reading files and mapping columns", value = 0, {
      incProgress(0.25, detail = "Mapping Darwin Core and BIEN fields")
      ingest_res <- run_ingest_workflow(input$ingest_files)

      if (is.null(ingest_res)) {
        showNotification("No non-empty CSV tables were detected in the uploaded files.", type = "warning", duration = 8)
        ingest_bundle(NULL)
        return(NULL)
      }

      incProgress(0.65, detail = "Building merged flat table and TNRS/coordinate augmentation")
      ingest_bundle(ingest_res)
      incProgress(1, detail = "Ingest analysis complete")
    })
  }, ignoreInit = TRUE)

  output$ingest_merge_suggestion <- renderUI({
    bundle <- ingest_bundle()
    if (is.null(bundle)) {
      return(tags$div(style = "color:#666;", "Upload CSV files and click Analyze to generate mapping and merge suggestions."))
    }

    key_txt <- if (!is.null(bundle$merge_key) && nzchar(bundle$merge_key)) bundle$merge_key else "No high-confidence key found"
    bien_check_txt <- if (isTRUE(bundle$bien_schema_check)) {
      "Merged schema is identical to BIEN reference fields (strict check)."
    } else if (isFALSE(bundle$bien_schema_check)) {
      "Merged schema differs from strict BIEN reference fields; staging preview includes normalized BIEN-ready columns."
    } else {
      "BIEN strict schema comparison not available for this run."
    }

    tags$div(
      style = "background:#eef6ff;border:1px solid #b7d2e8;color:#1e4f78;padding:10px 12px;border-radius:6px;",
      tags$strong("Suggested merge key: "), key_txt,
      tags$br(),
      tags$strong("RBIEN schema check: "), bien_check_txt
    )
  })

  output$ingest_file_summary <- renderDT({
    bundle <- ingest_bundle()
    if (is.null(bundle) || !is.data.frame(bundle$file_summary)) {
      return(datatable(data.frame(message = "No ingest summary available."), options = list(dom = "t"), rownames = FALSE))
    }
    datatable(bundle$file_summary, options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
  })

  output$ingest_column_map <- renderDT({
    bundle <- ingest_bundle()
    if (is.null(bundle) || !is.data.frame(bundle$column_map)) {
      return(datatable(data.frame(message = "No column mapping available."), options = list(dom = "t"), rownames = FALSE))
    }
    datatable(bundle$column_map, filter = "top", options = list(pageLength = 15, scrollX = TRUE), rownames = FALSE)
  })

  output$ingest_merge_candidates <- renderDT({
    bundle <- ingest_bundle()
    if (is.null(bundle) || !is.data.frame(bundle$merge_candidates) || nrow(bundle$merge_candidates) == 0) {
      return(datatable(data.frame(message = "No merge-key candidates identified."), options = list(dom = "t"), rownames = FALSE))
    }
    datatable(bundle$merge_candidates, options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
  })

  output$ingest_merged_preview <- renderDT({
    bundle <- ingest_bundle()
    if (is.null(bundle) || !is.data.frame(bundle$merged)) {
      return(datatable(data.frame(message = "No merged table available."), options = list(dom = "t"), rownames = FALSE))
    }
    datatable(utils::head(bundle$merged, 200), options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
  })

  output$ingest_staging_preview <- renderDT({
    bundle <- ingest_bundle()
    if (is.null(bundle) || !is.data.frame(bundle$staging)) {
      return(datatable(data.frame(message = "No staging table available."), options = list(dom = "t"), rownames = FALSE))
    }
    datatable(utils::head(bundle$staging, 200), options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
  })

  output$download_ingest_merged <- downloadHandler(
    filename = function() {
      paste0("bien_ingest_merged_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".csv")
    },
    content = function(file) {
      bundle <- ingest_bundle()
      if (is.null(bundle) || !is.data.frame(bundle$merged)) {
        write.csv(data.frame(message = "No merged table available."), file, row.names = FALSE)
        return(NULL)
      }
      write.csv(bundle$merged, file, row.names = FALSE)
    }
  )

  output$download_ingest_staging <- downloadHandler(
    filename = function() {
      paste0("bien_ingest_staging_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".csv")
    },
    content = function(file) {
      bundle <- ingest_bundle()
      if (is.null(bundle) || !is.data.frame(bundle$staging)) {
        write.csv(data.frame(message = "No staging table available."), file, row.names = FALSE)
        return(NULL)
      }
      write.csv(bundle$staging, file, row.names = FALSE)
    }
  )

  output$species_external_links <- renderUI({
    res <- bien_results()
    species_name <- if (!is.null(res$species) && nzchar(res$species)) {
      res$species
    } else {
      str_squish(input$species)
    }
    if (!nzchar(species_name)) {
      species_name <- STARTUP_SPECIES
    }
    species_name <- normalize_species_name(species_name)
    is_startup_species <- identical(species_name, STARTUP_SPECIES)
    species_slug <- gsub("\\s+", "_", species_name)
    species_query <- utils::URLencode(species_name, reserved = TRUE)

    wikipedia_url <- paste0("https://en.wikipedia.org/wiki/", species_slug)
    powo_url <- if (is_startup_species) {
      "https://powo.science.kew.org/taxon/urn:lsid:ipni.org:names:77170930-1"
    } else {
      paste0("https://powo.science.kew.org/results?q=", species_query)
    }
    mbg_url <- if (is_startup_species) {
      "https://www.missouribotanicalgarden.org/PlantFinder/PlantFinderDetails.aspx?taxonid=285000"
    } else {
      paste0("https://www.tropicos.org/name/Search?name=", species_query)
    }
    world_flora_url <- paste0("https://www.worldfloraonline.org/search?query=", species_query)
    inaturalist_url <- paste0("https://www.inaturalist.org/taxa/search?q=", species_query)
    asianplant_url <- get_asianplant_species_url(species_name)

    tags$div(
      style = "display:flex;flex-direction:column;gap:12px;max-width:900px;",
      tags$div(
        class = "bien-link-card",
        tags$strong("Wikipedia"),
        tags$p(style = "margin:6px 0 8px 0;color:#444;font-size:0.92em;", paste("Species page generated from:", species_name)),
        tags$a("Open Wikipedia", href = wikipedia_url, target = "_blank", class = "btn btn-default btn-sm")
      ),
      tags$div(
        class = "bien-link-card",
        tags$strong("Plants of the World Online (Kew)"),
        tags$p(
          style = "margin:6px 0 8px 0;color:#444;font-size:0.92em;",
          if (is_startup_species) {
            paste0("Direct taxon link for ", species_name, "; otherwise species search results.")
          } else {
            paste0("Species search results generated for: ", species_name)
          }
        ),
        tags$a("Open POWO", href = powo_url, target = "_blank", class = "btn btn-default btn-sm")
      ),
      tags$div(
        class = "bien-link-card",
        tags$strong("Missouri Botanical Garden"),
        tags$p(
          style = "margin:6px 0 8px 0;color:#444;font-size:0.92em;",
          if (is_startup_species) {
            paste0("Direct Plant Finder detail for ", species_name, "; otherwise Tropicos (Missouri Botanical Garden) name search.")
          } else {
            paste0("Tropicos name search generated for: ", species_name)
          }
        ),
        tags$a("Open Missouri Botanical Garden", href = mbg_url, target = "_blank", class = "btn btn-default btn-sm")
      ),
      tags$div(
        class = "bien-link-card",
        tags$strong("World Flora Online"),
        tags$p(
          style = "margin:6px 0 8px 0;color:#444;font-size:0.92em;",
          paste0("Species search generated for: ", species_name, ". This replaces The Plant List, which is no longer reliably reachable.")
        ),
        tags$a("Open World Flora Online", href = world_flora_url, target = "_blank", class = "btn btn-default btn-sm")
      ),
      tags$div(
        class = "bien-link-card",
        tags$strong("iNaturalist"),
        tags$p(
          style = "margin:6px 0 8px 0;color:#444;font-size:0.92em;",
          paste0("Taxon search generated for: ", species_name)
        ),
        tags$a("Open iNaturalist", href = inaturalist_url, target = "_blank", class = "btn btn-default btn-sm")
      ),
      if (!is.na(asianplant_url) && nzchar(asianplant_url)) {
        tags$div(
          class = "bien-link-card",
          tags$strong("AsianPlant.net"),
          tags$p(
            style = "margin:6px 0 8px 0;color:#444;font-size:0.92em;",
            paste0("Direct species page shown only when ", species_name, " is listed in AsianPlant.")
          ),
          tags$a("Open AsianPlant", href = asianplant_url, target = "_blank", class = "btn btn-default btn-sm")
        )
      }
    )
  })

  # Lazy-load BIEN trait data only when the user opens a trait-focused tab.
  trait_results <- reactive({
    res <- bien_results()
    req(res)

    if (isTRUE(res$is_startup_preloaded) && is.data.frame(res$traits)) {
      return(list(data = res$traits, error = NULL, loaded = TRUE))
    }

    req(!is.null(input$main_tabs), input$main_tabs %in% c("Traits", "Download"))

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

    if (isTRUE(res$is_startup_preloaded)) {
      return(list(data = res$ranges, error = NULL, range_sf = res$range_sf, loaded = TRUE, skipped = FALSE))
    }

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

  # Keep BIEN total-count and source-mix queries strictly manual. Automatic
  # post-query prefetch can be slow enough to look like the main query is hung.

  summary_results <- eventReactive(input$load_summary_counts, {
    res <- bien_results()
    req(res)

    cache_key <- paste0(res$query_cache_key, "||summary")
    cached <- get_cached_result(summary_cache, cache_key)
    if (!is.null(cached) && is.data.frame(cached$source_mix) && nrow(cached$source_mix) > 0) {
      return(cached)
    }

    withProgress(message = paste("Querying BIEN summary counts for", res$species), detail = "Summary statistics: estimating total matches and source mix", value = 0, {
      use_cultivated_filter <- isTRUE(res$use_cultivated_filter)
      use_introduced_filter <- isTRUE(res$use_introduced_filter)
      count_include_cultivated <- if (use_cultivated_filter) isTRUE(res$include_cultivated) else TRUE
      count_natives_only <- if (identical(res$occ_strategy, "fallback_relaxed_native") || identical(res$occ_strategy, "fallback_relaxed_geo")) {
        FALSE
      } else if (use_introduced_filter) {
        isTRUE(res$natives_only)
      } else {
        FALSE
      }
      count_only_geovalid <- if (identical(res$occ_strategy, "fallback_relaxed_geo")) {
        FALSE
      } else {
        isTRUE(res$only_geovalid)
      }

      incProgress(0.4, detail = "Counting total BIEN matches")
      occ_total_info <- if (!is.null(cached) && !is.null(cached$total) && !is.na(cached$total)) {
        list(total = cached$total, note = cached$note)
      } else {
        count_occurrence_records(
          species_name = res$species,
          cultivated = count_include_cultivated,
          natives_only = count_natives_only,
          only_geovalid = count_only_geovalid,
          timeout_sec = res$timeout_sec
        )
      }

      occ_total_all_info <- if (!is.null(cached) && !is.null(cached$total_all) && !is.na(cached$total_all)) {
        list(total = cached$total_all, note = cached$total_all_note)
      } else {
        count_occurrence_records(
          species_name = res$species,
          cultivated = TRUE,
          natives_only = FALSE,
          only_geovalid = FALSE,
          timeout_sec = min(res$timeout_sec, 30)
        )
      }

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
        total_all = occ_total_all_info$total,
        total_all_note = occ_total_all_info$note,
        source_mix = occ_source_mix,
        loaded = TRUE
      )
      set_summary_cache(cache_key, out)
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
        note = "Not loaded — click 'Load BIEN total counts and source mix (slower)' below to fetch the BIEN total count for this species.",
        total_all = NA_real_,
        total_all_note = "Not loaded — click 'Load BIEN total counts and source mix (slower)' below to fetch.",
        source_mix = NULL,
        loaded = FALSE
      )
    }

    occ_n <- if (is.data.frame(res$occurrences)) nrow(res$occurrences) else 0
    occ_returned_n <- if (!is.null(res$occurrences_returned)) res$occurrences_returned else occ_n
    occ_total_available <- summary_bundle$total
    occ_total_note <- summary_bundle$note
    occ_total_all_available <- summary_bundle$total_all
    occ_total_all_note <- summary_bundle$total_all_note
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
    field_obs_source_line <- if (is.data.frame(res$occurrences) && "observation_category" %in% names(res$occurrences)) {
      source_col <- find_first_col(res$occurrences, c("datasource", "data_source", "collection", "source"))
      if (!is.null(source_col)) {
        field_obs_rows <- res$occurrences %>%
          filter(observation_category == "Field observation (HumanObservation)")
        if (nrow(field_obs_rows) > 0) {
          src_counts <- sort(table(trimws(as.character(field_obs_rows[[source_col]]))), decreasing = TRUE)
          src_names <- names(src_counts)
          src_names[src_names == "" | is.na(src_names)] <- "unknown"
          paste(paste(src_names, as.integer(src_counts), sep = ": "), collapse = " | ")
        } else {
          "No rows in this category for current app sample"
        }
      } else {
        "Datasource column not returned by BIEN for this query"
      }
    } else {
      "Not available"
    }
    sample_plot_n <- if (is.data.frame(res$occurrences) && "observation_category" %in% names(res$occurrences)) {
      sum(res$occurrences$observation_category == "Plot / survey", na.rm = TRUE)
    } else {
      NA_real_
    }
    source_mix_plot_n <- if (is.data.frame(summary_bundle$source_mix)) {
      idx <- which(as.character(summary_bundle$source_mix$source_group) == "Plots")
      if (length(idx) > 0) sum(as.numeric(summary_bundle$source_mix$n_records[idx]), na.rm = TRUE) else 0
    } else {
      NA_real_
    }
    source_mix_mismatch_note <- if (!is.na(sample_plot_n) && !is.na(source_mix_plot_n) && sample_plot_n > 0 && source_mix_plot_n == 0) {
      "The BIEN-wide source fraction and app-sample categories are derived from different workflows: BIEN provenance fractions come from a separate BIEN-side grouped count query, while app categories come from the downloaded sampled table used for mapping. Compare both, but treat app-sample categories as sample composition rather than full-database fractions."
    } else {
      NULL
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
    strategy <- if (!is.null(res$occ_strategy) && nzchar(res$occ_strategy)) as.character(res$occ_strategy) else "strict"
    requested_profile_txt <- if (isTRUE(res$use_default_filter_profile)) {
      "Conservative default profile"
    } else {
      "Custom profile"
    }
    effective_query_txt <- switch(
      strategy,
      strict = "Strict query (requested filters kept)",
      fallback_relaxed_native = "Auto-relaxed native filter (geovalid unchanged)",
      fallback_relaxed_geo = "Auto-relaxed native and geovalid filters",
      backend_timeout_error = "No successful result (BIEN timeout)",
      backend_connection_error = "No successful result (BIEN connection error)",
      paste0("Strategy: ", strategy)
    )
    conservative_relaxed <- isTRUE(res$use_default_filter_profile) && strategy %in% c("fallback_relaxed_native", "fallback_relaxed_geo")

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
    mapped_pct_of_returned <- if (!is.na(occ_returned_n) && occ_returned_n > 0) {
      round(100 * mappable_n / occ_returned_n, 1)
    } else {
      NA_real_
    }
    mapped_pct_of_total <- if (!is.null(occ_total_all_available) && !is.na(occ_total_all_available) && occ_total_all_available > 0) {
      round(100 * mappable_n / occ_total_all_available, 3)
    } else {
      NA_real_
    }
    mapped_pct_line <- if (!is.na(mapped_pct_of_total)) {
      paste0(
        mapped_pct_of_total,
        "% of ALL BIEN observations for this species are currently mapped (",
        format(mappable_n, big.mark = ",", scientific = FALSE, trim = TRUE),
        " / ",
        format(occ_total_all_available, big.mark = ",", scientific = FALSE, trim = TRUE),
        "; sampled subset of all BIEN observations)"
      )
    } else if (!is.na(mapped_pct_of_returned)) {
      paste0(
        mapped_pct_of_returned,
        "% of BIEN returned rows are currently mapped (",
        format(mappable_n, big.mark = ",", scientific = FALSE, trim = TRUE),
        " / ",
        format(occ_returned_n, big.mark = ",", scientific = FALSE, trim = TRUE),
        "). ALL-species BIEN total is still loading."
      )
    } else {
      "Not available"
    }
    mapped_pct_guidance <- "If this mapped proportion seems low, click Query BIEN again to refresh a randomized sample, or increase 'Max mapped occurrence points' (and optionally 'Occurrence records to keep in app sample') in the sidebar."

    HTML(paste0(
      "<strong>Species:</strong> ", htmltools::htmlEscape(res$species),
      "<br><strong>Family:</strong> ", htmltools::htmlEscape(family_name),
      "<br><strong>Total BIEN occurrence records matching current strategy (count only; not downloaded):</strong> ", occ_total_txt,
      "<br><strong>Total ALL BIEN observations for this species (count only; unfiltered):</strong> ",
      if (!is.null(occ_total_all_available) && !is.na(occ_total_all_available)) {
        format(occ_total_all_available, big.mark = ",", scientific = FALSE, trim = TRUE)
      } else if (!is.null(occ_total_all_note) && nzchar(occ_total_all_note)) {
        paste0("Not available (", occ_total_all_note, ")")
      } else {
        "Not available"
      },
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
      "<br><strong>Observation categories in app sample:</strong> ", category_line,
      "<br><strong>Datasource breakdown for 'Field observation (HumanObservation)':</strong> ", field_obs_source_line,
      "<br><strong>Mapped-point proportion:</strong> ", mapped_pct_line,
      "<br><strong>Mapped-point guidance:</strong> ", mapped_pct_guidance,
      if (!is.null(source_mix_mismatch_note)) {
        paste0("<br><strong>Category reconciliation note:</strong> ", source_mix_mismatch_note)
      } else {
        ""
      },
      "<br><strong>Mappable occurrence points:</strong> ", mappable_n,
      "<br><strong>Mapped-point cap requested:</strong> ", res$map_point_cap,
      "<br><strong>Mapped-point native / introduced status:</strong> ", introduced_line,
      "<br><strong>Mapped-point cultivated status:</strong> ", cultivated_line,
      "<br><strong>Show only plot/survey records:</strong> ", ifelse(isTRUE(res$only_plot_observations), "yes", "no"),
      "<br><strong>Exclude field observation + citizen science records (HumanObservation + iNaturalist):</strong> ", ifelse(isTRUE(res$exclude_human_observation_records), "yes", "no"),
      "<br><strong>Use BIEN default conservative filter profile:</strong> ", ifelse(isTRUE(res$use_default_filter_profile), "yes", "no"),
      "<br><strong>Coordinate / geovalid summary:</strong> ", geovalid_line,
      "<br><strong>Overview map status:</strong> ", map_status,
      "<br><strong>Observation records after QA:</strong> ", res$occurrences_prepared$original_kept,
      "<br><strong>Observation records rendered on map:</strong> ", res$occurrences_prepared$qa$kept,
      "<br><strong>Observation records removed by QA:</strong> ", res$occurrences_prepared$qa$removed,
      "<br><strong>Trait records:</strong> ", trait_n,
      "<br><strong>Query timeout:</strong> ", res$timeout_sec, " sec",
      "<br><strong>Occurrence limit requested:</strong> ", res$occ_limit,
      "<br><strong>Occurrence fetch cap used:</strong> ", res$occ_fetch_limit,
      "<br><strong>Fast mode for large species:</strong> ", ifelse(isTRUE(res$fast_large_species_mode), "on (shorter waits, smaller first-pass sample)", "off (larger pulls, slower for widespread species)"),
      "<br><strong>Trait limit requested:</strong> ", res$trait_limit,
      "<br><strong>Trait fetch cap used:</strong> ", res$trait_fetch_limit,
      "<br><strong>Use BIEN is_cultivated filter:</strong> ", ifelse(res$use_cultivated_filter, paste0("yes (include cultivated = ", tolower(as.character(res$include_cultivated)), ")"), "no"),
      "<br><strong>Use BIEN is_introduced filter:</strong> ", ifelse(res$use_introduced_filter, paste0("yes (native only = ", tolower(as.character(res$natives_only)), ")"), "no"),
      "<br><strong>Requested vs effective BIEN profile:</strong> ", requested_profile_txt, " -> ", effective_query_txt,
      if (conservative_relaxed) {
        "<br><strong>Conservative profile preserved exactly?:</strong> no (auto-relaxed after strict attempt to recover mappable records)"
      } else {
        ""
      },
      "<br><strong>Occurrence strategy:</strong> ", htmltools::htmlEscape(res$occ_strategy),
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
    summary_cache_nonce()
    res <- bien_results()
    occ_n <- if (is.data.frame(res$occurrences)) nrow(res$occurrences) else 0
    mappable_n <- if (is.data.frame(res$occurrences_prepared$data)) nrow(res$occurrences_prepared$data) else 0
    cached_range <- get_cached_result(range_cache, res$query_cache_key)
    has_range <- !is.null(cached_range) && inherits(cached_range$range_sf, "sf") && nrow(cached_range$range_sf) > 0

    summary_cache_key <- paste0(res$query_cache_key, "||summary")
    summary_bundle <- get_cached_result(summary_cache, summary_cache_key)
    occ_total_all_available <- if (!is.null(summary_bundle)) summary_bundle$total_all else NA_real_
    mapped_pct_sample_notice <- {
      sample_pct <- if (is.finite(occ_n) && occ_n > 0 && is.finite(mappable_n) && mappable_n >= 0) {
        round(100 * mappable_n / occ_n, 1)
      } else {
        NA_real_
      }

      if (is.finite(sample_pct)) {
        paste0(
          sample_pct,
          "% of the current app sample is mapped (",
          format(mappable_n, big.mark = ",", scientific = FALSE, trim = TRUE),
          " / ",
          format(occ_n, big.mark = ",", scientific = FALSE, trim = TRUE),
          ")"
        )
      } else {
        "No current app-sample mapped fraction is available yet."
      }
    }
    mapped_pct_total_notice <- {
      total_pct <- if (is.finite(occ_total_all_available) && occ_total_all_available > 0 && is.finite(mappable_n) && mappable_n >= 0) {
        round(100 * mappable_n / occ_total_all_available, 3)
      } else {
        NA_real_
      }

      if (is.finite(total_pct)) {
        paste0(
          total_pct,
          "% of ALL BIEN observations are currently mapped (",
          format(mappable_n, big.mark = ",", scientific = FALSE, trim = TRUE),
          " / ",
          format(occ_total_all_available, big.mark = ",", scientific = FALSE, trim = TRUE),
          "; sampled subset of all BIEN observations)"
        )
      } else if (!is.null(summary_bundle) && !is.null(summary_bundle$total_all_note) && nzchar(summary_bundle$total_all_note)) {
      paste0(
        "ALL-species BIEN total is not available yet (",
        summary_bundle$total_all_note,
        ")"
      )
      } else {
        "ALL-species BIEN total is still loading."
      }
    }
    mapped_pct_guidance <- tags$span(
      "If this proportion is lower than you want, rerun ",
      tags$code("Query BIEN"),
      " to refresh the randomized sample, or increase ",
      tags$code("Max mapped occurrence points"),
      " in the sidebar."
    )

    make_notice <- function(style, title, message) {
      tags$div(
        style = style,
        tags$strong(title),
        message,
        tags$br(), tags$strong("Mapped fraction (app sample): "), mapped_pct_sample_notice,
        tags$br(), tags$strong("Mapped fraction (ALL BIEN observations): "), mapped_pct_total_notice,
        tags$br(), tags$strong("Adjustment: "), mapped_pct_guidance
      )
    }

    if (identical(res$occ_strategy, "fallback_relaxed_native") || identical(res$occ_strategy, "fallback_relaxed_geo")) {
      return(make_notice(
        "background:#fff3cd;border:1px solid #ffe69c;color:#664d03;padding:10px 12px;border-radius:6px;margin:8px 0;",
        "Filter relaxation note: ",
        tags$span(
          "The current result used a fallback BIEN strategy (",
          tags$code(res$occ_strategy),
          ") to recover records. Interpret native/geovalid conclusions cautiously."
        )
      ))
    }

    if (is_bien_connection_error(res$query_errors)) {
      return(make_notice(
        "background:#f8d7da;border:1px solid #f1aeb5;color:#842029;padding:10px 12px;border-radius:6px;margin:8px 0;",
        "BIEN connection note: ",
        "The public BIEN database is temporarily at capacity or refusing new connections, so this query could not retrieve occurrence records right now. Please try `Query BIEN` again shortly."
      ))
    }

    if (occ_n > 0 && mappable_n == 0 && has_range) {
      return(make_notice(
        "background:#fff3cd;border:1px solid #ffe69c;color:#664d03;padding:10px 12px;border-radius:6px;margin:8px 0;",
        "Overview note: ",
        "BIEN returned occurrence rows for this species, but not usable latitude/longitude coordinates in the current response. The map below is showing the BIEN range polygon instead."
      ))
    }

    if (occ_n > 0 && mappable_n == 0 && isTRUE(res$include_range_query)) {
      return(make_notice(
        "background:#cff4fc;border:1px solid #9eeaf9;color:#055160;padding:10px 12px;border-radius:6px;margin:8px 0;",
        "Overview note: ",
        "Occurrence rows were returned without usable coordinates. Open the Range tab to load BIEN's optional range layer for this species."
      ))
    }

    if (occ_n > 0 && mappable_n == 0) {
      return(make_notice(
        "background:#f8d7da;border:1px solid #f1aeb5;color:#842029;padding:10px 12px;border-radius:6px;margin:8px 0;",
        "Overview note: ",
        paste0(
          "Occurrence rows were returned, but no usable latitude/longitude coordinates are available to map under the current filter settings.",
          " This is a BIEN data availability limitation, not an app error.",
          " To recover a map: (1) uncheck 'Keep only BIEN geovalid coordinates' in the sidebar to include non-geovalid records,",
          " or (2) turn on 'Load BIEN range layers when the Range tab is opened' and re-query to display the BIEN range polygon instead.",
          " See the Observations tab to inspect the returned rows and their coordinate fields."
        )
      ))
    }

    if (isTRUE(res$occurrences_prepared$map_cap_applied)) {
      return(make_notice(
        "background:#cff4fc;border:1px solid #9eeaf9;color:#055160;padding:10px 12px;border-radius:6px;margin:8px 0;",
        "Overview note: ",
        "The map below is showing a capped subset of mappable occurrence points for responsiveness. The full returned occurrence table remains available in the Observations tab."
      ))
    }

    if (occ_n > 0) {
      return(tags$div(
        style = "background:#e9f7ef;border:1px solid #badbcc;color:#0f5132;padding:10px 12px;border-radius:6px;margin:8px 0;",
        tags$strong("Mapped fraction (app sample): "), mapped_pct_sample_notice,
        tags$br(), tags$strong("Mapped fraction (ALL BIEN observations): "), mapped_pct_total_notice,
        tags$br(), tags$strong("Adjustment: "), mapped_pct_guidance
      ))
    }

    NULL
  })

  output$slow_query_alert <- renderUI({
    res <- bien_results()
    elapsed <- suppressWarnings(as.numeric(res$query_elapsed_sec))
    if (isTRUE(res$cache_hit) || is.na(elapsed) || elapsed < 25) {
      return(NULL)
    }

    reasons <- c()
    if (isTRUE(res$only_geovalid)) {
      reasons <- c(reasons, "geovalid-only filtering")
    }
    if (isTRUE(res$use_introduced_filter) && isTRUE(res$natives_only)) {
      reasons <- c(reasons, "native-only filtering")
    }
    if (!is.null(res$occ_limit) && is.finite(res$occ_limit) && res$occ_limit >= 1000) {
      reasons <- c(reasons, paste0("large app sample request (", res$occ_limit, " rows)"))
    }
    if (identical(res$occ_strategy, "fallback_relaxed_native") || identical(res$occ_strategy, "fallback_relaxed_geo")) {
      reasons <- c(reasons, "fallback retries after strict query")
    }
    if (length(res$query_errors) > 0 && any(grepl("elapsed time limit|timeout", res$query_errors, ignore.case = TRUE))) {
      reasons <- c(reasons, "BIEN backend timeout/retry behavior")
    }
    reasons <- unique(reasons)
    reason_txt <- if (length(reasons) > 0) paste(reasons, collapse = "; ") else "BIEN backend load and query complexity"

    tags$div(
      style = "background:#fff3cd;border:1px solid #ffe69c;color:#664d03;padding:10px 12px;border-radius:6px;margin:8px 0;",
      tags$strong("Slow query notice: "),
      paste0("This run took ", elapsed, " seconds for ", res$species, "."),
      tags$br(),
      tags$strong("Likely cause: "), reason_txt,
      tags$br(),
      tags$strong("Speed-up options: "),
      "keep Fast mode for large species enabled, reduce occurrence/map limits, or relax strict native/geovalid filters for initial preview.",
      tags$br(),
      tags$strong("Good news: "),
      "you can still explore the returned sample now and load optional BIEN totals later with the summary button."
    )
  })

  output$occurrence_map <- renderLeaflet({
    res <- bien_results()
    occ_info <- res$occurrences_prepared
    cached_range <- get_cached_result(range_cache, res$query_cache_key)
    cached_range_sf <- if (!is.null(cached_range)) cached_range$range_sf else NULL

    map <- leaflet() %>% addProviderTiles(providers$Esri.WorldStreetMap)

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

    map %>% fitBounds(
      lng1 = min(df[[lon_col]], na.rm = TRUE),
      lat1 = min(df[[lat_col]], na.rm = TRUE),
      lng2 = max(df[[lon_col]], na.rm = TRUE),
      lat2 = max(df[[lat_col]], na.rm = TRUE)
    )
  })

  output$community_map <- renderLeaflet({
    res <- bien_results()
    bundle <- get_plot_community_bundle(res)
    plot_info <- bundle$prepared

    map <- leaflet() %>% addProviderTiles(providers$Esri.WorldStreetMap)

    if (is.null(plot_info$data) || !is.data.frame(plot_info$data) || nrow(plot_info$data) == 0 || is.null(plot_info$lat_col) || is.null(plot_info$lon_col)) {
      return(map %>% setView(lng = 0, lat = 20, zoom = 2))
    }

    df <- plot_info$data
    lat_col <- plot_info$lat_col
    lon_col <- plot_info$lon_col

    map <- map %>% addCircleMarkers(
      lng = df[[lon_col]],
      lat = df[[lat_col]],
      radius = 4,
      stroke = FALSE,
      fillColor = "#2C7BB6",
      fillOpacity = 0.8,
      popup = make_popup_text(df)
    )

    map %>% fitBounds(
      lng1 = min(df[[lon_col]], na.rm = TRUE),
      lat1 = min(df[[lat_col]], na.rm = TRUE),
      lng2 = max(df[[lon_col]], na.rm = TRUE),
      lat2 = max(df[[lat_col]], na.rm = TRUE)
    )
  })

  output$community_map_ui <- renderUI({
    res <- bien_results()
    bundle <- get_plot_community_bundle(res)
    prepared <- bundle$prepared
    mappable_n <- if (is.list(prepared) && is.data.frame(prepared$data)) nrow(prepared$data) else 0

    if (mappable_n > 0) {
      return(leafletOutput("community_map", height = 550))
    }

    tags$div(style = "height:0;")
  })

  output$community_notice <- renderUI({
    res <- bien_results()
    bundle <- get_plot_community_bundle(res)
    plot_df <- bundle$raw
    prepared <- bundle$prepared
    mappable_n <- if (is.list(prepared) && is.data.frame(prepared$data)) nrow(prepared$data) else 0

    # Timeout/blank map guidance message
    timeout_or_blank <- FALSE
    timeout_msg <- NULL
    # Check for timeout or zero results
    if (!is.data.frame(res$occurrences) || nrow(res$occurrences) == 0) {
      timeout_or_blank <- TRUE
      timeout_msg <- "No occurrence rows are loaded yet for this species. This may be due to a temporary timeout or strict filter settings."
    } else if (!is.data.frame(plot_df) || nrow(plot_df) == 0) {
      timeout_or_blank <- TRUE
      timeout_msg <- "No records were categorized as Plot / survey for the current species and filters. Try another species or broaden filters."
    } else if (mappable_n == 0) {
      timeout_or_blank <- TRUE
      timeout_msg <- paste0("Plot / survey records found (", nrow(plot_df), "), but none currently have usable coordinates for mapping.")
    }

    if (timeout_or_blank) {
      return(tags$div(
        style = "background:#f8d7da;border:2px solid #f1aeb5;color:#842029;padding:12px 14px;border-radius:8px;margin:10px 0;font-size:1.08em;",
        tags$p(timeout_msg),
        tags$p(
          style = "margin-top:8px;",
          tags$strong("Tip: "),
          "If you encountered a timeout or blank map, don't give up! Try clicking ",
          tags$code("Query BIEN"),
          " again, or try unchecking the ",
          tags$strong("Conservative default profile ⓘ"),
          " box above and rerun your query. This often recovers results for challenging species."
        )
      ))
    }

    tags$div(
      style = "background:#e9f7ef;border:1px solid #badbcc;color:#0f5132;padding:8px 10px;border-radius:6px;margin:8px 0;",
      paste0("Mapped ", format(mappable_n, big.mark = ",", scientific = FALSE, trim = TRUE), " plot/survey points for ", res$species, ".")
    )
  })

  output$community_summary <- renderUI({
    res <- bien_results()
    bundle <- get_plot_community_bundle(res)
    summarize_plot_community(bundle$raw, bundle$prepared)
  })

  output$temporal_stats <- renderUI({
    res <- req(bien_results())
    stats <- summarize_temporal_stats(res$occurrences)
    pct_with_dates <- if (stats$total_records > 0) round(100 * stats$records_with_dates / stats$total_records, 1) else 0
    total_records_label <- format(stats$total_records, big.mark = ",", scientific = FALSE, trim = TRUE)

    HTML(paste(
      sprintf("Total records: <strong>%s</strong>", total_records_label),
      sprintf("With dates: <strong>%d (%.1f%%)</strong>", stats$records_with_dates, pct_with_dates),
      if (!is.na(stats$earliest_year)) sprintf("Earliest: <strong>%d</strong>", stats$earliest_year) else "",
      if (!is.na(stats$latest_year)) sprintf("Latest: <strong>%d</strong>", stats$latest_year) else "",
      if (!is.na(stats$span_years)) sprintf("Span: <strong>%d years</strong>", stats$span_years) else "",
      if (!is.na(stats$median_year)) sprintf("Median year: <strong>%d</strong>", stats$median_year) else "",
      sep = "<br>"
    ))
  })

  output$temporal_histogram <- renderPlot({
    res <- bien_results()
    if (!is.data.frame(res$occurrences) || nrow(res$occurrences) == 0) {
      plot.new()
      text(0.5, 0.5, "No occurrence records available for temporal plotting.", cex = 1.1)
      return(invisible(NULL))
    }

    year_range <- input$temporal_year_range
    year_min <- if (!is.null(year_range) && length(year_range) == 2) year_range[1] else 1700
    year_max <- if (!is.null(year_range) && length(year_range) == 2) year_range[2] else 2030

    temporal_df <- bin_temporal_data(res$occurrences, year_min = year_min, year_max = year_max)
    if (is.null(temporal_df) || nrow(temporal_df) == 0) {
      plot.new()
      text(0.5, 0.55, "No dated records in the selected year range.", cex = 1.1)
      text(0.5, 0.43, "Try widening the year filter or checking a different species.", cex = 0.95)
      return(invisible(NULL))
    }

    category_colors <- c(
      "Specimen / herbarium" = "#8B4513",
      "Plot / survey" = "#2E7D32",
      "Citizen science (iNaturalist)" = "#F57C00",
      "Field observation (HumanObservation)" = "#1976D2",
      "GBIF / other aggregator" = "#7B1FA2",
      "Other / unknown" = "#757575"
    )

    ggplot(temporal_df, aes(x = decade_bin, y = count, fill = observation_category)) +
      geom_col(position = "stack", width = 8) +
      scale_fill_manual(values = category_colors, name = "Observation Category", drop = FALSE) +
      labs(
        title = paste0(res$species, " - Observations by Decade"),
        x = "Collection Year (decade)",
        y = "Number of Records"
      ) +
      scale_x_continuous(
        breaks = seq(floor(year_min / 10) * 10, ceiling(year_max / 10) * 10, by = 20),
        labels = function(x) paste0(x, "s")
      ) +
      theme_minimal() +
      theme(
        axis.text.x = element_text(angle = 45, hjust = 1),
        legend.position = "right",
        panel.grid.minor = element_blank()
      )
  })

  # Summarize the currently selected biological filters in plain language so users
  # can see immediately what kind of occurrence evidence is being requested.
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
      return("")
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
    range_bundle <- range_results()
    occ_info <- res$occurrences_prepared
    occ_df <- if (is.list(occ_info) && is.data.frame(occ_info$data)) occ_info$data else NULL
    occ_lat_col <- if (is.list(occ_info)) occ_info$lat_col else NULL
    occ_lon_col <- if (is.list(occ_info)) occ_info$lon_col else NULL
    has_occ_points <- is.data.frame(occ_df) && nrow(occ_df) > 0 && !is.null(occ_lat_col) && !is.null(occ_lon_col)

    map <- leaflet() %>%
      addProviderTiles(providers$Esri.WorldStreetMap) %>%
      addMapPane("rangePane", zIndex = 410) %>%
      addMapPane("occPane", zIndex = 420)

    add_occ_points <- function(map_obj) {
      if (!isTRUE(has_occ_points)) {
        return(map_obj)
      }
      map_obj %>% addCircleMarkers(
        lng = occ_df[[occ_lon_col]],
        lat = occ_df[[occ_lat_col]],
        radius = 3,
        stroke = FALSE,
        fillColor = "#d73027",
        fillOpacity = 0.75,
        options = pathOptions(pane = "occPane"),
        popup = make_popup_text(occ_df)
      )
    }

    if (!(inherits(range_bundle$range_sf, "sf") && nrow(range_bundle$range_sf) > 0)) {
      map <- add_occ_points(map)
      if (isTRUE(has_occ_points)) {
        return(map %>% fitBounds(
          lng1 = min(occ_df[[occ_lon_col]], na.rm = TRUE),
          lat1 = min(occ_df[[occ_lat_col]], na.rm = TRUE),
          lng2 = max(occ_df[[occ_lon_col]], na.rm = TRUE),
          lat2 = max(occ_df[[occ_lat_col]], na.rm = TRUE)
        ))
      }
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
        options = pathOptions(pane = "rangePane"),
        popup = bien_results()$species
      )
    } else {
      map <- map %>% addCircleMarkers(
        data = sf_obj,
        radius = 4,
        stroke = FALSE,
        fillOpacity = 0.7,
        options = pathOptions(pane = "rangePane")
      )
    }

    map <- add_occ_points(map)

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
