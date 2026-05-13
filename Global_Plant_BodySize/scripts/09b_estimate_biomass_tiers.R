## Global_Plant_BodySize/scripts/09b_estimate_biomass_tiers.R
## Stage 9b: Estimate above-ground biomass (AGB) and total biomass for each
## species using a tiered approach matched to data availability.
##
## TIER HIERARCHY (applied per species, best available wins):
##
##   Tier 4 (BEST):  DBH + height + species-level wood density
##                   Chave et al. 2014 Eq. 7: AGB = 0.0673 * (rho * D^2 * H)^0.976
##                   Applied when: dbh_cm_mean & height_m_mean & rho_match_level == "species"
##
##   Tier 3:         DBH + height + family/genus/global wood density
##                   Same Chave 2014 Eq. 7, but rho imputed
##                   Applied when: dbh_cm_mean & height_m_mean & rho_match_level in (genus, family, global_fallback)
##
##   Tier 2:         DBH only (no height), no wood density required
##                   Chave et al. 2005 Eq. 3 (moist tropical, no rho):
##                   AGB = exp(-1.499 + 2.148*ln(D) + 0.207*ln(D)^2 - 0.0281*ln(D)^3)
##                   For shrubs: Muukkonen 2007 shrub equation
##                   Applied when: dbh_cm_mean available but height_m_mean is NA
##
##   Tier 1 (WEAKEST): Height only, no DBH, no wood density
##                   Brown 1997 pantropical height-only for trees:
##                   AGB = exp(-2.289 + 2.649*ln(H) - 0.021*ln(H)^2)
##                   Growth-form-specific height-only equations for shrubs/herbs
##                   Applied when: height_m_mean available, dbh_cm_mean is NA
##
##   Tier 0 (GROWTH FORM):  No continuous size data; return NA biomass with note
##
## Below-ground biomass (BGB):
##   BGB = AGB * root_shoot_ratio (growth form specific)
##   Root:shoot ratios from Mokany et al. 2006 meta-analysis (UNVERIFIED):
##     tree: 0.26 | shrub: 0.40 | herb: 0.50 | graminoid: 0.55 | other: 0.26
##
## Total biomass:
##   total_biomass_kg = AGB_kg + BGB_kg
##
## All equations flagged UNVERIFIED — verify citations before publication.
##
## References (requires independent verification):
##   Chave et al. 2014. Improved allometric models to estimate tree AGB.
##     Global Change Biology 20(10):3177–3190. DOI: 10.1111/j.1365-2486.2014.03178.x
##     FLAGGED UNVERIFIED
##   Chave et al. 2005. Tree allometry and improved estimation of carbon stocks
##     and balance in tropical forests.
##     Oecologia 145:87–99. DOI: 10.1007/s00442-005-0100-x  FLAGGED UNVERIFIED
##   Brown S. 1997. Estimating biomass and biomass change of tropical forests.
##     FAO Forestry Paper 134.  FLAGGED UNVERIFIED
##   Mokany et al. 2006. Critical analysis of root:shoot ratios.
##     Global Change Biology 12:84–96.  FLAGGED UNVERIFIED
##   Muukkonen 2007. Generalized allometric models for aboveground biomass of shrubs.
##     Silva Fennica 41:651–669.  FLAGGED UNVERIFIED
##
## Input:
##   output/plant_bodysize_final.csv  — species size data (height, DBH)
##   output/species_wood_density.csv  — wood density per species (from Stage 9a)
##
## Output:
##   output/plant_biomass_estimates.csv — one row per species with:
##     species_name, agb_tier1_kg, agb_tier2_kg, agb_tier3_kg, agb_tier4_kg,
##     agb_best_kg, agb_best_tier, bgb_estimated_kg, total_biomass_kg,
##     biomass_note, equation_biome_flag
##
## Run from project root:
##   Rscript scripts/09b_estimate_biomass_tiers.R

if (basename(getwd()) == "scripts") setwd("..")

suppressPackageStartupMessages(library(data.table))

## ---- Constants: equation coefficients (FLAGGED UNVERIFIED) -----------------

## Chave 2014 Eq. 7 (with rho, DBH, H)
CHAVE2014_a <- 0.0673
CHAVE2014_b <- 0.976

## Chave 2005 Eq. 3 (moist forest, DBH only, no rho) — returns AGB in kg
chave2005_dbh_only <- function(D) {
  ## D in cm; returns kg
  exp(-1.499 + 2.148 * log(D) + 0.207 * log(D)^2 - 0.0281 * log(D)^3)
}

## Brown 1997 FAO height-only pantropical — returns AGB in kg
brown1997_height_only <- function(H) {
  ## H in m; returns kg
  exp(-2.289 + 2.649 * log(H) - 0.021 * log(H)^2)
}

## Muukkonen 2007 shrub height-only (generic shrub; UNVERIFIED coefficients)
## AGB (kg) = a * H^b  where H in m
MUUKKONEN_SHRUB_a <- 0.174
MUUKKONEN_SHRUB_b <- 1.940

## Herb/graminoid simple allometry (proxy; no standard universal equation)
## AGB (kg) ≈ 0.04 * H^1.5 where H in m  (order-of-magnitude proxy only)
HERB_a <- 0.04
HERB_b <- 1.50

## Root:shoot ratios (Mokany et al. 2006, UNVERIFIED)
ROOT_SHOOT <- data.table(
  growth_form_canonical = c("tree", "bamboo", "shrub", "subshrub",
                             "vine", "epiphyte", "herb", "graminoid",
                             "aquatic", "parasite", "unknown"),
  root_shoot_ratio      = c(0.26,   0.26,     0.40,   0.40,
                             0.26,   0.26,     0.50,   0.55,
                             0.50,   0.26,     0.26)
)

## ---- Load data -------------------------------------------------------------
message("[Stage 9b] Loading plant_bodysize_final.csv...")
stopifnot(file.exists("output/plant_bodysize_final.csv"))
final <- fread("output/plant_bodysize_final.csv", data.table = TRUE)
message("[Stage 9b] Species: ", nrow(final))

message("[Stage 9b] Loading species_wood_density.csv...")
stopifnot(file.exists("output/species_wood_density.csv"))
wd <- fread("output/species_wood_density.csv",
            select = c("species_name", "rho_mean", "rho_sd",
                       "rho_match_level", "rho_source"),
            data.table = TRUE)

## Join wood density to final
dt <- merge(final, wd, by = "species_name", all.x = TRUE)

## Join root:shoot ratios
dt <- merge(dt, ROOT_SHOOT, by = "growth_form_canonical", all.x = TRUE)
dt[is.na(root_shoot_ratio), root_shoot_ratio := 0.26]  ## default fallback

## ---- Helper: Chave 2014 Eq. 7 (vectorized) ---------------------------------
chave2014 <- function(rho, D, H) {
  ## rho in g/cm³; D in cm; H in m; returns AGB in kg
  ok <- !is.na(rho) & !is.na(D) & !is.na(H) & D > 0 & H > 0 & rho > 0
  out <- rep(NA_real_, length(rho))
  out[ok] <- CHAVE2014_a * (rho[ok] * D[ok]^2 * H[ok])^CHAVE2014_b
  out
}

## ---- Tier 4: DBH + height + species-level rho ------------------------------
message("[Stage 9b] Computing Tier 4 (Chave 2014, species rho)...")
dt[, agb_tier4_kg := ifelse(
  rho_match_level == "species" & !is.na(dbh_cm_mean) & !is.na(height_m_mean),
  chave2014(rho_mean, dbh_cm_mean, height_m_mean),
  NA_real_
)]

## ---- Tier 3: DBH + height + imputed rho (genus/family/global) --------------
message("[Stage 9b] Computing Tier 3 (Chave 2014, imputed rho)...")
dt[, agb_tier3_kg := ifelse(
  rho_match_level %in% c("genus", "family", "global_fallback") &
    !is.na(dbh_cm_mean) & !is.na(height_m_mean),
  chave2014(rho_mean, dbh_cm_mean, height_m_mean),
  NA_real_
)]

## ---- Tier 2: DBH only (Chave 2005 Eq 3 for trees; Muukkonen for shrubs) ----
message("[Stage 9b] Computing Tier 2 (DBH only)...")
dt[, agb_tier2_kg := {
  agb <- rep(NA_real_, .N)
  ## Trees and bamboo: Chave 2005 Eq 3 (moist forest, no rho)
  tree_mask <- !is.na(dbh_cm_mean) & dbh_cm_mean > 0 &
    growth_form_canonical %in% c("tree", "bamboo", "vine", "epiphyte")
  agb[tree_mask] <- chave2005_dbh_only(dbh_cm_mean[tree_mask])
  ## Shrubs/subshrubs: Muukkonen; use DBH as proxy diameter if no H
  ## (Muukkonen uses basal stem diameter; DBH is not ideal for shrubs —
  ##  flagged in biomass_note)
  shrub_mask <- !is.na(dbh_cm_mean) & dbh_cm_mean > 0 &
    growth_form_canonical %in% c("shrub", "subshrub")
  agb[shrub_mask] <- MUUKKONEN_SHRUB_a * (dbh_cm_mean[shrub_mask])^MUUKKONEN_SHRUB_b
  agb
}]

## ---- Tier 1: height only ---------------------------------------------------
message("[Stage 9b] Computing Tier 1 (height only)...")
dt[, agb_tier1_kg := {
  agb <- rep(NA_real_, .N)
  ## Trees: Brown 1997 pantropical height-only
  tree_mask <- !is.na(height_m_mean) & height_m_mean > 0 &
    growth_form_canonical %in% c("tree", "bamboo")
  agb[tree_mask] <- brown1997_height_only(height_m_mean[tree_mask])
  ## Shrubs: Muukkonen height-only
  shrub_mask <- !is.na(height_m_mean) & height_m_mean > 0 &
    growth_form_canonical %in% c("shrub", "subshrub", "vine", "epiphyte")
  agb[shrub_mask] <- MUUKKONEN_SHRUB_a * (height_m_mean[shrub_mask])^MUUKKONEN_SHRUB_b
  ## Herbs/graminoids: proxy allometry
  herb_mask <- !is.na(height_m_mean) & height_m_mean > 0 &
    growth_form_canonical %in% c("herb", "graminoid", "aquatic", "parasite")
  agb[herb_mask] <- HERB_a * (height_m_mean[herb_mask])^HERB_b
  agb
}]

## ---- Select best available tier per species --------------------------------
message("[Stage 9b] Selecting best tier per species...")
dt[, agb_best_kg := NA_real_]
dt[, agb_best_tier := NA_character_]

dt[!is.na(agb_tier4_kg), `:=`(agb_best_kg = agb_tier4_kg, agb_best_tier = "4")]
dt[!is.na(agb_tier4_kg), agb_best_tier := "4"]

dt[is.na(agb_best_kg) & !is.na(agb_tier3_kg),
   `:=`(agb_best_kg = agb_tier3_kg, agb_best_tier = "3")]

dt[is.na(agb_best_kg) & !is.na(agb_tier2_kg),
   `:=`(agb_best_kg = agb_tier2_kg, agb_best_tier = "2")]

dt[is.na(agb_best_kg) & !is.na(agb_tier1_kg),
   `:=`(agb_best_kg = agb_tier1_kg, agb_best_tier = "1")]

## ---- BGB and total biomass -------------------------------------------------
dt[, bgb_estimated_kg    := agb_best_kg * root_shoot_ratio]
dt[, total_biomass_kg    := agb_best_kg + bgb_estimated_kg]

## ---- Biomass notes and bias flags ------------------------------------------
dt[, biomass_note        := NA_character_]
dt[, equation_biome_flag := NA_character_]

## Flag shrubs where DBH was used as proxy for basal diameter
dt[agb_best_tier %in% c("2") & growth_form_canonical %in% c("shrub", "subshrub"),
   biomass_note := "Shrub: DBH used as proxy for basal stem diameter in Muukkonen 2007 — likely overestimate"]

## Flag global fallback rho
dt[rho_match_level == "global_fallback" & agb_best_tier %in% c("3", "4"),
   biomass_note := paste0(ifelse(!is.na(biomass_note), paste0(biomass_note, "; "), ""),
                          "Wood density imputed from global angiosperm fallback — high uncertainty")]

## Flag equation biome mismatch (Chave equations calibrated for tropics)
dt[agb_best_tier %in% c("2", "3", "4"),
   equation_biome_flag := "chave_pantropical"]
dt[agb_best_tier == "1" & growth_form_canonical == "tree",
   equation_biome_flag := "brown1997_pantropical"]

## ---- Report ----------------------------------------------------------------
tier_summary <- dt[!is.na(agb_best_tier), .N, by = agb_best_tier]
setorder(tier_summary, agb_best_tier)
message("\n[Stage 9b] AGB estimate coverage by tier:")
for (i in seq_len(nrow(tier_summary))) {
  message("  Tier ", tier_summary$agb_best_tier[i], ": ", tier_summary$N[i], " species")
}
message("  Total with any AGB estimate: ", sum(!is.na(dt$agb_best_kg)))
message("  Total with total_biomass_kg: ", sum(!is.na(dt$total_biomass_kg)))

## Quick plausibility check: median AGB for trees should be ~100–10000 kg
tree_check <- dt[growth_form_canonical == "tree" & !is.na(agb_best_kg)]
if (nrow(tree_check) > 0) {
  message("\n[Stage 9b] Tree AGB plausibility check (Tier ",
          tree_check[, names(which.max(table(agb_best_tier)))], "):")
  message("  n=", nrow(tree_check),
          " | median=", round(median(tree_check$agb_best_kg, na.rm=TRUE), 1),
          " kg | min=", round(min(tree_check$agb_best_kg, na.rm=TRUE), 2),
          " kg | max=", round(max(tree_check$agb_best_kg, na.rm=TRUE), 1), " kg")
  message("  Expected range for typical trees: ~10–100,000 kg")
  if (median(tree_check$agb_best_kg, na.rm=TRUE) < 5 ||
      median(tree_check$agb_best_kg, na.rm=TRUE) > 1e6) {
    warning("[Stage 9b] PLAUSIBILITY FAIL: tree median AGB outside expected range. ",
            "Check units and equation coefficients.")
  } else {
    message("  PLAUSIBILITY PASS")
  }
}

## ---- Write output ----------------------------------------------------------
out_cols <- c(
  "species_name", "growth_form_canonical", "higher_plant_group",
  "family", "genus",
  "height_m_mean", "height_m_n",
  "dbh_cm_mean", "dbh_cm_n",
  "rho_mean", "rho_sd", "rho_match_level",
  "agb_tier1_kg", "agb_tier2_kg", "agb_tier3_kg", "agb_tier4_kg",
  "agb_best_kg", "agb_best_tier",
  "bgb_estimated_kg", "total_biomass_kg",
  "root_shoot_ratio",
  "biomass_note", "equation_biome_flag"
)
## Keep only columns that exist
out_cols <- intersect(out_cols, names(dt))

dir.create("output", showWarnings = FALSE)
fwrite(dt[, ..out_cols], "output/plant_biomass_estimates.csv")
message("[Stage 9b] Biomass estimates written: output/plant_biomass_estimates.csv")
message("  Rows: ", nrow(dt))
message("=== Stage 9b complete ===")
