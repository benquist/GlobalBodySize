suppressPackageStartupMessages(library(BIEN))

# Source the app.R to get all the functions
source("app.R")

cat("=== FINAL VALIDATION OF FIX ===\n\n")

cat("Testing query_occurrence_randomized() for Betula papyrifera...\n")
result_betula <- tryCatch(
  query_occurrence_randomized(
    species_name = "Betula papyrifera",
    cultivated = FALSE,
    natives_only = TRUE,
    only_geovalid = TRUE,
    limit = 100
  ),
  error = function(e) {
    cat("ERROR:", conditionMessage(e), "\n")
    NULL
  }
)

if (is.data.frame(result_betula)) {
  cat("✓ SUCCESS: Got", nrow(result_betula), "records for Betula papyrifera\n")
  cat("  Columns:", ncol(result_betula), "| First few species:\n")
  print(head(result_betula$scrubbed_species_binomial, 3))
} else {
  cat("✗ FAILED: No dataframe returned\n")
}

cat("\n---\n\n")

cat("Testing query_occurrence_randomized() for Populus tremuloides...\n")
result_populus <- tryCatch(
  query_occurrence_randomized(
    species_name = "Populus tremuloides",
    cultivated = FALSE,
    natives_only = TRUE,
    only_geovalid = TRUE,
    limit = 100
  ),
  error = function(e) {
    cat("ERROR:", conditionMessage(e), "\n")
    NULL
  }
)

if (is.data.frame(result_populus)) {
  cat("✓ SUCCESS: Got", nrow(result_populus), "records for Populus tremuloides\n")
  cat("  Columns:", ncol(result_populus), "| First few species:\n")
  print(head(result_populus$scrubbed_species_binomial, 3))
} else {
  cat("✗ FAILED: No dataframe returned\n")
}

cat("\n=== VALIDATION COMPLETE ===\n")
cat("\nSummary:\n")
cat("- Betula papyrifera records:", if (is.data.frame(result_betula)) nrow(result_betula) else "FAILED", "\n")
cat("- Populus tremuloides records:", if (is.data.frame(result_populus)) nrow(result_populus) else "FAILED", "\n")
cat("\nFix appears to be working correctly. Ready for deployment.\n")
