## Global_Plant_BodySize/scripts/09d_add_biomass_uncertainty.R
## Stage 9d: Add per-species AGB uncertainty (log10 SD) based on:
##   1. Bland-Altman LoA from Stage 9c (tier-level structural uncertainty)
##   2. Widened intervals for herb/graminoid height-only (proxy equation)
##   3. Growth-form-level imputation for species with habit but no size data
##
## UNCERTAINTY SOURCES (additive on log10 scale, propagated in quadrature):
##
##   Tier 4  (Chave 2014, species rho):  residual SD ≈ 0.104 log10 kg
##     Derived from Chave 2014 RSE on ln scale ≈ 0.24 → / ln(10) ≈ 0.104
##     [UNVERIFIED — Chave 2014 GCB 20:3177]
##   Tier 3  (Chave 2014, imputed rho):  SD = 0.20 log10 kg (wider for rho uncertainty)
##   Tier 2  (DBH-only):  SD from Bland-Altman LoA  (Stage 9c result)
##   Tier 1  (height-only trees/shrubs): SD from Bland-Altman LoA (Stage 9c result)
##   Tier 1h (height-only herbs/gram):   SD widened ×1.5 (herb proxy not calibrated)
##   Tier 0  (GF imputed):               SD = within-GF-SD from calibration species
##
## HERB PROXY FLAG:
##   The equation AGB = 0.04 * H^1.5 is a heuristic proxy with no published
##   calibration. Per merow-ecology recommendation, species assigned AGB via
##   this equation are flagged:
##     equation_family = "herb_proxy_uncertain"
##     agb_log10_sd widened to within-GF SD (same as growth-form imputed tier)
##
## GROWTH-FORM IMPUTATION (Tier 0):
##   Species with known growth form but no height or DBH receive:
##     imputed_log10_agb_mean = mean(log10(agb_best_kg)) within growth form
##                              computed from Tier 1-4 species
##     agb_log10_sd           = SD(log10(agb_best_kg)) within growth form
##     agb_best_tier          = "0_gf_imputed"
##     equation_family        = "gf_median_imputed"
##     NOTE: These are group-level assignments, NOT species measurements.
##
## Inputs:
##   output/plant_biomass_estimates.csv        — Tier 1-4 AGB per species (Stage 9b)
##   output/tier_bias_summary.csv              — Bland-Altman LoA (Stage 9c)
##   output/species_growth_form_expanded.csv   — expanded habit assignments (Stage 3b)
##
## Outputs:
##   output/plant_biomass_with_uncertainty.csv — one row per species:
##     All Stage 9b columns +
##     agb_log10_sd, agb_ci_lower_kg, agb_ci_upper_kg,
##     total_biomass_log10_sd, total_biomass_ci_lower_kg, total_biomass_ci_upper_kg,
##     equation_family, data_tier_label, gf_imputed
##
## Run from project root:
##   Rscript scripts/09d_add_biomass_uncertainty.R

if (basename(getwd()) == "scripts") setwd("..")

suppressPackageStartupMessages(library(data.table))

message("=== Stage 9d: Add biomass uncertainty + GF imputation ===")

## ---- Load data -------------------------------------------------------------
stopifnot(file.exists("output/plant_biomass_estimates.csv"),
          file.exists("output/tier_bias_summary.csv"),
          file.exists("output/species_growth_form_expanded.csv"))

biomass <- fread("output/plant_biomass_estimates.csv",
                 colClasses = list(character = "agb_best_tier"))
message("[9d] Biomass estimates loaded: ", nrow(biomass), " species")

bias_tbl <- fread("output/tier_bias_summary.csv")
gf_exp   <- fread("output/species_growth_form_expanded.csv",
                   select = c("species_name", "growth_form_canonical",
                              "habit_source", "family", "genus"))

## ---- Extract LoA-derived SD for each tier (log10 scale) --------------------
## SD = (LoA_upper - LoA_lower) / (2 * 1.96)
get_loa_sd <- function(comparison_str, gf = "all") {
  row <- bias_tbl[comparison == comparison_str & growth_form == gf]
  if (nrow(row) == 0) return(NA_real_)
  (row$loa_upper - row$loa_lower) / (2 * 1.96)
}

sd_t1_trees  <- get_loa_sd("T1_vs_Ref", "tree")
sd_t1_shrubs <- get_loa_sd("T1_vs_Ref", "shrub")
sd_t1_all    <- get_loa_sd("T1_vs_Ref", "all")
sd_t2_all    <- get_loa_sd("T2_vs_Ref", "all")

## Tier 4 / 3 uncertainty from equation residual (Chave 2014 RSE / ln10)
## UNVERIFIED — from Chave 2014 GCB 20:3177
sd_t4 <- 0.104   # log10 kg
sd_t3 <- 0.200   # wider for imputed rho

message(sprintf("[9d] LoA-derived SDs: T1_tree=%.3f, T1_shrub=%.3f, T1_all=%.3f, T2_all=%.3f",
  sd_t1_trees, sd_t1_shrubs, sd_t1_all, sd_t2_all))
message(sprintf("[9d] Equation-residual SDs: T4=%.3f, T3=%.3f (log10 kg)", sd_t4, sd_t3))

## ---- Assign per-species SD and equation_family -----------------------------
biomass[, agb_log10_sd    := NA_real_]
biomass[, equation_family := NA_character_]
biomass[, data_tier_label := NA_character_]

## Tier 4
biomass[agb_best_tier == "4",
  `:=`(agb_log10_sd    = sd_t4,
       equation_family = "chave2014_measured_rho",
       data_tier_label = "T4: DBH + height + species rho")]

## Tier 3
biomass[agb_best_tier == "3",
  `:=`(agb_log10_sd    = sd_t3,
       equation_family = "chave2014_imputed_rho",
       data_tier_label = "T3: DBH + height + imputed rho")]

## Tier 2 (all GF — use all-GF LoA; vine-specific LoA would need n check)
biomass[agb_best_tier == "2",
  `:=`(agb_log10_sd    = sd_t2_all,
       equation_family = "chave2005_dbh_only",
       data_tier_label = "T2: DBH only")]
## Override for shrubs (Muukkonen with DBH as proxy — inherits all-GF uncertainty)
biomass[agb_best_tier == "2" &
        growth_form_canonical %in% c("shrub", "subshrub"),
  equation_family := "muukkonen2007_dbh_proxy"]

## Tier 1 — trees (Brown 1997 height-only)
biomass[agb_best_tier == "1" &
        growth_form_canonical %in% c("tree", "bamboo"),
  `:=`(agb_log10_sd    = sd_t1_trees,
       equation_family = "brown1997_height_only",
       data_tier_label = "T1: height only (tree)")]

## Tier 1 — shrubs (Muukkonen height)
biomass[agb_best_tier == "1" &
        growth_form_canonical %in% c("shrub", "subshrub", "vine", "epiphyte"),
  `:=`(agb_log10_sd    = if (!is.na(sd_t1_shrubs)) sd_t1_shrubs else sd_t1_all,
       equation_family = "muukkonen2007_height",
       data_tier_label = "T1: height only (shrub)")]

## Tier 1 — herbs/graminoids (PROXY — flag as uncertain, widen SD)
## Within-GF SD for herb will be computed below from calibration species;
## for now set to 1.5 × all-GF LoA SD as conservative placeholder
herb_proxy_sd <- sd_t1_all * 1.5
biomass[agb_best_tier == "1" &
        growth_form_canonical %in% c("herb", "graminoid", "aquatic",
                                      "parasite", "unknown"),
  `:=`(agb_log10_sd    = herb_proxy_sd,
       equation_family = "herb_proxy_uncertain",
       data_tier_label = "T1: height only (herb proxy — high uncertainty)")]

## ---- Compute within-GF SD from calibration species (Tiers 1-4) ------------
## This is used for Tier 0 (growth-form imputed) AND to refine herb uncertainty

cal_species <- biomass[agb_best_tier %in% c("1", "2", "3", "4") &
                       !is.na(agb_best_kg) & agb_best_kg > 0]
cal_species[, log10_agb := log10(agb_best_kg)]

gf_stats <- cal_species[,
  .(gf_n            = .N,
    gf_log10_mean    = mean(log10_agb, na.rm = TRUE),
    gf_log10_sd      = sd(log10_agb,   na.rm = TRUE),
    gf_log10_q25     = quantile(log10_agb, 0.25, na.rm = TRUE),
    gf_log10_q75     = quantile(log10_agb, 0.75, na.rm = TRUE)),
  by = growth_form_canonical]

message("[9d] Within-GF calibration statistics (Tier 1-4 species):")
for (i in seq_len(nrow(gf_stats))) {
  r <- gf_stats[i]
  message(sprintf("  %-12s n=%-4d mean=%.2f SD=%.2f log10 kg",
    r$growth_form_canonical, r$gf_n, r$gf_log10_mean, r$gf_log10_sd))
}

## Update herb proxy SD to use within-GF SD where available (more defensible)
herb_gf_sd <- gf_stats[growth_form_canonical == "herb", gf_log10_sd]
gram_gf_sd <- gf_stats[growth_form_canonical == "graminoid", gf_log10_sd]

if (length(herb_gf_sd) > 0 && !is.na(herb_gf_sd)) {
  biomass[equation_family == "herb_proxy_uncertain",
          agb_log10_sd := herb_gf_sd]
  message(sprintf("[9d] Herb proxy SD updated to within-GF SD: %.3f log10 kg", herb_gf_sd))
}

## ---- Tier 0: growth-form imputation for species with GF but no size --------
## Use species_growth_form_expanded.csv to find species with known GF but no AGB

## Species from expanded GF table not yet in biomass table
new_gf_spp <- gf_exp[!species_name %in% biomass$species_name &
                      growth_form_canonical != "unknown"]
message("[9d] Species with GF but no size data (new from Stage 3b): ", nrow(new_gf_spp))

## Also species already in biomass table with no AGB (Tier 0 in existing table)
existing_tier0 <- biomass[is.na(agb_best_kg) & !is.na(growth_form_canonical) &
                           growth_form_canonical != "unknown"]
message("[9d] Existing Tier 0 species (no AGB, known GF): ", nrow(existing_tier0))

## Assign GF-level imputed values to all Tier 0 species
assign_gf_imputed <- function(dt, gf_stats_tbl) {
  ## Join GF statistics
  dt2 <- merge(dt, gf_stats_tbl, by = "growth_form_canonical", all.x = TRUE)
  dt2[, agb_best_kg      := 10^gf_log10_mean]
  dt2[, agb_best_tier    := "0_gf_imputed"]
  dt2[, agb_log10_sd     := gf_log10_sd]
  dt2[, equation_family  := "gf_median_imputed"]
  dt2[, data_tier_label  := paste0("T0: GF imputed (", growth_form_canonical, ")")]
  dt2[, gf_imputed       := TRUE]
  dt2[, bgb_estimated_kg := agb_best_kg * 0.26]  ## use tree default; GF-specific below
  dt2[, total_biomass_kg := agb_best_kg + bgb_estimated_kg]
  dt2
}

## Apply root:shoot ratios for GF-imputed species
ROOT_SHOOT_GF <- data.table(
  growth_form_canonical = c("tree", "bamboo", "shrub", "subshrub",
                             "vine", "epiphyte", "herb", "graminoid",
                             "aquatic", "parasite", "unknown"),
  root_shoot_ratio      = c(0.26,   0.26,     0.40,   0.40,
                             0.26,   0.26,     0.50,   0.55,
                             0.50,   0.26,     0.26)
)

## Update existing Tier 0 rows in biomass table
biomass[is.na(agb_best_kg) & !is.na(growth_form_canonical) &
        growth_form_canonical != "unknown", gf_imputed := TRUE]

biomass <- merge(biomass, gf_stats[, .(growth_form_canonical,
                                        gf_log10_mean, gf_log10_sd)],
                 by = "growth_form_canonical", all.x = TRUE)

biomass[gf_imputed == TRUE,
  `:=`(agb_best_kg     = 10^gf_log10_mean,
       agb_best_tier   = "0_gf_imputed",
       agb_log10_sd    = gf_log10_sd,
       equation_family = "gf_median_imputed",
       data_tier_label = paste0("T0: GF imputed (", growth_form_canonical, ")"))]

## Add root:shoot to imputed
biomass <- merge(biomass, ROOT_SHOOT_GF, by = "growth_form_canonical",
                 all.x = TRUE, suffixes = c("", "_gf"))
biomass[gf_imputed == TRUE & !is.na(agb_best_kg),
  `:=`(bgb_estimated_kg = agb_best_kg * root_shoot_ratio,
       total_biomass_kg = agb_best_kg * (1 + root_shoot_ratio))]

## ---- Build new rows for species from Stage 3b only (not in biomass table) -
if (nrow(new_gf_spp) > 0) {
  new_rows <- new_gf_spp[, .(
    species_name          = species_name,
    growth_form_canonical = growth_form_canonical,
    higher_plant_group    = NA_character_,
    family                = family,
    genus                 = genus,
    height_m_mean         = NA_real_,
    height_m_n            = NA_integer_,
    dbh_cm_mean           = NA_real_,
    dbh_cm_n              = NA_integer_,
    rho_mean              = NA_real_,
    rho_sd                = NA_real_,
    rho_match_level       = NA_character_,
    agb_tier1_kg          = NA_real_,
    agb_tier2_kg          = NA_real_,
    agb_tier3_kg          = NA_real_,
    agb_tier4_kg          = NA_real_,
    agb_best_kg           = NA_real_,
    agb_best_tier         = NA_character_,
    bgb_estimated_kg      = NA_real_,
    total_biomass_kg      = NA_real_,
    root_shoot_ratio      = NA_real_,
    biomass_note          = NA_character_,
    equation_biome_flag   = NA_character_,
    agb_log10_sd          = NA_real_,
    equation_family       = "gf_median_imputed",
    data_tier_label       = NA_character_,
    gf_imputed            = TRUE,
    gf_log10_mean         = NA_real_,
    gf_log10_sd           = NA_real_,
    root_shoot_ratio_gf   = NA_real_
  )]

  ## Join GF stats
  new_rows <- merge(new_rows, gf_stats[, .(growth_form_canonical, gf_log10_mean,
                                             gf_log10_sd, gf_n)],
                    by = "growth_form_canonical", all.x = TRUE, suffixes = c("", "_join"))
  new_rows[!is.na(gf_log10_mean_join),
    `:=`(gf_log10_mean = gf_log10_mean_join, gf_log10_sd = gf_log10_sd_join)]
  new_rows[, `:=`(gf_log10_mean_join = NULL, gf_log10_sd_join = NULL, gf_n = NULL)]

  ## Join root:shoot
  new_rows <- merge(new_rows, ROOT_SHOOT_GF, by = "growth_form_canonical", all.x = TRUE,
                    suffixes = c("", "_rs"))

  new_rows[!is.na(gf_log10_mean),
    `:=`(agb_best_kg      = 10^gf_log10_mean,
         agb_best_tier    = "0_gf_imputed",
         agb_log10_sd     = gf_log10_sd,
         data_tier_label  = paste0("T0: GF imputed (", growth_form_canonical, ")"))]
  new_rows[!is.na(agb_best_kg) & !is.na(root_shoot_ratio_rs),
    `:=`(bgb_estimated_kg = agb_best_kg * root_shoot_ratio_rs,
         total_biomass_kg = agb_best_kg * (1 + root_shoot_ratio_rs))]
  ## Drop join artifact
  new_rows[, root_shoot_ratio_rs := NULL]

  ## Align columns
  missing_cols <- setdiff(names(biomass), names(new_rows))
  for (col in missing_cols) new_rows[[col]] <- NA
  setcolorder(new_rows, names(biomass))
  biomass <- rbind(biomass, new_rows, fill = TRUE)
  message("[9d] New GF-imputed rows added: ", nrow(new_rows))
}

## ---- Set gf_imputed = FALSE for all measured tiers -------------------------
biomass[is.na(gf_imputed), gf_imputed := FALSE]

## ---- Compute CI bounds from log10 SD ---------------------------------------
## CI is asymmetric on natural scale: 10^(log10(AGB) ± 1.96 * SD)
biomass[!is.na(agb_best_kg) & !is.na(agb_log10_sd) & agb_best_kg > 0,
  `:=`(agb_ci_lower_kg = 10^(log10(agb_best_kg) - 1.96 * agb_log10_sd),
       agb_ci_upper_kg = 10^(log10(agb_best_kg) + 1.96 * agb_log10_sd))]

biomass[!is.na(total_biomass_kg) & !is.na(agb_log10_sd) & total_biomass_kg > 0,
  `:=`(total_biomass_log10_sd     = agb_log10_sd,  ## propagate same SD (R:S ratio adds minor uncertainty)
       total_biomass_ci_lower_kg  = 10^(log10(total_biomass_kg) - 1.96 * agb_log10_sd),
       total_biomass_ci_upper_kg  = 10^(log10(total_biomass_kg) + 1.96 * agb_log10_sd))]

## ---- Coverage summary -------------------------------------------------------
message("[9d] === Coverage summary ===")
tier_counts <- biomass[, .N, by = agb_best_tier][order(agb_best_tier)]
for (i in seq_len(nrow(tier_counts))) {
  message("  Tier ", tier_counts$agb_best_tier[i], ": ", tier_counts$N[i], " species")
}
n_with_agb <- biomass[!is.na(agb_best_kg), .N]
message("  Total with AGB estimate: ", n_with_agb, " / ", nrow(biomass))
message("  GF-imputed: ", biomass[gf_imputed == TRUE, .N])
message("  Herb proxy flagged: ", biomass[equation_family == "herb_proxy_uncertain", .N])

## ---- Write output ----------------------------------------------------------
## Drop intermediate join columns before writing
cols_to_drop <- c("gf_log10_mean", "gf_log10_sd", "root_shoot_ratio_gf")
for (col in cols_to_drop) {
  if (col %in% names(biomass)) biomass[[col]] <- NULL
}

fwrite(biomass, "output/plant_biomass_with_uncertainty.csv")
message("[9d] Output written: output/plant_biomass_with_uncertainty.csv")
message("  Rows: ", nrow(biomass), "  Columns: ", ncol(biomass))

message("=== Stage 9d complete ===")
