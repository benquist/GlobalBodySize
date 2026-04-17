suppressPackageStartupMessages({
  required_packages <- c("shiny", "BIEN", "dplyr", "stringr", "leaflet", "DT")
  missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing_packages) > 0) {
    stop(
      paste0(
        "Missing required packages: ",
        paste(missing_packages, collapse = ", "),
        ". Install before launching."
      )
    )
  }

  library(shiny)
  library(BIEN)
  library(dplyr)
  library(stringr)
  library(leaflet)
  library(DT)
})

safe_bien_call <- function(expr, timeout_sec = 120) {
  on.exit(setTimeLimit(cpu = Inf, elapsed = Inf, transient = FALSE), add = TRUE)
  setTimeLimit(elapsed = timeout_sec, transient = TRUE)
  tryCatch(expr, error = function(e) e)
}

first_existing_col <- function(df, candidates) {
  if (!is.data.frame(df)) return(NULL)
  nm <- names(df)
  idx <- match(tolower(candidates), tolower(nm))
  idx <- idx[!is.na(idx)]
  if (length(idx) == 0) return(NULL)
  nm[idx[1]]
}

normalize_species_name <- function(x) {
  x <- str_squish(as.character(x))
  x <- x[nzchar(x)]
  if (length(x) == 0) return(character(0))

  vapply(x, function(one) {
    parts <- strsplit(one, "\\s+")[[1]]
    if (length(parts) >= 1) {
      genus <- parts[1]
      parts[1] <- paste0(stringr::str_to_upper(substr(genus, 1, 1)), stringr::str_to_lower(substr(genus, 2, nchar(genus))))
    }
    if (length(parts) >= 2) {
      parts[2] <- stringr::str_to_lower(parts[2])
    }
    paste(parts, collapse = " ")
  }, character(1))
}

parse_species_input <- function(text_input) {
  if (is.null(text_input)) text_input <- ""
  from_text <- unlist(strsplit(text_input, "[\\n,;]+"), use.names = FALSE)
  unique(normalize_species_name(from_text))
}

query_trait_data <- function(species_vec, max_records = 5000, timeout_sec = 180) {
  out <- list()
  for (sp in species_vec) {
    dat <- safe_bien_call(
      BIEN_trait_species(
        species = sp,
        all.taxonomy = TRUE,
        source.citation = TRUE,
        limit = as.integer(max_records),
        record_limit = min(500L, as.integer(max_records)),
        fetch.query = FALSE
      ),
      timeout_sec = timeout_sec
    )

    if (is.data.frame(dat) && nrow(dat) > 0) {
      dat$input_species <- sp
      out[[length(out) + 1]] <- dat
    }
  }

  if (length(out) == 0) return(data.frame())
  dplyr::bind_rows(out)
}
