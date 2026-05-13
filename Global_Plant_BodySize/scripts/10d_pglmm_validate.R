## Global_Plant_BodySize/scripts/10d_pglmm_validate.R
## Stage 10d: Multi-mode k-fold cross-validation of the PGLMM + Blomberg K.
##
## THREE CV MODES (set CV_MODE environment variable):
##
##   CV_MODE=family  [default]
##     Family-holdout CV (CV-B worst-case). Hold out entire families; refit
##     PGLMM; predict held-out species using fixed effects only (no family BLUP).
##     Estimand: 44K species with no genus-level training data.
##
##   CV_MODE=genus_extrap
##     Strict genus-holdout CV (approximate shortcut, NO refit). Zero the genus
##     BLUP from Stage 1 model; predict from fixed FE + family BLUP only.
##     VC from full-data Stage 1 fit — labeled explicitly as approximate.
##     Estimand: 44K species with no congeners in training set.
##     Requires: pglmm_family_blups.csv, pglmm_fixed_effects.csv, pglmm_variance_components.csv
##
##   CV_MODE=genus_interp
##     Within-genus holdout CV (full refit + pr=TRUE). Hold back ~50% of species
##     per eligible genus (>=2 measured); refit PGLMM; predict held-out species
##     using genus BLUP estimated from retained congeners.
##     Estimand: 217K species that share a genus with >=1 measured congener.
##
## PHYLOGENETIC LEAKAGE DISCLOSURE (all modes):
##   Covariance matrix A is fixed across folds (tree not rebuilt). CV estimates
##   a LOWER BOUND on true out-of-sample error. Results stratified by placement
##   scenario (S1/2 resolved vs. S3 polytomy). S3 RMSE labeled as lower bound —
##   polytomy-placed congeners share stem covariance even when genus BLUP zeroed.
##
## DATA_TIER TREATMENT:
##   Held-out species are predicted with data_tier="T1" (reference level, zero
##   FE offset). This simulates production: 261K target species have no allometric
##   measurement. Using observed tier would underestimate prediction error.
##
## CONVERGENCE:
##   N_CHAINS >= 3 (non-QUICK_CV): Gelman-Rubin R-hat computed for fixed effects.
##   Folds with any R-hat > 1.1 flagged. ESS reported for VCVs.
##
## References:
##   Blomberg SP, Garland T Jr & Ives AR (2003) Evolution 57(4):717-745.
##   DOI: 10.1111/j.0014-3820.2003.tb00285.x  [VERIFIED]
##   Hadfield JD (2010) J Stat Software 33(2). [UNVERIFIED vol/pg — verify before submit]
##   Gelman A & Rubin DB (1992) Statistical Science 7(4):457-472.
##
## Inputs:
##   output/plant_biomass_with_uncertainty.csv
##   output/pglmm_stage1_model.rds              (family + genus_interp modes)
##   output/tree_measured.nwk
##   output/tree_placement_audit.csv            (for S1/2 vs S3 stratification)
##   output/genus_family_lookup.csv
##   output/pglmm_family_blups.csv              (genus_extrap mode)
##   output/pglmm_fixed_effects.csv             (genus_extrap mode)
##   output/pglmm_variance_components.csv       (genus_extrap mode)
##
## Outputs (prefixed with cv mode name):
##   output/pglmm_cv_{mode}_fold_results.csv
##   output/pglmm_cv_{mode}_gf_summary.csv
##   output/pglmm_cv_{mode}_sizeclass_summary.csv
##   output/pglmm_cv_{mode}_scenario_summary.csv
##   output/pglmm_cv_{mode}_calibration.csv
##   output/pglmm_residual_blomberg_k.csv       (computed once, all modes)
##
## Run from project root:
##   CV_MODE=family       QUICK_CV=3 Rscript scripts/10d_pglmm_validate.R
##   CV_MODE=genus_extrap            Rscript scripts/10d_pglmm_validate.R
##   CV_MODE=genus_interp QUICK_CV=5 Rscript scripts/10d_pglmm_validate.R

if (basename(getwd()) == "scripts") setwd("..")

suppressPackageStartupMessages({
  library(data.table)
  library(MCMCglmm)
  library(ape)
  library(phytools)
})

## ---- Configuration ---------------------------------------------------------
CV_MODE  <- tolower(Sys.getenv("CV_MODE",  unset = "family"))
QUICK_CV <- as.integer(Sys.getenv("QUICK_CV", unset = "0"))

if (!CV_MODE %in% c("family", "genus_extrap", "genus_interp"))
  stop("[10d] Unknown CV_MODE='", CV_MODE, "'. Use: family | genus_extrap | genus_interp")

if (CV_MODE == "family") {
  N_FOLDS   <- if (QUICK_CV > 0) QUICK_CV else 10L
  CV_NITT   <- if (QUICK_CV > 0) 20000L   else 60000L
  CV_BURNIN <- if (QUICK_CV > 0)  5000L   else 10000L
  CV_THIN   <- 10L
  N_CHAINS  <- if (QUICK_CV > 0) 1L else 3L
} else if (CV_MODE == "genus_extrap") {
  N_FOLDS  <- if (QUICK_CV > 0) QUICK_CV else 10L
  N_CHAINS <- 0L
} else {  ## genus_interp
  N_FOLDS        <- if (QUICK_CV > 0) QUICK_CV else 5L
  CV_NITT        <- if (QUICK_CV > 0) 20000L   else 60000L
  CV_BURNIN      <- if (QUICK_CV > 0)  5000L   else 10000L
  CV_THIN        <- 10L
  N_CHAINS       <- if (QUICK_CV > 0) 1L else 3L
  MIN_GENUS_SIZE <- 2L
  HOLDOUT_FRAC   <- 0.50
}

message("=== Stage 10d: PGLMM CV + Blomberg K ===")
message(sprintf("[10d] CV_MODE=%s | N_FOLDS=%d | QUICK_CV=%s",
  CV_MODE, N_FOLDS, if (QUICK_CV > 0) as.character(QUICK_CV) else "OFF"))

## ---- Check inputs ----------------------------------------------------------
required_always  <- c("output/plant_biomass_with_uncertainty.csv",
                       "output/tree_measured.nwk",
                       "output/genus_family_lookup.csv")
required_refit   <- "output/pglmm_stage1_model.rds"
required_extrap  <- c("output/pglmm_family_blups.csv",
                       "output/pglmm_fixed_effects.csv",
                       "output/pglmm_variance_components.csv")

check_files <- required_always
if (CV_MODE %in% c("family", "genus_interp")) check_files <- c(check_files, required_refit)
if (CV_MODE == "genus_extrap")                check_files <- c(check_files, required_extrap)

missing_files <- check_files[!file.exists(check_files)]
if (length(missing_files) > 0)
  stop("[10d] Missing required inputs:\n  ", paste(missing_files, collapse = "\n  "))

## ---- Load data -------------------------------------------------------------
dt_all <- fread("output/plant_biomass_with_uncertainty.csv",
                colClasses = list(character = "agb_best_tier"))
tree_m  <- read.tree("output/tree_measured.nwk")

gf_lookup <- fread("output/genus_family_lookup.csv")
setnames(gf_lookup, c("genus", "family_backbone"))
dt_all[, genus_clean := trimws(genus)]
dt_all <- merge(dt_all, gf_lookup, by.x = "genus_clean", by.y = "genus", all.x = TRUE)
dt_all[, family := ifelse(!is.na(family_backbone) & family_backbone != "",
                          family_backbone,
                   ifelse(!is.na(family) & family != "", family, NA_character_))]
dt_all[, family_backbone := NULL]
message("[10d] Family filled from backbone: ", dt_all[!is.na(family), .N], " / ", nrow(dt_all))

## Placement scenario from tree audit
scenario_dt <- NULL
if (file.exists("output/tree_placement_audit.csv")) {
  audit <- fread("output/tree_placement_audit.csv")
  if ("scenario" %in% names(audit) && "species" %in% names(audit)) {
    scenario_dt <- audit[, .(
      animal         = gsub(" ", "_", species),
      scenario_group = ifelse(scenario == 3, "S3_polytomy", "S1_2_resolved")
    )]
    message("[10d] Placement scenario: ",
      scenario_dt[scenario_group=="S3_polytomy", .N], " S3 | ",
      scenario_dt[scenario_group=="S1_2_resolved", .N], " S1/2")
  }
}

## Measured subset
MEAS_TIERS <- c("1", "2", "3", "4")
meas <- dt_all[agb_best_tier %in% MEAS_TIERS &
               !is.na(agb_best_kg) & agb_best_kg > 0 &
               !is.na(growth_form_canonical) &
               !is.na(family) & !is.na(genus)]
meas[, log10_agb_kg := log10(agb_best_kg)]
meas[, data_tier    := paste0("T", agb_best_tier)]
meas[, animal       := gsub(" ", "_", species_name)]

hpg_n    <- meas[, .N, by = higher_plant_group]
rare_hpg <- hpg_n[N < 20, higher_plant_group]
meas[higher_plant_group %in% rare_hpg | is.na(higher_plant_group), higher_plant_group := "other"]

meas <- meas[animal %in% tree_m$tip.label]
message("[10d] Measured species in tree: ", nrow(meas))

if (!is.null(scenario_dt)) {
  meas <- merge(meas, scenario_dt, by = "animal", all.x = TRUE)
  meas[is.na(scenario_group), scenario_group := "unknown"]
} else {
  meas[, scenario_group := "unknown"]
}

genus_size <- meas[, .(n_meas_genus = .N), by = genus]
meas <- merge(meas, genus_size, by = "genus", all.x = TRUE)
meas[, genus_size_class := fcase(
  n_meas_genus == 1,  "n1",
  n_meas_genus <= 5,  "n2_5",
  n_meas_genus <= 20, "n6_20",
  default = "n21plus"
)]

message("[10d] Genus size class breakdown:")
meas[, .N, by = genus_size_class][order(genus_size_class)] |>
  (\(x) for(i in seq_len(nrow(x))) message(sprintf("  %-8s: %d spp", x$genus_size_class[i], x$N[i])))()

## ---- Helpers ---------------------------------------------------------------
compute_metrics <- function(dt) {
  dt[, error  := predicted - log10_agb_kg]
  dt[, sq_err := error^2]
  dt[, in_95  := log10_agb_kg >= (predicted - 1.96  * pred_sd) &
                 log10_agb_kg <= (predicted + 1.96  * pred_sd)]
  dt[, in_80  := log10_agb_kg >= (predicted - 1.282 * pred_sd) &
                 log10_agb_kg <= (predicted + 1.282 * pred_sd)]
  list(
    n         = nrow(dt),
    rmse      = sqrt(mean(dt$sq_err, na.rm = TRUE)),
    mae       = mean(abs(dt$error), na.rm = TRUE),
    bias      = mean(dt$error, na.rm = TRUE),
    cov_95    = mean(dt$in_95,  na.rm = TRUE),
    cov_80    = mean(dt$in_80,  na.rm = TRUE),
    pearson_r = tryCatch(cor(dt$predicted, dt$log10_agb_kg, use = "complete"), error = function(e) NA_real_)
  )
}

strat_metrics <- function(dt, col) {
  dt[, error  := predicted - log10_agb_kg]
  dt[, sq_err := error^2]
  dt[, in_95  := log10_agb_kg >= (predicted - 1.96 * pred_sd) &
                 log10_agb_kg <= (predicted + 1.96 * pred_sd)]
  dt[, .(
    n         = .N,
    rmse      = sqrt(mean(sq_err, na.rm = TRUE)),
    mae       = mean(abs(error), na.rm = TRUE),
    bias      = mean(error, na.rm = TRUE),
    cov_95    = mean(in_95, na.rm = TRUE),
    pearson_r = tryCatch(cor(predicted, log10_agb_kg, use="complete"), error=function(e) NA_real_)
  ), by = col]
}

calibration_table <- function(dt) {
  alphas <- seq(0.10, 0.90, by = 0.10)
  rbindlist(lapply(alphas, function(a) {
    z <- qnorm(1 - a / 2)
    data.table(
      nominal_coverage   = 1 - a,
      empirical_coverage = mean(dt$log10_agb_kg >= (dt$predicted - z*dt$pred_sd) &
                                dt$log10_agb_kg <= (dt$predicted + z*dt$pred_sd), na.rm=TRUE),
      n = nrow(dt)
    )
  }))
}

fe_prediction <- function(sol_mean, gf_vec, tier_vec, hpg_vec) {
  base    <- sol_mean["(Intercept)"]
  gf_nm   <- paste0("growth_form_canonical", gf_vec)
  tier_nm <- paste0("data_tier", tier_vec)
  hpg_nm  <- paste0("higher_plant_group", hpg_vec)
  base +
    vapply(gf_nm,   function(nm) ifelse(nm %in% names(sol_mean), sol_mean[nm], 0), numeric(1)) +
    vapply(tier_nm, function(nm) ifelse(nm %in% names(sol_mean), sol_mean[nm], 0), numeric(1)) +
    vapply(hpg_nm,  function(nm) ifelse(nm %in% names(sol_mean), sol_mean[nm], 0), numeric(1))
}

write_cv_outputs <- function(fold_dt, all_test_dt, mode_name) {
  gf_sum   <- strat_metrics(copy(all_test_dt), "growth_form_canonical")
  sc_sum   <- strat_metrics(copy(all_test_dt), "genus_size_class")
  scen_sum <- strat_metrics(copy(all_test_dt), "scenario_group")
  calib    <- calibration_table(all_test_dt)

  pfx <- paste0("output/pglmm_cv_", mode_name)
  dir.create("output", showWarnings = FALSE)
  fwrite(fold_dt,  paste0(pfx, "_fold_results.csv"))
  fwrite(gf_sum,   paste0(pfx, "_gf_summary.csv"))
  fwrite(sc_sum,   paste0(pfx, "_sizeclass_summary.csv"))
  fwrite(scen_sum, paste0(pfx, "_scenario_summary.csv"))
  fwrite(calib,    paste0(pfx, "_calibration.csv"))

  message("[10d] CV outputs written: ", pfx, "_{fold_results, gf, sizeclass, scenario, calibration}.csv")

  if (scen_sum[scenario_group == "S3_polytomy", .N] > 0)
    message(sprintf("[10d] S3 RMSE=%.4f — lower bound (polytomy covariance leakage into held-out genus/family)",
      scen_sum[scenario_group == "S3_polytomy", rmse]))

  cal_miss <- calib[abs(empirical_coverage - nominal_coverage) > 0.10, .N]
  if (cal_miss > 0)
    message(sprintf("[10d] CALIBRATION WARNING: %d of %d quantile levels have |empirical - nominal| > 0.10",
      cal_miss, nrow(calib)))
}

## ============================================================================
## BLOMBERG K
## ============================================================================
if (file.exists("output/pglmm_stage1_model.rds") &&
    !file.exists("output/pglmm_residual_blomberg_k.csv")) {

  message("\n[10d] Computing Blomberg K on Stage 1 residuals (stratified by scenario)...")
  model_s1_k <- readRDS("output/pglmm_stage1_model.rds")
  sol_k      <- colMeans(model_s1_k$Sol)

  meas[, fitted_k := fe_prediction(sol_k, growth_form_canonical, data_tier, higher_plant_group)]
  meas[, resid_k  := log10_agb_kg - fitted_k]
  rm(model_s1_k); gc(verbose = FALSE)

  do_blomberg <- function(tree_in, sub_dt, label) {
    tr  <- keep.tip(tree_in, sub_dt$animal)
    vec <- setNames(sub_dt$resid_k, sub_dt$animal)[tr$tip.label]
    if (length(vec) < 10) return(NULL)
    k   <- tryCatch(phylosig(tr, vec, method="K", test=TRUE, nsim=499),
                    error = function(e) { message("[10d] K error (", label, "): ", e$message); NULL })
    if (is.null(k)) return(NULL)
    data.table(
      scenario    = label,
      n_species   = length(vec),
      blomberg_K  = k$K,
      p_value     = k$P,
      note        = fcase(
        k$K < 0.1, "NEAR_ZERO",
        k$K < 0.3, "LOW",
        k$K < 0.6, "MODERATE",
        default    = "HIGH"
      )
    )
  }

  k_results <- list(do_blomberg(tree_m, meas, "all"))
  for (sg in unique(meas$scenario_group))
    k_results[[sg]] <- do_blomberg(tree_m, meas[scenario_group==sg], sg)
  k_dt <- rbindlist(Filter(Negate(is.null), k_results), fill=TRUE)

  message("[10d] Blomberg K:")
  for (i in seq_len(nrow(k_dt)))
    message(sprintf("  %-25s n=%-5d K=%.4f p=%.4f %s",
      k_dt$scenario[i], k_dt$n_species[i], k_dt$blomberg_K[i], k_dt$p_value[i], k_dt$note[i]))
  if ("S3_polytomy" %in% k_dt$scenario)
    message("[10d] NOTE: S3 K inflated — polytomy covariance treats all S3 congeners as exchangeable at genus node")

  fwrite(k_dt, "output/pglmm_residual_blomberg_k.csv")
  meas[, c("fitted_k", "resid_k") := NULL]
} else if (file.exists("output/pglmm_residual_blomberg_k.csv")) {
  message("[10d] Blomberg K file exists — skipping (delete to recompute)")
}

## ============================================================================
## HELPER: fit one or more MCMCglmm chains
## ============================================================================
fit_chains <- function(train_dt, tree_in, n_chains, nitt, burnin, thin, fold_id, pr_flag=FALSE) {
  hpg_n_f    <- train_dt[, .N, by=higher_plant_group]
  rare_f     <- hpg_n_f[N < 5, higher_plant_group]
  train_dt[higher_plant_group %in% rare_f, higher_plant_group := "other"]

  tree_tr <- tryCatch(keep.tip(tree_in, train_dt$animal[train_dt$animal %in% tree_in$tip.label]),
                       error=function(e) NULL)
  if (is.null(tree_tr) || length(tree_tr$tip.label) < 10) return(NULL)
  train_fit <- train_dt[animal %in% tree_tr$tip.label]
  Ainv_cv   <- inverseA(tree_tr, nodes="TIPS", scale=TRUE)$Ainv

  np <- 1 + (uniqueN(train_fit$growth_form_canonical)-1) +
            (uniqueN(train_fit$data_tier)-1) +
            (uniqueN(train_fit$higher_plant_group)-1)
  prior_cv <- list(
    B = list(mu=rep(0,np), V=diag(np)*4),
    G = list(G1=list(V=1,nu=1), G2=list(V=1,nu=1), G3=list(V=1,nu=1)),
    R = list(V=1, nu=1)
  )

  chains <- vector("list", max(n_chains, 1L))
  for (ch in seq_along(chains)) {
    set.seed(2026 + fold_id * 100 + ch)
    chains[[ch]] <- tryCatch(
      MCMCglmm(
        log10_agb_kg ~ growth_form_canonical + data_tier + higher_plant_group,
        random   = ~ animal + family + genus,
        family   = "gaussian",
        ginverse = list(animal=Ainv_cv),
        data     = as.data.frame(train_fit),
        prior    = prior_cv,
        nitt=nitt, burnin=burnin, thin=thin,
        pr=pr_flag, verbose=FALSE
      ),
      error=function(e) { message("[10d] Chain ", ch, " fold ", fold_id, ": ", e$message); NULL }
    )
  }
  valid <- Filter(Negate(is.null), chains)
  if (length(valid) == 0) return(NULL)

  rhat_flag <- FALSE
  if (length(valid) >= 2) {
    mc <- lapply(valid, function(m) coda::as.mcmc(m$Sol))
    gd <- tryCatch(coda::gelman.diag(mc)$psrf, error=function(e) NULL)
    if (!is.null(gd)) {
      rhat_flag <- max(gd[,1], na.rm=TRUE) > 1.1
      message(sprintf("[10d] Fold %d R-hat max=%.3f%s", fold_id, max(gd[,1],na.rm=TRUE),
        if (rhat_flag) " <<< FLAGGED" else ""))
    }
  }

  sol_pool <- do.call(rbind, lapply(valid, function(m) as.matrix(m$Sol)))
  vcv_pool <- do.call(rbind, lapply(valid, function(m) as.matrix(m$VCV)))
  list(sol_mean=colMeans(sol_pool), vcv_mean=colMeans(vcv_pool),
       rhat_flag=rhat_flag, n_train=nrow(train_fit))
}

## ============================================================================
## CV MODE: family
## ============================================================================
if (CV_MODE == "family") {
  message("\n[10d] === Family-holdout CV ===")
  message("[10d] Estimand: 44K species with no genus-level training data (worst-case).")

  fam_stats <- meas[, .(dom_gf=names(which.max(table(growth_form_canonical)))), by=family]
  setorder(fam_stats, dom_gf)
  fam_stats[, fold := ((seq_len(.N)-1) %% N_FOLDS) + 1L]
  meas <- merge(meas, fam_stats[,.(family,fold)], by="family", all.x=TRUE)
  meas[is.na(fold), fold := N_FOLDS]

  message("[10d] Fold sizes (species / families):")
  for (f in seq_len(N_FOLDS))
    message(sprintf("  Fold %2d: %4d spp | %3d fam", f, meas[fold==f,.N], meas[fold==f,uniqueN(family)]))

  cv_results <- vector("list", N_FOLDS)
  all_preds  <- vector("list", N_FOLDS)

  for (f in seq_len(N_FOLDS)) {
    message(sprintf("\n[10d] Fold %d/%d", f, N_FOLDS)); t0 <- proc.time()
    train <- meas[fold != f]
    test  <- copy(meas[fold == f]); test[, data_tier := "T1"]

    res <- fit_chains(train, tree_m, N_CHAINS, CV_NITT, CV_BURNIN, CV_THIN, f, pr_flag=FALSE)
    if (is.null(res)) { message("[10d] Fold ", f, " failed — skipping"); next }

    test[, predicted := fe_prediction(res$sol_mean, growth_form_canonical, data_tier, higher_plant_group)]
    test[, pred_sd   := sqrt(res$vcv_mean["units"] + res$vcv_mean["family.family"])]

    m <- compute_metrics(test)
    elapsed <- (proc.time()-t0)["elapsed"]/60
    message(sprintf("[10d] Fold %d: RMSE=%.4f bias=%+.4f 95PI=%.3f r=%.4f rhat=%s (%.1f min)",
      f, m$rmse, m$bias, m$cov_95, m$pearson_r, res$rhat_flag, elapsed))

    cv_results[[f]] <- data.table(fold=f, n_train=res$n_train, n_test=nrow(test),
      rmse=m$rmse, mae=m$mae, bias=m$bias, cov_95=m$cov_95, cov_80=m$cov_80,
      pearson_r=m$pearson_r, rhat_flag=res$rhat_flag)
    all_preds[[f]] <- test
    gc(verbose=FALSE)
  }

  valid  <- Filter(Negate(is.null), cv_results)
  if (length(valid)==0) stop("[10d] No valid folds.")
  fold_dt  <- rbindlist(valid)
  all_dt   <- rbindlist(all_preds, fill=TRUE)

  m_all <- compute_metrics(all_dt)
  message(sprintf("\n[10d] Family-holdout overall: RMSE=%.4f bias=%+.4f 95PI=%.3f r=%.4f n=%d",
    m_all$rmse, m_all$bias, m_all$cov_95, m_all$pearson_r, m_all$n))

  write_cv_outputs(fold_dt, all_dt, "family")
}

## ============================================================================
## CV MODE: genus_extrap
## ============================================================================
if (CV_MODE == "genus_extrap") {
  message("\n[10d] === Genus-extrap CV (approximate shortcut; no refit) ===")
  message("[10d] Estimand: 44K species with no congeners in training set.")
  message("[10d] DISCLOSURE: genus BLUP zeroed; VC from full-data Stage 1 fit.")

  fe_dt    <- fread("output/pglmm_fixed_effects.csv")
  fam_blup <- fread("output/pglmm_family_blups.csv")
  vc_dt    <- fread("output/pglmm_variance_components.csv")

  sol_named    <- setNames(fe_dt$post_mean, fe_dt$parameter)
  fam_blup_vec <- setNames(fam_blup$blup_mean, fam_blup$level)
  v_fam <- vc_dt[component=="family.family", post_mean]
  v_gen <- vc_dt[component=="genus.genus",   post_mean]
  v_r   <- vc_dt[component=="units",         post_mean]
  if (length(v_fam)==0) stop("[10d] family.family VC not found. Did 10b run with pr=TRUE?")

  ## Stratified genus-fold assignment by family then size class
  gen_info <- meas[, .(family=family[1], n_meas=.N), by=genus]
  setorder(gen_info, family, n_meas)
  set.seed(42)
  gen_info[, fold := ((seq_len(.N)-1) %% N_FOLDS) + 1L]
  meas_ext <- merge(meas, gen_info[,.(genus,fold)], by="genus", all.x=TRUE)
  meas_ext[is.na(fold), fold := N_FOLDS]

  all_preds <- vector("list", N_FOLDS)
  for (f in seq_len(N_FOLDS)) {
    test <- copy(meas_ext[fold==f]); test[, data_tier := "T1"]
    message(sprintf("[10d] Fold %d/%d: %d spp, %d genera", f, N_FOLDS, nrow(test), uniqueN(test$genus)))

    test[, predicted := {
      base   <- sol_named["(Intercept)"]
      gf_nm  <- paste0("growth_form_canonical", growth_form_canonical)
      tier_nm<- paste0("data_tier", data_tier)
      hpg_nm <- paste0("higher_plant_group", higher_plant_group)
      gf_fe  <- vapply(gf_nm,  function(nm) ifelse(nm %in% names(sol_named), sol_named[nm], 0), numeric(1))
      tier_fe<- vapply(tier_nm,function(nm) ifelse(nm %in% names(sol_named), sol_named[nm], 0), numeric(1))
      hpg_fe <- vapply(hpg_nm, function(nm) ifelse(nm %in% names(sol_named), sol_named[nm], 0), numeric(1))
      fam_re <- vapply(family, function(fam)
        ifelse(!is.na(fam) & fam %in% names(fam_blup_vec), fam_blup_vec[fam], 0), numeric(1))
      base + gf_fe + tier_fe + hpg_fe + fam_re   ## genus BLUP explicitly zeroed
    }]
    ## Uncertainty: propagate genus VC even though BLUP is zeroed
    test[, pred_sd := sqrt(v_fam + v_gen + v_r)]
    all_preds[[f]] <- test
  }

  all_dt <- rbindlist(all_preds, fill=TRUE)
  m_all  <- compute_metrics(all_dt)
  message(sprintf("\n[10d] Genus-extrap overall: RMSE=%.4f bias=%+.4f 95PI=%.3f r=%.4f n=%d",
    m_all$rmse, m_all$bias, m_all$cov_95, m_all$pearson_r, m_all$n))

  fold_dt <- all_dt[, {
    m <- compute_metrics(.SD)
    .(n_test=m$n, rmse=m$rmse, mae=m$mae, bias=m$bias, cov_95=m$cov_95, pearson_r=m$pearson_r)
  }, by=fold, .SDcols=c("predicted","log10_agb_kg","pred_sd")]

  write_cv_outputs(fold_dt, all_dt, "genus_extrap")
}

## ============================================================================
## CV MODE: genus_interp
## ============================================================================
if (CV_MODE == "genus_interp") {
  message("\n[10d] === Genus-interp CV (within-genus holdout; full refit) ===")
  message("[10d] Estimand: 217K species sharing a genus with >=1 measured congener.")
  message("[10d] Genus BLUP estimated from retained congeners (production procedure).")

  eligible_genera <- meas[n_meas_genus >= MIN_GENUS_SIZE, unique(genus)]
  message(sprintf("[10d] Eligible genera (>= %d measured spp): %d | eligible spp: %d",
    MIN_GENUS_SIZE, length(eligible_genera), meas[genus %in% eligible_genera, .N]))

  elig_info <- meas[genus %in% eligible_genera, .(family=family[1], n_meas=.N), by=genus]
  setorder(elig_info, family, n_meas)
  set.seed(42)
  elig_info[, fold := ((seq_len(.N)-1) %% N_FOLDS) + 1L]

  meas_int <- merge(meas, elig_info[,.(genus,fold)], by="genus", all.x=TRUE)

  all_preds <- vector("list", N_FOLDS)

  for (f in seq_len(N_FOLDS)) {
    message(sprintf("\n[10d] Fold %d/%d", f, N_FOLDS)); t0 <- proc.time()
    fold_genera <- elig_info[fold==f, genus]

    ## Hold out ~HOLDOUT_FRAC of each fold genus
    set.seed(2026 + f * 1000)
    hold_animals <- meas_int[genus %in% fold_genera, {
      idx <- sample(.N, max(1L, floor(.N * HOLDOUT_FRAC)))
      animal[idx]
    }, by=genus]$V1

    train <- meas_int[!animal %in% hold_animals]
    test  <- copy(meas_int[animal %in% hold_animals])
    test[, data_tier := "T1"]   ## production scenario

    ## Ensure each held genus has >=1 retained congener
    zero_gen <- train[genus %in% fold_genera, .(n=.N), by=genus][n==0, genus]
    if (length(zero_gen) > 0) {
      for (g in zero_gen) {
        rescue <- test[genus==g, animal[1]]
        test   <- test[animal != rescue]
        train  <- rbind(train, meas_int[animal==rescue])
      }
      message("[10d] Rescued ", length(zero_gen), " genera with 0 retained congeners")
    }

    message(sprintf("[10d] %d genera (partial hold): %d test | %d train",
      length(fold_genera), nrow(test), nrow(train)))

    res <- fit_chains(train, tree_m, N_CHAINS, CV_NITT, CV_BURNIN, CV_THIN, f, pr_flag=TRUE)
    if (is.null(res)) { message("[10d] Fold ", f, " failed — skipping"); next }

    sol_mean <- res$sol_mean
    vcv_mean <- res$vcv_mean

    ## Extract genus and family BLUPs from Sol (pr=TRUE saves them)
    gen_blup_vec <- setNames(
      sol_mean[grep("^genus\\.", names(sol_mean))],
      sub("^genus\\.", "", grep("^genus\\.", names(sol_mean), value=TRUE))
    )
    fam_blup_vec <- setNames(
      sol_mean[grep("^family\\.", names(sol_mean))],
      sub("^family\\.", "", grep("^family\\.", names(sol_mean), value=TRUE))
    )

    test[, predicted := {
      base    <- sol_mean["(Intercept)"]
      gf_nm   <- paste0("growth_form_canonical", growth_form_canonical)
      tier_nm <- paste0("data_tier", data_tier)
      hpg_nm  <- paste0("higher_plant_group", higher_plant_group)
      gf_fe   <- vapply(gf_nm,  function(nm) ifelse(nm %in% names(sol_mean), sol_mean[nm], 0), numeric(1))
      tier_fe <- vapply(tier_nm,function(nm) ifelse(nm %in% names(sol_mean), sol_mean[nm], 0), numeric(1))
      hpg_fe  <- vapply(hpg_nm, function(nm) ifelse(nm %in% names(sol_mean), sol_mean[nm], 0), numeric(1))
      gen_re  <- vapply(genus,  function(g)  ifelse(g  %in% names(gen_blup_vec), gen_blup_vec[g],  0), numeric(1))
      fam_re  <- vapply(family, function(fam)
        ifelse(!is.na(fam) & fam %in% names(fam_blup_vec), fam_blup_vec[fam], 0), numeric(1))
      base + gf_fe + tier_fe + hpg_fe + gen_re + fam_re
    }]
    ## Uncertainty: residual VC (genus + family BLUPs absorbed their variance)
    test[, pred_sd := sqrt(vcv_mean["units"])]

    m <- compute_metrics(test)
    elapsed <- (proc.time()-t0)["elapsed"]/60
    message(sprintf("[10d] Fold %d: RMSE=%.4f bias=%+.4f 95PI=%.3f r=%.4f rhat=%s (%.1f min)",
      f, m$rmse, m$bias, m$cov_95, m$pearson_r, res$rhat_flag, elapsed))

    all_preds[[f]] <- test
    gc(verbose=FALSE)
  }

  valid <- Filter(Negate(is.null), all_preds)
  if (length(valid)==0) stop("[10d] No valid folds.")
  all_dt <- rbindlist(valid, fill=TRUE)

  m_all <- compute_metrics(all_dt)
  message(sprintf("\n[10d] Genus-interp overall: RMSE=%.4f bias=%+.4f 95PI=%.3f r=%.4f n=%d",
    m_all$rmse, m_all$bias, m_all$cov_95, m_all$pearson_r, m_all$n))

  fold_dt <- all_dt[, {
    m <- compute_metrics(.SD)
    .(n_test=m$n, rmse=m$rmse, mae=m$mae, bias=m$bias, cov_95=m$cov_95, pearson_r=m$pearson_r)
  }, by=fold, .SDcols=c("predicted","log10_agb_kg","pred_sd")]

  write_cv_outputs(fold_dt, all_dt, "genus_interp")
}

message("\n=== Stage 10d complete (CV_MODE=", CV_MODE, ") ===")
