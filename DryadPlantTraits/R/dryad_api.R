`%||%` <- function(x, y) {
  if (is.null(x) || !length(x)) y else x
}

dryad_or <- function(x, y) {
  if (is.null(x) || !length(x)) y else x
}


dryad_api_base_url <- function() {
  "https://datadryad.org/api/v2"
}

dryad_now_utc <- function() {
  format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

dryad_request_sleep <- function() {
  Sys.sleep(getOption("dryad.request_delay", 1.0))
}

dryad_parse_retry_after <- function(header_file) {
  if (is.null(header_file) || !file.exists(header_file)) return(NA_real_)
  lines <- readLines(header_file, warn = FALSE)
  match <- grep("^[Rr]etry-[Aa]fter:", lines, value = TRUE)
  if (!length(match)) return(NA_real_)
  val <- suppressWarnings(as.numeric(trimws(sub("^[Rr]etry-[Aa]fter:\\s*", "", match[[1]]))))
  if (is.na(val) || val < 0) NA_real_ else val
}

dryad_require_curl <- function() {
  curl_path <- Sys.which("curl")
  if (identical(curl_path, "")) {
    stop("The curl command-line tool is required but was not found on PATH.", call. = FALSE)
  }
  curl_path
}

dryad_clean_api_path <- function(path) {
  cleaned <- sub("^https?://[^/]+/api/v2/?", "", path)
  cleaned <- sub("^/api/v2/?", "", cleaned)
  sub("^/+", "", cleaned)
}

dryad_compose_query <- function(params) {
  params <- params[!vapply(params, is.null, logical(1))]
  if (!length(params)) {
    return("")
  }

  pieces <- vapply(names(params), function(name) {
    paste0(
      utils::URLencode(name, reserved = TRUE),
      "=",
      utils::URLencode(as.character(params[[name]]), reserved = TRUE)
    )
  }, character(1))

  paste(pieces, collapse = "&")
}

dryad_build_url <- function(path, query = list()) {
  api_path <- dryad_clean_api_path(path)
  query_string <- dryad_compose_query(query)
  full_url <- paste0(dryad_api_base_url(), "/", api_path)
  if (!nzchar(query_string)) {
    return(full_url)
  }
  paste0(full_url, "?", query_string)
}

dryad_run_curl <- function(url, headers = NULL, destfile = NULL, header_file = NULL) {
  curl_bin <- dryad_require_curl()
  args <- c("-L", "--silent", "--show-error")

  if (length(headers)) {
    for (header in headers) {
      args <- c(args, "-H", header)
    }
  }

  if (!is.null(destfile)) {
    args <- c(args, "-o", destfile)
  }

  if (!is.null(header_file)) {
    args <- c(args, "-D", header_file)
  }

  args <- c(args, "--write-out", "__DRYAD_STATUS__:%{http_code}", url)
  output <- suppressWarnings(system2(curl_bin, args = args, stdout = TRUE, stderr = TRUE))
  curl_status <- attr(output, "status")
  if (is.null(curl_status)) {
    curl_status <- 0L
  }

  if (!length(output)) {
    return(list(http_code = 0L, body = "", curl_status = curl_status, output = character(0), url = url))
  }

  combined_output <- paste(output, collapse = "\n")
  status_match <- regexpr("__DRYAD_STATUS__:[0-9]{3}$", combined_output)
  status_line <- if (status_match[[1]] > 0L) regmatches(combined_output, status_match) else ""
  http_code <- suppressWarnings(as.integer(sub("^__DRYAD_STATUS__:", "", status_line)))
  if (is.na(http_code)) {
    http_code <- 0L
  }

  body <- if (is.null(destfile)) sub("__DRYAD_STATUS__:[0-9]{3}$", "", combined_output) else ""
  body <- trimws(body)

  list(
    http_code = http_code,
    body = body,
    curl_status = curl_status,
    output = output,
    url = url,
    destfile = destfile
  )
}

dryad_extract_error_message <- function(body_text) {
  if (!nzchar(body_text)) {
    return(NA_character_)
  }

  parsed <- tryCatch(jsonlite::fromJSON(body_text, simplifyVector = FALSE), error = function(e) NULL)
  if (is.list(parsed)) {
    for (key in c("message", "error", "errors")) {
      value <- parsed[[key]]
      if (!is.null(value)) {
        if (is.list(value)) {
          return(paste(unlist(value, use.names = FALSE), collapse = "; "))
        }
        return(as.character(value))
      }
    }
  }

  compact <- gsub("<[^>]+>", " ", body_text)
  compact <- gsub("\\s+", " ", compact)
  trimws(substr(compact, 1L, 250L))
}

dryad_api_get_json <- function(path, query = list(), headers = NULL) {
  url <- dryad_build_url(path, query = query)
  header_file <- tempfile("dryad_headers_", fileext = ".txt")
  on.exit(unlink(header_file), add = TRUE)
  max_retries <- 5L
  backoff <- 60.0

  for (attempt in seq_len(max_retries + 1L)) {
    response <- dryad_run_curl(url, headers = headers, header_file = header_file)

    if (response$http_code == 429L) {
      if (attempt > max_retries) break
      retry_after <- dryad_parse_retry_after(header_file)
      wait_secs <- if (!is.na(retry_after)) retry_after else backoff * 2^(attempt - 1L)
      message(sprintf("Dryad rate limit (HTTP 429): waiting %.0f seconds before retry %d/%d.", wait_secs, attempt, max_retries))
      Sys.sleep(wait_secs)
      next
    }

    if (response$curl_status != 0L || response$http_code >= 400L || response$http_code == 0L) {
      error_message <- dryad_extract_error_message(response$body)
      stop(
        sprintf(
          "Dryad request failed [%s] for %s%s",
          response$http_code,
          response$url,
          if (!is.na(error_message) && nzchar(error_message)) paste0(": ", error_message) else ""
        ),
        call. = FALSE
      )
    }

    return(jsonlite::fromJSON(response$body, simplifyVector = FALSE))
  }

  stop(sprintf("Dryad rate limit (HTTP 429) for %s: giving up after %d retries.", url, max_retries), call. = FALSE)
}

dryad_search_datasets <- function(q, subject = NULL, page = 1L, per_page = 100L) {
  result <- dryad_api_get_json(
    "search",
    query = list(q = q, subject = subject, page = page, per_page = per_page)
  )
  dryad_request_sleep()
  result
}

dryad_get_dataset_versions <- function(dataset_identifier, page = 1L, per_page = 100L) {
  result <- dryad_api_get_json(
    sprintf("datasets/%s/versions", utils::URLencode(dataset_identifier, reserved = TRUE)),
    query = list(page = page, per_page = per_page)
  )
  dryad_request_sleep()
  result
}

dryad_get_version_files <- function(version_id, page = 1L, per_page = 100L) {
  result <- dryad_api_get_json(
    sprintf("versions/%s/files", as.integer(version_id)),
    query = list(page = page, per_page = per_page)
  )
  dryad_request_sleep()
  result
}

dryad_download_file <- function(file_id, destfile, token = Sys.getenv("DRYAD_API_TOKEN", "")) {
  if (!nzchar(token)) {
    return(list(success = FALSE, status = 401L, message = "DRYAD_API_TOKEN is not set.", destfile = destfile))
  }

  response <- dryad_run_curl(
    dryad_build_url(sprintf("files/%s/download", as.integer(file_id))),
    headers = c(sprintf("Authorization: Bearer %s", token)),
    destfile = destfile
  )

  if (response$http_code %in% c(401L, 403L)) {
    if (file.exists(destfile)) {
      unlink(destfile)
    }
    return(list(
      success = FALSE,
      status = response$http_code,
      message = sprintf(
        "Dryad rejected the file download request (HTTP %s). Set DRYAD_API_TOKEN to a valid bearer token.",
        response$http_code
      ),
      destfile = destfile
    ))
  }

  if (response$curl_status != 0L || response$http_code >= 400L || response$http_code == 0L) {
    if (file.exists(destfile)) {
      unlink(destfile)
    }
    return(list(
      success = FALSE,
      status = response$http_code,
      message = sprintf("Dryad download failed with HTTP status %s.", response$http_code),
      destfile = destfile
    ))
  }

  list(success = TRUE, status = response$http_code, message = "downloaded", destfile = destfile)
}

dryad_extract_id_from_href <- function(href) {
  if (is.null(href) || !nzchar(href)) {
    return(NA_integer_)
  }
  suppressWarnings(as.integer(sub("^.*/", "", href)))
}

dryad_flatten_values <- function(x) {
  if (is.null(x) || !length(x)) {
    return(character(0))
  }
  if (!is.list(x)) {
    return(as.character(x))
  }
  unlist(lapply(x, dryad_flatten_values), use.names = FALSE)
}

dryad_compact_text <- function(x) {
  if (is.null(x) || !length(x)) {
    return(NA_character_)
  }
  out <- paste(dryad_flatten_values(x), collapse = "; ")
  out <- gsub("<[^>]+>", " ", out)
  out <- gsub("\\s+", " ", out)
  out <- trimws(out)
  if (!nzchar(out)) NA_character_ else out
}

dryad_author_string <- function(authors) {
  if (is.null(authors) || !length(authors)) {
    return(NA_character_)
  }

  author_names <- vapply(authors, function(author) {
    parts <- c(author$firstName, author$lastName)
    parts <- parts[!vapply(parts, is.null, logical(1))]
    paste(trimws(unlist(parts, use.names = FALSE)), collapse = " ")
  }, character(1))

  author_names <- author_names[nzchar(author_names)]
  if (!length(author_names)) NA_character_ else paste(author_names, collapse = "; ")
}

dryad_flatten_search_results <- function(payload, query_term = NA_character_) {
  datasets <- payload$`_embedded`$`stash:datasets`
  if (is.null(datasets) || !length(datasets)) {
    return(data.frame(stringsAsFactors = FALSE))
  }

  rows <- lapply(datasets, function(dataset) {
    data.frame(
      query_term = query_term,
      dryad_dataset_doi = dryad_or(dataset$identifier, NA_character_),
      dryad_dataset_id = dryad_or(dataset$id, NA_integer_),
      title = dryad_compact_text(dataset$title),
      authors = dryad_author_string(dataset$authors),
      abstract = dryad_compact_text(dataset$abstract),
      source_subjects = dryad_compact_text(c(dataset$subjects, dataset$subject, dataset$fieldOfScience, dataset$keywords)),
      field_of_science = dryad_compact_text(dataset$fieldOfScience),
      storage_size = suppressWarnings(as.numeric(dryad_or(dataset$storageSize, NA_real_))),
      latest_version_id = dryad_extract_id_from_href(dryad_or(dataset$`_links`$`stash:version`$href, "")),
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, rows)
}

dryad_flatten_versions <- function(payload, dataset_identifier = NA_character_) {
  versions <- payload$`_embedded`$`stash:versions`
  if (is.null(versions) || !length(versions)) {
    return(data.frame(stringsAsFactors = FALSE))
  }

  rows <- lapply(versions, function(version) {
    data.frame(
      dryad_dataset_doi = dataset_identifier,
      dryad_version_id = dryad_extract_id_from_href(dryad_or(version$`_links`$self$href, "")),
      title = dryad_compact_text(version$title),
      authors = dryad_author_string(version$authors),
      abstract = dryad_compact_text(version$abstract),
      source_subjects = dryad_compact_text(c(version$subjects, version$subject, version$fieldOfScience, version$keywords)),
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, rows)
}

dryad_flatten_files <- function(payload, dryad_dataset_doi = NA_character_, dryad_version_id = NA_integer_) {
  files <- payload$`_embedded`$`stash:files`
  if (is.null(files) || !length(files)) {
    return(data.frame(stringsAsFactors = FALSE))
  }

  rows <- lapply(files, function(file_entry) {
    data.frame(
      dryad_dataset_doi = dryad_dataset_doi,
      dryad_version_id = dryad_version_id,
      dryad_file_id = dryad_extract_id_from_href(dryad_or(file_entry$`_links`$self$href, "")),
      file_path = dryad_or(file_entry$path, NA_character_),
      file_size = suppressWarnings(as.numeric(dryad_or(file_entry$size, NA_real_))),
      mime_type = dryad_or(file_entry$mimeType, NA_character_),
      file_status = dryad_or(file_entry$status, NA_character_),
      download_href = dryad_or(file_entry$`_links`$`stash:download`$href, NA_character_),
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, rows)
}
