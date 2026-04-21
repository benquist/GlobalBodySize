suppressPackageStartupMessages(library(BIEN))

# Check if the species names themselves are in BIEN
test_species <- c("Betula papyrifera", "Populus tremuloides")

for (sp in test_species) {
  cat("\n===", sp, "===\n")
  
  # Check total count without any native filters - just species
  count_query <- paste(
    "SELECT COUNT(*) as total FROM view_full_occurrence_individual",
    "WHERE scrubbed_species_binomial = '", sp, "';"
  )
  
  result <- tryCatch(
    BIEN:::.BIEN_sql(count_query, fetch.query = FALSE),
    error = function(e) NULL
  )
  
  if (is.data.frame(result) && nrow(result) > 0) {
    total <- as.numeric(result$total[1])
    cat("Total records (no filters):", total, "\n")
    
    # Now test with is_introduced = 0 only (BIEN default)
    count_query2 <- paste(
      "SELECT COUNT(*) as total FROM view_full_occurrence_individual",
      "WHERE scrubbed_species_binomial = '", sp, "'",
      "AND is_introduced = 0;"
    )
    result2 <- BIEN:::.BIEN_sql(count_query2, fetch.query = FALSE)
    total2 <- as.numeric(result2$total[1])
    cat("With is_introduced = 0:", total2, "\n")
    
    # Test with NULL only
    count_query3 <- paste(
      "SELECT COUNT(*) as total FROM view_full_occurrence_individual",
      "WHERE scrubbed_species_binomial = '", sp, "'",
      "AND is_introduced IS NULL;"
    )
    result3 <- BIEN:::.BIEN_sql(count_query3, fetch.query = FALSE)
    total3 <- as.numeric(result3$total[1])
    cat("With is_introduced IS NULL:", total3, "\n")
    
    # Test with combined (our fix)
    count_query4 <- paste(
      "SELECT COUNT(*) as total FROM view_full_occurrence_individual",
      "WHERE scrubbed_species_binomial = '", sp, "'",
      "AND (is_introduced = 0 OR is_introduced IS NULL);"
    )
    result4 <- BIEN:::.BIEN_sql(count_query4, fetch.query = FALSE)
    total4 <- as.numeric(result4$total[1])
    cat("With (is_introduced = 0 OR is_introduced IS NULL):", total4, "\n")
    
  } else {
    cat("No records found for this species at all\n")
  }
}
