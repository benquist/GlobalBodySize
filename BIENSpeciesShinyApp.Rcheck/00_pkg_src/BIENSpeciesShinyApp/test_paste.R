suppressPackageStartupMessages(library(BIEN))

# Minimal test
cat("Minimal test of species name extraction:\n\n")
occ <- BIEN_occurrence_species(species = "Betula papyrifera", cultivated = TRUE, natives.only = FALSE, only.geovalid = FALSE)

raw_name <- unique(occ$scrubbed_species_binomial)[1]
trimmed_name <- trimws(raw_name)

cat("nchar(raw_name):", nchar(raw_name), "\n")
cat("nchar(trimmed_name):", nchar(trimmed_name), "\n")
cat("raw_name == trimmed_name:", raw_name == trimmed_name, "\n")
cat("stri repr(raw_name):", deparse(raw_name), "\n")
cat("repr(trimmed_name):", deparse(trimmed_name), "\n")

# Direct paste test
test_sql <- paste("SELECT COUNT(*) FROM v WHERE name = '", trimmed_name, "';")
cat("\nPasted SQL:\n", test_sql, "\n")
cat("nchar of SQL:", nchar(test_sql), "\n")

# Check: what if we DON'T use paste?
direct_sql <- sprintf("SELECT COUNT(*) FROM v WHERE name = '%s';", trimmed_name)
cat("\nUsing sprintf:\n", direct_sql, "\n")
