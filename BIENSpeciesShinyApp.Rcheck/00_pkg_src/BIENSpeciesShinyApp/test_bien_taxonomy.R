suppressWarnings(library(BIEN))

# Let's check if these species exist in BIEN at all
test_species <- c("Betula papyrifera", "Populus tremuloides")

for (sp in test_species) {
  cat("\n========================================\n")
  cat("Searching BIEN taxonomy for:", sp, "\n")
  cat("========================================\n")
  
  # Try BIEN_taxonomy_species directly
  tax_result <- tryCatch(
    BIEN::BIEN_taxonomy_species(sp),
    error = function(e) paste("Error:", conditionMessage(e))
  )
  
  if (is.character(tax_result)) {
    cat("Taxonomy lookup failed:", tax_result, "\n")
  } else if (is.data.frame(tax_result)) {
    cat("Taxonomy match found:", nrow(tax_result), "rows\n")
    if (nrow(tax_result) > 0) {
      print(head(tax_result[, c("scrubbed_species_binomial", "species_name", "genus", "native.status")], 10))
    }
  }
  
  # Try direct BIEN_occurrence_species which may handle taxonomy better
  cat("\n--- Trying BIEN_occurrence_species ---\n")
  occ_result <- tryCatch(
    BIEN::BIEN_occurrence_species(
      species = sp,
      cultivated = TRUE,
      natives.only = FALSE,
      only.geovalid = FALSE
    ),
    error = function(e) paste("Error:", conditionMessage(e))
  )
  
  if (is.character(occ_result)) {
    cat("Occurrence query failed:", occ_result, "\n")
  } else if (is.data.frame(occ_result)) {
    cat("Occurrence records found:", nrow(occ_result), "\n")
    if (nrow(occ_result) > 0) {
      cat("Scrubbed species names in result:", paste(unique(occ_result$scrubbed_species_binomial), collapse = ", "), "\n")
      cat("Datasources:", paste(unique(occ_result$datasource), collapse = ", "), "\n")
      cat("Sample observation_types:", paste(unique(na.omit(occ_result$observation_type))[1:3], collapse = ", "), "\n")
      cat("Native status in result:", paste(unique(na.omit(occ_result$native.status)), collapse = ", "), "\n")
    }
  }
}

# Try getting info about the genus too
cat("\n\n========================================\n")
cat("Checking genus-level availability\n")
cat("========================================\n")

genera <- c("Betula", "Populus")
for (gen in genera) {
  cat("\n--- Genus:", gen, "---\n")
  gen_result <- tryCatch(
    BIEN::BIEN_taxonomy_genus(gen),
    error = function(e) paste("Error:", conditionMessage(e))
  )
  
  if (!is.character(gen_result) && is.data.frame(gen_result)) {
    cat("Total species in genus:", nrow(gen_result), "\n")
    if (nrow(gen_result) > 0) {
      species_in_bien <- unique(gen_result$scrubbed_species_binomial)
      cat("Species available:", paste(head(species_in_bien, 10), collapse = ", "), "\n")
      if (gen == "Betula") {
        match_papyrifera <- species_in_bien[grepl("papyrifera", species_in_bien, ignore.case = TRUE)]
        cat("Matches for 'papyrifera':", paste(match_papyrifera, collapse = ", "), "\n")
      }
      if (gen == "Populus") {
        match_tremuloides <- species_in_bien[grepl("tremuloides", species_in_bien, ignore.case = TRUE)]
        cat("Matches for 'tremuloides':", paste(match_tremuloides, collapse = ", "), "\n")
      }
    }
  }
}
