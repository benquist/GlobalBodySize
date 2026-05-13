## Global_Plant_BodySize/scripts/09e_fix_allometry_methods.R
## Stage 9e: Correct mechanistically inappropriate allometric equations for
##   five growth forms identified by merow-ecology review (2026-05-13):
##
##   1. VINES (lianas): Chave 2005 / Chave 2014 tree equations applied in
##      Stages 9b/9d are mechanistically indefensible for liana architecture
##      (distributed stem mass, no trunk taper). All vine records are flagged
##      as "liana_PENDING" and their uncertainty widened.
##      Tier 1/2 vines: equation_family overridden; agb_log10_sd widened.
##      Tier 3/4 vines: measurements retained; flagged as inappropriate.
##      Action: await Gerwing & Farias 2000 Biotropica 32(4):697-703 and
##              Schnitzer et al. 2006 Biotropica for verified coefficients.
##              [Both UNVERIFIED — do not cite until paper access confirmed.]
##
##   2. EPIPHYTES: No cross-taxon AGB equation exists. The single Tier-1
##      epiphyte record (Muukkonen 2007 shrub equation) is dropped to
##      equation_family = "epiphyte_NA". All epiphyte AGB is flagged.
##
##   3. HERBS: AGB = 0.04 * H^1.5 is a heuristic proxy with no published
##      calibration source (Stage 9b comment). Flagged "herb_proxy_UNVALIDATED".
##
##   4. GRAMINOIDS: Height alone is a weak predictor of graminoid AGB (shoot
##      density, tiller count dominate variance). Flagged "graminoid_height_LOW".
##
##   5. SUBSHRUBS (boreal only): Muukkonen 2007 is marginal but retained.
##      Flagged "subshrub_muukkonen_MARGINAL" for tropical/arid species.
##
## New column added:
##   agb_method_flag — machine-readable status for downstream filtering:
##     "ok"                          — equation appropriate and calibration reasonable
##     "liana_PENDING"               — vine: tree equation used, awaiting liana allometry
##     "epiphyte_NA"                 — no defensible equation; AGB not updated
##     "herb_proxy_UNVALIDATED"      — herb height proxy; not literature-calibrated
##     "graminoid_height_LOW"        — graminoid height proxy; low predictor quality
##     "subshrub_muukkonen_MARGINAL" — marginal transferability outside boreal
##     "gf_imputed_ok"               — growth-form imputed (Tier 0); no measurement data
##
## Input:
##   output/plant_biomass_with_uncertainty.csv  (Stage 9d output, 340,136 rows)
##
## Output:
##   output/plant_biomass_with_uncertainty.csv  (overwritten in-place: same schema
##                                               + new column agb_method_flag)
##   output/allometry_method_audit.csv          — summary table of flags × GF × tier
##
## Run from project root:
##   Rscript scripts/09e_fix_allometry_methods.R

if (basename(getwd()) == "scripts") setwd("..")

suppressPackageStartupMessages(library(data.table))

message("=== Stage 9e: Fix allometry method flags ===")

## ---- Load Stage 9d output --------------------------------------------------
stopifnot(file.exists("output/plant_biomass_with_uncertainty.csv"))
dt <- fread("output/plant_biomass_with_uncertainty.csv",
            colClasses = list(character = c("agb_best_tier")))
message("[9e] Loaded: ", nrow(dt), " species, ", ncol(dt), " columns")

## ---- Initialise flag column: default = "ok" ---------------------------------
dt[, agb_method_flag := "ok"]

## Mark existing GF-imputed rows (Tier 0) — these have no measurement data
dt[agb_best_tier == "0_gf_imputed", agb_method_flag := "gf_imputed_ok"]

## ---- 1. VINES ---------------------------------------------------------------
## Vines are never appropriate targets for Chave (tree) or Muukkonen (shrub)
## equations. Flag ALL vine records as liana_PENDING regardless of tier.

LIANA_TIERS <- c("1", "2", "3", "4")  ## measurement tiers to flag

## Count before flagging
n_vine_meas <- dt[growth_form_canonical == "vine" &
                  agb_best_tier %in% LIANA_TIERS, .N]
message("[9e] Vines with tree/shrub equation (Tiers 1-4): ", n_vine_meas)

dt[growth_form_canonical == "vine", agb_method_flag := "liana_PENDING"]

## For Tier 1/2 vines: widen agb_log10_sd to reflect unknown equation error.
## Use 2× original SD (conservative widening; no validated liana LoA exists).
dt[growth_form_canonical == "vine" & agb_best_tier %in% c("1", "2") &
   !is.na(agb_log10_sd),
   agb_log10_sd := agb_log10_sd * 2]

## Override equation_family for Tier 1/2 to remove misleading label
dt[growth_form_canonical == "vine" & agb_best_tier == "2",
   equation_family := "chave2005_INAPPROPRIATE_liana_PENDING"]
dt[growth_form_canonical == "vine" & agb_best_tier == "1",
   equation_family := "muukkonen_INAPPROPRIATE_liana_PENDING"]

## For Tier 3/4 vines: keep equation label but append note
dt[growth_form_canonical == "vine" & agb_best_tier == "3",
   equation_family := "chave2014_imputed_rho_INAPPROPRIATE_liana_PENDING"]
dt[growth_form_canonical == "vine" & agb_best_tier == "4",
   equation_family := "chave2014_measured_rho_INAPPROPRIATE_liana_PENDING"]

## Append to biomass_note for all vine measurement tiers
dt[growth_form_canonical == "vine" & agb_best_tier %in% LIANA_TIERS,
   biomass_note := paste0(
     ifelse(!is.na(biomass_note) & biomass_note != "", paste0(biomass_note, "; "), ""),
     "LIANA_PENDING: Chave/Muukkonen tree/shrub equations are mechanistically ",
     "indefensible for liana architecture. AGB estimate retained as placeholder; ",
     "awaiting verified liana allometry (Gerwing & Farias 2000 [UNVERIFIED]; ",
     "Schnitzer et al. 2006 [UNVERIFIED])."
   )]

## Recompute CI bounds for vines with widened SD
dt[growth_form_canonical == "vine" & agb_best_tier %in% c("1", "2") &
   !is.na(agb_best_kg) & agb_best_kg > 0 & !is.na(agb_log10_sd),
   `:=`(agb_ci_lower_kg = 10^(log10(agb_best_kg) - 1.96 * agb_log10_sd),
        agb_ci_upper_kg = 10^(log10(agb_best_kg) + 1.96 * agb_log10_sd))]

dt[growth_form_canonical == "vine" & agb_best_tier %in% c("1", "2") &
   !is.na(total_biomass_kg) & total_biomass_kg > 0 & !is.na(agb_log10_sd),
   `:=`(total_biomass_log10_sd    = agb_log10_sd,
        total_biomass_ci_lower_kg = 10^(log10(total_biomass_kg) - 1.96 * agb_log10_sd),
        total_biomass_ci_upper_kg = 10^(log10(total_biomass_kg) + 1.96 * agb_log10_sd))]

## ---- 2. EPIPHYTES -----------------------------------------------------------
## Only 1 epiphyte has a Tier-1 Muukkonen estimate; all others are GF-imputed.
## Drop Tier-1 epiphyte to no equation — retain agb_best_kg from GF imputation
## (the GF median from calibration trees/herbs is a better placeholder than
## an arbitrary shrub equation applied to an epiphyte).

n_epi_meas <- dt[growth_form_canonical == "epiphyte" & agb_best_tier %in% LIANA_TIERS, .N]
message("[9e] Epiphytes with tree/shrub equation (Tiers 1-4): ", n_epi_meas)

if (n_epi_meas > 0) {
  ## Compute epiphyte GF median from existing GF-imputed value as fallback
  epi_gf_row <- dt[growth_form_canonical == "epiphyte" & agb_best_tier == "0_gf_imputed"][1]

  dt[growth_form_canonical == "epiphyte" & agb_best_tier %in% LIANA_TIERS,
     `:=`(agb_best_tier    = "0_gf_imputed",
          equation_family  = "epiphyte_NA_no_defensible_equation",
          data_tier_label  = "T0: epiphyte — no cross-taxon AGB equation exists",
          agb_best_kg      = epi_gf_row$agb_best_kg,
          agb_log10_sd     = epi_gf_row$agb_log10_sd,
          agb_ci_lower_kg  = epi_gf_row$agb_ci_lower_kg,
          agb_ci_upper_kg  = epi_gf_row$agb_ci_upper_kg,
          gf_imputed       = TRUE,
          biomass_note     = paste0(
            "EPIPHYTE_NA: No cross-taxon AGB equation exists for epiphytes. ",
            "Muukkonen 2007 shrub equation is mechanistically inappropriate. ",
            "AGB replaced with GF-median imputed value. See merow-ecology review 2026-05-13."
          ))]
}

dt[growth_form_canonical == "epiphyte", agb_method_flag := "epiphyte_NA"]

## ---- 3. HERBS ---------------------------------------------------------------
## The 0.04 * H^1.5 proxy has no published calibration source.
## Flag but do not alter AGB values — the proxy is retained as placeholder.
n_herb_proxy <- dt[equation_family == "herb_proxy_uncertain", .N]
message("[9e] Herb proxy records to flag: ", n_herb_proxy)

dt[equation_family == "herb_proxy_uncertain",
   `:=`(equation_family  = "herb_proxy_UNVALIDATED",
        agb_method_flag  = "herb_proxy_UNVALIDATED")]

dt[equation_family == "herb_proxy_UNVALIDATED" & is.na(biomass_note),
   biomass_note := paste0(
     "HERB_PROXY: AGB = 0.04 * H^1.5 is a heuristic proxy with no published calibration. ",
     "Do not report as literature-derived. Consider replacing with GF-median imputation ",
     "or querying TRY/BAAD for herb AGB * height pairs. See merow-ecology review 2026-05-13."
   )]

## ---- 4. GRAMINOIDS ----------------------------------------------------------
## Height is a weak predictor for graminoids; shoot density dominates variance.
n_gram <- dt[growth_form_canonical == "graminoid" & agb_best_tier %in% LIANA_TIERS, .N]
message("[9e] Graminoid height-only records to flag: ", n_gram)

dt[growth_form_canonical == "graminoid" & agb_best_tier %in% LIANA_TIERS,
   `:=`(equation_family = "graminoid_height_LOW",
        agb_method_flag = "graminoid_height_LOW")]

dt[equation_family == "graminoid_height_LOW" & is.na(biomass_note),
   biomass_note := paste0(
     "GRAMINOID_HEIGHT_LOW: Height alone is a weak predictor of graminoid AGB. ",
     "Shoot density, tiller count, and growing-season stage dominate variance. ",
     "Treat AGB estimate as high-uncertainty placeholder. See merow-ecology review 2026-05-13."
   )]

## ---- 5. SUBSHRUBS -----------------------------------------------------------
## Muukkonen 2007 is acceptable for boreal subshrubs but marginal elsewhere.
## Flag tropical/arid subshrubs — we do not have biome assignments per-species,
## so flag ALL subshrub Muukkonen records with MARGINAL and document the caveat.
n_subshrub <- dt[growth_form_canonical == "subshrub" &
                 equation_family %in% c("muukkonen2007_height", "muukkonen2007_dbh_proxy"), .N]
message("[9e] Subshrub Muukkonen records to flag: ", n_subshrub)

dt[growth_form_canonical == "subshrub" &
   equation_family %in% c("muukkonen2007_height", "muukkonen2007_dbh_proxy"),
   `:=`(agb_method_flag = "subshrub_muukkonen_MARGINAL")]

dt[agb_method_flag == "subshrub_muukkonen_MARGINAL" & is.na(biomass_note),
   biomass_note := paste0(
     "SUBSHRUB_MUUKKONEN_MARGINAL: Muukkonen 2007 calibrated on boreal/temperate shrubs. ",
     "Transferability to tropical, Mediterranean, or arid subshrubs is marginal. ",
     "No biome filter applied at this stage — user must assess by species range. ",
     "See merow-ecology review 2026-05-13."
   )]

## ---- Summary audit ----------------------------------------------------------
message("\n[9e] === agb_method_flag summary ===")
flag_summary <- dt[, .N, by = .(growth_form_canonical, agb_method_flag, agb_best_tier)]
setorder(flag_summary, growth_form_canonical, agb_method_flag, agb_best_tier)

flag_totals <- dt[, .N, by = agb_method_flag][order(-N)]
for (i in seq_len(nrow(flag_totals))) {
  message(sprintf("  %-40s %d species", flag_totals$agb_method_flag[i], flag_totals$N[i]))
}
message("  Total: ", nrow(dt))

## ---- Write audit CSV --------------------------------------------------------
dir.create("output", showWarnings = FALSE)
fwrite(flag_summary, "output/allometry_method_audit.csv")
message("[9e] Audit table written: output/allometry_method_audit.csv")

## ---- Write updated main CSV (overwrite in-place) ---------------------------
fwrite(dt, "output/plant_biomass_with_uncertainty.csv")
message("[9e] Output written: output/plant_biomass_with_uncertainty.csv")
message("  Rows: ", nrow(dt), "  Columns: ", ncol(dt))

message("=== Stage 9e complete ===")
