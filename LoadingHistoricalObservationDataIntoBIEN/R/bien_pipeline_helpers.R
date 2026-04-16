canonicalize_bien_header <- function(x) {
  out <- tolower(trimws(as.character(x)))
  out <- gsub("[^a-z0-9]+", "_", out)
  gsub("(^_+|_+$)", "", out)
}

canonicalize_join_values <- function(x) {
  vals <- trimws(as.character(x))
  vals[is.na(vals) | vals == ""] <- NA_character_
  tolower(vals)
}

safe_bien_runtime_call <- function(expr) {
  tryCatch(expr, error = function(e) e)
}

is_bien_runtime_available <- function() {
  requireNamespace("BIEN", quietly = TRUE)
}

get_bien_reference_fields <- local({
  cache <- NULL

  function() {
    if (!is.null(cache)) {
      return(cache)
    }

    fallback <- c(
      "scrubbed_species_binomial", "scrubbed_family", "scrubbed_genus", "scrubbed_author",
      "scrubbed_taxonomic_status", "latitude", "longitude", "date_collected", "dataset",
      "datasource", "dataowner", "collection_code", "trait_name", "trait_value", "unit",
      "method", "country", "stateProvince", "county", "locality"
    )

    if (!is_bien_runtime_available()) {
      cache <<- fallback
      return(cache)
    }

    occ <- safe_bien_runtime_call(
      BIEN::BIEN_occurrence_species(
        "Pinus ponderosa",
        cultivated = FALSE,
        natives.only = TRUE,
        only.geovalid = TRUE,
        all.taxonomy = TRUE,
        limit = 1,
        record_limit = 1,
        fetch.query = FALSE
      )
    )
    traits <- safe_bien_runtime_call(
      BIEN::BIEN_trait_species(
        "Pinus ponderosa",
        all.taxonomy = TRUE,
        source.citation = TRUE,
        limit = 1,
        record_limit = 1,
        fetch.query = FALSE
      )
    )

    occ_fields <- if (is.data.frame(occ)) names(occ) else character(0)
    trait_fields <- if (is.data.frame(traits)) names(traits) else character(0)
    cache <<- unique(c(occ_fields, trait_fields, fallback))
    cache
  }
})

get_bien_field_aliases <- function() {
  list(
    scrubbed_species_binomial = c("scientificname", "scientific_name", "species", "species_name", "taxon", "taxon_name"),
    latitude = c("decimallatitude", "latitude", "lat", "y"),
    longitude = c("decimallongitude", "longitude", "long", "lon", "x"),
    date_collected = c("eventdate", "date", "collection_date", "sample_date"),
    trait_name = c("measurementtype", "trait_name", "trait", "variable", "measurement_name", "dbh"),
    trait_value = c("measurementvalue", "trait_value", "value", "dbh", "diameter"),
    unit = c("measurementunit", "unit", "units", "trait_unit"),
    locality = c("locality", "plot_name", "plot", "site", "site_name", "location"),
    country = c("country", "country_name"),
    stateProvince = c("stateprovince", "state_province", "state", "province"),
    county = c("county", "municipality")
  )
}

suggest_bien_field <- function(column_name, bien_reference_fields = get_bien_reference_fields()) {
  col_norm <- canonicalize_bien_header(column_name)
  bien_norm <- canonicalize_bien_header(bien_reference_fields)

  exact_idx <- which(bien_norm == col_norm)
  if (length(exact_idx) > 0) {
    return(list(field = bien_reference_fields[[exact_idx[[1]]]], confidence = "high", reason = "exact_header_match"))
  }

  aliases <- get_bien_field_aliases()
  for (field in names(aliases)) {
    alias_norm <- canonicalize_bien_header(aliases[[field]])
    if (col_norm %in% alias_norm) {
      return(list(field = field, confidence = "medium", reason = "alias_match"))
    }
  }

  list(field = "", confidence = "low", reason = "no_bien_match")
}

infer_file_role <- function(df) {
  cols <- canonicalize_bien_header(names(df))
  observation_terms <- c("scientificname", "scientific_name", "species", "species_name", "taxon", "dbh", "diameter", "measurementvalue", "trait_value")
  metadata_terms <- c("plot_name", "plot", "site", "site_name", "locality", "country", "stateprovince", "county", "latitude", "lat", "longitude", "lon")

  observation_score <- sum(cols %in% observation_terms)
  metadata_score <- sum(cols %in% metadata_terms)

  role <- if (observation_score > metadata_score) {
    "observation"
  } else if (metadata_score > observation_score) {
    "metadata"
  } else {
    "mixed"
  }

  list(
    role = role,
    observation_score = observation_score,
    metadata_score = metadata_score,
    role_reason = paste0("observation_score=", observation_score, "; metadata_score=", metadata_score)
  )
}

score_join_columns <- function(primary_vec, metadata_vec) {
  p_vals <- unique(stats::na.omit(canonicalize_join_values(primary_vec)))
  m_vals <- unique(stats::na.omit(canonicalize_join_values(metadata_vec)))

  p_vals <- utils::head(p_vals, 500)
  m_vals <- utils::head(m_vals, 500)

  if (length(p_vals) == 0 || length(m_vals) == 0) {
    return(list(shared = 0L, primary_overlap = 0, metadata_overlap = 0, score = 0))
  }

  shared <- intersect(p_vals, m_vals)
  primary_overlap <- length(shared) / length(p_vals)
  metadata_overlap <- length(shared) / length(m_vals)
  score <- length(shared) * ((primary_overlap + metadata_overlap) / 2)

  list(
    shared = length(shared),
    primary_overlap = round(primary_overlap, 3),
    metadata_overlap = round(metadata_overlap, 3),
    score = round(score, 3)
  )
}

is_likely_join_key_name <- function(col_name) {
  key_tokens <- c(
    "plot", "plot_id", "plotid", "site", "site_id", "locality", "location",
    "eventid", "sampleid", "sample_id", "occurrenceid", "station", "transect", "quadrat"
  )
  canon <- canonicalize_bien_header(col_name)
  any(vapply(key_tokens, function(tok) grepl(tok, canon, fixed = TRUE), logical(1)))
}

is_likely_measurement_column <- function(col_name) {
  measurement_tokens <- c("dbh", "diameter", "height", "trait", "measurement", "value", "mass", "biomass")
  canon <- canonicalize_bien_header(col_name)
  any(vapply(measurement_tokens, function(tok) grepl(tok, canon, fixed = TRUE), logical(1)))
}

adjust_join_score <- function(base_score, primary_col, metadata_col) {
  adj <- base_score

  primary_is_key <- is_likely_join_key_name(primary_col)
  metadata_is_key <- is_likely_join_key_name(metadata_col)
  primary_is_measure <- is_likely_measurement_column(primary_col)
  metadata_is_measure <- is_likely_measurement_column(metadata_col)

  if (primary_is_key) adj <- adj * 1.35
  if (metadata_is_key) adj <- adj * 1.35
  if (canonicalize_bien_header(primary_col) == canonicalize_bien_header(metadata_col)) {
    adj <- adj * 1.2
  }

  if (primary_is_measure || metadata_is_measure) {
    adj <- adj * 0.4
  }

  round(adj, 3)
}

suggest_merge_plan <- function(data_list) {
  if (length(data_list) == 0) {
    return(list(primary_file = NULL, primary_key = NULL, metadata_files = character(0), file_summary = data.frame(), join_suggestions = data.frame()))
  }

  file_summary <- lapply(names(data_list), function(file_name) {
    df <- data_list[[file_name]]
    role <- infer_file_role(df)
    data.frame(
      file = file_name,
      rows = nrow(df),
      cols = ncol(df),
      role_suggestion = role$role,
      observation_score = role$observation_score,
      metadata_score = role$metadata_score,
      role_reason = role$role_reason,
      stringsAsFactors = FALSE
    )
  })
  file_summary <- do.call(rbind, file_summary)
  file_summary <- file_summary[order(-file_summary$observation_score, -file_summary$rows), , drop = FALSE]

  primary_file <- file_summary$file[[1]]
  primary_df <- data_list[[primary_file]]

  join_rows <- list()
  for (metadata_file in setdiff(names(data_list), primary_file)) {
    metadata_df <- data_list[[metadata_file]]
    best <- NULL

    for (primary_col in names(primary_df)) {
      for (metadata_col in names(metadata_df)) {
        this_score <- score_join_columns(primary_df[[primary_col]], metadata_df[[metadata_col]])
        if (this_score$shared == 0) {
          next
        }

        candidate <- data.frame(
          primary_file = primary_file,
          primary_key = primary_col,
          metadata_file = metadata_file,
          metadata_key = metadata_col,
          shared_unique_values = this_score$shared,
          primary_overlap = this_score$primary_overlap,
          metadata_overlap = this_score$metadata_overlap,
          score = adjust_join_score(this_score$score, primary_col, metadata_col),
          key_name_hint = ifelse(
            is_likely_join_key_name(primary_col) || is_likely_join_key_name(metadata_col),
            "join_key_like",
            ifelse(
              is_likely_measurement_column(primary_col) || is_likely_measurement_column(metadata_col),
              "measurement_like",
              "neutral"
            )
          ),
          stringsAsFactors = FALSE
        )

        if (is.null(best) || candidate$score[[1]] > best$score[[1]]) {
          best <- candidate
        }
      }
    }

    if (!is.null(best)) {
      join_rows[[length(join_rows) + 1]] <- best
    }
  }

  join_suggestions <- if (length(join_rows) > 0) do.call(rbind, join_rows) else data.frame()
  metadata_files <- if (is.data.frame(join_suggestions) && nrow(join_suggestions) > 0) join_suggestions$metadata_file else setdiff(names(data_list), primary_file)
  primary_key <- if (is.data.frame(join_suggestions) && nrow(join_suggestions) > 0) join_suggestions$primary_key[[1]] else names(primary_df)[[1]]

  list(
    primary_file = primary_file,
    primary_key = primary_key,
    metadata_files = metadata_files,
    file_summary = file_summary,
    join_suggestions = join_suggestions
  )
}

local_taxonomy_triage <- function(scientific_names) {
  x <- trimws(as.character(scientific_names))
  x[is.na(x)] <- ""

  status <- ifelse(
    x == "",
    "unresolved_blank",
    ifelse(grepl("\\b(sp|spp|cf|aff|indet)\\.?$", tolower(x)), "review_uncertain_name", "pending_external_backbone")
  )

  data.frame(
    scientificName = x,
    bien_matched_name = ifelse(x == "", NA_character_, x),
    bien_taxonomy_status = status,
    bien_family = NA_character_,
    stringsAsFactors = FALSE
  )
}

augment_bien_pipeline <- function(dwc_df, taxonomy_cap = 50) {
  if (!is.data.frame(dwc_df) || nrow(dwc_df) == 0) {
    stop("dwc_df must be a non-empty data.frame")
  }

  out <- dwc_df

  if (all(c("decimalLatitude", "decimalLongitude") %in% names(out))) {
    lat <- suppressWarnings(as.numeric(out$decimalLatitude))
    lon <- suppressWarnings(as.numeric(out$decimalLongitude))
    out$coordinate_valid_basic <- !is.na(lat) & !is.na(lon) & lat >= -90 & lat <= 90 & lon >= -180 & lon <= 180
    out$coordinate_issue <- ifelse(
      is.na(lat) | is.na(lon),
      "missing_coordinates",
      ifelse(out$coordinate_valid_basic, NA_character_, "out_of_bounds_or_non_numeric")
    )
  } else {
    out$coordinate_valid_basic <- NA
    out$coordinate_issue <- "coordinates_not_mapped"
  }

  if (!"scientificName" %in% names(out)) {
    out$bien_matched_name <- NA_character_
    out$bien_taxonomy_status <- "scientificName_not_mapped"
    out$bien_family <- NA_character_
    return(out)
  }

  unique_names <- unique(trimws(as.character(out$scientificName)))
  unique_names <- unique_names[!is.na(unique_names) & unique_names != ""]
  unique_names <- utils::head(unique_names, taxonomy_cap)

  tax_lookup <- if (length(unique_names) == 0) {
    local_taxonomy_triage(character(0))
  } else if (!is_bien_runtime_available()) {
    local_taxonomy_triage(unique_names)
  } else {
    rows <- lapply(unique_names, function(one_name) {
      tax_res <- safe_bien_runtime_call(BIEN::BIEN_taxonomy_species(one_name))
      if (is.data.frame(tax_res) && nrow(tax_res) > 0) {
        data.frame(
          scientificName = one_name,
          bien_matched_name = as.character(tax_res$scrubbed_species_binomial[[1]]),
          bien_taxonomy_status = as.character(tax_res$scrubbed_taxonomic_status[[1]]),
          bien_family = as.character(tax_res$scrubbed_family[[1]]),
          stringsAsFactors = FALSE
        )
      } else {
        local_taxonomy_triage(one_name)
      }
    })
    do.call(rbind, rows)
  }

  out <- merge(out, tax_lookup, by = "scientificName", all.x = TRUE, sort = FALSE)
  out$tnrs_status <- ifelse(
    is.na(out$scientificName) | trimws(as.character(out$scientificName)) == "",
    "missing_scientificName",
    ifelse(grepl("unresolved|review", out$bien_taxonomy_status, ignore.case = TRUE), "review_needed", "ready_for_tnrs_or_backbone_check")
  )
  out$gnrs_status <- ifelse(
    all(c("country", "stateProvince", "county", "locality") %in% names(out)),
    ifelse(
      trimws(ifelse(is.na(out$locality), "", as.character(out$locality))) != "" |
        trimws(ifelse(is.na(out$country), "", as.character(out$country))) != "",
      "ready_for_gnrs",
      "missing_geography"
    ),
    "missing_geography"
  )
  out$gvs_status <- ifelse(isTRUE(out$coordinate_valid_basic), "ready_for_gvs", "review_coordinates")
  out$nsr_status <- ifelse(
    !is.na(out$scientificName) & trimws(as.character(out$scientificName)) != "" & "country" %in% names(out),
    "ready_for_nsr",
    "missing_inputs"
  )

  out$gnrs_query_id <- if ("occurrenceID" %in% names(out)) {
    as.character(out$occurrenceID)
  } else {
    paste0("row_", seq_len(nrow(out)))
  }
  out$gnrs_input_country <- if ("country" %in% names(out)) trimws(as.character(out$country)) else NA_character_
  out$gnrs_input_stateProvince <- if ("stateProvince" %in% names(out)) trimws(as.character(out$stateProvince)) else NA_character_
  out$gnrs_input_county <- if ("county" %in% names(out)) trimws(as.character(out$county)) else NA_character_
  out$gnrs_input_locality <- if ("locality" %in% names(out)) trimws(as.character(out$locality)) else NA_character_
  out$gnrs_ready_for_submission <-
    (!is.na(out$gnrs_input_country) & out$gnrs_input_country != "") |
    (!is.na(out$gnrs_input_locality) & out$gnrs_input_locality != "")

  out
}

# ---- BIEN web service API helpers ----
library(httr)

bien_tnrs_query <- function(names) {
  # POST to BIEN TNRS API (example endpoint)
  # names: character vector
  if (length(names) == 0) return(data.frame())
  url <- "https://bien.nceas.ucsb.edu/bien/api/tnrs"
  resp <- httr::POST(url, body = list(names = names), encode = "json")
  stop_for_status(resp)
  content <- httr::content(resp, as = "parsed")
  # Return as data.frame (adapt to actual API response)
  as.data.frame(content)
}

bien_gnrs_query <- function(locations) {
  # POST to BIEN GNRS API (example endpoint)
  if (length(locations) == 0) return(data.frame())
  url <- "https://bien.nceas.ucsb.edu/bien/api/gnrs"
  resp <- httr::POST(url, body = list(locations = locations), encode = "json")
  stop_for_status(resp)
  content <- httr::content(resp, as = "parsed")
  as.data.frame(content)
}

bien_gvs_query <- function(coords) {
  # POST to BIEN GVS API (example endpoint)
  if (length(coords) == 0) return(data.frame())
  url <- "https://bien.nceas.ucsb.edu/bien/api/gvs"
  resp <- httr::POST(url, body = list(coords = coords), encode = "json")
  stop_for_status(resp)
  content <- httr::content(resp, as = "parsed")
  as.data.frame(content)
}

bien_nsr_query <- function(names) {
  # POST to BIEN NSR API (example endpoint)
  if (length(names) == 0) return(data.frame())
  url <- "https://bien.nceas.ucsb.edu/bien/api/nsr"
  resp <- httr::POST(url, body = list(names = names), encode = "json")
  stop_for_status(resp)
  content <- httr::content(resp, as = "parsed")
  as.data.frame(content)
}
# ---- End BIEN web service API helpers ----