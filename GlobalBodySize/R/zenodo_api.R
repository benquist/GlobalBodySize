## GlobalBodySize/R/zenodo_api.R
## Zenodo REST API client for body mass dataset discovery
## API docs: https://developers.zenodo.org/
## Base URL: https://zenodo.org/api/records
## No auth required for public records; rate limit ~60 req/min unauthenticated.
## Max page size: 100 records.

`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x

zenodo_api_base_url <- function() "https://zenodo.org/api/records"

zenodo_now_utc <- function() {
  format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

zenodo_request_sleep <- function() {
  Sys.sleep(getOption("globalsize.zenodo_delay", 2.0))  # 2s default; unauthenticated limit ~30/min
}

zenodo_require_curl <- function() {
  curl_path <- Sys.which("curl")
  if (identical(curl_path, "")) stop("curl is required but not found on PATH.", call. = FALSE)
  curl_path
}

zenodo_compose_query <- function(params) {
  params <- params[!vapply(params, is.null, logical(1))]
  if (!length(params)) return("")
  parts <- mapply(
    function(k, v) paste0(k, "=", utils::URLencode(as.character(v), reserved = TRUE)),
    names(params), params
  )
  paste0("?", paste(parts, collapse = "&"))
}

## Query Zenodo search endpoint for one term and one page.
## Filters to resource_type "dataset" by appending to the query string.
## Includes retry logic for transient failures (rate-limiting, timeouts).
zenodo_search_page <- function(query_term, page = 1, size = 100, max_retries = 3) {
  curl_path <- zenodo_require_curl()
  ## Scope to datasets only
  full_query <- paste0(query_term, " AND resource_type.type:dataset")
  qs <- zenodo_compose_query(list(q = full_query, page = page, size = size))
  url <- paste0(zenodo_api_base_url(), qs)

  for (attempt in seq_len(max_retries)) {
    tmp <- tempfile(fileext = ".json")
    cmd <- sprintf(
      '%s -s -f -H "Accept: application/json" "%s" -o "%s"',
      shQuote(curl_path), url, tmp
    )
    ret <- system(cmd, ignore.stderr = TRUE)

    if (ret == 0 && file.exists(tmp) && file.size(tmp) > 0) {
      parsed <- tryCatch(jsonlite::fromJSON(tmp, simplifyVector = FALSE), error = function(e) NULL)
      unlink(tmp)
      if (!is.null(parsed)) return(parsed)
    }
    unlink(tmp)
    if (attempt < max_retries) {
      wait <- 5 * attempt  # backoff: 5s, 10s
      message("  Zenodo retry ", attempt, "/", max_retries - 1,
              " for term: ", query_term, " page: ", page,
              " (waiting ", wait, "s)")
      Sys.sleep(wait)
    }
  }

  message("Zenodo API query failed for term: ", query_term, " page: ", page)
  NULL
}

## Flatten a list of Zenodo hit records to a data.frame with schema-compatible columns.
zenodo_flatten_hits <- function(hits, query_term) {
  if (!length(hits)) return(data.frame())
  rows <- lapply(hits, function(h) {
    meta <- h[["metadata"]] %||% list()
    doi  <- h[["doi"]] %||% h[["id"]] %||% NA_character_

    keywords <- paste(unlist(meta[["keywords"]] %||% list()), collapse = "; ")

    creators <- meta[["creators"]] %||% list()
    authors  <- paste(vapply(creators, function(cr) cr[["name"]] %||% "", character(1)),
                      collapse = "; ")

    data.frame(
      dryad_dataset_doi   = as.character(doi),
      title               = meta[["title"]] %||% NA_character_,
      abstract            = meta[["description"]] %||% NA_character_,
      keywords            = keywords,
      authors             = authors,
      publication_date    = meta[["publication_date"]] %||% NA_character_,
      dryad_version_id    = NA_character_,   # not applicable for Zenodo
      query_term          = query_term,
      query_timestamp_utc = zenodo_now_utc(),
      stringsAsFactors    = FALSE
    )
  })
  do.call(rbind, rows)
}

## Paginate through Zenodo results for a single search term.
## Returns a data.frame of all records across pages, or NULL if none found.
query_zenodo_term <- function(term, max_pages = 5, per_page = 100) {
  per_page <- min(per_page, 100L)  # Zenodo hard cap
  all_rows <- list()
  total_seen <- 0L

  for (pg in seq_len(max_pages)) {
    resp <- zenodo_search_page(term, page = pg, size = per_page)
    zenodo_request_sleep()

    if (is.null(resp)) break

    hits  <- resp[["hits"]][["hits"]] %||% list()
    total <- resp[["hits"]][["total"]] %||% 0L
    if (!length(hits)) break

    flat <- zenodo_flatten_hits(hits, term)
    if (nrow(flat)) all_rows[[pg]] <- flat
    total_seen <- total_seen + length(hits)
    if (total_seen >= total) break
  }

  if (!length(all_rows)) return(NULL)
  combined <- do.call(rbind, all_rows)
  combined[!duplicated(combined$dryad_dataset_doi), ]
}
