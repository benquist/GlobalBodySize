## GlobalBodySize/R/body_size_schema.R
## Extension of body_mass_schema.R for multi-dimensional body size measurements.
##
## SCOPE EXPANSION NOTE [2026-05-11]:
##   The GlobalBodySize project now tracks body size measurements of any type,
##   not just body mass. The three measurement classes are:
##     mass             — wet_mass, dry_mass, fat_free_mass, ash_free_mass, unspecified
##     linear_dimension — linear_length, linear_width, linear_height, linear_diameter,
##                        LW_modeled (derived)
##     volume           — volume
##
##   Storage architecture:
##     Mass table:        data/compiled/tier1_combined.csv
##     Linear size table: data/compiled/tier1_linear_size_combined.csv
##   These two tables are kept SEPARATE until a length-weight (L-W) conversion
##   workflow is implemented to produce mass equivalents for linear measurements.
##
##   Agent advisory:
##   - Always set `size_measurement_class` BEFORE `size_measurement_type`.
##   - Never silently pool wet_mass and LW_modeled values in the same analysis
##     without flagging the mixing explicitly.
##   - Marine species MUST use WoRMS AphiaID (`aphia_id`) as the primary
##     taxonomic identifier; GBIF usageKey is secondary for these taxa.

## ---- Size measurement class vocabulary --------------------------------------

globalsize_size_measurement_class_vocab <- function() {
  c("mass", "linear_dimension", "volume")
}

## ---- Size measurement type vocabulary ---------------------------------------
## Extends mass_type in body_mass_schema.R.
## Always set size_measurement_class first, then size_measurement_type.

globalsize_size_measurement_type_vocab <- function() {
  c(
    "wet_mass",
    "dry_mass",
    "fat_free_mass",
    "ash_free_mass",
    "linear_length",
    "linear_width",
    "linear_height",
    "linear_diameter",
    "volume",
    "LW_modeled",
    "unspecified"
  )
}

## ---- Canonical column schema for linear size compiled table -----------------
## Parallel to globalsize_schema_columns() in body_mass_schema.R.
## Written to: data/compiled/tier1_linear_size_combined.csv

globalsize_linear_size_schema_columns <- function() {
  c(
    # -- Provenance (same as mass schema) --
    "source_id",               # e.g., "mobs_mcclain2025"
    "source_display_name",     # human-readable database name
    "source_doi",              # DOI of the source dataset or paper (NA if none)
    "source_access_date",      # ISO 8601 date we downloaded/accessed
    "bibliographic_citation",  # Full citation string for downstream attribution
    "dataset_id",              # Internal unique ID for this source/dataset combination
    "original_row_id",         # Row number or ID within the source file
    "source_file_path",        # Filename or path within archive

    # -- Taxon (verbatim) --
    "verbatim_taxon_name",     # Name exactly as received from the source
    "verbatim_authorship",     # Authorship string as received (NA if not provided)
    "input_taxonomic_group",   # Controlled vocab: fish | crustacean | mollusc | echinoderm | etc.
    "input_taxonomic_rank",    # species | genus | family | order | class

    # -- Taxon (resolved - post pipeline) --
    "resolved_taxon_name",     # Accepted name after backbone reconciliation
    "resolved_authorship",     # Authorship of accepted name from backbone
    "resolved_taxon_rank",     # Rank of matched accepted name
    "kingdom",
    "phylum",
    "class",
    "order",
    "family",
    "genus",
    "primary_backbone",        # e.g., "WoRMS", "GBIF_Backbone_v2023"
    "gbif_usage_key",          # GBIF backbone usageKey (integer); NA for WoRMS-primary records
    "aphia_id",                # WoRMS AphiaID (integer); primary key for marine species
    "match_method",            # exact | canonical | synonym | fuzzy | manual | no_match
    "match_confidence",        # high | medium | low | unassessable
    "matched_status",          # accepted | synonym | unresolved | ambiguous | no_match
    "reconciliation_note",     # Free text for exceptions

    # -- Linear size fields --
    "size_measurement_class",  # always "linear_dimension" for this table
    "size_measurement_type",   # linear_length | linear_width | linear_height | linear_diameter
    "size_value_cm",           # measured value in centimetres (canonical unit)
    "size_value_cm_min",       # minimum if range given
    "size_value_cm_max",       # maximum if range given
    "size_dimension_notes",    # e.g. "Bell Height", "total length", "carapace width"

    # -- Mass equivalent (initially NA — populated by L-W conversion workflow later) --
    "mass_g_equiv",            # NA until length-weight conversion is available
    "lw_conversion_method",    # NA until conversion; then e.g. "FishBase_LW_eq"

    # -- Specimen/measurement metadata --
    "life_stage",              # adult | subadult | juvenile | larval | neonate | unknown
    "sex",                     # male | female | pooled | unknown
    "specimen_type",           # live | preserved | fossil | unknown
    "biological_unit",         # individual | colony | other
    "measurement_method",      # direct_measure | museum_label | literature | unknown
    "basis_of_record",         # Literature | PreservedSpecimen | HumanObservation | etc.

    # -- Reference --
    "size_reference_doi",      # DOI of the specific measurement reference
    "size_reference_text",     # Free text citation for the measurement

    # -- Spatial (when available) --
    "decimal_latitude",        # WGS84 decimal degrees
    "decimal_longitude",       # WGS84 decimal degrees
    "country_code",            # ISO 3166-1 alpha-2
    "ocean_region",            # for marine datasets; NA for terrestrial

    # -- Taxonomy authority for marine species --
    "worms_valid_name",        # Accepted name from WoRMS
    "worms_phylum",
    "worms_class",
    "worms_order",
    "worms_family",

    # -- QA --
    "size_confidence",         # high | medium | low | unassessable
    "qa_status",
    "qa_note",

    # -- Provenance trace --
    "date_added"
  )
}
