# scientific_data_api.R
# Functions for discovering plant trait datasets via Scientific Data (ISSN 2052-4463)
# using the CrossRef public API. No API key is required.

SDATA_CROSSREF_BASE <- "https://api.crossref.org/works"
SDATA_ISSN           <- "2052-4463"
# CrossRef polite pool: pass mailto as query param (avoids shell-quoting issues with User-Agent)
SDATA_CROSSREF_MAILTO <- "data-pipeline@research.org"

# Patterns for detecting data repository links in text fields
SDATA_FIGSHARE_PATTERN <- "10\\.6084/m9\\.figshare\\.([0-9]+(\\.[0-9]+)*)"
SDATA_ZENODO_PATTERN   <- "10\\.5281/zenodo\\.([0-9]+)"
SDATA_GITHUB_PATTERN   <- "github\\.com/([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)"
SDATA_DRYAD_PATTERN    <- "(10\\.5061/dryad\\.[A-Za-z0-9]+|datadryad\\.org)"


# Compose a CrossRef query URL for Scientific Data papers.
sdata_crossref_build_url <- function(query_term, rows = 20L, offset = 0L) {
  encoded_term <- utils::URLencode(query_term, reserved = TRUE)
  encoded_filter <- utils::URLencode(
    paste0("issn:", SDATA_ISSN),
    reserved = TRUE
  )
  select_fields <- utils::URLencode(
    "DOI,title,abstract,author,published,link,relation,subject",
    reserved = TRUE
  )
  paste0(
    SDATA_CROSSREF_BASE,
    "?filter=", encoded_filter,
    "&query=", encoded_term,
    "&rows=", as.integer(rows),
    "&offset=", as.integer(offset),
    "&select=", select_fields,
    "&mailto=", utils::URLencode(SDATA_CROSSREF_MAILTO, reserved = TRUE)
  )
}


# Query CrossRef for Scientific Data papers matching query_term.
# Returns the parsed JSON list (message element), or NULL on failure.
# Sleeps 1 second before each call to respect the polite pool.
sdata_crossref_search <- function(query_term, rows = 20L, offset = 0L) {
  Sys.sleep(1)

  url <- sdata_crossref_build_url(query_term, rows = rows, offset = offset)

  result <- tryCatch(
    dryad_run_curl(url),  # CrossRef polite pool via mailto= query param
    error = function(e) {
      warning(sprintf("sdata_crossref_search: curl error for term '%s' offset %d: %s",
                      query_term, offset, conditionMessage(e)))
      NULL
    }
  )

  if (is.null(result)) return(NULL)

  if (identical(result$http_code, 429L)) {
    warning("sdata_crossref_search: HTTP 429 — sleeping 10s then retrying once.")
    Sys.sleep(10)
    result <- tryCatch(
      dryad_run_curl(url),
      error = function(e) {
        warning(sprintf("sdata_crossref_search: retry curl error: %s", conditionMessage(e)))
        NULL
      }
    )
    if (is.null(result)) return(NULL)
  }

  if (!result$http_code %in% c(200L)) {
    warning(sprintf("sdata_crossref_search: HTTP %d for term '%s'", result$http_code, query_term))
    return(NULL)
  }

  if (!nzchar(result$body)) return(NULL)

  parsed <- tryCatch(
    jsonlite::fromJSON(result$body, simplifyVector = FALSE),
    error = function(e) {
      warning(sprintf("sdata_crossref_search: JSON parse error: %s", conditionMessage(e)))
      NULL
    }
  )

  parsed
}


# Extract a scalar character value from a possibly nested CrossRef field.
sdata_scalar_char <- function(x, default = NA_character_) {
  if (is.null(x) || (length(x) == 0L)) return(default)
  val <- x[[1]]
  if (is.null(val) || length(val) == 0L) return(default)
  out <- trimws(as.character(val))
  if (!nzchar(out)) default else out
}


# Collapse a list of strings into a single semicolon-separated string.
sdata_collapse_list <- function(x) {
  if (is.null(x) || length(x) == 0L) return(NA_character_)
  vals <- trimws(as.character(unlist(x)))
  vals <- vals[nzchar(vals)]
  if (!length(vals)) NA_character_ else paste(vals, collapse = "; ")
}


# Extract a flat author string from CrossRef author array.
sdata_extract_authors <- function(author_list) {
  if (is.null(author_list) || length(author_list) == 0L) return(NA_character_)
  names_vec <- vapply(author_list, function(a) {
    family <- a$family %||% ""
    given  <- a$given  %||% ""
    trimws(paste(given, family))
  }, character(1))
  names_vec <- names_vec[nzchar(names_vec)]
  if (!length(names_vec)) NA_character_ else paste(names_vec, collapse = "; ")
}


# Extract published year as character from CrossRef date-parts structure.
sdata_extract_year <- function(published) {
  if (is.null(published)) return(NA_character_)
  dp <- published[["date-parts"]]
  if (is.null(dp) || length(dp) == 0L) return(NA_character_)
  first <- dp[[1]]
  if (is.null(first) || length(first) == 0L) return(NA_character_)
  as.character(first[[1]])
}


# Scan a text blob and extract unique data-repo links.
# Returns named list: figshare (DOIs), zenodo (IDs), github (owner/repo), dryad (DOIs)
sdata_extract_repo_links_from_text <- function(text) {
  if (is.null(text) || !nzchar(trimws(text))) {
    return(list(figshare = character(0), zenodo = character(0),
                github = character(0), dryad = character(0)))
  }

  extract_all <- function(pattern, txt) {
    m <- gregexpr(pattern, txt, perl = TRUE)
    unique(regmatches(txt, m)[[1]])
  }

  figshare_hits <- extract_all(SDATA_FIGSHARE_PATTERN, text)
  zenodo_hits   <- extract_all(SDATA_ZENODO_PATTERN,   text)
  github_raw    <- extract_all(SDATA_GITHUB_PATTERN,   text)
  dryad_hits    <- extract_all(SDATA_DRYAD_PATTERN,    text)

  # Normalise GitHub matches: strip trailing punctuation / path components
  github_hits <- unique(sub("/.*$", "", sub("github\\.com/", "", github_raw)))
  # Keep only owner/repo pairs (two components)
  github_hits <- github_hits[grepl("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", github_hits)]

  # Normalise Dryad: keep only DOI form
  dryad_dois <- unique(grep("^10\\.5061/dryad\\.", dryad_hits, value = TRUE))

  list(
    figshare = figshare_hits,
    zenodo   = zenodo_hits,
    github   = github_hits,
    dryad    = dryad_dois
  )
}


# Merge two repo-link lists (element-wise union).
sdata_merge_repo_links <- function(a, b) {
  list(
    figshare = unique(c(a$figshare, b$figshare)),
    zenodo   = unique(c(a$zenodo,   b$zenodo)),
    github   = unique(c(a$github,   b$github)),
    dryad    = unique(c(a$dryad,    b$dryad))
  )
}


# Convert a repo-links list into a comma-separated string for the data_links column.
sdata_repo_links_to_string <- function(links) {
  all_links <- c(
    links$figshare,
    links$zenodo,
    links$github,
    links$dryad
  )
  all_links <- unique(all_links[nzchar(all_links)])
  if (!length(all_links)) NA_character_ else paste(all_links, collapse = ", ")
}


# Extract data repository links from a CrossRef work item.
# Scans abstract, relation (has-part / references), and returns merged list.
sdata_extract_data_links_from_item <- function(item) {
  abstract_text <- item$abstract %||% ""
  abstract_links <- sdata_extract_repo_links_from_text(abstract_text)

  relation_links <- list(figshare = character(0), zenodo = character(0),
                         github = character(0), dryad = character(0))
  relation <- item$relation
  if (!is.null(relation) && length(relation) > 0L) {
    relation_parts <- c(relation[["has-part"]], relation[["references"]])
    for (rel in relation_parts) {
      id_val <- rel$id %||% ""
      if (nzchar(id_val)) {
        hits <- sdata_extract_repo_links_from_text(id_val)
        relation_links <- sdata_merge_repo_links(relation_links, hits)
      }
    }
  }

  sdata_merge_repo_links(abstract_links, relation_links)
}


# Flatten a parsed CrossRef response into a data.frame matching provider_dataset_schema()
# plus extra columns: doi, paper_url, data_links.
# query_term is the search term that produced this result set.
sdata_flatten_crossref_results <- function(payload, query_term) {
  empty <- provider_dataset_schema(0L)
  empty$doi        <- character(0)
  empty$paper_url  <- character(0)
  empty$data_links <- character(0)

  if (is.null(payload)) return(empty)

  message_block <- payload[["message"]]
  if (is.null(message_block)) return(empty)

  items <- message_block[["items"]]
  if (is.null(items) || length(items) == 0L) return(empty)

  rows <- lapply(items, function(item) {
    doi         <- item$DOI %||% NA_character_
    title       <- sdata_scalar_char(item$title)
    abstract    <- trimws(item$abstract %||% NA_character_)
    authors_str <- sdata_extract_authors(item$author)
    subjects    <- sdata_collapse_list(item$subject)
    year        <- sdata_extract_year(item$published)

    paper_url <- paste0("https://doi.org/", doi)

    repo_links  <- sdata_extract_data_links_from_item(item)
    data_links  <- sdata_repo_links_to_string(repo_links)

    data.frame(
      source_provider    = "scientific_data",
      provider_dataset_id = doi,
      query_term         = query_term,
      title              = title,
      authors            = authors_str,
      abstract           = abstract,
      source_subjects    = subjects,
      field_of_science   = subjects,
      storage_size       = NA_real_,
      candidate_score    = NA_real_,
      candidate_keep     = TRUE,
      candidate_rationale = NA_character_,
      doi                = doi,
      paper_url          = paper_url,
      data_links         = data_links,
      stringsAsFactors   = FALSE
    )
  })

  do.call(rbind, rows)
}


# Score a single candidate dataset using the existing dryad_score_candidate_dataset()
# if available, otherwise return a neutral score.
sdata_score_candidate <- function(title, abstract, source_subjects) {
  score_fn <- get0("dryad_score_candidate_dataset", mode = "function", inherits = TRUE)
  if (!is.null(score_fn)) {
    return(score_fn(
      title = title %||% "",
      abstract = abstract %||% "",
      source_subjects = source_subjects %||% ""
    ))
  }

  # Fallback neutral score when dryad_score_candidate_dataset is not sourced
  list(
    candidate_score     = 0L,
    candidate_keep      = TRUE,
    candidate_rationale = "scoring_unavailable",
    plant_signal_count  = NA_integer_,
    trait_signal_count  = NA_integer_,
    measurement_signal_count = NA_integer_,
    exclude_signal_count = NA_integer_
  )
}
