shinyApp <- function(...) NULL
source('app.R', local = TRUE)

species <- 'Solidago canadensis'
cfg <- list(
  use_default_bien_filter_profile = TRUE,
  use_cultivated_filter = TRUE,
  include_cultivated = FALSE,
  use_introduced_filter = TRUE,
  natives_only = TRUE,
  only_geovalid = TRUE,
  exclude_human_observation_records = FALSE,
  only_plot_observations = FALSE
)

cat('species=', species, '\n', sep='')

# BIEN-side mappable counts
n_strict <- count_mappable_occurrences_for_species(species, cultivated = FALSE, natives_only = TRUE, only_geovalid = TRUE, timeout_sec = 15)
n_liberal <- count_mappable_occurrences_for_species(species, cultivated = TRUE, natives_only = FALSE, only_geovalid = FALSE, timeout_sec = 15)
cat('mappable_count_strict=', n_strict, '\n', sep='')
cat('mappable_count_liberal=', n_liberal, '\n', sep='')

# App query path benchmark
for (pt in c(8, 12, 20)) {
  t0 <- Sys.time()
  r <- query_occurrence_with_fallback(
    species_name = species,
    input = cfg,
    occ_limit = 2400,
    occ_page_size = 1000,
    timeout_sec = 20,
    connection_retry = FALSE,
    max_plans = 3,
    per_plan_timeout = pt,
    randomize_order = FALSE
  )
  dt <- round(as.numeric(difftime(Sys.time(), t0, units = 'secs')), 2)
  rows <- if (is.data.frame(r$data)) nrow(r$data) else NA_integer_
  cat('per_plan_timeout=', pt, ' strategy=', r$strategy, ' rows=', rows, ' elapsed=', dt, 's\n', sep='')
  cat('notes=', paste(r$notes, collapse = ' | '), '\n', sep='')

  if (is.data.frame(r$data) && nrow(r$data) > 0) {
    prep <- prepare_occurrences(r$data, map_point_cap = 1000, sample_method = 'head')
    mappable <- if (is.data.frame(prep$data)) nrow(prep$data) else 0
    cat('mappable=', mappable, ' coord_valid=', prep$qa$coord_valid, ' removed_invalid=', prep$qa$removed_invalid, '\n', sep='')
  }
}
