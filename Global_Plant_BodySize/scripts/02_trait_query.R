## Global_Plant_BodySize/scripts/02_trait_query.R
## Stage 2: Bulk query BIEN for numeric size traits (height and DBH).
##
## Queries:
##   "whole plant height"                  → output/bien_height_raw.csv
##   "maximum whole plant height"          → output/bien_max_height_raw.csv
##   "diameter at breast height (1.3 m)"  → output/bien_dbh_raw.csv
##
## NOTE 2026-05-11: Verified against BIEN_trait_list() (BIEN v1.2.8).
##   Correct BIEN trait name for DBH is "diameter at breast height (1.3 m)",
##   NOT "stem diameter or width" (does not exist in BIEN).
##   Added "maximum whole plant height" as a second height source.
##
## Both queries use BIEN_trait_traitname() to retrieve all records at once.
## Records are mapped to the canonical schema defined in plant_size_schema.R.
## Units are normalized (height → m, DBH → cm); ambiguous units are flagged.
##
## TIMING NOTE: Each BIEN trait query can take 5-30 minutes depending on
## trait coverage and server load. Files are cached — re-runs skip completed
## queries unless --overwrite is passed.
##
## Run from project root:
##   Rscript scripts/02_trait_query.R
##   Rscript scripts/02_trait_query.R --overwrite

args <- commandArgs(trailingOnly = TRUE)
overwrite <- "--overwrite" %in% args

if (basename(getwd()) == "scripts") setwd("..")

source("providers/bien/load_bien_traits.R")

## ---- Stage 2a: Whole plant height ------------------------------------------
message("=== Stage 2a: whole plant height ===")
run_bien_trait_intake(
  trait_name  = "whole plant height",
  output_file = "output/bien_height_raw.csv",
  overwrite   = overwrite
)

## ---- Stage 2b: Maximum whole plant height ---------------------------------
message("=== Stage 2b: maximum whole plant height ===")
run_bien_trait_intake(
  trait_name  = "maximum whole plant height",
  output_file = "output/bien_max_height_raw.csv",
  overwrite   = overwrite
)

## ---- Stage 2c: DBH (diameter at breast height) ----------------------------
## Verified trait name: BIEN_trait_list() returns "diameter at breast height (1.3 m)"
message("=== Stage 2c: diameter at breast height (1.3 m) ===")
run_bien_trait_intake(
  trait_name  = "diameter at breast height (1.3 m)",
  output_file = "output/bien_dbh_raw.csv",
  overwrite   = overwrite
)

message("=== Stage 2 complete ===")
