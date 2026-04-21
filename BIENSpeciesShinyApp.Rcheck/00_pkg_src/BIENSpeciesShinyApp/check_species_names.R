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
  cat("Unique scrubbed_species_binomial values:\n")
  unique_names <- unique(occ$scrubbed_species_binomial)
  print(unique_names)
  
  cat("\nUsing first name for SQL query:", unique_names[1], "\n")
  
  # Now try SQL query with the exact name from BIEN
  sql_name <- unique_names[1]
  count_query <- paste(
    "SELECT COUNT(*) as total FROM view_full_occurrence_individual",
    "WHERE scrubbed_species_binomial = '", sql_name, "';"
  )
  
  cat("SQL query:\n", count_query, "\n\n")
  
  result <- tryCatch(
    BIEN:::.BIEN_sql(count_query, fetch.query = FALSE),
    error = function(e) {
      cat("Error:", conditionMessage(e), "\n")
      NULL
    }
  )
  
  if (is.data.frame(result)) {
    cat("SQL result count:", result$total[1], "\n")
  }
}
