## Global_Plant_BodySize/scripts/03_growth_form_query.R
## Stage 3: Bulk query BIEN for growth form (categorical trait).
##
## Output: output/bien_growth_form_raw.csv
##   One row per BIEN growth form observation.
##   Growth form is used in Stage 5 to assign canonical growth form categories
##   (tree, shrub, herb, graminoid, bamboo, vine, epiphyte, aquatic, parasite).
##
## NOTE 2026-05-11: Verified against BIEN_trait_list() (BIEN v1.2.8).
##   Correct BIEN trait name is "whole plant growth form",
##   NOT "growth form" (does not exist in BIEN).
##
## NOTE: BIEN's "whole plant growth form" field contains freetext values. Mapping to the
## controlled vocabulary is done in Stage 5 (reconcile_growth_form.R).
## The raw freetext values are preserved in trait_value_verbatim.
##
## Run from project root:
##   Rscript scripts/03_growth_form_query.R
##   Rscript scripts/03_growth_form_query.R --overwrite

args <- commandArgs(trailingOnly = TRUE)
overwrite <- "--overwrite" %in% args

if (basename(getwd()) == "scripts") setwd("..")

source("providers/bien/load_bien_traits.R")

message("=== Stage 3: whole plant growth form ===")
run_bien_trait_intake(
  trait_name  = "whole plant growth form",
  output_file = "output/bien_growth_form_raw.csv",
  overwrite   = overwrite
)

message("=== Stage 3 complete ===")
