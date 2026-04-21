shinyApp <- function(...) NULL
source('app.R', local = TRUE)

species <- 'Sequoia sempervirens'
cat('Species:', species, '\n\n')

# 1) Raw BIEN SQL totals
q_total <- sprintf("SELECT COUNT(*) AS n FROM view_full_occurrence_individual WHERE scrubbed_species_binomial = '%s';", species)
q_latlon <- sprintf("SELECT COUNT(*) AS n FROM view_full_occurrence_individual WHERE scrubbed_species_binomial = '%s' AND latitude IS NOT NULL AND longitude IS NOT NULL;", species)
q_strict <- sprintf("SELECT COUNT(*) AS n FROM view_full_occurrence_individual WHERE scrubbed_species_binomial = '%s' AND (is_introduced=0 OR is_introduced IS NULL) AND latitude IS NOT NULL AND longitude IS NOT NULL;", species)
q_geovalid <- sprintf("SELECT COUNT(*) AS n FROM view_full_occurrence_individual WHERE scrubbed_species_binomial = '%s' AND (is_introduced=0 OR is_introduced IS NULL) AND latitude IS NOT NULL AND longitude IS NOT NULL AND geovalid = 1;", species)
q_noncentroid <- sprintf("SELECT COUNT(*) AS n FROM view_full_occurrence_individual WHERE scrubbed_species_binomial = '%s' AND (is_introduced=0 OR is_introduced IS NULL) AND latitude IS NOT NULL AND longitude IS NOT NULL AND geovalid = 1 AND (georef_protocol IS NULL OR georef_protocol<>'county centroid') AND (is_centroid IS NULL OR is_centroid=0);", species)

cat('DB total:', BIEN:::.BIEN_sql(q_total, fetch.query = FALSE)$n[1], '\n')
cat('DB with lat/lon:', BIEN:::.BIEN_sql(q_latlon, fetch.query = FALSE)$n[1], '\n')
cat('DB strict native + lat/lon:', BIEN:::.BIEN_sql(q_strict, fetch.query = FALSE)$n[1], '\n')
cat('DB strict + geovalid:', BIEN:::.BIEN_sql(q_geovalid, fetch.query = FALSE)$n[1], '\n')
cat('DB strict + geovalid + non-centroid:', BIEN:::.BIEN_sql(q_noncentroid, fetch.query = FALSE)$n[1], '\n\n')

# 2) App query function output
occ <- query_occurrence_randomized(
  species_name = species,
  cultivated = FALSE,
  natives_only = TRUE,
  only_geovalid = TRUE,
  limit = 2400,
  record_limit = 2400,
  randomize_order = FALSE
)
cat('query_occurrence_randomized rows:', if (is.data.frame(occ)) nrow(occ) else NA, '\n')

prep <- prepare_occurrences(occ, map_point_cap = 1000, sample_method = 'head')
cat('prepare_occurrences mappable rows:', if (is.data.frame(prep$data)) nrow(prep$data) else 0, '\n')
cat('QA total:', prep$qa$total, '\n')
cat('QA coord_valid:', prep$qa$coord_valid, '\n')
cat('QA kept:', prep$qa$kept, '\n')
cat('QA removed_invalid:', prep$qa$removed_invalid, '\n')
cat('QA duplicates_removed:', prep$qa$duplicates_removed, '\n')

if (is.data.frame(occ) && nrow(occ) > 0) {
  lat_col <- find_first_col(occ, c('latitude','lat','decimalLatitude'))
  lon_col <- find_first_col(occ, c('longitude','lon','decimalLongitude'))
  cat('Detected lat col:', lat_col, '| lon col:', lon_col, '\n')
  if (!is.null(lat_col) && !is.null(lon_col)) {
    cat('Non-NA lat:', sum(!is.na(occ[[lat_col]])), 'Non-NA lon:', sum(!is.na(occ[[lon_col]])), '\n')
  }
}
