suppressWarnings(library(BIEN))

species_list <- c("Betula papyrifera", "Populus tremuloides")

for (sp in species_list) {
  cat("\n====", sp, "====\n")
  
  # Query with ALL records including native.status
  occ <- BIEN::BIEN_occurrence_species(
    species = sp,
    cultivated = TRUE,
    natives.only = FALSE,
    only.geovalid = FALSE
  )
  
  if (is.data.frame(occ) && nrow(occ) > 0) {
    cat("Total records:", nrow(occ), "\n")
    cat("Unique native.status values:\n")
    status_summary <- table(occ$native.status, useNA = "always")
    print(status_summary)
    cat("\nPercent with native.status NULL/NA:", round(100 * sum(is.na(occ$native.status)) / nrow(occ), 2), "%\n")
    
    # Check datasource distribution
    cat("\nDatasources in this dataset:\n")
    ds_summary <- table(occ$datasource, useNA = "always")
    print(head(sort(ds_summary, decreasing = TRUE), 10))
  }
}
