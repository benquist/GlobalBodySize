suppressWarnings(library(BIEN))

# Define the custom function
sql_quote_literal <- function(x) {
  x <- as.character(x)
  x <- gsub("'", "''", x, fixed = TRUE)
  paste0("'", x, "'")
}

natives_check_with_null_fallback <- function(natives_only = TRUE) {
  if (isTRUE(natives_only)) {
    list(query = "AND (native_status = 'native' OR native_status IS NULL)")
  } else {
    list(query = "")
  }
}

# Test species
test_species <- c("Betula papyrifera", "Populus tremuloides")

cat("Testing the NULL-safe native status filter\n\n")

for (sp in test_species) {
  cat("===", sp, "===\n")
  
  # Build a simple count query using the new logic
  natives_filter <- natives_check_with_null_fallback(natives_only = TRUE)
  
  count_query <- paste(
    "SELECT COUNT(*) as total FROM view_full_occurrence_individual",
    "WHERE scrubbed_species_binomial = '", sp, "'",
    natives_filter$query,
    ";"
  )
  
  cat("Query filter clause:", natives_filter$query, "\n")
  
  result <- tryCatch(
    BIEN:::.BIEN_sql(count_query, fetch.query = FALSE),
    error = function(e) {
      cat("SQL Error:", conditionMessage(e), "\n")
      NULL
    }
  )
  
  if (is.data.frame(result) && nrow(result) > 0) {
    total <- as.numeric(result$total[1])
    cat("✓ With NULL-safe filter: ", total, " records\n")
  } else {
    cat("✗ Query failed\n")
  }
}

cat("\n\nThis fix allows Betula papyrifera and Populus tremuloides (which have NO native.status values)\n")
cat("to be included in queries when users request 'natives only' mode.\n")
