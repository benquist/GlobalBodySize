## scripts/run_all_intake.R
## Orchestration script — run all Animal_scaling_data provider intakes in sequence,
## then merge results into the compiled dataset.
##
## Run from the project root:
##   Rscript scripts/run_all_intake.R
##
## Individual providers can also be run stand-alone:
##   Rscript -e "source('providers/animaltraits/load_animaltraits.R'); run_animaltraits_intake()"
##   Rscript -e "source('providers/pnas_2303764120/load_pnas_2303764120.R'); run_pnas_intake()"
##   Rscript -e "source('providers/hatton2019/load_hatton2019.R'); run_hatton2019_intake()"

suppressPackageStartupMessages(library(data.table))

message("=== Animal_scaling_data: run_all_intake.R ===")
message("Working directory: ", getwd())

## ---- 1. AnimalTraits --------------------------------------------------------

message("\n--- AnimalTraits ---")
source("providers/animaltraits/load_animaltraits.R")
run_animaltraits_intake(
  dest_dir    = "providers/animaltraits/data/raw",
  output_file = "output/animaltraits_compiled.csv",
  overwrite   = FALSE
)

## ---- 2. PNAS 2303764120 (graceful skip if files absent) ---------------------

message("\n--- PNAS 2303764120 ---")
source("providers/pnas_2303764120/load_pnas_2303764120.R")
if (check_pnas_files("providers/pnas_2303764120/data/raw")) {
  run_pnas_intake(
    data_dir    = "providers/pnas_2303764120/data/raw",
    output_file = "output/pnas_2303764120_compiled.csv"
  )
} else {
  message("PNAS 2303764120: skipped — see instructions above to place Excel files.")
}

## ---- 3. Hatton et al. 2019 (downloads from Zenodo if not cached) ------------

message("\n--- Hatton et al. 2019 ---")
source("providers/hatton2019/load_hatton2019.R")
run_hatton2019_intake(
  dest_dir    = "providers/hatton2019/data/raw",
  output_file = "output/hatton2019_compiled.csv",
  overwrite   = FALSE
)

## ---- 4. Hatton et al. 2015 (user-provided XLS, graceful skip if absent) ------

message("\n--- Hatton et al. 2015 ---")
source("providers/hatton2015/load_hatton2015.R")
if (check_hatton2015_file("providers/hatton2015/data/raw")) {
  run_hatton2015_intake(
    data_dir    = "providers/hatton2015/data/raw",
    output_file = "output/hatton2015_compiled.csv"
  )
} else {
  message("Hatton2015: skipped — place database_s1.xls in providers/hatton2015/data/raw/")
}

## ---- 5. Merge all providers -------------------------------------------------

message("\n--- Merge providers ---")
source("scripts/merge_providers.R")

message("\n=== run_all_intake.R complete ===")
