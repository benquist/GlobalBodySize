suppressWarnings(library(BIEN))

# Define the corrected function
natives_check_with_null_fallback <- function(natives_only = TRUE) {
  if (isTRUE(natives_only)) {
    list(query = "AND (is_introduced=0 OR is_introduced IS NULL) ")
  } else {
    list(query = "")
  }
}

# Test species
test_species <- c("Betula papyrifera", "Populus tremuloides")

cat("Testing the CORRECTED NULL-safe is_introduced filter\n\n")

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
    cat("✓ Records with NULL-safe is_introduced filter:", total, "\n")
  } else {
    cat("✗ Query failed or no results\n")
  }
  cat("\n")
}

cat("Fix rationale:\n")
cat("- Betula papyrifera and Populus tremuloides have is_introduced = NULL for all records\n")
cat("- BIEN's default :::natives_check() filters to is_introduced=0 only\n")
cat("- Our patch adds OR is_introduced IS NULL to include unclassified records\n")
