library(shiny)
library(bslib)
library(BIEN)
library(sf)
library(leaflet)
library(leaflet.extras)
library(dplyr)
library(DT)
library(jsonlite)
library(digest)
library(promises)
library(future)

plan(multisession)

APP_VERSION <- "1.0.0"
BIEN_AMERICAS_BBOX <- list(xmin = -170, xmax = -34, ymin = -55, ymax = 55)
MIN_POLYGON_AREA_KM2 <- 100

# Anchor species for plausibility gate.
# Three wide-ranging Amazonian species (high BIEN coverage):
# Plus two terra firme indicators covering non-palm communities.
# NOTE: These pass for essentially any valid western Amazonian polygon;
#       a FAIL indicates a likely spatial, CRS, or data-coverage problem.
ANCHOR_SPECIES <- c(
  "Mauritia flexuosa",       # várzea palm — abundant, well-sampled
  "Iriartea deltoidea",      # terra firme palm — abundant, well-sampled
  "Euterpe precatoria",      # terra firme palm — abundant
  "Cedrelinga cateniformis", # terra firme non-palm — good western Amazonia coverage
  "Swietenia macrophylla"    # mahogany — CITES-listed, well-documented, stable taxonomy
)

curated_polygons_path <- "../data/curated_polygons.rds"
if (file.exists(curated_polygons_path)) {
  curated_polygons <- readRDS(curated_polygons_path)
} else {
  curated_polygons <- NULL
}

for (f in list.files("../modules", pattern = "\\.R$", full.names = TRUE)) source(f)
for (f in list.files("../utils",   pattern = "\\.R$", full.names = TRUE)) source(f)
