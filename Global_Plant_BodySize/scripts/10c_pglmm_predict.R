## Global_Plant_BodySize/scripts/10c_pglmm_predict.R
## Stage 10c: Two-stage BLUP-based body size prediction for all ~333K species.
##
## ARCHITECTURE:
##   Stage 1 (10b): MCMCglmm fitted on ~11,821 measured species → extracts
##     posterior family/genus BLUPs and fixed-effect coefficients.
##
##   Stage 2 (this script): For each of the remaining ~321K species, predict
##     log10(AGB) using available taxonomic BLUPs + growth-form fixed effects.
##     Posterior uncertainty is propagated by drawing 20 MCMC samples.
##
## PREDICTION FORMULA:
##   log10_agb_imputed_i = beta_gf[i] + beta_hpg[i] + u_family[i] + u_genus[i] + epsilon_i
##
##   where epsilon_i ~ N(0, V_R) with V_R from Stage 1 posterior.
##
## IMPUTATION BASIS HIERARCHY (assigned per species):
##   "genus_blup"     — genus BLUP available from Stage 1 → best quality
##   "family_blup"    — family BLUP available, no genus BLUP → moderate
##   "gf_mean_only"   — growth form known, family not in Stage 1 → weak
##   "grand_mean_only" — no GF, no family in Stage 1 → uninformative (flag)
##
## UNCERTAINTY:
##   Minimum 20 posterior draws from MCMC chain used for uncertainty propagation.
##   Output: per-species log10_agb_imputed_sd (across draws + residual variance).
##   Grand-mean-only species will have SD spanning 5+ log10 units — uninformative.
##   Do NOT compute community statistics from grand-mean-only species without
##   explicit propagation of their full posterior uncertainty.
##
## Inputs:
##   output/plant_biomass_with_uncertainty.csv  — all species (Stage 9e output)
##   output/pglmm_stage1_model.rds              — fitted MCMCglmm model (Stage 10b)
##   output/pglmm_family_blups.csv              — family posterior BLUPs
##   output/pglmm_genus_blups.csv               — genus posterior BLUPs
##   output/pglmm_variance_components.csv       — variance component posteriors
##   output/pglmm_fixed_effects.csv             — fixed effect posterior summaries
##
## Outputs:
##   output/plant_biomass_phylo_imputed.csv     — all 333K species with:
##     species_name, growth_form_canonical, family, genus,
##     agb_best_tier, agb_best_kg (original measured or NA),
##     log10_agb_imputed_mean, log10_agb_imputed_sd,
##     agb_imputed_kg, agb_imputed_ci_lower_kg, agb_imputed_ci_upper_kg,
##     imputation_basis, n_posterior_draws,
##     agb_method_flag
##
## Run from project root:
##   Rscript scripts/10c_pglmm_predict.R

if (basename(getwd()) == "scripts") setwd("..")

suppressPackageStartupMessages(library(data.table))

set.seed(2026)

N_DRAWS <- 20L  ## number of posterior draws for uncertainty propagation

message("=== Stage 10c: BLUP-based prediction for all species (Stage 2) ===")

## ---- Check inputs ----------------------------------------------------------
required_files <- c(
  "output/plant_biomass_with_uncertainty.csv",
  "output/pglmm_stage1_model.rds",
  "output/pglmm_family_blups.csv",
  "output/pglmm_genus_blups.csv",
  "output/pglmm_variance_components.csv",
  "output/pglmm_fixed_effects.csv"
)
missing <- required_files[!file.exists(required_files)]
if (length(missing) > 0) stop("[10c] Missing input files:\n  ", paste(missing, collapse = "\n  "))

## ---- Load all inputs -------------------------------------------------------
dt_all    <- fread("output/plant_biomass_with_uncertainty.csv",
                   colClasses = list(character = "agb_best_tier"))
model_s1  <- readRDS("output/pglmm_stage1_model.rds")
fam_blups <- fread("output/pglmm_family_blups.csv")
gen_blups <- fread("output/pglmm_genus_blups.csv")
vc        <- fread("output/pglmm_variance_components.csv")
fe        <- fread("output/pglmm_fixed_effects.csv")

message("[10c] Loaded: ", nrow(dt_all), " species total")
message("[10c] Family BLUPs: ", nrow(fam_blups), " families")
message("[10c] Genus BLUPs : ", nrow(gen_blups), " genera")

## ---- Extract posterior draws from MCMCglmm Sol matrix ----------------------
sol_post <- model_s1$Sol   ## rows = MCMC draws, cols = parameters
vcv_post <- model_s1$VCV   ## variance component draws

## Select N_DRAWS evenly spaced draws from the posterior
n_total_draws <- nrow(sol_post)
draw_idx <- round(seq(1, n_total_draws, length.out = N_DRAWS))
message("[10c] Using ", N_DRAWS, " posterior draws (of ", n_total_draws, " stored)")

## ---- Identify growth_form and HPG fixed effect columns ----------------------
## Fixed effects follow R contrast coding (first level = reference, absorbed into intercept)
## We map growth_form → fixed effect coefficient for prediction

## Intercept (reference = grand mean at reference GF/tier/HPG)
intercept_col <- "(Intercept)"

## GF fixed effect column names: "growth_form_canonicalSHRUB", etc.
gf_cols <- grep("^growth_form_canonical", colnames(sol_post), value = TRUE)
hpg_cols <- grep("^higher_plant_group",   colnames(sol_post), value = TRUE)
tier_cols <- grep("^data_tier",           colnames(sol_post), value = TRUE)

message("[10c] GF fixed effect cols  : ", length(gf_cols))
message("[10c] HPG fixed effect cols : ", length(hpg_cols))
message("[10c] Tier fixed effect cols: ", length(tier_cols))

## ---- Build growth-form reference table from posterior ----------------------
## For each growth form, compute the mean fixed effect across draws
## Reference GF (intercept absorbs it) — taken as first alphabetical level

## Helper: extract GF level name from column name
strip_prefix <- function(x, prefix) sub(paste0("^", prefix), "", x)

## Map GF → average fixed effect across N_DRAWS
make_fe_map <- function(cols, prefix, draw_mat) {
  if (length(cols) == 0) return(data.table(level = character(), fe_mean = numeric()))
  data.table(
    level   = strip_prefix(cols, prefix),
    fe_mean = colMeans(draw_mat[draw_idx, cols, drop = FALSE])
  )
}

gf_fe_map  <- make_fe_map(gf_cols,  "growth_form_canonical", sol_post)
hpg_fe_map <- make_fe_map(hpg_cols, "higher_plant_group",    sol_post)

## Reference levels (not in model columns — their effect is in the intercept)
## Add them as 0 effect (they are the baseline)
gf_all  <- unique(dt_all$growth_form_canonical)
hpg_all <- unique(dt_all$higher_plant_group)

gf_ref  <- setdiff(gf_all,  gf_fe_map$level)
hpg_ref <- setdiff(hpg_all, hpg_fe_map$level)

gf_fe_map  <- rbind(gf_fe_map,  data.table(level = gf_ref[!is.na(gf_ref)],   fe_mean = 0))
hpg_fe_map <- rbind(hpg_fe_map, data.table(level = hpg_ref[!is.na(hpg_ref)], fe_mean = 0))

## Intercept posterior mean (averaged over N_DRAWS)
intercept_mean <- mean(sol_post[draw_idx, intercept_col])

## V_R posterior mean for residual sampling
v_r_mean <- vc[component == "units", post_mean]
message("[10c] Residual variance V_R (posterior mean): ", round(v_r_mean, 4))

## ---- Join BLUPs to full species table --------------------------------------
## Family BLUPs: join on family name (strip "family." prefix if needed)
setnames(fam_blups, "level", "family")
setnames(gen_blups, "level", "genus")

dt_pred <- merge(dt_all, fam_blups[, .(family, family_blup = blup_mean, family_blup_sd = blup_sd)],
                 by = "family", all.x = TRUE)
dt_pred <- merge(dt_pred, gen_blups[, .(genus,  genus_blup  = blup_mean, genus_blup_sd  = blup_sd)],
                 by = "genus",  all.x = TRUE)

## Join fixed effects for GF and HPG
dt_pred <- merge(dt_pred, gf_fe_map[,  .(level, gf_fe  = fe_mean)],
                 by.x = "growth_form_canonical", by.y = "level", all.x = TRUE)
dt_pred <- merge(dt_pred, hpg_fe_map[, .(level, hpg_fe = fe_mean)],
                 by.x = "higher_plant_group",    by.y = "level", all.x = TRUE)

## Default to 0 for missing levels (novel GFs not in training data)
dt_pred[is.na(gf_fe),  gf_fe  := 0]
dt_pred[is.na(hpg_fe), hpg_fe := 0]

## ---- Assign imputation_basis per species ------------------------------------
dt_pred[, imputation_basis := fcase(
  !is.na(genus_blup)  & !is.na(family_blup), "genus_blup",
  !is.na(family_blup) & is.na(genus_blup),   "family_blup",
  !is.na(growth_form_canonical),              "gf_mean_only",
  default = "grand_mean_only"
)]

basis_counts <- dt_pred[, .N, by = imputation_basis][order(-N)]
message("\n[10c] === Imputation basis distribution ===")
for (i in seq_len(nrow(basis_counts))) {
  message(sprintf("  %-20s %d species (%.1f%%)",
    basis_counts$imputation_basis[i], basis_counts$N[i],
    100 * basis_counts$N[i] / nrow(dt_pred)))
}

## ---- Compute predictions with posterior uncertainty ------------------------
message("\n[10c] Computing posterior predictive means across ", N_DRAWS, " draws...")

## For each draw d, compute:
##   y_hat_d[i] = intercept_d + gf_fe_d[i] + hpg_fe_d[i] + family_blup[i] + genus_blup[i]
## (Using posterior-mean BLUPs for family/genus — simplification; see note below)
## Then add residual noise: epsilon ~ N(0, V_R_d)
## NOTE: For full posterior propagation, genus/family BLUPs should also be
## drawn per-MCMC-iteration. Using posterior means here is a pragmatic
## approximation that underestimates uncertainty. Flag in outputs.

## Point prediction (posterior mean of all components)
dt_pred[, log10_agb_imputed_mean := {
  base <- intercept_mean + gf_fe + hpg_fe
  base + ifelse(!is.na(genus_blup), genus_blup,
         ifelse(!is.na(family_blup), family_blup, 0))
}]

## Uncertainty from draws
draw_preds <- matrix(NA_real_, nrow = nrow(dt_pred), ncol = N_DRAWS)
for (d in seq_len(N_DRAWS)) {
  idx <- draw_idx[d]
  ## Per-draw intercept
  int_d <- sol_post[idx, intercept_col]
  ## Per-draw GF fixed effects (match to species)
  ## Simplified: use posterior mean GF/HPG FE; vary only intercept + residual
  v_r_d   <- vcv_post[idx, "units"]
  epsilon  <- rnorm(nrow(dt_pred), 0, sqrt(v_r_d))
  draw_preds[, d] <- int_d + dt_pred$gf_fe + dt_pred$hpg_fe +
    ifelse(!is.na(dt_pred$genus_blup), dt_pred$genus_blup,
    ifelse(!is.na(dt_pred$family_blup), dt_pred$family_blup, 0)) +
    epsilon
}

dt_pred[, log10_agb_imputed_sd := apply(draw_preds, 1, sd)]
dt_pred[, n_posterior_draws     := N_DRAWS]

## For grand-mean-only species, widen uncertainty to full V_total
v_total_mean <- sum(vc[component != "lambda_pagel", post_mean])
dt_pred[imputation_basis == "grand_mean_only",
  log10_agb_imputed_sd := sqrt(v_total_mean)]

## ---- Back-transform to kg ---------------------------------------------------
dt_pred[, agb_imputed_kg          := 10^log10_agb_imputed_mean]
dt_pred[, agb_imputed_ci_lower_kg := 10^(log10_agb_imputed_mean - 1.96 * log10_agb_imputed_sd)]
dt_pred[, agb_imputed_ci_upper_kg := 10^(log10_agb_imputed_mean + 1.96 * log10_agb_imputed_sd)]

## ---- Flag grand-mean-only as uninformative ----------------------------------
n_grand <- dt_pred[imputation_basis == "grand_mean_only", .N]
if (n_grand > 0) {
  message("[10c] WARNING: ", n_grand, " species have grand_mean_only imputation.")
  message("      Prediction intervals are ~5+ log10 units wide — essentially uninformative.")
  message("      Do NOT use these in community-weighted mean calculations without")
  message("      explicit multiple-imputation propagation.")
  dt_pred[imputation_basis == "grand_mean_only",
    agb_method_flag := paste0(agb_method_flag, ";grand_mean_only_UNINFORMATIVE")]
}

## ---- Summary statistics by imputation basis ---------------------------------
message("\n[10c] === Prediction SD by imputation basis ===")
sd_by_basis <- dt_pred[, .(
  n          = .N,
  mean_sd    = mean(log10_agb_imputed_sd, na.rm = TRUE),
  median_sd  = median(log10_agb_imputed_sd, na.rm = TRUE)
), by = imputation_basis]
for (i in seq_len(nrow(sd_by_basis))) {
  r <- sd_by_basis[i]
  message(sprintf("  %-20s n=%-6d mean_SD=%.3f  median_SD=%.3f log10 kg",
    r$imputation_basis, r$n, r$mean_sd, r$median_sd))
}

## ---- Select output columns --------------------------------------------------
out_cols <- c(
  "species_name", "growth_form_canonical", "higher_plant_group",
  "family", "genus",
  "agb_best_tier", "agb_best_kg",
  "log10_agb_imputed_mean", "log10_agb_imputed_sd",
  "agb_imputed_kg", "agb_imputed_ci_lower_kg", "agb_imputed_ci_upper_kg",
  "imputation_basis", "n_posterior_draws",
  "agb_method_flag",
  "family_blup", "family_blup_sd",
  "genus_blup",  "genus_blup_sd"
)
out_cols <- intersect(out_cols, names(dt_pred))

dir.create("output", showWarnings = FALSE)
fwrite(dt_pred[, ..out_cols], "output/plant_biomass_phylo_imputed.csv")
message("[10c] Output written: output/plant_biomass_phylo_imputed.csv")
message("  Rows: ", nrow(dt_pred), "  Columns: ", length(out_cols))

message("=== Stage 10c complete ===")
