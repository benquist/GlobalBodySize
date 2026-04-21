suppressWarnings(library(BIEN))

# Check what columns are available
cat("Checking available columns by querying the first record...\n")

query <- "SELECT * FROM view_full_occurrence_individual LIMIT 1;"
result <- tryCatch(
  BIEN:::.BIEN_sql(query, fetch.query = FALSE),
  error = function(e) {
    cat("Error:", conditionMessage(e), "\n")
    NULL
  }
)

if (is.data.frame(result)) {
  cat("Columns available:\n")
  cat(paste(colnames(result), collapse = ", "), "\n\n")
  
  # Check if native.status or is_introduced columns exist
  has_native_status <- "native.status" %in% tolower(colnames(result))
  has_is_introduced <- "is_introduced" %in% tolower(colnames(result))
  
  cat("Has native.status column:", has_native_status, "\n")
  cat("Has is_introduced column:", has_is_introduced, "\n")
  
  if (has_is_introduced) {
    cat("\nValues of is_introduced:\n")
    print(table(result$is_introduced, useNA = "always"))
  }
  
  if (has_native_status) {
    cat("\nValues of native.status:\n")
    print(table(result$native.status, useNA = "always"))
  }
}
