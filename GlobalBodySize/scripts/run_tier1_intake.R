#!/usr/bin/env Rscript
## GlobalBodySize/scripts/run_tier1_intake.R
## Stage 2: Intake and compile all Tier 1 curated databases
## Runs provider intake scripts in priority order per merow-ecology advisory:
##   1. PanTHERIA (mammals — Tier A)
##   2. AVONET (birds — Tier A)
##   3. FishBase/rfishbase (fish — Tier B, LW modeled)
##   4. AmphiBIO (amphibians — Tier A/B)
##   5. EltonTraits (cross-check — Tier A birds, Tier B mammals)
##   6. Ernest 2003 (mammal life stage complement — Tier A)
##   7. AnAge (vertebrate gap-fill — Tier B)
##
## Outputs all compiled CSVs to data/compiled/
## Writes data/compiled/tier1_combined.csv with all sources merged

find_project_root <- function() {
  cwd <- getwd()
  if (basename(cwd) == "GlobalBodySize") return(cwd)
  if (basename(cwd) == "scripts" && basename(dirname(cwd)) == "GlobalBodySize") return(dirname(cwd))
  proj <- file.path(cwd, "GlobalBodySize")
  if (dir.exists(proj)) return(proj)
  stop("Cannot locate GlobalBodySize project root from: ", cwd)
}

main <- function() {
  root <- find_project_root()

  source(file.path(root, "R", "body_mass_schema.R"))
  source(file.path(root, "R", "qa_checks.R"))

  compiled_dir <- file.path(root, "data", "compiled")
  dir.create(compiled_dir, recursive = TRUE, showWarnings = FALSE)

  results <- list()

  ## ---- 1. PanTHERIA --------------------------------------------------------
  message("\n=== 1. PanTHERIA ===")
  source(file.path(root, "providers", "pantheria", "load_pantheria.R"))
  tryCatch({
    pantheria <- run_pantheria_intake(
      dest_dir    = file.path(root, "data", "raw", "pantheria"),
      output_file = file.path(compiled_dir, "pantheria_compiled.csv")
    )
    results[["pantheria"]] <- pantheria
  }, error = function(e) message("PanTHERIA failed: ", conditionMessage(e)))

  ## ---- 2. AVONET -----------------------------------------------------------
  message("\n=== 2. AVONET ===")
  source(file.path(root, "providers", "avonet", "load_avonet.R"))
  tryCatch({
    avonet <- run_avonet_intake(
      dest_dir    = file.path(root, "data", "raw", "avonet"),
      output_file = file.path(compiled_dir, "avonet_compiled.csv")
    )
    results[["avonet"]] <- avonet
  }, error = function(e) message("AVONET failed: ", conditionMessage(e)))

  ## ---- 3. FishBase ---------------------------------------------------------
  message("\n=== 3. FishBase (rfishbase) ===")
  source(file.path(root, "providers", "fishbase", "load_fishbase.R"))
  tryCatch({
    fishbase <- run_fishbase_intake(
      max_species = 1000,  ## Start with 1000; remove cap for full run
      output_file = file.path(compiled_dir, "fishbase_compiled.csv")
    )
    results[["fishbase"]] <- fishbase
  }, error = function(e) message("FishBase failed: ", conditionMessage(e)))

  ## ---- 4-7. Additional providers (stubs — implement individually) ----------
  ## AmphiBIO, EltonTraits, Ernest2003, AnAge: see providers/ subdirectories
  message("\n=== 4-7. Additional Tier 1 providers ===")
  message("AmphiBIO, EltonTraits, Ernest 2003, AnAge: implement in providers/")
  message("Scripts to create: providers/amphibio/load_amphibio.R")
  message("                   providers/eltontraits/load_eltontraits.R")

  ## ---- Merge all available results -----------------------------------------
  results_valid <- Filter(Negate(is.null), results)
  if (!length(results_valid)) {
    message("\nNo providers returned data. Check errors above.")
    return(invisible(NULL))
  }

  ## Align columns to schema (add missing columns as NA)
  schema_cols <- globalsize_schema_columns()
  results_aligned <- lapply(results_valid, function(df) {
    missing_cols <- setdiff(schema_cols, names(df))
    for (col in missing_cols) df[[col]] <- NA
    df[, intersect(schema_cols, names(df)), drop = FALSE]
  })

  combined <- do.call(rbind, results_aligned)

  ## Assign unique measurement_id
  combined$measurement_id <- paste0("GBS_", sprintf("%08d", seq_len(nrow(combined))))

  ## Run QA
  message("\n=== Running QA ===")
  combined <- run_all_qa(combined, verbose = TRUE)

  ## Write combined
  out_file <- file.path(compiled_dir, "tier1_combined.csv")
  data.table::fwrite(combined, out_file)
  message("\nTier 1 combined: ", nrow(combined), " rows -> ", out_file)

  ## Summary by source and group
  message("\nRow counts by source:")
  print(sort(table(combined$source_id), decreasing = TRUE))
  message("\nRow counts by taxonomic group:")
  print(sort(table(combined$input_taxonomic_group), decreasing = TRUE))

  invisible(combined)
}

if (!interactive()) main()
