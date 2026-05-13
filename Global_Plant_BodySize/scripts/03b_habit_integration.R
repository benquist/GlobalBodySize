## Global_Plant_BodySize/scripts/03b_habit_integration.R
## Stage 3b: Expand species habit (growth form) coverage by pulling two
## additional BIEN habit traits and integrating them with the primary
## growth form data from Stage 5.
##
## BIEN habit traits used (all verified via BIEN_trait_list() with BIEN v1.2.8):
##   1. "whole plant growth form"           — already pulled in Stage 3/5 (primary)
##   2. "whole plant woodiness"             — NEW: woody / herbaceous / variable
##   3. "whole plant growth form diversity" — NEW: compound categories (Herb, Tree,
##                                            Shrub, Liana, Non-woody epiphyte, etc.)
##
## PRIORITY for habit assignment (per species):
##   primary GF (Stage 5, modal from verbatim records)
##   > GF diversity (modal from new records, mapped to canonical)
##   > woodiness (herbaceous → herb; woody → tree-or-shrub; requires family check)
##
## Inputs:
##   output/species_growth_form.csv              — Stage 5 output (primary)
##   output/bien_woodiness_raw.csv               — queried here if absent
##   output/bien_gf_diversity_raw.csv            — queried here if absent
##
## Outputs:
##   output/species_growth_form_expanded.csv     — one row per species, expanded coverage
##   output/habit_integration_report.csv         — coverage counts by source and growth form
##
## Run from project root:
##   Rscript scripts/03b_habit_integration.R
##   Rscript scripts/03b_habit_integration.R --overwrite  (re-query BIEN)

args      <- commandArgs(trailingOnly = TRUE)
overwrite <- "--overwrite" %in% args

if (basename(getwd()) == "scripts") setwd("..")

library(data.table)
source("providers/bien/load_bien_traits.R")
source("R/growth_form_vocab.R")

message("=== Stage 3b: habit integration ===")

## ---- Vocabulary maps for new BIEN habit traits ------------------------------

## Map "whole plant woodiness" values → canonical growth form
##   woody       → "unknown_woody"  (can't distinguish tree vs shrub without more data;
##                  family override applied below: Cactaceae → herb/succulent, Poaceae → graminoid)
##   herbaceous  → "herb"
##   variable    → "unknown"
##   NOTE: "unknown_woody" is a temporary label resolved to tree/shrub by family below,
##         or left as "unknown" if no family-level override applies.

map_woodiness_to_canonical <- function(val) {
  val <- tolower(trimws(as.character(val)))
  dplyr::case_when(
    val == "herbaceous" ~ "herb",
    val == "woody"      ~ "unknown_woody",   # resolved further below
    val == "variable"   ~ "unknown",
    TRUE                ~ "unknown"
  )
}

## Map "whole plant growth form diversity" values → canonical growth form
##   Compound categories (e.g. "Shrub_Tree") mapped to the broader / more
##   conservative category. Compound values with "_" separator are parsed.
##   NOTE: "Non-woody epiphyte" → "epiphyte"; "Liana" / "Liana_Vine" → "vine".

map_gf_diversity_to_canonical <- function(val) {
  ## Normalise: tolower, trim, then collapse underscore-joined compounds by
  ## mapping each component and returning the highest-priority resolved value.
  priority_order <- c("bamboo", "graminoid", "tree", "shrub", "subshrub",
                      "herb", "vine", "epiphyte", "aquatic", "parasite", "unknown")

  single_map <- c(
    "herb"               = "herb",
    "forb"               = "herb",
    "tree"               = "tree",
    "shrub"              = "shrub",
    "shrublet"           = "subshrub",
    "liana"              = "vine",
    "vine"               = "vine",
    "grass"              = "graminoid",
    "graminoid"          = "graminoid",
    "bamboo"             = "bamboo",
    "non-woody epiphyte" = "epiphyte",
    "epiphyte"           = "epiphyte",
    "aquatic"            = "aquatic",
    "parasite"           = "parasite",
    "hemiparasite"       = "parasite"
  )

  vapply(val, function(v) {
    v_clean <- tolower(trimws(as.character(v)))
    if (is.na(v_clean) || v_clean == "na" || nchar(v_clean) == 0) return("unknown")

    ## Split compound values on "_" or " "
    parts <- unique(trimws(unlist(strsplit(v_clean, "[_ ]+"))))

    ## Also try the full string in the map (e.g. "non-woody epiphyte")
    if (v_clean %in% names(single_map)) {
      return(unname(single_map[v_clean]))
    }

    ## Map each part and pick highest-priority resolved value
    mapped <- single_map[parts[parts %in% names(single_map)]]
    if (length(mapped) == 0) return("unknown")

    resolved <- unname(mapped)
    priority_idx <- match(resolved, priority_order)
    resolved[which.min(priority_idx)]
  }, FUN.VALUE = character(1), USE.NAMES = FALSE)
}

## ---- Woody species: family-level resolution to tree/shrub ------------------
## For species tagged "unknown_woody" from the woodiness trait, use family to
## infer tree vs. shrub as a rough guide. Families not listed → remain "unknown".
## This is a conservative heuristic, not a biological authority.

resolve_unknown_woody <- function(canonical_vec, family_vec) {
  ## Families predominantly arborescent (often tree) — CONSERVATIVE LIST
  tree_families <- c(
    "Fagaceae", "Betulaceae", "Pinaceae", "Cupressaceae", "Taxodiaceae",
    "Oleaceae", "Magnoliaceae", "Lauraceae", "Moraceae", "Ulmaceae",
    "Juglandaceae", "Platanaceae", "Sapindaceae", "Meliaceae", "Myrtaceae",
    "Dipterocarpaceae", "Malvaceae", "Tiliaceae", "Combretaceae", "Annonaceae"
  )
  ## Families predominantly shrubby
  shrub_families <- c(
    "Ericaceae", "Rhamnaceae", "Caprifoliaceae", "Pittosporaceae",
    "Myoporaceae", "Proteaceae", "Bruniaceae", "Penaeaceae"
  )

  ifelse(canonical_vec == "unknown_woody" & family_vec %in% tree_families, "tree",
  ifelse(canonical_vec == "unknown_woody" & family_vec %in% shrub_families, "shrub",
  ifelse(canonical_vec == "unknown_woody", "unknown",   # can't resolve
  canonical_vec)))
}

## ---- Step 1: Pull woodiness records ----------------------------------------
message("[3b] Pulling 'whole plant woodiness' from BIEN...")
run_bien_trait_intake(
  trait_name  = "whole plant woodiness",
  output_file = "output/bien_woodiness_raw.csv",
  overwrite   = overwrite
)

## ---- Step 2: Pull GF diversity records --------------------------------------
message("[3b] Pulling 'whole plant growth form diversity' from BIEN...")
run_bien_trait_intake(
  trait_name  = "whole plant growth form diversity",
  output_file = "output/bien_gf_diversity_raw.csv",
  overwrite   = overwrite
)

## ---- Step 3: Load all inputs ------------------------------------------------
gf_primary <- fread("output/species_growth_form.csv")
message("[3b] Primary GF loaded: ", nrow(gf_primary), " species")

wood_raw <- fread("output/bien_woodiness_raw.csv")
message("[3b] Woodiness records loaded: ", nrow(wood_raw))

gfd_raw <- fread("output/bien_gf_diversity_raw.csv")
message("[3b] GF diversity records loaded: ", nrow(gfd_raw))

## ---- Step 4: Collapse woodiness to one canonical value per species ----------
wood_raw[, canonical := map_woodiness_to_canonical(trait_value_verbatim)]
wood_raw[, canonical := resolve_unknown_woody(canonical, family)]

## Modal canonical per species (exclude "unknown")
wood_spp <- wood_raw[canonical != "unknown",
  .(woodiness_canonical = {
      tbl <- sort(table(canonical), decreasing = TRUE)
      names(tbl)[1]
    },
    woodiness_n_records = .N),
  by = .(species_name = verbatim_species_name)]

message("[3b] Woodiness: ", nrow(wood_spp), " species with resolvable habit")

## ---- Step 5: Collapse GF diversity to one canonical value per species -------
gfd_raw[, canonical := map_gf_diversity_to_canonical(trait_value_verbatim)]

## Apply graminoid family override (Poaceae, Cyperaceae, Juncaceae)
gfd_raw[, canonical := ifelse(
  family %in% c("Poaceae", "Cyperaceae", "Juncaceae"),
  "graminoid", canonical)]

gfd_spp <- gfd_raw[canonical != "unknown",
  .(gfd_canonical = {
      tbl <- sort(table(canonical), decreasing = TRUE)
      names(tbl)[1]
    },
    gfd_n_records = .N),
  by = .(species_name = verbatim_species_name)]

message("[3b] GF diversity: ", nrow(gfd_spp), " species with resolvable habit")

## ---- Step 6: Priority merge -------------------------------------------------
## Start with all species from primary (Stage 5)
primary_known <- gf_primary[growth_form_canonical != "unknown"]
primary_unknown <- gf_primary[growth_form_canonical == "unknown"]

## For species NOT in primary_known, try GF diversity then woodiness
new_species_gfd  <- gfd_spp[!species_name %in% gf_primary$species_name]
new_species_wood <- wood_spp[!species_name %in% gf_primary$species_name &
                              !species_name %in% gfd_spp$species_name]

message("[3b] Species new from GF diversity: ", nrow(new_species_gfd))
message("[3b] Species new from woodiness only: ", nrow(new_species_wood))

## Also upgrade "unknown" primary assignments if GF diversity or woodiness
## provides a real assignment
upgradeable <- primary_unknown$species_name

upgrade_gfd  <- gfd_spp[species_name %in% upgradeable]
upgrade_wood <- wood_spp[species_name %in% upgradeable &
                          !species_name %in% gfd_spp$species_name]

message("[3b] Unknown GF species upgraded via GF diversity: ", nrow(upgrade_gfd))
message("[3b] Unknown GF species upgraded via woodiness: ", nrow(upgrade_wood))

## ---- Step 7: Build expanded species table -----------------------------------
## Columns from primary: retain all. Add: habit_source, habit_source_n_records.

## Helper to create a compatible row from new/upgraded species
make_new_rows <- function(spp_names, canonical_vals, n_records, source_label,
                          lookup_family = NULL) {
  ## Try to pull family/genus/higher_plant_group from woodiness or GFD raw data
  meta <- unique(rbind(
    wood_raw[, .(verbatim_species_name, family, genus, higher_plant_group)],
    gfd_raw[, .(verbatim_species_name, family, genus, higher_plant_group)]
  ), by = "verbatim_species_name")
  setnames(meta, "verbatim_species_name", "species_name")

  dt <- data.table(
    species_name          = spp_names,
    growth_form_canonical = canonical_vals,
    growth_form_n_records = n_records,
    growth_form_conflict  = FALSE,
    is_graminoid          = canonical_vals == "graminoid",
    is_bamboo             = canonical_vals == "bamboo",
    is_bryophyte          = FALSE,
    habit_source          = source_label
  )

  ## Merge metadata
  dt <- merge(dt, meta, by = "species_name", all.x = TRUE)
  dt
}

## Start with primary_known rows, add habit_source column
out <- copy(gf_primary)
out[, habit_source := ifelse(growth_form_canonical != "unknown",
                              "primary_gf", "none")]

## Apply upgrades for existing "unknown" species — GFD first
if (nrow(upgrade_gfd) > 0) {
  out[species_name %in% upgrade_gfd$species_name,
      `:=`(growth_form_canonical = upgrade_gfd$gfd_canonical[
             match(species_name, upgrade_gfd$species_name)],
           growth_form_n_records = upgrade_gfd$gfd_n_records[
             match(species_name, upgrade_gfd$species_name)],
           habit_source          = "gf_diversity")]
}
if (nrow(upgrade_wood) > 0) {
  out[species_name %in% upgrade_wood$species_name,
      `:=`(growth_form_canonical = upgrade_wood$woodiness_canonical[
             match(species_name, upgrade_wood$species_name)],
           growth_form_n_records = upgrade_wood$woodiness_n_records[
             match(species_name, upgrade_wood$species_name)],
           habit_source          = "woodiness")]
}

## Add brand-new species from GF diversity
if (nrow(new_species_gfd) > 0) {
  new_gfd_rows <- make_new_rows(
    spp_names    = new_species_gfd$species_name,
    canonical_vals = new_species_gfd$gfd_canonical,
    n_records    = new_species_gfd$gfd_n_records,
    source_label = "gf_diversity"
  )
  ## Align columns to out (fill missing with NA)
  missing_cols <- setdiff(names(out), names(new_gfd_rows))
  for (col in missing_cols) new_gfd_rows[[col]] <- NA
  setcolorder(new_gfd_rows, names(out))
  out <- rbind(out, new_gfd_rows, fill = TRUE)
}

## Add brand-new species from woodiness only
if (nrow(new_species_wood) > 0) {
  new_wood_rows <- make_new_rows(
    spp_names    = new_species_wood$species_name,
    canonical_vals = new_species_wood$woodiness_canonical,
    n_records    = new_species_wood$woodiness_n_records,
    source_label = "woodiness"
  )
  missing_cols <- setdiff(names(out), names(new_wood_rows))
  for (col in missing_cols) new_wood_rows[[col]] <- NA
  setcolorder(new_wood_rows, names(out))
  out <- rbind(out, new_wood_rows, fill = TRUE)
}

## Ensure is_graminoid is updated for all rows
out[, is_graminoid := growth_form_canonical == "graminoid"]
out[, is_bamboo    := growth_form_canonical == "bamboo"]

## ---- Step 8: Coverage report ------------------------------------------------
n_total      <- nrow(out)
n_known      <- out[growth_form_canonical != "unknown", .N]
n_primary    <- out[habit_source == "primary_gf",  .N]
n_gfd        <- out[habit_source == "gf_diversity", .N]
n_woodiness  <- out[habit_source == "woodiness",   .N]
n_none       <- out[habit_source == "none",         .N]

message("[3b] === Coverage summary ===")
message("  Total species in expanded table : ", n_total)
message("  Known habit (non-unknown)        : ", n_known,   " (",
        round(100 * n_known / n_total, 1), "%)")
message("  From primary GF (Stage 5)        : ", n_primary)
message("  Added/upgraded via GF diversity  : ", n_gfd)
message("  Added/upgraded via woodiness     : ", n_woodiness)
message("  Still unknown                    : ", n_none)

## GF breakdown
gf_table <- out[growth_form_canonical != "unknown",
  .N, by = growth_form_canonical][order(-N)]
message("[3b] Growth form breakdown:")
for (i in seq_len(nrow(gf_table))) {
  message("  ", gf_table$growth_form_canonical[i], ": ", gf_table$N[i])
}

## Write coverage report
report <- data.table(
  source         = c("primary_gf", "gf_diversity", "woodiness", "none"),
  n_species      = c(n_primary, n_gfd, n_woodiness, n_none),
  note           = c(
    "Stage 5 whole plant growth form (primary, highest confidence)",
    "BIEN whole plant growth form diversity (mapped to canonical)",
    "BIEN whole plant woodiness (herbaceous/woody → coarse habit)",
    "No habit data available"
  )
)
fwrite(report, "output/habit_integration_report.csv")
message("[3b] Integration report written: output/habit_integration_report.csv")

## ---- Step 9: Write expanded species growth form table ----------------------
fwrite(out, "output/species_growth_form_expanded.csv")
message("[3b] Expanded GF table written: output/species_growth_form_expanded.csv")
message("  Rows: ", nrow(out))
message("  Columns: ", ncol(out))

message("=== Stage 3b complete ===")
