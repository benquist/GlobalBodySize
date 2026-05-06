# download_all.R
# Orchestrator: runs all 20 dataset download scripts in sequence.
# Skips datasets that already have data in their target folder.
# Run from the project root: source("download_all.R")

library(here)

scripts <- c(
  "R/download_01_main_study.R",
  "R/download_02_itrdb.R",
  "R/download_03_tropical_rings.R",
  "R/download_04_oldlist_west.R",
  "R/download_05_oldlist_east.R",
  "R/download_06_nts_dendro.R",
  "R/download_07_oldgrowth_canada.R",
  "R/download_08_tree_height_zenodo.R",
  "R/download_09_conifers_height.R",
  "R/download_10_monumental_height.R",
  "R/download_11_wood_density_zenodo.R",
  "R/download_12_wood_density_dv.R",
  "R/download_13_conduit_p50_dryad.R",
  "R/download_14_p50_sci_advances.R",
  "R/download_15_glopnet_leaf.R",
  "R/download_16_try_seed_mass.R",
  "R/download_17_treegOER_climate.R",
  "R/download_18_worldclim.R",
  "R/download_19_chelsa.R",
  "R/download_20_gbif_occurrence.R"
)

results <- data.frame(
  script  = scripts,
  status  = NA_character_,
  message = NA_character_,
  stringsAsFactors = FALSE
)

for (i in seq_along(scripts)) {
  s <- scripts[i]
  message("\n", strrep("=", 60))
  message("Running [", i, "/", length(scripts), "]: ", s)
  message(strrep("=", 60))
  tryCatch({
    source(here::here(s))
    results$status[i]  <- "OK"
    results$message[i] <- ""
  }, error = function(e) {
    results$status[i]  <<- "ERROR"
    results$message[i] <<- conditionMessage(e)
    message("ERROR in ", s, ":\n  ", conditionMessage(e))
  })
}

message("\n", strrep("=", 60))
message("DOWNLOAD SUMMARY")
message(strrep("=", 60))
print(results[, c("script", "status")], row.names = FALSE)

n_ok  <- sum(results$status == "OK",    na.rm = TRUE)
n_err <- sum(results$status == "ERROR", na.rm = TRUE)
message(sprintf("\n%d scripts OK | %d scripts with errors", n_ok, n_err))
message("Full download log: logs/download_log.csv")
