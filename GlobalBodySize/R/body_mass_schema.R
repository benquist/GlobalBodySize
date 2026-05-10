## GlobalBodySize/R/body_mass_schema.R
## Canonical field definitions for the GlobalBodySize compiled table
## Incorporates DwC compliance requirements, merow-ecology advisory, and
## biodiversity-informatics-checker recommendations.
##
## MANDATORY fields: must be non-NA for a row to pass QA gate
## CONDITIONAL fields: required when applicable (e.g., for fish, marine, museum records)

## ---- Canonical column order for compiled table --------------------------------

globalsize_schema_columns <- function() {
  c(
    # --- 1. Input provenance ---
    "source_id",                   # e.g., "pantheria", "avonet", "dryad_10.5061_dryad.abc"
    "source_display_name",         # human-readable database name
    "source_doi",                  # DOI of the source dataset or paper (NA if none)
    "source_access_date",          # ISO 8601 date we downloaded/accessed
    "bibliographic_citation",      # Full citation string for downstream attribution
    "dataset_id",                  # Internal unique ID for this source/dataset combination
    "original_row_id",             # Row number or ID within the source file
    "source_file_path",            # Filename or path within archive

    # --- 2. Input taxon fields ---
    "verbatim_taxon_name",         # Name exactly as received from the source (DwC: verbatimScientificName)
    "verbatim_authorship",         # Authorship string as received (NA if not provided)
    "input_taxonomic_group",       # Controlled vocab: mammal | bird | fish | reptile | amphibian | insect | plant | other
    "input_taxonomic_rank",        # species | genus | family | order | class (DwC: taxonRank)

    # --- 3. Reconciled taxon fields (post-taxonomy pipeline) ---
    "resolved_taxon_name",         # Accepted name after backbone reconciliation
    "resolved_authorship",         # Authorship of accepted name from backbone
    "resolved_taxon_rank",         # Rank of matched accepted name
    "resolved_taxonomic_group",    # Group after reconciliation (should match input; flag if not)
    "kingdom",                     # DwC: kingdom
    "phylum",                      # DwC: phylum
    "class",                       # DwC: class
    "order",                       # DwC: order
    "family",                      # DwC: family
    "genus",                       # DwC: genus
    "primary_backbone",            # e.g., "GBIF_Backbone_v2023", "MDD_v1.12", "BirdLife_2023"
    "gbif_usage_key",              # GBIF backbone usageKey (integer) — cross-group join key
    "group_specific_taxon_id",     # FishBase SpecCode, AmphibiaWeb ID, etc.
    "group_specific_backbone",     # Name of group-specific authority used
    "match_method",                # exact | canonical | synonym | fuzzy | manual | no_match
    "match_confidence",            # high | medium | low | unassessable
    "matched_status",              # accepted | synonym | unresolved | ambiguous | no_match
    "synonym_type",                # homotypic | heterotypic | misapplied | NA
    "cross_group_collision_flag",  # TRUE if gbif_usage_key appears in >1 input_taxonomic_group
    "genus_only_flag",             # TRUE if only genus available (common for insects)
    "reconciliation_note",         # Free text for exceptions
    "reconciliation_timestamp_utc", # ISO 8601 UTC timestamp
    "backbone_version",            # Version string or release date of backbone used

    # --- 4. Body mass fields ---
    "mass_g",                      # Body mass in GRAMS (canonical unit — always convert to grams)
    "mass_g_min",                  # Minimum mass if range provided (NA otherwise)
    "mass_g_max",                  # Maximum mass if range provided (NA otherwise)
    "mass_se",                     # Standard error of mass estimate (NA if not provided)
    "mass_n",                      # Sample size underlying the mass value (NA if not provided)

    # --- 5. Mass metadata (mandatory non-nullable for QA) ---
    "mass_type",                   # MANDATORY: wet | dry | fat_free | LW_modeled | ash_free | unspecified
    "measurement_method",          # direct_scale | LW_equation | literature_mean | museum_label | model_estimate | unknown
    "life_stage",                  # adult | subadult | juvenile | larval | neonate | unknown
    "sex",                         # male | female | pooled | unknown

    # --- 6. Spatial fields (when available) ---
    "decimal_latitude",            # DwC: decimalLatitude (WGS84)
    "decimal_longitude",           # DwC: decimalLongitude (WGS84)
    "coordinate_uncertainty_m",    # DwC: coordinateUncertaintyInMeters
    "country_code",                # ISO 3166-1 alpha-2

    # --- 7. Temporal fields ---
    "year_measured",               # Year measurement was made (integer)
    "date_measured",               # ISO 8601 date if more precision available

    # --- 8. DwC compliance fields ---
    "measurement_id",              # DwC MoF: measurementID — unique per measurement row
    "measurement_type",            # DwC MoF: measurementType = "body mass"
    "measurement_value",           # DwC MoF: measurementValue (string copy of mass_g)
    "measurement_unit",            # DwC MoF: measurementUnit = "g"
    "measurement_determined_date", # DwC MoF: measurementDeterminedDate
    "basis_of_record",             # DwC: basisOfRecord (PreservedSpecimen | LivingSpecimen | HumanObservation | MachineObservation | Literature)

    # --- 9. QA flags ---
    "mass_confidence",             # high | medium | low | unassessable
    "range_check_pass",            # TRUE | FALSE | NA (group-specific plausible range)
    "unit_check_pass",             # TRUE | FALSE | NA
    "outlier_flag",                # TRUE | FALSE | NA (statistical outlier detection result)
    "qa_status",                   # pass | fail | needs_review
    "qa_note"                      # Free text QA note
  )
}

## ---- Controlled vocabulary definitions --------------------------------------

globalsize_mass_type_vocab <- function() {
  c("wet", "dry", "fat_free", "LW_modeled", "ash_free", "unspecified")
}

globalsize_life_stage_vocab <- function() {
  c("adult", "subadult", "juvenile", "larval", "neonate", "unknown")
}

globalsize_sex_vocab <- function() {
  c("male", "female", "pooled", "unknown")
}

globalsize_taxonomic_group_vocab <- function() {
  c("mammal", "bird", "fish", "reptile", "amphibian", "insect",
    "other_invertebrate", "plant", "other")
}

globalsize_match_method_vocab <- function() {
  c("exact", "canonical", "synonym", "fuzzy", "manual", "no_match")
}

globalsize_basis_of_record_vocab <- function() {
  c("PreservedSpecimen", "LivingSpecimen", "HumanObservation",
    "MachineObservation", "Literature", "Unknown")
}

## ---- Plausible mass ranges by taxonomic group (g) ---------------------------
## Source: merow-ecology advisory + general macroecology literature
## NOTE: All ranges are UNVERIFIED — confirm against authoritative sources before use

globalsize_mass_range_limits <- function() {
  data.frame(
    group      = c("mammal", "bird",   "fish",  "reptile", "amphibian",
                   "insect", "plant",  "other"),
    min_g      = c(1.5,      1.5,      0.001,   0.05,      0.03,
                   0.00001,  0.001,    0.0001),
    max_g      = c(1.5e8,    160000,   4e6,     1e6,       60000,
                   100,      NA,       NA),
    notes      = c(
      "Etruscan shrew ~1.5g min; blue whale ~150,000 kg max",
      "Bee hummingbird ~1.6g; male ostrich ~156,000g (156 kg) — corrected from 15,000g",
      "Paedocypris ~0.001g; Mola alexandrini ~2,300 kg = 2.3e6g; max_g=4e6 allows 2x record",
      "Brookesia micra chameleon ~0.1g; saltwater crocodile ~1,000,000g — min lowered to 0.05g",
      "Paedophryne amauensis ~0.05g; Chinese giant salamander ~60,000g — corrected from 5000g",
      "Fairy wasp ~0.000025g; Goliath beetle ~100g",
      "Seeds to full plants — no upper limit defined; plant_size_proxy field disambiguates",
      "Varies widely by group — no global limit"
    ),
    stringsAsFactors = FALSE
  )
}
