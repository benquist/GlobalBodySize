suppressWarnings(library(BIEN))

# Simple test to see what we have for these species
test_species <- c("Betula papyrifera", "Populus tremuloides")

for (sp in test_species) {
  cat("\n========================================\n")
  cat("Species:", sp, "\n")
  cat("========================================\n")
  
  # Try BIEN_taxonomy_species
  tax <- tryCatch(
    BIEN::BIEN_taxonomy_species(sp),
    error = function(e) NULL
  )
  
  if (is.data.frame(tax) && nrow(tax) > 0) {
    cat("Taxonomy record count:", nrow(tax), "\n")
    cat("Column names:", paste(colnames(tax), collapse = ", "), "\n")
    if ("scrubbed_species_binomial" %in% colnames(tax)) {
      cat("Scrubbed binomials:", paste(unique(tax$scrubbed_species_binomial), collapse = " | "), "\n")
    }
    if ("native.status" %in% colnames(tax)) {
      cat("Native statuses:", paste(unique(na.omit(tax$native.status)), collapse = " | "), "\n")
    }
  } else {
    cat("No taxonomy record found\n")
  }
  
  # Try BIEN_occurrence_species
  cat("\nTrying BIEN_occurrence_species with liberal filters...\n")
  occ <- tryCatch(
    BIEN::BIEN_occurrence_species(
      species = sp,
      cultivated = TRUE,
      natives.only = FALSE,
      only.geovalid = FALSE
    ),
    error = function(e) NULL
  )
  
  if (is.data.frame(occ) && nrow(occ) > 0) {
    cat("Occurrence records found:", nrow(occ), "\n")
    cat("Scrubbed species:", paste(unique(occ$scrubbed_species_binomial), collapse = " | "), "\n")
    cat("Native status values:", paste(unique(na.omit(occ$native.status)), collapse = " | "), "\n")
    cat("Datasources:", paste(unique(occ$datasource), collapse = " | "), "\n")
  } else {
    cat("No occurrence records found\n")
  }
}

# Check genus level directly
cat("\n\n========================================\n")
cat("Checking Betula genus directly\n")
cat("========================================\n")

betula_tax <- tryCatch(
  BIEN::BIEN_taxonomy_genus("Betula"),
  error = function(e) NULL
)

if (is.data.frame(betula_tax) && nrow(betula_tax) > 0) {
  cat("Betula species in BIEN:", nrow(betula_tax), "\n")
  species_list <- unique(betula_tax$scrubbed_species_binomial)
  cat("Species:", paste(species_list, collapse=", "), "\n")
}

cat("\n\n========================================\n")
cat("Checking Populus genus directly\n")
cat("========================================\n")

populus_tax <- tryCatch(
  BIEN::BIEN_taxonomy_genus("Populus"),
  error = function(e) NULL
)

if (is.data.frame(populus_tax) && nrow(populus_tax) > 0) {
  cat("Populus species in BIEN:", nrow(populus_tax), "\n")
  species_list <- unique(populus_tax$scrubbed_species_binomial)
  cat("Species:", paste(species_list, collapse=", "), "\n")
}
