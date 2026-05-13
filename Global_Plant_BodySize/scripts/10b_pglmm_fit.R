## Global_Plant_BodySize/scripts/10b_pglmm_fit.R
## Stage 10b: Fit Bayesian Phylogenetic Generalised Linear Mixed Model (PGLMM)
##   on measured species (Tiers 1-4) using MCMCglmm.
##
## MODEL SPECIFICATION:
##   Response  : log10(agb_best_kg)   [above-ground biomass, log10 kg]
##   Fixed     : growth_form_canonical + agb_best_tier + higher_plant_group
##   Random    : animal (phylogenetic; via sparse Ainv)
##               + family (taxonomic family RE)
##               + genus  (taxonomic genus RE)
##
##   The 'animal' term is the standard MCMCglmm notation for the phylogenetic
##   random effect. The species_name column is mapped to 'animal' before fitting.
##
## WHY data_tier AS FIXED EFFECT (mandatory):
##   Stage 9c (Bland-Altman) found systematic biases:
##     Tier 1 vs Ref: mean bias = -0.877 log10 kg  (LoA [-3.94, +2.19])
##     Tier 2 vs Ref: mean bias = +0.380 log10 kg  (LoA [-0.40, +1.16])
##   Without data_tier in the model, these biases inflate growth-form effects
##   and the phylogenetic variance component (lambda). Mandatory inclusion.
##
## PRIORS (weakly informative; NOT flat):
##   B (fixed effects): Normal(0, 4) — covers ±4 orders of magnitude on log10 scale
##   G (each RE)      : inverse-Wishart(V=1, nu=1) — weakly informative
##   R (residual)     : inverse-Wishart(V=1, nu=1)
##   nu=0.002 flat prior is NOT used — can cause slow mixing near zero variance.
##
## PGLMM SCALE CONSTRAINT:
##   A full 333K-species PGLMM is computationally infeasible (~888 GB covariance
##   matrix, O(n^3) inversion). This script fits Stage 1 on ~11,821 measured species.
##   Stage 2 (10c) applies extracted BLUPs to all 333K species.
##
## PAGEL'S LAMBDA:
##   Estimated implicitly as: lambda = V_A / (V_A + V_family + V_genus + V_R)
##   Not assumed = 1 (Brownian motion) or = 0 (star phylogeny).
##
## MCMCglmm citation:
##   Hadfield JD (2010) MCMC methods for multi-response generalised linear mixed
##   models: the MCMCglmm R package. Journal of Statistical Software 33(2):1-22.
##   [UNVERIFIED exact vol/pg — verify before submitting]
##
## Blomberg K reference for residual signal check:
##   Blomberg SP, Garland T Jr & Ives AR (2003) Testing for phylogenetic signal
##   in comparative data. Evolution 57(4):717-745.
##   DOI: 10.1111/j.0014-3820.2003.tb00285.x  [VERIFIED]
##
## Inputs:
##   output/plant_biomass_with_uncertainty.csv  — full species data
##   output/tree_measured.nwk                   — pruned phylogeny (Stage 10a)
##
## Outputs:
##   output/pglmm_stage1_model.rds              — fitted MCMCglmm model object
##   output/pglmm_variance_components.csv       — V_A, V_family, V_genus, V_R, lambda
##   output/pglmm_fixed_effects.csv             — posterior means + 95% CI for fixed effects
##   output/pglmm_family_blups.csv              — posterior mean BLUP per family
##   output/pglmm_genus_blups.csv               — posterior mean BLUP per genus
##
## Run from project root (long-running: ~30-120 min depending on hardware):
##   Rscript scripts/10b_pglmm_fit.R

if (basename(getwd()) == "scripts") setwd("..")

suppressPackageStartupMessages({
  library(data.table)
  library(MCMCglmm)
  library(ape)
})

set.seed(2026)

message("=== Stage 10b: MCMCglmm PGLMM fit (Stage 1 — measured species) ===")

## ---- Load data -------------------------------------------------------------
stopifnot(file.exists("output/plant_biomass_with_uncertainty.csv"),
          file.exists("output/tree_measured.nwk"),
          file.exists("output/genus_family_lookup.csv"))

dt_all <- fread("output/plant_biomass_with_uncertainty.csv",
                colClasses = list(character = "agb_best_tier"))
tree_m  <- read.tree("output/tree_measured.nwk")

## ---- Fill family from backbone lookup (family column is all NA in pipeline) -
## 10a writes genus_family_lookup.csv from V.PhyloMaker2 tips.info.WP
gf_lookup <- fread("output/genus_family_lookup.csv")
setnames(gf_lookup, c("genus", "family_backbone"))
dt_all[, genus_clean := trimws(genus)]
dt_all <- merge(dt_all, gf_lookup, by.x = "genus_clean", by.y = "genus", all.x = TRUE)
dt_all[, family := ifelse(!is.na(family_backbone) & family_backbone != "",
                          family_backbone,
                   ifelse(!is.na(family) & family != "", family, NA_character_))]
dt_all[, family_backbone := NULL]
message("[10b] Family filled from backbone: ", dt_all[!is.na(family), .N], " / ", nrow(dt_all))

message("[10b] Full species data: ", nrow(dt_all))
message("[10b] Measured tree tips: ", length(tree_m$tip.label))

## ---- Subset to measured species (Tiers 1-4) --------------------------------
MEAS_TIERS <- c("1", "2", "3", "4")

meas <- dt_all[agb_best_tier %in% MEAS_TIERS &
               !is.na(agb_best_kg) & agb_best_kg > 0 &
               !is.na(growth_form_canonical) &
               !is.na(family) & !is.na(genus)]

meas[, log10_agb_kg := log10(agb_best_kg)]
meas[, data_tier    := paste0("T", agb_best_tier)]

## Recode higher_plant_group: collapse rare groups to "other" to avoid
## sparse-level problems in MCMC
hpg_n <- meas[, .N, by = higher_plant_group]
rare_hpg <- hpg_n[N < 20, higher_plant_group]
meas[higher_plant_group %in% rare_hpg | is.na(higher_plant_group),
     higher_plant_group := "other"]

message("[10b] Measured species for PGLMM: ", nrow(meas))

## ---- Match species names to tree tips --------------------------------------
## MCMCglmm requires animal column = tip labels in tree (underscores)
meas[, animal := gsub(" ", "_", species_name)]

## Keep only species in tree
in_tree <- meas$animal %in% tree_m$tip.label
message("[10b] Species matched to tree: ", sum(in_tree), " / ", nrow(meas))

if (sum(!in_tree) > 0) {
  message("[10b] Species not in tree (first 10): ",
    paste(head(meas$animal[!in_tree], 10), collapse = ", "))
}

meas_fit <- meas[in_tree]

## Prune tree to exactly the fitted species
tree_fit <- keep.tip(tree_m, meas_fit$animal)
message("[10b] Tree pruned to fitted species: ", length(tree_fit$tip.label), " tips")

## ---- Compute sparse inverse A matrix ---------------------------------------
message("[10b] Computing sparse inverse A matrix (Ainv) from tree...")
Ainv <- inverseA(tree_fit, nodes = "TIPS", scale = TRUE)$Ainv
message("[10b] Ainv computed: ", nrow(Ainv), " x ", ncol(Ainv), " sparse matrix")

## ---- Set priors ------------------------------------------------------------
## Count fixed effect levels
gf_levels  <- unique(meas_fit$growth_form_canonical)
tier_levels <- unique(meas_fit$data_tier)
hpg_levels  <- unique(meas_fit$higher_plant_group)
n_fixed <- 1 + (length(gf_levels) - 1) + (length(tier_levels) - 1) + (length(hpg_levels) - 1)
message("[10b] Estimated fixed effect parameters: ~", n_fixed)
message("  growth_form levels  : ", length(gf_levels))
message("  data_tier levels    : ", length(tier_levels))
message("  higher_plant_group  : ", length(hpg_levels))

prior_s1 <- list(
  ## Fixed effects: Normal(0, 4) — covers ±4 log10 kg orders of magnitude
  B = list(
    mu = rep(0, n_fixed),
    V  = diag(n_fixed) * 4   ## SD = 2 on log10 scale
  ),
  ## Variance components: weakly informative inverse-Wishart (nu=1, NOT nu=0.002)
  G = list(
    G1 = list(V = 1, nu = 1),  ## phylogenetic (animal)
    G2 = list(V = 1, nu = 1),  ## family
    G3 = list(V = 1, nu = 1)   ## genus
  ),
  R = list(V = 1, nu = 1)      ## residual
)

## ---- Fit MCMCglmm ----------------------------------------------------------
## MCMC settings: 600,000 iterations, 100,000 burnin, thin every 100
## → 5,000 posterior samples stored
## For a quick test run, set nitt=10000, burnin=2000, thin=10

NITT   <- 600000L
BURNIN <- 100000L
THIN   <- 100L

message("[10b] Fitting MCMCglmm (nitt=", NITT, ", burnin=", BURNIN, ", thin=", THIN, ")...")
message("[10b] Expected posterior samples: ", (NITT - BURNIN) / THIN)
message("[10b] NOTE: This may take 30-120 minutes on a laptop. Progress printed every 1000 iterations.")

t_start <- proc.time()

model_s1 <- MCMCglmm(
  log10_agb_kg ~ growth_form_canonical + data_tier + higher_plant_group,
  random   = ~ animal + family + genus,
  family   = "gaussian",
  ginverse = list(animal = Ainv),
  data     = as.data.frame(meas_fit),
  prior    = prior_s1,
  nitt     = NITT,
  burnin   = BURNIN,
  thin     = THIN,
  verbose  = TRUE
)

t_elapsed <- proc.time() - t_start
message(sprintf("[10b] Fitting complete: %.1f minutes", t_elapsed["elapsed"] / 60))

## ---- Save model object -----------------------------------------------------
dir.create("output", showWarnings = FALSE)
saveRDS(model_s1, "output/pglmm_stage1_model.rds")
message("[10b] Model saved: output/pglmm_stage1_model.rds")

## ---- Variance components and lambda ----------------------------------------
## Extract posterior means and 95% CIs for VCV (variance-covariance) chains

vcv_post <- model_s1$VCV  ## columns: animal, family, genus, units (residual)

vc_summary <- data.table(
  component    = colnames(vcv_post),
  post_mean    = apply(vcv_post, 2, mean),
  post_sd      = apply(vcv_post, 2, sd),
  post_ci_lo   = apply(vcv_post, 2, quantile, 0.025),
  post_ci_hi   = apply(vcv_post, 2, quantile, 0.975),
  eff_samp     = apply(vcv_post, 2, effectiveSize)
)

## Compute Pagel's lambda: V_phylo / (V_phylo + V_family + V_genus + V_R)
v_a    <- vc_summary[component == "animal.animal",     post_mean]
v_fam  <- vc_summary[component == "family.family",     post_mean]
v_gen  <- vc_summary[component == "genus.genus",       post_mean]
v_r    <- vc_summary[component == "units",             post_mean]
v_tot  <- v_a + v_fam + v_gen + v_r
lambda_post_mean <- v_a / v_tot

## Per-draw lambda
lambda_draws <- vcv_post[, "animal.animal"] /
  (vcv_post[, "animal.animal"] + vcv_post[, "family.family"] +
   vcv_post[, "genus.genus"]  + vcv_post[, "units"])

lambda_row <- data.table(
  component  = "lambda_pagel",
  post_mean  = mean(lambda_draws),
  post_sd    = sd(lambda_draws),
  post_ci_lo = quantile(lambda_draws, 0.025),
  post_ci_hi = quantile(lambda_draws, 0.975),
  eff_samp   = effectiveSize(lambda_draws)
)
vc_summary <- rbind(vc_summary, lambda_row)

message("\n[10b] === Variance components (posterior means) ===")
message(sprintf("  V_phylo  (animal)  : %.4f  [%.4f, %.4f]", v_a,   vc_summary[component=="animal.animal",   post_ci_lo], vc_summary[component=="animal.animal",   post_ci_hi]))
message(sprintf("  V_family           : %.4f  [%.4f, %.4f]", v_fam, vc_summary[component=="family.family",   post_ci_lo], vc_summary[component=="family.family",   post_ci_hi]))
message(sprintf("  V_genus            : %.4f  [%.4f, %.4f]", v_gen, vc_summary[component=="genus.genus",     post_ci_lo], vc_summary[component=="genus.genus",     post_ci_hi]))
message(sprintf("  V_residual         : %.4f  [%.4f, %.4f]", v_r,   vc_summary[component=="units",           post_ci_lo], vc_summary[component=="units",           post_ci_hi]))
message(sprintf("  Pagel lambda       : %.4f  [%.4f, %.4f]",
  lambda_post_mean, lambda_row$post_ci_lo, lambda_row$post_ci_hi))
message(sprintf("  Phylogenetic signal: %s",
  ifelse(lambda_post_mean > 0.5, "STRONG (lambda > 0.5)",
  ifelse(lambda_post_mean > 0.2, "MODERATE (0.2 < lambda <= 0.5)", "WEAK (lambda <= 0.2)"))))

fwrite(vc_summary, "output/pglmm_variance_components.csv")
message("[10b] Variance components written: output/pglmm_variance_components.csv")

## ---- Fixed effects summary -------------------------------------------------
sol_post <- model_s1$Sol
fe_summary <- data.table(
  parameter  = colnames(sol_post),
  post_mean  = apply(sol_post, 2, mean),
  post_sd    = apply(sol_post, 2, sd),
  post_ci_lo = apply(sol_post, 2, quantile, 0.025),
  post_ci_hi = apply(sol_post, 2, quantile, 0.975),
  eff_samp   = apply(sol_post, 2, effectiveSize),
  pMCMC      = apply(sol_post, 2, function(x) 2 * min(mean(x > 0), mean(x < 0)))
)

fwrite(fe_summary, "output/pglmm_fixed_effects.csv")
message("[10b] Fixed effects written: output/pglmm_fixed_effects.csv")

## ---- Extract family and genus BLUPs ----------------------------------------
## BLUPs are in Sol columns matching "^family\\." and "^genus\\."
## These are the key outputs needed for Stage 2 prediction (10c).

family_cols <- grep("^family\\.", colnames(sol_post), value = TRUE)
genus_cols  <- grep("^genus\\.",  colnames(sol_post), value = TRUE)

if (length(family_cols) == 0 || length(genus_cols) == 0) {
  ## Random effect BLUPs are sometimes stored separately
  message("[10b] NOTE: RE BLUPs not in Sol — extracting from model$Sol directly")
  message("      Check MCMCglmm version; structure may differ. Proceeding...")
}

## Helper: extract BLUP table from Sol columns matching a prefix
extract_blups <- function(sol_mat, prefix) {
  cols <- grep(paste0("^", prefix, "\\."), colnames(sol_mat), value = TRUE)
  if (length(cols) == 0) return(NULL)
  level_names <- sub(paste0("^", prefix, "\\."), "", cols)
  data.table(
    level      = level_names,
    blup_mean  = apply(sol_mat[, cols, drop = FALSE], 2, mean),
    blup_sd    = apply(sol_mat[, cols, drop = FALSE], 2, sd),
    blup_ci_lo = apply(sol_mat[, cols, drop = FALSE], 2, quantile, 0.025),
    blup_ci_hi = apply(sol_mat[, cols, drop = FALSE], 2, quantile, 0.975)
  )
}

family_blups <- extract_blups(sol_post, "family")
genus_blups  <- extract_blups(sol_post, "genus")

if (!is.null(family_blups)) {
  fwrite(family_blups, "output/pglmm_family_blups.csv")
  message("[10b] Family BLUPs written: ", nrow(family_blups), " families")
} else {
  message("[10b] WARNING: Family BLUPs not extracted — check model Sol structure")
}

if (!is.null(genus_blups)) {
  fwrite(genus_blups, "output/pglmm_genus_blups.csv")
  message("[10b] Genus BLUPs written: ", nrow(genus_blups), " genera")
} else {
  message("[10b] WARNING: Genus BLUPs not extracted — check model Sol structure")
}

## ---- Chain diagnostics (basic) ---------------------------------------------
message("\n[10b] === Chain diagnostics ===")
message("Gelman-Rubin R-hat requires multiple chains — not computed for single chain.")
message("Check trace plots and effective sample sizes:")

eff_samps <- apply(vcv_post, 2, effectiveSize)
for (nm in names(eff_samps)) {
  flag <- if (eff_samps[nm] < 200) " <<< LOW — consider longer chain" else ""
  message(sprintf("  ESS %-20s %.0f%s", nm, eff_samps[nm], flag))
}

message("\n[10b] Run gelman.diag() with nrun=2+ chains for full convergence check.")

message("=== Stage 10b complete ===")
