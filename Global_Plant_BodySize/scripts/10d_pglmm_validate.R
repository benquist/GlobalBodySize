## Global_Plant_BodySize/scripts/10d_pglmm_validate.R
## Stage 10d: Phylogenetically-informed k-fold cross-validation of the Stage 1
##   PGLMM (output of Stage 10b) and residual phylogenetic signal check.
##
## KEY DESIGN DECISION — PHYLOGENETIC K-FOLD:
##   Standard random k-fold CV leaks phylogenetic information: related species
##   appear in both train and test sets, inflating apparent predictive accuracy.
##   Here, entire FAMILIES are held out as test sets (family-level holdout).
##   This directly simulates the real-world scenario: predicting for a family
##   with no measured species using family BLUP from other families.
##
## VALIDATION WORKFLOW:
##   1. Partition measured species into 10 approximately-equal folds by family.
##      Families are assigned to folds; all species within a family go together.
##   2. For each fold:
##      a. Fit a reduced MCMCglmm on all species NOT in held-out families
##         (shorter chain for CV: nitt=60000, burnin=10000, thin=10 → 5000 draws)
##      b. Predict for held-out family species using:
##         - Grand mean + GF fixed effects only (no family BLUP available for holdouts)
##         - This simulates the worst-case imputation scenario for novel families
##      c. Compute RMSE, MAE, 90% PI coverage, Pearson r
##   3. Report validation metrics aggregated across folds and stratified by GF.
##   4. Compute Blomberg's K on Stage 1 model residuals (full chain).
##      K near 0 → model adequately captured phylogenetic signal in residuals.
##      K > 0.3  → consider adding higher taxonomic grouping or branch length scaling.
##
## IMPORTANT: This script requires Stage 10b (pglmm_stage1_model.rds) to be
##   complete. CV fitting 10 reduced models adds ~5-10× the Stage 10b runtime.
##   Use the QUICK_CV flag for a fast 3-fold subset check.
##
## References:
##   Blomberg SP, Garland T Jr & Ives AR (2003) Evolution 57(4):717-745.
##   DOI: 10.1111/j.0014-3820.2003.tb00285.x  [VERIFIED]
##
## Inputs:
##   output/plant_biomass_with_uncertainty.csv  — measured species data
##   output/pglmm_stage1_model.rds              — fitted Stage 1 model
##   output/tree_measured.nwk                   — pruned phylogeny
##
## Outputs:
##   output/pglmm_cv_fold_results.csv       — per-fold metrics
##   output/pglmm_cv_summary.csv            — aggregated CV metrics by GF
##   output/pglmm_residual_blomberg_k.csv   — Blomberg K on Stage 1 residuals
##   output/pglmm_validation_report.html    — human-readable summary (optional)
##
## Run from project root (slow — ~5-10 hours for full 10-fold):
##   QUICK_CV=3 Rscript scripts/10d_pglmm_validate.R   # fast 3-fold subset
##   Rscript scripts/10d_pglmm_validate.R               # full 10-fold

if (basename(getwd()) == "scripts") setwd("..")

suppressPackageStartupMessages({
  library(data.table)
  library(MCMCglmm)
  library(ape)
  library(phytools)  ## for phylosig() Blomberg K
})

set.seed(2026)

## ---- Configuration ---------------------------------------------------------
## Check for QUICK_CV environment variable (number of folds for fast test)
QUICK_CV   <- as.integer(Sys.getenv("QUICK_CV", unset = "0"))
N_FOLDS    <- if (QUICK_CV > 0) QUICK_CV else 10L
CV_NITT    <- if (QUICK_CV > 0) 20000L else 60000L
CV_BURNIN  <- if (QUICK_CV > 0) 5000L  else 10000L
CV_THIN    <- 10L

message("=== Stage 10d: Phylogenetic k-fold CV + Blomberg K ===")
message(sprintf("[10d] Folds: %d | nitt: %d | burnin: %d | thin: %d",
  N_FOLDS, CV_NITT, CV_BURNIN, CV_THIN))
if (QUICK_CV > 0) message("[10d] QUICK_CV mode: ", QUICK_CV, " folds only")

## ---- Check inputs ----------------------------------------------------------
required_files <- c(
  "output/plant_biomass_with_uncertainty.csv",
  "output/pglmm_stage1_model.rds",
  "output/tree_measured.nwk"
)
missing <- required_files[!file.exists(required_files)]
if (length(missing) > 0) stop("[10d] Missing input files:\n  ", paste(missing, collapse = "\n  "))

## ---- Load data -------------------------------------------------------------
dt_all   <- fread("output/plant_biomass_with_uncertainty.csv",
                  colClasses = list(character = "agb_best_tier"))
model_s1 <- readRDS("output/pglmm_stage1_model.rds")
tree_m   <- read.tree("output/tree_measured.nwk")

## ---- Fill family from backbone lookup (family column is all NA in pipeline) -
if (file.exists("output/genus_family_lookup.csv")) {
  gf_lookup <- fread("output/genus_family_lookup.csv")
  setnames(gf_lookup, c("genus", "family_backbone"))
  dt_all[, genus_clean := trimws(genus)]
  dt_all <- merge(dt_all, gf_lookup, by.x = "genus_clean", by.y = "genus", all.x = TRUE)
  dt_all[, family := ifelse(!is.na(family_backbone) & family_backbone != "",
                            family_backbone,
                     ifelse(!is.na(family) & family != "", family, NA_character_))]
  dt_all[, family_backbone := NULL]
  message("[10d] Family filled from backbone: ", dt_all[!is.na(family), .N], " / ", nrow(dt_all))
}

MEAS_TIERS <- c("1", "2", "3", "4")
meas <- dt_all[agb_best_tier %in% MEAS_TIERS &
               !is.na(agb_best_kg) & agb_best_kg > 0 &
               !is.na(growth_form_canonical) &
               !is.na(family) & !is.na(genus)]
meas[, log10_agb_kg := log10(agb_best_kg)]
meas[, data_tier    := paste0("T", agb_best_tier)]
meas[, animal       := gsub(" ", "_", species_name)]

## Keep only species in tree
meas <- meas[animal %in% tree_m$tip.label]
message("[10d] Measured species for CV: ", nrow(meas))

## ---- Stage 1 residuals for Blomberg K (before CV) --------------------------
message("\n[10d] Computing Blomberg K on Stage 1 residuals...")

## Fitted values from Stage 1 model
## MCMCglmm fitted values = posterior mean of Sol (fixed) + RE contributions
## Simplified: use posterior mean fixed effects applied to training data
sol_mean <- colMeans(model_s1$Sol)
fitted_intercept <- sol_mean["(Intercept)"]

## Build design-like prediction for training data
meas[, fitted_fe := {
  fe <- fitted_intercept
  ## Add GF fixed effects
  gf_col <- paste0("growth_form_canonical", growth_form_canonical)
  fe + vapply(gf_col, function(nm) ifelse(nm %in% names(sol_mean), sol_mean[nm], 0), numeric(1))
}]
meas[, resid_s1 := log10_agb_kg - fitted_fe]

## Compute Blomberg K using phytools::phylosig()
tree_resid <- keep.tip(tree_m, meas$animal)
resid_vec  <- setNames(meas$resid_s1, meas$animal)
resid_vec  <- resid_vec[tree_resid$tip.label]  ## align to tree order

k_result <- tryCatch(
  phylosig(tree_resid, resid_vec, method = "K", test = TRUE, nsim = 999),
  error = function(e) {
    message("[10d] Blomberg K computation failed: ", conditionMessage(e))
    NULL
  }
)

blomberg_dt <- NULL
if (!is.null(k_result)) {
  blomberg_dt <- data.table(
    metric   = "Blomberg_K",
    value    = k_result$K,
    p_value  = k_result$P,
    n_species = length(resid_vec),
    interpretation = fcase(
      k_result$K < 0.1,  "NEAR_ZERO: model adequately captured phylogenetic signal",
      k_result$K < 0.3,  "LOW: minor residual phylogenetic signal remaining",
      k_result$K < 0.6,  "MODERATE: consider adding higher-level taxonomic RE",
      default = "HIGH: substantial residual signal — consider branch length rescaling"
    )
  )
  message(sprintf("[10d] Blomberg K = %.4f  (p = %.4f)", k_result$K, k_result$P))
  message(sprintf("[10d]   %s", blomberg_dt$interpretation))

  dir.create("output", showWarnings = FALSE)
  fwrite(blomberg_dt, "output/pglmm_residual_blomberg_k.csv")
  message("[10d] Blomberg K written: output/pglmm_residual_blomberg_k.csv")
}

## ---- Phylogenetic k-fold CV ------------------------------------------------
message("\n[10d] Assigning families to ", N_FOLDS, " folds (family-level holdout)...")

## Get unique families and assign to folds
families <- unique(meas$family)
families <- families[!is.na(families)]
set.seed(42)
families_shuffled <- sample(families)
fold_assignments <- data.table(
  family = families_shuffled,
  fold   = ((seq_along(families_shuffled) - 1) %% N_FOLDS) + 1L
)

meas <- merge(meas, fold_assignments, by = "family", all.x = TRUE)
meas[is.na(fold), fold := N_FOLDS]  ## unassigned → last fold

for (f in seq_len(N_FOLDS)) {
  message(sprintf("[10d] Fold %d: %d species (%d families) held out",
    f, meas[fold == f, .N], meas[fold == f, uniqueN(family)]))
}

## ---- Run CV folds ----------------------------------------------------------
cv_results <- vector("list", N_FOLDS)

## Reuse Stage 1 prior (N_FOLDS models will use same prior spec)
## Prior must have correct dimension for each fold's fixed effects
## (number of levels may vary — recompute inside loop)

for (f in seq_len(N_FOLDS)) {
  message(sprintf("\n[10d] === Fold %d / %d ===", f, N_FOLDS))
  t_fold <- proc.time()

  train  <- meas[fold != f]
  test   <- meas[fold == f]

  message(sprintf("[10d] Train: %d  |  Test: %d", nrow(train), nrow(test)))

  ## Build tree for training species
  tree_train <- tryCatch(
    keep.tip(tree_m, train$animal[train$animal %in% tree_m$tip.label]),
    error = function(e) NULL
  )
  if (is.null(tree_train) || length(tree_train$tip.label) < 10) {
    message("[10d] Fold ", f, ": insufficient tree tips — skipping")
    next
  }

  train_fit <- train[animal %in% tree_train$tip.label]
  Ainv_cv   <- inverseA(tree_train, nodes = "TIPS", scale = TRUE)$Ainv

  ## Dynamic prior: adjust B dimension to actual parameter count
  gf_lev  <- unique(train_fit$growth_form_canonical)
  tier_lev <- unique(train_fit$data_tier)
  hpg_lev  <- unique(train_fit$higher_plant_group)
  np <- 1 + (length(gf_lev) - 1) + (length(tier_lev) - 1) + (length(hpg_lev) - 1)

  prior_cv <- list(
    B = list(mu = rep(0, np), V = diag(np) * 4),
    G = list(G1 = list(V = 1, nu = 1),
             G2 = list(V = 1, nu = 1),
             G3 = list(V = 1, nu = 1)),
    R = list(V = 1, nu = 1)
  )

  model_cv <- tryCatch(
    MCMCglmm(
      log10_agb_kg ~ growth_form_canonical + data_tier + higher_plant_group,
      random   = ~ animal + family + genus,
      family   = "gaussian",
      ginverse = list(animal = Ainv_cv),
      data     = as.data.frame(train_fit),
      prior    = prior_cv,
      nitt     = CV_NITT,
      burnin   = CV_BURNIN,
      thin     = CV_THIN,
      verbose  = FALSE
    ),
    error = function(e) {
      message("[10d] Fold ", f, " MCMCglmm error: ", conditionMessage(e))
      NULL
    }
  )

  if (is.null(model_cv)) { cv_results[[f]] <- NULL; next }

  ## Predict for test species (held-out families → family BLUP not available)
  ## Use only fixed effects (grand mean + GF FE): worst-case scenario simulation
  sol_cv <- colMeans(model_cv$Sol)
  vcv_cv <- colMeans(model_cv$VCV)
  v_r_cv <- vcv_cv["units"]

  ## Build test predictions
  test_pred <- copy(test)
  test_pred[, predicted := {
    base <- sol_cv["(Intercept)"]
    gf_col_nm <- paste0("growth_form_canonical", growth_form_canonical)
    gf_fe     <- vapply(gf_col_nm, function(nm) ifelse(nm %in% names(sol_cv), sol_cv[nm], 0), numeric(1))
    base + gf_fe
  }]

  ## Prediction SD from V_R (residual only — no family BLUP)
  test_pred[, pred_sd := sqrt(v_r_cv + vcv_cv["family.family"])]

  ## Metrics
  test_pred[, error      := predicted - log10_agb_kg]
  test_pred[, sq_error   := error^2]
  test_pred[, in_90_pi   := log10_agb_kg >= (predicted - 1.645 * pred_sd) &
                             log10_agb_kg <= (predicted + 1.645 * pred_sd)]

  rmse      <- sqrt(mean(test_pred$sq_error, na.rm = TRUE))
  mae       <- mean(abs(test_pred$error), na.rm = TRUE)
  pi_cov    <- mean(test_pred$in_90_pi, na.rm = TRUE)
  pearson_r <- tryCatch(cor(test_pred$predicted, test_pred$log10_agb_kg, use = "complete"),
                        error = function(e) NA_real_)
  bias      <- mean(test_pred$error, na.rm = TRUE)

  t_fold_elapsed <- (proc.time() - t_fold)["elapsed"] / 60
  message(sprintf("[10d] Fold %d: RMSE=%.4f  MAE=%.4f  90%%PI_cov=%.3f  r=%.4f  bias=%.4f  (%.1f min)",
    f, rmse, mae, pi_cov, pearson_r, bias, t_fold_elapsed))

  ## Per-GF metrics
  gf_metrics <- test_pred[, .(
    n           = .N,
    rmse        = sqrt(mean(sq_error, na.rm = TRUE)),
    mae         = mean(abs(error), na.rm = TRUE),
    pi_cov_90   = mean(in_90_pi, na.rm = TRUE),
    pearson_r   = tryCatch(cor(predicted, log10_agb_kg, use = "complete"), error = function(e) NA_real_),
    bias        = mean(error, na.rm = TRUE)
  ), by = growth_form_canonical]

  cv_results[[f]] <- list(
    fold       = f,
    n_train    = nrow(train_fit),
    n_test     = nrow(test_pred),
    rmse       = rmse,
    mae        = mae,
    pi_cov_90  = pi_cov,
    pearson_r  = pearson_r,
    bias       = bias,
    gf_metrics = gf_metrics
  )

  rm(model_cv); gc(verbose = FALSE)
}

## ---- Aggregate CV results --------------------------------------------------
valid_folds <- Filter(Negate(is.null), cv_results)
n_valid <- length(valid_folds)

if (n_valid == 0) {
  warning("[10d] No valid folds completed. Check MCMCglmm errors above.")
} else {
  ## Overall fold-level summary
  fold_dt <- rbindlist(lapply(valid_folds, function(x) {
    data.table(fold = x$fold, n_train = x$n_train, n_test = x$n_test,
               rmse = x$rmse, mae = x$mae, pi_cov_90 = x$pi_cov_90,
               pearson_r = x$pearson_r, bias = x$bias)
  }))

  message("\n[10d] === Cross-validation summary (", n_valid, "/", N_FOLDS, " folds) ===")
  message(sprintf("  Mean RMSE         : %.4f log10 kg", mean(fold_dt$rmse, na.rm = TRUE)))
  message(sprintf("  Mean MAE          : %.4f log10 kg", mean(fold_dt$mae,  na.rm = TRUE)))
  message(sprintf("  Mean 90%% PI cover : %.3f (target: 0.90)", mean(fold_dt$pi_cov_90, na.rm = TRUE)))
  message(sprintf("  Mean Pearson r    : %.4f",  mean(fold_dt$pearson_r, na.rm = TRUE)))
  message(sprintf("  Mean bias         : %.4f log10 kg", mean(fold_dt$bias, na.rm = TRUE)))

  ## GF-level metrics pooled across folds
  gf_all <- rbindlist(lapply(valid_folds, function(x) x$gf_metrics), fill = TRUE)
  gf_summary <- gf_all[, .(
    n_total     = sum(n, na.rm = TRUE),
    mean_rmse   = mean(rmse,      na.rm = TRUE),
    mean_mae    = mean(mae,       na.rm = TRUE),
    mean_pi90   = mean(pi_cov_90, na.rm = TRUE),
    mean_r      = mean(pearson_r, na.rm = TRUE),
    mean_bias   = mean(bias,      na.rm = TRUE)
  ), by = growth_form_canonical]

  message("\n[10d] GF-level CV metrics (mean across folds):")
  for (i in seq_len(nrow(gf_summary))) {
    r <- gf_summary[i]
    message(sprintf("  %-12s n=%-5d RMSE=%.3f  90PI=%.2f  r=%.3f  bias=%+.3f",
      r$growth_form_canonical, r$n_total, r$mean_rmse, r$mean_pi90, r$mean_r, r$mean_bias))
  }

  dir.create("output", showWarnings = FALSE)
  fwrite(fold_dt,    "output/pglmm_cv_fold_results.csv")
  fwrite(gf_summary, "output/pglmm_cv_summary.csv")
  message("\n[10d] CV results written:")
  message("  output/pglmm_cv_fold_results.csv")
  message("  output/pglmm_cv_summary.csv")

  ## Calibration warning
  pi_mean <- mean(fold_dt$pi_cov_90, na.rm = TRUE)
  if (pi_mean < 0.80) {
    message("\n[10d] WARNING: 90% PI coverage = ", round(pi_mean, 3),
      " — substantially below target (0.90).")
    message("      Prediction intervals are overconfident. Consider:")
    message("      1. Wider priors on variance components")
    message("      2. Additional taxonomic random effects")
    message("      3. Reporting 80% PI instead of 90%")
  } else if (pi_mean > 0.98) {
    message("\n[10d] NOTE: 90% PI coverage = ", round(pi_mean, 3), " — conservative (too wide).")
    message("      Prediction intervals may be overly uncertain for well-measured families.")
  } else {
    message("\n[10d] 90% PI coverage = ", round(pi_mean, 3), " — approximately calibrated (target: 0.90)")
  }
}

message("=== Stage 10d complete ===")
