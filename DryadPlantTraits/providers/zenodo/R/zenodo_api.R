# zenodo_api.R
# Functions for discovering plant trait datasets on Zenodo via the public REST API.
# No API key is required for public records.
# API docs: https://developers.zenodo.org/

ZENODO_API_BASE   <- "https://zenodo.org/api/records"
ZENODO_FILES_BASE <- "https://zenodo.org/api/records/%s/files"
ZENODO_POLITE_SLEEP_SEC <- 1.0   # seconds between requests (unauthenticated: 100 req/hr)


# ---------------------------------------------------------------------------
# Auth helper
# ---------------------------------------------------------------------------

# Returns a Bearer token header string if ZENODO_API_TOKEN is set, else NULL.
# With a token Zenodo allows 5000 req/hr vs 100/hr unauthenticated.
zenodo_auth_header <- function() {
  tok <- Sys.getenv("ZENODO_API_TOKEN", unset = "")
  if (nzchar(tok)) paste0("Authorization: Bearer ", tok) else NULL
}


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

# Build a Zenodo records search URL.
# type: "dataset" | "publication" | "" (all)
zenodo_build_search_url <- function(query, type = "dataset", size = 100L, page = 1L) {
  params <- list(
    q    = query,
    size = as.integer(size),
    page = as.integer(page),
    sort = "mostrecent"
  )
  if (nzchar(type)) params[["type"]] <- type

  query_str <- paste(
    mapply(function(k, v) paste0(k, "=", utils::URLencode(as.character(v), reserved = TRUE)),
           names(params), params),
    collapse = "&"
  )
  paste0(ZENODO_API_BASE, "?", query_str)
}


# Execute a GET request with exponential backoff on 429.
# max_retries: number of additional attempts after the first failure.
# base_wait_sec: initial wait in seconds; doubles each retry.
zenodo_run_with_backoff <- function(url, max_retries = 4L, base_wait_sec = 60L) {
  auth_header <- zenodo_auth_header()
  headers     <- if (!is.null(auth_header)) auth_header else NULL

  do_request <- function() {
    tryCatch(
      dryad_run_curl(url, headers = headers),
      error = function(e) {
        warning(sprintf("zenodo HTTP error: %s", conditionMessage(e)))
        NULL
      }
    )
  }

  result <- do_request()
  if (is.null(result)) return(NULL)
  if (!identical(result$http_code, 429L)) return(result)

  wait <- base_wait_sec
  for (attempt in seq_len(max_retries)) {
    message(sprintf("Zenodo rate limit (HTTP 429): waiting %d seconds before retry %d/%d.",
                    wait, attempt, max_retries))
    Sys.sleep(wait)
    result <- do_request()
    if (is.null(result)) return(NULL)
    if (!identical(result$http_code, 429L)) return(result)
    wait <- wait * 2L
  }

  warning(sprintf("Zenodo rate limit persists after %d retries — skipping request.", max_retries))
  NULL
}


# Execute a Zenodo REST API search. Returns parsed JSON list or NULL.
zenodo_search <- function(query, type = "dataset", size = 100L, page = 1L) {
  Sys.sleep(ZENODO_POLITE_SLEEP_SEC)

  url    <- zenodo_build_search_url(query, type = type, size = size, page = page)
  result <- zenodo_run_with_backoff(url)

  if (is.null(result)) return(NULL)
  if (!result$http_code %in% c(200L)) {
    warning(sprintf("zenodo_search: HTTP %d for query '%s' page %d",
                    result$http_code, query, page))
    return(NULL)
  }
  if (!nzchar(result$body)) return(NULL)

  tryCatch(
    jsonlite::fromJSON(result$body, simplifyVector = FALSE),
    error = function(e) {
      warning(sprintf("zenodo_search: JSON parse error: %s", conditionMessage(e)))
      NULL
    }
  )
}


# Fetch file list for a single Zenodo record ID.
# Returns a data.frame with columns: file_name, file_size, download_url, mime_type.
# Returns an empty data.frame on failure.
zenodo_fetch_files <- function(record_id) {
  Sys.sleep(ZENODO_POLITE_SLEEP_SEC)

  url    <- sprintf(ZENODO_FILES_BASE, record_id)
  result <- zenodo_run_with_backoff(url)

  if (is.null(result) || !result$http_code %in% c(200L) || !nzchar(result$body)) {
    return(zenodo_empty_file_table())
  }

  parsed <- tryCatch(
    jsonlite::fromJSON(result$body, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.null(parsed)) return(zenodo_empty_file_table())

  # New-style Zenodo API returns list at top level; each entry has "key", "size", "links"
  entries <- if (is.list(parsed) && !is.null(parsed[["entries"]])) {
    parsed[["entries"]]
  } else if (is.list(parsed) && is.null(parsed[["entries"]])) {
    # Some records use the top-level list directly
    if (length(parsed) && is.list(parsed[[1]]) && !is.null(parsed[[1]][["key"]])) parsed
    else list()
  } else {
    list()
  }

  if (!length(entries)) return(zenodo_empty_file_table())

  file_name    <- vapply(entries, function(e) e$key    %||% NA_character_, character(1))
  file_size    <- vapply(entries, function(e) {
    sz <- e$size %||% NA_real_
    if (is.null(sz) || length(sz) == 0L) NA_real_ else as.numeric(sz)
  }, numeric(1))
  download_url <- vapply(entries, function(e) {
    lnk <- e$links$content %||% e$links$self %||% NA_character_
    if (is.null(lnk) || length(lnk) == 0L) NA_character_ else as.character(lnk)
  }, character(1))

  data.frame(
    file_name    = file_name,
    file_size    = file_size,
    download_url = download_url,
    mime_type    = NA_character_,
    stringsAsFactors = FALSE
  )
}


zenodo_empty_file_table <- function() {
  data.frame(
    file_name    = character(0),
    file_size    = numeric(0),
    download_url = character(0),
    mime_type    = character(0),
    stringsAsFactors = FALSE
  )
}


# ---------------------------------------------------------------------------
# Result flattening
# ---------------------------------------------------------------------------

# Extract a scalar character from a possibly-nested Zenodo field.
zenodo_scalar_char <- function(x, default = NA_character_) {
  if (is.null(x) || length(x) == 0L) return(default)
  val <- trimws(as.character(x[[1]]))
  if (!nzchar(val)) default else val
}


# Flatten a single Zenodo hit to a one-row data.frame aligned to provider_dataset_schema.
zenodo_flatten_hit <- function(hit, query_term = NA_character_) {
  meta <- hit$metadata %||% list()

  record_id <- as.character(hit$id %||% NA_character_)
  doi        <- hit$doi   %||% meta$doi %||% NA_character_

  title <- zenodo_scalar_char(meta$title)

  description <- zenodo_scalar_char(meta$description)
  # Strip HTML tags from abstract/description
  description <- gsub("<[^>]+>", " ", description %||% "")
  description <- gsub("\\s+", " ", description)
  description <- trimws(description)

  creators <- meta$creators %||% list()
  authors_str <- if (length(creators)) {
    paste(vapply(creators, function(c) {
      trimws(c$name %||% paste(c$given %||% "", c$family %||% ""))
    }, character(1)), collapse = "; ")
  } else NA_character_

  kw <- meta$keywords %||% list()
  subjects_str <- if (length(kw)) {
    paste(unlist(kw), collapse = "; ")
  } else NA_character_

  resource_type <- zenodo_scalar_char(meta$resource_type$type %||% list())

  data.frame(
    source_provider     = "zenodo",
    provider_dataset_id = paste0("zenodo:", record_id),
    zenodo_record_id    = record_id,
    doi                 = as.character(doi),
    query_term          = as.character(query_term),
    title               = as.character(title),
    authors             = as.character(authors_str),
    abstract            = as.character(description),
    source_subjects     = as.character(subjects_str),
    field_of_science    = as.character(resource_type),
    storage_size        = NA_real_,
    candidate_score     = NA_real_,
    candidate_keep      = NA,
    candidate_rationale = NA_character_,
    stringsAsFactors    = FALSE
  )
}


# Flatten all hits from a parsed Zenodo search response.
# Returns a data.frame (may have 0 rows).
zenodo_flatten_hits <- function(parsed, query_term = NA_character_) {
  hits <- parsed$hits$hits %||% list()
  if (!length(hits)) return(provider_dataset_schema(0L))

  rows <- lapply(hits, function(h) {
    tryCatch(
      zenodo_flatten_hit(h, query_term = query_term),
      error = function(e) NULL
    )
  })
  rows <- Filter(Negate(is.null), rows)
  if (!length(rows)) return(provider_dataset_schema(0L))
  do.call(rbind, rows)
}


# ---------------------------------------------------------------------------
# Candidate scoring — Zenodo-specific
#
# Zenodo strengths vs Dryad:
#   - keywords field is author-supplied and reliable
#   - title and description (abstract) are the best text signals
#   - resource_type=dataset is already filtered at search time
#
# False-positive patterns observed in initial run:
#   - Photonics / materials science papers scored high on "trait" hits in abstract
#   - Legal briefs, lizard/gecko/bird/fish papers
#   - LANDIS simulation papers (trait=life history trait, not plant morphology)
#
# Strategy:
#   1. Require BOTH plant_hits > 0 AND trait_hits > 0 (same as shared scorer)
#   2. Keywords match gives a large bonus (+6 per keyword hit), since Zenodo
#      keywords are curated by authors
#   3. Hard-veto non-plant-biology domains by scanning title + keywords
# ---------------------------------------------------------------------------

ZENODO_VETO_PATTERNS <- c(
  "photon", "metallurg", "opto-metal", "lizard", "gecko", "amphibian",
  "reptile", "avian", "ornitholog", "fish trait", "coral", "marine mammal",
  "telemetry.*forensic", "legal.*liability", "scienter", "bio-economy",
  "diatom trait", "fungal trait", "bacterial trait", "insect trait",
  "lepidoptera", "coleoptera", "diptera",
  "fisheries", "tuna fishery", "fish stock", "fishery resource", "fishery data",
  "annual catches", "monthly catches", "trophic.*fishery",
  "ocean.*atlas|socat", "squamate",
  "carabid", "ground beetle", "beetle trait",
  "pocillopora", "foraminifer", "benthic.*proxies",
  "conversation.*arousal|valence.*arousal",
  "power plant operations|PUDL|EIA form 923",
  "bulk api data",
  "renewable.*industry|industry relocation",
  "temperature.*lagoon|lagoon.*temperature|temperature.*station",
  "birth.*herbivore|herbivore.*birth|parturition|phenology of births"
)

ZENODO_KEYWORD_PLANT_TERMS <- c(
  "plant trait", "leaf trait", "wood density", "specific leaf area", "sla",
  "lma", "leaf area", "leaf nitrogen", "leaf phosphorus", "stomatal",
  "plant functional trait", "plant height", "seed mass", "root trait",
  "specific root length", "hydraulic", "photosynthesis", "wood anatomy",
  "plant ecology", "flora", "tree trait", "grass trait", "shrub trait",
  "functional diversity", "plant community", "vegetation trait", "trait database",
  "leaf economics", "plant morphology", "stem density", "bark", "ldmc",
  "turgor loss", "p50", "xylem"
)

zenodo_score_candidate <- function(title, abstract, subjects) {
  title_lc    <- tolower(title    %||% "")
  abstract_lc <- tolower(abstract %||% "")
  subjects_lc <- tolower(subjects %||% "")

  # Hard veto: if title or keywords match a non-plant domain, reject immediately
  combined_lc <- paste(title_lc, subjects_lc)
  for (pat in ZENODO_VETO_PATTERNS) {
    if (grepl(pat, combined_lc, perl = TRUE)) {
      return(list(
        candidate_score     = -10L,
        candidate_keep      = FALSE,
        candidate_rationale = paste0("veto_match=", pat)
      ))
    }
  }

  # Keyword bonus: each Zenodo keyword matching a plant-trait term adds +6
  kw_hits <- 0L
  if (nzchar(subjects_lc)) {
    kw_list <- strsplit(subjects_lc, ";\\s*|,\\s*")[[1]]
    for (kw in kw_list) {
      kw <- trimws(kw)
      if (any(vapply(ZENODO_KEYWORD_PLANT_TERMS, function(t) grepl(t, kw, fixed = TRUE), logical(1)))) {
        kw_hits <- kw_hits + 1L
      }
    }
  }

  # Base score from shared scorer (title + abstract + subjects)
  base <- dryad_score_candidate_dataset(
    title           = title_lc,
    abstract        = abstract_lc,
    source_subjects = subjects_lc
  )

  final_score <- base$candidate_score + (kw_hits * 6L)
  final_keep  <- base$plant_signal_count > 0L && base$trait_signal_count > 0L && final_score >= 6L
  final_keep  <- base$plant_signal_count > 0L && base$trait_signal_count > 0L && final_score >= 10L

  list(
    candidate_score     = final_score,
    candidate_keep      = final_keep,
    candidate_rationale = paste0(base$candidate_rationale,
                                 sprintf("; kw_hits=%d", kw_hits))
  )
}


# ---------------------------------------------------------------------------
# File support detection (mirrors sdata / dryad helpers)
# ---------------------------------------------------------------------------

zenodo_is_supported_tabular <- function(file_name) {
  if (is.na(file_name) || !nzchar(file_name)) return(FALSE)
  any(endsWith(tolower(file_name), c(".csv", ".tsv", ".txt", ".tab", ".xlsx", ".xls")))
}

zenodo_is_supported_archive <- function(file_name) {
  if (is.na(file_name) || !nzchar(file_name)) return(FALSE)
  any(endsWith(tolower(file_name), c(".zip", ".tar", ".tar.gz", ".tgz", ".gz")))
}
