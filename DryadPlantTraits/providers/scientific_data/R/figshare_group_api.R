# figshare_group_api.R
# Figshare reverse-search for plant trait datasets linked to Scientific Data.
#
# Strategy: search Figshare articles (item_type=3, datasets only) using
# plant-trait-specific terms. For each result, check whether the article's
# `resource_doi` (the citing paper) or `references` field points to a
# Scientific Data paper (DOI prefix 10.1038/s41597 or 10.1038/sdata).
# This inverts the paper→file direction: we find downloadable files FIRST
# and then link them back to the paper, bypassing paper-level scoring gates.
#
# Returns two data.frames:
#   - datasets: provider_dataset_schema rows (DOI = the paper DOI)
#   - files: provider_file_schema rows ready for compile step

FIGSHARE_API_BASE     <- "https://api.figshare.com/v2"
FIGSHARE_PAGE_SIZE    <- 100L
SDATA_DOI_PATTERNS    <- c("10.1038/s41597", "10.1038/sdata")

# ---------------------------------------------------------------------------
# Search term strategies
# ---------------------------------------------------------------------------

figshare_plant_trait_queries <- function() {
  c(
    "plant functional trait",
    "plant trait database",
    "leaf trait",
    "specific leaf area wood density",
    "stomatal conductance leaf",
    "root trait plant",
    "plant height seed mass",
    "hydraulic trait plant"
  )
}

# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

# GET Figshare article search endpoint.
# The GET /v2/articles endpoint accepts search_for, item_type, page, page_size as
# query parameters — equivalent to the POST /v2/articles/search body fields.
figshare_search_articles <- function(search_for, page = 1L) {
  url <- paste0(
    FIGSHARE_API_BASE, "/articles",
    "?search_for=",  utils::URLencode(search_for, reserved = TRUE),
    "&item_type=",   3L,     # datasets only
    "&page_size=",   FIGSHARE_PAGE_SIZE,
    "&page=",        as.integer(page)
  )

  Sys.sleep(0.5)
  result <- tryCatch(
    dryad_run_curl(url),
    error = function(e) {
      warning(sprintf("figshare_search_articles: curl error for '%s': %s",
                      search_for, conditionMessage(e)))
      NULL
    }
  )

  if (is.null(result)) return(NULL)
  if (result$http_code == 429L) {
    warning("figshare_search_articles: HTTP 429 — sleeping 30s then retrying.")
    Sys.sleep(30)
    result <- tryCatch(dryad_run_curl(url), error = function(e) NULL)
    if (is.null(result)) return(NULL)
  }
  if (!result$http_code %in% c(200L)) {
    warning(sprintf("figshare_search_articles: HTTP %d for '%s'", result$http_code, search_for))
    return(NULL)
  }
  if (!nzchar(result$body)) return(NULL)

  tryCatch(
    jsonlite::fromJSON(result$body, simplifyVector = FALSE),
    error = function(e) {
      warning(sprintf("figshare_search_articles: JSON parse error: %s", conditionMessage(e)))
      NULL
    }
  )
}

# Fetch full article detail (needed for resource_doi and file list).
figshare_fetch_article <- function(article_id) {
  url <- paste0(FIGSHARE_API_BASE, "/articles/", article_id)
  Sys.sleep(0.3)
  result <- tryCatch(
    dryad_run_curl(url),
    error = function(e) NULL
  )
  if (is.null(result) || !result$http_code %in% c(200L)) return(NULL)
  if (!nzchar(result$body)) return(NULL)
  tryCatch(
    jsonlite::fromJSON(result$body, simplifyVector = FALSE),
    error = function(e) NULL
  )
}

# ---------------------------------------------------------------------------
# Scientific Data link detection
# ---------------------------------------------------------------------------

# Returns TRUE if any string in `links` matches a Scientific Data DOI pattern.
figshare_is_sdata_linked <- function(resource_doi, references) {
  candidates <- c(
    as.character(resource_doi %||% ""),
    unlist(lapply(references %||% list(), function(r) as.character(r %||% "")))
  )
  candidates <- candidates[nzchar(candidates)]
  any(vapply(candidates, function(x) {
    any(vapply(SDATA_DOI_PATTERNS, function(pat) grepl(pat, x, fixed = TRUE), logical(1)))
  }, logical(1)))
}

# Extract Scientific Data paper DOI from resource_doi or references.
figshare_extract_sdata_doi <- function(resource_doi, references) {
  candidates <- c(
    as.character(resource_doi %||% ""),
    unlist(lapply(references %||% list(), function(r) as.character(r %||% "")))
  )
  candidates <- candidates[nzchar(candidates)]
  for (cand in candidates) {
    for (pat in SDATA_DOI_PATTERNS) {
      if (grepl(pat, cand, fixed = TRUE)) {
        # Normalise: strip https://doi.org/ prefix
        return(tolower(sub("^https?://doi\\.org/", "", trimws(cand))))
      }
    }
  }
  NA_character_
}

# ---------------------------------------------------------------------------
# Build output rows from a fetched article
# ---------------------------------------------------------------------------

figshare_build_file_rows <- function(article_detail, paper_doi, query_label) {
  files_list <- article_detail[["files"]]
  if (is.null(files_list) || length(files_list) == 0L) return(NULL)

  rows <- lapply(files_list, function(f) {
    fname <- as.character(f$name %||% NA_character_)
    data.frame(
      source_provider           = "scientific_data",
      provider_dataset_id       = paper_doi,
      provider_file_id          = paste0("figshare::", article_detail$id, "::", fname),
      file_path                 = fname,
      file_size                 = suppressWarnings(as.numeric(f$size %||% NA_real_)),
      mime_type                 = as.character(f$mime_type %||% NA_character_),
      file_status               = NA_character_,
      download_href             = as.character(f$download_url %||% NA_character_),
      candidate_score           = NA_real_,
      candidate_keep            = TRUE,
      query_term                = query_label,
      source_title              = as.character(article_detail$title %||% NA_character_),
      source_authors            = NA_character_,
      source_subjects           = sdata_collapse_list(article_detail$tags),
      source_abstract           = as.character(article_detail$description %||% NA_character_),
      file_supported_tabular    = provider_is_supported_tabular_path(fname %||% ""),
      file_supported_container  = provider_is_supported_archive_path(fname %||% ""),
      query_source              = "figshare_reverse",
      stringsAsFactors          = FALSE
    )
  })
  do.call(rbind, Filter(Negate(is.null), rows))
}

figshare_build_dataset_row <- function(article_detail, paper_doi, query_label) {
  title    <- as.character(article_detail$title %||% NA_character_)
  abstract <- as.character(article_detail$description %||% NA_character_)
  subjects <- sdata_collapse_list(article_detail$tags)

  score_result <- sdata_score_candidate(title, abstract, subjects)

  data.frame(
    source_provider      = "scientific_data",
    provider_dataset_id  = paper_doi,
    query_term           = query_label,
    title                = title,
    authors              = NA_character_,
    abstract             = abstract,
    source_subjects      = subjects,
    field_of_science     = subjects,
    storage_size         = suppressWarnings(as.numeric(article_detail$size %||% NA_real_)),
    candidate_score      = as.numeric(score_result$candidate_score),
    candidate_keep       = TRUE,   # already confirmed plant-trait via file search
    candidate_rationale  = paste0(score_result$candidate_rationale, "; figshare_reverse=TRUE"),
    doi                  = paper_doi,
    paper_url            = paste0("https://doi.org/", paper_doi),
    data_links           = paste0("10.6084/m9.figshare.", article_detail$id),
    query_source         = "figshare_reverse",
    stringsAsFactors     = FALSE
  )
}

# ---------------------------------------------------------------------------
# Main discovery function
# ---------------------------------------------------------------------------

# Search Figshare for plant trait datasets and link them back to Scientific Data papers.
# Returns list(datasets = data.frame, files = data.frame).
figshare_reverse_discover <- function(output_dir) {
  ds_checkpoint_path   <- file.path(output_dir, "figshare_reverse_datasets.csv")
  file_checkpoint_path <- file.path(output_dir, "figshare_reverse_files.csv")
  queries <- figshare_plant_trait_queries()

  seen_article_ids <- character(0)
  dataset_rows     <- list()
  file_rows        <- list()
  first_ds_write   <- TRUE
  first_file_write <- TRUE

  # Resume from checkpoint
  if (file.exists(file_checkpoint_path)) {
    existing <- tryCatch(
      utils::read.csv(file_checkpoint_path, stringsAsFactors = FALSE, check.names = FALSE),
      error = function(e) NULL
    )
    if (!is.null(existing) && nrow(existing) && "provider_file_id" %in% names(existing)) {
      # Recover article IDs already processed from the file IDs
      seen_article_ids <- unique(sub("figshare::([0-9]+)::.*", "\\1",
                                     grep("^figshare::", existing$provider_file_id, value = TRUE)))
      file_rows        <- list(existing)
      first_file_write <- FALSE
      message(sprintf("Figshare reverse: resuming — %d articles already processed.", length(seen_article_ids)))
    }
  }
  if (file.exists(ds_checkpoint_path)) {
    existing_ds <- tryCatch(
      utils::read.csv(ds_checkpoint_path, stringsAsFactors = FALSE, check.names = FALSE),
      error = function(e) NULL
    )
    if (!is.null(existing_ds) && nrow(existing_ds)) {
      dataset_rows   <- list(existing_ds)
      first_ds_write <- FALSE
    }
  }

  for (q in queries) {
    message(sprintf("Figshare reverse: searching '%s'", q))
    page <- 1L

    repeat {
      results <- figshare_search_articles(search_for = q, page = page)
      if (is.null(results) || length(results) == 0L) break

      kept_this_page <- 0L

      for (item in results) {
        article_id <- as.character(item$id %||% "")
        if (!nzchar(article_id) || article_id %in% seen_article_ids) next

        seen_article_ids <- c(seen_article_ids, article_id)

        # Fetch full article detail to get resource_doi, references, and files
        detail <- figshare_fetch_article(article_id)
        if (is.null(detail)) next

        # Check Scientific Data link
        if (!figshare_is_sdata_linked(detail$resource_doi, detail$references)) next

        paper_doi <- figshare_extract_sdata_doi(detail$resource_doi, detail$references)
        if (is.na(paper_doi)) next

        message(sprintf("  Figshare reverse: found article %s linked to paper %s", article_id, paper_doi))
        kept_this_page <- kept_this_page + 1L

        # Build dataset row
        ds_row <- tryCatch(figshare_build_dataset_row(detail, paper_doi, q), error = function(e) NULL)
        if (!is.null(ds_row)) {
          dataset_rows[[length(dataset_rows) + 1L]] <- ds_row
          utils::write.table(
            ds_row, ds_checkpoint_path,
            sep = ",", row.names = FALSE, na = "",
            append = !first_ds_write, col.names = first_ds_write,
            qmethod = "double"
          )
          first_ds_write <- FALSE
        }

        # Build file rows
        f_rows <- tryCatch(figshare_build_file_rows(detail, paper_doi, q), error = function(e) NULL)
        if (!is.null(f_rows) && nrow(f_rows) > 0L) {
          file_rows[[length(file_rows) + 1L]] <- f_rows
          utils::write.table(
            f_rows, file_checkpoint_path,
            sep = ",", row.names = FALSE, na = "",
            append = !first_file_write, col.names = first_file_write,
            qmethod = "double"
          )
          first_file_write <- FALSE
        }
      }

      # Figshare returns empty list [] when past last page
      if (length(results) < FIGSHARE_PAGE_SIZE) break
      page <- page + 1L
    }
  }

  datasets <- if (length(dataset_rows)) do.call(rbind, dataset_rows) else {
    empty <- provider_dataset_schema(0L)
    empty$doi <- empty$paper_url <- empty$data_links <- empty$query_source <- character(0)
    empty
  }
  files <- if (length(file_rows)) do.call(rbind, file_rows) else {
    empty <- provider_file_schema(0L)
    empty$query_source <- character(0)
    empty
  }

  n_tabular <- if (nrow(files)) sum(files$file_supported_tabular, na.rm = TRUE) else 0L
  message(sprintf("Figshare reverse: %d Scientific Data-linked datasets, %d files (%d tabular).",
                  nrow(datasets), nrow(files), n_tabular))

  list(datasets = datasets, files = files)
}
