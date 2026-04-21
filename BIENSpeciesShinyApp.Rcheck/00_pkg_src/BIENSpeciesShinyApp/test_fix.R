suppressWarnings(library(BIEN))

# Custom function with NULL handling
natives_check_with_null_fallback <- function(natives_only = TRUE) {
  if (isTRUE(natives_only)) {
    list(query = "AND (native.status = 'native' OR native.status IS NULL)")
  } else {
    list(query = "")
  }
}

# Test the fix
test_species <- c("Betula papyrifera", "Populus tremuloides")

for (sp in test_species) {
  cat("\n====", sp, "====\n")
  
  # Test with OLD way (BIEN's natives_check - should return 0)
  cat("OLD WAY (BIEN internal):\n")
  natives_old <- BIEN:::.natives_check(TRUE)
  cat("WHERE clause:", natives_old$query, "\n")
  
  # Manual count with the old logic
  old_query <- paste(
    "SELECT COUNT(*) as total FROM view_full_occurrence_individual",
    "WHERE scrubbed_species_binomial = '", sp, "'",
    natives_old$query,
    "LIMIT 1;"
  )
  old_result <- BIEN:::.BIEN_sql(old_query, fetch.query = FALSE)
  if (is.data.frame(old_result)) {
    cat("Count with old logic:", old_result$total[1], "\n")
  }
  
  # Test with NEW way (our custom version - should return many)
  cat("NEW WAY (null-safe):\n")
  natives_new <- natives_check_with_null_fallback(TRUE)
  cat("WHERE clause:", natives_new$query, "\n")
  
  # Manual count with the new logic
  new_query <- paste(
    "SELECT COUNT(*) as total FROM view_full_occurrence_individual",
    "WHERE scrubbed_species_binomial = '", sp, "'",
    natives_new$query,
    "LIMIT 1;"
  )
  new_result <- BIEN:::.BIEN_sql(new_query, fetch.query = FALSE)
  if (is.data.frame(new_result)) {
    cat("Count with new logic:", new_result$total[1], "\n")
  }
}
