dryad_or <- function(x, y) {
  if (is.null(x) || !length(x)) y else x
}

dryad_get_required_function <- function(name) {
  if (!exists(name, mode = "function", inherits = TRUE)) {
    stop(sprintf("%s() is not available. Source R/trait_dictionary.R and R/dryad_api.R first.", name), call. = FALSE)
  }
  get(name, mode = "function", inherits = TRUE)
}

dryad_canonical_name_local <- function(x) {
  dryad_get_required_function("dryad_canonical_name")(x)
}

dryad_trait_dictionary_lookup_local <- function(dictionary = NULL) {
  if (is.null(dictionary)) {
    dryad_get_required_function("dryad_trait_dictionary_lookup")()
  } else {
    dryad_get_required_function("dryad_trait_dictionary_lookup")(dictionary)
  }
}

dryad_now_utc_local <- function() {
  if (exists("dryad_now_utc", mode = "function", inherits = TRUE)) {
    return(get("dryad_now_utc", mode = "function", inherits = TRUE)())
  }
  format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

dryad_standardize_trait_label_local <- function(raw_trait_name, lookup) {
  dryad_get_required_function("dryad_standardize_trait_label")(raw_trait_name, lookup = lookup)
}

dryad_read_trait_dictionary_local <- function() {
  dryad_get_required_function("dryad_read_trait_dictionary")()
}

dryad_non_empty_string <- function(x) {
  values <- trimws(as.character(x))
  values[!nzchar(values)] <- NA_character_
  values
}

# Normalize a raw string into a proper "Genus species" binomial.
# Handles: lowercase (abies_concolor), ALL CAPS (ABIES_CONCOLOR), mixed case,
# underscore or space separators, and infraspecific epithets (var./ssp./subsp.).
# Returns a list:
#   $binomial           - "Genus species" or NA_character_ if not parseable
#   $infraspecific_rank - rank keyword ("var", "subsp", "f", etc.) or NA_character_
#   $infraspecific_epithet - infraspecific epithet token or NA_character_
dryad_normalize_binomial <- function(x) {
  NA_result <- list(binomial = NA_character_,
                    infraspecific_rank = NA_character_,
                    infraspecific_epithet = NA_character_)
  if (is.na(x) || !nzchar(trimws(x))) return(NA_result)
  x <- trimws(x)
  # Replace common separators and hybrid markers with spaces
  # (many Dryad files use dot-separated names like "Gustavia.superba")
  x <- gsub("[._\u00d7]", " ", x)
  x <- gsub("\\s+", " ", x)
  parts <- strsplit(x, " ")[[1]]
  if (length(parts) < 2L) return(NA_result)
  genus   <- parts[[1]]
  epithet <- parts[[2]]

  # Rank keywords checked BEFORE length guards so short epithets like 'f' are handled
  rank_keywords <- c("var", "var.", "ssp", "ssp.", "subsp", "subsp.",
                     "subvar", "subvar.", "f", "f.", "cf", "cf.", "aff", "aff.",
                     "sp", "sp.", "spp", "spp.", "nov", "x", "x.")
  # Unresolved-taxon markers: reject entirely (no true epithet can follow)
  unresolved_markers <- c("sp", "sp.", "spp", "spp.")

  infra_rank    <- NA_character_
  infra_epithet <- NA_character_

  if (tolower(epithet) %in% tolower(rank_keywords)) {
    if (tolower(epithet) %in% tolower(unresolved_markers)) return(NA_result)
    if (length(parts) < 3L) return(NA_result)
    infra_rank <- tolower(gsub("\\.", "", epithet))  # normalise: "var." -> "var"
    epithet    <- parts[[3]]
    # Capture any following infraspecific epithet (parts[4] onwards are authorship — ignored)
    infra_epithet <- tolower(epithet)
  } else {
    # Check if parts[3] is a rank keyword → capture as infraspecific
    if (length(parts) >= 4L && tolower(parts[[3]]) %in% tolower(rank_keywords) &&
        !tolower(parts[[3]]) %in% tolower(unresolved_markers)) {
      infra_rank    <- tolower(gsub("\\.", "", parts[[3]]))
      infra_epithet <- tolower(parts[[4]])
    }
  }

  # Length and digit guards
  if (nchar(genus) < 3L || nchar(epithet) < 2L) return(NA_result)
  if (grepl("[0-9]", genus) || grepl("[0-9]", epithet)) return(NA_result)

  # Title-case genus, lowercase epithet
  genus   <- paste0(toupper(substr(genus, 1, 1)), tolower(substr(genus, 2, nchar(genus))))
  epithet <- tolower(epithet)

  list(
    binomial           = paste(genus, epithet),
    infraspecific_rank = infra_rank,
    infraspecific_epithet = infra_epithet
  )
}

# Heuristic scan: find a column in df where most values look like binomials.
# Used as a last-resort fallback when no alias column was matched.
# Returns the column name or NA_character_.
dryad_find_species_column <- function(df, exclude_cols = character(0)) {
  # Pattern allows title-case both genus and epithet: "Quercus Robur" or "quercus robur"
  binomial_pattern <- "^[A-Za-z]{3,}[_ .][A-Za-z]{2,}"
  candidate_cols <- setdiff(names(df)[vapply(df, is.character, logical(1))], exclude_cols)
  best_col <- NA_character_
  best_frac <- 0.5  # require at least 50% of non-NA values to match
  for (col in candidate_cols) {
    vals <- trimws(as.character(df[[col]]))
    vals <- vals[nzchar(vals) & !is.na(vals)]
    if (!length(vals)) next
    frac <- mean(grepl(binomial_pattern, vals))
    if (frac > best_frac) {
      best_frac <- frac
      best_col <- col
    }
  }
  best_col
}

dryad_alias_map <- function() {
  list(
    scrubbed_species_binomial = c(
      # BIEN / Darwin Core standard
      "scrubbed_species_binomial", "scientificname", "scientific_name",
      "verbatimscientificname", "taxon_name_acc",
      # Common "species" variants
      "species", "species_name", "spp_name", "sp_name",
      "species_binomial", "binomial", "binomial_name",
      # Taxon / taxonomy variants
      "taxon", "taxon_name", "taxonomy", "taxonomic_name",
      "taxa", "taxon_label",
      # Latin name variants (canonical matching handles case/punct)
      "latin_name", "latin.name", "latinname", "latin_names",
      "latin", "latin_binomial",
      # Accepted / matched / resolved name variants
      "accepted_name", "accepted_species", "accepted_taxon",
      "name_matched", "matched_name", "matched_species",
      "resolved_name", "resolved_species", "final_name",
      "best_match", "best_name",
      # Phylogenetic / genomics naming
      "genus_species", "phylo_name", "tip_label", "tip_name",
      "otu_name", "otu_label",
      # Organism / plant naming
      "organism", "organism_name",
      "plant_name", "plant_species", "plant_taxon",
      "plantspp", "old.plantspp", "old_plantspp", "oldplantspp",
      "full_name", "fullname",
      # AusTraits / TRY style
      "AccSpeciesName", "SpeciesName", "species_binom"
    ),
    # Separate genus column — used to build full binomial when species is split
    genus = c("genus", "gen", "genus_name", "Genus", "genus_id"),
    # Specific epithet column — used when genus and epithet are in separate columns
    epithet = c(
      "specific_epithet", "specificepithet", "epithet",
      "species_epithet", "sp", "spp", "sp.", "spp."
    ),
    latitude = c(
      "latitude", "lat", "decimallatitude", "y",
      "lat_dd", "lat_deg", "latitude_dd", "latitude_deg", "latdd",
      "lat_wgs84", "latitude_wgs84", "site_lat", "site_latitude",
      "y_coord", "y_coordinate", "northing", "verbatimlatitude",
      "lat_n", "latitude_n", "ddlat", "gps_lat", "gps_latitude"
    ),
    longitude = c(
      "longitude", "lon", "long", "decimallongitude", "x",
      "lon_dd", "lon_deg", "long_dd", "longitude_dd", "longitude_deg", "londd",
      "lon_wgs84", "longitude_wgs84", "site_lon", "site_long", "site_longitude",
      "x_coord", "x_coordinate", "easting", "verbatimlongitude",
      "lon_e", "longitude_e", "ddlon", "gps_lon", "gps_longitude"
    ),
    elevation = c(
      "elevation", "altitude", "elev", "alt",
      "elevation_m", "elev_m", "altitude_m", "alt_m",
      "elevation_masl", "masl", "m_asl",
      "verbatimelevation", "minimumelevationinmeters", "maximumelevationinmeters",
      "verbatimaltitude", "site_elevation", "site_altitude", "site_elev",
      "mean_elevation", "elevation_ft"
    ),
    date_collected = c(
      "date_collected", "eventdate", "date", "collection_date", "sample_date",
      "year", "yr", "collection_year", "sample_year", "observation_year",
      "collectiondate", "samplingdate", "sampling_date", "date_sampled",
      "datesampled", "measurement_date", "measurementdate",
      "observation_date", "observationdate",
      "harvestdate", "harvest_date", "date_of_collection",
      "verbatimeventdate"
    ),
    country = c(
      # Darwin Core / BIEN standard
      "country", "countrycode", "country_code",
      # Descriptive variants
      "country_name", "nation", "nation_name", "country_of_collection",
      # ISO / abbreviation columns seen in ecological datasets
      "iso_country", "iso2", "iso3", "iso_a2", "iso_a3",
      # Common field name variants
      "sampling_country", "collection_country", "site_country"
    ),
    stateProvince = c(
      # Darwin Core / BIEN standard
      "stateprovince", "state_province",
      # Short forms
      "state", "province", "prov",
      # Regional / administrative
      "region", "administrative_area", "admin_area", "adm1",
      # Descriptive variants common in ecological CSVs
      "state_name", "province_name", "region_name",
      "sampling_region", "collection_state", "site_state",
      "state_province_name", "dept", "department"
    ),
    county = c(
      # Darwin Core / BIEN standard
      "county",
      # Administrative level 2 variants
      "municipality", "district", "adm2",
      # Common ecological field names
      "county_name", "municipality_name", "district_name",
      "subregion", "sub_region", "departamento", "comarca",
      "collection_county", "site_county"
    ),
    locality = c(
      # Darwin Core / BIEN standard
      "locality", "verbatimlocality",
      # Site / plot names (very common in trait datasets)
      "site", "site_name", "site_id", "site_code",
      "plot", "plot_name", "plot_id", "plot_code",
      # Generic location descriptors
      "location", "location_name", "location_id",
      "place", "place_name",
      # Descriptive / narrative
      "sampling_location", "collection_site", "observation_site",
      "habitat", "stand", "stand_name", "transect", "transect_name"
    ),
    trait_name = c(
      "trait_name", "trait", "measurementtype", "variable", "measurement_name",
      "measurementorfacttype", "parameter", "trait_id"
    ),
    trait_value = c(
      "trait_value", "value", "measurementvalue", "observation", "trait_measurement",
      "measurementorfactvalue", "trait_mean", "mean"
    ),
    unit = c(
      "unit", "units", "measurementunit", "trait_unit",
      "measurementorfactunit", "unit_of_measurement"
    ),
    dataset = c("dataset", "dataset_name", "study", "study_name"),
    datasource = c("datasource", "data_source", "source"),
    dataowner = c("dataowner", "data_owner", "owner", "authors"),
    collection_code = c(
      "collection_code", "collection", "site_code", "plot_code",
      "sample_id", "sample_code", "specimen_code"
    ),
    method = c("method", "measurement_method", "protocol", "methodology")
  )
}

# Scan companion README/metadata files in the same directory for column name hints.
# Returns a named list mapping canonical column name -> BIEN field name for any
# columns the README associates with lat/lon/date/elevation language.
dryad_readme_column_hints <- function(data_path, column_names) {
  dir_path <- dirname(data_path)
  readme_files <- list.files(dir_path, pattern = "(?i)(readme|metadata|codebook|data_dictionary|column)", full.names = TRUE)
  readme_files <- readme_files[!grepl(basename(data_path), readme_files, fixed = TRUE)]

  if (!length(readme_files)) return(list())

  hints <- list()
  lat_terms   <- "(?i)(latitude|decimal.?lat|lat.?coord|lat.?dd|gps.?lat|site.?lat|northing)"
  lon_terms   <- "(?i)(longitude|decimal.?lon|lon.?coord|lon.?dd|gps.?lon|site.?lon|easting)"
  elev_terms  <- "(?i)(elevation|altitude|masl|m\\.a\\.s\\.l)"
  date_terms  <- "(?i)(collection.?date|sampling.?date|date.?collected|event.?date|year.?of.?collection|harvest.?date)"

  for (readme_path in readme_files) {
    lines <- tryCatch(
      readLines(readme_path, warn = FALSE, encoding = "UTF-8"),
      error = function(e) tryCatch(
        readLines(readme_path, warn = FALSE, encoding = "latin1"),
        error = function(e2) character(0)
      )
    )
    if (!length(lines)) next

    for (col in column_names) {
      col_canon <- dryad_canonical_name_local(col)
      # Look for lines that mention this column name adjacent to a semantic keyword
      pattern <- paste0("(?i)\\b", gsub("_", "[_. -]?", col_canon), "\\b")
      matching_lines <- grep(pattern, lines, perl = TRUE, value = TRUE)
      if (!length(matching_lines)) next
      combined <- paste(matching_lines, collapse = " ")

      if (!col_canon %in% names(hints)) {
        if (grepl(lat_terms, combined, perl = TRUE))  hints[[col_canon]] <- "latitude"
        if (grepl(lon_terms, combined, perl = TRUE))  hints[[col_canon]] <- "longitude"
        if (grepl(elev_terms, combined, perl = TRUE)) hints[[col_canon]] <- "elevation"
        if (grepl(date_terms, combined, perl = TRUE)) hints[[col_canon]] <- "date_collected"
      }
    }
  }
  hints
}

# Augment guesses with README-derived hints, filling in only fields that are currently NA.
dryad_apply_readme_hints <- function(guesses, column_names, data_path) {
  hints <- dryad_readme_column_hints(data_path, column_names)
  if (!length(hints)) return(guesses)
  canon_cols <- dryad_canonical_name_local(column_names)
  for (canon in names(hints)) {
    field <- hints[[canon]]
    if (field %in% names(guesses) && (is.null(guesses[[field]]) || is.na(guesses[[field]]))) {
      original_col_index <- match(canon, canon_cols)
      if (!is.na(original_col_index)) {
        guesses[[field]] <- column_names[[original_col_index]]
      }
    }
  }
  guesses
}

dryad_find_alias_column <- function(column_names, aliases) {
  column_keys <- dryad_canonical_name_local(column_names)
  alias_keys <- dryad_canonical_name_local(aliases)
  match_index <- match(alias_keys, column_keys, nomatch = 0L)
  match_index <- match_index[match_index > 0L]
  if (!length(match_index)) {
    return(NA_character_)
  }
  column_names[[match_index[[1]]]]
}

dryad_guess_columns <- function(df, data_path = NULL) {
  alias_map <- dryad_alias_map()
  column_names <- names(df)
  guesses <- lapply(alias_map, function(aliases) dryad_find_alias_column(column_names, aliases))
  guesses <- as.list(guesses)
  # Augment with README hints for any fields still unresolved
  if (!is.null(data_path) && nzchar(data_path) && file.exists(data_path)) {
    guesses <- dryad_apply_readme_hints(guesses, column_names, data_path)
  }
  guesses
}

dryad_dictionary_trait_columns <- function(df, lookup = NULL) {
  if (is.null(lookup)) {
    lookup <- dryad_trait_dictionary_lookup_local()
  }
  column_names <- names(df)
  column_keys <- dryad_canonical_name_local(column_names)
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
    inferred_unit = rep(FALSE, size),
    method = rep(NA_character_, size),
    country = rep(NA_character_, size),
    stateProvince = rep(NA_character_, size),
    county = rep(NA_character_, size),
    locality = rep(NA_character_, size),
    elevation_m = rep(NA_real_, size),
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
    raw_elevation = rep(NA_character_, size),
    raw_country = rep(NA_character_, size),
    raw_stateProvince = rep(NA_character_, size),
    raw_county = rep(NA_character_, size),
    raw_locality = rep(NA_character_, size),
    raw_date_collected = rep(NA_character_, size),
    input_name_verbatim = rep(NA_character_, size),
    infraspecific_rank = rep(NA_character_, size),
    infraspecific_epithet = rep(NA_character_, size),
    source_column_taxon = rep(NA_character_, size),
    source_column_trait_name = rep(NA_character_, size),
    source_column_trait_value = rep(NA_character_, size),
    source_column_unit = rep(NA_character_, size),
    qa_flags = rep(NA_character_, size),
    stringsAsFactors = FALSE
  )
}

dryad_fill_common_fields <- function(output, base_df, row_index, guesses, provenance, raw_trait_name, raw_trait_value, raw_unit, trait_match) {
  # --- Species binomial resolution ---
  # CAPTURE VERBATIM SOURCE VALUE BEFORE ANY NORMALIZATION
  input_name_verbatim <- if (!is.null(guesses$scrubbed_species_binomial) &&
                             !is.na(guesses$scrubbed_species_binomial)) {
    dryad_non_empty_string(base_df[[guesses$scrubbed_species_binomial]])[[1]]
  } else {
    NA_character_
  }
  
  # Track which column ultimately resolved the binomial (updated as we progress through steps)
  resolved_source_column <- guesses$scrubbed_species_binomial
  
  # Helper: get a trimmed character value from a column if column is mapped
  .col_val <- function(col_guess) {
    if (!is.null(col_guess) && !is.na(col_guess))
      trimws(as.character(base_df[[col_guess]][[1]]))
    else
      NA_character_
  }

  # Step 1: get the raw candidate value from the alias-matched column
  raw_binomial_candidate <- input_name_verbatim

  # Helper: call normalizer and test if it succeeded
  .norm <- function(s) dryad_normalize_binomial(s)
  .binomial <- function(parsed) parsed$binomial

  # Step 1b: normalize via dryad_normalize_binomial (handles lowercase, ALL CAPS,
  # underscore separators, and infraspecific epithets like var./ssp.)
  parsed <- .norm(raw_binomial_candidate)
  if (!is.na(.binomial(parsed))) {
    raw_binomial_candidate <- .binomial(parsed)
  }

  # Step 2: if still no valid binomial, try prepending genus from separate genus column
  if (is.na(.binomial(parsed))) {
    genus_val <- .col_val(guesses$genus)
    if (!is.na(genus_val) && nzchar(genus_val)) {
      parsed2 <- .norm(paste(genus_val, raw_binomial_candidate))
      if (!is.na(.binomial(parsed2))) {
        parsed <- parsed2
        raw_binomial_candidate <- .binomial(parsed2)
        resolved_source_column <- "genus_prepend"
      }
    }
  }

  # Step 2b: try constructing from separate genus + epithet columns
  if (is.na(.binomial(parsed))) {
    genus_val   <- .col_val(guesses$genus)
    epithet_val <- .col_val(guesses$epithet)
    if (!is.na(genus_val) && nzchar(genus_val) &&
        !is.na(epithet_val) && nzchar(epithet_val)) {
      parsed3 <- .norm(paste(genus_val, epithet_val))
      if (!is.na(.binomial(parsed3))) {
        parsed <- parsed3
        raw_binomial_candidate <- .binomial(parsed3)
        resolved_source_column <- paste(guesses$genus, "+", guesses$epithet, sep="")
      }
    }
  }

  # Step 2c: heuristic fallback — scan character columns for one that looks like
  # a species name column (>50% of values match binomial pattern)
  if (is.na(.binomial(parsed))) {
    already_mapped <- unlist(guesses[!is.na(guesses)])
    fallback_col <- dryad_find_species_column(base_df, exclude_cols = already_mapped)
    if (!is.na(fallback_col)) {
      fallback_val <- dryad_non_empty_string(base_df[[fallback_col]])[[1]]
      parsed4 <- .norm(fallback_val)
      if (!is.na(.binomial(parsed4))) {
        parsed <- parsed4
        raw_binomial_candidate <- .binomial(parsed4)
        resolved_source_column <- fallback_col
      }
    }
  }

  # Step 3: write resolved fields
  output$scrubbed_species_binomial[[row_index]] <- .binomial(parsed)
  output$infraspecific_rank[[row_index]]        <- parsed$infraspecific_rank
  output$infraspecific_epithet[[row_index]]     <- parsed$infraspecific_epithet
  output$latitude[[row_index]] <- suppressWarnings(as.numeric(if (!is.na(guesses$latitude)) base_df[[guesses$latitude]][[1]] else NA))
  output$longitude[[row_index]] <- suppressWarnings(as.numeric(if (!is.na(guesses$longitude)) base_df[[guesses$longitude]][[1]] else NA))
  output$date_collected[[row_index]] <- if (!is.na(guesses$date_collected)) dryad_non_empty_string(base_df[[guesses$date_collected]])[[1]] else NA_character_
  output$dataset[[row_index]] <- if (!is.na(guesses$dataset)) dryad_non_empty_string(base_df[[guesses$dataset]])[[1]] else dryad_or(provenance$dryad_dataset_doi, dryad_or(provenance$source_title, NA_character_))
  output$datasource[[row_index]] <- if (!is.na(guesses$datasource)) dryad_non_empty_string(base_df[[guesses$datasource]])[[1]] else "Dryad"
  output$dataowner[[row_index]] <- if (!is.na(guesses$dataowner)) dryad_non_empty_string(base_df[[guesses$dataowner]])[[1]] else dryad_or(provenance$source_authors, NA_character_)
  output$collection_code[[row_index]] <- if (!is.na(guesses$collection_code)) dryad_non_empty_string(base_df[[guesses$collection_code]])[[1]] else NA_character_
  output$method[[row_index]] <- if (!is.na(guesses$method)) dryad_non_empty_string(base_df[[guesses$method]])[[1]] else NA_character_
  output$country[[row_index]] <- if (!is.na(guesses$country)) dryad_non_empty_string(base_df[[guesses$country]])[[1]] else NA_character_
  output$stateProvince[[row_index]] <- if (!is.na(guesses$stateProvince)) dryad_non_empty_string(base_df[[guesses$stateProvince]])[[1]] else NA_character_
  output$county[[row_index]] <- if (!is.na(guesses$county)) dryad_non_empty_string(base_df[[guesses$county]])[[1]] else NA_character_
  output$locality[[row_index]] <- if (!is.na(guesses$locality)) dryad_non_empty_string(base_df[[guesses$locality]])[[1]] else NA_character_
  output$elevation_m[[row_index]] <- suppressWarnings(as.numeric(if (!is.null(guesses$elevation) && !is.na(guesses$elevation)) base_df[[guesses$elevation]][[1]] else NA))
  output$trait_name[[row_index]] <- trait_match$standardized_trait_name
  output$trait_value[[row_index]] <- dryad_non_empty_string(raw_trait_value)
  raw_unit_clean <- dryad_non_empty_string(raw_unit)
  use_standard_unit <- is.na(raw_unit_clean) && !is.na(trait_match$standard_unit)
  output$unit[[row_index]] <- dryad_non_empty_string(if (!is.na(raw_unit)) raw_unit else trait_match$standard_unit)
  output$inferred_unit[[row_index]] <- use_standard_unit
  output$expected_unit_class[[row_index]] <- trait_match$expected_unit_class
  output$value_type[[row_index]] <- trait_match$value_type
  output$standard_unit[[row_index]] <- trait_match$standard_unit
  output$trait_dictionary_notes[[row_index]] <- trait_match$notes
  output$dryad_dataset_doi[[row_index]] <- dryad_or(provenance$dryad_dataset_doi, NA_character_)
  output$dryad_version_id[[row_index]] <- suppressWarnings(as.integer(dryad_or(provenance$dryad_version_id, NA_integer_)))
  output$dryad_file_id[[row_index]] <- suppressWarnings(as.integer(dryad_or(provenance$dryad_file_id, NA_integer_)))
  output$source_title[[row_index]] <- dryad_or(provenance$source_title, NA_character_)
  output$source_authors[[row_index]] <- dryad_or(provenance$source_authors, NA_character_)
  output$source_subjects[[row_index]] <- dryad_or(provenance$source_subjects, NA_character_)
  output$source_abstract[[row_index]] <- dryad_or(provenance$source_abstract, NA_character_)
  output$download_timestamp_utc[[row_index]] <- dryad_or(provenance$download_timestamp_utc, dryad_now_utc_local())
  output$source_file_path[[row_index]] <- dryad_or(provenance$source_file_path, NA_character_)
  output$original_row_number[[row_index]] <- suppressWarnings(as.integer(base_df$.dryad_original_row_number[[1]]))
  # raw_taxon: preserve whatever was in the original source column (code, epithet, or full name)
  output$raw_taxon[[row_index]] <- if (!is.na(raw_binomial_candidate)) raw_binomial_candidate else {
    if (!is.na(guesses$scrubbed_species_binomial)) dryad_non_empty_string(base_df[[guesses$scrubbed_species_binomial]])[[1]] else NA_character_
  }
  output$raw_trait_name[[row_index]] <- dryad_non_empty_string(raw_trait_name)
  output$raw_trait_value[[row_index]] <- dryad_non_empty_string(raw_trait_value)
  output$raw_unit[[row_index]] <- dryad_non_empty_string(raw_unit)
  output$raw_latitude[[row_index]] <- if (!is.na(guesses$latitude)) dryad_non_empty_string(base_df[[guesses$latitude]])[[1]] else NA_character_
  output$raw_longitude[[row_index]] <- if (!is.na(guesses$longitude)) dryad_non_empty_string(base_df[[guesses$longitude]])[[1]] else NA_character_
  output$raw_elevation[[row_index]] <- if (!is.null(guesses$elevation) && !is.na(guesses$elevation)) dryad_non_empty_string(base_df[[guesses$elevation]])[[1]] else NA_character_
  output$raw_country[[row_index]] <- if (!is.na(guesses$country)) dryad_non_empty_string(base_df[[guesses$country]])[[1]] else NA_character_
  output$raw_stateProvince[[row_index]] <- if (!is.na(guesses$stateProvince)) dryad_non_empty_string(base_df[[guesses$stateProvince]])[[1]] else NA_character_
  output$raw_county[[row_index]] <- if (!is.na(guesses$county)) dryad_non_empty_string(base_df[[guesses$county]])[[1]] else NA_character_
  output$raw_locality[[row_index]] <- if (!is.na(guesses$locality)) dryad_non_empty_string(base_df[[guesses$locality]])[[1]] else NA_character_
  output$raw_date_collected[[row_index]] <- if (!is.na(guesses$date_collected)) dryad_non_empty_string(base_df[[guesses$date_collected]])[[1]] else NA_character_
  output$input_name_verbatim[[row_index]] <- input_name_verbatim
  output$source_column_taxon[[row_index]] <- resolved_source_column
  output$source_column_trait_name[[row_index]] <- dryad_or(provenance$source_column_trait_name, raw_trait_name)
  output$source_column_trait_value[[row_index]] <- dryad_or(provenance$source_column_trait_value, guesses$trait_value)
  output$source_column_unit[[row_index]] <- dryad_or(provenance$source_column_unit, guesses$unit)
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
    trait_match <- dryad_standardize_trait_label_local(raw_trait_name, lookup = trait_lookup)
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

  # Skip boolean flag columns (>50% of non-NA values are "yes"/"no"/"true"/"false")
  BOOL_FLAG_TOKENS <- c("yes", "no", "true", "false", "y", "n")
  trait_columns <- Filter(function(col) {
    vals <- trimws(tolower(as.character(df[[col]])))
    vals <- vals[nzchar(vals) & vals != "na"]
    if (!length(vals)) return(FALSE)
    bool_frac <- mean(vals %in% BOOL_FLAG_TOKENS)
    bool_frac < 0.5
  }, trait_columns)
  if (!length(trait_columns)) return(NULL)

  total_rows <- nrow(df) * length(trait_columns)
  output <- dryad_make_observation_table(total_rows)
  out_index <- 1L

  for (trait_column in trait_columns) {
    trait_match <- dryad_standardize_trait_label_local(trait_column, lookup = trait_lookup)
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

dryad_standardize_records <- function(df, provenance = list(), dictionary = NULL) {
  if (!is.data.frame(df) || !nrow(df) || !ncol(df)) {
    return(dryad_make_observation_table(0L))
  }

  if (is.null(dictionary)) {
    dictionary <- dryad_read_trait_dictionary_local()
  }

  working_df <- df
  working_df$.dryad_original_row_number <- seq_len(nrow(working_df))
  data_path <- dryad_or(provenance$source_file_path, NULL)
  guesses <- dryad_guess_columns(working_df, data_path = data_path)
  trait_lookup <- dryad_trait_dictionary_lookup_local(dictionary)

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
