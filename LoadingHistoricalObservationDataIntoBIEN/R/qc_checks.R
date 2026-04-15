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
    parse_ok <- suppressWarnings(!is.na(as.Date(raw_date)))
    non_blank <- !(is.na(raw_date) | trimws(raw_date) == "")
    bad <- non_blank & !parse_ok
    if (any(bad)) {
      add_issue("eventDate not ISO-parseable", "WARN", sum(bad), "Use YYYY-MM-DD or a consistent parseable date format.")
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
