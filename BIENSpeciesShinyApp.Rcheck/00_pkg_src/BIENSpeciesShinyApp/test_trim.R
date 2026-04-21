suppressPackageStartupMessages(library(BIEN))

# Use BIEN_occurrence_species which definitely works
cat("Getting records via BIEN_occurrence_species for Betula papyrifera...\n")
occ <- BIEN_occurrence_species(
  species = "Betula papyrifera",
  cultivated = TRUE,
  natives.only = FALSE,
  only.geovalid = FALSE
)

if (is.data.frame(occ) && nrow(occ) > 0) {
  cat("Got", nrow(occ), "records\n")
  
  # Get the name and TRIM it
  raw_name <- unique(occ$scrubbed_species_binomial)[1]
  trimmed_name <- trimws(raw_name)
  
  cat("Raw name: '", raw_name, "'\n", sep="")
  cat("Trimmed name: '", trimmed_name, "'\n", sep="")
  
  # Try SQL query WITH trimming
  count_query <- paste(
    "SELECT COUNT(*) as total FROM view_full_occurrence_individual",
    "WHERE scrubbed_species_binomial = '", trimmed_name, "';"
  )
  
  cat("\nSQL query:\n", count_query, "\n")
  
  result <- BIEN:::.BIEN_sql(count_query, fetch.query = FALSE)
  cat("SQL result count:", result$total[1], "\n")
  
  # Test with filters
  cat("\n--- Testing with native filter ---\n")
  
  count_with_native <- paste(
    "SELECT COUNT(*) as total FROM view_full_occurrence_individual",
    "WHERE scrubbed_species_binomial = '", trimmed_name, "'",
    "AND (is_introduced = 0 OR is_introduced IS NULL);"
  )
  result_native <- BIEN:::.BIEN_sql(count_with_native, fetch.query = FALSE)
  cat("With NULL-safe native filter:", result_native$total[1], "\n")
}
