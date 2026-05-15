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
# withCallingHandlers is base R — no library() call needed

plan(multisession)

APP_VERSION <- "1.0.0"
BIEN_AMERICAS_BBOX <- list(xmin = -170, xmax = -34, ymin = -55, ymax = 55)
MIN_POLYGON_AREA_KM2 <- 100
ANCHOR_SPECIES <- c(
  "Mauritia flexuosa",
  "Iriartea deltoidea",
  "Virola surinamensis",
  "Cecropia latiloba",
  "Euterpe precatoria"
)

curated_polygons_path <- "../data/curated_polygons.rds"
if (file.exists(curated_polygons_path)) {
  curated_polygons <- readRDS(curated_polygons_path)
} else {
  curated_polygons <- NULL
}

for (f in list.files("../modules", pattern = "\\.R$", full.names = TRUE)) {
  source(f)
}
for (f in list.files("../utils", pattern = "\\.R$", full.names = TRUE)) {
  source(f)
}
