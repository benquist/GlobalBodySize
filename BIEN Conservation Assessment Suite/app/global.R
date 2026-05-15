# global.R — BIEN Flora Explora: Conservation Assessment Suite
# Auto-sourced by Shiny before app.R. Loads all packages, sets configuration,
# registers the async worker pool, and sources utility / module files.
#
# Architecture note: CFG is a single shared config list available to all
# workers and modules via options(bien_cfg = CFG) + getOption("bien_cfg").
# This avoids passing CFG as a function argument across the promise boundary.

# ── Packages ─────────────────────────────────────────────────────────────────
library(shiny)          # Shiny framework
library(bslib)          # Bootstrap 5 themes
library(BIEN)           # BIEN R package (Maitner et al. 2018)
library(sf)             # Simple features spatial operations
library(leaflet)        # Interactive maps
library(leaflet.extras) # Draw toolbar for user-drawn polygons
library(dplyr)          # Data wrangling
library(DT)             # Sortable, filterable HTML tables
library(jsonlite)       # GeoJSON parsing
library(digest)         # SHA-256 polygon fingerprinting for provenance
library(promises)       # Async promise chaining (then/catch)
library(future)         # Multisession workers for concurrent BIEN queries

# ── Geodesic math guard ───────────────────────────────────────────────────────
# sf::sf_use_s2(TRUE) enables the S2 spherical geometry library, which gives
# correct area and intersection results for large polygons near the equator.
# Must be TRUE before any st_area() or st_intersection() call in the app.
if (!isTRUE(sf::sf_use_s2())) {
  sf::sf_use_s2(TRUE)
  if (!isTRUE(sf::sf_use_s2())) stop("Failed to enable sf_use_s2(); refusing to start app.")
}

# ── Async worker pool ─────────────────────────────────────────────────────────
# Three workers support the three-stage concurrent query design:
#   Worker 1 — Stage 1: BIEN_list_country (fast species checklist, seconds)
#   Worker 2 — Stage 2: BIEN_occurrence_sf (occurrence records, minutes)
#   Worker 3 — Stage 3: BIEN_ranges_sf (range overlap, slow, optional)
# Workers 1 and 2 always run; Worker 3 is activated only when the user
# checks "Include range overlap analysis."
plan(multisession, workers = 3)

# ── Application configuration ─────────────────────────────────────────────────
# Single config object — referenced as CFG$X by all utils and modules.
# Stored in globalenv AND in options() so it is accessible from any
# evaluation environment, including future workers after the options() snapshot.
CFG <- list(
  APP_VERSION          = "1.0.0",

  # Bounding box for the BIEN Americas domain; used to catch off-hemisphere uploads.
  BIEN_AMERICAS_BBOX   = list(xmin = -170, xmax = -34, ymin = -55, ymax = 55),

  # Polygon area limits. Polygons below MIN are likely erroneous uploads.
  # Polygons above MAX stall the BIEN PostGIS server and produce unreliable
  # richness estimates. MAX is set to ~2× the Alto Japurá pilot study area
  # (~250,000 km²) to accommodate large conservation units.
  MIN_POLYGON_AREA_KM2 = 100,
  MAX_POLYGON_AREA_KM2 = 50000,

  # Per-call deadline (seconds) for BIEN_*_sf() API calls.
  BIEN_API_TIMEOUT_SEC = 180,

  # Anchor species used in the plausibility gate (Data Quality tab).
  # These five taxa are wide-ranging western Amazonian species that should
  # appear in any correctly geocoded query of the Alto Japurá basin.
  # A FAIL indicates a spatial, CRS, or BIEN coverage issue, not true absence.
  ANCHOR_SPECIES = c(
    "Mauritia flexuosa",      # aguaje palm — ubiquitous in flooded várzea
    "Iriartea deltoidea",     # huacrapona — dominant terra firme canopy palm
    "Euterpe precatoria",     # açaí — widespread understory palm
    "Cedrelinga cateniformis",# tornillo — common Amazonian timber tree
    "Swietenia macrophylla"   # big-leaf mahogany — flagship conservation species
  )
)
assign("CFG", CFG, envir = globalenv())   # lexical lookup by sourced functions
options(bien_cfg = CFG)                   # fallback for shiny sharedEnv and workers

# ── Optional curated polygon library ─────────────────────────────────────────
# If a pre-built RDS of curated AOIs exists, load it for the polygon selector.
# Not required; app runs without it.
curated_polygons_path <- "../data/curated_polygons.rds"
if (file.exists(curated_polygons_path)) {
  curated_polygons <- readRDS(curated_polygons_path)
} else {
  curated_polygons <- NULL
}

# ── Source modules and utilities ──────────────────────────────────────────────
# modules/: Shiny UI/server fragments (map rendering, draw toolbar helpers)
# utils/:   Pure R functions for BIEN queries, spatial QA, confidence tiers, exports
for (f in list.files("../modules", pattern = "\\.R$", full.names = TRUE)) sys.source(f, envir = globalenv())
for (f in list.files("../utils",   pattern = "\\.R$", full.names = TRUE)) sys.source(f, envir = globalenv())
