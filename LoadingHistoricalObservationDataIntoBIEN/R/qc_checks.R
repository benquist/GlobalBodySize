run_dwc_qc <- function(dwc_df) {
  if (!is.data.frame(dwc_df)) {
    stop("dwc_df must be a data.frame")
  }

  rows <- list()

  add_issue <- function(issue, severity, count, detail) {
    rows[[length(rows) + 1]] <<- data.frame(
      issue = issue,
      severity = severity,
      affected_rows = as.integer(count),
      detail = detail,
      stringsAsFactors = FALSE
    )
  }

  if (!"scientificName" %in% names(dwc_df)) {
    add_issue("scientificName missing", "BLOCK", nrow(dwc_df), "Darwin Core mapping must include scientificName.")
  } else {
    bad <- is.na(dwc_df$scientificName) | trimws(as.character(dwc_df$scientificName)) == ""
    if (any(bad)) {
      add_issue("scientificName blank", "BLOCK", sum(bad), "Records with blank scientificName cannot be BIEN-ready.")
    }
  }

  if (!"eventDate" %in% names(dwc_df)) {
    add_issue("eventDate missing", "WARN", nrow(dwc_df), "Include eventDate where possible for temporal analyses.")
  } else {
    raw_date <- as.character(dwc_df$eventDate)
    parsed_dates <- suppressWarnings(as.Date(rep(NA_character_, length(raw_date))))
    for (i in seq_along(raw_date)) {
      parsed_dates[[i]] <- tryCatch(
        suppressWarnings(as.Date(raw_date[[i]])),
        error = function(e) as.Date(NA)
      )
    }
    parse_ok <- !is.na(parsed_dates)
    non_blank <- !(is.na(raw_date) | trimws(raw_date) == "")
    bad <- non_blank & !parse_ok
    if (any(bad)) {
      add_issue("eventDate not ISO-parseable", "WARN", sum(bad), "Use YYYY-MM-DD or a consistent parseable date format.")
    }

    plausible_low <- as.Date("1700-01-01")
    plausible_high <- Sys.Date() + 1
    implausible <- non_blank & parse_ok & (parsed_dates < plausible_low | parsed_dates > plausible_high)
    if (any(implausible)) {
      add_issue("eventDate outside plausible range", "WARN", sum(implausible), "Dates before 1700-01-01 or in the future should be reviewed.")
    }
  }

  if ("occurrenceID" %in% names(dwc_df)) {
    ids <- trimws(as.character(dwc_df$occurrenceID))
    non_blank <- !is.na(ids) & ids != ""
    id_tab <- table(ids[non_blank], useNA = "no")
    dup_values <- names(id_tab[id_tab > 1])
    duplicated_id <- non_blank & ids %in% dup_values
    if (any(duplicated_id)) {
      add_issue("duplicate occurrenceID", "BLOCK", sum(duplicated_id), "occurrenceID values should be unique per record.")
    }
  }

  if ("occurrenceStatus" %in% names(dwc_df)) {
    allowed <- c("present", "absent")
    vals <- tolower(trimws(as.character(dwc_df$occurrenceStatus)))
    bad <- !(vals %in% allowed) & vals != "" & !is.na(vals)
    if (any(bad)) {
      add_issue("occurrenceStatus outside controlled vocabulary", "WARN", sum(bad), "Expected values: present or absent.")
    }
  }

  if ("basisOfRecord" %in% names(dwc_df)) {
    allowed <- c("humanobservation", "machineobservation", "materialsample", "preservedspecimen", "fossilspecimen", "livingspecimen")
    vals <- tolower(trimws(as.character(dwc_df$basisOfRecord)))
    bad <- !(vals %in% allowed) & vals != "" & !is.na(vals)
    if (any(bad)) {
      add_issue("basisOfRecord outside controlled vocabulary", "WARN", sum(bad), "Use standard Darwin Core basisOfRecord values.")
    }
  }

  if (all(c("decimalLatitude", "decimalLongitude") %in% names(dwc_df))) {
    lat <- suppressWarnings(as.numeric(dwc_df$decimalLatitude))
    lon <- suppressWarnings(as.numeric(dwc_df$decimalLongitude))
    bad <- is.na(lat) | is.na(lon) | lat < -90 | lat > 90 | lon < -180 | lon > 180 | (lat == 0 & lon == 0)
    if (any(bad)) {
      add_issue("invalid or implausible coordinates", "WARN", sum(bad), "Check bounds and possible lat-long swaps or zero-zero points.")
    }

    likely_swapped <- !is.na(lat) & !is.na(lon) & abs(lat) > 90 & abs(lon) <= 90
    if (any(likely_swapped)) {
      add_issue("likely latitude/longitude swap", "WARN", sum(likely_swapped), "Latitude exceeds +/-90 while longitude is within +/-90.")
    }

    if ("country" %in% names(dwc_df)) {
      country <- tolower(trimws(as.character(dwc_df$country)))
      in_us <- country %in% c("united states", "united states of america", "usa", "u.s.a.")
      in_canada <- country %in% c("canada")
      in_mexico <- country %in% c("mexico")

      us_out <- in_us & !is.na(lat) & !is.na(lon) & (lat < 18 | lat > 72 | lon < -170 | lon > -65)
      ca_out <- in_canada & !is.na(lat) & !is.na(lon) & (lat < 41 | lat > 84 | lon < -142 | lon > -52)
      mx_out <- in_mexico & !is.na(lat) & !is.na(lon) & (lat < 14 | lat > 33 | lon < -119 | lon > -86)
      cc_bad <- us_out | ca_out | mx_out

      if (any(cc_bad)) {
        add_issue("country-coordinate mismatch (basic envelope)", "WARN", sum(cc_bad), "Coordinates fall outside expected country envelopes for USA/Canada/Mexico.")
      }
    }
  }

  if (length(rows) == 0) {
    return(data.frame(
      issue = "No QC issues detected",
      severity = "PASS",
      affected_rows = 0L,
      detail = "All current checks passed.",
      stringsAsFactors = FALSE
    ))
  }

  do.call(rbind, rows)
}

qc_has_blockers <- function(qc_df) {
  if (!is.data.frame(qc_df) || nrow(qc_df) == 0) {
    return(FALSE)
  }

  any(qc_df$severity == "BLOCK")
}

qc_severity_count <- function(qc_df, severity) {
  if (!is.data.frame(qc_df) || nrow(qc_df) == 0) {
    return(0L)
  }
  sum(qc_df$severity == severity)
}
