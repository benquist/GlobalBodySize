shinyApp <- function(...) NULL
source('app.R', local = TRUE)

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

r <- query_occurrence_with_fallback(
  species_name = 'Sequoia sempervirens',
  input = cfg,
  occ_limit = 2400,
  occ_page_size = 1000,
  timeout_sec = 20,
  connection_retry = FALSE,
  max_plans = 3,
  per_plan_timeout = 20,
  randomize_order = FALSE
)

cat('strategy=', r$strategy, '\n', sep = '')
cat('notes=', paste(r$notes, collapse = ' | '), '\n', sep = '')
cat('has_df=', is.data.frame(r$data), ' rows=', if (is.data.frame(r$data)) nrow(r$data) else -1, '\n', sep = '')

if (is.data.frame(r$data) && nrow(r$data) > 0) {
  p <- prepare_occurrences(r$data, map_point_cap = 1000, sample_method = 'head')
  cat('mappable=', if (is.data.frame(p$data)) nrow(p$data) else 0, ' coord_valid=', p$qa$coord_valid, '\n', sep = '')
}
