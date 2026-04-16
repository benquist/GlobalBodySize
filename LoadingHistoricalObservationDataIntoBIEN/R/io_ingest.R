read_historical_csv <- function(path) {
  if (is.null(path) || !nzchar(path) || !file.exists(path)) {
    stop("Input file does not exist.")
  }

  df <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  # Remove blank rows: all columns are NA or empty string
  is_blank_row <- apply(df, 1, function(row) all(is.na(row) | trimws(as.character(row)) == ""))
  df <- df[!is_blank_row, , drop = FALSE]
  if (!is.data.frame(df) || nrow(df) == 0) {
    stop("CSV was loaded but contains no rows after removing blanks.")
  }

  df$.source_row <- seq_len(nrow(df))
  df
}

required_dwc_terms <- function() {
  c(
    "occurrenceID",
    "basisOfRecord",
    "scientificName",
    "eventDate",
    "locality",
    "occurrenceStatus"
  )
}
