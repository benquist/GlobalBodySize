## GlobalBodySize/R/dryad_api.R
## Dryad REST API client for GlobalBodySize
## Direct adaptation of DryadPlantTraits/R/dryad_api.R for body mass searches
## API base: https://datadryad.org/api/v2

`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x

dryad_api_base_url <- function() "https://datadryad.org/api/v2"

dryad_now_utc <- function() {
  format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

dryad_request_sleep <- function() {
  Sys.sleep(getOption("globalsize.dryad_delay", 1.0))
}

dryad_require_curl <- function() {
  curl_path <- Sys.which("curl")
  if (identical(curl_path, "")) {
    stop("curl is required but not found on PATH.", call. = FALSE)
  }
  curl_path
}

dryad_compose_query <- function(params) {
  params <- params[!vapply(params, is.null, logical(1))]
  if (!length(params)) return("")
  parts <- mapply(function(k, v) paste0(k, "=", utils::URLencode(as.character(v), reserved = TRUE)),
                  names(params), params)
  paste0("?", paste(parts, collapse = "&"))
}

## Query Dryad search endpoint for a single search term
dryad_search_term <- function(query_term, page = 1, per_page = 100) {
  curl_path <- dryad_require_curl()
  base <- dryad_api_base_url()
  qs <- dryad_compose_query(list(q = query_term, page = page, per_page = per_page))
  url <- paste0(base, "/search", qs)

  tmp <- tempfile(fileext = ".json")
  cmd <- sprintf(
    '%s -s -f -H "Accept: application/json" "%s" -o "%s"',
    shQuote(curl_path), url, tmp
  )
  ret <- system(cmd, ignore.stderr = TRUE)
  if (ret != 0 || !file.exists(tmp) || file.size(tmp) == 0) {
    message("Dryad API query failed for term: ", query_term, " page: ", page)
    return(NULL)
  }

  parsed <- tryCatch(jsonlite::fromJSON(tmp, simplifyVector = FALSE), error = function(e) NULL)
  unlink(tmp)
  parsed
}

## Paginate through all results for a search term
dryad_paginate_term <- function(query_term, max_pages = 10, per_page = 100,
                                verbose = TRUE) {
  all_results <- list()
  for (pg in seq_len(max_pages)) {
    if (verbose) message("  Dryad | term: '", query_term, "' | page ", pg)
    resp <- dryad_search_term(query_term, page = pg, per_page = per_page)
    dryad_request_sleep()
    if (is.null(resp)) break
    datasets <- resp[["_embedded"]][["stash:datasets"]]
    if (is.null(datasets) || !length(datasets)) break
    all_results <- c(all_results, datasets)
    total <- resp[["total"]] %||% 0
    if (length(all_results) >= total) break
  }
  all_results
}

## Flatten a list of Dryad dataset records to a data.frame
dryad_flatten_datasets <- function(dataset_list, query_term) {
  if (!length(dataset_list)) return(data.frame())
  rows <- lapply(dataset_list, function(d) {
    data.frame(
      dryad_dataset_doi    = d[["identifier"]] %||% NA_character_,
      title                = d[["title"]] %||% NA_character_,
      abstract             = d[["abstract"]] %||% NA_character_,
      keywords             = paste(unlist(d[["keywords"]]), collapse = "; "),
      authors              = paste(vapply(d[["authors"]] %||% list(),
                                         function(a) paste(a[["firstName"]] %||% "",
                                                           a[["lastName"]] %||% ""),
                                         character(1)), collapse = "; "),
      publication_date     = d[["publicationDate"]] %||% NA_character_,
      dryad_version_id     = d[["versionNumber"]] %||% NA_character_,
      query_term           = query_term,
      query_timestamp_utc  = dryad_now_utc(),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}
