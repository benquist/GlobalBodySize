# europepmc_api.R
# Europe PMC-based discovery of Scientific Data plant trait papers.
#
# Europe PMC indexes Scientific Data with full text for Open Access articles,
# supporting section-aware boolean queries (KW:, TITLE:, ABSTRACT:, METHODS:).
# This catches papers where the CrossRef abstract is missing or uninformative
# but the keywords or methods section lists standard plant trait variable names.
# No API key required. Cursor-based pagination (no offset limit).

EPMC_BASE  <- "https://www.ebi.ac.uk/europepmc/webservices/rest/search"
EPMC_EMAIL <- "data-pipeline@research.org"

# ---------------------------------------------------------------------------
# Query strategies
# ---------------------------------------------------------------------------

# Each element: list(label, query).
# Uses Europe PMC field prefixes: KW:, TITLE:, ABSTRACT:, JOURNAL:
# Queries target Scientific Data (journal name) with plant trait signal.
europepmc_plant_trait_queries <- function() {
  list(
    list(
      label = "epmc_kw_plant_trait",
      query = 'JOURNAL:"Scientific Data" AND (KW:"plant trait" OR KW:"functional trait" OR KW:"leaf trait" OR KW:"plant functional trait" OR KW:"trait database")'
    ),
    list(
      label = "epmc_title_plant_trait",
      query = paste0(
        'JOURNAL:"Scientific Data" AND (',
        'TITLE:"plant trait" OR TITLE:"functional trait" OR ',
        'TITLE:"plant functional trait" OR TITLE:"leaf trait" OR ',
        'TITLE:"wood density" OR TITLE:"specific leaf area" OR ',
        'TITLE:"trait database" OR TITLE:"trait data"',
        ')'
      )
    ),
    list(
      label = "epmc_abstract_measured_traits",
      query = paste0(
        'JOURNAL:"Scientific Data" AND (',
        'ABSTRACT:"specific leaf area" OR ABSTRACT:"leaf dry matter content" OR ',
        'ABSTRACT:"wood density" OR ABSTRACT:"stomatal conductance" OR ',
        'ABSTRACT:"hydraulic conductance" OR ABSTRACT:"leaf nitrogen" OR ',
        'ABSTRACT:"plant height" OR ABSTRACT:"seed mass" OR ',
        'ABSTRACT:"root length" OR ABSTRACT:"turgor loss point"',
        ')'
      )
    ),
    list(
      label = "epmc_kw_trait_variants",
      query = paste0(
        'JOURNAL:"Scientific Data" AND (',
        'KW:"SLA" OR KW:"LMA" OR KW:"LDMC" OR KW:"Ks" OR KW:"P50" OR ',
        'KW:"Huber value" OR KW:"conduit diameter" OR KW:"bark thickness" OR ',
        'KW:"AusTraits" OR KW:"TRY" OR KW:"BIEN" OR KW:"FRED" OR KW:"LEDA"',
        ')'
      )
    ),
    # Full-text BODY: queries — searches methods/results/data descriptor body text.
    # This catches papers where trait names appear only in the data description,
    # not in the title, abstract, or keywords.
    list(
      label = "epmc_body_leaf_traits",
      query = paste0(
        'JOURNAL:"Scientific Data" AND (',
        'BODY:"specific leaf area" OR BODY:"leaf dry matter content" OR ',
        'BODY:"leaf nitrogen content" OR BODY:"leaf area index" OR ',
        'BODY:"leaf thickness" OR BODY:"leaf phosphorus" OR ',
        'BODY:"leaf carbon" OR BODY:"leaf mass per area"',
        ')'
      )
    ),
    list(
      label = "epmc_body_wood_root_traits",
      query = paste0(
        'JOURNAL:"Scientific Data" AND (',
        'BODY:"wood density" OR BODY:"wood specific gravity" OR ',
        'BODY:"specific root length" OR BODY:"root tissue density" OR ',
        'BODY:"root length density" OR BODY:"bark thickness" OR ',
        'BODY:"xylem vessel" OR BODY:"conduit diameter"',
        ')'
      )
    ),
    list(
      label = "epmc_body_plant_hydraulics",
      query = paste0(
        'JOURNAL:"Scientific Data" AND (',
        'BODY:"turgor loss point" OR BODY:"hydraulic conductance" OR ',
        'BODY:"stomatal conductance" OR BODY:"P50" OR BODY:"P88" OR ',
        'BODY:"vessel diameter" OR BODY:"cavitation resistance"',
        ')'
      )
    ),
    list(
      label = "epmc_body_trait_dataset",
      query = paste0(
        'JOURNAL:"Scientific Data" AND (',
        'BODY:"plant trait" OR BODY:"functional trait" OR BODY:"plant functional trait"',
        ') AND (',
        'BODY:"elevation gradient" OR BODY:"climate gradient" OR ',
        'BODY:"vegetation survey" OR BODY:"community weighted mean" OR ',
        'BODY:"trait database" OR BODY:"trait dataset"',
        ')'
      )
    )
  )
}

# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

europepmc_build_url <- function(query, cursor_mark = "*", page_size = 1000L) {
  # EPMC requires spaces encoded as + and double-quotes as %22.
  # URLencode(reserved=TRUE) over-encodes the colon in field prefixes like JOURNAL:
  # which causes the API to silently return XML instead of JSON.
  epmc_encode_query <- function(q) {
    q <- gsub('"',  '%22', q, fixed = TRUE)
    q <- gsub(' ',  '+',   q, fixed = TRUE)
    q <- gsub('(',  '%28', q, fixed = TRUE)
    q <- gsub(')',  '%29', q, fixed = TRUE)
    q
  }
  paste0(
    EPMC_BASE,
    "?query=",      epmc_encode_query(query),
    "&resultType=", "core",
    "&format=",     "json",
    "&pageSize=",   as.integer(page_size),
    "&cursorMark=", utils::URLencode(cursor_mark, reserved = FALSE),
    "&email=",      utils::URLencode(EPMC_EMAIL,  reserved = FALSE)
  )
}

europepmc_fetch_page <- function(url) {
  Sys.sleep(0.5)

  result <- tryCatch(
    dryad_run_curl(url, headers = list("Accept:application/json")),
    error = function(e) {
      warning(sprintf("europepmc_fetch_page: curl error: %s", conditionMessage(e)))
      NULL
    }
  )
  if (is.null(result)) return(NULL)

  if (result$http_code == 429L) {
    warning("europepmc_fetch_page: HTTP 429 — sleeping 30s then retrying.")
    Sys.sleep(30)
    result <- tryCatch(dryad_run_curl(url, headers = list("Accept:application/json")), error = function(e) NULL)
    if (is.null(result)) return(NULL)
  }
  if (!result$http_code %in% c(200L)) {
    warning(sprintf("europepmc_fetch_page: HTTP %d", result$http_code))
    return(NULL)
  }
  if (!nzchar(result$body)) return(NULL)

  tryCatch(
    jsonlite::fromJSON(result$body, simplifyVector = FALSE),
    error = function(e) {
      warning(sprintf("europepmc_fetch_page: JSON parse error: %s", conditionMessage(e)))
      NULL
    }
  )
}

# ---------------------------------------------------------------------------
# Data extraction from Europe PMC result items
# ---------------------------------------------------------------------------

europepmc_extract_doi <- function(item) {
  doi <- item$doi %||% ""
  if (nzchar(trimws(doi))) return(tolower(trimws(doi)))
  # Fallback: check identifiers
  ids <- item$identifiers %||% list()
  for (id_obj in ids %||% list()) {
    if (identical(tolower(id_obj$type %||% ""), "doi")) {
      return(tolower(trimws(id_obj$id %||% "")))
    }
  }
  NA_character_
}

europepmc_extract_authors <- function(author_list) {
  if (is.null(author_list) || length(author_list) == 0L) return(NA_character_)
  names_vec <- vapply(author_list, function(a) {
    trimws(as.character(a$fullName %||% a$lastName %||% ""))
  }, character(1))
  names_vec <- names_vec[nzchar(names_vec)]
  if (!length(names_vec)) NA_character_ else paste(names_vec, collapse = "; ")
}

europepmc_extract_subjects <- function(item) {
  kw_list <- item$keywordList$keyword %||% list()
  subjects <- vapply(kw_list %||% list(), function(k) as.character(k %||% ""), character(1))
  subjects <- subjects[nzchar(subjects)]
  if (!length(subjects)) NA_character_ else paste(subjects, collapse = "; ")
}

# ---------------------------------------------------------------------------
# Main discovery function
# ---------------------------------------------------------------------------

# Run all Europe PMC queries against Scientific Data.
# Returns a data.frame in provider_dataset_schema + (doi, paper_url, data_links, query_source).
europepmc_discover_plant_traits <- function(output_dir) {
  checkpoint_path <- file.path(output_dir, "europepmc_checkpoint.csv")
  queries         <- europepmc_plant_trait_queries()

  seen_dois   <- character(0)
  all_rows    <- list()
  first_write <- TRUE

  if (file.exists(checkpoint_path)) {
    existing <- tryCatch(
      utils::read.csv(checkpoint_path, stringsAsFactors = FALSE, check.names = FALSE),
      error = function(e) NULL
    )
    if (!is.null(existing) && nrow(existing) && "doi" %in% names(existing)) {
      seen_dois   <- unique(existing$doi[!is.na(existing$doi)])
      all_rows    <- list(existing)
      first_write <- FALSE
      message(sprintf("Europe PMC: resuming — %d DOIs already fetched.", length(seen_dois)))
    }
  }

  for (q in queries) {
    message(sprintf("Europe PMC: running query '%s'", q$label))
    cursor_mark <- "*"
    page_num    <- 1L

    repeat {
      url    <- europepmc_build_url(q$query, cursor_mark = cursor_mark)
      parsed <- europepmc_fetch_page(url)

      if (is.null(parsed)) {
        warning(sprintf("Europe PMC: fetch failed for '%s' — stopping query.", q$label))
        break
      }

      result_list <- parsed$resultList$result %||% list()
      if (length(result_list) == 0L) break

      rows <- lapply(result_list, function(item) {
        doi <- europepmc_extract_doi(item)
        if (is.na(doi) || !nzchar(doi)) return(NULL)

        title    <- trimws(as.character(item$title    %||% NA_character_))
        abstract <- trimws(as.character(item$abstractText %||% NA_character_))
        authors  <- europepmc_extract_authors(item$authorList$author)
        subjects <- europepmc_extract_subjects(item)

        score_result <- sdata_score_candidate(title, abstract, subjects)

        data.frame(
          source_provider      = "scientific_data",
          provider_dataset_id  = doi,
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
          doi                  = doi,
          paper_url            = paste0("https://doi.org/", doi),
          data_links           = NA_character_,
          query_source         = "europepmc",
          stringsAsFactors     = FALSE
        )
      })

      rows <- Filter(Negate(is.null), rows)

      if (length(rows) > 0L) {
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

      next_cursor <- parsed$nextCursorMark %||% ""
      if (!nzchar(trimws(next_cursor))) break
      if (identical(next_cursor, cursor_mark)) break   # guard
      cursor_mark <- next_cursor
      page_num    <- page_num + 1L

      message(sprintf("  Europe PMC '%s': page %d", q$label, page_num))
    }
  }

  if (!length(all_rows)) {
    empty <- provider_dataset_schema(0L)
    empty$doi <- empty$paper_url <- empty$data_links <- empty$query_source <- character(0)
    return(empty)
  }

  result <- do.call(rbind, all_rows)
  message(sprintf("Europe PMC: %d total candidate datasets (%d kept).",
                  nrow(result), sum(result$candidate_keep, na.rm = TRUE)))
  result
}
