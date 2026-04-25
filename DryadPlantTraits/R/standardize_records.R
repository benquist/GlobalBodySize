dryad_non_empty_string <- function(x) {
  values <- trimws(as.character(x))
  values[!nzchar(values)] <- NA_character_
  values
}

dryad_alias_map <- function() {
  list(
    scrubbed_species_binomial = c("scrubbed_species_binomial", "scientificname", "scientific_name", "species", "species_name", "taxon", "taxon_name", "accepted_name"),
    latitude = c("latitude", "lat", "decimallatitude", "y"),
    longitude = c("longitude", "lon", "long", "decimallongitude", "x"),
    date_collected = c("date_collected", "eventdate", "date", "collection_date", "sample_date"),
    country = c("country", "country_name"),
    stateProvince = c("stateprovince", "state_province", "state", "province"),
    county = c("county", "municipality"),
    locality = c("locality", "site", "site_name", "plot", "plot_name", "location"),
    trait_name = c("trait_name", "trait", "measurementtype", "variable", "measurement_name"),
    trait_value = c("trait_value", "value", "measurementvalue", "observation", "trait_measurement"),
    unit = c("unit", "units", "measurementunit", "trait_unit"),
    dataset = c("dataset", "dataset_name", "study", "study_name"),
    datasource = c("datasource", "data_source", "source"),
    dataowner = c("dataowner", "data_owner", "owner", "authors"),
    collection_code = c("collection_code", "collection", "site_code", "plot_code"),
    method = c("method", "measurement_method", "protocol")
  )
}

dryad_find_alias_column <- function(column_names, aliases) {
  column_keys <- dryad_canonical_name(column_names)
  alias_keys <- dryad_canonical_name(aliases)
  match_index <- match(alias_keys, column_keys, nomatch = 0L)
  match_index <- match_index[match_index > 0L]
  if (!length(match_index)) {
    return(NA_character_)
  }
  column_names[[match_index[[1]]]]
}

dryad_guess_columns <- function(df) {
  alias_map <- dryad_alias_map()
  column_names <- names(df)
  guesses <- lapply(alias_map, function(aliases) dryad_find_alias_column(column_names, aliases))
  as.list(guesses)
}

dryad_dictionary_trait_columns <- function(df, lookup = dryad_trait_dictionary_lookup()) {
  column_names <- names(df)
  column_keys <- dryad_canonical_name(column_names)
  matched <- vapply(column_keys, function(key) !is.null(lookup[[key]]), logical(1))
  column_names[matched]
}

dryad_metadata_value <- function(df, column_name, default = NA_character_) {
  if (is.na(column_name) || !nzchar(column_name) || !column_name %in% names(df)) {
    return(rep(default, nrow(df)))
  }
  dryad_non_empty_string(df[[column_name]])
}

dryad_make_observation_table <- function(size) {
  data.frame(
    scrubbed_species_binomial = rep(NA_character_, size),
    latitude = rep(NA_real_, size),
    longitude = rep(NA_real_, size),
    date_collected = rep(NA_character_, size),
    dataset = rep(NA_character_, size),
    datasource = rep(NA_character_, size),
    dataowner = rep(NA_character_, size),
    collection_code = rep(NA_character_, size),
    trait_name = rep(NA_character_, size),
    trait_value = rep(NA_character_, size),
    unit = rep(NA_character_, size),
    method = rep(NA_character_, size),
    country = rep(NA_character_, size),
    stateProvince = rep(NA_character_, size),
    county = rep(NA_character_, size),
    locality = rep(NA_character_, size),
    expected_unit_class = rep(NA_character_, size),
    value_type = rep(NA_character_, size),
    standard_unit = rep(NA_character_, size),
    trait_dictionary_notes = rep(NA_character_, size),
    dryad_dataset_doi = rep(NA_character_, size),
    dryad_version_id = rep(NA_integer_, size),
    dryad_file_id = rep(NA_integer_, size),
    source_title = rep(NA_character_, size),
    source_authors = rep(NA_character_, size),
    source_subjects = rep(NA_character_, size),
    source_abstract = rep(NA_character_, size),
    download_timestamp_utc = rep(NA_character_, size),
    source_file_path = rep(NA_character_, size),
    original_row_number = rep(NA_integer_, size),
    raw_taxon = rep(NA_character_, size),
    raw_trait_name = rep(NA_character_, size),
    raw_trait_value = rep(NA_character_, size),
    raw_unit = rep(NA_character_, size),
    raw_latitude = rep(NA_character_, size),
    raw_longitude = rep(NA_character_, size),
    raw_country = rep(NA_character_, size),
    raw_stateProvince = rep(NA_character_, size),
    raw_county = rep(NA_character_, size),
    raw_locality = rep(NA_character_, size),
    raw_date_collected = rep(NA_character_, size),
    source_column_taxon = rep(NA_character_, size),
    source_column_trait_name = rep(NA_character_, size),
    source_column_trait_value = rep(NA_character_, size),
    source_column_unit = rep(NA_character_, size),
    stringsAsFactors = FALSE
  )
}

dryad_fill_common_fields <- function(output, base_df, row_index, guesses, provenance, raw_trait_name, raw_trait_value, raw_unit, trait_match) {
  output$scrubbed_species_binomial[[row_index]] <- if (!is.na(guesses$scrubbed_species_binomial)) dryad_non_empty_string(base_df[[guesses$scrubbed_species_binomial]])[[1]] else NA_character_
  output$latitude[[row_index]] <- suppressWarnings(as.numeric(if (!is.na(guesses$latitude)) base_df[[guesses$latitude]][[1]] else NA))
  output$longitude[[row_index]] <- suppressWarnings(as.numeric(if (!is.na(guesses$longitude)) base_df[[guesses$longitude]][[1]] else NA))
  output$date_collected[[row_index]] <- if (!is.na(guesses$date_collected)) dryad_non_empty_string(base_df[[guesses$date_collected]])[[1]] else NA_character_
  output$dataset[[row_index]] <- if (!is.na(guesses$dataset)) dryad_non_empty_string(base_df[[guesses$dataset]])[[1]] else provenance$dryad_dataset_doi %||% provenance$source_title %||% NA_character_
  output$datasource[[row_index]] <- if (!is.na(guesses$datasource)) dryad_non_empty_string(base_df[[guesses$datasource]])[[1]] else "Dryad"
  output$dataowner[[row_index]] <- if (!is.na(guesses$dataowner)) dryad_non_empty_string(base_df[[guesses$dataowner]])[[1]] else provenance$source_authors %||% NA_character_
  output$collection_code[[row_index]] <- if (!is.na(guesses$collection_code)) dryad_non_empty_string(base_df[[guesses$collection_code]])[[1]] else NA_character_
  output$method[[row_index]] <- if (!is.na(guesses$method)) dryad_non_empty_string(base_df[[guesses$method]])[[1]] else NA_character_
  output$country[[row_index]] <- if (!is.na(guesses$country)) dryad_non_empty_string(base_df[[guesses$country]])[[1]] else NA_character_
  output$stateProvince[[row_index]] <- if (!is.na(guesses$stateProvince)) dryad_non_empty_string(base_df[[guesses$stateProvince]])[[1]] else NA_character_
  output$county[[row_index]] <- if (!is.na(guesses$county)) dryad_non_empty_string(base_df[[guesses$county]])[[1]] else NA_character_
  output$locality[[row_index]] <- if (!is.na(guesses$locality)) dryad_non_empty_string(base_df[[guesses$locality]])[[1]] else NA_character_
  output$trait_name[[row_index]] <- trait_match$standardized_trait_name
  output$trait_value[[row_index]] <- dryad_non_empty_string(raw_trait_value)
  output$unit[[row_index]] <- dryad_non_empty_string(if (!is.na(raw_unit)) raw_unit else trait_match$standard_unit)
  output$expected_unit_class[[row_index]] <- trait_match$expected_unit_class
  output$value_type[[row_index]] <- trait_match$value_type
  output$standard_unit[[row_index]] <- trait_match$standard_unit
  output$trait_dictionary_notes[[row_index]] <- trait_match$notes
  output$dryad_dataset_doi[[row_index]] <- provenance$dryad_dataset_doi %||% NA_character_
  output$dryad_version_id[[row_index]] <- suppressWarnings(as.integer(provenance$dryad_version_id %||% NA_integer_))
  output$dryad_file_id[[row_index]] <- suppressWarnings(as.integer(provenance$dryad_file_id %||% NA_integer_))
  output$source_title[[row_index]] <- provenance$source_title %||% NA_character_
  output$source_authors[[row_index]] <- provenance$source_authors %||% NA_character_
  output$source_subjects[[row_index]] <- provenance$source_subjects %||% NA_character_
  output$source_abstract[[row_index]] <- provenance$source_abstract %||% NA_character_
  output$download_timestamp_utc[[row_index]] <- provenance$download_timestamp_utc %||% dryad_now_utc()
  output$source_file_path[[row_index]] <- provenance$source_file_path %||% NA_character_
  output$original_row_number[[row_index]] <- suppressWarnings(as.integer(base_df$.dryad_original_row_number[[1]]))
  output$raw_taxon[[row_index]] <- if (!is.na(guesses$scrubbed_species_binomial)) dryad_non_empty_string(base_df[[guesses$scrubbed_species_binomial]])[[1]] else NA_character_
  output$raw_trait_name[[row_index]] <- dryad_non_empty_string(raw_trait_name)
  output$raw_trait_value[[row_index]] <- dryad_non_empty_string(raw_trait_value)
  output$raw_unit[[row_index]] <- dryad_non_empty_string(raw_unit)
  output$raw_latitude[[row_index]] <- if (!is.na(guesses$latitude)) dryad_non_empty_string(base_df[[guesses$latitude]])[[1]] else NA_character_
  output$raw_longitude[[row_index]] <- if (!is.na(guesses$longitude)) dryad_non_empty_string(base_df[[guesses$longitude]])[[1]] else NA_character_
  output$raw_country[[row_index]] <- if (!is.na(guesses$country)) dryad_non_empty_string(base_df[[guesses$country]])[[1]] else NA_character_
  output$raw_stateProvince[[row_index]] <- if (!is.na(guesses$stateProvince)) dryad_non_empty_string(base_df[[guesses$stateProvince]])[[1]] else NA_character_
  output$raw_county[[row_index]] <- if (!is.na(guesses$county)) dryad_non_empty_string(base_df[[guesses$county]])[[1]] else NA_character_
  output$raw_locality[[row_index]] <- if (!is.na(guesses$locality)) dryad_non_empty_string(base_df[[guesses$locality]])[[1]] else NA_character_
  output$raw_date_collected[[row_index]] <- if (!is.na(guesses$date_collected)) dryad_non_empty_string(base_df[[guesses$date_collected]])[[1]] else NA_character_
  output$source_column_taxon[[row_index]] <- guesses$scrubbed_species_binomial
  output$source_column_trait_name[[row_index]] <- provenance$source_column_trait_name %||% raw_trait_name
  output$source_column_trait_value[[row_index]] <- provenance$source_column_trait_value %||% guesses$trait_value
  output$source_column_unit[[row_index]] <- provenance$source_column_unit %||% guesses$unit
  output
}

dryad_standardize_long_records <- function(df, guesses, provenance, trait_lookup) {
  trait_name_col <- guesses$trait_name
  trait_value_col <- guesses$trait_value
  unit_col <- guesses$unit

  if (is.na(trait_name_col) || is.na(trait_value_col)) {
    return(NULL)
  }

  output <- dryad_make_observation_table(nrow(df))

  for (row_index in seq_len(nrow(df))) {
    base_row <- df[row_index, , drop = FALSE]
    raw_trait_name <- as.character(base_row[[trait_name_col]][[1]])
    raw_trait_value <- as.character(base_row[[trait_value_col]][[1]])
    raw_unit <- if (!is.na(unit_col)) as.character(base_row[[unit_col]][[1]]) else NA_character_
    trait_match <- dryad_standardize_trait_label(raw_trait_name, lookup = trait_lookup)
    row_provenance <- c(provenance, list(
      source_column_trait_name = trait_name_col,
      source_column_trait_value = trait_value_col,
      source_column_unit = unit_col
    ))
    output <- dryad_fill_common_fields(output, base_row, row_index, guesses, row_provenance, raw_trait_name, raw_trait_value, raw_unit, trait_match)
  }

  keep <- !(is.na(output$trait_value) | output$trait_value == "")
  output[keep, , drop = FALSE]
}

dryad_standardize_wide_records <- function(df, guesses, provenance, trait_lookup) {
  trait_columns <- setdiff(dryad_dictionary_trait_columns(df, lookup = trait_lookup), unlist(guesses, use.names = FALSE))
  if (!length(trait_columns)) {
    return(NULL)
  }

  total_rows <- nrow(df) * length(trait_columns)
  output <- dryad_make_observation_table(total_rows)
  out_index <- 1L

  for (trait_column in trait_columns) {
    trait_match <- dryad_standardize_trait_label(trait_column, lookup = trait_lookup)
    for (row_index in seq_len(nrow(df))) {
      raw_trait_value <- as.character(df[[trait_column]][[row_index]])
      if (!nzchar(trimws(raw_trait_value)) || identical(raw_trait_value, "NA")) {
        next
      }

      base_row <- df[row_index, , drop = FALSE]
      row_provenance <- c(provenance, list(source_column_trait_value = trait_column, source_column_unit = guesses$unit))
      output <- dryad_fill_common_fields(output, base_row, out_index, guesses, row_provenance, trait_column, raw_trait_value, if (!is.na(guesses$unit)) as.character(base_row[[guesses$unit]][[1]]) else NA_character_, trait_match)
      out_index <- out_index + 1L
    }
  }

  output[seq_len(max(out_index - 1L, 0L)), , drop = FALSE]
}

dryad_standardize_records <- function(df, provenance = list(), dictionary = dryad_read_trait_dictionary()) {
  if (!is.data.frame(df) || !nrow(df) || !ncol(df)) {
    return(dryad_make_observation_table(0L))
  }

  working_df <- df
  working_df$.dryad_original_row_number <- seq_len(nrow(working_df))
  guesses <- dryad_guess_columns(working_df)
  trait_lookup <- dryad_trait_dictionary_lookup(dictionary)

  long_result <- dryad_standardize_long_records(working_df, guesses, provenance, trait_lookup)
  if (!is.null(long_result) && nrow(long_result)) {
    return(long_result)
  }

  wide_result <- dryad_standardize_wide_records(working_df, guesses, provenance, trait_lookup)
  if (!is.null(wide_result) && nrow(wide_result)) {
    return(wide_result)
  }

  dryad_make_observation_table(0L)
}
