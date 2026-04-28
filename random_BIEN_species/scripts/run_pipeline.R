#!/usr/bin/env Rscript

# =============================================================================
# scripts/run_pipeline.R
# Purpose : End-to-end orchestrator for the random_BIEN_species workflow.
#
# Workflow summary:
#   1) Read reproducible config (seed, thresholds, climate variables)
#   2) Build candidate species pool from BIEN taxonomy
#   3) Randomly draw species and run QA cleaning on occurrences
#   4) Keep first species with >= min_records clean points
#   5) Extract WorldClim BIO variables at occurrence points
#   6) Save analysis tables and a climate-space figure
#
# This script is intentionally linear and verbose so students can trace the
# full workflow without jumping across multiple abstraction layers.
# =============================================================================

args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(prefix, default = NULL) {
  hit <- grep(paste0("^", prefix, "="), args, value = TRUE)
  if (length(hit) == 0) return(default)
  sub(paste0("^", prefix, "="), "", hit[1])
}

is_dry_run <- any(args %in% c("--dry-run", "--dry_run"))
config_path <- arg_value("--config", "config.yml")

script_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(script_arg) > 0) {
  # Running via Rscript --file=... : infer project root from script location
  script_path <- normalizePath(sub("^--file=", "", script_arg[1]))
  project_root <- normalizePath(file.path(dirname(script_path), ".."))
} else {
  # Running interactively from project root
  project_root <- normalizePath(".")
}

setwd(project_root)

source("R/utils.R")
source("R/data_access.R")
source("R/cleaning.R")
source("R/climate.R")
source("R/plotting.R")

cfg <- read_config(config_path)
# Fix random seed for reproducibility of random species draws
set.seed(as.integer(cfg$seed))

if (is_dry_run) {
  log_info("Dry run successful. Parsed scripts and loaded config from ", config_path)
  quit(save = "no", status = 0)
}

ensure_directory("outputs")

log_info("Building random candidate species pool from BIEN")
species_pool <- get_species_pool(cfg)
write_csv(data.frame(species = species_pool, stringsAsFactors = FALSE), "outputs/species_pool.csv")

attempt_log <- data.frame(
  attempt = integer(0),
  species = character(0),
  n_raw = integer(0),
  n_clean = integer(0),
  eligible = logical(0),
  message = character(0),
  stringsAsFactors = FALSE
)

tried <- character(0)
selected <- NULL
max_attempts <- as.integer(cfg$max_random_attempts)

for (i in seq_len(max_attempts)) {
  # Avoid drawing the same species twice
  available <- setdiff(species_pool, tried)
  if (length(available) == 0) break

  species <- sample(available, size = 1)
  tried <- c(tried, species)

  log_info("Attempt ", i, "/", max_attempts, ": ", species)

  step_message <- "ok"
  raw <- NULL
  cleaned <- NULL

  tryCatch({
    # Pull raw BIEN occurrences, then apply transparent QA filters
    raw <- fetch_occurrences(species = species, occurrence_limit = as.integer(cfg$occurrence_limit))
    cleaned <- qa_clean_occurrences(raw)
  }, error = function(e) {
    step_message <<- conditionMessage(e)
  })

  n_raw <- if (is.data.frame(raw)) nrow(raw) else 0L
  n_clean <- if (is.list(cleaned) && is.data.frame(cleaned$data)) nrow(cleaned$data) else 0L
  eligible <- n_clean >= as.integer(cfg$min_records)

  attempt_log <- rbind(
    attempt_log,
    data.frame(
      attempt = i,
      species = species,
      n_raw = n_raw,
      n_clean = n_clean,
      eligible = eligible,
      message = step_message,
      stringsAsFactors = FALSE
    )
  )

  if (eligible) {
    # Stop at first species that satisfies minimum cleaned-record threshold
    selected <- list(species = species, raw = raw, cleaned = cleaned)
    break
  }
}

write_csv(attempt_log, "outputs/selection_attempts.csv")

if (is.null(selected)) {
  stop(
    "No eligible species found after ", max_attempts,
    " attempts. Check BIEN availability and consider lowering min_records in config.yml."
  )
}

selected_df <- data.frame(
  species = selected$species,
  n_raw = nrow(selected$raw),
  n_clean = nrow(selected$cleaned$data),
  selected_at_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  stringsAsFactors = FALSE
)
write_csv(selected_df, "outputs/selected_species.csv")
write_csv(selected$cleaned$qa_summary, "outputs/qa_summary.csv")
write_csv(selected$cleaned$data, "outputs/cleaned_occurrences.csv")

# Download/read requested WorldClim layers and extract at occurrence locations
bio_rasters <- get_worldclim_bio(
  worldclim_res = cfg$worldclim_res,
  cache_dir = "outputs/worldclim_cache",
  bio_vars = cfg$bio_vars
)

occ_climate <- extract_climate_values(selected$cleaned$data, bio_rasters)
write_csv(occ_climate, "outputs/cleaned_occurrences_with_climate.csv")

bio_names <- resolve_bio_var_names(cfg$bio_vars)
if (length(bio_names) < 2) {
  stop("At least two BIO variables are required for climate-space plotting")
}

plot_path <- sprintf(
  "outputs/climate_niche_%s_vs_%s.png",
  tolower(bio_names[1]),
  tolower(bio_names[2])
)

plot_climate_niche(
  data = occ_climate,
  bio_x = bio_names[1],
  bio_y = bio_names[2],
  output_png = plot_path,
  bins = as.integer(cfg$plot$bins %||% 45),
  width = as.numeric(cfg$plot$width %||% 8),
  height = as.numeric(cfg$plot$height %||% 6),
  dpi = as.numeric(cfg$plot$dpi %||% 300)
)

log_info("Pipeline complete")
log_info("Selected species: ", selected$species)
log_info("Outputs written to: outputs/")
