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

t0 <- Sys.time()
out <- query_occurrence_with_fallback(
  species_name = 'Eschscholzia californica',
  input = cfg,
  occ_limit = 2400,
  occ_page_size = 1000,
  timeout_sec = 20,
  connection_retry = FALSE,
  max_plans = 3,
  per_plan_timeout = 20,
  randomize_order = FALSE
)
dt <- round(as.numeric(difftime(Sys.time(), t0, units = 'secs')), 2)
rows <- if (is.list(out) && is.data.frame(out$data)) nrow(out$data) else NA
strat <- if (is.list(out) && !is.null(out$strategy)) out$strategy else 'none'
cat('strategy=', strat, ' rows=', rows, ' elapsed=', dt, 's\n', sep = '')
if (is.list(out) && !is.null(out$notes)) {
  cat('notes:\n')
  cat(paste(out$notes, collapse='\n'), '\n')
}

t1 <- Sys.time()
count_info <- count_occurrence_records(
  species_name = 'Eschscholzia californica',
  cultivated = FALSE,
  natives_only = TRUE,
  only_geovalid = TRUE,
  timeout_sec = 20
)
dt2 <- round(as.numeric(difftime(Sys.time(), t1, units = 'secs')), 2)
cat('count_total=', count_info$total, ' note=', count_info$note, ' elapsed=', dt2, 's\n', sep = '')
