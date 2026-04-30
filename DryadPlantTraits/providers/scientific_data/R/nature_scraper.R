# nature_scraper.R
# Scrapes Nature.com landing pages for Scientific Data papers to extract
# data availability links (Figshare, Zenodo, Dryad, GitHub).
# Used for papers where CrossRef does not expose linked data repository DOIs.

# User-agent for polite scraping
NATURE_SCRAPER_UA <- "DryadPlantTraits/1.0 (research data pipeline; mailto:data-pipeline@research.org)"

# Fetch HTML from a Nature.com article landing page.
# Returns the HTML as a character string, or NULL on error.
nature_fetch_landing_page <- function(doi) {
  doi_clean <- trimws(as.character(doi))

  # Build the article URL: https://www.nature.com/articles/{doi-suffix}
  # Nature.com uses the DOI suffix (everything after "10.1038/") as the article path
  doi_suffix <- sub("^10\\.1038/", "", doi_clean, perl = TRUE)
  if (!nzchar(doi_suffix) || doi_suffix == doi_clean) {
    warning(sprintf("nature_fetch_landing_page: expected 10.1038/ DOI, got '%s'", doi_clean))
    return(NULL)
  }

  url <- paste0("https://www.nature.com/articles/", doi_suffix)

  headers <- c(
    paste0("User-Agent: ", NATURE_SCRAPER_UA),
    "Accept: text/html,application/xhtml+xml",
    "Accept-Language: en-US,en;q=0.9"
  )

  result <- tryCatch(
    dryad_run_curl(url, headers = headers),
    error = function(e) {
      warning(sprintf("nature_fetch_landing_page: curl error for %s: %s", doi_clean, conditionMessage(e)))
      NULL
    }
  )

  if (is.null(result)) return(NULL)

  # Handle HTTP 301/302 redirects — Nature sometimes redirects old sdata. URLs
  if (result$http_code %in% c(301L, 302L)) {
    Sys.sleep(1)
    result <- tryCatch(
      dryad_run_curl(url, headers = c(headers, "Location-follow: true")),
      error = function(e) NULL
    )
    if (is.null(result)) return(NULL)
  }

  if (!result$http_code %in% c(200L, 301L, 302L)) {
    warning(sprintf("nature_fetch_landing_page: HTTP %d for %s", result$http_code, doi_clean))
    return(NULL)
  }

  result$body
}


# Extract data repository links from a Nature article HTML page.
# Looks in the "Data availability", "Data records", and supplementary sections.
# Returns a character vector of repository DOIs or URLs.
nature_extract_data_links <- function(html) {
  if (is.null(html) || !nzchar(html)) return(character(0))

  links <- character(0)

  # --- Figshare article DOIs ---
  # Pattern: 10.6084/m9.figshare.XXXXXXXX (possibly .vN suffix)
  fig_art <- regmatches(html, gregexpr(
    "10\\.6084/m9\\.figshare\\.[0-9]+(\\.[0-9]+)*",
    html, perl = TRUE
  ))[[1]]
  links <- c(links, fig_art)

  # --- Figshare collection DOIs ---
  # Pattern: 10.6084/m9.figshare.c.XXXXXXXX
  fig_col <- regmatches(html, gregexpr(
    "10\\.6084/m9\\.figshare\\.c\\.[0-9]+",
    html, perl = TRUE
  ))[[1]]
  links <- c(links, fig_col)

  # --- Zenodo DOIs ---
  # Pattern: 10.5281/zenodo.XXXXXXXX
  zen <- regmatches(html, gregexpr(
    "10\\.5281/zenodo\\.[0-9]+",
    html, perl = TRUE
  ))[[1]]
  links <- c(links, zen)

  # --- Dryad DOIs ---
  # Pattern: 10.5061/dryad.[a-z0-9]+
  dryad <- regmatches(html, gregexpr(
    "10\\.5061/dryad\\.[a-zA-Z0-9]+",
    html, perl = TRUE
  ))[[1]]
  links <- c(links, dryad)

  # --- GitHub repos ---
  # Pattern: github.com/owner/repo (from href attributes or text)
  gh <- regmatches(html, gregexpr(
    "https?://github\\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+",
    html, perl = TRUE
  ))[[1]]
  # Filter out github.com/nature or similar non-data repos
  gh <- gh[!grepl("github\\.com/(nature|springer|NPG)", gh, ignore.case = TRUE)]
  links <- c(links, gh)

  # --- OSF ---
  # Pattern: osf.io/XXXXX
  osf <- regmatches(html, gregexpr(
    "https?://osf\\.io/[a-zA-Z0-9]+",
    html, perl = TRUE
  ))[[1]]
  links <- c(links, osf)

  # --- Pangaea ---
  # Pattern: doi.pangaea.de or 10.1594/PANGAEA
  pangaea <- regmatches(html, gregexpr(
    "10\\.1594/PANGAEA\\.[0-9]+",
    html, perl = TRUE
  ))[[1]]
  links <- c(links, pangaea)

  unique(trimws(links[nzchar(links)]))
}


# Scrape a single Scientific Data paper from Nature.com and return data links.
# Input: DOI string (e.g. "10.1038/sdata.2016.2")
# Output: list with $doi, $url, $links (char vector), $error
nature_scrape_paper <- function(doi) {
  doi_clean <- trimws(as.character(doi))

  html <- nature_fetch_landing_page(doi_clean)

  if (is.null(html)) {
    return(list(doi = doi_clean, url = NA_character_, links = character(0),
                error = "Failed to fetch HTML"))
  }

  links <- nature_extract_data_links(html)

  doi_suffix <- sub("^10\\.1038/", "", doi_clean, perl = TRUE)
  url <- paste0("https://www.nature.com/articles/", doi_suffix)

  list(
    doi   = doi_clean,
    url   = url,
    links = links,
    error = if (length(links) == 0L) "No data links found in HTML" else NA_character_
  )
}


# Scrape a batch of DOIs, returning a data.frame of results.
# Input: dois — character vector of DOIs
# Output: data.frame with columns: doi, nature_url, data_links, scrape_status
nature_scrape_batch <- function(dois, sleep_sec = 2, verbose = TRUE) {
  results <- lapply(seq_along(dois), function(i) {
    doi <- dois[i]
    if (verbose) {
      message(sprintf("  [%d/%d] Scraping Nature.com for: %s", i, length(dois), doi))
    }

    result <- tryCatch(
      nature_scrape_paper(doi),
      error = function(e) {
        list(doi = doi, url = NA_character_, links = character(0),
             error = conditionMessage(e))
      }
    )

    out <- data.frame(
      doi          = result$doi,
      nature_url   = if (is.na(result$url)) NA_character_ else result$url,
      data_links   = if (length(result$links)) paste(result$links, collapse = ", ") else NA_character_,
      scrape_status = if (!is.na(result$error)) paste("FAIL:", result$error) else
                      sprintf("OK:%d_links", length(result$links)),
      stringsAsFactors = FALSE
    )

    if (i < length(dois)) Sys.sleep(sleep_sec)
    out
  })

  do.call(rbind, results)
}
