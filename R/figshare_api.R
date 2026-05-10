## GlobalBodySize/R/figshare_api.R
## Figshare REST API client for body mass dataset discovery
## API docs: https://docs.figshare.com/
## Base URL: https://api.figshare.com/v2
## No auth required for public search; rate limit ~1 req/sec unauthenticated.
## Max page size: 100 articles per page.
## Resource type filtered to "dataset" via item_type=3.

`%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x

figshare_api_base_url <- function() "https://api.figshare.com/v2"

figshare_now_utc <- function() {
  format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

figshare_request_sleep <- function() {
  Sys.sleep(getOption("globalsize.figshare_delay", 1.5))
}

figshare_require_curl <- function() {
  curl_path <- Sys.which("curl")
  if (identical(curl_path, "")) stop("curl is required but not found on PATH.", call. = FALSE)
  curl_path
}

## Figshare uses POST /articles/search for keyword queries.
## Payload JSON: { "search_for": "...", "item_type": 3, "page": N, "page_size": N }
## item_type 3 = dataset (see Figshare API docs for full item type list).
figshare_search_page <- function(query_term, page = 1, page_size = 100) {
  curl_path <- figshare_require_curl()
  page_size <- min(page_size, 100L)
  url <- paste0(figshare_api_base_url(), "/articles/search")

  ## Build JSON payload inline — item_type 3 restricts to datasets
  ## Use sprintf to avoid jsonlite auto_unbox complexity with nested calls
  payload <- sprintf(
    '{"search_for":%s,"item_type":3,"page":%d,"page_size":%d}',
    jsonlite::toJSON(query_term, auto_unbox = TRUE),
    as.integer(page),
    as.integer(page_size)
  )

  tmp_out <- tempfile(fileext = ".json")
  cmd <- sprintf(
    '%s -s -f -X POST -H "Content-Type: application/json" -d %s "%s" -o "%s"',
    shQuote(curl_path),
    shQuote(payload),
    url,
    tmp_out
  )
  ret <- system(cmd, ignore.stderr = TRUE)

  if (ret != 0 || !file.exists(tmp_out) || file.size(tmp_out) == 0) {
    message("Figshare API query failed for term: ", query_term, " page: ", page)
    unlink(tmp_out)
    return(NULL)
  }

  parsed <- tryCatch(
    jsonlite::fromJSON(tmp_out, simplifyVector = FALSE),
    error = function(e) NULL
  )
  unlink(tmp_out)
  parsed
}

## Flatten a list of Figshare article records into a schema-compatible data.frame.
figshare_flatten_articles <- function(articles, query_term) {
  if (!length(articles)) return(data.frame())
  rows <- lapply(articles, function(a) {
    doi <- a[["doi"]] %||% NA_character_
    if (identical(doi, "") || is.null(doi)) doi <- NA_character_

    authors_raw <- a[["authors"]] %||% list()
    authors <- paste(vapply(authors_raw,
                            function(au) au[["full_name"]] %||% au[["name"]] %||% "",
                            character(1)),
                     collapse = "; ")

    tags <- paste(unlist(a[["tags"]] %||% list()), collapse = "; ")

    ## Figshare summary search results don't include full abstract — use title only.
    ## Full metadata can be fetched via /articles/{id} in a subsequent enrichment pass.
    data.frame(
      dryad_dataset_doi   = as.character(doi),
      title               = a[["title"]] %||% NA_character_,
      abstract            = NA_character_,          # not returned in search results
      keywords            = tags,
      authors             = authors,
      publication_date    = a[["published_date"]] %||% NA_character_,
      dryad_version_id    = NA_character_,
      query_term          = query_term,
      query_timestamp_utc = figshare_now_utc(),
      figshare_id         = as.character(a[["id"]] %||% NA_character_),
      stringsAsFactors    = FALSE
    )
  })
  do.call(rbind, rows)
}

## Paginate through Figshare results for a single search term.
## Returns a deduplicated data.frame or NULL if nothing found.
query_figshare_term <- function(term, max_pages = 5, per_page = 100) {
  per_page  <- min(per_page, 100L)
  all_rows  <- list()
  seen_ids  <- character(0)

  for (pg in seq_len(max_pages)) {
    resp <- figshare_search_page(term, page = pg, page_size = per_page)
    figshare_request_sleep()

    if (is.null(resp) || !length(resp)) break

    flat <- figshare_flatten_articles(resp, term)
    if (!nrow(flat)) break   # empty page = exhausted results

    ## Deduplicate within this crawl using figshare_id
    new_rows <- flat[!flat$figshare_id %in% seen_ids, ]
    if (nrow(new_rows)) {
      all_rows[[pg]]  <- new_rows
      seen_ids        <- c(seen_ids, new_rows$figshare_id)
    }

    ## Figshare returns fewer than page_size when exhausted
    if (length(resp) < per_page) break
  }

  if (!length(all_rows)) return(NULL)
  combined <- do.call(rbind, all_rows)
  ## Drop figshare_id helper column before returning (not in shared schema)
  combined[, setdiff(names(combined), "figshare_id")]
}
