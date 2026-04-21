suppressWarnings(library(BIEN))

# Load the custom function from app.R
source('/Users/brianjenquist/VSCode/BIEN-SpeciesShinyApp/app.R', local = TRUE)

# Test species
test_species <- c("Betula papyrifera", "Populus tremuloides")

cat("Testing the fix with the new natives_check_with_null_fallback() function\n\n")

for (sp in test_species) {
  cat("===", sp, "===\n")
  
  # Call query_occurrence_randomized directly with the new logic
  result <- query_occurrence_randomized(
    species_name = sp,
    cultivated = FALSE,
    natives_only = TRUE,  # Using native-only filter
    only_geovalid = TRUE,
    limit = 100,
    record_limit = 100,
    randomize_order = FALSE
  )
  
  if (is.data.frame(result) && nrow(result) > 0) {
    cat("✓ SUCCESS: Got", nrow(result), "records\n")
    cat("  Datasources:", paste(unique(result$datasource), collapse = ", "), "\n")
  } else if (inherits(result, "error")) {
    cat("✗ ERROR:", conditionMessage(result), "\n")
  } else {
    cat("✗ No records returned\n")
  }
  cat("\n")
}
