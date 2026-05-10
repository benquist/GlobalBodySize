# Load required packages, installing any missing CRAN dependencies on startup.
suppressPackageStartupMessages({
  required_packages <- c("shiny", "BIEN", "dplyr", "stringr", "leaflet", "DT", "sf", "ggplot2", "jsonlite", "httr")
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
  library(jsonlite)
  library(httr)
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

# Fetch a species photo from iNaturalist (primary) or Wikipedia REST API (fallback).
# Returns list(url, attribution_short, attribution, source_url, inat_name) or NULL.
# Only cc-by, cc-by-sa, and cc0 iNaturalist photos are used; All Rights Reserved and
# NC/ND licenses are rejected to prevent copyright violations in a public deployed app.
# The returned iNaturalist taxon name is validated against the queried name to catch
# silent taxonomic mismatches (estimated 10-30% in complex families).
fetch_species_photo <- function(species_name, timeout_sec = 8) {
  if (!nzchar(trimws(species_name))) return(NULL)

  # --- Primary: Wikipedia REST summary API ---
  # Wikipedia thumbnails are often high-quality curated images.
  # Note: POWO does not expose images via its public API (images array always empty);
  # GBIF is used as the second fallback and includes Kew/herbarium images.
  wiki_result <- tryCatch({
    slug <- gsub(" ", "_", trimws(species_name))
    resp <- httr::GET(
      paste0("https://en.wikipedia.org/api/rest_v1/page/summary/",
             utils::URLencode(slug, reserved = TRUE)),
      httr::timeout(timeout_sec)
    )
    if (httr::http_error(resp)) stop("wiki http error")
    if (!grepl("application/json", httr::http_type(resp), fixed = TRUE)) stop("wiki not json")
    parsed <- jsonlite::fromJSON(
      httr::content(resp, as = "text", encoding = "UTF-8"),
      simplifyVector = FALSE
    )
    thumb_url <- parsed$originalimage$source
    if (is.null(thumb_url) || !nzchar(as.character(thumb_url))) {
      thumb_url <- parsed$thumbnail$source
    }
    if (is.null(thumb_url) || !nzchar(as.character(thumb_url))) stop("wiki no image")
    if (!startsWith(as.character(thumb_url), "https://")) stop("wiki non-https url")
    list(
      url               = as.character(thumb_url),
      attribution_short = "Wikipedia",
      attribution       = "Wikimedia Commons",
      source_url        = paste0("https://en.wikipedia.org/wiki/",
                                 utils::URLencode(slug, reserved = TRUE)),
      inat_name         = NULL
    )
  }, error = function(e) NULL)

  if (!is.null(wiki_result)) return(wiki_result)

  # --- Second: GBIF occurrence media ---
  # POWO does not expose images via its public API (images field always empty).
  # GBIF aggregates images from Kew herbarium, iNaturalist, NYBG, Smithsonian, and
  # hundreds of other institutions — the best available open aggregator.
  # Two-step: (1) species/match to get usageKey, (2) occurrence/search with mediaType.
  gbif_result <- tryCatch({
    resp <- httr::GET(
      "https://api.gbif.org/v1/species/match",
      query = list(name = species_name, kingdom = "Plantae", verbose = FALSE),
      httr::timeout(timeout_sec)
    )
    if (httr::http_error(resp)) stop("gbif match http error")
    if (!grepl("application/json", httr::http_type(resp), fixed = TRUE)) stop("gbif not json")
    m <- jsonlite::fromJSON(
      httr::content(resp, as = "text", encoding = "UTF-8"),
      simplifyVector = FALSE
    )
    match_type <- if (!is.null(m$matchType)) as.character(m$matchType) else "NONE"
    if (!match_type %in% c("EXACT", "FUZZY")) stop("gbif no match")
    usage_key <- if (!is.null(m$usageKey)) as.character(m$usageKey) else ""
    if (!nzchar(usage_key)) stop("gbif no usageKey")
    gbif_name <- if (!is.null(m$species)) as.character(m$species) else ""

    resp2 <- httr::GET(
      "https://api.gbif.org/v1/occurrence/search",
      query = list(taxonKey = usage_key, mediaType = "StillImage",
                   limit = 20L, hasCoordinate = FALSE),
      httr::timeout(timeout_sec)
    )
    if (httr::http_error(resp2)) stop("gbif occurrence http error")
    parsed2 <- jsonlite::fromJSON(
      httr::content(resp2, as = "text", encoding = "UTF-8"),
      simplifyVector = FALSE
    )
    results <- parsed2$results
    if (!is.list(results) || length(results) == 0) stop("gbif no occurrences")

    img_url <- NULL; img_creator <- NULL; img_publisher <- NULL; occ_key <- NULL
    for (occ in results) {
      media_list <- occ$media
      if (!is.list(media_list) || length(media_list) == 0) next
      for (med in media_list) {
        url_candidate <- if (!is.null(med$identifier)) as.character(med$identifier) else ""
        if (!nzchar(url_candidate) || !startsWith(url_candidate, "https://")) next
        img_url       <- url_candidate
        img_creator   <- if (!is.null(med$creator)  && nzchar(as.character(med$creator)))  as.character(med$creator)  else NULL
        img_publisher <- if (!is.null(med$publisher) && nzchar(as.character(med$publisher))) as.character(med$publisher) else NULL
        occ_key       <- if (!is.null(occ$key)) as.character(occ$key) else NULL
        break
      }
      if (!is.null(img_url)) break
    }
    if (is.null(img_url)) stop("gbif no valid image url")

    attr_parts <- Filter(Negate(is.null), list(img_creator, img_publisher))
    attribution <- if (length(attr_parts) > 0) paste(attr_parts, collapse = " / ") else "GBIF"
    source_url  <- if (!is.null(occ_key)) {
      paste0("https://www.gbif.org/occurrence/", occ_key)
    } else {
      paste0("https://www.gbif.org/species/", usage_key)
    }
    list(
      url               = img_url,
      attribution_short = "GBIF",
      attribution       = attribution,
      source_url        = source_url,
      inat_name         = gbif_name
    )
  }, error = function(e) NULL)

  if (!is.null(gbif_result)) return(gbif_result)

  # --- Third: iNaturalist taxa API (CC-BY / CC-BY-SA / CC0 only) ---
  allowed_licenses <- c("cc-by", "cc-by-sa", "cc0")
  tryCatch({
    resp <- httr::GET(
      "https://api.inaturalist.org/v1/taxa",
      query = list(q = species_name, rank = "species", per_page = 1L, locale = "en"),
      httr::timeout(timeout_sec)
    )
    if (httr::http_error(resp)) stop("inat http error")
    if (!grepl("application/json", httr::http_type(resp), fixed = TRUE)) stop("inat not json")
    parsed <- jsonlite::fromJSON(
      httr::content(resp, as = "text", encoding = "UTF-8"),
      simplifyVector = FALSE
    )
    results <- parsed$results
    if (!is.list(results) || length(results) == 0) stop("inat no results")
    taxon <- results[[1]]
    inat_name <- if (!is.null(taxon$name)) taxon$name else ""
    if (!identical(tolower(trimws(inat_name)), tolower(trimws(species_name)))) stop("inat name mismatch")
    photo <- taxon$default_photo
    if (is.null(photo)) stop("inat no default photo")
    license_code <- if (!is.null(photo$license_code)) tolower(trimws(as.character(photo$license_code))) else ""
    if (!license_code %in% allowed_licenses) stop("inat license not allowed")
    photo_url <- if (!is.null(photo$large_url) && nzchar(as.character(photo$large_url)) && startsWith(as.character(photo$large_url), "https://")) {
      as.character(photo$large_url)
    } else if (!is.null(photo$medium_url)) {
      as.character(photo$medium_url)
    } else ""
    if (!nzchar(photo_url) || !startsWith(photo_url, "https://")) stop("inat no valid url")
    taxon_id <- if (!is.null(taxon$id)) taxon$id else ""
    attribution <- if (!is.null(photo$attribution) && nzchar(as.character(photo$attribution))) {
      as.character(photo$attribution)
    } else {
      "iNaturalist"
    }
    list(
      url               = photo_url,
      attribution_short = paste0("iNaturalist \u00b7 ", toupper(license_code)),
      attribution       = attribution,
      source_url        = paste0("https://www.inaturalist.org/taxa/", taxon_id),
      inat_name         = inat_name
    )
  }, error = function(e) NULL)
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

  url <- unname(idx[[binomial]])
  # Allowlist: only return URLs with https:// scheme pointing to asianplant.net
  # to prevent supply-chain XSS if the external site is compromised.
  if (!grepl("^https://([a-zA-Z0-9-]+\\.)*asianplant\\.net(/|$)", url)) {
    return(NA_character_)
  }
  url
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
  # Use a direct SQL query with LIMIT instead of BIEN_taxonomy_genus(genus).
  # BIEN_taxonomy_genus() for large genera (e.g. Arctostaphylos, 60+ spp) can
  # return very slowly and exceed R's setTimeLimit interrupt window, hanging
  # the app. Querying bien_taxonomy directly with a LIKE prefix and LIMIT 250
  # is fast and returns more than enough candidates for edit-distance ranking.
  genus_sql <- paste0(
    "SELECT DISTINCT scrubbed_species_binomial FROM bien_taxonomy ",
    "WHERE scrubbed_species_binomial LIKE ", sql_quote_literal(paste0(genus, " %")),
    " AND scrubbed_species_binomial IS NOT NULL",
    " AND scrubbed_species_binomial <> ''",
    " LIMIT 250;"
  )
  genus_rows <- safe_bien_call(
    BIEN:::.BIEN_sql(genus_sql, fetch.query = FALSE),
    timeout_sec = min(timeout_sec, 8)
  )

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
  # NOTE: scrubbed_taxonomic_status = 'Accepted' filter intentionally removed.
  # BIEN taxonomy stores many species (e.g. Arctostaphylos) with status values
  # other than 'Accepted' (e.g. lowercase, NULL, or alternate strings), causing
  # those genera to silently disappear from the autofill. We include all species
  # with a non-null binomial; the occurrence query itself is the ground truth for
  # whether a species has BIEN data.
  sql <- paste0(
    "SELECT DISTINCT b.scrubbed_species_binomial AS taxon ",
    "FROM bien_taxonomy b ",
    "WHERE b.scrubbed_species_binomial IS NOT NULL ",
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
natives_check_with_null_fallback <- function(natives_only = TRUE, strict_no_unknown = FALSE) {
  if (isTRUE(natives_only)) {
    if (isTRUE(strict_no_unknown)) {
      # Strict native: exclude both introduced AND unevaluated (is_introduced IS NULL).
      # Use this for Old-World taxa where BIEN's NSR has no coverage and IS NULL would
      # otherwise re-admit introduced/cultivated New-World records (e.g. Markhamia lutea
      # returning India/Australia/Mexico horticultural records as 'native').
      list(query = "AND is_introduced=0 ")
    } else {
      # Include records where is_introduced = 0 (native) OR is_introduced IS NULL (unknown)
      list(query = "AND (is_introduced=0 OR is_introduced IS NULL) ")
    }
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
query_occurrence_randomized <- function(species_name, cultivated = FALSE, natives_only = TRUE, only_geovalid = TRUE, limit = 1000, record_limit = 500, randomize_order = TRUE, require_coords = FALSE, allow_centroids = FALSE, strict_native_no_unknown = FALSE) {
  cultivated_ <- BIEN:::.cultivated_check(cultivated)
  newworld_ <- BIEN:::.newworld_check(NULL)
  taxonomy_ <- BIEN:::.taxonomy_check(TRUE)
  native_ <- BIEN:::.native_check(TRUE)
  observation_ <- BIEN:::.observation_check(TRUE)
  political_ <- BIEN:::.political_check(FALSE)
  natives_ <- natives_check_with_null_fallback(natives_only, strict_no_unknown = strict_native_no_unknown)
  collection_ <- BIEN:::.collection_check(FALSE)
  geovalid_ <- BIEN:::.geovalid_check(only_geovalid)

  # Skip randomization for large fetches and also for very small-limit fallback plans.
  # ORDER BY random() LIMIT N requires scoring all matching rows even for tiny N,
  # which can take minutes on species with 500k+ occurrences (e.g. Solidago canadensis).
  # For limit <= 500, natural table order + R-side stratified sampling is sufficient.
  use_randomize <- isTRUE(randomize_order) && limit > 500 && limit <= 10000
  order_clause <- if (use_randomize) "ORDER BY random()" else ""

  # When require_coords=TRUE, add SQL-level filter requiring at least one valid coordinate source.
  # Accept records where either the float lat/lon is in-range OR a PostGIS geom is present.
  # Records with non-null but out-of-range floats AND no geom are excluded.
  coord_bearing_clause <- if (isTRUE(require_coords)) {
    paste(
      "AND (geom IS NOT NULL",
      "OR (latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180))"
    )
  } else {
    ""
  }

  centroid_clause <- if (isTRUE(allow_centroids)) "" else paste(
    "AND (georef_protocol is NULL OR georef_protocol<>'county centroid')",
    "AND (is_centroid IS NULL OR is_centroid=0)"
  )

  query <- paste(
    "SELECT scrubbed_species_binomial", taxonomy_$select,
    native_$select, political_$select,
    # Use COALESCE with a range guard so that:
    # (1) valid float lat/lon is used when available
    # (2) out-of-range non-null floats fall through to the PostGIS geom column
    # (3) geom IS NULL when both sources unavailable → NULL (safe, no exception)
    # ST_Y/ST_X on NULL::geometry = NULL; geography→geometry cast is always safe.
    ",COALESCE(CASE WHEN latitude BETWEEN -90 AND 90 THEN latitude ELSE NULL END, ST_Y(geom::geometry)) AS latitude,",
    "COALESCE(CASE WHEN longitude BETWEEN -180 AND 180 THEN longitude ELSE NULL END, ST_X(geom::geometry)) AS longitude,",
    "date_collected,",
    "datasource,dataset,dataowner,custodial_institution_codes,collection_code,view_full_occurrence_individual.datasource_id",
    collection_$select, cultivated_$select, newworld_$select,
    observation_$select, geovalid_$select,
    "FROM view_full_occurrence_individual",
    "WHERE scrubbed_species_binomial in (", paste(sql_quote_literal(species_name), collapse = ", "), ")",
    cultivated_$query, newworld_$query, natives_$query,
    observation_$query, geovalid_$query,
    "AND higher_plant_group NOT IN ('Algae','Bacteria','Fungi')",
    centroid_clause,
    "AND scrubbed_species_binomial IS NOT NULL",
    coord_bearing_clause,
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
      strict_native_no_unknown = FALSE,
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
    strict_native_no_unknown = if (is.null(input$strict_native_no_unknown)) FALSE else isTRUE(input$strict_native_no_unknown),
    use_cultivated_filter = if (is.null(input$use_cultivated_filter)) TRUE else isTRUE(input$use_cultivated_filter),
    include_cultivated = if (is.null(input$include_cultivated)) FALSE else isTRUE(input$include_cultivated),
    only_geovalid = if (is.null(input$only_geovalid)) TRUE else isTRUE(input$only_geovalid),
    exclude_human_observation_records = if (is.null(input$exclude_human_observation_records)) FALSE else isTRUE(input$exclude_human_observation_records),
    only_plot_observations = if (is.null(input$only_plot_observations)) FALSE else isTRUE(input$only_plot_observations)
  )
}

query_occurrence_with_fallback <- function(species_name, input, occ_limit, occ_page_size, timeout_sec, connection_retry = FALSE, max_plans = 5, per_plan_timeout = 25, randomize_order = TRUE) {
  filter_cfg <- resolve_filter_profile(input)
  include_cultivated <- if (filter_cfg$use_cultivated_filter) filter_cfg$include_cultivated else TRUE
  natives_only <- if (filter_cfg$use_introduced_filter) filter_cfg$natives_only else FALSE
  strict_native_no_unknown <- isTRUE(filter_cfg$strict_native_no_unknown) && isTRUE(natives_only)
  only_geovalid <- filter_cfg$only_geovalid

  # Respect larger user-requested sample sizes while keeping an upper guardrail for server stability.
  fast_limit <- min(occ_limit, 50000)
  fast_page_size <- min(occ_page_size, 5000, fast_limit)

  # Try the user-requested interpretation first, then relax native-only and finally
  # geovalid constraints if needed so the app can still show some BIEN evidence.
  # The final fallback_coord_bearing plan adds a SQL-level lat/lon IS NOT NULL guard
  # for species (e.g. Pouteria reticulata) where BIEN's natural table order returns
  # only null-coord records under LIMIT N without ORDER BY.
  # limit=500 on coord_bearing keeps it under the ORDER BY random() threshold (>500)
  # so it runs fast on filtered rows.
  plans <- list(
    list(label = "strict",                  natives.only = natives_only, only.geovalid = only_geovalid, require_coords = FALSE, allow_centroids = FALSE, limit = fast_limit,           record_limit = fast_page_size),
    list(label = "fallback_relaxed_native", natives.only = FALSE,       only.geovalid = only_geovalid, require_coords = FALSE, allow_centroids = FALSE, limit = min(fast_limit, 500), record_limit = min(fast_page_size, 500)),
    list(label = "fallback_relaxed_geo",   natives.only = FALSE,        only.geovalid = FALSE,         require_coords = FALSE, allow_centroids = FALSE, limit = min(fast_limit, 500), record_limit = min(fast_page_size, 500)),
    list(label = "fallback_coord_bearing", natives.only = FALSE,        only.geovalid = FALSE,         require_coords = TRUE,  allow_centroids = FALSE, limit = min(fast_limit, 500), record_limit = min(fast_page_size, 500)),
    # Last resort: allow county centroid georeferenced records (georef_protocol='county centroid'
    # or is_centroid=1). These are imprecise (county-level) but better than no map at all.
    # Triggered only when fallback_coord_bearing also returns 0 rows.
    list(label = "fallback_allow_centroids", natives.only = FALSE,      only.geovalid = FALSE,         require_coords = TRUE,  allow_centroids = TRUE,  limit = min(fast_limit, 500), record_limit = min(fast_page_size, 500))
  )
  # When the strict-only profile is on, suppress the auto-relaxation ladder so
  # that records returned to the UI cannot have silently dropped natives.only or
  # only.geovalid constraints. The user sees strict results or an empty map and
  # an explicit banner — never India/Australia/Mexico records mislabeled as the
  # 'conservative' interpretation of an Old-World native (e.g. Markhamia lutea).
  if (isTRUE(filter_cfg$use_default_profile)) {
    plans <- plans[1]
  } else {
    plans <- plans[seq_len(max(1, min(length(plans), as.integer(max_plans))))]
  }

  # Precompute plan-set membership once so the loop does not recheck on every iteration.
  has_relaxed_geo_plan      <- any(vapply(plans, function(p) identical(p$label, "fallback_relaxed_geo"),     logical(1)))
  has_coord_bearing_plan    <- any(vapply(plans, function(p) identical(p$label, "fallback_coord_bearing"),   logical(1)))
  has_allow_centroids_plan  <- any(vapply(plans, function(p) identical(p$label, "fallback_allow_centroids"), logical(1)))

  notes <- character()
  last_result <- NULL
  # best_nonempty_result: first plan that returned >0 rows (even if 0 mappable coords).
  # Used as a last-resort fallback when coord_bearing also returns 0 rows — e.g. species
  # like Pouteria reticulata where BIEN's view stores is_geovalid=1 but latitude/longitude
  # columns are NULL for every record. In that case we return the data so the user at
  # least sees the statistics table, even though the map will be empty.
  best_nonempty_result <- NULL
  best_nonempty_strategy <- NULL
  attempts_n <- if (isTRUE(connection_retry)) 3 else 1
  query_started <- Sys.time()
  deadline <- query_started + as.numeric(timeout_sec)
  skip_to_relaxed_geo   <- FALSE
  skip_to_coord_bearing <- FALSE
  skip_to_allow_centroids <- FALSE

  for (plan in plans) {
    if (isTRUE(skip_to_relaxed_geo) && !identical(plan$label, "fallback_relaxed_geo") && !identical(plan$label, "fallback_coord_bearing") && !identical(plan$label, "fallback_allow_centroids")) {
      next
    }
    if (isTRUE(skip_to_coord_bearing) && !identical(plan$label, "fallback_coord_bearing") && !identical(plan$label, "fallback_allow_centroids")) {
      next
    }
    if (isTRUE(skip_to_allow_centroids) && !identical(plan$label, "fallback_allow_centroids")) {
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
          require_coords = isTRUE(plan$require_coords),
          allow_centroids = isTRUE(plan$allow_centroids),
          limit = plan$limit,
          record_limit = plan$record_limit,
          randomize_order = randomize_order,
          strict_native_no_unknown = isTRUE(strict_native_no_unknown) && isTRUE(plan$natives.only)
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
      # Save first non-empty result as fallback. Only non-coord-bearing plans are
      # eligible: the coord_bearing plan by construction returns only coord-valid rows,
      # and if it returns 0 rows there is no useful fallback to preserve from it.
      if (is.null(best_nonempty_result) && !isTRUE(plan$require_coords)) {
        best_nonempty_result   <- res$result
        best_nonempty_strategy <- plan$label
      }

      plan_mappable_n <- count_mappable_occurrences(res$result)
      notes <- c(notes, paste0("plan_mappable=", plan_mappable_n, "; plan=", plan$label))

      if (plan_mappable_n == 0) {
        # When strict returns rows but all coords are null, skip directly to the
        # coord_bearing plan (SQL lat/lon IS NOT NULL) without wasting a round-trip
        # on fallback_relaxed_geo which cannot fix table-order-driven null coords.
        if (identical(plan$label, "strict")) {
          if (has_coord_bearing_plan) {
            notes <- c(notes, "zero_mappable_strict_triggered_coord_bearing_pass")
            skip_to_coord_bearing <- TRUE
          } else if (has_relaxed_geo_plan) {
            notes <- c(notes, "zero_mappable_strict_triggered_relaxed_geo_pass")
            skip_to_relaxed_geo <- TRUE
          }
          next
        }

        if ((identical(plan$label, "fallback_relaxed_geo") || identical(plan$label, "fallback_relaxed_native")) && has_coord_bearing_plan) {
          notes <- c(notes, paste0("zero_mappable_on_", plan$label, "_triggered_coord_bearing_pass"))
          skip_to_coord_bearing <- TRUE
          next
        }

        # coord_bearing returned rows but all have null coords (should not happen since
        # it filters lat IS NOT NULL, but guard here just in case).
        if (identical(plan$label, "fallback_coord_bearing") && has_allow_centroids_plan) {
          notes <- c(notes, "zero_mappable_on_coord_bearing_triggered_allow_centroids_pass")
          skip_to_allow_centroids <- TRUE
          next
        }
      }

      tagged <- res$result
      if (is.data.frame(tagged)) tagged$bien_query_strategy <- plan$label
      return(list(data = tagged, strategy = plan$label, notes = notes, limit_used = plan$limit))
    }

    # When fallback_coord_bearing returns 0 rows (no records with lat/lon after all
    # relaxations), try allow_centroids which drops the county-centroid exclusion.
    # This recovers species like Pouteria reticulata where BIEN's only georeferenced
    # records are county centroids — excluded by the normal filters.
    if (is.data.frame(res$result) && nrow(res$result) == 0 && identical(plan$label, "fallback_coord_bearing") && has_allow_centroids_plan) {
      notes <- c(notes, "coord_bearing_empty_triggered_allow_centroids_pass")
      skip_to_allow_centroids <- TRUE
    }

    if (inherits(res$result, "error")) {
      err_msg <- conditionMessage(res$result)
      notes <- c(notes, paste("occ_error:", err_msg))

      # Connection saturation usually won't improve within the same query cycle.
      if (is_bien_connection_error(err_msg)) {
        break
      }

      # Timeouts on strict filters are common for large species; go to coord_bearing
      # directly (if available) so null-coord table-order species get a chance too.
      if (is_bien_timeout_error(err_msg)) {
        if (has_coord_bearing_plan) {
          skip_to_coord_bearing <- TRUE
        } else {
          skip_to_relaxed_geo <- TRUE
        }
        next
      }
    }
  }

  # All plans exhausted with no mappable-coord result.
  # If BIEN returned records but none had valid lat/lon (e.g. is_geovalid=1 but
  # latitude/longitude columns are NULL in the view — a known BIEN data issue for
  # some species), return those records so the statistics table is still populated.
  # The map will be empty but the user gets provenance and record counts.
  # Return the actual plan's strategy label (not a synthetic label) so that all
  # downstream repro-script and count-query logic uses the correct filter params.
  if (!is.null(best_nonempty_result)) {
    notes <- c(notes, "no_coord_bearing_records_in_bien_view")
    if (is.data.frame(best_nonempty_result)) best_nonempty_result$bien_query_strategy <- best_nonempty_strategy
    return(list(data = best_nonempty_result, strategy = best_nonempty_strategy, notes = notes, limit_used = fast_limit))
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
      # No ORDER BY random() — that forces a full-table sort on 100M+ rows.
      # Fetch a larger natural-order pool and shuffle client-side with sample().
      "LIMIT", as.integer(pool_size * 5L), ";"
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
    # R-side shuffle: cheaper than ORDER BY random() on a large BIEN table.
    if (nrow(out) > pool_size) {
      out <- out[sample.int(nrow(out), pool_size), , drop = FALSE]
    }
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
    fast_candidate <- sample(starter_pool, size = 1)
    return(list(status = "ok", species = fast_candidate[[1]], mappable_n = NA_integer_, attempts = 1, precheck = "starter_pool_fast_pick"))
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
  has_real_error <- function(x) {
    if (length(x) == 0) return(FALSE)
    error_patterns <- c(
      "occ_error:", "trait_error:", "range_error:", "error", "timeout",
      "elapsed time limit", "could not connect", "remaining connection slots",
      "statement timeout", "failed"
    )
    x_lc <- tolower(as.character(x))
    any(sapply(x_lc, function(s) {
      !grepl("^occ_strategy=", s, ignore.case = TRUE) &&
        any(sapply(error_patterns, function(p) grepl(p, s, fixed = TRUE)))
    }))
  }
  query_has_error <- has_real_error(query_errors)

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
      is.data.frame(occ) && nrow(occ) > 0 ~ "matched",
      query_has_error ~ "error",
      TRUE ~ "no_records"
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
    return("Chimarrhis hookeri")
  }

  best_species <- "Chimarrhis hookeri"
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

STARTUP_SPECIES <- "Pinus teocote"
STARTUP_SPECIES_SLUG <- gsub("\\s+", "_", tolower(STARTUP_SPECIES))
STARTUP_CACHE_KEY <- paste0("startup_preloaded_", STARTUP_SPECIES_SLUG)

# Build the preloaded startup result once at app launch (global scope) so every
# session inherits it immediately without re-reading CSVs or the range shapefile.
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

# Preload the accepted-species autocomplete list once at app launch (global scope)
# so every new session gets instant autocomplete without a 60-sec per-session block.
startup_species_suggestions <- load_accepted_species_suggestions(timeout_sec = 60)
if (length(startup_species_suggestions) == 0) {
  startup_species_suggestions <- STARTUP_SPECIES
}

# ---------------------------------------------------------------------------
# Shared cross-session cache (global scope)
# A30-min TTL cache shared across all sessions so popular species are never
# re-queried from BIEN while a warm result exists.  R assignment is
# single-threaded so this is race-safe on shinyapps.io's single-process model.
# ---------------------------------------------------------------------------
SHARED_CACHE_TTL_SEC  <- 1800L   # 30 minutes
SHARED_CACHE_MAX_KEYS <- 50L

shared_bien_cache <- new.env(parent = emptyenv())

get_shared_cache <- function(cache_key) {
  if (is.null(cache_key) ||
      !exists(cache_key, envir = shared_bien_cache, inherits = FALSE)) {
    return(NULL)
  }
  entry <- get(cache_key, envir = shared_bien_cache, inherits = FALSE)
  age_sec <- as.numeric(difftime(Sys.time(), entry$cached_at, units = "secs"))
  if (age_sec > SHARED_CACHE_TTL_SEC) {
    rm(list = cache_key, envir = shared_bien_cache)
    return(NULL)
  }
  entry$value
}

set_shared_cache <- function(cache_key, value) {
  assign(cache_key,
         list(value = value, cached_at = Sys.time()),
         envir = shared_bien_cache)
  keys <- ls(envir = shared_bien_cache, all.names = FALSE)
  if (length(keys) > SHARED_CACHE_MAX_KEYS) {
    times <- vapply(keys, function(k) {
      as.numeric(get(k, envir = shared_bien_cache, inherits = FALSE)$cached_at)
    }, numeric(1))
    n_evict <- length(keys) - SHARED_CACHE_MAX_KEYS
    rm(list = keys[order(times)[seq_len(n_evict)]], envir = shared_bien_cache)
  }
  invisible(NULL)
}

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

# [ingest helpers removed: get_dwc_aliases, get_bien_reference_fields, lookup_alias_term,
#  build_column_mapping, suggest_merge_key, standardize_table_columns, merge_standardized_tables,
#  augment_tnrs_and_coordinates, build_staging_table]

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
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 20px;
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
        flex: 1 1 auto;
        min-width: 0;
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
      .bien-species-photo-wrap {
        flex-shrink: 0;
        text-align: center;
      }
      .bien-species-photo {
        width: 160px;
        height: 160px;
        border-radius: 12px;
        object-fit: cover;
        object-position: center 30%;
        display: block;
        border: 2px solid var(--panel-border);
        box-shadow: 0 2px 8px rgba(31, 91, 143, 0.10);
        transition: opacity 200ms ease;
      }
      .bien-photo-attr {
        font-size: 0.68em;
        color: #6a8aa6;
        margin-top: 3px;
        max-width: 160px;
        overflow: hidden;
        white-space: nowrap;
        text-overflow: ellipsis;
        text-align: center;
      }
      .bien-photo-attr a {
        color: #4a80aa;
        text-decoration: none;
      }
      .bien-photo-disclaimer {
        font-size: 0.62em;
        color: #8aaabb;
        margin-top: 2px;
        max-width: 160px;
        text-align: center;
        line-height: 1.2;
      }
      .bien-photo-fallback {
        width: 160px;
        height: 160px;
        border-radius: 12px;
        background: var(--bien-mint);
        border: 2px dashed var(--panel-border);
        display: flex;
        align-items: center;
        justify-content: center;
        color: #9ab5cb;
        font-size: 0.70em;
        text-align: center;
      }
      @media (max-width: 900px) {
        .bien-species-photo, .bien-photo-fallback { width: 120px; height: 120px; }
        .bien-photo-attr { max-width: 120px; }
        .bien-photo-disclaimer { max-width: 120px; }
      }
      @media (max-width: 640px) {
        .bien-species-photo-wrap { display: none; }
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
      .nav-tabs > li:nth-child(1) > a { border-left: 6px solid #6f8f3f; }  /* About & Help (visual pos 9)       */
      .nav-tabs > li:nth-child(2) > a { border-left: 6px solid #2f79b7; }  /* Occurrence   (visual pos 1)       */
      .nav-tabs > li:nth-child(3) > a { border-left: 6px solid #7b8ec8; }  /* Temporal     (visual pos 6)       */
      .nav-tabs > li:nth-child(4) > a { border-left: 6px solid #d4a537; }  /* Observations (visual pos 2)       */
      .nav-tabs > li:nth-child(5) > a { border-left: 6px solid #69b34c; }  /* Traits       (visual pos 3)       */
      .nav-tabs > li:nth-child(6) > a { border-left: 6px solid #e07a5f; }  /* Community    (visual pos 5)       */
      .nav-tabs > li:nth-child(7) > a { border-left: 6px solid #49a078; }  /* Range        (visual pos 4)       */
      .nav-tabs > li:nth-child(8) > a { border-left: 6px solid #4e8c2c; }  /* Download     (visual pos 7)       */
      .nav-tabs > li:nth-child(9) > a { border-left: 6px solid #2a83a8; }  /* External Links (visual pos 8)     */
      .nav-tabs > li.active > a,
      .nav-tabs > li.active > a:focus,
      .nav-tabs > li.active > a:hover {
        color: #ffffff;
        background: linear-gradient(180deg, #3d89c8 0%, #1f5b8f 100%);
        border: 2px solid #1f5b8f;
        box-shadow: 0 2px 0 #18456f, 0 7px 14px rgba(31, 91, 143, 0.25);
        transform: translateY(-1px);
      }
      .nav-tabs > li.active:nth-child(3) > a,
      .nav-tabs > li.active:nth-child(3) > a:focus,
      .nav-tabs > li.active:nth-child(3) > a:hover,
      .nav-tabs > li.active:nth-child(5) > a,
      .nav-tabs > li.active:nth-child(5) > a:focus,
      .nav-tabs > li.active:nth-child(5) > a:hover,
      .nav-tabs > li.active:nth-child(6) > a,
      .nav-tabs > li.active:nth-child(6) > a:focus,
      .nav-tabs > li.active:nth-child(6) > a:hover,
      .nav-tabs > li.active:nth-child(8) > a,
      .nav-tabs > li.active:nth-child(8) > a:focus,
      .nav-tabs > li.active:nth-child(8) > a:hover {
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
      /* ── Tab visual reorder: Occurrence first, About last ─────────────── */
      .nav-tabs { flex-wrap: wrap; }
      .nav-tabs > li:nth-child(1)  { order: 9; }  /* About & Help  → last  */
      .nav-tabs > li:nth-child(2)  { order: 1; }  /* Occurrence    → 1st  */
      .nav-tabs > li:nth-child(3)  { order: 6; }  /* Temporal      → 6th  */
      .nav-tabs > li:nth-child(4)  { order: 2; }  /* Observations  → 2nd  */
      .nav-tabs > li:nth-child(5)  { order: 3; }  /* Traits        → 3rd  */
      .nav-tabs > li:nth-child(6)  { order: 5; }  /* Community     → 5th  */
      .nav-tabs > li:nth-child(7)  { order: 4; }  /* Range         → 4th  */
      .nav-tabs > li:nth-child(8)  { order: 7; }  /* Download      → 7th  */
      .nav-tabs > li:nth-child(9)  { order: 8; }  /* External Links → 8th */
      /* ── Data quality signal components ──────────────────────────────── */
      .taxon-match-banner {
        display: flex;
        align-items: flex-start;
        gap: 10px;
        background: #fff8f0;
        border: 1px solid #f0c070;
        border-left: 4px solid #d97b15;
        border-radius: 0 4px 4px 0;
        padding: 10px 14px;
        margin-bottom: 12px;
        font-size: 0.9em;
        line-height: 1.5;
      }
      .taxon-match-banner .banner-label {
        color: #7a5a00;
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        font-size: 0.78em;
        white-space: nowrap;
      }
      .taxon-match-banner .banner-input  { color: #555; font-style: italic; }
      .taxon-match-banner .banner-match  { color: #333; font-weight: 600; }
      .taxon-match-banner .banner-meta   { color: #999; font-size: 0.82em; }
      .qa-chips-bar {
        display: flex;
        flex-wrap: wrap;
        gap: 6px;
        padding: 6px 0 10px 0;
      }
      .qa-chip {
        display: inline-flex;
        align-items: center;
        gap: 5px;
        background: #f7f8fa;
        border: 1px solid #e0e0e0;
        border-radius: 14px;
        padding: 3px 10px;
        font-size: 0.81em;
        white-space: nowrap;
      }
      .qa-chip .qa-label { color: #888; font-weight: 500; }
      .qa-chip .qa-value { color: #333; font-weight: 600; }
      .qa-chip.qa-warn   { background: #fff8f0; border-color: #f0c070; }
      .qa-chip.qa-warn .qa-value { color: #d97b15; }
      .map-caption-row {
        font-size: 0.81em;
        color: #aaa;
        padding: 4px 0 6px 0;
        line-height: 1.4;
      }
      .map-caption-row.cap-warn { color: #d97b15; }
      .recon-callout {
        background: #f7f8fa;
        border-left: 3px solid var(--bien-blue);
        border-radius: 0 4px 4px 0;
        padding: 8px 14px;
        margin-bottom: 10px;
        font-size: 0.87em;
      }
      .recon-callout .rc-label { color: #888; font-size: 0.82em; margin-right: 4px; }
      .recon-callout .rc-value { color: #333; font-weight: 600; }
      .disclosure-strip {
        background: #fffbf0;
        border-top: 1px solid #ffe0a0;
        border-bottom: 1px solid #ffe0a0;
        padding: 7px 12px;
        margin-bottom: 10px;
        font-size: 0.83em;
        color: #7a5a00;
        line-height: 1.5;
      }
      .null-status-note {
        font-size: 0.80em;
        color: #888;
        font-style: italic;
        padding: 2px 0 8px 0;
      }
      /* ── Summary panel redesign ─────────────────────────────────────── */
      .warn-rail {
        display: flex;
        flex-wrap: wrap;
        gap: 6px;
        margin-bottom: 14px;
      }
      .warn-chip-inline {
        display: inline-flex;
        align-items: flex-start;
        gap: 5px;
        background: #fffbeb;
        border: 1px solid #f0c070;
        border-left: 3px solid #b45309;
        border-radius: 4px;
        padding: 4px 10px;
        font-size: 0.81em;
        color: #7a4505;
        white-space: normal;
        line-height: 1.4;
      }
      .metric-row {
        display: flex;
        flex-wrap: wrap;
        gap: 10px;
        margin-bottom: 14px;
      }
      .metric-card {
        background: #fff;
        border: 1px solid #e5e7eb;
        border-radius: 6px;
        padding: 10px 16px;
        min-width: 120px;
        flex: 1;
      }
      .metric-card .mc-value {
        font-size: 1.45em;
        font-weight: 700;
        color: #1a1a1a;
        line-height: 1;
      }
      .metric-card .mc-label {
        font-size: 0.78em;
        color: #374151;
        margin-top: 4px;
        font-weight: 500;
      }
      .metric-card .mc-sub {
        font-size: 0.70em;
        color: #9ca3af;
        margin-top: 2px;
      }
      .filter-chips-bar {
        display: flex;
        flex-wrap: wrap;
        gap: 6px;
        margin-bottom: 12px;
      }
      .filter-chip {
        background: #f4f4f1;
        border: 1px solid #d1d5db;
        border-radius: 12px;
        padding: 2px 10px;
        font-size: 0.78em;
        font-family: monospace;
        color: #374151;
        white-space: nowrap;
      }
      .filter-chip.fc-warn {
        background: #fff8f0;
        border-color: #f0c070;
        color: #b45309;
      }
      .source-scorecard {
        margin-bottom: 14px;
        border: 1px solid #e5e7eb;
        border-radius: 6px;
        overflow: hidden;
        font-size: 0.84em;
      }
      .source-scorecard-header {
        background: #f9fafb;
        padding: 5px 12px;
        font-size: 0.76em;
        font-weight: 600;
        color: #6b7280;
        letter-spacing: 0.04em;
        text-transform: uppercase;
        border-bottom: 1px solid #e5e7eb;
      }
      .source-row {
        display: flex;
        align-items: center;
        padding: 5px 12px;
        gap: 10px;
        border-bottom: 1px solid #f3f4f6;
      }
      .source-row:last-child { border-bottom: none; }
      .source-bar {
        width: 4px;
        height: 16px;
        border-radius: 2px;
        flex-shrink: 0;
      }
      .source-name { flex: 1; color: #374151; }
      .source-n { font-weight: 600; color: #1a1a1a; min-width: 40px; text-align: right; }
      .source-pct { color: #6b7280; min-width: 46px; text-align: right; }
      .qa-summary-line {
        font-size: 0.82em;
        color: #555;
        margin-bottom: 10px;
        line-height: 1.5;
      }
      .summary-section {
        border-top: 1px solid #f0f0f0;
        margin-top: 4px;
      }
      .summary-section > summary {
        font-size: 0.85em;
        font-weight: 600;
        color: #374151;
        cursor: pointer;
        padding: 8px 0;
        user-select: none;
        list-style: none;
        display: flex;
        align-items: center;
        gap: 6px;
      }
      .summary-section > summary::-webkit-details-marker { display: none; }
      .summary-section > summary::before {
        content: '\25b6';
        font-size: 0.65em;
        color: #9ca3af;
        transition: transform 0.15s;
        display: inline-block;
        flex-shrink: 0;
      }
      .summary-section[open] > summary::before { transform: rotate(90deg); }
      .summary-section-body {
        padding: 4px 0 14px 14px;
        font-size: 0.82em;
        color: #555;
        line-height: 1.85;
      }
      .summary-section-body strong { color: #1a1a1a; font-weight: 600; }
      .summary-tier3 > summary { color: #9ca3af; font-weight: 500; }
      .absent-indicator { color: #9ca3af; font-style: italic; }
      .repro-block {
        background: #f9fafb;
        border: 1px solid #e5e7eb;
        border-radius: 6px;
        padding: 12px 16px;
        margin-top: 18px;
      }
      .repro-block .repro-label {
        font-size: 0.75em;
        font-weight: 600;
        color: #6b7280;
        letter-spacing: 0.04em;
        text-transform: uppercase;
        margin-bottom: 6px;
      }
      .repro-block pre {
        background: #fff;
        border: 1px solid #e5e7eb;
        border-radius: 4px;
        padding: 8px 12px;
        font-size: 0.84em;
        color: #374151;
        white-space: pre-wrap;
        word-break: break-word;
        margin: 0;
        max-height: 200px;
        overflow-y: auto;
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
          "Explore occurrence records, functional traits, and range maps for any BIEN plant species. Search by name to visualize distributions, summarize trait data, and access curated range evidence."
        )
      )
    ),
    uiOutput("species_photo_panel")
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
        actionButton("open_tab_help", "Help", class = "btn btn-info btn-lg bien-action-btn bien-help-btn"),
        tags$span("\u00A0"),
        tags$button(
          id = "copy_link_btn",
          class = "btn btn-default btn-sm",
          style = "vertical-align:middle;",
          title = "Copy a shareable link for the current species and tab to the clipboard",
          onclick = paste0(
            "var url = window.location.href;",
            "if (navigator.clipboard && navigator.clipboard.writeText) {",
            "  navigator.clipboard.writeText(url).then(function() {",
            "    var b = document.getElementById('copy_link_btn');",
            "    var orig = b.innerHTML;",
            "    b.innerHTML = 'Copied!';",
            "    b.style.color = '#2E7D32';",
            "    setTimeout(function(){ b.innerHTML = orig; b.style.color = ''; }, 1800);",
            "  });",
            "} else {",
            "  window.prompt('Copy this link:', url);",
            "}"
          ),
          "\U0001F517 Copy link"
        )
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
      checkboxInput("use_default_bien_filter_profile", compact_label("Strict-only BIEN profile (no auto-relaxation)", "Runs ONLY the strict plan: cultivated records excluded, BIEN geovalid coordinates required, and native-or-unknown semantics (is_introduced = 0 OR is_introduced IS NULL). Important caveat: BIEN's NSR (Native Species Resolver) has incomplete coverage for Old World taxa, so 'IS NULL' can re-admit introduced/cultivated New World records for non-American species (e.g. Markhamia lutea returning India/Australia/Mexico horticultural records). When this box is checked the app will NOT silently fall back to relaxed native or relaxed geovalid plans; if strict returns no records you will see an empty map rather than relaxed records mislabeled as conservative. For Old-World taxa, ALSO enable the 'Strict native (exclude unevaluated)' option in the granular controls. Uncheck to expose the individual filter toggles and the auto-fallback ladder."), value = FALSE),
      conditionalPanel(
        condition = "input.use_default_bien_filter_profile == false",
        checkboxInput("use_introduced_filter", compact_label("Filter by native vs introduced", "Controls whether establishment status is enforced. If disabled, records are kept regardless of native or introduced status."), value = TRUE),
        conditionalPanel(
          condition = "input.use_introduced_filter == true",
          checkboxInput("natives_only", compact_label("Keep native / unknown-status only", "When enabled, retains records where BIEN classifies the species as native or where introduced status is unclassified (is_introduced IS NULL). Records explicitly marked introduced are excluded."), value = TRUE),
          conditionalPanel(
            condition = "input.natives_only == true",
            checkboxInput("strict_native_no_unknown", compact_label("Strict native (exclude unevaluated)", "Emits SQL 'AND is_introduced = 0' with NO NULL fallback. Use this for Old-World taxa (e.g. Markhamia lutea) where BIEN's NSR has no coverage and the default IS NULL fallback would otherwise re-admit introduced/cultivated New-World records. Trade-off: species with sparse establishment-status metadata may return zero records."), value = FALSE)
          )
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
      uiOutput("taxon_match_banner_ui"),
      tabsetPanel(
        id = "main_tabs",
        selected = "Occurrence",

        # ── About & Help tab ───────────────────────────────────────────────────
        tabPanel(
          "About & Help",
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
          uiOutput("recon_callout_ui"),
          uiOutput("qa_chips_bar_ui"),
          uiOutput("occ_strategy_banner_ui"),
          leafletOutput("occurrence_map", height = 550),
          uiOutput("map_caption_ui"),
          br(),
          uiOutput("overview_notice"),
          uiOutput("slow_query_alert"),
          br(),
          uiOutput("summary_warn_rail_ui"),
          tags$p(
            style = "color:#555;max-width:900px;font-size:0.9em;",
            "Statistics for the current map. Load full BIEN totals and source fractions on demand."
          ),
          actionButton("load_summary_counts", "Load full BIEN counts (slower)", class = "btn-default btn-sm"),
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
          tags$h4("Taxonomic Reconciliation"),
          tags$p(
            style = "color:#555;font-size:0.93em;max-width:900px;margin-bottom:8px;",
            "BIEN-returned name match for the current query. Match is provisional and based on BIEN's internal scrubber only — not cross-validated against GBIF or World Flora Online."
          ),
          DTOutput("reconciliation_table"),
          br(),
          tags$h4("Observation Source Summary"),
          DTOutput("observation_source_table"),
          br(),
          tags$h4("Observation Records"),
          tags$div(
            class = "disclosure-strip",
            tags$strong("Deduplication note: "),
            "Records are deduplicated on species + latitude + longitude + observation_type. ",
            "Two specimens from different collections at the same plot coordinates are collapsed to one record. ",
            "Observation type (Specimen, Plot, Citizen science, HumanObservation) is classified heuristically from datasource and observation_type fields; some records may be misclassified. ",
            tags$strong("\u2018Other / unknown\u2019 category "),
            "includes records where source type could not be determined \u2014 treat these with caution."
          ),
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
          tags$div(
            class = "disclosure-strip",
            tags$strong("Trait parsing note: "),
            "Only single-number numeric values are plotted. Range notation (e.g., \u201810\u201315\u2019), multi-token strings, and categorical values are set to NA and excluded from histograms \u2014 they remain in the raw trait table below. ",
            "No unit harmonization is performed. Trait values in different units for the same trait should not be pooled for quantitative analysis without converting units first. ",
            "If multiple units are detected for a single trait, that is noted in the Trait Summary table above."
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
          tags$div(
            class = "disclosure-strip",
            tags$strong("Plot records only: "),
            "This map shows records categorized as Plot\u2009/\u2009survey for the current species. ",
            "These are structured floristic surveys with known area and sampling effort \u2014 distinct from herbarium specimens or citizen-science observations shown on the main Occurrence tab. ",
            "Plot presence reflects detection within a defined monitoring network, not the full species range."
          ),
          uiOutput("community_notice"),
          uiOutput("community_map_ui"),
          br(),
          tags$h4("Plot Community Summary"),
          uiOutput("community_summary")
        ),
        tabPanel("Range", br(),
          tags$div(
            style = "background:#fff3cd;border:1px solid #ffe69c;border-left:4px solid #d97b15;color:#664d03;padding:10px 14px;border-radius:0 6px 6px 0;margin-bottom:14px;font-size:0.9em;line-height:1.5;",
            tags$strong("\u26a0\ufe0f Model caveat \u2014 read before interpreting: "),
            "BIEN range polygons are outputs of species distribution models (SDMs), not surveyed or verified native range boundaries. ",
            "They represent modeled habitat suitability under the assumptions of the underlying SDM, which may substantially over- or under-predict the realized range. ",
            "The polygon is not peer-reviewed for this species specifically. ",
            "Do not use as a legal basis for conservation status or as evidence of species presence or absence at any specific location. ",
            "Treat as a coarse biogeographic reference layer only."
          ),
          verbatimTextOutput("range_text"),
          leafletOutput("range_map", height = 500)
        ),
        tabPanel(
          "Download",
          br(),
          tags$style(HTML("#bien_query_code, #plot_query_code, #trait_query_code { max-height: 450px; overflow-y: auto; overflow-x: auto; font-size:0.85em; }")),

          # Reproducibility notice banner
          tags$div(
            style = "background:#fff3cd;border:1px solid #ffe69c;border-left:4px solid #d97b15;color:#664d03;padding:10px 14px;border-radius:0 6px 6px 0;margin-bottom:14px;font-size:0.9em;line-height:1.6;",
            tags$strong("\u26a0\ufe0f About the R scripts on this page"),
            tags$br(),
            "The R scripts below use the same species name, filters, and query parameters that were active in your app session. ",
            "Each script uses ", tags$code("set.seed(42)"), " so the row-sampling step is consistent across runs. ",
            "However, BIEN\u2019s record count for any species can change over time as new data are ingested, ",
            "so the exact rows may differ from what the app showed. ",
            tags$strong("Scripts use the public BIEN R API ("), tags$code("BIEN_occurrence_species()"), tags$strong(") rather than the app\u2019s internal SQL,"),
            " so some records visible in the app (those using the PostGIS geom coordinate fallback) may not appear when you run the script locally. ",
            "See the script comments for full details."
          ),

          # Pre-download row counts
          uiOutput("download_row_counts_ui"),
          br(),

          # ZIP bundle
          tags$div(
            style = "background:#e8f5e9;border:1px solid #a5d6a7;border-radius:6px;padding:10px 14px;margin-bottom:16px;",
            tags$h4(style = "margin-top:0;color:#1b5e20;", "\U0001F4E6 Download everything as a ZIP"),
            tags$p(style = "color:#2e7d32;margin:0 0 8px 0;font-size:0.93em;",
              "One bundle: occurrence CSV, plot CSV, trait CSV, all three R scripts, and a README.txt explaining each file."
            ),
            downloadButton("download_all_zip", "Download all datasets + code (.zip)", class = "btn btn-success btn-sm")
          ),

          tags$h4("Occurrence Downloads"),
          tags$p(
            style = "color:#555;max-width:900px;",
            "Downloads the occurrence records currently in the app sample. The R script fetches the same query with the same filters and samples up to the same limit; ",
            tags$code("set.seed(42)"), " is included so the row selection is reproducible. ",
            "See the script header for full details on what is and is not exact."
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
            "Plot / survey records only (structured floristic inventories with known area and sampling effort). ",
            "The R script is self-contained: it fetches occurrence records directly and filters inline \u2014 no intermediate file is required."
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
            "Functional trait measurements from BIEN. No unit harmonization is applied; check the ", tags$code("unit"), " column before pooling values across sources. ",
            "The script warns you if the record limit was reached (meaning BIEN may hold more records than were downloaded)."
          ),
          downloadButton("download_trait_csv", "Download trait CSV", class = "btn btn-default btn-sm"),
          tags$span("\u00A0"),
          downloadButton("download_trait_repro_script", "Download trait R code", class = "btn btn-default btn-sm"),
          br(), br(),
          verbatimTextOutput("trait_query_code")
        ),
        tabPanel(
          "Explore this species",
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
  manual_query_nonce <- reactiveVal(0L)

  # If no pre-cached sample data exists for the startup species, auto-trigger
  # a live BIEN query after the first reactive flush so the map populates
  # without the user needing to click "Query BIEN".
  # session$onFlushed() is used (not observe()) so the trigger fires AFTER
  # the eventReactive is fully initialised and ignoreInit is no longer active.
  if (is.null(startup_preloaded_result)) {
    session$onFlushed(function() {
      manual_query_nonce(isolate(manual_query_nonce()) + 1L)
      query_trigger("run")
    }, once = TRUE)
  }

  last_lucky_species <- reactiveVal(NULL)
  species_select_choices <- reactiveVal(STARTUP_SPECIES)

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

  observeEvent(TRUE, {
    # Use globally preloaded suggestions (loaded once at app launch) — no per-session BIEN call needed.
    # Also honour ?species= and ?tab= URL parameters for shareable bookmarks.
    url_query <- parseQueryString(session$clientData$url_search)
    species_from_url <- url_query[["species"]]
    tab_from_url     <- url_query[["tab"]]

    if (!is.null(species_from_url) && nzchar(species_from_url)) {
      sp_decoded <- utils::URLdecode(species_from_url)
      sp_clean   <- normalize_species_name(sp_decoded)
      update_species_select_input(sp_clean, choices = startup_species_suggestions)
    } else {
      update_species_select_input(STARTUP_SPECIES, choices = startup_species_suggestions)
    }

    valid_tabs <- c("About & Help", "Occurrence", "Community", "Observations",
                    "Traits", "Range", "Download", "Explore this species", "Temporal Distribution")
    if (!is.null(tab_from_url) && nzchar(tab_from_url) &&
        utils::URLdecode(tab_from_url) %in% valid_tabs) {
      updateTabsetPanel(session, "main_tabs",
                        selected = utils::URLdecode(tab_from_url))
    }
  }, once = TRUE)

  # Keep the URL bar in sync with the active species + tab so users can copy/
  # share a link that restores the same view.  Uses mode = "replace" to avoid
  # polluting the browser history with every tab click.
  observeEvent(list(input$species, input$main_tabs), {
    sp  <- if (!is.null(input$species) && nzchar(input$species)) input$species else ""
    tab <- if (!is.null(input$main_tabs)) input$main_tabs else "Occurrence"
    new_qs <- paste0(
      "?species=", utils::URLencode(sp,  reserved = TRUE),
      "&tab=",     utils::URLencode(tab, reserved = TRUE)
    )
    updateQueryString(new_qs, mode = "replace")
  }, ignoreInit = FALSE)

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
      "Explore this species" = "Open external species references generated from the current species name.",
      "About & Help" = "Read app background, scope, and interpretation context.",
      "Use Query BIEN to run live retrieval."
    )

    showModal(modalDialog(
      title = paste("Help —", active_tab),
      tags$p(help_text),
      tags$div(
        style = "background:#e8f5e9;border:1px solid #b7dfb9;color:#1b5e20;padding:8px 10px;border-radius:6px;margin:10px 0 0 0;font-size:0.92em;",
        tags$strong("Default (conservative ecological view): "),
        "Showing BIEN records where species is classified as native or introduced status is unclassified (confirmed native + unknown status — records explicitly marked introduced are excluded); cultivated records hidden; only BIEN geovalid coordinates shown; all observation-source categories retained (including field observation / citizen science); and all observation categories (plot + non-plot) retained.",
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
      fallback_coord_bearing = FALSE,
      fallback_allow_centroids = FALSE,
      requested_natives_only
    )
    effective_only_geovalid <- switch(
      strategy,
      strict = requested_only_geovalid,
      fallback_relaxed_native = requested_only_geovalid,
      fallback_relaxed_geo = FALSE,
      fallback_coord_bearing = FALSE,
      fallback_allow_centroids = FALSE,
      requested_only_geovalid
    )

    occ_limit <- if (is.null(res$occ_limit) || !is.finite(res$occ_limit)) 1000 else as.integer(res$occ_limit)
    occ_fetch_limit <- if (is.null(res$occ_fetch_limit) || !is.finite(res$occ_fetch_limit)) max(occ_limit, 1000) else as.integer(res$occ_fetch_limit)
    exclude_human_obs <- isTRUE(res$exclude_human_observation_records)
    only_plot_obs <- isTRUE(res$only_plot_observations)
    filter_profile_txt <- if (isTRUE(res$use_default_filter_profile)) "conservative default" else "custom"

    # Plain-English strategy description for the script header
    strategy_plain <- switch(
      strategy,
      strict                          = "All requested filters applied successfully.",
      fallback_relaxed_native         = "WARNING: Native-only filter was automatically relaxed (strict setting returned no results within timeout). Non-native records may be included.",
      fallback_relaxed_geo            = "WARNING: Geovalid filter was automatically relaxed. Records without BIEN coordinate validation may be included.",
      fallback_coord_bearing          = "WARNING: Fallback to coordinate-bearing records only; native status filtering may have been relaxed.",
      fallback_allow_centroids        = "WARNING: County centroid records included as last-resort fallback. Coordinates are county-level centroids, not actual observation locations.",
      startup_preloaded_local_dataset = "Data loaded from app startup cache. Re-run Query BIEN in the app for a live result.",
      paste("Strategy:", strategy)
    )

    bien_ver <- tryCatch(as.character(packageVersion("BIEN")), error = function(e) "unknown")
    gen_date <- format(Sys.Date(), "%Y-%m-%d")

    paste(
      "# =============================================================================",
      "# BIEN Species Occurrence Dataset - Reproducible R Script",
      "# Generated by the BIEN Species Shiny App",
      "# App:    https://benquist.shinyapps.io/bien-species-shinyapp/",
      "# Source: https://github.com/benquist/BIEN-SpeciesShinyApp",
      "# =============================================================================",
      "#",
      "# REQUIRED CITATION",
      "# -----------------",
      "# Enquist et al. (2026). BIEN: Botanical Information and Ecology Network.",
      "# Methods in Ecology and Evolution.",
      "# DOI: https://doi.org/10.1111/2041-210x.70274",
      "# Also run citation(\"BIEN\") for the R package citation.",
      "#",
      "# WHAT THIS SCRIPT DOES",
      "# ----------------------",
      "# Downloads plant occurrence records for one species from the BIEN database",
      "# (Botanical Information and Ecology Network) and saves the result to CSV.",
      "# BIEN covers vascular plants of the Americas. Records include herbarium",
      "# specimens, floristic plot surveys, and field observations.",
      "# Each record is a documented occurrence, NOT a model prediction.",
      "#",
      "# QUERY SUMMARY",
      "# -------------",
      paste0("# Species:              ", species_for_code),
      paste0("# Generated:            ", gen_date, " (UTC)"),
      paste0("# BIEN R package:       ", bien_ver),
      paste0("# Filter profile:       ", filter_profile_txt),
      paste0("# Native records only:  ", tolower(as.character(effective_natives_only)),
             "  (TRUE = records marked as introduced are excluded)"),
      paste0("# Geovalid only:        ", tolower(as.character(effective_only_geovalid)),
             "  (TRUE = only BIEN coordinate-validated records)"),
      paste0("# Include cultivated:   ", tolower(as.character(active_cultivated)),
             "  (FALSE = cultivated records excluded)"),
      paste0("# Occurrence strategy:  ", strategy),
      paste0("#   -> ", strategy_plain),
      "#",
      "# REPRODUCIBILITY NOTE",
      "# --------------------",
      "# The species, filters, and query parameters below are taken exactly from",
      "# your app session. set.seed(42) makes the row-sampling step consistent",
      "# across runs. However, BIEN's record count for any species can change as",
      "# new data are ingested, so results may differ if BIEN has been updated.",
      "#",
      "# This script uses the public BIEN_occurrence_species() API. The app's",
      "# internal query also extracts PostGIS geometry coordinates (geom column)",
      "# as a fallback when float latitude/longitude are NULL. That PostGIS",
      "# fallback is not available through this public API, so some species may",
      "# return fewer mappable records here than they showed in the app.",
      "#",
      "# OBSERVATION CATEGORY NOTE",
      "# -------------------------",
      "# The observation_category column is a HEURISTIC label assigned by",
      "# searching datasource, observation_type, and related fields for keywords.",
      "# Some records may be misclassified. Always inspect the original",
      "# datasource and observation_type columns. Treat 'Other / unknown'",
      "# with extra caution before using it in quantitative analyses.",
      "#",
      "# DATA COLUMN GLOSSARY",
      "# --------------------",
      "# scrubbed_species_binomial : BIEN-accepted species name after taxonomic scrubbing",
      "# latitude / longitude      : Decimal degrees (WGS 84); NULL for some BIEN records",
      "# date_collected            : Collection date (Darwin Core equivalent: eventDate)",
      "# datasource                : Primary data provider (e.g. GBIF, iDigBio, CVS)",
      "# dataset                   : Dataset within the datasource",
      "# is_introduced             : 0=native/not introduced; 1=introduced; NULL=unknown",
      "# is_cultivated             : 1=cultivated; 0=not cultivated; NULL=unknown",
      "# observation_type          : Raw BIEN observation type field",
      "# observation_category      : App heuristic category (see note above)",
      "#",
      "# DARWIN CORE COLUMN MAPPING (for GBIF tools, Darwin Core archives, etc.)",
      "# -------------------------------------------------------------------------",
      "# scrubbed_species_binomial -> scientificName",
      "# latitude                  -> decimalLatitude",
      "# longitude                 -> decimalLongitude",
      "# date_collected            -> eventDate",
      "# datasource                -> datasetName (approximate)",
      "# =============================================================================",
      "",
      "# Install required packages if not already installed.",
      "# Run these lines once, then comment them out:",
      "# install.packages(\"BIEN\")",
      "# install.packages(\"dplyr\")",
      "# install.packages(\"stringr\")",
      "",
      "library(BIEN)",
      "library(dplyr)",
      "library(stringr)",
      "",
      "# Set a random seed so the row-sampling step is reproducible across runs.",
      "# Change 42 to any integer if you want a different but still reproducible sample.",
      "set.seed(42)",
      "",
      "# --- Query parameters (auto-filled from your app session) ---",
      paste0("species_name    <- ", deparse(species_for_code)),
      paste0("occ_limit       <- ", occ_limit,
             "L  # max rows to keep after downsampling"),
      paste0("occ_fetch_limit <- ", occ_fetch_limit,
             "L  # rows to request from BIEN before downsampling"),
      "",
      "# --- Filter flags (matched to what was active in the app) ---",
      paste0("natives_only  <- ", tolower(as.character(effective_natives_only)),
             "   # exclude records where is_introduced = 1"),
      paste0("only_geovalid <- ", tolower(as.character(effective_only_geovalid)),
             "   # require BIEN coordinate validation flag"),
      paste0("cultivated    <- ", tolower(as.character(active_cultivated)),
             "   # include cultivated records"),
      "",
      "# --- Step 1: Fetch occurrence records via the BIEN public API ---",
      "# BIEN_occurrence_species() is the recommended public interface.",
      "# See ?BIEN_occurrence_species for full parameter documentation.",
      "occ <- BIEN_occurrence_species(",
      "  species              = species_name,",
      "  natives.only         = natives_only,",
      "  only.geovalid        = only_geovalid,",
      "  cultivated           = cultivated,",
      "  all.taxonomy         = TRUE,   # include full taxonomic hierarchy columns",
      "  native.status        = TRUE,   # include is_introduced column",
      "  observation.type     = TRUE,   # include observation_type column",
      "  political.boundaries = FALSE,",
      "  collection.info      = TRUE,   # include datasource, dataset, collection columns",
      "  limit                = occ_fetch_limit,",
      "  fetch.query          = FALSE",
      ")",
      "",
      "if (!is.data.frame(occ) || nrow(occ) == 0) {",
      "  message(\"No records returned. Try natives_only = FALSE or only_geovalid = FALSE.\")",
      "  stop(\"Query returned no rows.\")",
      "}",
      "",
      "cat(\"Records returned by BIEN:\", nrow(occ), \"\\n\")",
      "",
      "# --- Step 2: Classify each record into a broad observation category ---",
      "# This mirrors the classification shown in the app's Observations tab.",
      "# It searches datasource, observation_type, and related fields for keywords.",
      "# IMPORTANT: This is a heuristic. Some records may be misclassified.",
      "# Always check the original observation_type and datasource columns.",
      "# The 'Other / unknown' category contains records that matched no pattern.",
      "categorize_observation_records <- function(df) {",
      "  if (!is.data.frame(df) || nrow(df) == 0) return(df)",
      "  # Helper: find a column from a list of candidates (case-insensitive).",
      "  find_col <- function(candidates) {",
      "    hit <- candidates[candidates %in% names(df)]",
      "    if (length(hit) > 0) return(hit[[1]])",
      "    lower <- tolower(names(df))",
      "    for (cn in candidates) {",
      "      idx <- which(lower == tolower(cn))",
      "      if (length(idx) > 0) return(names(df)[idx[[1]]])",
      "    }",
      "    NULL",
      "  }",
      "  obs_col   <- find_col(c('observation_type', 'observation.type'))",
      "  src_col   <- find_col(c('datasource', 'data_source', 'collection', 'source'))",
      "  dset_col  <- find_col(c('dataset', 'dataset_name'))",
      "  basis_col <- find_col(c('basisOfRecord', 'basis_of_record'))",
      "",
      "  obs_txt   <- if (!is.null(obs_col))   as.character(df[[obs_col]])   else rep('', nrow(df))",
      "  src_txt   <- if (!is.null(src_col))   as.character(df[[src_col]])   else rep('', nrow(df))",
      "  dset_txt  <- if (!is.null(dset_col))  as.character(df[[dset_col]])  else rep('', nrow(df))",
      "  basis_txt <- if (!is.null(basis_col)) as.character(df[[basis_col]]) else rep('', nrow(df))",
      "",
      "  combined  <- tolower(paste(obs_txt, src_txt, dset_txt, basis_txt))",
      "  basis_low <- tolower(basis_txt)",
      "",
      "  df$observation_category <- dplyr::case_when(",
      "    stringr::str_detect(combined, 'specimen|herb|preserved|museum|preservedspecimen') ~",
      "      'Specimen / herbarium',",
      "    stringr::str_detect(combined, 'plot|survey|inventory|monitoring') ~",
      "      'Plot / survey',",
      "    stringr::str_detect(combined, 'inaturalist') ~",
      "      'Citizen science (iNaturalist)',",
      "    (stringr::str_detect(basis_low, 'humanobservation|human observation') |",
      "      (stringr::str_detect(combined, 'human.observation|human_observation') &",
      "         !stringr::str_detect(combined, 'specimen|museum|herb'))) ~",
      "      'Field observation (HumanObservation)',",
      "    stringr::str_detect(combined, 'gbif') ~ 'GBIF / other aggregator',",
      "    TRUE ~ 'Other / unknown'",
      "  )",
      "  df",
      "}",
      "",
      "occ <- categorize_observation_records(occ)",
      "",
      "# --- Step 3: Post-query filters (mirror app settings) ---",
      if (isTRUE(exclude_human_obs)) {
        paste(
          "# Exclude iNaturalist and field observation records (was active in app).",
          "occ <- occ %>%",
          "  dplyr::filter(!observation_category %in% c(",
          "    'Citizen science (iNaturalist)', 'Field observation (HumanObservation)'",
          "  ))",
          sep = "\n"
        )
      } else {
        "# No HumanObservation / iNaturalist exclusion was active in the app."
      },
      if (isTRUE(only_plot_obs)) {
        paste(
          "# Plot-only filter was active in the app.",
          "occ <- occ %>% dplyr::filter(observation_category == 'Plot / survey')",
          sep = "\n"
        )
      } else {
        "# Plot-only filter was not active; all observation categories are retained."
      },
      "",
      "# --- Step 4: Downsample if more records were returned than occ_limit ---",
      "# Stratified by datasource to preserve proportional source representation.",
      "# set.seed(42) at the top of the script makes this step reproducible.",
      "if (nrow(occ) > occ_limit) {",
      "  src_col_name <- intersect(",
      "    c('datasource', 'data_source', 'collection', 'source'), names(occ)",
      "  )[1]",
      "  if (!is.na(src_col_name) && src_col_name %in% names(occ)) {",
      "    occ <- occ %>%",
      "      dplyr::group_by(.data[[src_col_name]]) %>%",
      "      dplyr::slice_sample(prop = min(1, occ_limit / nrow(occ))) %>%",
      "      dplyr::ungroup() %>%",
      "      dplyr::slice_head(n = occ_limit)",
      "  } else {",
      "    occ <- dplyr::slice_sample(occ, n = occ_limit)",
      "  }",
      "  cat('Downsampled to:', nrow(occ), 'rows\\n')",
      "}",
      "",
      "cat('Final dataset rows:', nrow(occ), '\\n')",
      "cat('Observation categories:\\n')",
      "print(table(occ$observation_category, useNA = 'ifany'))",
      "",
      "# --- Step 5: Save to CSV ---",
      "out_file <- paste0(gsub('\\\\s+', '_', species_name), '_occurrence_dataset_reproduced.csv')",
      "write.csv(occ, out_file, row.names = FALSE)",
      "cat('Saved to:', out_file, '\\n')",
      "",
      "# --- Session information (keep this with your data for reproducibility) ---",
      "# This captures the R version and package versions used to generate this dataset.",
      "# Include this output when sharing data with collaborators.",
      "cat('\\n--- Session information ---\\n')",
      "sessionInfo()",
      sep = "\n"
    )
  }

  build_trait_repro_script <- function(res) {
    species_for_code <- if (!is.null(res$species) && nzchar(res$species)) res$species else "Pinus ponderosa"
    trait_limit <- if (is.null(res$trait_limit) || !is.finite(res$trait_limit)) 1000 else as.integer(res$trait_limit)
    trait_fetch_limit <- if (is.null(res$trait_fetch_limit) || !is.finite(res$trait_fetch_limit)) min(trait_limit, 1000) else as.integer(res$trait_fetch_limit)
    trait_record_limit <- min(500L, trait_limit)
    bien_ver <- tryCatch(as.character(packageVersion("BIEN")), error = function(e) "unknown")
    gen_date <- format(Sys.Date(), "%Y-%m-%d")

    paste(
      "# =============================================================================",
      "# BIEN Species Trait Dataset - Reproducible R Script",
      "# Generated by the BIEN Species Shiny App",
      "# App:    https://benquist.shinyapps.io/bien-species-shinyapp/",
      "# Source: https://github.com/benquist/BIEN-SpeciesShinyApp",
      "# =============================================================================",
      "#",
      "# REQUIRED CITATION",
      "# -----------------",
      "# Enquist et al. (2026). BIEN: Botanical Information and Ecology Network.",
      "# Methods in Ecology and Evolution.",
      "# DOI: https://doi.org/10.1111/2041-210x.70274",
      "# Also run citation(\"BIEN\") for the R package citation.",
      "#",
      "# WHAT THIS SCRIPT DOES",
      "# ----------------------",
      "# Downloads functional trait records for one plant species from the BIEN",
      "# database and saves to CSV. BIEN trait data aggregate published plant trait",
      "# measurements from the literature, plot-based studies, and other sources.",
      "#",
      "# QUERY SUMMARY",
      "# -------------",
      paste0("# Species:          ", species_for_code),
      paste0("# Generated:        ", gen_date, " (UTC)"),
      paste0("# BIEN R package:   ", bien_ver),
      paste0("# Row limit:        ", trait_fetch_limit, " (records requested from BIEN)"),
      "#",
      "# IMPORTANT TRAIT CAVEATS",
      "# -----------------------",
      "# 1. NO UNIT HARMONIZATION: Trait values from different sources may use",
      "#    different units. Always inspect the 'unit' column before comparing or",
      "#    pooling values. The 'trait_value' column is a CHARACTER string, not a",
      "#    number, because some records contain non-numeric entries.",
      "# 2. RECORD LIMIT: If BIEN holds more records than the limit requested,",
      "#    you will only see a subset. The script prints a warning below if the",
      "#    limit was reached.",
      "# 3. NO SPECIES TAXONOMY FILTERING: BIEN_trait_species() returns records",
      "#    for the species as-named. If the species has synonyms in BIEN, those",
      "#    may not be automatically captured.",
      "# 4. REPRODUCIBILITY: Trait records are generally stable unless BIEN ingests",
      "#    new data, but check the BIEN R package version in sessionInfo() below.",
      "# =============================================================================",
      "",
      "# Install required packages if not already installed.",
      "# Run these lines once, then comment them out:",
      "# install.packages(\"BIEN\")",
      "# install.packages(\"dplyr\")",
      "",
      "library(BIEN)",
      "library(dplyr)",
      "",
      "# --- Query parameters (auto-filled from your app session) ---",
      paste0("species_name       <- ", deparse(species_for_code)),
      paste0("trait_fetch_limit  <- ", trait_fetch_limit, "L  # rows requested from BIEN"),
      paste0("trait_record_limit <- ", trait_record_limit, "L  # page size for BIEN fetches"),
      "",
      "# --- Fetch trait records ---",
      "traits <- BIEN_trait_species(",
      "  species        = species_name,",
      "  all.taxonomy   = TRUE,",
      "  source.citation = TRUE,",
      "  limit          = trait_fetch_limit,",
      "  record_limit   = trait_record_limit,",
      "  fetch.query    = FALSE",
      ")",
      "",
      "if (!is.data.frame(traits) || nrow(traits) == 0) {",
      "  message(\"No trait records returned for: \", species_name)",
      "  stop(\"Query returned no rows.\")",
      "}",
      "",
      "# --- Truncation warning (Telford requirement: T-B) ---",
      paste0("if (nrow(traits) >= ", trait_fetch_limit, "L) {"),
      "  warning(",
      paste0("    \"Trait record limit (\", ", trait_fetch_limit, ", \") was reached. \","),
      "    \"BIEN may hold MORE records than were downloaded. \",",
      "    \"Increase trait_fetch_limit or use BIEN_trait_species() with a higher limit \",",
      "    \"to ensure completeness.\"",
      "  )",
      "}",
      "",
      "# --- Summary of records by trait ---",
      "cat(\"Trait records downloaded:\", nrow(traits), \"\\n\")",
      "cat(\"Records per trait:\\n\")",
      "if ('trait_name' %in% names(traits)) {",
      "  print(sort(table(traits$trait_name, useNA = 'ifany'), decreasing = TRUE))",
      "}",
      "",
      "# --- Save to CSV ---",
      "# NOTE: 'trait_value' is a character column. Cast to numeric only after",
      "# verifying units are consistent across all records you wish to pool.",
      "out_file <- paste0(gsub('\\\\s+', '_', species_name), '_trait_dataset_reproduced.csv')",
      "write.csv(traits, out_file, row.names = FALSE)",
      "cat('Saved to:', out_file, '\\n')",
      "",
      "# --- Session information (include with shared data for reproducibility) ---",
      "cat('\\n--- Session information ---\\n')",
      "sessionInfo()",
      sep = "\n"
    )
  }

  build_plot_repro_script <- function(res) {
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
      fallback_coord_bearing = FALSE,
      fallback_allow_centroids = FALSE,
      requested_natives_only
    )
    effective_only_geovalid <- switch(
      strategy,
      strict = requested_only_geovalid,
      fallback_relaxed_native = requested_only_geovalid,
      fallback_relaxed_geo = FALSE,
      fallback_coord_bearing = FALSE,
      fallback_allow_centroids = FALSE,
      requested_only_geovalid
    )

    occ_fetch_limit <- if (is.null(res$occ_fetch_limit) || !is.finite(res$occ_fetch_limit)) 1000 else as.integer(res$occ_fetch_limit)
    bien_ver <- tryCatch(as.character(packageVersion("BIEN")), error = function(e) "unknown")
    gen_date <- format(Sys.Date(), "%Y-%m-%d")

    paste(
      "# =============================================================================",
      "# BIEN Species Plot / Survey Records - Reproducible R Script",
      "# Generated by the BIEN Species Shiny App",
      "# App:    https://benquist.shinyapps.io/bien-species-shinyapp/",
      "# Source: https://github.com/benquist/BIEN-SpeciesShinyApp",
      "# =============================================================================",
      "#",
      "# REQUIRED CITATION",
      "# -----------------",
      "# Enquist et al. (2026). BIEN: Botanical Information and Ecology Network.",
      "# Methods in Ecology and Evolution.",
      "# DOI: https://doi.org/10.1111/2041-210x.70274",
      "# Also run citation(\"BIEN\") for the R package citation.",
      "#",
      "# WHAT THIS SCRIPT DOES",
      "# ----------------------",
      "# Downloads all occurrence records for one species from BIEN, assigns",
      "# observation categories, and then filters to 'Plot / survey' records only.",
      "# Plot / survey records are structured floristic inventories with known",
      "# sampling area and effort, making them suitable for community analyses.",
      "#",
      "# This script is SELF-CONTAINED: it fetches data directly without reading",
      "# from any intermediate CSV file. No occurrence script needs to run first.",
      "#",
      "# QUERY SUMMARY",
      "# -------------",
      paste0("# Species:             ", species_for_code),
      paste0("# Generated:           ", gen_date, " (UTC)"),
      paste0("# BIEN R package:      ", bien_ver),
      paste0("# Native records only: ", tolower(as.character(effective_natives_only))),
      paste0("# Geovalid only:       ", tolower(as.character(effective_only_geovalid))),
      paste0("# Include cultivated:  ", tolower(as.character(active_cultivated))),
      paste0("# Max fetch limit:     ", occ_fetch_limit),
      "#",
      "# OBSERVATION CATEGORY NOTE",
      "# -------------------------",
      "# 'Plot / survey' is a HEURISTIC label. It is assigned by searching the",
      "# datasource, observation_type, and related fields for keywords. Records",
      "# that match 'plot', 'survey', 'inventory', or 'monitoring' (case-insensitive)",
      "# are assigned this category. Some records may be misclassified.",
      "# Always inspect the original observation_type and datasource columns.",
      "# =============================================================================",
      "",
      "# Install required packages if not already installed.",
      "# Run these lines once, then comment them out:",
      "# install.packages(\"BIEN\")",
      "# install.packages(\"dplyr\")",
      "# install.packages(\"stringr\")",
      "",
      "library(BIEN)",
      "library(dplyr)",
      "library(stringr)",
      "",
      "# Set seed for reproducibility of any row-sampling step.",
      "set.seed(42)",
      "",
      "# --- Query parameters ---",
      paste0("species_name    <- ", deparse(species_for_code)),
      paste0("occ_fetch_limit <- ", occ_fetch_limit, "L"),
      "",
      "# --- Step 1: Fetch occurrence records via the BIEN public API ---",
      "occ <- BIEN_occurrence_species(",
      "  species              = species_name,",
      paste0("  natives.only         = ", tolower(as.character(effective_natives_only)), ","),
      paste0("  only.geovalid        = ", tolower(as.character(effective_only_geovalid)), ","),
      paste0("  cultivated           = ", tolower(as.character(active_cultivated)), ","),
      "  all.taxonomy         = TRUE,",
      "  native.status        = TRUE,",
      "  observation.type     = TRUE,",
      "  political.boundaries = FALSE,",
      "  collection.info      = TRUE,",
      "  limit                = occ_fetch_limit,",
      "  fetch.query          = FALSE",
      ")",
      "",
      "if (!is.data.frame(occ) || nrow(occ) == 0) {",
      "  message(\"No records returned. Try natives_only = FALSE or only_geovalid = FALSE.\")",
      "  stop(\"Query returned no rows.\")",
      "}",
      "",
      "cat(\"Records returned by BIEN:\", nrow(occ), \"\\n\")",
      "",
      "# --- Step 2: Classify records into observation categories ---",
      "# This is a heuristic classification. See header note above.",
      "categorize_observation_records <- function(df) {",
      "  if (!is.data.frame(df) || nrow(df) == 0) return(df)",
      "  find_col <- function(candidates) {",
      "    hit <- candidates[candidates %in% names(df)]",
      "    if (length(hit) > 0) return(hit[[1]])",
      "    lower <- tolower(names(df))",
      "    for (cn in candidates) {",
      "      idx <- which(lower == tolower(cn))",
      "      if (length(idx) > 0) return(names(df)[idx[[1]]])",
      "    }",
      "    NULL",
      "  }",
      "  obs_col  <- find_col(c('observation_type', 'observation.type'))",
      "  src_col  <- find_col(c('datasource', 'data_source', 'collection', 'source'))",
      "  dset_col <- find_col(c('dataset', 'dataset_name'))",
      "  basis_col <- find_col(c('basisOfRecord', 'basis_of_record'))",
      "  obs_txt   <- if (!is.null(obs_col))   as.character(df[[obs_col]])   else rep('', nrow(df))",
      "  src_txt   <- if (!is.null(src_col))   as.character(df[[src_col]])   else rep('', nrow(df))",
      "  dset_txt  <- if (!is.null(dset_col))  as.character(df[[dset_col]])  else rep('', nrow(df))",
      "  basis_txt <- if (!is.null(basis_col)) as.character(df[[basis_col]]) else rep('', nrow(df))",
      "  combined  <- tolower(paste(obs_txt, src_txt, dset_txt, basis_txt))",
      "  basis_low <- tolower(basis_txt)",
      "  df$observation_category <- dplyr::case_when(",
      "    stringr::str_detect(combined, 'specimen|herb|preserved|museum|preservedspecimen') ~ 'Specimen / herbarium',",
      "    stringr::str_detect(combined, 'plot|survey|inventory|monitoring') ~ 'Plot / survey',",
      "    stringr::str_detect(combined, 'inaturalist') ~ 'Citizen science (iNaturalist)',",
      "    (stringr::str_detect(basis_low, 'humanobservation|human observation') |",
      "      (stringr::str_detect(combined, 'human.observation|human_observation') &",
      "         !stringr::str_detect(combined, 'specimen|museum|herb'))) ~ 'Field observation (HumanObservation)',",
      "    stringr::str_detect(combined, 'gbif') ~ 'GBIF / other aggregator',",
      "    TRUE ~ 'Other / unknown'",
      "  )",
      "  df",
      "}",
      "",
      "occ <- categorize_observation_records(occ)",
      "",
      "# --- Step 3: Filter to Plot / survey records only ---",
      "plot_occ <- dplyr::filter(occ, observation_category == 'Plot / survey')",
      "cat('Plot / survey records:', nrow(plot_occ), 'of', nrow(occ), 'total records\\n')",
      "",
      "if (nrow(plot_occ) == 0) {",
      "  message(\"No plot/survey records found. \",",
      "    \"The observation_category heuristic may not match this species' data. \",",
      "    \"Inspect the observation_type column in occ for classification clues.\")",
      "}",
      "",
      "# --- Step 4: Save to CSV ---",
      "plot_file <- paste0(gsub('\\\\s+', '_', species_name), '_plot_survey_reproduced.csv')",
      "write.csv(plot_occ, plot_file, row.names = FALSE)",
      "cat('Saved to:', plot_file, '\\n')",
      "",
      "# --- Session information ---",
      "cat('\\n--- Session information ---\\n')",
      "sessionInfo()",
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
    # Update LRU timestamp on access.
    attr(cache_env, "lru_times")[[cache_key]] <- Sys.time()
    get(cache_key, envir = cache_env, inherits = FALSE)
  }

  # Evict the least-recently-used entry when the cache exceeds max_keys.
  evict_lru_cache <- function(cache_env, max_keys = 8L) {
    keys <- ls(envir = cache_env, all.names = FALSE)
    if (length(keys) <= max_keys) return(invisible(NULL))
    times <- attr(cache_env, "lru_times")
    if (is.null(times)) times <- list()
    # Assign a very old timestamp to any key with no recorded time.
    key_times <- vapply(keys, function(k) {
      t <- times[[k]]
      if (is.null(t)) as.numeric(Sys.time()) - 1e9 else as.numeric(t)
    }, numeric(1))
    n_evict <- length(keys) - max_keys
    evict_keys <- keys[order(key_times)[seq_len(n_evict)]]
    for (k in evict_keys) {
      rm(list = k, envir = cache_env)
      times[[k]] <- NULL
    }
    attr(cache_env, "lru_times") <- times
    invisible(NULL)
  }

  set_cache <- function(cache_env, cache_key, value, max_keys = 8L) {
    assign(cache_key, value, envir = cache_env)
    lru <- attr(cache_env, "lru_times")
    if (is.null(lru)) lru <- list()
    lru[[cache_key]] <- Sys.time()
    attr(cache_env, "lru_times") <- lru
    evict_lru_cache(cache_env, max_keys = max_keys)
    invisible(NULL)
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
      lucky_pick_note <- if (is.character(lucky$precheck) && grepl("range_verified", lucky$precheck)) {
        "(range-map verified)"
      } else {
        "(fast starter pick; range verification skipped)"
      }
      showNotification(
        paste0("Random species selected: ", lucky$species, " ", lucky_pick_note, ". Plot-only filtering was turned off for this run."),
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

    # 1. Per-session cache (fastest — no TTL needed within one session).
    if (exists(cache_key, envir = query_cache, inherits = FALSE)) {
      cached_res <- get(cache_key, envir = query_cache, inherits = FALSE)
      cached_res$cache_hit <- TRUE
      cached_res$query_elapsed_sec <- 0
      return(cached_res)
    }

    # 2. Cross-session shared cache (warm results from other sessions, TTL=30 min).
    shared_hit <- get_shared_cache(cache_key)
    if (!is.null(shared_hit)) {
      shared_hit$cache_hit <- TRUE
      shared_hit$query_elapsed_sec <- 0
      set_cache(query_cache, cache_key, shared_hit)   # promote to session cache
      return(shared_hit)
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
        # 5 plans: strict -> relaxed_native -> relaxed_geo -> coord_bearing -> allow_centroids.
        max_plans = 5,
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
          # Prioritize coordinate-valid rows in the app-level sample so that species
          # whose BIEN records are a mix of mappable and coordinate-null rows (e.g.
          # Pouteria reticulata, where trait/plot records dominate the raw pull) do
          # not end up with an all-null-coord sample after stratified downsampling.
          pre_lat_col <- find_first_col(occ, c("latitude", "decimal_latitude", "lat"))
          pre_lon_col <- find_first_col(occ, c("longitude", "decimal_longitude", "lon", "long"))
          has_coord <- if (!is.null(pre_lat_col) && !is.null(pre_lon_col)) {
            lat_v <- suppressWarnings(as.numeric(occ[[pre_lat_col]]))
            lon_v <- suppressWarnings(as.numeric(occ[[pre_lon_col]]))
            !is.na(lat_v) & !is.na(lon_v) & lat_v >= -90 & lat_v <= 90 & lon_v >= -180 & lon_v <= 180
          } else {
            rep(TRUE, nrow(occ))
          }
          coord_rows <- occ[has_coord, , drop = FALSE]
          no_coord_rows <- occ[!has_coord, , drop = FALSE]
          coord_n <- nrow(coord_rows)
          if (coord_n > 0 && coord_n < nrow(occ)) {
            # Draw as many coord-valid rows as possible (up to occ_limit), then pad
            # with coord-null rows to reach occ_limit if coord_valid rows are sparse.
            coord_sample_n <- min(coord_n, occ_limit)
            coord_sample <- sample_occurrence_rows(coord_rows, target_n = coord_sample_n, sample_method = display_sampling_method)
            remaining_n <- occ_limit - nrow(coord_sample)
            if (remaining_n > 0 && nrow(no_coord_rows) > 0) {
              no_coord_sample <- sample_occurrence_rows(no_coord_rows, target_n = remaining_n, sample_method = display_sampling_method)
              occ <- dplyr::bind_rows(coord_sample, no_coord_sample)
            } else {
              occ <- coord_sample
            }
          } else {
            occ <- sample_occurrence_rows(occ, target_n = occ_limit, sample_method = display_sampling_method)
          }
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

      set_cache(query_cache, cache_key, result)
      set_shared_cache(cache_key, result)   # warm the cross-session cache
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

    if (isTRUE(res$use_default_filter_profile) && (identical(res$occ_strategy, "fallback_relaxed_geo") || identical(res$occ_strategy, "fallback_coord_bearing"))) {
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

    if (mappable_n == 0 && !is_bien_connection_error(res$query_errors)) {
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
          "No mappable occurrence points were found under current filters.",
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
      res <- bien_results()
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

  output$download_all_zip <- downloadHandler(
    filename = function() {
      res <- bien_results()
      species_safe <- gsub("[^A-Za-z0-9_]+", "_", if (!is.null(res$species)) res$species else "species")
      paste0(species_safe, "_BIEN_data_bundle_", format(Sys.Date(), "%Y%m%d"), ".zip")
    },
    content = function(file) {
      res         <- bien_results()
      trait_bundle <- trait_results()
      sp_safe     <- gsub("[^A-Za-z0-9_]+", "_", if (!is.null(res$species)) res$species else "species")

      tmp_dir <- file.path(tempdir(), paste0("bien_bundle_", sp_safe, "_", floor(as.numeric(Sys.time()))))
      dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)

      write_csv_clean <- function(df_or_null, fpath, fallback_msg) {
        if (is.data.frame(df_or_null) && nrow(df_or_null) > 0) {
          write.csv(df_or_null, fpath, row.names = FALSE)
        } else {
          write.csv(data.frame(message = fallback_msg), fpath, row.names = FALSE)
        }
      }

      # Occurrence CSV
      write_csv_clean(res$occurrences,
        file.path(tmp_dir, paste0(sp_safe, "_occurrences.csv")),
        "No occurrence data available.")

      # Trait CSV
      write_csv_clean(trait_bundle$data,
        file.path(tmp_dir, paste0(sp_safe, "_traits.csv")),
        "No trait data available.")

      # Plot community CSV
      plot_bundle <- tryCatch(get_plot_community_bundle(res), error = function(e) list(raw = NULL))
      write_csv_clean(plot_bundle$raw,
        file.path(tmp_dir, paste0(sp_safe, "_plot_community.csv")),
        "No plot community data available.")

      # R repro scripts
      writeLines(build_occurrence_repro_script(res),
        file.path(tmp_dir, paste0(sp_safe, "_reproduce_occurrences.R")), useBytes = TRUE)
      writeLines(build_trait_repro_script(res),
        file.path(tmp_dir, paste0(sp_safe, "_reproduce_traits.R")), useBytes = TRUE)
      writeLines(build_plot_repro_script(res),
        file.path(tmp_dir, paste0(sp_safe, "_reproduce_plot_community.R")), useBytes = TRUE)

      # README.txt
      occ_n    <- if (is.data.frame(res$occurrences)) nrow(res$occurrences) else 0
      trait_n  <- if (is.data.frame(trait_bundle$data)) nrow(trait_bundle$data) else 0
      plot_n   <- if (is.data.frame(plot_bundle$raw))  nrow(plot_bundle$raw)  else 0
      readme_lines <- c(
        "BIEN SPECIES DATA BUNDLE",
        paste0("Species: ", if (!is.null(res$species)) res$species else "unknown"),
        paste0("Downloaded: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"), " UTC"),
        paste0("BIEN R package version: ", as.character(packageVersion("BIEN"))),
        paste0("App: https://benquist.shinyapps.io/bien-species-shinyapp/"),
        paste0("Source: https://github.com/benquist/BIEN-SpeciesShinyApp"),
        "",
        "REQUIRED CITATION",
        "Enquist et al. (2026). BIEN: Botanical Information and Ecology Network.",
        "Methods in Ecology and Evolution.",
        "DOI: https://doi.org/10.1111/2041-210x.70274",
        "Also run: citation(\"BIEN\") in R for the package citation.",
        "",
        "FILES IN THIS BUNDLE",
        paste0(sp_safe, "_occurrences.csv              : Occurrence records (", occ_n, " rows). Clean CSV, load with read.csv()."),
        paste0(sp_safe, "_traits.csv                   : Trait records (", trait_n, " rows). Check 'unit' column before pooling values."),
        paste0(sp_safe, "_plot_community.csv            : Plot/survey records (", plot_n, " rows), filtered from occurrences."),
        paste0(sp_safe, "_reproduce_occurrences.R       : R script to reproduce the occurrence dataset."),
        paste0(sp_safe, "_reproduce_traits.R            : R script to reproduce the trait dataset."),
        paste0(sp_safe, "_reproduce_plot_community.R    : R script to reproduce the plot/survey dataset (self-contained)."),
        "",
        "FILTER SETTINGS",
        paste0("Filter profile:       ", if (isTRUE(res$use_default_filter_profile)) "conservative default" else "custom"),
        paste0("Native records only:  ", if (!is.null(res$natives_only)) res$natives_only else "unknown"),
        paste0("Geo-validated only:   ", if (!is.null(res$only_geovalid)) res$only_geovalid else "unknown"),
        paste0("Occurrence strategy:  ", if (!is.null(res$occ_strategy)) res$occ_strategy else "unknown"),
        "",
        "REPRODUCIBILITY NOTES",
        "- CSV files are clean (no '#' comment lines) and parseable by read.csv().",
        "- R scripts use set.seed(42) for row-sampling reproducibility.",
        "- Scripts use the public BIEN_occurrence_species() API. Results may differ",
        "  slightly from app if BIEN data were updated since this download.",
        "- The observation_category column is a HEURISTIC label; see script comments.",
        "- Trait values are character strings with no unit harmonization applied.",
        "  Always check the 'unit' column before pooling values across sources."
      )
      writeLines(readme_lines, file.path(tmp_dir, "README.txt"))

      old_wd <- setwd(tmp_dir)
      on.exit({ setwd(old_wd); unlink(tmp_dir, recursive = TRUE) }, add = TRUE)
      zip(file, files = list.files(tmp_dir, full.names = FALSE))
    }
  )


  output$download_row_counts_ui <- renderUI({
    res <- bien_results()
    if (is.null(res) || !is.list(res)) return(NULL)

    occ_n   <- if (is.data.frame(res$occurrences)) nrow(res$occurrences) else 0
    trait_bundle <- tryCatch(trait_results(), error = function(e) list(data = NULL))
    trait_n <- if (is.data.frame(trait_bundle$data)) nrow(trait_bundle$data) else 0
    plot_bundle <- tryCatch(get_plot_community_bundle(res), error = function(e) list(raw = NULL))
    plot_n  <- if (is.data.frame(plot_bundle$raw)) nrow(plot_bundle$raw) else 0

    tags$div(
      style = "background:#f5f5f5;border:1px solid #ddd;border-radius:6px;padding:8px 14px;margin-bottom:10px;font-size:0.88em;color:#333;",
      tags$strong("Current dataset sizes: "),
      tags$span(paste0("Occurrences: ", formatC(occ_n, format="d", big.mark=","), " rows")),
      tags$span(" \u00B7 "),
      tags$span(paste0("Plot/survey: ", formatC(plot_n, format="d", big.mark=","), " rows")),
      tags$span(" \u00B7 "),
      tags$span(paste0("Traits: ", formatC(trait_n, format="d", big.mark=","), " rows"))
    )
  })

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
    gbif_url <- paste0("https://www.gbif.org/occurrence/search?q=", species_query)
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
      tags$div(
        class = "bien-link-card",
        tags$strong("GBIF (Global Biodiversity Information Facility)"),
        tags$p(
          style = "margin:6px 0 8px 0;color:#444;font-size:0.92em;",
          paste0("Occurrence search generated for: ", species_name)
        ),
        tags$a("Open GBIF", href = gbif_url, target = "_blank", class = "btn btn-default btn-sm")
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

  # Species photo: fetched in an observer (not in renderUI) so the HTTP call never blocks
  # the render cycle. The startup preloaded result is explicitly skipped so the 5-10 second
  # iNat/Wikipedia timeout cannot fire at session startup.
  #
  # Cache policy: only successful (non-NULL) fetches are cached. NULL results (network failure,
  # no photo found) are not cached so the next query for the same species will retry.
  species_photo_rv <- reactiveVal(NULL)

  observeEvent(bien_results(), {
    res <- bien_results()

    # Startup preloaded result: show fallback emoji immediately, no network call.
    if (isTRUE(res$is_startup_preloaded)) {
      species_photo_rv(NULL)
      return()
    }

    species_name <- normalize_species_name(
      if (!is.null(res$species) && nzchar(res$species)) res$species
      else str_squish(input$species)
    )
    if (!nzchar(species_name)) {
      species_photo_rv(NULL)
      return()
    }

    cache_key <- paste0("photo_", tolower(species_name))
    if (exists(cache_key, envir = query_cache, inherits = FALSE)) {
      species_photo_rv(get(cache_key, envir = query_cache, inherits = FALSE))
    } else {
      photo <- fetch_species_photo(species_name)
      if (!is.null(photo)) {
        assign(cache_key, photo, envir = query_cache)
      }
      species_photo_rv(photo)
    }
  }, ignoreNULL = TRUE)

  # renderUI reads only from species_photo_rv — no network I/O in the render path.
  output$species_photo_panel <- renderUI({
    photo <- species_photo_rv()
    res   <- bien_results()
    species_name <- normalize_species_name(
      if (!is.null(res$species) && nzchar(res$species)) res$species
      else str_squish(input$species)
    )
    if (!nzchar(species_name)) species_name <- STARTUP_SPECIES

    if (is.null(photo)) {
      tags$div(
        class = "bien-species-photo-wrap",
        tags$div(class = "bien-photo-fallback", "\U0001F33F")
      )
    } else {
      disclaimer_txt <- if (identical(photo$attribution_short, "Wikipedia")) {
        "Wikimedia Commons"
      } else if (identical(photo$attribution_short, "GBIF")) {
        "Specimen/observation image via GBIF"
      } else {
        "Community photo; not peer-verified"
      }
      tags$div(
        class = "bien-species-photo-wrap",
        tags$a(
          href = photo$source_url,
          target = "_blank",
          rel = "noopener noreferrer",
          tags$img(
            src   = photo$url,
            class = "bien-species-photo",
            alt   = paste("Photograph of", species_name),
            title = photo$attribution
          )
        ),
        tags$p(
          class = "bien-photo-attr",
          tags$a(
            href   = photo$source_url,
            target = "_blank",
            rel    = "noopener noreferrer",
            photo$attribution_short
          )
        ),
        tags$p(
          class = "bien-photo-disclaimer",
          disclaimer_txt
        )
      )
    }
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
      set_cache(trait_cache, cache_key, out)
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
      set_cache(range_cache, cache_key, out)
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
      set_cache(range_cache, cache_key, out)
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
      count_natives_only <- if (res$occ_strategy %in% c("fallback_relaxed_native", "fallback_relaxed_geo", "fallback_coord_bearing", "fallback_allow_centroids")) {
        FALSE
      } else if (use_introduced_filter) {
        isTRUE(res$natives_only)
      } else {
        FALSE
      }
      count_only_geovalid <- if (res$occ_strategy %in% c("fallback_relaxed_geo", "fallback_coord_bearing", "fallback_allow_centroids")) {
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

  # ── Shared reactive: BIEN-returned matched taxon name (avoids duplicate
  #    find_first_col + unique() work in banner and callout outputs) ────────
  matched_taxon_name_rv <- reactive({
    res <- bien_results()
    if (is.null(res) || !is.data.frame(res$occurrences) || nrow(res$occurrences) == 0)
      return(NA_character_)
    sp_col <- find_first_col(res$occurrences,
                             c("scrubbed_species_binomial", "species", "scientific_name"))
    if (is.null(sp_col)) return(NA_character_)
    vals <- na.omit(unique(as.character(res$occurrences[[sp_col]])))
    if (length(vals) > 0) vals[[1]] else NA_character_
  })

  # ── Taxon match banner: shown across all tabs when BIEN resolves a different name ────
  output$taxon_match_banner_ui <- renderUI({
    res <- bien_results()
    if (is.null(res) || is.null(res$occurrences)) return(NULL)
    if (is.null(res$species) || length(res$species) == 0) return(NULL)

    input_name   <- trimws(as.character(res$species))
    matched_name <- matched_taxon_name_rv()

    if (is.na(matched_name)) return(NULL)
    names_differ <- !identical(
      tolower(trimws(input_name)),
      tolower(trimws(matched_name))
    )
    if (!names_differ) return(NULL)

    tags$div(
      class = "taxon-match-banner",
      tags$span(class = "banner-label", "Name resolved:"),
      tags$span(class = "banner-input", htmltools::htmlEscape(input_name)),
      tags$span(style = "color:#aaa;", "\u2192"),
      tags$span(class = "banner-match", tags$em(htmltools::htmlEscape(matched_name))),
      tags$span(class = "banner-meta",
        "BIEN-returned match only \u2014 not cross-validated against GBIF or World Flora Online. Verify this is your intended taxon."
      )
    )
  })

  # ── Compact reconciliation callout above the occurrence map ──────────────
  output$recon_callout_ui <- renderUI({
    res <- bien_results()
    if (is.null(res) || is.null(res$occurrences)) return(NULL)
    if (is.null(res$species) || length(res$species) == 0) return(NULL)

    input_name   <- trimws(as.character(res$species))
    matched_name <- matched_taxon_name_rv()

    if (is.na(matched_name)) return(NULL)

    match_status <- if (identical(tolower(trimws(input_name)), tolower(trimws(matched_name)))) {
      "exact"
    } else {
      "resolved"
    }

    tags$div(
      class = "recon-callout",
      tags$span(class = "rc-label", "Queried:"),
      tags$span(class = "rc-value", htmltools::htmlEscape(input_name)),
      tags$span(style = "color:#ccc;margin:0 8px;", "|"),
      tags$span(class = "rc-label", "BIEN match:"),
      tags$span(class = "rc-value", tags$em(htmltools::htmlEscape(matched_name))),
      if (match_status == "resolved") {
        tags$span(
          style = "margin-left:10px;font-size:0.82em;color:#d97b15;",
          "\u26a0 Names differ \u2014 see banner above and Observations tab for details."
        )
      }
    )
  })

  # ── Persistent banner: effective BIEN query strategy when not strict ────
  # Surfaces the actual plan that produced the displayed records whenever the
  # auto-fallback ladder relaxed native or geovalid constraints. This is the
  # source of truth for filter provenance — the showNotification toasts elsewhere
  # are transient and easily missed.
  output$occ_strategy_banner_ui <- renderUI({
    res <- bien_results()
    if (is.null(res)) return(NULL)
    strategy <- if (!is.null(res$occ_strategy) && nzchar(res$occ_strategy)) res$occ_strategy else "strict"
    if (identical(strategy, "strict") || identical(strategy, "startup_preloaded_local_dataset")) return(NULL)

    dropped <- switch(strategy,
      "fallback_relaxed_native"   = "native-only constraint dropped (records of any establishment status included)",
      "fallback_relaxed_geo"      = "native-only AND BIEN geovalid constraints dropped",
      "fallback_coord_bearing"    = "native-only AND geovalid dropped; SQL lat/lon-not-null guard applied",
      "fallback_allow_centroids"  = "native-only AND geovalid dropped; county-centroid georeferences allowed (county-level precision)",
      "backend_connection_error"  = "BIEN backend connection error — no records loaded",
      "backend_timeout_error"     = "BIEN backend timeout — no records loaded",
      "none"                      = "no plan returned records",
      paste("non-strict strategy:", strategy)
    )

    tags$div(
      style = "background:#fff3cd;border:1px solid #ffeeba;color:#856404;
               padding:10px 14px;margin:6px 0 10px 0;border-radius:4px;
               font-size:0.95em;",
      tags$strong("Filter notice: "),
      sprintf("Effective BIEN query strategy is '%s'. ", strategy),
      dropped, ". ",
      tags$br(),
      tags$em("Records shown do not match the strict-profile semantics. To restore strict-only behavior, check the 'Strict-only BIEN profile (no auto-relaxation)' box in the sidebar.")
    )
  })

  # ── QA chips bar above the occurrence map ───────────────────────────────
  output$qa_chips_bar_ui <- renderUI({
    res <- bien_results()
    if (is.null(res) || is.null(res$occurrences)) return(NULL)

    occ          <- if (is.data.frame(res$occurrences)) res$occurrences else NULL
    if (is.null(occ) || nrow(occ) == 0) return(NULL)

    occ_n        <- nrow(occ)
    occ_returned <- if (!is.null(res$occurrences_returned) && !is.na(res$occurrences_returned)) as.integer(res$occurrences_returned) else occ_n
    occ_prep     <- res$occurrences_prepared
    mapped_n     <- if (is.list(occ_prep) && is.data.frame(occ_prep$data)) nrow(occ_prep$data) else occ_n
    cap_active   <- isTRUE(occ_prep$map_cap_applied)

    # Check summary cache for total_all so we can show fraction in the chip
    summary_cache_key_qa <- paste0(res$query_cache_key, "||summary")
    summary_bundle_qa    <- get_cached_result(summary_cache, summary_cache_key_qa)
    occ_total_all_qa     <- if (!is.null(summary_bundle_qa) && !is.na(summary_bundle_qa$total_all))
                               as.integer(summary_bundle_qa$total_all) else NA_integer_

    # Introduced status counts — preserve NA before lowercasing to avoid "na" string
    intro_col  <- find_first_col(occ, c("is_introduced", "native_status"))
    intro_raw  <- if (!is.null(intro_col)) occ[[intro_col]] else rep(NA_character_, nrow(occ))
    intro_vals <- ifelse(is.na(intro_raw), NA_character_, tolower(trimws(as.character(intro_raw))))
    n_native   <- sum(intro_vals %in% c("0", "false", "f", "n", "native", "not introduced"), na.rm = TRUE)
    n_introd   <- sum(intro_vals %in% c("1", "true", "t", "i", "introduced"), na.rm = TRUE)
    n_unknown  <- sum(is.na(intro_vals) | intro_vals == "", na.rm = TRUE)

    pct_unknown <- if (occ_n > 0) round(100 * n_unknown / occ_n) else 0

    make_chip <- function(label, value, warn = FALSE) {
      cls <- if (warn) "qa-chip qa-warn" else "qa-chip"
      tags$span(
        class = cls,
        tags$span(class = "qa-label", label),
        tags$span(class = "qa-value", value)
      )
    }

    # First chip: plain count, or fraction if total_all known, or cap indicator
    first_chip <- if (cap_active) {
      make_chip(
        "Map showing",
        paste0(format(mapped_n, big.mark = ","), " of ",
               format(occ_returned, big.mark = ","), " fetched"),
        warn = TRUE
      )
    } else if (!is.na(occ_total_all_qa) && occ_total_all_qa > 0) {
      pct_of_total <- round(100 * occ_n / occ_total_all_qa)
      make_chip(
        "Records",
        paste0(format(occ_n, big.mark = ","), " / ",
               format(occ_total_all_qa, big.mark = ","),
               " (", pct_of_total, "%)"),
        warn = pct_of_total < 50
      )
    } else {
      make_chip("Records shown", format(occ_n, big.mark = ","))
    }

    chip_list <- list(
      first_chip,
      make_chip("Native", format(n_native, big.mark = ",")),
      make_chip("Introduced", format(n_introd, big.mark = ","), warn = n_introd > 0),
      if (n_unknown > 0) make_chip("Unknown status",
                paste0(format(n_unknown, big.mark = ","),
                       if (pct_unknown > 20) paste0(" \u26a0 ", pct_unknown, "%") else ""),
                warn = pct_unknown > 20)
    )

    null_footnote <- if (n_unknown > 0) {
      tags$div(
        class = "null-status-note",
        "\u2020 \u2018Unknown status\u2019 includes records where is_introduced is NULL (not assessed by BIEN). These are not confirmed native."
      )
    } else NULL

    tagList(
      do.call(tags$div, c(list(class = "qa-chips-bar"), chip_list)),
      null_footnote
    )
  })

  # ── Map caption: sampling disclosure below the occurrence map ────────────
  output$map_caption_ui <- renderUI({
    res <- bien_results()
    if (is.null(res) || is.null(res$occurrences)) return(NULL)

    occ_prep  <- res$occurrences_prepared
    mapped_n  <- if (is.list(occ_prep) && is.data.frame(occ_prep$data)) nrow(occ_prep$data) else 0
    cap_active <- isTRUE(occ_prep$map_cap_applied)
    orig_kept  <- if (!is.null(occ_prep$original_kept)) as.integer(occ_prep$original_kept) else mapped_n
    method_txt <- if (!is.null(res$occurrence_sample_mode) && nzchar(res$occurrence_sample_mode)) res$occurrence_sample_mode else "random"

    if (cap_active) {
      n_denom <- if (!is.null(occ_prep$original_kept) && as.integer(occ_prep$original_kept) > mapped_n) {
        paste0(" of ", format(as.integer(occ_prep$original_kept), big.mark = ","), " mappable records")
      } else {
        " records (map limit active)"
      }
      tags$div(
        class = "map-caption-row cap-warn",
        HTML(paste0(
          "\u26a0 Showing ", format(mapped_n, big.mark = ","), n_denom,
          " (sampling method: ", htmltools::htmlEscape(method_txt),
          "). Spatial density is not comparable across taxa. Increase limit in sidebar or download the full dataset."
        ))
      )
    } else if (mapped_n > 0) {
      tags$div(
        class = "map-caption-row",
        paste0("Showing ", format(mapped_n, big.mark = ","),
               " occurrence records \u00b7 BIEN database (Western Hemisphere)")
      )
    } else {
      NULL
    }
  })

  # ── Warning rail: amber chips shown above the stats section ─────────────
  output$summary_warn_rail_ui <- renderUI({
    summary_cache_nonce()
    res <- bien_results()
    if (is.null(res) || is.null(res$occurrences)) return(NULL)
    occ_n <- if (is.data.frame(res$occurrences)) nrow(res$occurrences) else 0
    if (occ_n == 0) return(NULL)

    occ_prep   <- res$occurrences_prepared
    mappable_n <- if (is.list(occ_prep) && is.data.frame(occ_prep$data)) nrow(occ_prep$data) else 0

    summary_cache_key_w <- paste0(res$query_cache_key, "||summary")
    summary_bundle_w    <- get_cached_result(summary_cache, summary_cache_key_w)
    occ_total_all_w     <- if (!is.null(summary_bundle_w)) summary_bundle_w$total_all else NA_real_

    make_warn <- function(txt) tags$div(class = "warn-chip-inline", "\u26a0\u00a0", txt)

    warns <- list()

    # Fraction of BIEN universe shown on map
    if (!is.na(occ_total_all_w) && occ_total_all_w > 0) {
      pct <- round(100 * mappable_n / occ_total_all_w, 1)
      if (pct < 100) {
        warns <- c(warns, list(make_warn(paste0(
          "Only ", pct, "% of BIEN records are shown on the map (",
          format(mappable_n, big.mark = ","), " of ",
          format(as.integer(occ_total_all_w), big.mark = ","),
          " total). Increase \u2018Max mapped occurrence points\u2019 or re-query for a fresh random sample."
        ))))
      }
    }

    # Fast mode
    if (isTRUE(res$fast_large_species_mode)) {
      warns <- c(warns, list(make_warn(
        "Fast mode is on \u2014 the sample may not be geographically representative. Turn off fast mode in the sidebar for a larger draw."
      )))
    }

    # Cultivated status gap
    mapped_df <- if (is.data.frame(occ_prep$data)) occ_prep$data else res$occurrences
    if (!is.null(mapped_df) && is.data.frame(mapped_df)) {
      cult_col <- find_first_col(mapped_df, c("is_cultivated", "cultivated"))
      if (is.null(cult_col) || all(is.na(mapped_df[[cult_col]]))) {
        warns <- c(warns, list(make_warn(
          "Cultivated status is not confirmed per record for this query \u2014 cultivated filter was applied at the query level only."
        )))
      }
    }

    if (length(warns) == 0) return(NULL)
    do.call(tags$div, c(list(class = "warn-rail"), warns))
  })

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
      fallback_coord_bearing = "Auto-relaxed to coordinate-bearing records only (SQL lat/lon filter)",
      fallback_allow_centroids = "Auto-relaxed to include county centroid records (imprecise, county-level coordinates)",
      backend_timeout_error = "No successful result (BIEN timeout)",
      backend_connection_error = "No successful result (BIEN connection error)",
      paste0("Strategy: ", strategy)
    )
    conservative_relaxed <- isTRUE(res$use_default_filter_profile) && strategy %in% c("fallback_relaxed_native", "fallback_relaxed_geo", "fallback_coord_bearing", "fallback_allow_centroids")

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

    cache_age_note <- if (isTRUE(res$cache_hit)) {
      # Estimate age from shared cache if present; otherwise just say cached.
      entry <- tryCatch(
        get(res$query_cache_key, envir = shared_bien_cache, inherits = FALSE),
        error = function(e) NULL
      )
      if (!is.null(entry) && !is.null(entry$cached_at)) {
        age_min <- round(as.numeric(difftime(Sys.time(), entry$cached_at, units = "mins")), 1)
        paste0("served from cache \u2014 ", age_min, " min old")
      } else {
        "served from session cache"
      }
    } else {
      NULL
    }

    HTML(paste0(
      if (!is.null(cache_age_note)) {
        paste0(
          "<div style='display:inline-block;background:#e8f5e9;color:#2E7D32;",
          "border:1px solid #a5d6a7;border-radius:4px;padding:2px 10px;",
          "font-size:0.85em;font-weight:600;margin-bottom:8px;'>",
          "\u26A1 Cache hit \u2014 ", htmltools::htmlEscape(cache_age_note),
          "</div><br>"
        )
      } else {
        ""
      },
      "<strong>Species:</strong> ", htmltools::htmlEscape(res$species),
      "<br><strong>Family:</strong> ", htmltools::htmlEscape(family_name)
    ))

    # ── New helper variables for structured output ────────────────────────

    # Source scorecard: parse observation_category column into colored rows
    source_colors <- c(
      "Specimen / herbarium"            = "#3B6E8F",
      "GBIF / other aggregator"         = "#7B6CA0",
      "Citizen science (iNaturalist)"   = "#4D9E74",
      "Plot / survey"                   = "#C1813D",
      "Field observation (HumanObservation)" = "#888888"
    )
    source_scorecard_rows <- list()
    if (is.data.frame(res$occurrences) && "observation_category" %in% names(res$occurrences)) {
      cat_counts <- sort(table(res$occurrences$observation_category), decreasing = TRUE)
      cat_total  <- sum(cat_counts)
      for (cat_name in names(cat_counts)) {
        n_cat <- as.integer(cat_counts[[cat_name]])
        pct_cat <- if (cat_total > 0) round(100 * n_cat / cat_total, 1) else 0
        col_cat <- if (cat_name %in% names(source_colors)) source_colors[[cat_name]] else "#aaaaaa"
        source_scorecard_rows <- c(source_scorecard_rows, list(
          tags$div(class = "source-row",
            tags$div(class = "source-bar", style = paste0("background:", col_cat, ";")),
            tags$span(class = "source-name", cat_name),
            tags$span(class = "source-n",   format(n_cat, big.mark = ",")),
            tags$span(class = "source-pct", paste0(pct_cat, "%"))
          )
        ))
      }
    }

    # QA counts
    qa_removed    <- res$occurrences_prepared$qa$removed
    qa_kept       <- res$occurrences_prepared$qa$kept
    original_kept <- res$occurrences_prepared$original_kept

    # Filter chips
    make_filter_chip <- function(txt, warn = FALSE) {
      cls <- if (warn) "filter-chip fc-warn" else "filter-chip"
      tags$span(class = cls, txt)
    }
    strategy_label <- switch(
      strategy,
      strict                   = "strict",
      fallback_relaxed_native  = "auto-relaxed (native)",
      fallback_relaxed_geo     = "auto-relaxed (geo)",
      fallback_coord_bearing   = "auto-relaxed (coord-bearing)",
      fallback_allow_centroids = "county centroids",
      strategy
    )
    filter_chips <- Filter(Negate(is.null), list(
      if (isTRUE(res$use_introduced_filter) && isTRUE(res$natives_only))
        make_filter_chip("native range only"),
      if (isTRUE(res$use_introduced_filter) && !isTRUE(res$natives_only))
        make_filter_chip("all range status"),
      if (isTRUE(res$use_cultivated_filter) && !isTRUE(res$include_cultivated))
        make_filter_chip("exclude cultivated"),
      make_filter_chip(paste0("query: ", strategy_label), warn = strategy != "strict"),
      if (isTRUE(res$fast_large_species_mode)) make_filter_chip("fast mode", warn = TRUE)
    ))

    # Metric card helper
    make_metric_card <- function(value, label, sub = NULL) {
      tags$div(class = "metric-card",
        tags$div(class = "mc-value", as.character(value)),
        tags$div(class = "mc-label", label),
        if (!is.null(sub)) tags$div(class = "mc-sub", sub)
      )
    }
    total_all_fmt <- if (!is.na(occ_total_all_available))
      format(as.integer(occ_total_all_available), big.mark = ",") else "\u2298"
    qa_removed_fmt <- ifelse(is.null(qa_removed) || is.na(qa_removed), "0", as.character(qa_removed))

    # Reproducibility string
    repro_str <- paste0(
      "Species: ",         res$species,
      " | Family: ",       family_name,
      " | Strategy: ",     strategy_label,
      " | Native only: ",  ifelse(isTRUE(res$use_introduced_filter) && isTRUE(res$natives_only), "yes", "no"),
      " | Excl. cultivated: ", ifelse(isTRUE(res$use_cultivated_filter) && !isTRUE(res$include_cultivated), "yes", "no"),
      " | Records in app: ", occ_n,
      " | Mapped points: ", mappable_n,
      " | Query date: ",   format(Sys.Date(), "%Y-%m-%d"),
      " | BIEN snapshot: \u2298 not available",
      " | Source: BIEN database (Western Hemisphere)"
    )

    # ── Assemble structured output ────────────────────────────────────────
    tagList(

      # Cache hit badge
      if (!is.null(cache_age_note)) {
        tags$div(
          style = "display:inline-block;background:#e8f5e9;color:#2E7D32;border:1px solid #a5d6a7;border-radius:4px;padding:2px 10px;font-size:0.85em;font-weight:600;margin-bottom:10px;",
          "\u26A1 Cache hit \u2014 ", cache_age_note
        )
      },

      # ── TIER 1: Always visible ───────────────────────────────────────────

      # Species / family header
      tags$div(style = "margin-bottom:12px;",
        tags$span(
          style = "font-size:1.05em;font-style:italic;font-weight:600;color:#2D5986;",
          htmltools::htmlEscape(res$species)
        ),
        tags$span(
          style = "color:#6b7280;font-size:0.88em;margin-left:10px;",
          htmltools::htmlEscape(family_name)
        )
      ),

      # Metric cards
      tags$div(class = "metric-row",
        make_metric_card(format(occ_n, big.mark = ","),    "Records in app",   "matching current filters"),
        make_metric_card(total_all_fmt,                    "Total BIEN",        "unfiltered (load above)"),
        make_metric_card(format(mappable_n, big.mark = ","), "Points on map",  "post-QA"),
        make_metric_card(qa_removed_fmt,                   "Removed by QA",    "duplicates + invalid coords")
      ),

      # Active filter chips
      if (length(filter_chips) > 0)
        do.call(tags$div, c(list(class = "filter-chips-bar"), filter_chips)),

      # Source breakdown scorecard
      if (length(source_scorecard_rows) > 0) {
        tags$div(class = "source-scorecard",
          tags$div(class = "source-scorecard-header", "Data source breakdown (app sample)"),
          do.call(tagList, source_scorecard_rows)
        )
      },

      # QA one-liner
      tags$div(class = "qa-summary-line",
        tags$strong("QA:"),
        " valid records: ", occ_n,
        " \u00b7 duplicates removed: ", qa_removed_fmt,
        " \u00b7 on map: ", mappable_n,
        " \u00b7 sample mode: ", describe_sampling_mode(res$occurrence_sample_mode)
      ),

      # Map coverage fraction (visible when total is known)
      if (!is.na(mapped_pct_of_total)) {
        tags$div(class = "qa-summary-line",
          tags$strong("Map coverage:"),
          " ", round(mapped_pct_of_total, 1), "% of ALL BIEN observations shown (",
          format(mappable_n, big.mark = ","), " of ",
          format(as.integer(occ_total_all_available), big.mark = ","), ")",
          if (mapped_pct_of_total < 50) {
            tags$span(class = "warn-chip-inline",
              style = "margin-left:8px;padding:2px 7px;",
              "\u26a0 partial view"
            )
          }
        )
      } else if (!is.na(mapped_pct_of_returned)) {
        tags$div(class = "qa-summary-line",
          tags$strong("Map coverage:"),
          " ", mapped_pct_of_returned,
          "% of fetched records shown. Load BIEN totals above for full-database fraction."
        )
      },

      # Map cap / connection alerts
      if (connection_issue) {
        tags$div(class = "warn-chip-inline", style = "margin-bottom:10px;",
          "\u26a0 BIEN connection failed \u2014 no records retrieved. Try re-querying."
        )
      } else if (isTRUE(res$occurrences_prepared$map_cap_applied)) {
        tags$div(class = "qa-summary-line",
          tags$strong("\u26a0 Map cap active:"), " showing ",
          format(mappable_n, big.mark = ","), " of ",
          format(as.integer(res$occurrences_prepared$original_kept), big.mark = ","),
          " mappable records. Increase cap in sidebar."
        )
      },

      # ── TIER 2: collapsible sections (open by default) ──────────────────
      tags$hr(style = "border:none;border-top:1px solid #f0f0f0;margin:14px 0 6px 0;"),

      # Filter Profile & Query
      tags$details(class = "summary-section", open = "",
        tags$summary("Filter Profile & Query"),
        tags$div(class = "summary-section-body",
          tags$div(tags$strong("Requested vs effective BIEN profile: "),
            requested_profile_txt, " \u2192 ", effective_query_txt),
          if (conservative_relaxed) tags$div(
            tags$strong("Conservative profile preserved exactly? "),
            "No \u2014 auto-relaxed after strict attempt to recover mappable records."
          ),
          tags$div(tags$strong("Native-range records only: "),
            ifelse(isTRUE(res$use_introduced_filter) && isTRUE(res$natives_only), "yes", "no")),
          tags$div(tags$strong("Exclude cultivated records: "),
            ifelse(isTRUE(res$use_cultivated_filter) && !isTRUE(res$include_cultivated), "yes", "no")),
          tags$div(tags$strong("Use BIEN default conservative filter profile: "),
            ifelse(isTRUE(res$use_default_filter_profile), "yes", "no")),
          tags$div(tags$strong("Show only plot/survey records: "),
            ifelse(isTRUE(res$only_plot_observations), "yes", "no")),
          tags$div(tags$strong("Exclude HumanObservation + iNaturalist: "),
            ifelse(isTRUE(res$exclude_human_observation_records), "yes", "no")),
          tags$div(tags$strong("Mapped-point cap: "), "showing ",
            format(mappable_n, big.mark = ","), " of ",
            format(as.integer(if (!is.null(original_kept)) original_kept else mappable_n), big.mark = ","),
            " mappable (cap: ", format(res$map_point_cap, big.mark = ","), ")"),
          tags$div(tags$strong("Query source: "), query_source_txt),
          tags$div(tags$strong("Sampling mode: "),
            describe_sampling_mode(res$occurrence_sample_mode))
        )
      ),

      # Data Completeness & Gaps
      tags$details(class = "summary-section", open = "",
        tags$summary("Data Completeness & Gaps"),
        tags$div(class = "summary-section-body",
          tags$div(tags$strong("BIEN provenance source mix (filtered total): "),
            if (!is.null(summary_bundle) && isTRUE(summary_bundle$loaded)) {
              htmltools::htmlEscape(source_mix_line)
            } else {
              tags$span(class = "absent-indicator",
                "\u2298 Not loaded \u2014 click \u2018Load full BIEN counts\u2019 above")
            }
          ),
          if (!is.null(source_mix_mismatch_note)) {
            tags$div(tags$em(style = "color:#888;font-size:0.9em;", source_mix_mismatch_note))
          },
          tags$div(tags$strong("Total BIEN records matching strategy: "),
            htmltools::htmlEscape(occ_total_txt)),
          tags$div(tags$strong("Total ALL BIEN records (unfiltered): "),
            if (!is.na(occ_total_all_available))
              format(as.integer(occ_total_all_available), big.mark = ",")
            else
              tags$span(class = "absent-indicator",
                "\u2298 Load full BIEN counts above")
          ),
          tags$div(tags$strong("Native/introduced status in mapped points: "),
            htmltools::htmlEscape(introduced_line)),
          tags$div(tags$strong("Cultivated status: "),
            if (grepl("not returned", cultivated_line, ignore.case = TRUE)) {
              tags$span(class = "absent-indicator",
                "\u26a0 ", htmltools::htmlEscape(cultivated_line))
            } else {
              htmltools::htmlEscape(cultivated_line)
            }
          ),
          tags$div(tags$strong("HumanObservation datasource breakdown: "),
            htmltools::htmlEscape(field_obs_source_line)),
          tags$div(
            style = "color:#888;font-size:0.88em;font-style:italic;margin-left:10px;margin-bottom:4px;",
            "Note: iNaturalist records are classified separately from HumanObservation in this app\u2019s ",
            "schema (Darwin Core basisOfRecord = HumanObservation for both; this app reclassifies them)."
          ),
          tags$div(tags$strong("Temporal range of records: "),
            tags$span(class = "absent-indicator",
              "\u2298 Not available \u2014 date range not summarized by this query")),
          tags$div(tags$strong("Coordinate precision distribution: "),
            tags$span(class = "absent-indicator",
              "\u2298 Not available \u2014 coordinateUncertaintyInMeters not returned")),
          tags$div(tags$strong("BIEN database snapshot date: "),
            tags$span(class = "absent-indicator",
              "\u2298 Not available \u2014 BIEN does not expose a version/timestamp via this query"))
        )
      ),

      # ── TIER 3: Technical / Diagnostic (collapsed by default) ───────────
      tags$details(class = "summary-section summary-tier3",
        tags$summary("Technical / Diagnostic"),
        tags$div(class = "summary-section-body",
          tags$div(tags$strong("Query elapsed time: "), query_elapsed_txt),
          tags$div(tags$strong("Query timeout: "), res$timeout_sec, " sec"),
          tags$div(tags$strong("Fast mode for large species: "),
            ifelse(isTRUE(res$fast_large_species_mode),
              "on (shorter waits, smaller first-pass sample)",
              "off (larger pulls, slower for widespread species)")),
          tags$div(tags$strong("Occurrence limit requested: "), res$occ_limit),
          tags$div(tags$strong("Occurrence fetch cap used: "), res$occ_fetch_limit),
          tags$div(tags$strong("Coordinate / geovalid summary: "),
            htmltools::htmlEscape(geovalid_line)),
          tags$div(tags$strong("Observation records after QA: "), original_kept),
          tags$div(tags$strong("Observation records rendered on map: "), qa_kept),
          tags$div(tags$strong("Observation records removed by QA: "), qa_removed_fmt),
          tags$div(tags$strong("Map overview status: "),
            htmltools::htmlEscape(map_status)),
          tags$div(tags$strong("Trait records: "),
            htmltools::htmlEscape(as.character(trait_n))),
          tags$div(tags$strong("Trait limit requested: "), res$trait_limit),
          tags$div(tags$strong("Trait fetch cap used: "), res$trait_fetch_limit),
          tags$div(tags$strong("Range query status: "),
            htmltools::htmlEscape(range_status)),
          if (connection_issue) tags$div(tags$strong("BIEN server status: "),
            "The public BIEN database is temporarily at capacity or refusing connections. Please rerun the query in a minute or two."),
          if (any(grepl("elapsed time limit", res$query_errors, fixed = TRUE))) tags$div(
            tags$strong("Performance note: "),
            "BIEN timed out for at least one endpoint; try the default sample sizes or rerun the query."),
          if (occ_n > 0 && mappable_n == 0) tags$div(
            tags$strong("Map note: "),
            "This is a BIEN data-response limitation for the current species/query, not necessarily an app error.")
        )
      ),

      # ── Reproducibility block ────────────────────────────────────────────
      tags$div(class = "repro-block",
        tags$div(class = "repro-label",
          "Reproducibility statement \u2014 cite this filter profile"),
        tags$pre(repro_str)
      )

    ) # end tagList
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

    if (res$occ_strategy %in% c("fallback_relaxed_native", "fallback_relaxed_geo", "fallback_coord_bearing")) {
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

    if (identical(res$occ_strategy, "fallback_allow_centroids")) {
      return(make_notice(
        "background:#fff3cd;border:1px solid #ffe69c;color:#664d03;padding:10px 12px;border-radius:6px;margin:8px 0;",
        "County centroid note: ",
        tags$span(
          "No precise occurrence coordinates were available for this species in BIEN. ",
          "The map shows ", tags$strong("county centroid"), " coordinates — the geographic center of ",
          "the county/region of each record, not the actual observation location. ",
          "Points are imprecise (county-level resolution) and should not be used for ",
          "fine-scale spatial analyses."
        )
      ))
    }

    # Species where BIEN's view stores is_geovalid=1 but latitude/longitude columns
    # are NULL for all records. Detected via query_errors note.
    if (occ_n > 0 && mappable_n == 0 && any(grepl("no_coord_bearing_records_in_bien_view", res$query_errors, fixed = TRUE))) {
      return(make_notice(
        "background:#fff3cd;border:1px solid #ffe69c;color:#664d03;padding:10px 12px;border-radius:6px;margin:8px 0;",
        "BIEN coordinate note: ",
        tags$span(
          "BIEN returned ", occ_n, " records for this species, but the ",
          tags$code("latitude"), "/", tags$code("longitude"),
          " columns in the BIEN occurrence view are NULL for all records. ",
          "This is a known data quality issue for some species in BIEN where ",
          tags$code("is_geovalid=1"), " is set but actual coordinates are not stored in the view. ",
          "The statistics table is populated but the map will remain empty. ",
          "Try opening the Range tab for an SDM-based range polygon."
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
        "BIEN returned occurrence rows for this species, but not usable latitude/longitude coordinates in the current response. The map below is showing the BIEN range polygon instead. Note: BIEN range polygons are SDM model outputs, not verified native range boundaries — treat as coarse biogeographic reference."
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
    if (res$occ_strategy %in% c("fallback_relaxed_native", "fallback_relaxed_geo", "fallback_coord_bearing", "fallback_allow_centroids")) {
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
