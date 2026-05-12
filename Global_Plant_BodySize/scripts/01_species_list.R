## Global_Plant_BodySize/scripts/01_species_list.R
## Stage 1: Retrieve the complete BIEN vascular plant species list.
##
## Output: output/bien_species_list.csv
##   One row per BIEN species with taxonomy and provenance columns.
##   This is the authoritative roster; all species are carried to Stage 8
##   even if no trait data exist (trait_data_available = FALSE).
##
## Run from project root:
##   Rscript scripts/01_species_list.R
##   Rscript scripts/01_species_list.R --overwrite

args <- commandArgs(trailingOnly = TRUE)
overwrite <- "--overwrite" %in% args

## Set working directory to project root if running from scripts/
if (basename(getwd()) == "scripts") setwd("..")

source("providers/bien/load_bien_species.R")

run_bien_species_intake(
  output_file = "output/bien_species_list.csv",
  overwrite   = overwrite
)
