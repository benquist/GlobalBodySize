suppressWarnings(library(BIEN))

# Check the native_status column specifically for our species
cat("Checking native_status values for our species...\n\n")

species_list <- c("Betula papyrifera", "Populus tremuloides")

for (sp in species_list) {
  cat("===", sp, "===\n")
  
  # Query to see native_status distribution
  query <- paste(
    "SELECT COUNT(*) as total,",
    "SUM(CASE WHEN native_status = 'native' THEN 1 ELSE 0 END) as native_count,",
    "SUM(CASE WHEN native_status = 'introduced' THEN 1 ELSE 0 END) as introduced_count,",
    "SUM(CASE WHEN native_status IS NULL THEN 1 ELSE 0 END) as null_count,",
    "SUM(CASE WHEN native_status NOT IN ('native', 'introduced') AND native_status IS NOT NULL THEN 1 ELSE 0 END) as other_count",
    "FROM view_full_occurrence_individual",
    "WHERE scrubbed_species_binomial = '", sp, "';"
  )
  
  result <- tryCatch(
    BIEN:::.BIEN_sql(query, fetch.query = FALSE),
    error = function(e) {
      cat("Error:", conditionMessage(e), "\n")
      NULL
    }
  )
  
  if (is.data.frame(result) && nrow(result) > 0) {
    cat("Total records:", result$total[1], "\n")
    cat("Native:", result$native_count[1], "\n")
    cat("Introduced:", result$introduced_count[1], "\n")
    cat("NULL:", result$null_count[1], "\n")
    cat("Other:", result$other_count[1], "\n")
  }
  cat("\n")
}

# Also check what actual values exist in native_status column
cat("\n=== Sample native_status values ===\n")
query2 <- "SELECT DISTINCT native_status FROM view_full_occurrence_individual WHERE native_status IS NOT NULL LIMIT 20;"
result2 <- BIEN:::.BIEN_sql(query2, fetch.query = FALSE)
if (is.data.frame(result2)) {
  cat("Unique native_status values:\n")
  print(result2$native_status)
}
