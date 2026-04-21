suppressWarnings(library(BIEN))

# Test configuration
test_species <- c("Betula papyrifera", "Populus tremuloides")

test_query <- function(sp, cultivated = FALSE, natives_only = TRUE, geovalid = TRUE, plot_only = FALSE) {
  cat("\n---", sp, "---\n")
  cat("Filters: cultivated=", cultivated, " | natives_only=", natives_only, " | geovalid=", geovalid, " | plot_only=", plot_only, "\n")
  
  # Total count query
  cultivated_ <- BIEN:::.cultivated_check(cultivated)
  natives_ <- BIEN:::.natives_check(natives_only)
  geovalid_ <- BIEN:::.geovalid_check(geovalid)
  observation_ <- BIEN:::.observation_check(TRUE)
  newworld_ <- BIEN:::.newworld_check(NULL)
  
  base_query <- paste(
    "SELECT COUNT(*) as total",
    "FROM view_full_occurrence_individual",
    "WHERE scrubbed_species_binomial = '", sp, "'",
    cultivated_$query, newworld_$query, natives_$query, observation_$query, geovalid_$query,
    "AND higher_plant_group NOT IN ('Algae','Bacteria','Fungi')",
    "AND (georef_protocol is NULL OR georef_protocol<>'county centroid')",
    "AND (is_centroid IS NULL OR is_centroid=0)",
    "AND scrubbed_species_binomial IS NOT NULL;"
  )
  
  count_result <- tryCatch(
    BIEN:::.BIEN_sql(base_query, fetch.query = FALSE),
    error = function(e) paste("ERROR:", conditionMessage(e))
  )
  
  if (is.character(count_result)) {
    cat("Count query error:", count_result, "\n")
  } else if (is.data.frame(count_result)) {
    total <- as.numeric(count_result$total[1])
    cat("Total records:", total, "\n")
    
    # If total > 0, try to get some sample records
    if (total > 0) {
      occ_result <- tryCatch({
        BIEN:::.BIEN_sql(
          paste(
            "SELECT scrubbed_species_binomial, observation_type, datasource, dataset, latitude, longitude",
            "FROM view_full_occurrence_individual",
            "WHERE scrubbed_species_binomial = '", sp, "'",
            cultivated_$query, newworld_$query, natives_$query, observation_$query, geovalid_$query,
            "AND higher_plant_group NOT IN ('Algae','Bacteria','Fungi')",
            "AND (georef_protocol is NULL OR georef_protocol<>'county centroid')",
            "AND (is_centroid IS NULL OR is_centroid=0)",
            "AND scrubbed_species_binomial IS NOT NULL",
            "LIMIT 5;"),
          fetch.query = FALSE,
          record_limit = 5
        )
      }, error = function(e) paste("ERROR:", conditionMessage(e)))
      
      if (is.character(occ_result)) {
        cat("Sample query error:", occ_result, "\n")
      } else if (is.data.frame(occ_result)) {
        cat("Sample records:", nrow(occ_result), "\n")
        if (nrow(occ_result) > 0) {
          cat("  Datasources:", paste(unique(occ_result$datasource), collapse = ", "), "\n")
          cat("  Observation types:", paste(unique(occ_result$observation_type), collapse = ", "), "\n")
        }
      }
    }
  }
}

# Test each species with different filter combinations
for (sp in test_species) {
  cat("========================================\n")
  cat("SPECIES:", sp, "\n")
  cat("========================================\n")
  
  # Conservative (default app settings)
  test_query(sp, cultivated = FALSE, natives_only = TRUE, geovalid = TRUE, plot_only = FALSE)
  
  # Relax natives-only
  test_query(sp, cultivated = FALSE, natives_only = FALSE, geovalid = TRUE, plot_only = FALSE)
  
  # Relax all
  test_query(sp, cultivated = TRUE, natives_only = FALSE, geovalid = FALSE, plot_only = FALSE)
}
