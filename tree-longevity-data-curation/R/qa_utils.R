# qa_utils.R
# QA helpers: coordinate validation, unit checks, Darwin Core audits.
# Applied after download; results logged to logs/qa_log.csv.

QA_LOG_PATH <- here::here("logs", "qa_log.csv")

#' Append a QA result row to qa_log.csv.
log_qa <- function(dataset_id, dataset_name, check_name,
                   status, n_flagged = NA, notes = "") {
  row <- data.frame(
    dataset_id   = dataset_id,
    dataset_name = dataset_name,
    check_name   = check_name,
    status       = status,        # PASS / WARN / FAIL / SKIP
    n_flagged    = n_flagged,
    qa_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    notes        = notes,
    stringsAsFactors = FALSE
  )
  if (!file.exists(QA_LOG_PATH)) {
    write.csv(row, QA_LOG_PATH, row.names = FALSE)
  } else {
    existing <- read.csv(QA_LOG_PATH, stringsAsFactors = FALSE)
    write.csv(rbind(existing, row), QA_LOG_PATH, row.names = FALSE)
  }
  invisible(row)
}

#' Validate decimal latitude/longitude columns in a data.frame.
check_coordinates <- function(df, lat_col = "decimalLatitude",
                              lon_col = "decimalLongitude",
                              dataset_id, dataset_name) {
  if (!all(c(lat_col, lon_col) %in% names(df))) {
    log_qa(dataset_id, dataset_name, "coordinate_check",
           "SKIP", notes = paste("Columns not found:", lat_col, lon_col))
    return(invisible(NULL))
  }
  lat <- df[[lat_col]]
  lon <- df[[lon_col]]
  flags <- list(
    lat_range   = sum(!is.na(lat) & (lat < -90  | lat > 90),  na.rm = TRUE),
    lon_range   = sum(!is.na(lon) & (lon < -180 | lon > 180), na.rm = TRUE),
    zero_zero   = sum(!is.na(lat) & !is.na(lon) & lat == 0 & lon == 0,
                      na.rm = TRUE),
    lat_missing = sum(is.na(lat)),
    lon_missing = sum(is.na(lon))
  )
  total_flagged <- sum(unlist(flags))
  status <- if (total_flagged == 0) "PASS" else "WARN"
  log_qa(dataset_id, dataset_name, "coordinate_check",
         status, total_flagged,
         paste(names(flags), unlist(flags), sep = "=", collapse = "; "))
  invisible(flags)
}

#' Check that wood density values are within plausible range (0.05–1.5 g/cm³).
check_wood_density <- function(values, dataset_id, dataset_name,
                               unit = "g/cm3") {
  lo <- 0.05; hi <- 1.50
  n_out <- sum(!is.na(values) & (values < lo | values > hi))
  status <- if (n_out == 0) "PASS" else "WARN"
  log_qa(dataset_id, dataset_name, "wood_density_range_check",
         status, n_out,
         paste0("unit=", unit, " range_checked=[", lo, ",", hi, "]"))
  invisible(n_out)
}

#' Check P50 sign convention: negative MPa expected.
#' Warns if majority of values are positive (possible sign flip).
check_p50_sign <- function(values, dataset_id, dataset_name) {
  n_pos <- sum(values > 0, na.rm = TRUE)
  n_neg <- sum(values < 0, na.rm = TRUE)
  status <- if (n_neg >= n_pos) "PASS" else "WARN"
  log_qa(dataset_id, dataset_name, "p50_sign_convention",
         status, n_pos,
         paste0("n_positive=", n_pos, " n_negative=", n_neg,
                " — expected negative MPa; WARN if majority positive"))
  invisible(list(n_pos = n_pos, n_neg = n_neg))
}

#' Check that required Darwin Core fields are present in a data.frame.
check_dwc_fields <- function(df, dataset_id, dataset_name,
                             required = c("species", "decimalLatitude",
                                          "decimalLongitude",
                                          "eventDate", "basisOfRecord")) {
  missing_cols <- setdiff(required, names(df))
  status <- if (length(missing_cols) == 0) "PASS" else "WARN"
  log_qa(dataset_id, dataset_name, "dwc_field_check",
         status, length(missing_cols),
         paste("missing:", paste(missing_cols, collapse = ", ")))
  invisible(missing_cols)
}
