# =============================================================================
# R/climate.R
# Purpose : Download WorldClim BIO rasters and extract climate values at
#           cleaned occurrence point locations.
#
# Ecological context (ecology-user Steps 1 & 4):
#   WorldClim BIO variables (BIO1–BIO19) are derived climate layers computed
#   from monthly temperature and precipitation data (1970–2000 baseline). They
#   summarize ecologically meaningful climate dimensions:
#     BIO1  = Annual Mean Temperature (°C × 10 — divide by 10 for °C)
#     BIO12 = Annual Precipitation (mm/year)
#   These two axes are the most widely used in climate-niche characterization
#   because they broadly capture the energy and water dimensions of climate
#   that constrain plant distributions (Whittaker 1975 biome diagram).
#
#   The approach here is correlative (Step 8): we are NOT modeling a causal
#   mechanism. We are asking "where in climate space do occurrences fall?"
#   This is a descriptive realized-niche summary, not a mechanistic SDM.
#
# Resolution note (Step 2 — scale declaration):
#   WorldClim resolution options (arc-minutes):
#     10  ≈ 18 km at the equator  — appropriate for continental summaries
#      5  ≈  9 km
#    2.5  ≈  4.5 km
#    0.5  ≈  1 km                 — appropriate for landscape/regional work
#   This pipeline defaults to 10 arc-min (set in config.yml: worldclim_res: 10).
#   Coarser resolution reduces download size and extraction time at the cost
#   of local-scale climate heterogeneity.
#
# WorldClim citation (mandatory):
#   Fick, S. E., and Hijmans, R. J. (2017). WorldClim 2: New 1-km spatial
#   resolution climate surfaces for global land areas. International Journal
#   of Climatology, 37, 4302–4315. https://doi.org/10.1002/joc.5086
#
# Packages used:
#   geodata — downloads WorldClim rasters from the WorldClim website
#   terra   — high-performance raster handling and point extraction in R
#             (replacement for the older `raster` package)
# =============================================================================


# --------------------------------------------------------------------------- #
# BIO variable name normalizer (internal helper)
#
# Usage : layers <- resolve_bio_var_names(c(1, 12))
#         # returns c("BIO1", "BIO12")
#
# WorldClim raster layer names from geodata::worldclim_global() follow the
# format "BIO1", "BIO12", etc. This function accepts flexible input formats
# (integers, "bio1", "BIO_1") and normalizes them to the canonical "BIO1"
# form so that the subset operation in get_worldclim_bio() always works.
# --------------------------------------------------------------------------- #
resolve_bio_var_names <- function(bio_vars) {
  x <- as.character(unlist(bio_vars))
  x <- trimws(x)

  # If the value is a bare integer string (e.g., "1", "12"), prefix with "BIO"
  # If it already has BIO/bio prefix, just uppercase it
  out <- ifelse(grepl("^[0-9]+$", x), paste0("BIO", x), toupper(x))

  # Normalize "BIO_1" → "BIO1" (some geodata versions use underscore separator)
  out <- gsub("^BIO_", "BIO", out)
  unique(out)
}


# --------------------------------------------------------------------------- #
# WorldClim BIO raster downloader / reader
#
# Usage : bio <- get_worldclim_bio(worldclim_res = 10,
#                                  cache_dir = "outputs/worldclim_cache",
#                                  bio_vars  = c(1, 12))
#
# Input:
#   worldclim_res — raster resolution in arc-minutes (10, 5, 2.5, or 0.5)
#   cache_dir     — local directory to cache downloaded raster files.
#                   On first run geodata downloads ~3–200 MB depending on
#                   resolution. Subsequent runs read from cache (fast).
#   bio_vars      — integer or character vector of BIO layer numbers to keep
#                   (default: c(1, 12) = temperature + precipitation)
#
# Output: a terra SpatRaster with one layer per requested BIO variable
#
# Caching behavior:
#   geodata::worldclim_global() stores files in cache_dir/climate/wc2.1_*/
#   The `path` argument controls where. If the files already exist, geodata
#   reads them from disk without downloading again.
#
# Why subset early?
#   WorldClim provides 19 BIO layers. Loading all 19 into memory when we only
#   need 2 wastes RAM (each global layer at 10 arc-min is ~12 MB in memory).
#   We subset to only the requested layers before returning.
# --------------------------------------------------------------------------- #
get_worldclim_bio <- function(worldclim_res = 10,
                               cache_dir    = "outputs/worldclim_cache",
                               bio_vars     = c(1, 12)) {

  if (!requireNamespace("geodata", quietly = TRUE)) {
    stop("Package 'geodata' is required. Install with install.packages('geodata').")
  }
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("Package 'terra' is required. Install with install.packages('terra').")
  }

  ensure_directory(cache_dir)
  res_num <- as.numeric(worldclim_res)

  log_info("Downloading/reading WorldClim BIO rasters at ", res_num, " arc-min resolution")

  # geodata returns all 19 BIO layers as a SpatRaster
  bio <- geodata::worldclim_global(var = "bio", res = res_num, path = cache_dir)

  # Normalize layer names to "BIO1", "BIO12", etc. (geodata naming can vary,
  # e.g. "wc2.1_10m_bio_1", "bio12", or "BIO_12")
  raw_names <- names(bio)
  nm <- toupper(raw_names)
  nm <- gsub(".*BIO_?([0-9]+)$", "BIO\\1", nm)
  nm <- gsub("^BIO_", "BIO", nm)
  names(bio) <- nm

  # Resolve and validate the requested BIO variable names
  needed  <- resolve_bio_var_names(bio_vars)
  present <- intersect(needed, names(bio))
  missing <- setdiff(needed, names(bio))

  if (length(missing) > 0) {
    stop("Requested BIO layers not found: ", paste(missing, collapse = ", "))
  }

  # Return only the requested layers (memory efficient)
  bio[[present]]
}


# --------------------------------------------------------------------------- #
# Climate value extractor
#
# Usage : occ_climate <- extract_climate_values(cleaned_occurrences, bio_rasters)
#
# Input:
#   occurrences  — cleaned data.frame from qa_clean_occurrences()$data;
#                  must have columns: latitude, longitude (decimal degrees, WGS84)
#   bio_rasters  — SpatRaster from get_worldclim_bio()
#
# Output: the input data.frame with BIO columns appended (one column per layer)
#
# How extraction works:
#   terra::vect() converts the data.frame to a SpatVector (spatial points).
#   terra::extract() samples the raster value at each point location using
#   bilinear or nearest-neighbour interpolation (default: nearest cell centre).
#   Points that fall outside the raster extent (e.g., in ocean) return NA.
#
# NA interpretation:
#   NA climate values occur for points in the ocean, on small islands, or
#   with very imprecise coordinates that fall in a no-data cell. The plotting
#   function (plotting.R) removes NAs before rendering the climate niche.
#   A high NA rate (> 10–20%) may indicate systematic coordinate problems.
#
# CRS note:
#   EPSG:4326 is the standard CRS for geographic coordinates (lat/lon, WGS84).
#   WorldClim rasters are published in WGS84, so no reprojection is needed.
# --------------------------------------------------------------------------- #
extract_climate_values <- function(occurrences, bio_rasters) {

  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("Package 'terra' is required. Install with install.packages('terra').")
  }

  # Convert occurrence data.frame to terra spatial points (EPSG:4326 = WGS84)
  pts <- terra::vect(
    occurrences,
    geom = c("longitude", "latitude"),   # columns holding x, y respectively
    crs  = "EPSG:4326"
  )

  # Extract raster values at point locations; result includes an "ID" column
  # (row index) which we remove — we only want the BIO value columns
  vals <- terra::extract(bio_rasters, pts)
  vals <- vals[, setdiff(names(vals), "ID"), drop = FALSE]

  # Append BIO columns to the occurrence data.frame and return
  cbind(occurrences, vals, stringsAsFactors = FALSE)
}
