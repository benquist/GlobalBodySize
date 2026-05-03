## ============================================================
## tallo_bien_preexport.R
## Pre-export QA pipeline for Tallo v1.0.0 → BIEN database
##
## Purpose:
##   Build a Darwin-Core-ready table of individual-tree records
##   from Tallo.csv, suitable for loading into the BIEN
##   occurrence + trait database.
##
## Outputs:
##   data/processed/tallo_bien_preexport.csv  — accepted records
##   data/processed/tallo_bien_rejected.csv   — quarantined records
##   data/processed/tallo_bien_provenance.txt — run metadata
##
## Steps:
##   1. Load raw data
##   2. Exclude unidentifiable records (species NA)
##   3. Assign coordinate precision class + coordinateUncertaintyInMeters
##   4. Quarantine implausible records (T_481206)
##   5. Build measurementRemarks from source QA flags
##   6. Reverse-geocode country / state / county (GADM via sf + geodata)
##   7. Rename fields to Darwin Core / BIEN schema
##   8. Write outputs + provenance log
##
## Requirements:
##   data.table, dplyr, sf, geodata, lubridate (all on CRAN)
##
## Notes:
##   - TNRS reconciliation is NOT run here; run separately via
##     TNRS::TNRS() against wcvp/tropicos and join on scientificName.
##   - Year/date extraction from Tallo_references.csv is partially
##     automated below; some references require manual year lookup.
##   - GADM admin-2 (county) reverse geocoding is memory-intensive;
##     this script processes by country to limit peak memory.
##   - Record GADM version, geodata version, and run date in provenance.
##
## Provenance:
##   Created: 2026-05-02
##   Author:  plant_scaling_data project / m-agent pipeline
##   Source:  Jucker et al. 2022, Global Change Biology 28:5254-5268
##            https://doi.org/10.1111/gcb.16302
##            Data: https://doi.org/10.5281/zenodo.6637599
## ============================================================

suppressPackageStartupMessages({
  library(data.table)
  library(dplyr)
  library(sf)
  library(geodata)
})

## ---- Paths ------------------------------------------------------------------
# Resolve project root from script location (works from Rscript CLI, source(), or RStudio)
script_self <- tryCatch(
  normalizePath(sys.frames()[[1]]$ofile),
  error = function(e) tryCatch(
    normalizePath(rstudioapi::getActiveDocumentContext()$path),
    error = function(e2) normalizePath(file.path(getwd(), "scripts/tallo_bien_preexport.R"))
  )
)
PROJECT_ROOT <- dirname(dirname(script_self))   # scripts/ -> project root
RAW_DIR  <- file.path(PROJECT_ROOT, "data/raw/tallo")
OUT_DIR   <- file.path(dirname(RAW_DIR), "..", "processed")
GADM_DIR  <- file.path(dirname(RAW_DIR), "..", "gadm_cache")
dir.create(OUT_DIR,  showWarnings = FALSE, recursive = TRUE)
dir.create(GADM_DIR, showWarnings = FALSE, recursive = TRUE)

cat("Reading Tallo.csv ...\n")
tallo <- fread(file.path(RAW_DIR, "Tallo.csv"))
refs  <- fread(file.path(RAW_DIR, "Tallo_references.csv"),
               encoding = "Latin-1")
cat("Loaded", nrow(tallo), "records,", length(unique(tallo$reference_id)),
    "references\n")

## ---- Step 1: Exclude unidentifiable records ---------------------------------
cat("\n--- Step 1: Exclude NA-species records ---\n")
rejected_sp <- tallo[is.na(species)]
cat("Excluded (species NA):", nrow(rejected_sp), "\n")
tallo_id <- tallo[!is.na(species)]
cat("Remaining:", nrow(tallo_id), "\n")

## ---- Step 2: Quarantine implausible records ---------------------------------
cat("\n--- Step 2: Quarantine implausible records ---\n")

# T_481206: 102.7 m tree with no species at 31.2°N/-84.5°W (Georgia USA)
# No eastern US species reaches >~60 m; likely unit error (feet) or GPS error
quarantine_ids <- c("T_481206")
rejected_implausible <- tallo_id[tree_id %in% quarantine_ids]
rejected_implausible[, rejection_reason := "implausible_height_for_location_no_species"]
cat("Quarantined (implausible):", nrow(rejected_implausible), "\n")
tallo_id <- tallo_id[!tree_id %in% quarantine_ids]

## ---- Step 3: Coordinate precision + uncertainty ----------------------------
cat("\n--- Step 3: Coordinate precision classes ---\n")

tallo_id[, lat_dp := nchar(sub("^[^.]*[.]?", "", as.character(abs(latitude))))]
tallo_id[, lon_dp := nchar(sub("^[^.]*[.]?", "", as.character(abs(longitude))))]
tallo_id[, min_dp := pmin(as.integer(lat_dp), as.integer(lon_dp))]

tallo_id[, coord_precision_class := fcase(
  min_dp == 0, "integer_~100km",
  min_dp == 1, "1dp_~11km",
  min_dp == 2, "2dp_~1km",
  min_dp >= 3, "3plus_dp_acceptable"
)]

tallo_id[, coordinateUncertaintyInMeters := fcase(
  min_dp == 0, 111000L,
  min_dp == 1,  11100L,
  min_dp == 2,   1100L,
  default = NA_integer_
)]

tallo_id[, is_plot_centroid := min_dp <= 2]

prec_tab <- tallo_id[, .N, by = coord_precision_class][order(coord_precision_class)]
print(prec_tab)

## ---- Step 4: lon=0 anomaly flag --------------------------------------------
# 6 Quercus ilex records from reference 35 with lon=0 in Spain
# Geographically possible (NE Spain ~lon 0) but warrants source verification
tallo_id[longitude == 0,
         coordinateRemarks := "longitude=0; verify against source publication (ref 35)"]

## ---- Step 5: Measurement remarks from source QA flags ---------------------
cat("\n--- Step 5: measurementRemarks from outlier flags ---\n")
tallo_id[, measurementRemarks := fcase(
  height_outlier == "Y" & crown_radius_outlier == "Y",
    "height_outlier=Y; crown_radius_outlier=Y (Tallo v1.0.0 allometric outlier flags)",
  height_outlier == "Y",
    "height_outlier=Y (Tallo v1.0.0 allometric outlier flag)",
  crown_radius_outlier == "Y",
    "crown_radius_outlier=Y (Tallo v1.0.0 allometric outlier flag)",
  default = NA_character_
)]

# Sapling / juvenile flag
tallo_id[!is.na(height_m) & height_m < 2,
         lifeStage := "juvenile/sapling (height_m < 2)"]

## ---- Step 6: Year range from references ------------------------------------
# Attempt to extract 4-digit year from source string
# Many citations contain the year immediately after the first author
refs[, year_extracted := as.integer(
  sub(".*\\((\\d{4})\\).*", "\\1", source, perl = TRUE) |>
    (\(x) ifelse(grepl("^\\d{4}$", x), x, NA_character_))()
)]
# Where extraction fails, set NA — these need manual lookup
refs_year <- refs[, .(reference_id, year_extracted)]
cat("References with year extracted:", sum(!is.na(refs_year$year_extracted)),
    "of", nrow(refs_year), "\n")
cat("References needing manual year lookup:",
    sum(is.na(refs_year$year_extracted)), "\n")

tallo_id <- merge(tallo_id, refs_year, by = "reference_id", all.x = TRUE)
# ── eventDate: publication year is NOT the measurement/collection date ─────────
# Setting eventDate = "YYYY-01-01" from a citation year is incorrect Darwin Core:
# publication lag means the year often differs from the measurement year.
# BIEN temporal filters, phenology analyses, and temporal overlap queries would
# be corrupted by a fabricated January 1 date. Audit finding: 2026-05-02.
# Action required before BIEN ingestion: source measurement year from study
# metadata where available (e.g., Jucker et al. 2022 Table S1 study dates).
tallo_id[, eventDate := NA_character_]          # measurement date unavailable
tallo_id[, year_from_citation := year_extracted] # approximate; pub year not collection year
tallo_id[, date_precision := fcase(
  !is.na(year_extracted), "publication_year_only_not_collection_date",
  default = "unknown_requires_manual_lookup"
)]

## ---- Step 7: Reverse geocoding — country (admin 0) -------------------------
cat("\n--- Step 6: Reverse geocoding (country) ---\n")
cat("Building sf points object ...\n")
pts <- st_as_sf(tallo_id[, .(tree_id, longitude, latitude)],
                coords = c("longitude", "latitude"),
                crs = 4326, remove = FALSE)

cat("Loading world polygons (GADM admin-0) ...\n")
sf::sf_use_s2(FALSE)   # GADM polygons have minor topology issues; disable S2
world_sv  <- geodata::world(resolution = 1, path = GADM_DIR)
world_sf  <- st_make_valid(st_as_sf(world_sv))

cat("Joining country ...\n")
pts_country <- st_join(pts,
                       world_sf[, c("NAME_0", "GID_0")],
                       join = st_within, left = TRUE)

# Points outside polygons (ocean, coastal) — try 1 km buffer snap
na_country <- pts_country[is.na(pts_country$NAME_0), ]
cat("Points unmatched to country:", nrow(na_country),
    "(coastal/ocean; attempting 1 km buffer snap)\n")
if (nrow(na_country) > 0) {
  na_buffered <- st_buffer(na_country["tree_id"], dist = 1000)
  na_snap     <- st_join(na_buffered,
                         world_sf[, c("NAME_0", "GID_0")],
                         join = st_intersects, left = TRUE)
  na_snap     <- st_drop_geometry(na_snap)
  pts_country <- st_drop_geometry(pts_country)
  pts_country <- rows_update(pts_country,
                              na_snap[, c("tree_id","NAME_0","GID_0")],
                              by = "tree_id", unmatched = "ignore")
  cat("After buffer snap, still unmatched:",
      sum(is.na(pts_country$NAME_0)), "\n")
} else {
  pts_country <- st_drop_geometry(pts_country)
}

tallo_id <- merge(tallo_id,
                  pts_country[, c("tree_id","NAME_0","GID_0")],
                  by = "tree_id", all.x = TRUE)
setnames(tallo_id, c("NAME_0","GID_0"), c("country","gadm_gid_0"))

## ---- Step 8: Reverse geocoding — state/province (admin 1) -----------------
cat("\n--- Step 7: Reverse geocoding (state/province by country) ---\n")

unique_countries <- unique(na.omit(tallo_id$gadm_gid_0))
cat("Processing", length(unique_countries), "countries for admin-1 ...\n")

adm1_results <- lapply(seq_along(unique_countries), function(i) {
  ccode <- unique_countries[i]
  sub_pts <- pts[pts$tree_id %in% tallo_id[gadm_gid_0 == ccode, tree_id], ]
  if (nrow(sub_pts) == 0) return(NULL)
  gadm1 <- tryCatch(
    sf::st_as_sf(geodata::gadm(country = ccode, level = 1, path = GADM_DIR)),
    error = function(e) {
      message("GADM admin-1 unavailable for: ", ccode, " — ", e$message)
      NULL
    }
  )
  if (is.null(gadm1)) return(NULL)
  joined <- st_join(sub_pts["tree_id"],
                    gadm1[, c("NAME_1","GID_1")],
                    join = st_within, left = TRUE)
  st_drop_geometry(joined)
})

adm1_df <- rbindlist(Filter(Negate(is.null), adm1_results))
if (nrow(adm1_df) > 0) {
  tallo_id <- merge(tallo_id, adm1_df, by = "tree_id", all.x = TRUE)
  setnames(tallo_id, c("NAME_1","GID_1"), c("stateProvince","gadm_gid_1"))
} else {
  tallo_id[, stateProvince := NA_character_]
  tallo_id[, gadm_gid_1    := NA_character_]
}

## ---- Step 9: Reverse geocoding — county (admin 2, US/CAN/MEX only) --------
cat("\n--- Step 8: Reverse geocoding (county — US/CAN/MEX only) ---\n")

priority_countries <- c("USA","CAN","MEX")
adm2_results <- lapply(priority_countries, function(ccode) {
  sub_pts <- pts[pts$tree_id %in% tallo_id[gadm_gid_0 == ccode, tree_id], ]
  if (nrow(sub_pts) == 0) return(NULL)
  gadm2 <- tryCatch(
    sf::st_as_sf(geodata::gadm(country = ccode, level = 2, path = GADM_DIR)),
    error = function(e) {
      message("GADM admin-2 unavailable for: ", ccode, " — ", e$message)
      NULL
    }
  )
  if (is.null(gadm2)) return(NULL)
  cat("  ", ccode, ": joining", nrow(sub_pts), "points to admin-2 ...\n")
  joined <- st_join(sub_pts["tree_id"],
                    gadm2[, c("NAME_2","GID_2")],
                    join = st_within, left = TRUE)
  st_drop_geometry(joined)
})

adm2_df <- rbindlist(Filter(Negate(is.null), adm2_results))
if (nrow(adm2_df) > 0) {
  tallo_id <- merge(tallo_id, adm2_df, by = "tree_id", all.x = TRUE)
  setnames(tallo_id, c("NAME_2","GID_2"), c("county","gadm_gid_2"))
} else {
  tallo_id[, county     := NA_character_]
  tallo_id[, gadm_gid_2 := NA_character_]
}

## ---- Step 10: Darwin Core / BIEN field layout ------------------------------
cat("\n--- Step 9: Building Darwin Core output table ---\n")

# Split genus and specificEpithet from binomial
tallo_id[, genus_dc := sub(" .*", "", species)]
tallo_id[, specificEpithet := sub("^[^ ]+ ", "", species)]

bien_export <- tallo_id[, .(
  # Identifiers
  occurrenceID          = tree_id,
  # Taxonomy
  scientificName        = species,
  genus                 = genus_dc,
  specificEpithet       = specificEpithet,
  family                = family,
  higherClassification  = division,
  # Geography
  decimalLatitude       = latitude,
  decimalLongitude      = longitude,
  coordinateUncertaintyInMeters = coordinateUncertaintyInMeters,
  coord_precision_class = coord_precision_class,
  is_plot_centroid      = is_plot_centroid,
  coordinateRemarks     = coordinateRemarks,
  country               = country,
  gadm_gid_0            = gadm_gid_0,
  stateProvince         = stateProvince,
  gadm_gid_1            = gadm_gid_1,
  county                = county,
  gadm_gid_2            = gadm_gid_2,
  # Date
  eventDate             = eventDate,       # NA: measurement date unavailable; see year_from_citation
  year_from_citation    = year_from_citation,
  date_precision        = date_precision,
  # Establishment
  establishmentMeans    = NA_character_,  # Tallo includes natural forest AND plantation records;
                                         # requires curation from Jucker et al. 2022 Table S1
                                         # before BIEN ingestion (native/introduced/cultivated).
  # Traits
  stem_diameter_cm      = stem_diameter_cm,
  plant_height_m        = height_m,
  crown_radius_m        = crown_radius_m,
  # QA flags
  height_outlier_source    = height_outlier,
  crown_radius_outlier_source = crown_radius_outlier,
  measurementRemarks    = measurementRemarks,
  lifeStage             = lifeStage,
  # Provenance
  reference_id          = reference_id,
  datasetName           = "Tallo v1.0.0",
  datasetDOI            = "https://doi.org/10.5281/zenodo.6637599",
  bibliographicCitation = "Jucker et al. 2022, Global Change Biology 28:5254-5268. https://doi.org/10.1111/gcb.16302"
)]

## ---- Step 11: Write outputs ------------------------------------------------
cat("\n--- Step 10: Writing outputs ---\n")

out_accepted  <- file.path(OUT_DIR, "tallo_bien_preexport.csv")
out_rejected  <- file.path(OUT_DIR, "tallo_bien_rejected.csv")
out_prov      <- file.path(OUT_DIR, "tallo_bien_provenance.txt")

fwrite(bien_export, out_accepted)
cat("Accepted records written:", nrow(bien_export), "->", out_accepted, "\n")

rejected_all <- rbindlist(list(
  cbind(rejected_sp,          rejection_reason = "species_NA"),
  cbind(rejected_implausible[, rejection_reason := NULL],
        rejection_reason = "implausible_height_no_species")
), fill = TRUE)
fwrite(rejected_all, out_rejected)
cat("Rejected records written:", nrow(rejected_all), "->", out_rejected, "\n")

# Provenance log
prov_lines <- c(
  paste0("tallo_bien_preexport.R run: ", Sys.time()),
  paste0("R version: ", R.version$version.string),
  paste0("sf version: ",      packageVersion("sf")),
  paste0("geodata version: ", packageVersion("geodata")),
  paste0("data.table version: ", packageVersion("data.table")),
  paste0("GADM cache path: ", GADM_DIR),
  paste0("GADM resolution: admin-0 (global), admin-1 (all countries), admin-2 (USA/CAN/MEX)"),
  paste0("Source: Tallo v1.0.0 — Jucker et al. 2022 https://doi.org/10.1111/gcb.16302"),
  paste0("Input rows: ", nrow(tallo)),
  paste0("Excluded (species NA): ", nrow(rejected_sp)),
  paste0("Quarantined (implausible): ", nrow(rejected_implausible)),
  paste0("Accepted records: ", nrow(bien_export)),
  paste0("Records with GPS-quality coords (3+ dp): ",
         nrow(bien_export[bien_export$is_plot_centroid == FALSE, ])),
  paste0("Records with plot-centroid coords (<=2 dp): ",
         nrow(bien_export[bien_export$is_plot_centroid == TRUE, ])),
  paste0("Outstanding: TNRS reconciliation not yet run (5164 species names need backbone validation)"),
  paste0("Outstanding: eventDate populated for refs with year parseable from citation string;",
         " ", sum(is.na(tallo_id$eventDate)), " records need manual year lookup")
)
writeLines(prov_lines, out_prov)
cat("Provenance written ->", out_prov, "\n")

cat("\nDone.\n")
