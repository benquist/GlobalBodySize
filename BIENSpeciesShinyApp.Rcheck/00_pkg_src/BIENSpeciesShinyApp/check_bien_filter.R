suppressWarnings(library(BIEN))

# Check what BIEN's internal natives_check actually generates
natives_bien <- BIEN:::.natives_check(TRUE)
cat("BIEN's native filter (natives_only=TRUE):\n")
cat(natives_bien$query, "\n\n")

# Check the select clause
native_bien_select <- BIEN:::.native_check(TRUE)
cat("BIEN's native SELECT:\n")
cat(native_bien_select$select, "\n")
