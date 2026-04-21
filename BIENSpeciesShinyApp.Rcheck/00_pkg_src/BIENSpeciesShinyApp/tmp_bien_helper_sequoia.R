suppressPackageStartupMessages(library(BIEN))
sp <- "Sequoia sempervirens"
t0 <- Sys.time()
x <- tryCatch(
  BIEN_occurrence_species(
    species = sp,
    cultivated = FALSE,
    natives.only = TRUE,
    only.geovalid = TRUE,
    all.taxonomy = TRUE,
    observations = TRUE,
    political.boundaries = FALSE,
    collection.info = FALSE,
    native.status = TRUE
  ),
  error = function(e) e
)
dt <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 2)
if (inherits(x, "error")) {
  cat("ERR:", conditionMessage(x), "\n")
} else {
  cat("rows=", nrow(x), " elapsed=", dt, "s\n", sep = "")
  lat_col <- intersect(c("latitude", "decimal_latitude", "lat"), names(x))
  lon_col <- intersect(c("longitude", "decimal_longitude", "lon"), names(x))
  if (length(lat_col) > 0 && length(lon_col) > 0) {
    lat <- suppressWarnings(as.numeric(x[[lat_col[1]]]))
    lon <- suppressWarnings(as.numeric(x[[lon_col[1]]]))
    cat("latlon_non_na=", sum(!is.na(lat) & !is.na(lon)), "\n", sep = "")
    cat("lat_col=", lat_col[1], " lon_col=", lon_col[1], "\n", sep = "")
  } else {
    cat("no_latlon_columns\n")
  }
}
