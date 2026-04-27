# openalex_api.R
# OpenAlex-based discovery of Scientific Data plant trait papers.
#
# Uses OpenAlex's ML concept/keyword indexing and cursor pagination.
# OpenAlex indexes full-text of Open Access papers, so it catches trait-rich
# papers whose CrossRef abstracts are missing or too brief to score.
# No API key required; polite-pool email sent as `mailto` query param.

OPENALEX_BASE  <- "https://api.openalex.org/works"
OPENALEX_EMAIL <- "data-pipeline@research.org"

# ---------------------------------------------------------------------------
# Search query strategies
# ---------------------------------------------------------------------------

# Each query is a named list(label, search).
# "search" uses OpenAlex BM25 full-text search (title + abstract + indexed keywords).
# Separate queries are run to maximise recall; dedup by DOI is done downstream.
openalex_plant_trait_queries <- function() {
  list(
    list(label = "oa_plant_functional_trait",  search = "plant functional trait"),
    list(label = "oa_leaf_trait",              search = "leaf trait database"),
    list(label = "oa_specific_leaf_area",      search = "specific leaf area"),
    list(label = "oa_wood_density",            search = "wood density plant"),
    list(label = "oa_root_trait",              search = "root trait plant"),
    list(label = "oa_hydraulic_trait",         search = "hydraulic trait plant"),
    list(label = "oa_trait_database",          search = "plant trait database ecology"),
    list(label = "oa_lma_ldmc",                search = "leaf mass area leaf dry matter content")
  )
}

# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

openalex_build_url <- function(search_term, cursor = "*", per_page = 200L) {
  # Filter: ISSN for Scientific Data = 2052-4463
  filter_str <- "primary_location.source.issn:2052-4463"
  select_str <- paste0(
    "id,doi,title,abstract_inverted_index,authorships,",
    "keywords,concepts,primary_location,publication_year"
  )
  paste0(
    OPENALEX_BASE,
    "?filter=",    utils::URLencode(filter_str,  reserved = TRUE),
    "&search=",    utils::URLencode(search_term, reserved = TRUE),
    "&per-page=",  as.integer(per_page),
    "&cursor=",    utils::URLencode(cursor,       reserved = TRUE),
    "&select=",    utils::URLencode(select_str,   reserved = TRUE),
    "&mailto=",    utils::URLencode(OPENALEX_EMAIL, reserved = TRUE)
  )
}

# Reconstruct plain-text abstract from OpenAlex inverted index format.
# Format: list where names = words, values = list of integer positions.
openalex_reconstruct_abstract <- function(inv_idx) {
  if (is.null(inv_idx) || length(inv_idx) == 0L) return(NA_character_)
  word_pos <- unlist(lapply(names(inv_idx), function(word) {
    positions <- unlist(inv_idx[[word]])
    setNames(rep(word, length(positions)), as.character(positions))
  }))
  if (length(word_pos) == 0L) return(NA_character_)
  ordered <- word_pos[order(as.integer(names(word_pos)))]
  paste(ordered, collapse = " ")
}

# Extract authors as a semicolon-separated string from OpenAlex authorship array.
openalex_extract_authors <- function(authorships) {
  if (is.null(authorships) || length(authorships) == 0L) return(NA_character_)
  names_vec <- vapply(authorships, function(a) {
    display <- a$author$display_name %||% ""
    trimws(as.character(display))
  }, character(1))
  names_vec <- names_vec[nzchar(names_vec)]
  if (!length(names_vec)) NA_character_ else paste(names_vec, collapse = "; ")
}

# Extract semicolon-separated concept/keyword labels.
openalex_extract_subjects <- function(concepts, keywords) {
  concept_labels <- character(0)
  if (!is.null(concepts) && length(concepts) > 0L) {
    concept_labels <- vapply(concepts, function(c) {
      as.character(c$display_name %||% "")
    }, character(1))
    concept_labels <- concept_labels[nzchar(concept_labels)]
  }
  kw_labels <- character(0)
  if (!is.null(keywords) && length(keywords) > 0L) {
    kw_labels <- vapply(keywords, function(k) {
      as.character(k$display_name %||% k$keyword %||% "")
    }, character(1))
    kw_labels <- kw_labels[nzchar(kw_labels)]
  }
  all_labels <- unique(c(concept_labels, kw_labels))
  if (!length(all_labels)) NA_character_ else paste(all_labels, collapse = "; ")
}

# Run one OpenAlex request and return the parsed JSON or NULL.
openalex_fetch_page <- function(url) {
  Sys.sleep(0.5)   # OpenAlex polite pool: 10 req/s max

  result <- tryCatch(
    dryad_run_curl(url),
    error = function(e) {
      warning(sprintf("openalex_fetch_page: curl error: %s", conditionMessage(e)))
      NULL
    }
  )
  if (is.null(result)) return(NULL)

  if (result$http_code == 429L) {
    warning("openalex_fetch_page: HTTP 429 — sleeping 30s then retrying.")
    Sys.sleep(30)
    result <- tryCatch(dryad_run_curl(url), error = function(e) NULL)
    if (is.null(result)) return(NULL)
  }

  if (!result$http_code %in% c(200L)) {
    warning(sprintf("openalex_fetch_page: HTTP %d", result$http_code))
    return(NULL)
  }
  if (!nzchar(result$body)) return(NULL)

  tryCatch(
    jsonlite::fromJSON(result$body, simplifyVector = FALSE),
    error = function(e) {
      warning(sprintf("openalex_fetch_page: JSON parse error: %s", conditionMessage(e)))
      NULL
    }
  )
}

# ---------------------------------------------------------------------------
# Main discovery function
# ---------------------------------------------------------------------------

# Run all OpenAlex queries against Scientific Data papers.
# Returns a data.frame in provider_dataset_schema + extra columns (doi, paper_url, data_links).
# Deduplication by DOI is done inside so repeated query hits don't inflate rows.
openalex_discover_plant_traits <- function(output_dir, per_page = 200L) {
  checkpoint_path <- file.path(output_dir, "openalex_checkpoint.csv")
  queries         <- openalex_plant_trait_queries()

  seen_dois <- character(0)
  all_rows  <- list()
  first_write <- TRUE

  if (file.exists(checkpoint_path)) {
    existing <- tryCatch(
      utils::read.csv(checkpoint_path, stringsAsFactors = FALSE, check.names = FALSE),
      error = function(e) NULL
    )
    if (!is.null(existing) && nrow(existing) && "doi" %in% names(existing)) {
      seen_dois   <- unique(existing$doi)
      all_rows    <- list(existing)
      first_write <- FALSE
      message(sprintf("OpenAlex: resuming — %d DOIs already fetched.", length(seen_dois)))
    }
  }

  for (q in queries) {
    message(sprintf("OpenAlex: running query '%s'", q$label))
    cursor <- "*"
    page_num <- 1L

    repeat {
      url    <- openalex_build_url(q$search, cursor = cursor, per_page = per_page)
      parsed <- openalex_fetch_page(url)

      if (is.null(parsed)) {
        warning(sprintf("OpenAlex: fetch failed for '%s' (cursor=%s) — stopping query.", q$label, cursor))
        break
      }

      items <- parsed$results
      if (is.null(items) || length(items) == 0L) break

      rows <- lapply(items, function(item) {
        raw_doi <- trimws(tolower(item$doi %||% ""))
        # OpenAlex DOI format is full URL like "https://doi.org/10.1038/..."
        doi_clean <- sub("^https://doi.org/", "", raw_doi)
        if (!nzchar(doi_clean)) return(NULL)

        title    <- sdata_scalar_char(item$title)
        abstract <- openalex_reconstruct_abstract(item$abstract_inverted_index)
        authors  <- openalex_extract_authors(item$authorships)
        subjects <- openalex_extract_subjects(item$concepts, item$keywords)

        score_result <- sdata_score_candidate(title, abstract, subjects)

        data.frame(
          source_provider      = "scientific_data",
          provider_dataset_id  = doi_clean,
          query_term           = q$label,
          title                = title,
          authors              = authors,
          abstract             = abstract,
          source_subjects      = subjects,
          field_of_science     = subjects,
          storage_size         = NA_real_,
          candidate_score      = as.numeric(score_result$candidate_score),
          candidate_keep       = as.logical(score_result$candidate_keep),
          candidate_rationale  = as.character(score_result$candidate_rationale),
          doi                  = doi_clean,
          paper_url            = paste0("https://doi.org/", doi_clean),
          data_links           = NA_character_,
          query_source         = "openalex",
          stringsAsFactors     = FALSE
        )
      })

      rows <- Filter(Negate(is.null), rows)
      if (length(rows) == 0L) {
        # advance cursor
      } else {
        page_df  <- do.call(rbind, rows)
        new_rows <- page_df[!page_df$doi %in% seen_dois, , drop = FALSE]

        if (nrow(new_rows) > 0L) {
          seen_dois <- c(seen_dois, new_rows$doi)
          all_rows[[length(all_rows) + 1L]] <- new_rows
          utils::write.table(
            new_rows, checkpoint_path,
            sep = ",", row.names = FALSE, na = "",
            append = !first_write, col.names = first_write,
            qmethod = "double"
          )
          first_write <- FALSE
        }
      }

      next_cursor <- parsed$meta[["next_cursor"]]
      if (is.null(next_cursor) || !nzchar(trimws(next_cursor %||% ""))) break
      if (identical(next_cursor, cursor)) break   # guard against infinite loop
      cursor   <- next_cursor
      page_num <- page_num + 1L

      message(sprintf("  OpenAlex '%s': page %d (cursor=%s...)",
                      q$label, page_num,
                      substr(next_cursor, 1, 20)))
    }
  }

  if (!length(all_rows)) {
    empty <- provider_dataset_schema(0L)
    empty$doi         <- character(0)
    empty$paper_url   <- character(0)
    empty$data_links  <- character(0)
    empty$query_source <- character(0)
    return(empty)
  }

  result <- do.call(rbind, all_rows)
  message(sprintf("OpenAlex: %d total candidate datasets (%d kept).",
                  nrow(result), sum(result$candidate_keep, na.rm = TRUE)))
  result
}
