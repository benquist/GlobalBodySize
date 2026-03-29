#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  required <- c("BIEN", "dplyr", "stringr", "readr", "httr2", "jsonlite", "tibble", "tidyr")
  missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing) > 0) {
    install.packages(missing, repos = "https://cloud.r-project.org")
  }

  library(BIEN)
  library(dplyr)
  library(stringr)
  library(readr)
  library(httr2)
  library(jsonlite)
  library(tibble)
  library(tidyr)
})

base_dir <- "cacti"
raw_dir <- file.path(base_dir, "data_raw")
proc_dir <- file.path(base_dir, "data_processed")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(proc_dir, recursive = TRUE, showWarnings = FALSE)

cat("[1/6] Pulling BIEN taxonomy for Cactaceae...\n")
bien_tax <- BIEN_taxonomy_family("Cactaceae")
readr::write_csv(bien_tax, file.path(raw_dir, "bien_cactaceae_taxonomy.csv"), na = "")

accepted_species <- bien_tax %>%
  filter(scrubbed_taxonomic_status == "Accepted", !is.na(scrubbed_species_binomial)) %>%
  distinct(scrubbed_species_binomial) %>%
  arrange(scrubbed_species_binomial)

cat("Accepted Cactaceae species in BIEN taxonomy:", nrow(accepted_species), "\n")
readr::write_csv(accepted_species, file.path(proc_dir, "bien_cactaceae_species_accepted.csv"), na = "")

cat("[2/6] Pulling BIEN traits for Cactaceae...\n")
bien_traits <- BIEN_trait_family("Cactaceae", all.taxonomy = TRUE, source.citation = TRUE)
names(bien_traits) <- make.unique(names(bien_traits))
readr::write_csv(bien_traits, file.path(raw_dir, "bien_cactaceae_traits_all.csv"), na = "")

cat("[3/6] Filtering BIEN traits to body size and flower color...\n")
bien_target <- bien_traits %>%
  mutate(
    trait_name_lc = str_to_lower(trait_name),
    trait_group = case_when(
      str_detect(trait_name_lc, "flower color") ~ "flower_color",
      str_detect(trait_name_lc, "height|diameter|dbh|mass|biomass") ~ "body_size",
      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(trait_group)) %>%
  transmute(
    source_dataset = "BIEN",
    source_url = dplyr::coalesce(url_source, "https://bien.nceas.ucsb.edu/bien/"),
    source_record_id = as.character(id),
    species = scrubbed_species_binomial,
    genus = scrubbed_genus,
    family = scrubbed_family,
    trait_group,
    trait_name,
    trait_value,
    unit,
    method,
    latitude,
    longitude,
    elevation_m,
    project_pi,
    access
  )

readr::write_csv(bien_target, file.path(proc_dir, "bien_cacti_target_traits.csv"), na = "")

cat("BIEN target trait records:", nrow(bien_target), "\n")

cat("[4/6] Pulling supplementary cacti traits from Wikidata SPARQL...\n")
# Q14560 = Cactaceae
sparql_query <- '
SELECT ?taxon ?taxonLabel ?speciesName ?height ?heightUnitLabel ?diameter ?diameterUnitLabel ?mass ?massUnitLabel ?flowerColorLabel WHERE {
  ?taxon wdt:P225 ?speciesName .
  ?taxon wdt:P171* wd:Q14560 .
  ?taxon wdt:P105 wd:Q7432 .
  OPTIONAL {
    ?taxon p:P2048 ?hStmt .
    ?hStmt psn:P2048 ?hNode .
    ?hNode wikibase:quantityAmount ?height .
    OPTIONAL { ?hNode wikibase:quantityUnit ?heightUnit . }
  }
  OPTIONAL {
    ?taxon p:P2386 ?dStmt .
    ?dStmt psn:P2386 ?dNode .
    ?dNode wikibase:quantityAmount ?diameter .
    OPTIONAL { ?dNode wikibase:quantityUnit ?diameterUnit . }
  }
  OPTIONAL {
    ?taxon p:P2067 ?mStmt .
    ?mStmt psn:P2067 ?mNode .
    ?mNode wikibase:quantityAmount ?mass .
    OPTIONAL { ?mNode wikibase:quantityUnit ?massUnit . }
  }
  OPTIONAL { ?taxon wdt:P2827 ?flowerColor . }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en".
    ?taxon rdfs:label ?taxonLabel .
    ?heightUnit rdfs:label ?heightUnitLabel .
    ?diameterUnit rdfs:label ?diameterUnitLabel .
    ?massUnit rdfs:label ?massUnitLabel .
    ?flowerColor rdfs:label ?flowerColorLabel .
  }
}
'

wikidata_resp <- request("https://query.wikidata.org/sparql") %>%
  req_url_query(query = sparql_query, format = "json") %>%
  req_user_agent("cacti-traits-pipeline/1.0 (local research use)") %>%
  req_perform()

wikidata_json <- jsonlite::fromJSON(resp_body_string(wikidata_resp), flatten = TRUE)

bindings <- wikidata_json$results$bindings
if (is.null(bindings) || length(bindings) == 0 || nrow(as.data.frame(bindings)) == 0) {
  wikidata_tbl <- tibble(
    species = character(),
    trait_group = character(),
    trait_name = character(),
    trait_value = character(),
    unit = character(),
    source_dataset = character(),
    source_url = character(),
    source_record_id = character(),
    retrieved_utc = character()
  )
} else {
  wd_flat <- as_tibble(bindings)

  pull_val <- function(df, col_prefix) {
    val_col <- paste0(col_prefix, ".value")
    if (val_col %in% names(df)) df[[val_col]] else rep(NA_character_, nrow(df))
  }

  wd_tidy <- tibble(
    species = dplyr::coalesce(pull_val(wd_flat, "speciesName"), pull_val(wd_flat, "taxonLabel")),
    taxon_qid = str_replace(pull_val(wd_flat, "taxon"), "^.*/", ""),
    height = pull_val(wd_flat, "height"),
    height_unit = pull_val(wd_flat, "heightUnitLabel"),
    diameter = pull_val(wd_flat, "diameter"),
    diameter_unit = pull_val(wd_flat, "diameterUnitLabel"),
    mass = pull_val(wd_flat, "mass"),
    mass_unit = pull_val(wd_flat, "massUnitLabel"),
    flower_color = pull_val(wd_flat, "flowerColorLabel")
  )

  wd_long <- bind_rows(
    wd_tidy %>%
      filter(!is.na(height) & height != "") %>%
      transmute(species, trait_group = "body_size", trait_name = "height", trait_value = height, unit = height_unit, taxon_qid),
    wd_tidy %>%
      filter(!is.na(diameter) & diameter != "") %>%
      transmute(species, trait_group = "body_size", trait_name = "diameter", trait_value = diameter, unit = diameter_unit, taxon_qid),
    wd_tidy %>%
      filter(!is.na(mass) & mass != "") %>%
      transmute(species, trait_group = "body_size", trait_name = "mass", trait_value = mass, unit = mass_unit, taxon_qid),
    wd_tidy %>%
      filter(!is.na(flower_color) & flower_color != "") %>%
      transmute(species, trait_group = "flower_color", trait_name = "flower color", trait_value = flower_color, unit = NA_character_, taxon_qid)
  ) %>%
    mutate(
      source_dataset = "Wikidata",
      source_url = str_c("https://www.wikidata.org/wiki/", taxon_qid),
      source_record_id = taxon_qid,
      retrieved_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
    ) %>%
    select(-taxon_qid)

  wikidata_tbl <- wd_long
}

readr::write_csv(wikidata_tbl, file.path(raw_dir, "wikidata_cacti_traits.csv"), na = "")
cat("Wikidata supplemental trait records:", nrow(wikidata_tbl), "\n")

cat("[5/6] Combining BIEN + supplementary sources...\n")
combined <- bind_rows(
  bien_target %>%
    mutate(retrieved_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)),
  wikidata_tbl %>%
    select(any_of(names(bien_target)), retrieved_utc)
) %>%
  mutate(species = str_squish(species)) %>%
  filter(!is.na(species), species != "")

readr::write_csv(combined, file.path(proc_dir, "cacti_traits_combined.csv"), na = "")

cat("[6/6] Writing non-BIEN provenance log...\n")
non_bien_provenance <- tibble(
  source_dataset = "Wikidata",
  source_description = "Structured species traits queried from Wikidata SPARQL endpoint for taxa in family Cactaceae (Q14560).",
  source_endpoint = "https://query.wikidata.org/sparql",
  source_web = "https://www.wikidata.org/",
  query_traits = "height (P2048), diameter (P2386), mass (P2067), flower color (P2827)",
  query_time_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
)
readr::write_csv(non_bien_provenance, file.path(proc_dir, "non_bien_sources_log.csv"), na = "")

summary_tbl <- tibble(
  metric = c(
    "BIEN accepted cacti species",
    "BIEN target-trait records",
    "Wikidata supplemental records",
    "Combined records"
  ),
  value = c(
    nrow(accepted_species),
    nrow(bien_target),
    nrow(wikidata_tbl),
    nrow(combined)
  )
)
readr::write_csv(summary_tbl, file.path(proc_dir, "run_summary.csv"), na = "")

cat("Done. Outputs written under:", normalizePath(base_dir), "\n")
