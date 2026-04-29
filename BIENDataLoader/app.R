library(shiny)
library(DT)
library(httr)
library(jsonlite)

# Allow larger uploads on shinyapps while keeping in-app warnings for large files.
options(shiny.maxRequestSize = 100 * 1024^2)

# ── Cloudflare Worker relay URLs (replace YOUR_SUBDOMAIN with your workers.dev account name) ──
TNRS_URL <- "https://bien-relay-tnrs.benquist.workers.dev"
GNRS_URL <- "https://bien-relay-gnrs.benquist.workers.dev"
GVS_URL  <- "https://bien-relay-gvs.benquist.workers.dev"
NSR_URL  <- "https://bien-relay-nsr.benquist.workers.dev"

if (any(grepl("YOUR_SUBDOMAIN", c(TNRS_URL, GNRS_URL, GVS_URL, NSR_URL)))) {
  warning("[BIEN Data Loader] CF Worker URLs still contain 'YOUR_SUBDOMAIN' placeholder. ",
          "Edit the *_URL constants at the top of app.R before deploying.")
}

# ── Static field lists ────────────────────────────────────────────────────────

BIEN_STAGING_FIELDS <- c(
  # Taxonomy — populated by TNRS (scrubbed_* fields from BIEN DB view_full_occurrence_individual)
  "scrubbed_species_binomial", "scrubbed_family", "scrubbed_genus",
  "scrubbed_author", "scrubbed_taxonomic_status",
  # Verbatim name — captured before TNRS scrubbing; intentionally NOT overwritten by TNRS
  "verbatim_scientific_name",
  # Coordinates
  "latitude", "longitude",
  # GVS coordinate QA — BIEN DB field is_centroid (filtered: WHERE is_centroid IS NULL OR is_centroid=0)
  "is_centroid",
  # Temporal
  "date_collected",
  # Dataset provenance
  "dataset", "datasource", "dataowner", "collection_code",
  # Geography — populated by GNRS (BIEN DB: country, state_province, county)
  "locality", "country", "state_province", "county", "plot_name",
  # Record identifiers
  "occurrenceID", "basisOfRecord",
  # NSR native status — BIEN DB .native_check fields
  "native_status", "native_status_reason",
  "native_status_country", "native_status_state_province", "native_status_county_parish",
  "is_introduced",
  # NSR cultivated status — BIEN DB .cultivated_check: is_cultivated_observation
  "is_cultivated_observation",
  # Verbatim / elevation
  "verbatimLocality", "verbatimElevation",
  "elevation_min", "elevation_max",
  # ── Plot Structure (vegetation survey fields; canonical BIEN plot view: plot_area_ha, subplot, individual_count, coord_uncertainty_m, sampling_protocol) ──
  "cover",                # Percent cover of taxon in plot (0–100) — extension field
  "cover_total",          # Total vegetation cover in plot (0–100; stand-level) — extension field
  "relative_cover",       # Cover of taxon relative to all taxa in plot (0–100) — extension field
  "individual_count",     # BIEN plot view: number of individuals of the taxon in plot
  "stem_count",           # Number of stems counted (clonal taxa) — extension field
  "plot_area_ha",         # BIEN plot view: plot surveyed area in hectares
  "plot_size_m2",         # Plot area in m² (pass-through; convert to ha for BIEN ingest) — extension field
  "basal_area_m2ha",      # Stand basal area in m²/ha (plot-level aggregate) — extension field
  "coord_uncertainty_m",  # BIEN plot view: coordinate uncertainty in meters
  "sampling_protocol",    # BIEN plot view: sampling protocol / methodology
  # ── Individual Plant Metrics ──────────────────────────────────────────────
  "height_m",             # Plant height in meters — extension field
  "dbh_cm",               # Diameter at breast height (1.3 m) in cm — extension field
  "stratum",              # Vertical stratum: canopy/subcanopy/shrub/herb/ground — extension field
  "subplot",              # BIEN plot view: subplot or sub-quadrat identifier within the main plot
  # ── Topography ────────────────────────────────────────────────────────────
  "slope",                # Slope in degrees (0=flat, 90=vertical) — extension field
  "aspect",               # Aspect in degrees clockwise from N — extension field
  "topographic_position"  # Qualitative: ridge/upper slope/mid slope/lower slope/valley — extension field
)

# ── BIEN Field Definitions (Help tab reference table) ────────────────────────
BIEN_FIELD_DEFS <- c(
  scrubbed_species_binomial    = "Accepted species binomial after TNRS name-scrubbing (BIEN DB: scrubbed_species_binomial)",
  verbatim_scientific_name     = "Original species name as submitted, before any TNRS correction. Never overwritten.",
  scrubbed_family              = "Accepted family name after TNRS scrubbing",
  scrubbed_genus               = "Accepted genus after TNRS scrubbing",
  scrubbed_author              = "Authorship of the accepted name from TNRS",
  scrubbed_taxonomic_status    = "TNRS taxonomic status: accepted, synonym, etc.",
  latitude                     = "Decimal latitude in WGS84. Must be in [-90, 90]. Negative = south.",
  longitude                    = "Decimal longitude in WGS84. Must be in [-180, 180]. Negative = west.",
  is_centroid                  = "GVS centroid flag: 1 = coordinate matches a political centroid; 0 = checked, not centroid; blank = not checked.",
  date_collected               = "Collection or observation date. Accepts common date formats (YYYY-MM-DD preferred).",
  dataset                      = "Dataset or project name this record belongs to.",
  datasource                   = "Source institution or data repository.",
  dataowner                    = "Person or organization owning the dataset; often the lead collector.",
  collection_code              = "Voucher, herbarium, or catalog number for the record.",
  locality                     = "Textual description of the collection locality.",
  country                      = "Country name (standardized by GNRS).",
  state_province               = "State or province name (standardized by GNRS).",
  county                       = "County or parish name (standardized by GNRS).",
  plot_name                    = "Plot or site identifier. Used to link observations to plot metadata.",
  occurrenceID                 = "Globally unique identifier for the occurrence record (Darwin Core).",
  basisOfRecord                = "Nature of the record: HumanObservation, PreservedSpecimen, etc.",
  native_status                = "NSR native status: N=native, I=introduced, NI=native+introduced, UNK=unknown.",
  native_status_reason         = "Basis for NSR native status assignment.",
  native_status_country        = "Country used to evaluate native status.",
  native_status_state_province = "State/province used to evaluate native status.",
  native_status_county_parish  = "County/parish used to evaluate native status.",
  is_introduced                = "1 if taxon is introduced in the specified region; 0 if not.",
  is_cultivated_observation    = "1 if this record represents a cultivated individual; generally excluded from range/SDM analyses.",
  verbatimLocality             = "Verbatim locality string as recorded in the field (not standardized).",
  verbatimElevation            = "Verbatim elevation as recorded in the field (not converted).",
  elevation_min                = "Minimum elevation of the collection locality in meters.",
  elevation_max                = "Maximum elevation of the collection locality in meters.",
  # Plot structure
  cover                        = "Extension field (not in BIEN view_full_occurrence_individual; preserved as pass-through for plot/community datasets). Percent cover of the taxon within the plot (0-100).",
  cover_total                  = "Extension field (not in BIEN view_full_occurrence_individual; preserved as pass-through for plot/community datasets). Total vegetation cover in the plot (0-100); stand-level aggregate.",
  relative_cover               = "Extension field (not in BIEN view_full_occurrence_individual; preserved as pass-through for plot/community datasets). Cover of the taxon relative to all taxa in the plot (0-100).",
  individual_count             = "BIEN plot view (view_full_occurrence_individual): number of individuals of the taxon recorded in the plot.",
  stem_count                   = "Extension field (not in BIEN view_full_occurrence_individual; preserved as pass-through for plot/community datasets). Number of stems counted (may differ from individual_count for clonal taxa).",
  plot_area_ha                 = "BIEN plot view (view_full_occurrence_individual): plot surveyed area in hectares (preferred BIEN unit).",
  plot_size_m2                 = "Extension field (not in BIEN view_full_occurrence_individual; preserved as pass-through for plot/community datasets). Plot area in square meters; convert to ha for BIEN ingest.",
  basal_area_m2ha              = "Extension field (not in BIEN view_full_occurrence_individual; preserved as pass-through for plot/community datasets). Stand basal area in m2/ha (plot-level aggregate, not per-taxon).",
  coord_uncertainty_m          = "BIEN plot view (view_full_occurrence_individual): coordinate uncertainty in meters around the reported lat/lon.",
  sampling_protocol            = "BIEN plot view (view_full_occurrence_individual): sampling protocol or methodology used for the plot survey.",
  # Individual plant metrics
  height_m                     = "Extension field (not in BIEN view_full_occurrence_individual; preserved as pass-through for plot/community datasets). Plant height in meters.",
  dbh_cm                       = "Extension field (not in BIEN view_full_occurrence_individual; preserved as pass-through for plot/community datasets). Diameter at breast height (measured at 1.3 m above ground) in centimeters.",
  stratum                      = "Extension field (not in BIEN view_full_occurrence_individual; preserved as pass-through for plot/community datasets). Vertical stratum of the individual: canopy, subcanopy, shrub, herb, or ground.",
  subplot                      = "BIEN plot view (view_full_occurrence_individual): subplot or sub-quadrat identifier within the main plot.",
  # Topography
  slope                        = "Extension field (not in BIEN view_full_occurrence_individual; preserved as pass-through for plot/community datasets). Terrain slope in degrees from horizontal (0 = flat, 90 = vertical cliff).",
  aspect                       = "Extension field (not in BIEN view_full_occurrence_individual; preserved as pass-through for plot/community datasets). Terrain aspect in degrees clockwise from north (0/360=N, 90=E, 180=S, 270=W).",
  topographic_position         = "Extension field (not in BIEN view_full_occurrence_individual; preserved as pass-through for plot/community datasets). Qualitative topographic position: ridge, upper slope, mid slope, lower slope, or valley."
)

BIEN_FIELD_CATEGORY <- c(
  scrubbed_species_binomial    = "Taxonomy",
  verbatim_scientific_name     = "Taxonomy",
  scrubbed_family              = "Taxonomy",
  scrubbed_genus               = "Taxonomy",
  scrubbed_author              = "Taxonomy",
  scrubbed_taxonomic_status    = "Taxonomy",
  latitude                     = "Coordinates",
  longitude                    = "Coordinates",
  is_centroid                  = "Coordinates",
  date_collected               = "Temporal",
  dataset                      = "Provenance",
  datasource                   = "Provenance",
  dataowner                    = "Provenance",
  collection_code              = "Provenance",
  sampling_protocol            = "Provenance",
  locality                     = "Geography",
  country                      = "Geography",
  state_province               = "Geography",
  county                       = "Geography",
  plot_name                    = "Geography",
  occurrenceID                 = "Identifiers",
  basisOfRecord                = "Identifiers",
  native_status                = "NSR Status",
  native_status_reason         = "NSR Status",
  native_status_country        = "NSR Status",
  native_status_state_province = "NSR Status",
  native_status_county_parish  = "NSR Status",
  is_introduced                = "NSR Status",
  is_cultivated_observation    = "NSR Status",
  verbatimLocality             = "Verbatim",
  verbatimElevation            = "Verbatim",
  elevation_min                = "Elevation",
  elevation_max                = "Elevation",
  cover                        = "Plot Structure",
  cover_total                  = "Plot Structure",
  relative_cover               = "Plot Structure",
  individual_count             = "Plot Structure",
  stem_count                   = "Plot Structure",
  plot_area_ha                 = "Plot Structure",
  plot_size_m2                 = "Plot Structure",
  basal_area_m2ha              = "Plot Structure",
  coord_uncertainty_m          = "Plot Structure",
  height_m                     = "Plant Metrics",
  dbh_cm                       = "Plant Metrics",
  stratum                      = "Plant Metrics",
  subplot                      = "Plant Metrics",
  slope                        = "Topography",
  aspect                       = "Topography",
  topographic_position         = "Topography"
)

DWC_TERMS <- c(
  "occurrenceID", "basisOfRecord", "scientificName", "scientificNameAuthorship",
  "family", "genus", "taxonRank", "eventDate", "year", "month", "day",
  "decimalLatitude", "decimalLongitude", "coordinateUncertaintyInMeters",
  "geodeticDatum", "country", "stateProvince", "county", "locality",
  "verbatimLocality", "verbatimElevation", "minimumElevationInMeters",
  "maximumElevationInMeters", "institutionCode", "collectionCode",
  "catalogNumber", "datasetName", "occurrenceStatus", "habitat",
  "recordedBy", "identifiedBy", "taxonID"
)

# ── Canonicalize helper ───────────────────────────────────────────────────────

canonicalize <- function(x) {
  gsub("_+", "_", gsub("[^a-z0-9]+", "_", tolower(trimws(as.character(x)))))
}

blank_row_filter <- function(df) {
  if (nrow(df) == 0L || ncol(df) == 0L) return(df)
  not_blank <- Reduce(`|`, lapply(df, function(col) {
    s <- trimws(as.character(col))
    !is.na(col) & nzchar(s) & s != "NA"
  }))
  df[not_blank, , drop = FALSE]
}

safe_read_csv_with_fallbacks <- function(path, file_label = basename(path)) {
  sniffed_sep <- tryCatch({
    hdr <- readLines(path, n = 1L, warn = FALSE, encoding = "UTF-8")
    n_comma <- nchar(hdr) - nchar(gsub(",", "", hdr, fixed = TRUE))
    n_semi  <- nchar(hdr) - nchar(gsub(";", "", hdr, fixed = TRUE))
    if (n_semi > n_comma) ";" else ","
  }, error = function(e) NULL)

  sep_candidates <- if (!is.null(sniffed_sep))
    c(sniffed_sep, setdiff(c(",", ";"), sniffed_sep))
  else c(",", ";")

  attempts <- expand.grid(
    sep          = sep_candidates,
    fileEncoding = c("UTF-8", "latin1"),
    stringsAsFactors = FALSE
  )
  errors <- character(0)

  for (i in seq_len(nrow(attempts))) {
    sep_i <- attempts$sep[i]
    enc_i <- attempts$fileEncoding[i]
    res <- tryCatch(
      utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE,
                      sep = sep_i, fileEncoding = enc_i),
      error = function(e) e
    )

    if (!inherits(res, "error")) {
      if (ncol(res) == 1L) {
        hdr <- names(res)[1]
        wrong_sep <- (sep_i == "," && grepl(";", hdr, fixed = TRUE)) ||
                     (sep_i == ";" && grepl(",", hdr, fixed = TRUE))
        if (isTRUE(wrong_sep)) {
          errors <- c(errors, paste0("sep='", sep_i, "', enc=", enc_i, ": one-column parse"))
          next
        }
      }
      return(res)
    }

errors <- c(errors, paste0("sep='", sep_i, "', enc=", enc_i, ": ", conditionMessage(res)))
  }

  stop(paste0("Could not read '", file_label, "'. Tried comma/semicolon separators and UTF-8/Latin-1. Errors: ",
              paste(errors, collapse = " | ")), call. = FALSE)
}

# ── Mapping lookup tables (built once at load time) ───────────────────────────

DWC_LOOKUP <- setNames(DWC_TERMS, canonicalize(DWC_TERMS))

DWC_ALIASES <- c(
  scientific_name = "scientificName", species = "scientificName", taxon = "scientificName",
  taxon_name = "scientificName", name = "scientificName",
  lat = "decimalLatitude", latitude = "decimalLatitude", decimal_latitude = "decimalLatitude",
  lon = "decimalLongitude", long = "decimalLongitude", longitude = "decimalLongitude",
  decimal_longitude = "decimalLongitude",
  date = "eventDate", event_date = "eventDate", collection_date = "eventDate",
  date_collected = "eventDate", sample_date = "eventDate",
  state = "stateProvince", state_province = "stateProvince", province = "stateProvince",
  occurrence_id = "occurrenceID", basis_of_record = "basisOfRecord",
  family_name = "family", genus_name = "genus",
  collector = "recordedBy", observer = "recordedBy", recorded_by = "recordedBy",
  data_recorder = "recordedBy", recorder = "recordedBy", surveyor = "recordedBy",
  field_crew = "recordedBy", technician = "recordedBy", investigator = "recordedBy",
  site = "locality", plot = "locality", plot_name = "locality", location = "locality",
  transect = "locality", station = "locality", quadrat = "locality",
  institution = "institutionCode", collection = "collectionCode",
  herbarium = "institutionCode", herbarium_code = "institutionCode",
  catalog_number = "catalogNumber", voucher = "catalogNumber", voucher_number = "catalogNumber",
  specimen_id = "catalogNumber", accession = "catalogNumber",
  dataset = "datasetName", dataset_name = "datasetName", project = "datasetName",
  study = "datasetName", survey = "datasetName",
  habitat_notes = "habitat", notes = NA_character_, habitat_description = "habitat",
  elevation = "minimumElevationInMeters", elevation_m = "minimumElevationInMeters",
  alt = "minimumElevationInMeters", altitude = "minimumElevationInMeters",
  elev_m = "minimumElevationInMeters", elev = "minimumElevationInMeters"
)

BIEN_LOOKUP <- setNames(BIEN_STAGING_FIELDS, canonicalize(BIEN_STAGING_FIELDS))

BIEN_ALIASES <- c(
  scientific_name = "scrubbed_species_binomial", species = "scrubbed_species_binomial",
  scientificname  = "scrubbed_species_binomial", taxon = "scrubbed_species_binomial",
  name = "scrubbed_species_binomial",
  lat = "latitude", decimal_latitude = "latitude", decimallatitude = "latitude",
  lon = "longitude", long = "longitude", decimal_longitude = "longitude",
  decimallongitude = "longitude",
  date = "date_collected", event_date = "date_collected", eventdate = "date_collected",
  collection_date = "date_collected",
  state = "state_province", stateprovince = "state_province",
  plot = "plot_name", site = "plot_name",
  occurrence_id = "occurrenceID", occurrenceid = "occurrenceID",
  family_name = "scrubbed_family", family = "scrubbed_family",
  genus_name = "scrubbed_genus",  genus = "scrubbed_genus",
  observer = "dataowner", collector = "dataowner", recorded_by = "dataowner",
  data_recorder = "dataowner", recorder = "dataowner", surveyor = "dataowner",
  field_crew = "dataowner", technician = "dataowner", investigator = "dataowner",
  elevation_m = "elevation_min", elevation = "elevation_min",
  alt = "elevation_min", altitude = "elevation_min",
  elev_m = "elevation_min", elev = "elevation_min",
  dataset_name = "dataset", dataset = "dataset",
  project = "dataset", study = "dataset", survey = "dataset",
  transect = "plot_name", station = "plot_name", quadrat = "plot_name",
  voucher = "collection_code", voucher_number = "collection_code",
  catalog_number = "collection_code", specimen_id = "collection_code",
  locality_description = "verbatimLocality", habitat_notes = "verbatimLocality",
  # ── Verbatim name aliases ─────────────────────────────────────────────────
  verbatim_name = "verbatim_scientific_name", verbatim_species = "verbatim_scientific_name",
  original_name = "verbatim_scientific_name", submitted_name = "verbatim_scientific_name",
  # ── Plot structure aliases ────────────────────────────────────────────────
  cover_pct = "cover", pct_cover = "cover", percent_cover = "cover", pct_cov = "cover",
  cover_total_pct = "cover_total", total_cover = "cover_total",
  rel_cover = "relative_cover", relative_abundance = "relative_cover",
  n_individuals = "individual_count", count = "individual_count",
  abundance_count = "individual_count", ind_count = "individual_count",
  n_stems = "stem_count", stems = "stem_count", stem_number = "stem_count",
  area_ha = "plot_area_ha", plot_area = "plot_area_ha", survey_area_ha = "plot_area_ha",
  plot_size = "plot_size_m2", quadrat_size_m2 = "plot_size_m2",
  subplot_size_m2 = "plot_size_m2", area_m2 = "plot_size_m2",
  ba_m2ha = "basal_area_m2ha", stand_ba = "basal_area_m2ha",
  basal_area = "basal_area_m2ha",
  coord_uncertainty = "coord_uncertainty_m", coordinate_uncertainty_m = "coord_uncertainty_m",
  coordinateuncertaintyinmeters = "coord_uncertainty_m",
  protocol = "sampling_protocol", method = "sampling_protocol",
  samplingprotocol = "sampling_protocol", survey_method = "sampling_protocol",
  # ── Individual plant metric aliases ───────────────────────────────────────
  ht_m = "height_m", plant_height = "height_m", height = "height_m",
  canopy_height_m = "height_m", tree_height_m = "height_m",
  dbh = "dbh_cm", stem_diameter_cm = "dbh_cm", diameter_cm = "dbh_cm",
  layer = "stratum", canopy_layer = "stratum", vegetation_layer = "stratum",
  subplot_name = "subplot", sub_plot = "subplot", quadrat_id = "subplot",
  # ── Topography aliases ────────────────────────────────────────────────────
  slope_deg = "slope", terrain_slope = "slope", slope_degrees = "slope",
  aspect_deg = "aspect", terrain_aspect = "aspect", exposure = "aspect",
  aspect_degrees = "aspect",
  topo = "topographic_position", topo_position = "topographic_position",
  position = "topographic_position", landform = "topographic_position"
)

# ── Vectorized auto-suggest ───────────────────────────────────────────────────

suggest_mapping <- function(col_names) {
  can <- canonicalize(col_names)

  dwc_direct <- DWC_LOOKUP[can]
  dwc_alias  <- DWC_ALIASES[can]
  dwc        <- ifelse(!is.na(dwc_direct), dwc_direct,
                  ifelse(!is.na(dwc_alias), dwc_alias, NA_character_))

  bien_direct <- BIEN_LOOKUP[can]
  bien_alias  <- BIEN_ALIASES[can]
  bien        <- ifelse(!is.na(bien_direct), bien_direct,
                   ifelse(!is.na(bien_alias), bien_alias, NA_character_))

  data.frame(
    source_col  = col_names,
    dwc_term    = unname(dwc),
    bien_field  = unname(bien),
    stringsAsFactors = FALSE
  )
}

# ── Build staging table (vectorized) ─────────────────────────────────────────

build_staging <- function(merged_df, mapping) {
  # Drop rows with no bien_field mapping
  m <- mapping[!is.na(mapping$bien_field) & nzchar(trimws(mapping$bien_field)), , drop=FALSE]

  staged <- data.frame(matrix(NA_character_, nrow=nrow(merged_df), ncol=length(BIEN_STAGING_FIELDS)),
                       stringsAsFactors=FALSE)
  names(staged) <- BIEN_STAGING_FIELDS

  for (i in seq_len(nrow(m))) {
    src <- m$source_col[i]
    fld <- m$bien_field[i]
    if (src %in% names(merged_df) && fld %in% BIEN_STAGING_FIELDS) {
      staged[[fld]] <- as.character(merged_df[[src]])
    }
  }

  # ── Capture verbatim_scientific_name before TNRS can overwrite scrubbed name ──
  # verbatim_scientific_name is intentionally NOT overwritten by TNRS
  if (all(is.na(staged$verbatim_scientific_name) | staged$verbatim_scientific_name == "")) {
    spp_row <- m[m$bien_field == "scrubbed_species_binomial", , drop=FALSE]
    if (nrow(spp_row) > 0 && spp_row$source_col[1] %in% names(merged_df)) {
      staged$verbatim_scientific_name <- as.character(merged_df[[spp_row$source_col[1]]])
    }
  }

  if (all(is.na(staged$basisOfRecord) | staged$basisOfRecord == "")) {
    staged$basisOfRecord <- "HumanObservation"
  }
  staged
}

# ── Build DWC table (vectorized) ─────────────────────────────────────────────

build_dwc <- function(merged_df, mapping) {
  m <- mapping[!is.na(mapping$dwc_term) & nzchar(trimws(mapping$dwc_term)), , drop=FALSE]
  if (nrow(m) == 0) return(data.frame(stringsAsFactors=FALSE))

  out <- lapply(seq_len(nrow(m)), function(i) {
    src <- m$source_col[i]
    if (src %in% names(merged_df)) as.character(merged_df[[src]]) else rep(NA_character_, nrow(merged_df))
  })
  names(out) <- m$dwc_term
  as.data.frame(out, stringsAsFactors=FALSE)
}

# ── Vectorized QC checks ──────────────────────────────────────────────────────

run_qc <- function(staged) {
  rows <- list()

  check_field <- function(label, field, check_fn, sev_fail) {
    if (!field %in% names(staged)) return(NULL)
    vals <- as.character(staged[[field]])
    pass <- check_fn(vals)
    n_pass <- sum(pass, na.rm=TRUE)
    n_fail <- sum(!pass, na.rm=TRUE)
    ex_fail <- vals[which(!pass)[1]]
    data.frame(field=field, check=label,
               n_records=nrow(staged), n_pass=n_pass, n_fail=n_fail,
               severity=if(n_fail==0) "PASS" else sev_fail,
               example_fail=if(is.na(ex_fail)) NA_character_ else ex_fail,
               stringsAsFactors=FALSE)
  }

  # Date parseable — try multiple common formats gracefully
  if ("date_collected" %in% names(staged)) {
    raw <- as.character(staged$date_collected)
    parsed <- suppressWarnings(as.Date(raw, tryFormats = c(
      "%Y-%m-%d", "%m/%d/%y", "%m/%d/%Y",
      "%d/%m/%Y", "%Y/%m/%d", "%d-%m-%Y",
      "%d-%b-%Y", "%B %d, %Y", "%b %d, %Y"
    )))
    n_pass <- sum(!is.na(parsed))
    n_fail <- sum(is.na(parsed) & !is.na(raw) & trimws(raw) != "")
    ex <- raw[which(is.na(parsed) & !is.na(raw) & trimws(raw) != "")][1]
    rows[["date"]] <- data.frame(
      field="date_collected", check="Date parseable (common formats)",
      n_records=nrow(staged), n_pass=n_pass, n_fail=n_fail,
      severity=if(n_fail==0) "PASS" else "WARN",
      example_fail=if(is.na(ex)) NA_character_ else ex,
      stringsAsFactors=FALSE)
  }

  # Latitude
  rows[["lat"]] <- check_field("Latitude in range [-90, 90]", "latitude",
    function(v) { n <- suppressWarnings(as.numeric(v)); !is.na(n) & n >= -90 & n <= 90 }, "BLOCK")

  # Longitude
  rows[["lon"]] <- check_field("Longitude in range [-180, 180]", "longitude",
    function(v) { n <- suppressWarnings(as.numeric(v)); !is.na(n) & n >= -180 & n <= 180 }, "BLOCK")

  # Species name not blank
  rows[["spp"]] <- check_field("Species name not blank", "scrubbed_species_binomial",
    function(v) !is.na(v) & trimws(v) != "", "WARN")

  # Required fields all present (not 100% blank)
  for (fld in c("latitude","longitude","date_collected","country","scrubbed_species_binomial")) {
    if (fld %in% names(staged)) {
      vals <- as.character(staged[[fld]])
      n_miss <- sum(is.na(vals) | trimws(vals) == "")
      sev    <- if (n_miss == nrow(staged)) "BLOCK" else if (n_miss > 0) "WARN" else "PASS"
      rows[[paste0("req_",fld)]] <- data.frame(
        field=fld, check="Required field populated",
        n_records=nrow(staged), n_pass=nrow(staged)-n_miss, n_fail=n_miss,
        severity=sev, example_fail=NA_character_, stringsAsFactors=FALSE)
    }
  }

  # ── Plot field range QC (only fires for rows where field is populated) ──
  plot_range_check <- function(label, field, lo, hi, sev_fail) {
    if (!field %in% names(staged)) return(NULL)
    vals <- as.character(staged[[field]])
    populated <- !is.na(vals) & trimws(vals) != ""
    n_pop <- sum(populated)
    if (n_pop == 0) return(NULL)  # field not populated — skip silently
    n_vals <- suppressWarnings(as.numeric(vals[populated]))
    pass_populated <- !is.na(n_vals) & n_vals >= lo & n_vals <= hi
    n_pass <- sum(pass_populated)
    n_fail <- n_pop - n_pass
    ex_fail <- vals[populated][which(!pass_populated)[1]]
    data.frame(field=field, check=label,
               n_records=n_pop, n_pass=n_pass, n_fail=n_fail,
               severity=if(n_fail==0) "PASS" else sev_fail,
               example_fail=if(is.na(ex_fail)) NA_character_ else ex_fail,
               stringsAsFactors=FALSE)
  }
  rows[["cover"]]       <- plot_range_check("Cover in range [0, 100] %",           "cover",        0, 100, "WARN")
  rows[["cover_tot"]]   <- plot_range_check("Cover total in range [0, 100] %",      "cover_total",  0, 100, "WARN")
  rows[["rel_cover"]]   <- plot_range_check("Relative cover in range [0, 100] %",   "relative_cover", 0, 100, "WARN")
  rows[["slope_qc"]]    <- plot_range_check("Slope in range [0, 90] degrees",        "slope",        0,  90, "WARN")
  rows[["aspect_qc"]]   <- plot_range_check("Aspect in range [0, 360] degrees",      "aspect",       0, 360, "WARN")
  rows[["dbh_qc"]]      <- plot_range_check("DBH non-negative (>= 0 cm)",            "dbh_cm",       0, 1e4, "WARN")
  rows[["height_qc"]]   <- plot_range_check("Height non-negative (>= 0 m)",          "height_m",     0, 200, "WARN")
  rows[["plotarea_qc"]] <- plot_range_check("Plot area non-negative (>= 0 ha)",       "plot_area_ha", 0, 1e6, "WARN")
  rows[["ind_cnt_qc"]]  <- plot_range_check("Individual count non-negative (>= 0)",  "individual_count", 0, 1e6, "WARN")

  qc <- do.call(rbind, Filter(Negate(is.null), rows))
  if (!is.null(qc)) row.names(qc) <- NULL
  qc
}

# ── UI ────────────────────────────────────────────────────────────────────────

ui <- navbarPage(
  title = tags$span(class="navbar-brand-hidden"),
  id    = "tabs",
  header = tagList(
    tags$head(
      tags$style(HTML("
        :root {
          --bien-blue: #2f79b7;
          --bien-blue-deep: #1f5b8f;
          --bien-green: #74b64a;
          --bien-green-deep: #4e8c2c;
          --bien-sky: #e9f4ff;
          --bien-mint: #eef9e8;
          --panel-border: #cfe2f3;
          --text-ink: #24445f;
        }

        body {
          padding: 0;
          font-family: 'Segoe UI', Arial, sans-serif;
          color: var(--text-ink);
          background: linear-gradient(180deg, #f7fbff 0%, #fbfef9 100%);
        }

        .navbar {
          background: linear-gradient(90deg, var(--bien-blue-deep) 0%, var(--bien-blue) 72%, #3d8bc8 100%) !important;
          border-color: #1a4a72 !important;
          box-shadow: 0 2px 12px rgba(22, 67, 108, 0.22);
        }
        /* Brand hidden — title lives in page-header above the navbar */
        .navbar-brand, .navbar-brand-hidden {
          display: none !important;
          width: 0 !important;
          padding: 0 !important;
          margin: 0 !important;
        }
        /* Tabs fill the full navbar width */
        .navbar-nav {
          margin: 0 !important;
          float: none !important;
          display: flex !important;
          flex-wrap: wrap;
        }
        .navbar-nav > li {
          flex: 0 0 auto;
        }
        .navbar-nav > li > a {
          padding: 14px 20px !important;
          font-size: 0.95em !important;
          font-weight: 500 !important;
          letter-spacing: 0.02em;
        }
        .page-header {
          padding: 20px 24px;
          background: linear-gradient(180deg, #ffffff 0%, #f2f9ff 100%);
          border-bottom: 1px solid var(--panel-border);
          margin: 0;
          box-shadow: none;
        }
        .bien-header-brand {
          display: flex;
          align-items: center;
          gap: 16px;
          flex-wrap: wrap;
        }
        .bien-logo {
          height: 62px;
          width: auto;
          filter: drop-shadow(0 2px 4px rgba(0, 0, 0, 0.12));
        }
        .page-header h1 {
          color: var(--bien-blue-deep);
          font-size: 2em;
          font-weight: 700;
          line-height: 1.2;
          margin-top: 0;
          margin-bottom: 8px;
        }
        .page-header p {
          color: #426988;
          font-size: 1.05em;
          line-height: 1.4;
          margin-bottom: 0;
          max-width: 920px;
        }
        .navbar-brand, .navbar-nav > li > a {
          color: #ffffff !important;
          text-shadow: none;
        }
        .navbar-default .navbar-nav > li > a {
          transition: background-color 0.18s ease, color 0.18s ease;
        }
        .navbar-default .navbar-nav > li > a:hover {
          background-color: rgba(255, 255, 255, 0.14) !important;
          color: #ffffff !important;
        }
        .navbar-nav > .active > a,
        .navbar-default .navbar-nav > .active > a:hover,
        .navbar-default .navbar-nav > .active > a:focus {
          background: linear-gradient(180deg, rgba(255, 255, 255, 0.26) 0%, rgba(255, 255, 255, 0.12) 100%) !important;
          color: #ffffff !important;
          box-shadow: inset 0 -3px 0 var(--bien-green);
          font-weight: 600;
        }

        a:focus-visible,
        button:focus-visible,
        .btn:focus-visible,
        .navbar-nav > li > a:focus-visible,
        .nav > li > a:focus-visible {
          outline: 3px solid rgba(116, 182, 74, 0.95) !important;
          outline-offset: 2px;
          border-radius: 4px;
        }

        /* Cold-start overlay */
        #cold-overlay {
          position:fixed; inset:0; z-index:9999;
          background:rgba(255,255,255,0.97);
          display:flex; flex-direction:column;
          align-items:center; justify-content:center;
        }
        @keyframes spin { 100% { transform:rotate(360deg); } }
        .cold-spin {
          width:52px; height:52px; border-radius:50%;
          border:6px solid #d0e4f7; border-top-color:var(--bien-blue);
          animation:spin 0.8s linear infinite; margin-bottom:18px;
        }
        #cold-overlay p  { font-size:1.1em; color:var(--bien-blue); font-weight:600; margin:0 0 6px; }
        #cold-overlay small { color:#777; font-size:0.85em; }

        /* Info cards */
        .bl-card {
          background: linear-gradient(160deg, #ffffff 0%, #f4faff 100%);
          border: 1px solid var(--panel-border);
          border-left: 4px solid var(--bien-blue);
          padding:12px 16px;
          margin:10px 0;
          border-radius:10px;
          box-shadow: 0 8px 18px rgba(36, 68, 95, 0.09);
        }
        .bl-card-warn  { border-left-color:#e6a817; background:#fffaf0; }
        .bl-card-block { border-left-color:#c0392b; background:#fff6f6; }
        .bl-card-pass  { border-left-color:#27ae60; background:#f2fff6; }

        /* Step badges */
        .step-badge {
          display:inline-block; width:28px; height:28px; border-radius:50%;
          background:var(--bien-blue); color:#fff; font-weight:700;
          text-align:center; line-height:28px; margin-right:8px; font-size:0.9em;
        }
        .step-done { background:#27ae60; }

        /* QC severity colours in tables */
        .qc-PASS  { color:#27ae60; font-weight:700; }
        .qc-WARN  { color:#e6a817; font-weight:700; }
        .qc-BLOCK { color:#c0392b; font-weight:700; }

        .btn-primary {
          background: linear-gradient(180deg, var(--bien-blue) 0%, var(--bien-blue-deep) 100%);
          border-color: #194a72;
        }
        .btn-primary:hover,
        .btn-primary:active,
        .btn-primary:focus {
          background: linear-gradient(180deg, #2a6ea8 0%, #184d79 100%);
          border-color: #143e62;
        }
        .btn-success {
          background: linear-gradient(180deg, var(--bien-green) 0%, var(--bien-green-deep) 100%);
          border-color: #3f7423;
        }
        .btn-success:hover,
        .btn-success:active,
        .btn-success:focus {
          background: linear-gradient(180deg, #6aa93f 0%, #447b27 100%);
          border-color: #365f1f;
        }

        /* Spacing */
        .shiny-input-container { margin-bottom:8px; }

        @media (max-width: 768px) {
          .bien-logo { height: 44px; }
          .page-header h1 { font-size: 1.4em; }
          .navbar-nav > li > a { padding: 12px 10px !important; font-size: 0.82em !important; }
        }
      ")),
      tags$script(HTML("
        $(document).on('shiny:connected', function() {
          var ov = document.getElementById('cold-overlay');
          if (ov) ov.style.display = 'none';
        });
        /* Move page-header above the navbar so it sits at top of page */
        $(document).ready(function() {
          var ph = $('.page-header').detach();
          $('.navbar').before(ph);
        });
      "))
    ),
    tags$div(class = "page-header",
      tags$div(class = "bien-header-brand",
        tags$img(src="bien.png", alt="BIEN logo", class="bien-logo"),
        tags$div(
          tags$h1("BIEN Data Loader"),
          tags$p("Upload, validate, and export BIEN-ready records")
        )
      )
    ),
    tags$div(id="cold-overlay",
      tags$div(class="cold-spin"),
      tags$p("BIEN Data Loader is starting up\u2026"),
      tags$small("First load may take a moment on free hosting.")
    )
  ),

  # ── Tab 1: Upload & Merge ─────────────────────────────────────────────────
  tabPanel("1 \u2022 Upload & Merge",
    fluidRow(
      column(4,
        tags$div(class="bl-card",
          tags$span(class="step-badge", "1"),
          tags$strong("Load Data"),
          tags$hr(style="margin:8px 0"),
          checkboxInput("use_demo", "Use built-in demo data (12 obs + 6 plots)", value=TRUE),
          conditionalPanel("!input.use_demo",
            tags$div(
              fileInput("files", "Upload CSV file(s)", multiple=TRUE, accept=".csv",
                        placeholder="Select one or more .csv files"),
              tags$small(
                style="display:block; margin-top:-6px; margin-bottom:6px; color:#555;",
                "To select multiple files: macOS (Command-click), Windows/Linux (Ctrl-click)."
              ),
              tags$small(
                tags$a(href="#", onclick="$(\"[data-value='? \\u2022 Help']\").tab('show'); return false;",
                  style="color:#2f6fab; text-decoration:underline; cursor:pointer;",
                  "What format should my CSV files be?"
                )
              )
            )
          ),
          tags$hr(style="margin:8px 0"),
          uiOutput("primary_file_ui"),
          uiOutput("join_key_ui"),
          tags$br(),
          actionButton("btn_prepare", "Prepare Dataset \u25b6", class="btn-primary btn-lg",
                       style="width:100%")
        ),
        uiOutput("step1_status")
      ),
      column(8,
        uiOutput("preview_header"),
        DT::dataTableOutput("preview_table")
      )
    )
  ),

  # ── Tab 2: Map Fields ─────────────────────────────────────────────────────
  tabPanel("2 \u2022 Map Fields",
    uiOutput("tab2_gating"),
    fluidRow(
      column(12,
        tags$div(class="bl-card",
          tags$span(class="step-badge", "2"),
          tags$strong("Review and adjust field mappings"),
          tags$div(style="color:#4f6272; font-size:0.9em; margin-top:6px;",
            "Choose mappings from the dropdowns for approved Darwin Core and BIEN fields.",
            tags$br(),
            "Do not type or invent Darwin Core/BIEN field strings. Leave a mapping blank to skip that source column, then click Apply Mapping."),
          tags$br(), tags$br(),
          actionButton("btn_apply_mapping", "Apply Mapping \u25b6", class="btn-primary"),
          tags$span(style="margin-left:12px;"),
          uiOutput("step2_status_inline")
        ),
        DT::dataTableOutput("mapping_table")
      )
    )
  ),

  # ── Tab 3: Stage & Validate ───────────────────────────────────────────────
  tabPanel("3 \u2022 Stage & Validate",
    uiOutput("tab3_gating"),
    fluidRow(
      column(4,
        tags$div(class="bl-card",
          tags$span(class="step-badge", "3"),
          tags$strong("QC Summary")
        ),
        uiOutput("qc_summary_ui"),
        tags$br(),
        tags$div(class="bl-card bl-card-warn",
          tags$strong("BIEN Web Services (Required for BIEN Schema Mapping)"),
          tags$p(style="font-size:0.85em; margin:4px 0 6px;",
            "Run these services sequentially for BIEN-schema-ready outputs: TNRS -> GNRS -> GVS -> NSR. These steps populate and standardize BIEN fields and should be completed before final export to the BIEN staging table."),
          tags$p(style="font-size:0.8em; color:#7f8c8d; margin:0 0 8px;",
            HTML("<strong>Cloud timeout warning:</strong> Download the validation scripts below and run them locally in R when possible. ",
                 "The in-app buttons contact external servers that may be unreachable from cloud hosting ",
                 "(shinyapps.io runs on AWS; external APIs may block cloud IPs). ",
                 "If an in-app check times out after ~25s, the local script is the reliable path. ",
                 "For BIEN schema mapping, complete TNRS -> GNRS -> GVS -> NSR before final export.")),

          tags$hr(style="margin:6px 0;"),
          downloadButton("dl_tnrs_script", "\u2b07 Download TNRS validation script (.R)",
                         class="btn-success btn-sm",
                         style="width:100%; margin-bottom:6px; font-size:0.85em;"),
          actionButton("btn_tnrs", "Try TNRS in app (may timeout from cloud)", class="btn-warning btn-sm",
                       style="width:100%; margin-bottom:4px;"),
          fileInput("upload_tnrs", "Upload TNRS results CSV",
            accept=".csv", buttonLabel="Browse", placeholder="tnrs_results.csv",
            width="100%"),
          uiOutput("tnrs_status_ui"),
          tags$p(style="font-size:0.8em; color:#555; margin:4px 0 8px;",
            "TNRS matches submitted scientific names to accepted names (WCVP/WFO), standardizes spelling/authorship where possible, and writes scrubbed taxonomy fields."),
          tags$hr(style="margin:6px 0;"),
          downloadButton("dl_gnrs_script", "\u2b07 Download GNRS validation script (.R)",
                         class="btn-success btn-sm",
                         style="width:100%; margin-bottom:6px; font-size:0.85em;"),
          actionButton("btn_gnrs", "Try GNRS in app (may timeout from cloud)", class="btn-warning btn-sm",
                       style="width:100%; margin-bottom:4px;"),
          fileInput("upload_gnrs", "Upload GNRS results CSV",
            accept=".csv", buttonLabel="Browse", placeholder="gnrs_results.csv",
            width="100%"),
          uiOutput("gnrs_status_ui"),
          tags$p(style="font-size:0.8em; color:#555; margin:4px 0 8px;",
            "GNRS standardizes political geography (country/state/county) and helps catch misspellings and inconsistent region strings."),
          tags$hr(style="margin:6px 0;"),
          downloadButton("dl_gvs_script", "\u2b07 Download GVS validation script (.R)",
                         class="btn-success btn-sm",
                         style="width:100%; margin-bottom:6px; font-size:0.85em;"),
          actionButton("btn_gvs", "Try GVS in app (may timeout from cloud)", class="btn-warning btn-sm",
                       style="width:100%; margin-bottom:4px;"),
          fileInput("upload_gvs", "Upload GVS results CSV",
            accept=".csv", buttonLabel="Browse", placeholder="gvs_results.csv",
            width="100%"),
          uiOutput("gvs_status_ui"),
          tags$p(style="font-size:0.8em; color:#555; margin:4px 0 8px;",
            "GVS checks whether lat/lon appear to be political centroids and flags potential georeferencing precision issues; it does not delete records."),
          tags$hr(style="margin:6px 0;"),
          downloadButton("dl_nsr_script", "\u2b07 Download NSR validation script (.R)",
                         class="btn-success btn-sm",
                         style="width:100%; margin-bottom:6px; font-size:0.85em;"),
          actionButton("btn_nsr", "Try NSR in app (may timeout from cloud)", class="btn-warning btn-sm",
                       style="width:100%; margin-bottom:4px;"),
          fileInput("upload_nsr", "Upload NSR results CSV",
            accept=".csv", buttonLabel="Browse", placeholder="nsr_results.csv",
            width="100%"),
          uiOutput("nsr_status_ui"),
          tags$p(style="font-size:0.8em; color:#555; margin:4px 0 0;",
            "NSR estimates native/introduced/cultivated status by taxon plus region, useful for filtering non-native or cultivated observations in downstream analyses.")
        )
      ),
      column(8,
        tabsetPanel(id="stage_tabs",
          tabPanel("Staging Table",  DT::dataTableOutput("staged_table")),
          tabPanel("DWC (Darwin Core) Table", DT::dataTableOutput("dwc_table")),
          tabPanel("QC Details",     DT::dataTableOutput("qc_table")),
          tabPanel("TNRS Results",   DT::dataTableOutput("tnrs_table")),
          tabPanel("GNRS Results",   DT::dataTableOutput("gnrs_table")),
          tabPanel("GVS Results",    DT::dataTableOutput("gvs_table")),
          tabPanel("NSR Results",    DT::dataTableOutput("nsr_table"))
        )
      )
    )
  ),

  # ── Tab 4: Export ─────────────────────────────────────────────────────────
  tabPanel("4 \u2022 Export",
    uiOutput("tab4_gating"),
    fluidRow(
      column(4,
        tags$div(class="bl-card",
          tags$span(class="step-badge", "4"),
          tags$strong("Download Outputs"),
          tags$hr(style="margin:8px 0"),
          downloadButton("dl_staged",  "BIEN Staging Table (.csv)",
                         style="width:100%; margin-bottom:8px;"),
          downloadButton("dl_dwc",     "Darwin Core Table (.csv)",
                         style="width:100%; margin-bottom:8px;"),
          downloadButton("dl_mapping", "Field Mapping (.csv)",
                         style="width:100%; margin-bottom:8px;"),
          downloadButton("dl_qc",      "QC Report (.csv)",
                         style="width:100%; margin-bottom:8px;"),
          downloadButton("dl_packet",  "Full Packet (.zip)",
                         style="width:100%;"),
          tags$br(),
          uiOutput("dl_status_ui")
        )
      ),
      column(8,
        tags$div(class="bl-card",
          tags$strong("Export Summary"),
          tags$hr(style="margin:8px 0"),
          verbatimTextOutput("export_summary")
        )
      )
    )
  ),

  # ── Tab 5: Help ───────────────────────────────────────────────────────────
  tabPanel(
    "? \u2022 Help",
    fluidRow(
      column(
        width = 10, offset = 1,
        style = "padding-top:32px; padding-bottom:48px;",

        # Title
        tags$h2("BIEN Data Loader \u2014 Help & About",
          style = "font-size:1.6rem; font-weight:600; color:#1a1a2e; margin-bottom:4px;"),
        tags$p(
          "A guided tool for uploading, standardizing, validating, and exporting
           field observation data into the BIEN database.",
          style = "color:#555; font-size:0.95rem; margin-bottom:28px;"),
        tags$hr(style = "border-color:#d0dce8; margin-bottom:28px;"),

        # CSV File Format
        tags$h3("CSV File Format",
          style = "font-size:1.1rem; font-weight:600; color:#2f6fab; margin-bottom:12px;"),
        tags$p(style = "font-size:0.9rem; color:#555; margin-bottom:12px;",
          "The app accepts one or two CSV files. Only one file is required. Each file should
           have column headers in the first row."),

        fluidRow(
          column(6,
            tags$div(class = "bl-card", style = "margin-bottom:16px;",
              tags$strong("File 1 \u2014 Observation Records (required)",
                style = "font-size:0.93rem; color:#1a1a2e;"),
              tags$p(style = "margin:8px 0 6px 0; font-size:0.88rem; color:#3a3a3a; line-height:1.6;",
                "One row per observation. Must include at minimum a species name column.
                 Any other columns are optional but will be auto-mapped if recognized."),
              tags$p(style = "margin:4px 0 4px 0; font-size:0.82rem; color:#555;",
                tags$strong("Example columns:")),
              tags$ul(
                style = "margin:0; padding-left:18px; font-size:0.83rem; color:#3a3a3a; line-height:1.9;",
                tags$li(tags$code("species"), " or ", tags$code("scientificName"),
                  " \u2014 species binomial, e.g. ", tags$em("Quercus robur")),
                tags$li(tags$code("lat"), ", ", tags$code("lon"),
                  " \u2014 decimal latitude and longitude"),
                tags$li(tags$code("date"), " or ", tags$code("date_collected"),
                  " \u2014 collection date"),
                tags$li(tags$code("country"), ", ", tags$code("state"), ", ",
                  tags$code("county"), " \u2014 political geography"),
                tags$li(tags$code("plot_name"), " or ", tags$code("site"),
                  " \u2014 plot or site identifier"),
                tags$li(tags$code("collector"), ", ", tags$code("dataset"),
                  ", ", tags$code("notes"), " \u2014 provenance fields")
              )
            )
          ),
          column(6,
            tags$div(class = "bl-card", style = "margin-bottom:16px;",
              tags$strong("File 2 \u2014 Metadata or Plot Data (optional)",
                style = "font-size:0.93rem; color:#1a1a2e;"),
              tags$p(style = "margin:8px 0 6px 0; font-size:0.88rem; color:#3a3a3a; line-height:1.6;",
                "Any supplementary table you want joined to the observation records \u2014
                 plot metadata, site attributes, survey details, etc. The two files are
                 joined on a shared key column you select."),
              tags$p(style = "margin:4px 0 4px 0; font-size:0.82rem; color:#555;",
                tags$strong("Example use cases:")),
              tags$ul(
                style = "margin:0; padding-left:18px; font-size:0.83rem; color:#3a3a3a; line-height:1.9;",
                tags$li("Plot metadata table keyed by ", tags$code("plot_name"),
                  " (elevation, habitat type, area surveyed)"),
                tags$li("Site coordinates table when lat/lon are stored separately"),
                tags$li("Observer or institution details linked by ", tags$code("dataset")),
                tags$li("Voucher or specimen records joined by ", tags$code("occurrenceID"))
              ),
              tags$div(
                style = "margin-top:10px; padding:8px 10px; background:#f0fff4;
                         border-left:3px solid #27ae60; border-radius:3px;",
                tags$small(style = "color:#1a5c35; font-size:0.82rem;",
                  tags$strong("Not required."),
                  " If you only have one file, simply upload it and leave File 2 blank."
                )
              )
            )
          )
        ),

        tags$div(
          style = "background:#f4f6f8; border-radius:6px; padding:12px 18px; margin-bottom:24px;",
          tags$p(style = "margin:0; font-size:0.85rem; color:#555; line-height:1.7;",
            tags$strong("Column name flexibility: "),
            "The app recognizes common variants automatically \u2014 ",
            tags$code("lat"), ", ", tags$code("latitude"), ", ",
            tags$code("decimal_latitude"), ", ", tags$code("decimalLatitude"),
            " all map to the same field. You can also correct or override any
             auto-suggested mapping in the Map Fields step."
          )
        ),

        tags$hr(style = "border-color:#d0dce8; margin-bottom:24px;"),

        # What This App Does
        tags$h3("What This App Does",
          style = "font-size:1.1rem; font-weight:600; color:#2f6fab; margin-bottom:12px;"),
        tags$div(class = "bl-card", style = "margin-bottom:24px;",
          tags$p(style = "margin:0; font-size:0.93rem; line-height:1.65; color:#2c2c2c;",
            "Upload one or two CSV files of field observation records, map your column names
             to Darwin Core and BIEN staging schema fields, run automated taxonomy and
             geography validation via BIEN web services (TNRS, GNRS, GVS, NSR), and
             download a clean, validated dataset ready to load into the BIEN database."
          )
        ),

        # Four-Step Workflow
        tags$h3("Four-Step Workflow",
          style = "font-size:1.1rem; font-weight:600; color:#2f6fab; margin-bottom:16px;"),
        fluidRow(
          column(6,
            tags$div(class = "bl-card", style = "margin-bottom:16px; min-height:110px;",
              tags$span(class = "step-badge", "1"),
              tags$strong(" Upload & Merge",
                style = "font-size:0.97rem; color:#1a1a2e; margin-left:6px;"),
              tags$p(style = "margin:10px 0 0 0; font-size:0.88rem; line-height:1.6; color:#3a3a3a;",
                "Upload 1\u20132 CSV files. Optionally join them on a shared key column
                 to merge observation and plot metadata before processing.")
            )
          ),
          column(6,
            tags$div(class = "bl-card", style = "margin-bottom:16px; min-height:110px;",
              tags$span(class = "step-badge", "2"),
              tags$strong(" Map Fields",
                style = "font-size:0.97rem; color:#1a1a2e; margin-left:6px;"),
              tags$p(style = "margin:10px 0 0 0; font-size:0.88rem; line-height:1.6; color:#3a3a3a;",
                "Auto-suggest mappings from your column names to Darwin Core terms and
                 BIEN staging fields using column name aliases \u2014 e.g., ",
                tags$code("lat"), " \u2192 ", tags$code("decimalLatitude"), ", ",
                tags$code("species"), " \u2192 ", tags$code("scientificName"), ".")
            )
          )
        ),
        fluidRow(
          column(6,
            tags$div(class = "bl-card", style = "margin-bottom:16px; min-height:200px;",
              tags$span(class = "step-badge", "3"),
              tags$strong(" Stage & Validate",
                style = "font-size:0.97rem; color:#1a1a2e; margin-left:6px;"),
              tags$p(style = "margin:10px 0 0 0; font-size:0.88rem; line-height:1.6; color:#3a3a3a;",
                "Builds Darwin Core (DwC) + BIEN staging tables, then runs four validation services:"),
              tags$ul(
                style = "margin:6px 0 0 0; padding-left:18px; font-size:0.86rem; color:#3a3a3a; line-height:1.8;",
                tags$li(tags$strong("TNRS"), " \u2014 Resolves/scrubs scientific names against WCVP + WFO"),
                tags$li(tags$strong("GNRS"), " \u2014 Standardizes country / state / county"),
                tags$li(tags$strong("GVS"),  " \u2014 Flags coordinate-level political centroids"),
                tags$li(tags$strong("NSR"),  " \u2014 Assigns native / introduced / cultivated status per region")
              )
            )
          ),
          column(6,
            tags$div(class = "bl-card", style = "margin-bottom:16px; min-height:200px;",
              tags$span(class = "step-badge", "4"),
              tags$strong(" Export",
                style = "font-size:0.97rem; color:#1a1a2e; margin-left:6px;"),
              tags$p(style = "margin:10px 0 0 0; font-size:0.88rem; line-height:1.6; color:#3a3a3a;",
                "Download the validated output as a BIEN staging CSV or a Darwin Core CSV,
                 ready for database ingestion or archival. QC report and field mapping are
                 also available for provenance documentation.")
            )
          )
        ),

        tags$hr(style = "border-color:#d0dce8; margin:8px 0 24px 0;"),

        # Scientific Caveats
        tags$h3("Scientific Caveats",
          style = "font-size:1.1rem; font-weight:600; color:#8a6000; margin-bottom:12px;"),
        tags$div(class = "bl-card-warn", style = "margin-bottom:24px;",
          tags$ul(
            style = "margin:0; padding-left:20px; font-size:0.88rem; line-height:1.8; color:#3a2800;",
            tags$li(
              tags$strong("Name scrubbing collapses synonyms to accepted names."),
              " Review TNRS results carefully for ambiguous or multi-match cases before
               accepting scrubbed names. Inspect the ", tags$code("match_score"),
              " and ", tags$code("taxon_rank"), " fields \u2014 genus-only matches have
               lower inferential value than full species matches."
            ),
            tags$li(
              tags$strong("GNRS standardizes to political units."),
              " Sub-national precision depends on the spelling quality of your submitted
               locality strings."
            ),
            tags$li(
              tags$strong("Native, introduced, and cultivated status from NSR is region-specific"),
              " and may carry uncertainty for species near distributional boundaries or with
               complex histories. Cultivated records in particular should generally be excluded
               from range and SDM analyses."
            ),
            tags$li(
              tags$strong("Centroid flags do not remove records \u2014 they are informational."),
              " ", tags$code("is_centroid = 1"), " means the coordinate matches a known political
               centroid. ", tags$code("is_centroid = 0"), " means it was evaluated and is not a
               centroid. ", tags$code("is_centroid = NULL"), " means the check was not performed
               (e.g., missing coordinates or out-of-scope geography). Apply downstream QA rules
               based on your project\u2019s tolerance for positional imprecision."
            ),
            tags$li(
              tags$strong("scientificName authorship."),
              " The ", tags$code("species"), " column name alias maps to ",
              tags$code("scientificName"), " without authorship. Per Darwin Core, ",
              tags$code("scientificName"), " ideally includes authorship (e.g., ",
              tags$em("Quercus robur"), " L.). TNRS will parse bare binomials
               correctly, but authorship will be absent from output unless provided."
            )
          )
        ),

        # Technical Notes
        tags$h3("Technical Notes",
          style = "font-size:1.1rem; font-weight:600; color:#2f6fab; margin-bottom:12px;"),
        tags$div(
          style = "background:#f4f6f8; border-radius:6px; padding:16px 20px; margin-bottom:24px;",
          tags$ul(
            style = "margin:0; padding-left:20px; font-size:0.87rem; line-height:1.8; color:#444;",
            tags$li(
              "Validation API calls are routed through Cloudflare Worker relays (",
              tags$code("bien-relay-*.benquist.workers.dev"),
              ") to bypass network restrictions on the hosting platform."
            ),
            tags$li(
              "Taxonomy scrubbing writes results to ", tags$code("scrubbed_*"),
              " fields; original submitted names are always preserved."
            ),
            tags$li(
              "TNRS uses WCVP + WFO as name-matching backbones. These taxonomic
               backbones are versioned and updated periodically. For reproducibility,
               record the TNRS query date and note the backbone versions in your
               methods documentation."
            ),
            tags$li(
              "All API calls use a 10-second connect timeout. Records that fail due to
               timeout or upstream unavailability are returned with NULL validation fields \u2014
               check your results tabs for missing rows before treating the dataset as fully validated."
            ),
            tags$li(
              "NSR native/introduced/cultivated status is context-dependent \u2014 the same
               species may be native in one political region and introduced in another."
            )
          )
        ),

        tags$hr(style = "border-color:#d0dce8; margin-bottom:24px;"),

        # ── BIEN Staging Field Reference ──────────────────────────────────────
        tags$h3("BIEN Staging Field Reference",
          style = "font-size:1.1rem; font-weight:600; color:#2f6fab; margin-bottom:6px;"),
        tags$p(style = "font-size:0.88rem; color:#666; margin-bottom:12px;",
          "All recognized BIEN staging fields, their data category, and a plain-language definition.
           Search or scroll to find any field. This table drives the auto-mapping in Tab 2."),
        DT::dataTableOutput("help_field_ref"),
        tags$br(),

        tags$hr(style = "border-color:#d0dce8; margin-bottom:24px;"),

        # About / Credits
        tags$h3("About",
          style = "font-size:1.1rem; font-weight:600; color:#2f6fab; margin-bottom:12px;"),
        tags$div(class = "bl-card", style = "margin-bottom:40px;",
          tags$p(style = "margin:0 0 8px 0; font-size:0.9rem; line-height:1.65; color:#2c2c2c;",
            "Built for the ",
            tags$strong("BIEN (Botanical Information and Ecology Network)"), " project."),
          tags$p(style = "margin:0 0 8px 0; font-size:0.88rem; line-height:1.65; color:#444;",
            "TNRS, GNRS, GVS, and NSR validation services are maintained by the
             BIEN team at the University of Arizona."),
          tags$p(style = "margin:0; font-size:0.85rem; color:#777;",
            "Validation API documentation: ",
            tags$a(href="https://tnrsapi.xyz", target="_blank", rel="noopener noreferrer", "tnrsapi.xyz",
              style="color:#2f6fab;"), " \u00b7 ",
            tags$a(href="https://gnrsapi.xyz", target="_blank", rel="noopener noreferrer", "gnrsapi.xyz",
              style="color:#2f6fab;"), " \u00b7 ",
            tags$a(href="https://gvsapi.xyz",  target="_blank", rel="noopener noreferrer", "gvsapi.xyz",
              style="color:#2f6fab;"), " \u00b7 ",
            tags$a(href="https://nsrapi.xyz",  target="_blank", rel="noopener noreferrer", "nsrapi.xyz",
              style="color:#2f6fab;")
          )
        )
      ) # /column
    )   # /fluidRow
  )     # /tabPanel Help

)

# ── Server ────────────────────────────────────────────────────────────────────

server <- function(input, output, session) {

  rv <- reactiveValues(
    raw_files    = NULL,
    merged       = NULL,
    mapping_draft = NULL,
    mapping      = NULL,
    staged       = NULL,
    dwc          = NULL,
    qc           = NULL,
    tnrs_result  = NULL,
    gnrs_result  = NULL,
    gvs_result   = NULL,
    nsr_result   = NULL,
    completion_modal_shown = FALSE
  )

  # ── Resolve demo data path reliably regardless of working directory ──────────
  demo_data_path <- function(filename) {
    # 1. Relative to app directory (standard runApp)
    rel <- file.path("demo_data", filename)
    if (file.exists(rel)) return(rel)
    # 2. Relative to the directory of this script (shinyapps.io)
    app_dir <- tryCatch(dirname(sys.frame(1)$ofile), error=function(e) NULL)
    if (!is.null(app_dir)) {
      p <- file.path(app_dir, "demo_data", filename)
      if (file.exists(p)) return(p)
    }
    NULL
  }

  approved_mapping_choices <- list(
    dwc = c("", DWC_TERMS),
    bien = c("", BIEN_STAGING_FIELDS)
  )

  build_mapping_select_html <- function(selected, choices, select_class, row_idx) {
    selected_val <- if (is.null(selected) || is.na(selected)) "" else as.character(selected)
    option_tags <- vapply(choices, function(choice) {
      label <- if (nzchar(choice)) choice else " "
      paste0(
        "<option value=\"", htmltools::htmlEscape(choice), "\"",
        if (identical(choice, selected_val)) " selected" else "",
        ">", htmltools::htmlEscape(label), "</option>"
      )
    }, character(1))
    paste0(
      "<select class='form-control input-sm ", select_class, "' data-row='", row_idx,
      "' style='min-width:220px;'>",
      paste(option_tags, collapse = ""),
      "</select>"
    )
  }

  # ── Load raw files whenever source changes (for column detection only) ──────
  observe({
    # Clear all downstream state when source switches
    rv$merged <- NULL; rv$mapping_draft <- NULL; rv$mapping <- NULL
    rv$staged <- NULL; rv$dwc <- NULL; rv$qc <- NULL
    rv$tnrs_result <- NULL; rv$gnrs_result <- NULL
    rv$gvs_result  <- NULL; rv$nsr_result  <- NULL
  rv$completion_modal_shown <- FALSE

    if (isTRUE(input$use_demo)) {
      obs_path  <- demo_data_path("observations.csv")
      meta_path <- demo_data_path("plot_metadata.csv")
      if (is.null(obs_path) || is.null(meta_path)) {
        showNotification("Demo data files not found. Check that demo_data/ folder is present.",
                         type="error", duration=12)
        return()
      }
      rv$raw_files <- list(
        "observations.csv"  = read.csv(obs_path,  stringsAsFactors=FALSE, check.names=FALSE),
        "plot_metadata.csv" = read.csv(meta_path, stringsAsFactors=FALSE, check.names=FALSE)
      )
      # Strip completely blank rows from demo data
      rv$raw_files <- lapply(rv$raw_files, blank_row_filter)
    } else if (!is.null(input$files)) {
      too_large <- input$files$name[input$files$size > 100 * 1024 * 1024]
      if (length(too_large) > 0) {
        rv$raw_files <- NULL
        showNotification(
          paste0(
            "Upload rejected: file(s) exceed app maximum upload size (100 MB): ",
            paste(too_large, collapse = ", "),
            "."
          ),
          type = "error", duration = 12
        )
        return()
      }

      total_bytes <- sum(input$files$size)
      if (total_bytes > 200 * 1024^2) {
        rv$raw_files <- NULL
        showNotification(
          paste0("Upload rejected: combined size (", round(total_bytes / 1024^2, 1),
                 " MB) exceeds the 200 MB aggregate limit. Upload fewer or smaller files."),
          type = "error", duration = 12
        )
        return()
      }

      # Basic file size guard: warn if any file > 50 MB
      large <- input$files$name[input$files$size > 50 * 1024 * 1024]
      if (length(large) > 0) {
        showNotification(paste0("Large file(s) detected (> 50 MB): ",
          paste(large, collapse=", "), ". Loading may be slow. App upload limit is 100 MB per file."),
          type="warning", duration=10)
      }

      loaded <- tryCatch(
        {
          setNames(
            lapply(seq_along(input$files$datapath), function(i) {
              p <- input$files$datapath[[i]]
              n <- input$files$name[[i]]
              df <- safe_read_csv_with_fallbacks(p, file_label = n)
              blank_row_filter(df)
            }),
            input$files$name
          )
        },
        error = function(e) e
      )

      if (inherits(loaded, "error")) {
        rv$raw_files <- NULL
        showNotification(
          paste0("Upload failed. Please check CSV delimiter/encoding and retry. ", conditionMessage(loaded)),
          type = "error", duration = 12
        )
        return()
      }

      rv$raw_files <- loaded
    }
  })

  # ── Primary file selector ─────────────────────────────────────────────────
  output$primary_file_ui <- renderUI({
    req(rv$raw_files)
    fnames <- names(rv$raw_files)
    # Auto-select the file with the most rows (usually the observation/survey file)
    best_primary <- fnames[which.max(sapply(rv$raw_files, nrow))]
    selectInput("primary_file",
      "Primary observation file (file with most rows auto-selected — adjust if needed)",
      choices=fnames, selected=best_primary)
  })

  # ── Join key UI ───────────────────────────────────────────────────────────
  output$join_key_ui <- renderUI({
    req(rv$raw_files)
    req(input$primary_file)
    primary <- input$primary_file
    others  <- setdiff(names(rv$raw_files), primary)
    if (length(others) == 0) return(tags$p(style="color:#555; font-size:0.85em;",
      "Single file — no join needed."))

    tagList(lapply(others, function(f) {
      prim_cols <- names(rv$raw_files[[primary]])
      meta_cols <- names(rv$raw_files[[f]])
      # Auto-guess matching keys by canonical name intersection
      can_prim <- setNames(prim_cols, canonicalize(prim_cols))
      can_meta <- setNames(meta_cols, canonicalize(meta_cols))
      shared   <- intersect(names(can_prim), names(can_meta))
      pk_guess <- if (length(shared) > 0) can_prim[[shared[1]]] else prim_cols[[1]]
      fk_guess <- if (length(shared) > 0) can_meta[[shared[1]]] else meta_cols[[1]]

      tags$div(
        tags$p(style="font-weight:600; margin:8px 0 4px;",
               paste0("Join \u2192 ", f)),
        fluidRow(
          column(6, selectInput(paste0("pk_", make.names(f)),
                                paste("Key in", primary),
                                choices=prim_cols, selected=pk_guess)),
          column(6, selectInput(paste0("fk_", make.names(f)),
                                paste("Key in", f),
                                choices=meta_cols, selected=fk_guess))
        )
      )
    }))
  })

  # ── Step 1: Prepare (merge) ───────────────────────────────────────────────
  observeEvent(input$btn_prepare, {
    req(rv$raw_files)
    tryCatch({
      primary <- if (!is.null(input$primary_file) && nzchar(input$primary_file)) {
        input$primary_file
      } else names(rv$raw_files)[[1]]

      merged <- rv$raw_files[[primary]]
      others <- setdiff(names(rv$raw_files), primary)

      for (f in others) {
        pk  <- input[[paste0("pk_", make.names(f))]]
        fk  <- input[[paste0("fk_", make.names(f))]]
        if (is.null(pk) || !nzchar(pk)) pk <- names(merged)[[1]]
        if (is.null(fk) || !nzchar(fk)) fk <- names(rv$raw_files[[f]])[[1]]

        meta <- rv$raw_files[[f]]
        meta <- meta[!duplicated(meta[[fk]]), , drop=FALSE]
        merged <- merge(merged, meta, by.x=pk, by.y=fk, all.x=TRUE,
                        suffixes=c("", paste0(".", make.names(f))))
      }

      rv$merged        <- merged
      rv$mapping_draft <- suggest_mapping(names(merged))
      rv$mapping       <- NULL
      rv$staged        <- NULL
      rv$dwc           <- NULL
      rv$qc            <- NULL
      rv$tnrs_result   <- NULL
      rv$gnrs_result   <- NULL
      rv$gvs_result    <- NULL

      showModal(modalDialog(
        title = "Step 1 complete",
        tags$p("Your dataset is prepared."),
        tags$p("Why this matters: mapping each source column to approved Darwin Core and BIEN fields ensures a valid schema and reliable staging outputs."),
        easyClose = TRUE,
        footer = tagList(
          actionButton("btn_go_map", "Go to 2 \u2022 Map Fields \u2192", class = "btn btn-primary"),
          modalButton("Close")
        )
      ))
      rv$nsr_result    <- NULL
    }, error = function(e) {
      showNotification(
        paste0("Prepare Dataset failed: ", conditionMessage(e),
               " — check that your join key columns exist in both files."),
        type = "error", duration = 15
      )
    })
  })

  output$step1_status <- renderUI({
    if (is.null(rv$merged)) return(NULL)
    tags$div(class="bl-card bl-card-pass", style="margin-top:10px;",
      tags$strong("Dataset ready"),
      tags$br(),
      paste0(nrow(rv$merged), " rows \u00d7 ", ncol(rv$merged), " columns"),
      tags$br(),
      paste0("Files: ", paste(names(rv$raw_files), collapse=", ")),
      tags$hr(style="margin:8px 0;"),
      tags$span(style="color:#36556e;",
        "Next: Click '2 \u2022 Map Fields' to confirm how your source columns map to approved Darwin Core and BIEN fields before staging.")
    )
  })

  output$preview_header <- renderUI({
    if (is.null(rv$merged)) return(tags$div(class="bl-card",
      tags$em("Click \u2018Prepare Dataset\u2019 to load and merge your files.")))
    tags$div(class="bl-card",
      tags$strong("Merged data preview (first 8 rows)"))
  })

  output$preview_table <- DT::renderDataTable({
    req(rv$merged)
    DT::datatable(utils::head(rv$merged, 8), rownames=FALSE,
      options=list(pageLength=8, scrollX=TRUE, dom='t'))
  }, server=FALSE)

  # ── Tab 2 gating ─────────────────────────────────────────────────────────
  output$tab2_gating <- renderUI({
    if (is.null(rv$merged)) {
      tags$div(class="bl-card bl-card-warn",
        tags$strong("Complete Step 1 first: "),
        "Go to \u20181 \u2022 Upload & Merge\u2019 and click Prepare Dataset.")
    }
  })

  # ── Help tab: Field Reference table ───────────────────────────────────────
  output$help_field_ref <- DT::renderDataTable({
    flds <- names(BIEN_FIELD_DEFS)
    df <- data.frame(
      Field      = flds,
      Category   = unname(BIEN_FIELD_CATEGORY[flds]),
      Definition = unname(BIEN_FIELD_DEFS[flds]),
      stringsAsFactors = FALSE
    )
    DT::datatable(
      df,
      rownames = FALSE,
      colnames = c("BIEN Field", "Category", "Definition"),
      options  = list(pageLength=15, scrollX=TRUE, dom='frtip',
        columnDefs=list(list(width='180px', targets=0),
                        list(width='120px', targets=1),
                        list(className='dt-wrap', targets=2))),
      class    = "stripe hover compact"
    )
  }, server=FALSE)

  # ── Step 2: Mapping table (editable DT) ───────────────────────────────────
  output$mapping_table <- DT::renderDataTable({
    req(rv$mapping_draft)
    mapping_view <- rv$mapping_draft
    mapping_view$dwc_term <- vapply(seq_len(nrow(mapping_view)), function(i) {
      build_mapping_select_html(
        selected = mapping_view$dwc_term[i],
        choices = approved_mapping_choices$dwc,
        select_class = "map-dwc",
        row_idx = i
      )
    }, character(1))
    mapping_view$bien_field <- vapply(seq_len(nrow(mapping_view)), function(i) {
      build_mapping_select_html(
        selected = mapping_view$bien_field[i],
        choices = approved_mapping_choices$bien,
        select_class = "map-bien",
        row_idx = i
      )
    }, character(1))
    DT::datatable(
      mapping_view,
      editable = FALSE,
      escape = FALSE,
      rownames = FALSE,
      colnames = c("Source Column", "Suggested DWC Term", "Suggested BIEN Field"),
      options  = list(pageLength=30, scrollX=TRUE, dom='frtip'),
      caption  = "Use dropdowns only: choose approved Darwin Core and BIEN fields (or leave blank). Do not type or invent BIEN/Darwin field strings. Then click Apply Mapping.",
      callback = DT::JS(
        "table.on('change', 'select.map-dwc', function() {",
        "  var row = $(this).data('row');",
        "  Shiny.setInputValue('mapping_dwc_change', {row: row, value: this.value, nonce: Math.random()}, {priority: 'event'});",
        "});",
        "table.on('change', 'select.map-bien', function() {",
        "  var row = $(this).data('row');",
        "  Shiny.setInputValue('mapping_bien_change', {row: row, value: this.value, nonce: Math.random()}, {priority: 'event'});",
        "});"
      )
    )
  }, server=FALSE)

  observeEvent(input$mapping_dwc_change, {
    req(rv$mapping_draft)
    info <- input$mapping_dwc_change
    row_idx <- suppressWarnings(as.integer(info$row))
    if (is.na(row_idx) || row_idx < 1 || row_idx > nrow(rv$mapping_draft)) return()
    val <- if (is.null(info$value)) "" else as.character(info$value)
    if (!(val %in% approved_mapping_choices$dwc)) return()
    df <- rv$mapping_draft
    df$dwc_term[row_idx] <- if (nzchar(val)) val else NA_character_
    rv$mapping_draft <- df
  })

  observeEvent(input$mapping_bien_change, {
    req(rv$mapping_draft)
    info <- input$mapping_bien_change
    row_idx <- suppressWarnings(as.integer(info$row))
    if (is.na(row_idx) || row_idx < 1 || row_idx > nrow(rv$mapping_draft)) return()
    val <- if (is.null(info$value)) "" else as.character(info$value)
    if (!(val %in% approved_mapping_choices$bien)) return()
    df <- rv$mapping_draft
    df$bien_field[row_idx] <- if (nzchar(val)) val else NA_character_
    rv$mapping_draft <- df
  })

  observeEvent(input$btn_apply_mapping, {
    req(rv$mapping_draft)
    req(rv$merged)
    # Build mapping, staging and DWC in one tryCatch
    tryCatch({
      mapping <- rv$mapping_draft
      mapping$source_col  <- as.character(mapping$source_col)
      mapping$dwc_term    <- as.character(mapping$dwc_term)
      mapping$bien_field  <- as.character(mapping$bien_field)
      rv$mapping <- mapping
      rv$staged  <- build_staging(rv$merged, rv$mapping)
      rv$dwc     <- build_dwc(rv$merged, rv$mapping)
    }, error = function(e) {
      showNotification(
        paste0("Apply Mapping failed: ", conditionMessage(e)),
        type = "error", duration = 15
      )
    })
    # Run QC in a separate tryCatch so staging is never lost if QC errors
    if (!is.null(rv$staged)) {
      tryCatch({
        rv$qc <- run_qc(rv$staged)
      }, error = function(e) {
        showNotification(
          paste0("QC check failed: ", conditionMessage(e),
                 " — staging table is still available for download."),
          type = "warning", duration = 15
        )
      })
    }

    if (!is.null(rv$mapping) && !is.null(rv$staged)) {
      showModal(modalDialog(
        title = "Step 2 complete",
        "Mapping has been applied.",
        tags$p("Reason: this mapping created BIEN staging and Darwin Core outputs for review before export."),
        easyClose = TRUE,
        footer = tagList(
          actionButton("btn_go_stage", "Go to 3 \u2022 Stage & Validate \u2192", class = "btn btn-primary"),
          modalButton("Close")
        )
      ))
    }
  })

  observeEvent(input$btn_go_map, {
    removeModal()
    updateNavbarPage(session, "tabs", selected = "2 \u2022 Map Fields")
  })

  observeEvent(input$btn_go_stage, {
    removeModal()
    updateNavbarPage(session, "tabs", selected = "3 \u2022 Stage & Validate")
  })

  output$step2_status_inline <- renderUI({
    if (is.null(rv$mapping)) return(NULL)
    n_dwc  <- sum(!is.na(rv$mapping$dwc_term) & nzchar(trimws(rv$mapping$dwc_term)))
    n_bien <- sum(!is.na(rv$mapping$bien_field) & nzchar(trimws(rv$mapping$bien_field)))
    tags$span(style="color:#27ae60; font-weight:600;",
      paste0("Mapping applied \u2014 ", n_dwc, " DWC terms, ", n_bien, " BIEN fields mapped. Next: open '3 \u2022 Stage & Validate'."))
  })

  # ── Tab 3 gating ─────────────────────────────────────────────────────────
  output$tab3_gating <- renderUI({
    if (is.null(rv$mapping)) {
      tags$div(class="bl-card bl-card-warn",
        tags$strong("Complete Step 2 first: "),
        "Go to \u20182 \u2022 Map Fields\u2019 and click Apply Mapping.")
    } else {
      tags$div(class="bl-card",
        tags$strong("Next in Step 3: "),
        "Review the staging table and QC details here, then continue to '4 \u2022 Export' when everything looks correct.")
    }
  })

  # ── QC summary ───────────────────────────────────────────────────────────
  output$qc_summary_ui <- renderUI({
    if (is.null(rv$qc)) return(tags$div(class="bl-card",
      tags$em("Apply mapping to see QC results.")))

    qc <- rv$qc
    n_pass  <- sum(qc$severity == "PASS",  na.rm=TRUE)
    n_warn  <- sum(qc$severity == "WARN",  na.rm=TRUE)
    n_block <- sum(qc$severity == "BLOCK", na.rm=TRUE)

    card_cls <- if (n_block > 0) "bl-card bl-card-block" else
                if (n_warn  > 0) "bl-card bl-card-warn"  else "bl-card bl-card-pass"

    verdict <- if (n_block > 0) "Export caution \u2014 review BLOCK issues" else
               if (n_warn  > 0) "Ready with warnings" else "All checks passed"

    tags$div(class=card_cls,
      tags$strong(verdict),
      tags$ul(style="margin:6px 0 0; padding-left:16px;",
        tags$li(style="color:#27ae60;", paste0("PASS: ", n_pass)),
        tags$li(style="color:#e6a817;", paste0("WARN: ", n_warn)),
        tags$li(style="color:#c0392b;", paste0("BLOCK: ", n_block))
      )
    )
  })

  # ── Stage/DWC/QC tables ───────────────────────────────────────────────────
  output$staged_table <- DT::renderDataTable({
    req(rv$staged)
    DT::datatable(rv$staged, rownames=FALSE,
      options=list(pageLength=10, scrollX=TRUE))
  }, server=TRUE)

  output$dwc_table <- DT::renderDataTable({
    req(rv$dwc)
    DT::datatable(rv$dwc, rownames=FALSE,
      options=list(pageLength=10, scrollX=TRUE))
  }, server=TRUE)

  output$qc_table <- DT::renderDataTable({
    req(rv$qc)
    DT::datatable(rv$qc, rownames=FALSE,
      options=list(pageLength=20, scrollX=TRUE),
      callback=DT::JS("
        table.on('draw', function() {
          table.rows().every(function() {
            var data = this.data();
            var sev  = data[data.length-2];
            if (sev === 'BLOCK') $(this.node()).css('color','#c0392b');
            else if (sev === 'WARN') $(this.node()).css('color','#b07d00');
          });
        });
      ")
    )
  }, server=TRUE)

  # ── TNRS ─────────────────────────────────────────────────────────────────
  observeEvent(input$btn_tnrs, {
    if (is.null(rv$staged)) {
      showNotification("No staging table found — complete Steps 1-3 (Upload, Map Fields, Apply Mapping) before running TNRS.",
                       type="error", duration=10)
      return()
    }
    names_vec <- unique(trimws(as.character(rv$staged$scrubbed_species_binomial)))
    names_vec <- names_vec[!is.na(names_vec) & names_vec != ""]
    n_total <- length(names_vec)

    if (n_total == 0) {
      rv$tnrs_result <- data.frame(
        note = paste0("No species names found in 'scrubbed_species_binomial'. ",
                      "Check that your field mapping routes the species name column to scrubbed_species_binomial, ",
                      "then re-apply mapping before running TNRS."),
        stringsAsFactors = FALSE)
      return()
    }

    if (n_total > 20) {
      names_vec <- names_vec[seq_len(20)]
      showNotification(paste0("TNRS capped to first 20 of ", n_total,
        " unique names."),
        type="warning", duration=8)
    }

    withProgress(message="Submitting to TNRS\u2026", value=0.2, {
      err_msg <- NULL
      result <- tryCatch({
        tnrs_data <- data.frame(
          id = seq_along(names_vec),
          Name_submitted = names_vec,
          stringsAsFactors = FALSE
        )
        tnrs_body <- jsonlite::toJSON(
          list(opts = list(mode="resolve", matches="best", sources="wcvp,wfo", acc=1L),
               data = tnrs_data),
          auto_unbox = TRUE
        )
        resp <- httr::POST(
          TNRS_URL,
          body = tnrs_body,
          httr::content_type("application/json"),
          httr::config(connecttimeout = 10),
          httr::timeout(120)
        )
        setProgress(0.8)
        code <- httr::status_code(resp)
        if (code == 200) {
          txt <- httr::content(resp, "text", encoding="UTF-8")
          df  <- tryCatch(jsonlite::fromJSON(txt, flatten=TRUE), error=function(e) {
            err_msg <<- paste0("TNRS returned 200 but response could not be parsed: ", conditionMessage(e))
            NULL
          })
          if (is.data.frame(df) && nrow(df) > 0) df else {
            if (is.null(err_msg)) err_msg <<- "TNRS returned 200 but no rows in response."
            NULL
          }
        } else {
          body_txt <- tryCatch(httr::content(resp, "text", encoding="UTF-8"), error=function(e) "")
          err_msg <<- paste0("TNRS HTTP ", code, ": ", substr(body_txt, 1, 200))
          NULL
        }
      }, error=function(e) {
        err_msg <<- paste0("TNRS connection error: ", conditionMessage(e))
        NULL
      })

      setProgress(1.0)
      rv$tnrs_result <- if (is.null(result)) {
        data.frame(note = if (!is.null(err_msg)) err_msg else
                         "TNRS request failed (unknown error).",
                   stringsAsFactors = FALSE)
      } else result

      # ── Write TNRS results back to staging scrubbed_* fields ────────────
      if (!is.null(rv$staged) && is.data.frame(rv$tnrs_result) &&
          !"note" %in% names(rv$tnrs_result) &&
          "Name_submitted" %in% names(rv$tnrs_result)) {
        tnrs <- rv$tnrs_result
        stg  <- rv$staged
        stg_names_key <- trimws(stg$scrubbed_species_binomial)
        for (i in seq_len(nrow(tnrs))) {
          submitted <- tnrs$Name_submitted[i]
          rows <- which(stg_names_key == trimws(submitted))
          if (length(rows) == 0) next
          # Accepted name (prefer Accepted_name, fall back to Name_matched)
          acc <- NA_character_
          for (col in c("Accepted_name", "Name_matched")) {
            if (col %in% names(tnrs) && !is.na(tnrs[[col]][i]) && nzchar(trimws(tnrs[[col]][i]))) {
              acc <- tnrs[[col]][i]; break
            }
          }
          if (!is.na(acc)) stg$scrubbed_species_binomial[rows] <- acc
          # Family
          for (col in c("Accepted_family", "Family")) {
            if (col %in% names(tnrs) && !is.na(tnrs[[col]][i]) && nzchar(trimws(tnrs[[col]][i]))) {
              stg$scrubbed_family[rows] <- tnrs[[col]][i]; break
            }
          }
          # Genus
          for (col in c("Genus_matched", "Genus")) {
            if (col %in% names(tnrs) && !is.na(tnrs[[col]][i]) && nzchar(trimws(tnrs[[col]][i]))) {
              stg$scrubbed_genus[rows] <- tnrs[[col]][i]; break
            }
          }
          # Author
          for (col in c("Accepted_name_author", "Author_matched")) {
            if (col %in% names(tnrs) && !is.na(tnrs[[col]][i]) && nzchar(trimws(tnrs[[col]][i]))) {
              stg$scrubbed_author[rows] <- tnrs[[col]][i]; break
            }
          }
          # Taxonomic status
          for (col in c("Taxonomic_status", "Name_matched_status")) {
            if (col %in% names(tnrs) && !is.na(tnrs[[col]][i]) && nzchar(trimws(tnrs[[col]][i]))) {
              stg$scrubbed_taxonomic_status[rows] <- tnrs[[col]][i]; break
            }
          }
        }
        rv$staged <- stg
        showNotification(
          paste0("TNRS complete: scrubbed_* fields updated for ", nrow(tnrs), " name(s)."),
          type="message", duration=6)
      }
    })
  })

  output$tnrs_status_ui <- renderUI({
    if (is.null(rv$tnrs_result)) return(NULL)
    if ("note" %in% names(rv$tnrs_result)) {
      tags$p(style="color:#c0392b; font-size:0.85em; margin-top:4px;",
             rv$tnrs_result$note[1])
    } else {
      tags$p(style="color:#27ae60; font-size:0.85em; margin-top:4px;",
             paste0("TNRS complete: ", nrow(rv$tnrs_result), " name(s) returned"))
    }
  })

  output$tnrs_table <- DT::renderDataTable({
    req(rv$tnrs_result)
    DT::datatable(rv$tnrs_result, rownames=FALSE,
      options=list(pageLength=20, scrollX=TRUE))
  }, server=TRUE)

  # ── GNRS ─────────────────────────────────────────────────────────────────
  observeEvent(input$btn_gnrs, {
    if (is.null(rv$staged)) {
      showNotification("No staging table found — complete Steps 1-3 (Upload, Map Fields, Apply Mapping) before running GNRS.",
                       type="error", duration=10)
      return()
    }
    geo_cols <- intersect(c("country","state_province","county"), names(rv$staged))
    if (length(geo_cols) == 0) {
      rv$gnrs_result <- data.frame(note="No geography columns (country/state_province/county) found in staging table.",
                                   stringsAsFactors=FALSE)
      return()
    }

    geo_tbl <- unique(rv$staged[, geo_cols, drop=FALSE])
    geo_tbl <- geo_tbl[rowSums(!is.na(geo_tbl) & geo_tbl != "") > 0, , drop=FALSE]
    # GNRS expects DWC column names: country, stateProvince, county (+ id)
    names(geo_tbl) <- gsub("state_province", "stateProvince", names(geo_tbl))
    if (!"county" %in% names(geo_tbl)) geo_tbl$county <- ""
    geo_tbl <- data.frame(id=seq_len(nrow(geo_tbl)), geo_tbl, stringsAsFactors=FALSE)

    withProgress(message="Submitting to GNRS\u2026", value=0.2, {
      err_msg <- NULL
      result <- tryCatch({
        gnrs_body <- jsonlite::toJSON(
          list(opts = list(mode="resolve", sources="geonames,gadm"),
               data = geo_tbl),
          auto_unbox = TRUE
        )
        resp <- httr::POST(
          GNRS_URL,
          body = gnrs_body,
          httr::content_type("application/json"),
          httr::config(connecttimeout = 10),
          httr::timeout(120)
        )
        setProgress(0.8)
        code <- httr::status_code(resp)
        if (code == 200) {
          txt <- httr::content(resp, "text", encoding="UTF-8")
          df  <- tryCatch(jsonlite::fromJSON(txt, flatten=TRUE), error=function(e) {
            err_msg <<- paste0("GNRS returned 200 but response could not be parsed: ", conditionMessage(e))
            NULL
          })
          if (is.data.frame(df) && nrow(df) > 0) df else {
            if (is.null(err_msg)) err_msg <<- "GNRS returned 200 but no rows in response."
            NULL
          }
        } else {
          body_txt <- tryCatch(httr::content(resp, "text", encoding="UTF-8"), error=function(e) "")
          err_msg <<- paste0("GNRS HTTP ", code, ": ", substr(body_txt, 1, 200))
          NULL
        }
      }, error=function(e) {
        err_msg <<- paste0("GNRS connection error: ", conditionMessage(e))
        NULL
      })

      setProgress(1.0)
      rv$gnrs_result <- if (is.null(result)) {
        data.frame(note = if (!is.null(err_msg)) err_msg else
                         "GNRS request failed (unknown error).",
                   stringsAsFactors = FALSE)
      } else result

      # ── Write GNRS matched geography back to staging ─────────────────────
      if (!is.null(rv$staged) && is.data.frame(rv$gnrs_result) &&
          !"note" %in% names(rv$gnrs_result)) {
        gnrs <- rv$gnrs_result
        stg  <- rv$staged
        # GNRS returns country_matched, stateProvince_matched, county_matched
        # Join by submitted values to update staging rows
        cty_col   <- intersect(c("Country_matched",   "country_matched",   "country"),   names(gnrs))[1]
        state_col <- intersect(c("StateProvince_matched", "stateProvince_matched", "stateProvince"), names(gnrs))[1]
        coun_col  <- intersect(c("County_matched",    "county_matched",    "county"),    names(gnrs))[1]
        sub_cty   <- intersect(c("country"),   names(gnrs))[1]
        sub_state <- intersect(c("stateProvince"), names(gnrs))[1]
        if (!is.na(cty_col) && !is.na(sub_cty) && !is.na(sub_state)) {
          for (i in seq_len(nrow(gnrs))) {
            cty_match   <- trimws(stg$country) == trimws(gnrs[[sub_cty]][i])
            state_submitted <- trimws(gnrs[[sub_state]][i])
            state_match <- is.na(stg$state_province) | trimws(stg$state_province) == "" |
                           state_submitted == "" |
                           trimws(stg$state_province) == state_submitted
            rows <- which(cty_match & state_match)
            if (length(rows) == 0) next
            if (!is.na(cty_col)   && !is.na(gnrs[[cty_col]][i])   && nzchar(gnrs[[cty_col]][i]))   stg$country[rows]        <- gnrs[[cty_col]][i]
            if (!is.na(state_col) && !is.na(gnrs[[state_col]][i]) && nzchar(gnrs[[state_col]][i])) stg$state_province[rows] <- gnrs[[state_col]][i]
            if (!is.na(coun_col)  && !is.na(gnrs[[coun_col]][i])  && nzchar(gnrs[[coun_col]][i]))  stg$county[rows]         <- gnrs[[coun_col]][i]
          }
          rv$staged <- stg
          showNotification(
            paste0("GNRS complete: geography validated for ", nrow(gnrs), " location(s)."),
            type="message", duration=6)
        }
      }
    })
  })

  output$gnrs_status_ui <- renderUI({
    if (is.null(rv$gnrs_result)) return(NULL)
    if ("note" %in% names(rv$gnrs_result)) {
      tags$p(style="color:#c0392b; font-size:0.85em; margin-top:4px;",
             rv$gnrs_result$note[1])
    } else {
      tags$p(style="color:#27ae60; font-size:0.85em; margin-top:4px;",
             paste0("GNRS complete: ", nrow(rv$gnrs_result), " record(s) checked"))
    }
  })

  output$gnrs_table <- DT::renderDataTable({
    req(rv$gnrs_result)
    DT::datatable(rv$gnrs_result, rownames=FALSE,
      options=list(pageLength=20, scrollX=TRUE))
  }, server=TRUE)

  # ── GVS ──────────────────────────────────────────────────────────────────
  observeEvent(input$btn_gvs, {
    if (is.null(rv$staged)) {
      showNotification("No staging table found — complete Steps 1-3 (Upload, Map Fields, Apply Mapping) before running GVS.",
                       type="error", duration=10)
      return()
    }
    coord_cols <- intersect(c("latitude","longitude"), names(rv$staged))
    if (length(coord_cols) < 2) {
      rv$gvs_result <- data.frame(
        note="Staging table must have both 'latitude' and 'longitude' columns for GVS.",
        stringsAsFactors=FALSE)
      return()
    }
    coord_tbl <- unique(rv$staged[, c("latitude","longitude"), drop=FALSE])
    coord_tbl <- coord_tbl[
      !is.na(coord_tbl$latitude) & trimws(coord_tbl$latitude) != "" &
      !is.na(coord_tbl$longitude) & trimws(coord_tbl$longitude) != "", , drop=FALSE]
    if (nrow(coord_tbl) == 0) {
      rv$gvs_result <- data.frame(
        note="No valid coordinate pairs found in staging table.",
        stringsAsFactors=FALSE)
      return()
    }
    # GVS expects an unkeyed 2-column matrix [[lat,lon],[lat,lon],...] with numeric values
    gvs_data <- lapply(seq_len(nrow(coord_tbl)), function(i)
      c(as.numeric(trimws(coord_tbl$latitude[i])), as.numeric(trimws(coord_tbl$longitude[i]))))

    withProgress(message="Submitting to GVS\u2026", value=0.2, {
      err_msg <- NULL
      result <- tryCatch({
        gvs_body <- jsonlite::toJSON(
          list(opts = list(mode = "resolve"), data = gvs_data),
          auto_unbox = TRUE
        )
        resp <- httr::POST(
          GVS_URL,
          body = gvs_body,
          httr::content_type("application/json"),
          httr::add_headers(Accept="application/json", charset="UTF-8"),
          httr::config(connecttimeout=10),
          httr::timeout(120)
        )
        setProgress(0.8)
        code <- httr::status_code(resp)
        if (code == 200) {
          txt <- httr::content(resp, "text", encoding="UTF-8")
          df  <- tryCatch(jsonlite::fromJSON(txt, flatten=TRUE), error=function(e) {
            err_msg <<- paste0("GVS returned 200 but response could not be parsed: ", conditionMessage(e))
            NULL
          })
          if (is.data.frame(df) && nrow(df) > 0) df else {
            if (is.null(err_msg)) err_msg <<- "GVS returned 200 but no rows in response."
            NULL
          }
        } else {
          body_txt <- tryCatch(httr::content(resp, "text", encoding="UTF-8"), error=function(e) "")
          err_msg <<- paste0("GVS HTTP ", code, ": ", substr(body_txt, 1, 200))
          NULL
        }
      }, error=function(e) {
        err_msg <<- paste0("GVS connection error: ", conditionMessage(e))
        NULL
      })

      setProgress(1.0)
      rv$gvs_result <- if (is.null(result)) {
        data.frame(note = if (!is.null(err_msg)) err_msg else
                         "GVS request failed (unknown error).",
                   stringsAsFactors=FALSE)
      } else result

      # ── Write GVS results back to staging (BIEN DB: is_centroid field) ───
      if (!is.null(rv$staged) && is.data.frame(rv$gvs_result) &&
          !"note" %in% names(rv$gvs_result) && nrow(rv$gvs_result) > 0) {
        tryCatch({
          gvs <- rv$gvs_result
          stg <- rv$staged
          lat_col <- intersect(c("latitude_verbatim","latitude"), names(gvs))[1]
          lon_col <- intersect(c("longitude_verbatim","longitude"), names(gvs))[1]
          if (!is.na(lat_col) && !is.na(lon_col) && "is_centroid" %in% names(stg)) {
            for (i in seq_len(nrow(gvs))) {
              rows <- which(
                trimws(as.character(stg$latitude))  == trimws(as.character(gvs[[lat_col]][i])) &
                trimws(as.character(stg$longitude)) == trimws(as.character(gvs[[lon_col]][i]))
              )
              if (length(rows) == 0) next
              centroid_val <- "0"
              for (cflag in c("is_country_centroid","is_state_centroid","is_county_centroid")) {
                if (cflag %in% names(gvs) && !is.na(gvs[[cflag]][i]) &&
                    as.character(gvs[[cflag]][i]) %in% c("1","TRUE","true")) {
                  centroid_val <- "1"; break
                }
              }
              stg$is_centroid[rows] <- centroid_val
            }
            rv$staged <- stg
          }
        }, error=function(e) {
          showNotification(paste0("GVS writeback error: ", conditionMessage(e)),
                           type="warning", duration=8)
        })
        showNotification(
          paste0("GVS complete: ", nrow(rv$gvs_result), " coordinate pair(s) validated."),
          type="message", duration=6)
      }
    })
  })

  output$gvs_status_ui <- renderUI({
    if (is.null(rv$gvs_result)) return(NULL)
    if ("note" %in% names(rv$gvs_result)) {
      tags$p(style="color:#c0392b; font-size:0.85em; margin-top:4px;",
             rv$gvs_result$note[1])
    } else {
      tags$p(style="color:#27ae60; font-size:0.85em; margin-top:4px;",
             paste0("GVS complete: ", nrow(rv$gvs_result), " coordinate pair(s) checked"))
    }
  })

  output$gvs_table <- DT::renderDataTable({
    req(rv$gvs_result)
    DT::datatable(rv$gvs_result, rownames=FALSE,
      options=list(pageLength=20, scrollX=TRUE))
  }, server=TRUE)

  output$dl_gvs_script <- downloadHandler(
    filename = function() paste0("gvs_validation_", Sys.Date(), ".R"),
    contentType = "text/plain",
    content = function(file) {
      coord_tbl <- if (!is.null(rv$staged) &&
                       all(c("latitude","longitude") %in% names(rv$staged))) {
        u <- unique(rv$staged[, c("latitude","longitude"), drop=FALSE])
        u <- u[!is.na(u$latitude) & trimws(u$latitude) != "" &
               !is.na(u$longitude) & trimws(u$longitude) != "", , drop=FALSE]
        u
      } else NULL

      data_r <- if (!is.null(coord_tbl) && nrow(coord_tbl) > 0) {
        rows <- apply(coord_tbl, 1, function(r) paste0('  c("', r["latitude"], '","', r["longitude"], '")'))
        paste0("list(\n", paste(rows, collapse=",\n"), "\n)")
      } else {
        'list(c("34.42","-119.7"), c("39.55","-105.78"))  # Replace with your coordinates'
      }

      script <- paste0(
        "# GVS Coordinate Validation Script\n",
        "# Generated by BIEN Data Loader on ", Sys.Date(), "\n",
        "# Run this script locally where outbound HTTPS is available.\n",
        "# Requires: httr, jsonlite\n\n",
        "library(httr)\nlibrary(jsonlite)\n\n",
        "# Each element is c(latitude, longitude) as character strings\n",
        "gvs_data <- ", data_r, "\n\n",
        'opts_json <- \'{"mode":"resolve"}\'\n',
        "data_json <- jsonlite::toJSON(gvs_data, auto_unbox=TRUE)\n",
        "body <- paste0('{\"opts\":', opts_json, ',\"data\":', data_json, '}')\n\n",
        'message("Submitting ', if (!is.null(coord_tbl)) nrow(coord_tbl) else 0, ' coordinate pair(s) to GVS...")\n',
        "resp <- httr::POST(\n",
        '  "https://gvsapi.xyz/gvs_api.php",\n',
        "  body = body,\n",
        '  httr::content_type("application/json"),\n',
        '  httr::add_headers(Accept="application/json"),\n',
        "  httr::timeout(120)\n",
        ")\n\n",
        "if (httr::status_code(resp) != 200) stop(\"GVS returned HTTP \", httr::status_code(resp))\n\n",
        'result <- jsonlite::fromJSON(httr::content(resp, "text", encoding="UTF-8"), flatten=TRUE)\n',
        "print(result)\n\n",
        'out_file <- paste0("gvs_results_", Sys.Date(), ".csv")\n',
        "write.csv(result, out_file, row.names=FALSE)\n",
        'message("Results saved to: ", out_file)\n'
      )
      writeLines(script, file)
    }
  )

  # ── NSR ──────────────────────────────────────────────────────────────────
  observeEvent(input$btn_nsr, {
    if (is.null(rv$staged)) {
      showNotification("No staging table found — complete Steps 1-3 (Upload, Map Fields, Apply Mapping) before running NSR.",
                       type="error", duration=10)
      return()
    }
    # NSR requires: taxon, country, state_province (county_parish optional), user_id
    spp_col <- "scrubbed_species_binomial"
    if (!spp_col %in% names(rv$staged) ||
        all(is.na(rv$staged[[spp_col]]) | trimws(rv$staged[[spp_col]]) == "")) {
      rv$nsr_result <- data.frame(
        note=paste0("No species names in 'scrubbed_species_binomial'. Run TNRS first or check field mapping."),
        stringsAsFactors=FALSE)
      return()
    }

    nsr_tbl <- unique(rv$staged[, intersect(c(spp_col,"scrubbed_family","country","state_province","county"),
                                            names(rv$staged)), drop=FALSE])
    nsr_tbl <- nsr_tbl[!is.na(nsr_tbl[[spp_col]]) & trimws(nsr_tbl[[spp_col]]) != "", , drop=FALSE]

    # NSR 5-col format: taxon, country, state_province, county_parish, user_id
    nsr_send <- data.frame(
      taxon          = trimws(nsr_tbl[[spp_col]]),
      country        = if ("country"        %in% names(nsr_tbl)) trimws(nsr_tbl$country)        else "",
      state_province = if ("state_province" %in% names(nsr_tbl)) trimws(nsr_tbl$state_province) else "",
      county_parish  = if ("county"         %in% names(nsr_tbl)) trimws(nsr_tbl$county)         else "",
      user_id        = seq_len(nrow(nsr_tbl)),
      stringsAsFactors=FALSE
    )

    if (nrow(nsr_send) > 20) {
      nsr_send <- nsr_send[seq_len(20), ]
      showNotification(paste0("NSR capped to first 20 unique taxon/location combinations."),
                       type="warning", duration=8)
    }

    withProgress(message="Submitting to NSR\u2026", value=0.2, {
      err_msg <- NULL
      result <- tryCatch({
        nsr_body <- jsonlite::toJSON(
          list(opts=list(mode="resolve"), data=nsr_send),
          auto_unbox=TRUE
        )
        resp <- httr::POST(
          NSR_URL,
          body = nsr_body,
          httr::content_type("application/json"),
          httr::add_headers(Accept="application/json", charset="UTF-8"),
          httr::config(connecttimeout=10),
          httr::timeout(120)
        )
        setProgress(0.8)
        code <- httr::status_code(resp)
        if (code == 200) {
          txt <- httr::content(resp, "text", encoding="UTF-8")
          # NSR returns a transposed JSON object: first row is column names
          raw <- tryCatch(jsonlite::fromJSON(txt), error=function(e) {
            err_msg <<- paste0("NSR returned 200 but response could not be parsed: ", conditionMessage(e))
            NULL
          })
          if (!is.null(raw)) {
            df <- tryCatch({
              # NSR response is {"id": [col_names], "rownum1": [vals], ...}
              col_names <- raw$id
              row_ids   <- setdiff(names(raw), "id")
              rows      <- lapply(row_ids, function(k) setNames(as.list(raw[[k]]), col_names))
              d         <- as.data.frame(do.call(rbind, lapply(rows, as.data.frame,
                             stringsAsFactors=FALSE)), stringsAsFactors=FALSE)
              d
            }, error=function(e) {
              err_msg <<- paste0("NSR response parse error: ", conditionMessage(e))
              NULL
            })
            df
          } else NULL
        } else {
          body_txt <- tryCatch(httr::content(resp, "text", encoding="UTF-8"), error=function(e) "")
          err_msg <<- paste0("NSR HTTP ", code, ": ", substr(body_txt, 1, 200))
          NULL
        }
      }, error=function(e) {
        err_msg <<- paste0("NSR connection error: ", conditionMessage(e))
        NULL
      })

      setProgress(1.0)
      rv$nsr_result <- if (is.null(result)) {
        data.frame(note = if (!is.null(err_msg)) err_msg else
                         "NSR request failed (unknown error).",
                   stringsAsFactors=FALSE)
      } else result

      # ── Write NSR results back to staging (BIEN DB native status fields) ─
      if (!is.null(rv$staged) && is.data.frame(rv$nsr_result) &&
          !"note" %in% names(rv$nsr_result)) {
        nsr  <- rv$nsr_result
        stg  <- rv$staged
        sp_col <- intersect(c("species","taxon"), names(nsr))[1]
        if (!is.na(sp_col)) {
          # Join by species + country + state_province for location-specific native status
          nsr_state_col <- intersect(c("state_province","stateProvince"), names(nsr))[1]
          nsr_key <- paste(trimws(nsr[[sp_col]]),
                           trimws(if ("country" %in% names(nsr)) nsr$country else ""),
                           trimws(if (!is.na(nsr_state_col)) nsr[[nsr_state_col]] else ""),
                           sep="\u001f")
          stg_key <- paste(trimws(stg$scrubbed_species_binomial),
                           trimws(if ("country"        %in% names(stg)) stg$country        else ""),
                           trimws(if ("state_province"  %in% names(stg)) stg$state_province else ""),
                           sep="\u001f")
          write_if <- function(nsr_col, stg_col) {
            if (nsr_col %in% names(nsr) && stg_col %in% names(stg)) {
              val <- as.character(nsr[[nsr_col]][i])
              if (!is.na(val) && nzchar(val)) stg[[stg_col]][rows] <<- val
            }
          }
          n_written <- 0L
          for (i in seq_len(nrow(nsr))) {
            rows <- which(stg_key == nsr_key[i])
            if (length(rows) == 0) next
            n_written <- n_written + 1L
            # BIEN DB .native_check fields
            write_if("native_status",               "native_status")
            write_if("native_status_reason",        "native_status_reason")
            write_if("native_status_country",       "native_status_country")
            write_if("native_status_state_province","native_status_state_province")
            write_if("native_status_county_parish", "native_status_county_parish")
            # BIEN DB is_introduced
            write_if("isIntroduced",                "is_introduced")
            # BIEN DB is_cultivated_observation
            write_if("isCultivatedNSR",             "is_cultivated_observation")
          }
          rv$staged <- stg
          showNotification(
            paste0("NSR complete: native status + cultivated fields updated for ",
                   n_written, " taxon/location combination(s)."),
            type="message", duration=6)
        }
      }
    })
  })

  output$nsr_status_ui <- renderUI({
    if (is.null(rv$nsr_result)) return(NULL)
    if ("note" %in% names(rv$nsr_result)) {
      tags$p(style="color:#c0392b; font-size:0.85em; margin-top:4px;",
             rv$nsr_result$note[1])
    } else {
      tags$p(style="color:#27ae60; font-size:0.85em; margin-top:4px;",
             paste0("NSR complete: ", nrow(rv$nsr_result), " taxon/location combination(s) checked"))
    }
  })

  output$nsr_table <- DT::renderDataTable({
    req(rv$nsr_result)
    DT::datatable(rv$nsr_result, rownames=FALSE,
      options=list(pageLength=20, scrollX=TRUE))
  }, server=TRUE)

  # ── All-services-complete modal ────────────────────────────────────────────
  observe({
    # Fire only when all four results exist and none carries the error sentinel
    all_done <- !is.null(rv$tnrs_result) && !"note" %in% names(rv$tnrs_result) &&
                !is.null(rv$gnrs_result) && !"note" %in% names(rv$gnrs_result) &&
                !is.null(rv$gvs_result)  && !"note" %in% names(rv$gvs_result)  &&
                !is.null(rv$nsr_result)  && !"note" %in% names(rv$nsr_result)
    if (rv$completion_modal_shown || !all_done) return()
    rv$completion_modal_shown <- TRUE

    run_ts <- format(Sys.time(), "%Y-%m-%d %H:%M %Z")

    showModal(modalDialog(
      title = tags$span(
        style = "font-size:1.15rem; font-weight:700; color:#2f6fab;",
        "\u2713 BIEN Service Processing Complete"
      ),
      easyClose = TRUE,
      size = "m",
      footer = tagList(
        actionButton("modal_go_export", "Go to Export (Tab 4) \u2192",
          class = "btn btn-primary",
          style = "background:#2f6fab; border-color:#1a4980; color:#fff;"),
        modalButton("Close")
      ),

      # Service checklist
      tags$div(class = "bl-card bl-card-pass", style = "margin-bottom:12px;",
        tags$p(style = "font-weight:600; margin:0 0 8px 0; color:#1a5c35;",
          "All 4 BIEN services completed successfully:"),
        tags$table(style = "width:100%; font-size:0.88rem; border-collapse:collapse;",
          tags$tr(
            tags$td(style="padding:3px 8px 3px 0; font-weight:700; white-space:nowrap;", "\u2713 TNRS"),
            tags$td(style="padding:3px 0; color:#2c2c2c;",
              "Scientific names resolved/scrubbed against WCVP + WFO; ", tags$code("scrubbed_*"), " fields populated.")
          ),
          tags$tr(
            tags$td(style="padding:3px 8px 3px 0; font-weight:700; white-space:nowrap;", "\u2713 GNRS"),
            tags$td(style="padding:3px 0; color:#2c2c2c;",
              "Political geography (country/state/county) standardized.")
          ),
          tags$tr(
            tags$td(style="padding:3px 8px 3px 0; font-weight:700; white-space:nowrap;", "\u2713 GVS"),
            tags$td(style="padding:3px 0; color:#2c2c2c;",
              "Coordinate centroid flags assigned; precision issues identified.")
          ),
          tags$tr(
            tags$td(style="padding:3px 8px 3px 0; font-weight:700; white-space:nowrap;", "\u2713 NSR"),
            tags$td(style="padding:3px 0; color:#2c2c2c;",
              "Native/introduced/cultivated status assigned by taxon and region.")
          )
        )
      ),

      # Staging table ready
      tags$div(class = "bl-card bl-card-pass", style = "margin-bottom:12px;",
        tags$p(style = "margin:0; font-size:0.9rem; color:#1a5c35;",
          tags$strong("The BIEN Staging Table is ready for export."),
          " It contains the original columns alongside reconciled BIEN schema fields."),
        tags$p(style = "margin:8px 0 0 0; font-size:0.86rem; color:#1a5c35;",
          "After review, click 'Go to Export (Tab 4) \u2192' to continue.")
      ),

      # Science review reminder
      tags$div(class = "bl-card bl-card-warn",
        tags$p(style = "font-weight:600; margin:0 0 6px 0; color:#7a4800;",
          "\u26a0 Review results before treating outputs as analysis-ready:"),
        tags$ul(style = "margin:0; padding-left:18px; font-size:0.87rem; line-height:1.8; color:#3a2800;",
          tags$li(tags$strong("TNRS:"), " check for ambiguous or low-confidence name matches. ",
            "Genus-only or multi-match records have lower inferential value."),
          tags$li(tags$strong("GNRS:"), " review unmatched or low-confidence political units; ",
            "country/state/county consistency depends on input spelling quality."),
          tags$li(tags$strong("GVS:"), " inspect centroid-flagged records \u2014 ",
            tags$code("is_centroid = 1"), " indicates potential positional imprecision."),
          tags$li(tags$strong("NSR:"), " native/introduced/cultivated status is ",
            "interpretation-dependent and should be reviewed for your study scope and region.")
        ),
        tags$p(style = "margin:8px 0 0 0; font-size:0.8rem; color:#555;",
          "Services run: ", tags$code(run_ts), ". ",
          "Endpoints: TNRS (tnrsapi.xyz), GNRS (gnrsapi.xyz), GVS (gvsapi.xyz), NSR (nsrapi.xyz).")
      )
    ))
  }) |> bindEvent(rv$nsr_result, rv$tnrs_result, rv$gnrs_result, rv$gvs_result,
                  ignoreInit = TRUE, ignoreNULL = FALSE)

  observeEvent(input$modal_go_export, {
    removeModal()
    updateNavbarPage(session, "tabs", selected = "4 \u2022 Export")
  })

  output$dl_nsr_script <- downloadHandler(
    filename = function() paste0("nsr_validation_", Sys.Date(), ".R"),
    contentType = "text/plain",
    content = function(file) {
      nsr_tbl <- if (!is.null(rv$staged) && "scrubbed_species_binomial" %in% names(rv$staged)) {
        u <- unique(rv$staged[, intersect(c("scrubbed_species_binomial","country","state_province","county"),
                                         names(rv$staged)), drop=FALSE])
        u <- u[!is.na(u$scrubbed_species_binomial) & trimws(u$scrubbed_species_binomial) != "", , drop=FALSE]
        if (nrow(u) > 0) {
          data.frame(
            taxon          = trimws(u$scrubbed_species_binomial),
            country        = if ("country"        %in% names(u)) trimws(u$country)        else "",
            state_province = if ("state_province" %in% names(u)) trimws(u$state_province) else "",
            county_parish  = if ("county"         %in% names(u)) trimws(u$county)         else "",
            user_id        = seq_len(nrow(u)),
            stringsAsFactors=FALSE)
        } else NULL
      } else NULL

      data_r <- if (!is.null(nsr_tbl) && nrow(nsr_tbl) > 0) {
        rows <- apply(nsr_tbl, 1, function(r)
          paste0('  list(taxon=', shQuote(r["taxon"]), ', country=', shQuote(r["country"]),
                 ', state_province=', shQuote(r["state_province"]),
                 ', county_parish=', shQuote(r["county_parish"]),
                 ', user_id=', r["user_id"], 'L)'))
        paste0("dplyr::bind_rows(\n", paste(rows, collapse=",\n"), "\n)")
      } else {
        'data.frame(taxon="Pinus ponderosa", country="United States", state_province="California", county_parish="", user_id=1L, stringsAsFactors=FALSE)'
      }

      script <- paste0(
        "# NSR Native Species Resolver Validation Script\n",
        "# Generated by BIEN Data Loader on ", Sys.Date(), "\n",
        "# Run this script locally where outbound HTTPS is available.\n",
        "# Requires: httr, jsonlite, dplyr\n",
        "# NSR endpoint: https://nsrapi.xyz/nsr_wsb.php\n",
        "# Input columns required: taxon, country, state_province, county_parish, user_id\n\n",
        "library(httr)\nlibrary(jsonlite)\nlibrary(dplyr)\n\n",
        "nsr_tbl <- ", data_r, "\n\n",
        "body <- jsonlite::toJSON(\n",
        "  list(opts=list(mode=\"resolve\"), data=nsr_tbl),\n",
        "  auto_unbox=TRUE\n",
        ")\n\n",
        'message("Submitting ', if (!is.null(nsr_tbl)) nrow(nsr_tbl) else 0,
        ' taxon/location combination(s) to NSR...")\n',
        "resp <- httr::POST(\n",
        '  "https://nsrapi.xyz/nsr_wsb.php",\n',
        "  body = body,\n",
        '  httr::content_type("application/json"),\n',
        '  httr::add_headers(Accept="application/json"),\n',
        "  httr::timeout(120)\n",
        ")\n\n",
        "if (httr::status_code(resp) != 200) stop(\"NSR returned HTTP \", httr::status_code(resp))\n\n",
        "# NSR returns a transposed JSON; decode it:\n",
        'raw <- jsonlite::fromJSON(httr::content(resp, "text", encoding="UTF-8"))\n',
        "col_names <- raw$id\n",
        "row_ids   <- setdiff(names(raw), \"id\")\n",
        "rows      <- lapply(row_ids, function(k) setNames(as.list(raw[[k]]), col_names))\n",
        "result    <- as.data.frame(do.call(rbind, lapply(rows, as.data.frame, stringsAsFactors=FALSE)),\n",
        "             stringsAsFactors=FALSE)\n\n",
        "print(result[, intersect(c('species','country','state_province','native_status',\n",
        "  'native_status_reason','isIntroduced','isCultivatedNSR'), names(result))])\n\n",
        'out_file <- paste0("nsr_results_", Sys.Date(), ".csv")\n',
        "write.csv(result, out_file, row.names=FALSE)\n",
        'message("Results saved to: ", out_file)\n'
      )
      writeLines(script, file)
    }
  )

  # ── TNRS upload-back ──────────────────────────────────────────────────────
  observeEvent(input$upload_tnrs, {
    req(input$upload_tnrs)
    if (input$upload_tnrs$size > 20 * 1024^2) {
      showNotification("Upload rejected: TNRS results file exceeds 20 MB. Confirm you selected the correct results CSV.", type = "error", duration = 10)
      return()
    }
    if (is.null(rv$staged)) {
      showNotification("No staging table — complete Steps 1-3 before uploading TNRS results.",
                       type="error", duration=10)
      return()
    }
    tryCatch({
      df <- safe_read_csv_with_fallbacks(
        input$upload_tnrs$datapath,
        file_label = input$upload_tnrs$name
      )
      if (nrow(df) == 0) stop("Uploaded CSV has no rows.")
      rv$tnrs_result <- df

      if ("Name_submitted" %in% names(df) && !"note" %in% names(df)) {
        tnrs <- df
        stg  <- rv$staged
        stg_names_key <- trimws(stg$scrubbed_species_binomial)
        for (i in seq_len(nrow(tnrs))) {
          submitted <- tnrs$Name_submitted[i]
          rows <- which(stg_names_key == trimws(submitted))
          if (length(rows) == 0) next
          for (col in c("Accepted_name","Name_matched")) {
            if (col %in% names(tnrs) && !is.na(tnrs[[col]][i]) && nzchar(trimws(tnrs[[col]][i]))) {
              stg$scrubbed_species_binomial[rows] <- tnrs[[col]][i]; break
            }
          }
          for (col in c("Accepted_family","Family")) {
            if (col %in% names(tnrs) && !is.na(tnrs[[col]][i]) && nzchar(trimws(tnrs[[col]][i]))) {
              stg$scrubbed_family[rows] <- tnrs[[col]][i]; break
            }
          }
          for (col in c("Genus_matched","Genus")) {
            if (col %in% names(tnrs) && !is.na(tnrs[[col]][i]) && nzchar(trimws(tnrs[[col]][i]))) {
              stg$scrubbed_genus[rows] <- tnrs[[col]][i]; break
            }
          }
          for (col in c("Accepted_name_author","Author_matched")) {
            if (col %in% names(tnrs) && !is.na(tnrs[[col]][i]) && nzchar(trimws(tnrs[[col]][i]))) {
              stg$scrubbed_author[rows] <- tnrs[[col]][i]; break
            }
          }
          for (col in c("Taxonomic_status","Name_matched_status")) {
            if (col %in% names(tnrs) && !is.na(tnrs[[col]][i]) && nzchar(trimws(tnrs[[col]][i]))) {
              stg$scrubbed_taxonomic_status[rows] <- tnrs[[col]][i]; break
            }
          }
        }
        rv$staged <- stg
        showNotification(
          paste0("TNRS results loaded: scrubbed_* fields updated for ", nrow(tnrs), " name(s)."),
          type="message", duration=6)
      } else {
        showNotification("TNRS CSV loaded (no writeback — missing 'Name_submitted' column or contains error note).",
                         type="warning", duration=8)
      }
    }, error=function(e) {
      showNotification(paste0("TNRS upload failed: ", conditionMessage(e)),
                       type="error", duration=10)
    })
  })

  # ── GNRS upload-back ──────────────────────────────────────────────────────
  observeEvent(input$upload_gnrs, {
    req(input$upload_gnrs)
    if (input$upload_gnrs$size > 20 * 1024^2) {
      showNotification("Upload rejected: GNRS results file exceeds 20 MB. Confirm you selected the correct results CSV.", type = "error", duration = 10)
      return()
    }
    if (is.null(rv$staged)) {
      showNotification("No staging table — complete Steps 1-3 before uploading GNRS results.",
                       type="error", duration=10)
      return()
    }
    tryCatch({
      df <- safe_read_csv_with_fallbacks(
        input$upload_gnrs$datapath,
        file_label = input$upload_gnrs$name
      )
      if (nrow(df) == 0) stop("Uploaded CSV has no rows.")
      rv$gnrs_result <- df

      if (!"note" %in% names(df)) {
        gnrs <- df
        stg  <- rv$staged
        country_col  <- intersect(c("Country_matched","country_matched","Country","country"), names(gnrs))[1]
        state_col    <- intersect(c("StateProvince_matched","stateProvince_matched","State_province_matched","state_province_matched"), names(gnrs))[1]
        county_col   <- intersect(c("County_matched","county_matched","County","county"), names(gnrs))[1]
        sub_country  <- intersect(c("Country_submitted","country_submitted","Country","country"), names(gnrs))[1]
        sub_state    <- intersect(c("StateProvince_submitted","stateProvince_submitted","State_province","state_province"), names(gnrs))[1]

        if (!is.na(sub_country) && !is.na(country_col)) {
          stg_key  <- paste(trimws(tolower(stg$country)), trimws(tolower(stg$state_province)))
          gnrs_sub <- paste(trimws(tolower(gnrs[[sub_country]])),
                            trimws(tolower(if (!is.na(sub_state)) gnrs[[sub_state]] else "")))
          for (i in seq_len(nrow(gnrs))) {
            rows <- which(stg_key == gnrs_sub[i])
            if (length(rows) == 0) next
            if (!is.na(country_col) && !is.na(gnrs[[country_col]][i]) && nzchar(gnrs[[country_col]][i]))
              stg$country[rows] <- gnrs[[country_col]][i]
            if (!is.na(state_col) && !is.na(gnrs[[state_col]][i]) && nzchar(gnrs[[state_col]][i]))
              stg$state_province[rows] <- gnrs[[state_col]][i]
            if (!is.na(county_col) && !is.na(gnrs[[county_col]][i]) && nzchar(gnrs[[county_col]][i]))
              stg$county[rows] <- gnrs[[county_col]][i]
          }
          rv$staged <- stg
          showNotification(
            paste0("GNRS results loaded: geography updated for ", nrow(gnrs), " location(s)."),
            type="message", duration=6)
        } else {
          showNotification("GNRS CSV loaded (no writeback — column names not recognised).",
                           type="warning", duration=8)
        }
      } else {
        showNotification("GNRS CSV loaded (contains error note, no writeback).",
                         type="warning", duration=8)
      }
    }, error=function(e) {
      showNotification(paste0("GNRS upload failed: ", conditionMessage(e)),
                       type="error", duration=10)
    })
  })

  # ── GVS upload-back ───────────────────────────────────────────────────────
  observeEvent(input$upload_gvs, {
    req(input$upload_gvs)
    if (input$upload_gvs$size > 20 * 1024^2) {
      showNotification("Upload rejected: GVS results file exceeds 20 MB. Confirm you selected the correct results CSV.", type = "error", duration = 10)
      return()
    }
    if (is.null(rv$staged)) {
      showNotification("No staging table — complete Steps 1-3 before uploading GVS results.",
                       type="error", duration=10)
      return()
    }
    tryCatch({
      df <- safe_read_csv_with_fallbacks(
        input$upload_gvs$datapath,
        file_label = input$upload_gvs$name
      )
      if (nrow(df) == 0) stop("Uploaded CSV has no rows.")
      rv$gvs_result <- df

      if (!"note" %in% names(df)) {
        gvs <- df
        stg <- rv$staged
        lat_col <- intersect(c("latitude_verbatim","latitude"), names(gvs))[1]
        lon_col <- intersect(c("longitude_verbatim","longitude"), names(gvs))[1]
        if (!is.na(lat_col) && !is.na(lon_col) && "is_centroid" %in% names(stg)) {
          for (i in seq_len(nrow(gvs))) {
            rows <- which(
              trimws(as.character(stg$latitude))  == trimws(as.character(gvs[[lat_col]][i])) &
              trimws(as.character(stg$longitude)) == trimws(as.character(gvs[[lon_col]][i]))
            )
            if (length(rows) == 0) next
            centroid_val <- "0"
            for (cflag in c("is_country_centroid","is_state_centroid","is_county_centroid")) {
              if (cflag %in% names(gvs) && !is.na(gvs[[cflag]][i]) &&
                  as.character(gvs[[cflag]][i]) %in% c("1","TRUE","true")) {
                centroid_val <- "1"; break
              }
            }
            stg$is_centroid[rows] <- centroid_val
          }
          rv$staged <- stg
          showNotification(
            paste0("GVS results loaded: is_centroid updated for ", nrow(gvs), " coordinate pair(s)."),
            type="message", duration=6)
        } else {
          showNotification("GVS CSV loaded (no writeback — lat/lon columns not found or is_centroid not in staging).",
                           type="warning", duration=8)
        }
      } else {
        showNotification("GVS CSV loaded (contains error note, no writeback).",
                         type="warning", duration=8)
      }
    }, error=function(e) {
      showNotification(paste0("GVS upload failed: ", conditionMessage(e)),
                       type="error", duration=10)
    })
  })

  # ── NSR upload-back ───────────────────────────────────────────────────────
  observeEvent(input$upload_nsr, {
    req(input$upload_nsr)
    if (input$upload_nsr$size > 20 * 1024^2) {
      showNotification("Upload rejected: NSR results file exceeds 20 MB. Confirm you selected the correct results CSV.", type = "error", duration = 10)
      return()
    }
    if (is.null(rv$staged)) {
      showNotification("No staging table — complete Steps 1-3 before uploading NSR results.",
                       type="error", duration=10)
      return()
    }
    tryCatch({
      df <- safe_read_csv_with_fallbacks(
        input$upload_nsr$datapath,
        file_label = input$upload_nsr$name
      )
      if (nrow(df) == 0) stop("Uploaded CSV has no rows.")
      rv$nsr_result <- df

      if (!"note" %in% names(df)) {
        nsr <- df
        stg <- rv$staged
        sp_col <- intersect(c("species","taxon"), names(nsr))[1]
        if (!is.na(sp_col)) {
          nsr_state_col <- intersect(c("state_province","stateProvince"), names(nsr))[1]
          nsr_key <- paste(trimws(nsr[[sp_col]]),
                           trimws(if ("country" %in% names(nsr)) nsr$country else ""),
                           trimws(if (!is.na(nsr_state_col)) nsr[[nsr_state_col]] else ""),
                           sep="\u001f")
          stg_key <- paste(trimws(stg$scrubbed_species_binomial),
                           trimws(if ("country" %in% names(stg)) stg$country else ""),
                           trimws(if ("state_province" %in% names(stg)) stg$state_province else ""),
                           sep="\u001f")
          write_if <- function(nsr_col, stg_col) {
            if (nsr_col %in% names(nsr) && stg_col %in% names(stg)) {
              val <- as.character(nsr[[nsr_col]][i])
              if (!is.na(val) && nzchar(val)) stg[[stg_col]][rows] <<- val
            }
          }
          n_written <- 0L
          for (i in seq_len(nrow(nsr))) {
            rows <- which(stg_key == nsr_key[i])
            if (length(rows) == 0) next
            n_written <- n_written + 1L
            write_if("native_status",               "native_status")
            write_if("native_status_reason",        "native_status_reason")
            write_if("native_status_country",       "native_status_country")
            write_if("native_status_state_province","native_status_state_province")
            write_if("native_status_county_parish", "native_status_county_parish")
            write_if("isIntroduced",                "is_introduced")
            write_if("isCultivatedNSR",             "is_cultivated_observation")
          }
          rv$staged <- stg
          showNotification(
            paste0("NSR results loaded: native status + cultivated fields updated for ",
                   n_written, " taxon/location combination(s)."),
            type="message", duration=6)
        } else {
          showNotification("NSR CSV loaded (no writeback — 'species' or 'taxon' column not found).",
                           type="warning", duration=8)
        }
      } else {
        showNotification("NSR CSV loaded (contains error note, no writeback).",
                         type="warning", duration=8)
      }
    }, error=function(e) {
      showNotification(paste0("NSR upload failed: ", conditionMessage(e)),
                       type="error", duration=10)
    })
  })

  # ── Tab 4 gating ─────────────────────────────────────────────────────────
  output$tab4_gating <- renderUI({
    if (is.null(rv$staged)) {
      tags$div(class="bl-card bl-card-warn",
        tags$strong("Not ready yet: "),
        "Go to \u20182 \u2022 Map Fields\u2019 and click Apply Mapping to build the staging table first.")
    }
  })

  # ── Export summary ────────────────────────────────────────────────────────
  output$export_summary <- renderText({
    req(rv$staged)
    qc <- rv$qc
    n_block <- if (!is.null(qc)) sum(qc$severity=="BLOCK", na.rm=TRUE) else NA
    n_warn  <- if (!is.null(qc)) sum(qc$severity=="WARN",  na.rm=TRUE) else NA
    n_dwc   <- if (!is.null(rv$mapping))
      sum(!is.na(rv$mapping$dwc_term) & nzchar(trimws(rv$mapping$dwc_term))) else 0
    n_bien  <- if (!is.null(rv$mapping))
      sum(!is.na(rv$mapping$bien_field) & nzchar(trimws(rv$mapping$bien_field))) else 0

    paste(
      paste0("Records in staging table:  ", nrow(rv$staged)),
      paste0("BIEN fields populated:     ", n_bien, " / ", length(BIEN_STAGING_FIELDS)),
      paste0("DWC terms mapped:          ", n_dwc),
      paste0("QC BLOCK issues:           ", n_block),
      paste0("QC WARN issues:            ", n_warn),
      paste0("TNRS run:                  ", if (!is.null(rv$tnrs_result)) "yes" else "no"),
      paste0("GNRS run:                  ", if (!is.null(rv$gnrs_result)) "yes" else "no"),
      paste0("GVS run:                   ", if (!is.null(rv$gvs_result))  "yes" else "no"),
      paste0("NSR run:                   ", if (!is.null(rv$nsr_result))  "yes" else "no"),
      "",
      "NOTE: Field names match BIEN DB (view_full_occurrence_individual)",
      "applied in this session. Authoritative taxonomic reconciliation",
      "requires downstream expert and service review before BIEN DB append.",
      sep="\n"
    )
  })

  # ── Tab 4 download status (replaces conditional button renderUI) ──────────
  output$dl_status_ui <- renderUI({
    if (is.null(rv$staged)) {
      tags$p(style="color:#e6a817; font-size:0.82em; margin-top:8px;",
        "\u26a0 Complete Steps 1\u20133 first. Downloads will contain a placeholder until staging is ready.")
    } else {
      tags$p(style="color:#27ae60; font-size:0.82em; margin-top:8px;",
        paste0("\u2713 Ready \u2014 ", nrow(rv$staged), " records staged."))
    }
  })

  # ── Download handlers ─────────────────────────────────────────────────────
  # CSV formula-injection sanitizer (OWASP: prevent Excel formula injection)
  sanitize_csv_col <- function(x) {
    # Ensure every column becomes a simple, 1-value-per-row character vector.
    if (is.list(x)) {
      x <- vapply(x, function(v) {
        if (length(v) == 0 || all(is.na(v))) return(NA_character_)
        if (length(v) == 1) return(as.character(v))
        jsonlite::toJSON(v, auto_unbox = TRUE, null = "null")
      }, character(1))
    }
    s <- as.character(x)
    # Skip formula injection guard for numeric values (e.g. negative coordinates)
    is_numeric_like <- !is.na(suppressWarnings(as.numeric(s)))
    ifelse(!is.na(s) & !is_numeric_like & grepl("^[=+@-]", s), paste0("'", s), s)
  }
  safe_write_csv <- function(df, file) {
    if (!is.data.frame(df)) {
      df <- as.data.frame(df, stringsAsFactors = FALSE)
    }
    df[] <- lapply(df, sanitize_csv_col)
    con <- file(file, open = "w", encoding = "UTF-8")
    on.exit(close(con), add = TRUE)
    utils::write.csv(df, con, row.names = FALSE, na = "")
  }

  output$dl_staged <- downloadHandler(
    filename = function() paste0("bien_staging_", Sys.Date(), ".csv"),
    contentType = "text/csv; charset=UTF-8",
    content  = function(file) {
      tryCatch({
        if (is.null(rv$staged)) {
          utils::write.csv(data.frame(error="No staging table — complete Steps 1-3 first."), file, row.names=FALSE)
          return()
        }
        safe_write_csv(rv$staged, file)
      }, error = function(e) {
        utils::write.csv(data.frame(error=paste0("Download failed: ", conditionMessage(e))), file, row.names=FALSE)
      })
    }
  )

  output$dl_dwc <- downloadHandler(
    filename = function() paste0("dwc_table_", Sys.Date(), ".csv"),
    contentType = "text/csv; charset=UTF-8",
    content  = function(file) {
      tryCatch({
        if (is.null(rv$dwc) || ncol(rv$dwc) == 0) {
          utils::write.csv(data.frame(error="No DWC terms were mapped — check field mapping in Step 2."), file, row.names=FALSE)
          return()
        }
        safe_write_csv(rv$dwc, file)
      }, error = function(e) {
        utils::write.csv(data.frame(error=paste0("Download failed: ", conditionMessage(e))), file, row.names=FALSE)
      })
    }
  )

  output$dl_mapping <- downloadHandler(
    filename = function() paste0("field_mapping_", Sys.Date(), ".csv"),
    contentType = "text/csv; charset=UTF-8",
    content  = function(file) {
      tryCatch({
        if (is.null(rv$mapping)) {
          utils::write.csv(data.frame(error="No mapping applied yet — complete Step 2 first."), file, row.names=FALSE)
          return()
        }
        safe_write_csv(rv$mapping, file)
      }, error = function(e) {
        utils::write.csv(data.frame(error=paste0("Download failed: ", conditionMessage(e))), file, row.names=FALSE)
      })
    }
  )

  output$dl_qc <- downloadHandler(
    filename = function() paste0("qc_report_", Sys.Date(), ".csv"),
    contentType = "text/csv; charset=UTF-8",
    content  = function(file) {
      tryCatch({
        if (is.null(rv$qc)) {
          utils::write.csv(data.frame(error="No QC results — complete Steps 1-3 first."), file, row.names=FALSE)
          return()
        }
        safe_write_csv(rv$qc, file)
      }, error = function(e) {
        utils::write.csv(data.frame(error=paste0("Download failed: ", conditionMessage(e))), file, row.names=FALSE)
      })
    }
  )

  output$dl_tnrs_script <- downloadHandler(
    filename = function() paste0("tnrs_validation_", Sys.Date(), ".R"),
    contentType = "text/plain",
    content = function(file) {
      names_vec <- if (!is.null(rv$staged) && "scrubbed_species_binomial" %in% names(rv$staged)) {
        unique(trimws(as.character(rv$staged$scrubbed_species_binomial)))
      } else character(0)
      names_vec <- names_vec[!is.na(names_vec) & nzchar(names_vec)]
      names_r <- if (length(names_vec) > 0)
        paste0('c(\n  ', paste(shQuote(names_vec), collapse=',\n  '), '\n)')
      else 'c()  # No species names found; populate this vector manually'
      script <- paste0(
        '# TNRS Taxonomy Validation Script\n',
        '# Generated by BIEN Data Loader on ', Sys.Date(), '\n',
        '# Run this script locally where outbound HTTPS is available.\n',
        '# Requires: httr, jsonlite\n\n',
        'library(httr)\nlibrary(jsonlite)\n\n',
        'names_vec <- ', names_r, '\n\n',
        'if (length(names_vec) == 0) stop("names_vec is empty -- add species names above.")\n',
        'if (length(names_vec) > 100) {\n',
        '  message("Capping to first 100 names for this request.")\n',
        '  names_vec <- names_vec[seq_len(100)]\n',
        '}\n\n',
        'tnrs_data <- data.frame(\n',
        '  id             = seq_along(names_vec),\n',
        '  Name_submitted = names_vec,\n',
        '  stringsAsFactors = FALSE\n',
        ')\n\n',
        'body <- jsonlite::toJSON(\n',
        '  list(\n',
        '    opts = list(mode="resolve", matches="best", sources="wcvp,wfo", acc=1L),\n',
        '    data = tnrs_data\n',
        '  ),\n',
        '  auto_unbox = TRUE\n',
        ')\n\n',
        'message("Submitting ", nrow(tnrs_data), " name(s) to TNRS...")\n',
        'resp <- httr::POST(\n',
        '  "https://tnrsapi.xyz/tnrs_api.php",\n',
        '  body = body,\n',
        '  httr::content_type("application/json"),\n',
        '  httr::timeout(120)\n',
        ')\n\n',
        'if (httr::status_code(resp) != 200) stop("TNRS returned HTTP ", httr::status_code(resp))\n\n',
        'result <- jsonlite::fromJSON(httr::content(resp, "text", encoding="UTF-8"), flatten=TRUE)\n',
        'print(result)\n\n',
        'out_file <- paste0("tnrs_results_", Sys.Date(), ".csv")\n',
        'write.csv(result, out_file, row.names=FALSE)\n',
        'message("Results saved to: ", out_file)\n'
      )
      writeLines(script, file)
    }
  )

  output$dl_gnrs_script <- downloadHandler(
    filename = function() paste0("gnrs_validation_", Sys.Date(), ".R"),
    contentType = "text/plain",
    content = function(file) {
      geo_tbl <- if (!is.null(rv$staged)) {
        geo_cols <- intersect(c("country","state_province","county"), names(rv$staged))
        if (length(geo_cols) > 0) {
          g <- unique(rv$staged[, geo_cols, drop=FALSE])
          g <- g[rowSums(!is.na(g) & g != "") > 0, , drop=FALSE]
          names(g) <- gsub("state_province", "stateProvince", names(g))
          if (!"country"       %in% names(g)) g$country <- ""
          if (!"stateProvince" %in% names(g)) g$stateProvince <- ""
          if (!"county"        %in% names(g)) g$county <- ""
          data.frame(id=seq_len(nrow(g)), g, stringsAsFactors=FALSE)
        } else NULL
      } else NULL

      geo_r <- if (!is.null(geo_tbl) && nrow(geo_tbl) > 0) {
        rows <- apply(geo_tbl, 1, function(r)
          paste0('  list(id=', r["id"], ', country=', shQuote(r["country"]),
                 ', stateProvince=', shQuote(r["stateProvince"]),
                 ', county=', shQuote(r["county"]), ')'))
        paste0('dplyr::bind_rows(\n', paste(rows, collapse=',\n'), '\n)')
      } else {
        'data.frame(id=1L, country="United States", stateProvince="", county="", stringsAsFactors=FALSE)  # Replace with your data'
      }

      script <- paste0(
        '# GNRS Geography Validation Script\n',
        '# Generated by BIEN Data Loader on ', Sys.Date(), '\n',
        '# Run this script locally where outbound HTTPS is available.\n',
        '# Requires: httr, jsonlite, dplyr\n\n',
        'library(httr)\nlibrary(jsonlite)\nlibrary(dplyr)\n\n',
        'geo_tbl <- ', geo_r, '\n\n',
        'body <- jsonlite::toJSON(\n',
        '  list(\n',
        '    opts = list(mode="resolve", sources="geonames,gadm"),\n',
        '    data = geo_tbl\n',
        '  ),\n',
        '  auto_unbox = TRUE\n',
        ')\n\n',
        'message("Submitting ", nrow(geo_tbl), " geography record(s) to GNRS...")\n',
        'resp <- httr::POST(\n',
        '  "https://gnrsapi.xyz/gnrs_api.php",\n',
        '  body = body,\n',
        '  httr::content_type("application/json"),\n',
        '  httr::timeout(120)\n',
        ')\n\n',
        'if (httr::status_code(resp) != 200) stop("GNRS returned HTTP ", httr::status_code(resp))\n\n',
        'result <- jsonlite::fromJSON(httr::content(resp, "text", encoding="UTF-8"), flatten=TRUE)\n',
        'print(result)\n\n',
        'out_file <- paste0("gnrs_results_", Sys.Date(), ".csv")\n',
        'write.csv(result, out_file, row.names=FALSE)\n',
        'message("Results saved to: ", out_file)\n'
      )
      writeLines(script, file)
    }
  )

  output$dl_packet <- downloadHandler(
    filename = function() paste0("bien_data_packet_", Sys.Date(), ".zip"),
    contentType = "application/zip",
    content  = function(file) {
      if (is.null(rv$staged)) {
        utils::write.csv(data.frame(error="No staging table — complete Steps 1-3 first."), file, row.names=FALSE)
        return()
      }
      tryCatch({
        # Use tempfile() for guaranteed-unique path; clean up on exit
        tmp <- tempfile(pattern="bien_packet_")
        dir.create(tmp, recursive=TRUE, showWarnings=FALSE)
        on.exit(unlink(tmp, recursive=TRUE), add=TRUE)

        out_files <- character(0)
        write_part <- function(df, fname) {
          p <- file.path(tmp, fname)
          safe_write_csv(df, p)
          out_files <<- c(out_files, p)
        }
        if (!is.null(rv$staged))       write_part(rv$staged,       "bien_staging.csv")
        if (!is.null(rv$dwc))          write_part(rv$dwc,          "dwc_table.csv")
        if (!is.null(rv$mapping))      write_part(rv$mapping,      "field_mapping.csv")
        if (!is.null(rv$qc))           write_part(rv$qc,           "qc_report.csv")
        if (!is.null(rv$tnrs_result))  write_part(rv$tnrs_result,  "tnrs_results.csv")
        if (!is.null(rv$gnrs_result))  write_part(rv$gnrs_result,  "gnrs_results.csv")
        if (!is.null(rv$gvs_result))   write_part(rv$gvs_result,   "gvs_results.csv")
        if (!is.null(rv$nsr_result))   write_part(rv$nsr_result,   "nsr_results.csv")

        # zip with full paths + junk-path flag (-j) to avoid setwd() race condition
        utils::zip(zipfile=file, files=out_files, flags="-j")
      }, error = function(e) {
        utils::write.csv(data.frame(error=paste0("Packet build failed: ", conditionMessage(e))), file, row.names=FALSE)
      })
    }
  )
}

shinyApp(ui, server)
