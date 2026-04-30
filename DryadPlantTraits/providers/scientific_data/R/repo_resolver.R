# repo_resolver.R
# Functions for resolving data repository URLs found in Scientific Data papers
# into lists of downloadable files. Supports Figshare, Zenodo, GitHub, and Dryad.
# All HTTP calls use dryad_run_curl() from dryad_api.R.

SDATA_GITHUB_UA <- "DryadPlantTraits/1.0 (mailto:data-pipeline@research.org)"


# Internal helper: run curl and retry once on HTTP 429.
sdata_curl_with_retry <- function(url, headers = NULL) {
  result <- tryCatch(
    dryad_run_curl(url, headers = headers),
    error = function(e) {
      warning(sprintf("sdata_curl_with_retry: curl error for %s: %s", url, conditionMessage(e)))
      NULL
    }
  )

  if (is.null(result)) return(NULL)

  if (identical(result$http_code, 429L)) {
    warning(sprintf("sdata_curl_with_retry: HTTP 429 for %s — sleeping 10s then retrying.", url))
    Sys.sleep(10)
    result <- tryCatch(
      dryad_run_curl(url, headers = headers),
      error = function(e) {
        warning(sprintf("sdata_curl_with_retry: retry curl error: %s", conditionMessage(e)))
        NULL
      }
    )
  }

  result
}


# Internal helper: parse JSON body from a curl result, returning NULL on error.
sdata_parse_json <- function(result, context = "") {
  if (is.null(result) || !result$http_code %in% c(200L)) {
    if (!is.null(result)) {
      warning(sprintf("sdata_parse_json: HTTP %d%s", result$http_code,
                      if (nzchar(context)) paste0(" [", context, "]") else ""))
    }
    return(NULL)
  }
  if (!nzchar(result$body)) return(NULL)
  tryCatch(
    jsonlite::fromJSON(result$body, simplifyVector = FALSE),
    error = function(e) {
      warning(sprintf("sdata_parse_json: JSON parse error%s: %s",
                      if (nzchar(context)) paste0(" [", context, "]") else "",
                      conditionMessage(e)))
      NULL
    }
  )
}


# Internal helper: empty resolver output data.frame.
sdata_empty_file_table <- function() {
  data.frame(
    repo_type    = character(0),
    repo_id      = character(0),
    file_name    = character(0),
    download_url = character(0),
    file_size    = numeric(0),
    mime_type    = character(0),
    stringsAsFactors = FALSE
  )
}


# Resolve a Figshare collection DOI (10.6084/m9.figshare.c.XXXXX) into files.
# Fetches all articles in the collection, then resolves each article's files.
sdata_resolve_figshare_collection <- function(collection_doi) {
  empty <- sdata_empty_file_table()

  raw <- trimws(as.character(collection_doi))
  # Extract numeric collection ID from DOI like 10.6084/m9.figshare.c.3843841
  coll_id <- sub(".*10\\.6084/m9\\.figshare\\.c\\.([0-9]+).*", "\\1", raw, perl = TRUE)
  if (!nzchar(coll_id) || coll_id == raw) {
    warning(sprintf("sdata_resolve_figshare_collection: cannot extract collection ID from '%s'", raw))
    return(empty)
  }

  # Get collection articles list
  articles_url <- paste0("https://api.figshare.com/v2/collections/", coll_id, "/articles?limit=100")
  result <- sdata_curl_with_retry(articles_url)
  parsed <- sdata_parse_json(result, paste0("figshare_collection:", coll_id))
  if (is.null(parsed)) return(empty)

  if (!is.list(parsed) || !length(parsed)) return(empty)

  # Resolve each article in the collection
  all_rows <- lapply(parsed, function(art) {
    article_id <- as.character(art$id %||% "")
    if (!nzchar(article_id)) return(empty)
    Sys.sleep(0.3)
    sdata_resolve_figshare(article_id)
  })
  all_rows <- all_rows[!vapply(all_rows, function(d) is.null(d) || nrow(d) == 0L, logical(1))]
  if (!length(all_rows)) return(empty)
  do.call(rbind, all_rows)
}


# Resolve a Figshare DOI or article ID into a table of downloadable files.
# Input: DOI like "10.6084/m9.figshare.30940019" or numeric/string article ID.
# Also handles collection DOIs (10.6084/m9.figshare.c.XXXXX) by delegating.
# Returns data.frame: repo_type, repo_id, file_name, download_url, file_size, mime_type
sdata_resolve_figshare <- function(figshare_doi_or_id) {
  empty <- sdata_empty_file_table()

  # Delegate collection DOIs to collection resolver
  raw <- trimws(as.character(figshare_doi_or_id))
  if (grepl("10\\.6084/m9\\.figshare\\.c\\.[0-9]", raw, perl = TRUE)) {
    return(sdata_resolve_figshare_collection(raw))
  }

  # Extract numeric article ID from DOI or use as-is
  if (grepl("10\\.6084/m9\\.figshare\\.", raw, perl = TRUE)) {
    # Take the last numeric component (before any version suffix like .v2)
    last_comp <- sub(".*10\\.6084/m9\\.figshare\\.([0-9]+).*", "\\1", raw, perl = TRUE)
    article_id <- last_comp
  } else {
    # Strip non-digits
    article_id <- gsub("[^0-9]", "", raw)
  }

  if (!nzchar(article_id)) {
    warning(sprintf("sdata_resolve_figshare: cannot extract article ID from '%s'", raw))
    return(empty)
  }

  url    <- paste0("https://api.figshare.com/v2/articles/", article_id)
  result <- sdata_curl_with_retry(url)
  parsed <- sdata_parse_json(result, paste0("figshare:", article_id))
  if (is.null(parsed)) return(empty)

  files_list <- parsed[["files"]]
  if (is.null(files_list) || length(files_list) == 0L) return(empty)

  rows <- lapply(files_list, function(f) {
    data.frame(
      repo_type    = "figshare",
      repo_id      = article_id,
      file_name    = as.character(f$name    %||% NA_character_),
      download_url = as.character(f$download_url %||% NA_character_),
      file_size    = suppressWarnings(as.numeric(f$size    %||% NA_real_)),
      mime_type    = as.character(f$mime_type %||% NA_character_),
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, rows)
}


# Internal: recursively list GitHub directory contents up to max_depth levels.
# Returns character vector of raw.githubusercontent.com download URLs.
sdata_github_list_contents <- function(owner_repo, path = "", depth = 0L,
                                        max_depth = 2L, collected = character(0)) {
  if (depth > max_depth || length(collected) >= 200L) return(collected)

  api_url <- paste0("https://api.github.com/repos/", owner_repo, "/contents",
                    if (nzchar(path)) paste0("/", path) else "")
  headers <- c(
    "Accept: application/vnd.github+json",
    paste0("User-Agent: ", SDATA_GITHUB_UA)
  )

  result <- sdata_curl_with_retry(api_url, headers = headers)
  if (is.null(result) || !result$http_code %in% c(200L)) return(collected)

  parsed <- tryCatch(
    jsonlite::fromJSON(result$body, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.null(parsed)) return(collected)

  for (item in parsed) {
    if (length(collected) >= 200L) break
    item_type <- item$type %||% ""
    if (identical(item_type, "file")) {
      raw_url <- item$download_url %||% NA_character_
      if (!is.na(raw_url) && nzchar(raw_url)) {
        collected <- c(collected, raw_url)
      }
    } else if (identical(item_type, "dir") && depth < max_depth) {
      Sys.sleep(0.5)
      collected <- sdata_github_list_contents(
        owner_repo = owner_repo,
        path       = item$path %||% "",
        depth      = depth + 1L,
        max_depth  = max_depth,
        collected  = collected
      )
    }
  }

  collected
}


# Resolve a GitHub repo URL or owner/repo spec into a table of file download URLs.
# Input: "https://github.com/owner/repo" or "owner/repo"
# Returns data.frame: repo_type, repo_id, file_name, download_url, file_size, mime_type
sdata_resolve_github <- function(repo_url_or_spec) {
  empty <- sdata_empty_file_table()

  raw <- trimws(as.character(repo_url_or_spec))
  # Extract owner/repo
  owner_repo <- sub(".*github\\.com/", "", raw)
  # Keep only first two path components
  parts <- strsplit(owner_repo, "/", fixed = TRUE)[[1]]
  parts <- parts[nzchar(parts)]
  if (length(parts) < 2L) {
    warning(sprintf("sdata_resolve_github: cannot parse owner/repo from '%s'", raw))
    return(empty)
  }
  owner_repo <- paste(parts[1], parts[2], sep = "/")

  download_urls <- tryCatch(
    sdata_github_list_contents(owner_repo),
    error = function(e) {
      warning(sprintf("sdata_resolve_github: error listing '%s': %s", owner_repo, conditionMessage(e)))
      character(0)
    }
  )

  if (!length(download_urls)) return(empty)

  data.frame(
    repo_type    = "github",
    repo_id      = owner_repo,
    file_name    = basename(download_urls),
    download_url = download_urls,
    file_size    = NA_real_,
    mime_type    = NA_character_,
    stringsAsFactors = FALSE
  )
}


# Resolve a Zenodo DOI or record ID into a table of downloadable files.
# Input: DOI like "10.5281/zenodo.12345" or numeric record ID.
# Returns data.frame: repo_type, repo_id, file_name, download_url, file_size, mime_type
sdata_resolve_zenodo <- function(zenodo_doi_or_id) {
  empty <- sdata_empty_file_table()

  raw <- trimws(as.character(zenodo_doi_or_id))
  if (grepl("10\\.5281/zenodo\\.", raw, perl = TRUE)) {
    record_id <- sub(".*10\\.5281/zenodo\\.([0-9]+).*", "\\1", raw, perl = TRUE)
  } else {
    record_id <- gsub("[^0-9]", "", raw)
  }

  if (!nzchar(record_id)) {
    warning(sprintf("sdata_resolve_zenodo: cannot extract record ID from '%s'", raw))
    return(empty)
  }

  url    <- paste0("https://zenodo.org/api/records/", record_id)
  result <- sdata_curl_with_retry(url)
  parsed <- sdata_parse_json(result, paste0("zenodo:", record_id))
  if (is.null(parsed)) return(empty)

  files_list <- parsed[["files"]]
  if (is.null(files_list) || length(files_list) == 0L) return(empty)

  rows <- lapply(files_list, function(f) {
    file_name    <- as.character(f$key %||% NA_character_)
    # Zenodo API: links.self is the download URL
    links        <- f$links %||% list()
    download_url <- as.character(links$self %||% NA_character_)
    file_size    <- suppressWarnings(as.numeric(f$size %||% NA_real_))
    mime_type    <- as.character(f$type %||% NA_character_)

    data.frame(
      repo_type    = "zenodo",
      repo_id      = record_id,
      file_name    = file_name,
      download_url = download_url,
      file_size    = file_size,
      mime_type    = mime_type,
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, rows)
}


# Return a placeholder row for Dryad links — handled by the main Dryad pipeline.
# Input: DOI like "10.5061/dryad.abc123"
# Returns data.frame: repo_type, repo_id, file_name, download_url, file_size, mime_type
sdata_resolve_dryad <- function(dryad_doi) {
  data.frame(
    repo_type    = "dryad",
    repo_id      = trimws(as.character(dryad_doi)),
    file_name    = NA_character_,
    download_url = NA_character_,
    file_size    = NA_real_,
    mime_type    = NA_character_,
    stringsAsFactors = FALSE
  )
}


# Detect the type of a single link string.
# Returns one of "figshare", "zenodo", "github", "dryad", or "unknown".
sdata_detect_link_type <- function(link) {
  link <- trimws(link)
  if (grepl("10\\.6084/m9\\.figshare\\.", link, perl = TRUE)) return("figshare")
  if (grepl("10\\.5281/zenodo\\.",        link, perl = TRUE)) return("zenodo")
  if (grepl("github\\.com/",              link, perl = TRUE)) return("github")
  if (grepl("10\\.5061/dryad\\.",         link, perl = TRUE)) return("dryad")
  if (grepl("[0-9]{6,}", link) && !grepl("/", link)) {
    # Bare numeric IDs — check whether they look like Figshare or Zenodo
    # Prefer Zenodo range heuristic — cannot reliably distinguish; treat as unknown.
    return("unknown")
  }
  "unknown"
}


# Resolve a comma-separated string of repo links into a unified file table.
# Dispatches each link to the appropriate resolver.
# Failed links are skipped with a warning.
# Returns data.frame: repo_type, repo_id, file_name, download_url, file_size, mime_type
sdata_resolve_data_links <- function(data_links_string) {
  empty <- sdata_empty_file_table()

  if (is.null(data_links_string) || is.na(data_links_string) || !nzchar(trimws(data_links_string))) {
    return(empty)
  }

  links <- trimws(strsplit(data_links_string, ",", fixed = TRUE)[[1]])
  links <- links[nzchar(links)]
  if (!length(links)) return(empty)

  all_rows <- lapply(links, function(link) {
    tryCatch({
      link_type <- sdata_detect_link_type(link)
      switch(link_type,
        figshare = sdata_resolve_figshare(link),
        zenodo   = sdata_resolve_zenodo(link),
        github   = sdata_resolve_github(link),
        dryad    = sdata_resolve_dryad(link),
        {
          warning(sprintf("sdata_resolve_data_links: unknown link type for '%s' — skipping.", link))
          empty
        }
      )
    }, error = function(e) {
      warning(sprintf("sdata_resolve_data_links: error resolving '%s': %s", link, conditionMessage(e)))
      empty
    })
  })

  all_rows <- all_rows[!vapply(all_rows, function(d) is.null(d) || nrow(d) == 0L, logical(1))]
  if (!length(all_rows)) return(empty)
  do.call(rbind, all_rows)
}
