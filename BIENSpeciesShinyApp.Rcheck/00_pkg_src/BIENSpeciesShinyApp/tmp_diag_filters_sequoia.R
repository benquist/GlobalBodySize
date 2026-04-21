shinyApp <- function(...) NULL
source('app.R', local = TRUE)

species <- 'Sequoia sempervirens'

configs <- list(
  default = list(
    use_default_bien_filter_profile = TRUE,
    use_cultivated_filter = TRUE,
    include_cultivated = FALSE,
    use_introduced_filter = TRUE,
    natives_only = TRUE,
    only_geovalid = TRUE,
    exclude_human_observation_records = FALSE,
    only_plot_observations = FALSE
  ),
  custom_liberal = list(
    use_default_bien_filter_profile = FALSE,
    use_cultivated_filter = FALSE,
    include_cultivated = TRUE,
    use_introduced_filter = FALSE,
    natives_only = FALSE,
    only_geovalid = FALSE,
    exclude_human_observation_records = FALSE,
    only_plot_observations = FALSE
  ),
  custom_plot_only = list(
    use_default_bien_filter_profile = FALSE,
    use_cultivated_filter = FALSE,
    include_cultivated = TRUE,
    use_introduced_filter = FALSE,
    natives_only = FALSE,
    only_geovalid = FALSE,
    exclude_human_observation_records = FALSE,
    only_plot_observations = TRUE
  )
)

for (nm in names(configs)) {
  cfg <- configs[[nm]]
  cat('\n==', nm, '==\n')
  occ <- query_occurrence_with_fallback(
    species_name = species,
    input = cfg,
    occ_limit = 2400,
    occ_page_size = 1000,
    timeout_sec = 12,
    connection_retry = FALSE,
    max_plans = 1,
    per_plan_timeout = 8,
    randomize_order = FALSE
  )
  if (!is.data.frame(occ) || nrow(occ) == 0) {
    cat('query rows: 0\n')
    next
  }
  cat('query rows:', nrow(occ), '\n')
  filtered <- apply_runtime_occurrence_filters(occ, cfg)
  cat('after runtime filter rows:', nrow(filtered), '\n')
  prep <- prepare_occurrences(filtered, map_point_cap = 1000, sample_method = 'head')
  cat('mappable rows:', if (is.data.frame(prep$data)) nrow(prep$data) else 0, '\n')
  cat('qa total:', prep$qa$total, 'coord_valid:', prep$qa$coord_valid, 'removed_invalid:', prep$qa$removed_invalid, '\n')
}
