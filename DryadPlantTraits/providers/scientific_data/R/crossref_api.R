# crossref_api.R
# Functions to fetch data repository links from CrossRef for Scientific Data papers.
# CrossRef provides relation data (e.g., supplementary, has-preprint) and references
# that often point to Figshare, Zenodo, Dryad, and GitHub repositories.

CROSSREF_API_BASE <- "https://api.crossref.org/works"

# Fetch a Scientific Data paper's metadata and relations from CrossRef.
# Input: DOI (with or without "10." prefix)
# Output: list with $links (vector of repo URLs), $title, $abstract, etc.
crossref_fetch_paper_relations <- function(doi) {
  if (is.null(doi) || is.na(doi) || !nzchar(trimws(doi))) {
    return(list(links = character(0), error = "Invalid DOI"))
  }

  doi_clean <- trimws(as.character(doi))
  if (!startsWith(doi_clean, "10.")) {
    doi_clean <- paste0("10.", doi_clean)
  }

  url <- paste0(CROSSREF_API_BASE, "/", doi_clean)

  result <- tryCatch(
    dryad_run_curl(url),
    error = function(e) {
      warning(sprintf("crossref_fetch_paper_relations: curl error for %s: %s", doi, conditionMessage(e)))
      NULL
    }
  )

  if (is.null(result) || result$http_code != 200L) {
    http_code <- if (!is.null(result)) result$http_code else "NULL"
    return(list(links = character(0), error = sprintf("HTTP %s", http_code)))
  }

  if (!nzchar(result$body)) {
    return(list(links = character(0), error = "Empty response body"))
  }

  parsed <- tryCatch(
    jsonlite::fromJSON(result$body, simplifyVector = FALSE),
    error = function(e) {
      warning(sprintf("crossref_fetch_paper_relations: JSON parse error for %s: %s", doi, conditionMessage(e)))
      NULL
    }
  )

  if (is.null(parsed) || !identical(parsed$status, "ok")) {
    return(list(links = character(0), error = "Invalid or malformed JSON response"))
  }

  msg <- parsed$message
  if (is.null(msg)) {
    return(list(links = character(0), error = "No message in response"))
  }

  # Extract data repository links from relations, references, and URL fields
  links <- character(0)

  # 1. Check relations (supplementary materials, preprints, etc.)
  relations <- msg$relation %||% list()
  for (rel in relations) {
    rel_type <- rel$`relation-type` %||% ""
    rel_urls <- rel$`related-work` %||% list()
    # Filter for data-related relations: 'has-preprint', 'is-supplemented-by', 'supplement', etc.
    if (grepl("supplement|data|preprint", rel_type, ignore.case = TRUE)) {
      for (related in rel_urls) {
        rel_doi <- related$DOI %||% NA_character_
        if (!is.na(rel_doi) && nzchar(rel_doi)) {
          links <- c(links, rel_doi)
        }
      }
    }
  }

  # 2. Check URL field for supplementary or data links
  url_field <- msg$URL %||% NA_character_
  if (!is.na(url_field) && nzchar(url_field)) {
    links <- c(links, url_field)
  }

  # 3. Check reference list for Figshare, Zenodo, Dryad, GitHub links
  references <- msg$reference %||% list()
  for (ref in references) {
    ref_doi <- ref$DOI %||% NA_character_
    if (!is.na(ref_doi) && nzchar(ref_doi)) {
      # Filter for known data repo DOI prefixes
      if (grepl("^10\\.(6084|5281|5061)", ref_doi, perl = TRUE)) { # figshare, zenodo, dryad
        links <- c(links, ref_doi)
      }
    }

    # Also check raw reference string for repo URLs
    ref_str <- ref$`raw-text` %||% ""
    if (nzchar(ref_str)) {
      # Look for GitHub, Figshare, Zenodo, Dryad URLs in text
      extracted <- character(0)
      if (grepl("github\\.com", ref_str, ignore.case = TRUE)) {
        gh_match <- regmatches(ref_str, regexpr("https?://github\\.com/[^/\\s]+/[^/\\s]+", ref_str, ignore.case = TRUE))
        if (length(gh_match)) extracted <- c(extracted, gh_match)
      }
      if (grepl("figshare\\.com|10\\.6084", ref_str, ignore.case = TRUE)) {
        fig_match <- regmatches(ref_str, regexpr("10\\.6084/m9\\.figshare\\.[0-9]+", ref_str, perl = TRUE))
        if (length(fig_match)) extracted <- c(extracted, fig_match)
      }
      if (grepl("zenodo\\.org|10\\.5281", ref_str, ignore.case = TRUE)) {
        zen_match <- regmatches(ref_str, regexpr("10\\.5281/zenodo\\.[0-9]+", ref_str, perl = TRUE))
        if (length(zen_match)) extracted <- c(extracted, zen_match)
      }
      if (grepl("dryad\\.org|10\\.5061", ref_str, ignore.case = TRUE)) {
        dry_match <- regmatches(ref_str, regexpr("10\\.5061/dryad\\.[a-z0-9]+", ref_str, perl = TRUE))
        if (length(dry_match)) extracted <- c(extracted, dry_match)
      }
      links <- c(links, extracted)
    }
  }

  # 4. Check the DOI URL itself (sometimes contains supplementary/data info)
  # Nature Scientific Data often links to Figshare repos in the "Data Availability" section
  # which CrossRef may not capture, but we can check the paper's URL
  paper_url <- msg$URL %||% NA_character_

  list(
    links = unique(trimws(links[nzchar(links)])),
    title = msg$title %||% NA_character_,
    abstract = msg$abstract %||% NA_character_,
    doi = doi_clean,
    paper_url = paper_url
  )
}


# Fetch data links for a vector of DOIs (vectorized wrapper).
# Returns named character vector mapping DOI to comma-separated links.
crossref_fetch_batch_data_links <- function(dois, verbose = TRUE) {
  result <- setNames(character(length(dois)), dois)

  for (i in seq_along(dois)) {
    doi <- dois[i]
    if (verbose && (i %% 5) == 0) {
      message(sprintf("  [%d/%d] Fetching CrossRef relations for %s", i, length(dois), doi))
    }

    relations <- crossref_fetch_paper_relations(doi)
    if (length(relations$links) > 0L) {
      result[i] <- paste(relations$links, collapse = ", ")
    }

    Sys.sleep(0.5) # Be polite to CrossRef API
  }

  result
}
