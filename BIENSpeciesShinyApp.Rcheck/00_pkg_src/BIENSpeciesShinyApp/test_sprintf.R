suppressPackageStartupMessages(library(BIEN))

cat("Testing direct SQL query with Betula papyrifera...\n\n")
occ <- BIEN_occurrence_species(species = "Betula papyrifera", cultivated = TRUE, natives.only = FALSE, only.geovalid = FALSE)
trimmed_name <- trimws(unique(occ$scrubbed_species_binomial)[1])

# Create SQL without any paste confusion
sql_query <- sprintf(
  "SELECT COUNT(*) as total FROM view_full_occurrence_individual WHERE scrubbed_species_binomial = '%s';",
  trimmed_name
)

cat("SQL Query:\n", sql_query, "\n\n")

result <- BIEN:::.BIEN_sql(sql_query, fetch.query = FALSE)
cat("Result count:", result$total[1], "\n\n")

# Now test with native filter
sql_with_native <- sprintf(
  "SELECT COUNT(*) as total FROM view_full_occurrence_individual WHERE scrubbed_species_binomial = '%s' AND (is_introduced = 0 OR is_introduced IS NULL);",
  trimmed_name
)

cat("With native filter:\n", sql_with_native, "\n\n")
result_native <- BIEN:::.BIEN_sql(sql_with_native, fetch.query = FALSE)
cat("With native filter count:", result_native$total[1], "\n\n")

# Also try Populus
trimmed_name2 <- "Populus tremuloides"
sql_query2 <- sprintf(
  "SELECT COUNT(*) as total FROM view_full_occurrence_individual WHERE scrubbed_species_binomial = '%s';",
  trimmed_name2
)
cat("Testing Populus tremuloides...\n")
cat("SQL Query:\n", sql_query2, "\n")
result2 <- BIEN:::.BIEN_sql(sql_query2, fetch.query = FALSE)
cat("Result count:", result2$total[1], "\n")
