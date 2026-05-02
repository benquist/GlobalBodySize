# scripts/06_pgls_allometry.R
# Core allometric scaling analysis: OLS, SMA, and PGLS regressions
# across Niklas-Enquist and BAAD datasets against Smith & Brown (2018) phylogeny.

library(caper)
library(ape)
library(dplyr)
library(ggplot2)
library(smatr)
library(phytools)
library(tibble)
library(readr)
library(tidyr)

proj_dir <- normalizePath(".")

dir.create(file.path(proj_dir, "output"), showWarnings = FALSE, recursive = TRUE)

# ── SECTION A: Load data ──────────────────────────────────────────────────────

ne_species_means   <- readRDS(file.path(proj_dir, "data/processed/ne_species_means.rds"))
baad_species_means <- readRDS(file.path(proj_dir, "data/processed/baad_species_means.rds"))
pruned_tree        <- readRDS(file.path(proj_dir, "data/processed/pgls_tree_smith2018_s2.rds"))

cat("Tree tips:", ape::Ntip(pruned_tree), "\n")

# ── SECTION B: Match data to tree ────────────────────────────────────────────
# V.PhyloMaker2 produces tip labels with underscores (Genus_species).
# Add an underscore version of each species name for matching.

ne_species_means  <- ne_species_means  |> dplyr::mutate(taxa_tree  = gsub(" ", "_", taxa))
baad_species_means <- baad_species_means |> dplyr::mutate(sp_tree = gsub(" ", "_", speciesMatched))

ne_in_tree      <- ne_species_means[ne_species_means$taxa_tree %in% pruned_tree$tip.label, ]
ne_tree_pruned  <- ape::keep.tip(pruned_tree, ne_in_tree$taxa_tree)
cat("NE species in tree:", nrow(ne_in_tree), "\n")

baad_in_tree     <- baad_species_means[baad_species_means$sp_tree %in% pruned_tree$tip.label, ]
baad_tree_pruned <- ape::keep.tip(pruned_tree, baad_in_tree$sp_tree)
cat("BAAD species in tree:", nrow(baad_in_tree), "\n")

# ── SECTION C: Caper comparative.data objects ─────────────────────────────────
# caper requires the names.col values to exactly match tree tip labels.
# Use underscore-format name columns as the matching key.

ne_df         <- as.data.frame(ne_in_tree)
rownames(ne_df) <- ne_df$taxa_tree
# Clear node labels to avoid "Labels duplicated between tips and nodes" error
ne_tree_pruned$node.label <- NULL
cd_ne <- caper::comparative.data(phy = ne_tree_pruned, data = ne_df,
                                  names.col = "taxa_tree", vcv = TRUE, warn.dropped = FALSE)

baad_df         <- as.data.frame(baad_in_tree)
rownames(baad_df) <- baad_df$sp_tree
baad_tree_pruned$node.label <- NULL
cd_baad <- caper::comparative.data(phy = baad_tree_pruned, data = baad_df,
                                    names.col = "sp_tree", vcv = TRUE, warn.dropped = FALSE)

# ── SECTION D: Helper — run OLS, SMA, PGLS ───────────────────────────────────

run_scaling <- function(cd, y_col, x_col, dataset_label, wbe_slope = NA_real_) {
  dat <- cd$data
  y   <- dat[[y_col]]; x <- dat[[x_col]]
  ok  <- is.finite(y) & is.finite(x)
  if (sum(ok) < 10) return(NULL)
  y <- y[ok]; x <- x[ok]
  dat_ok <- dat[ok, ]
  n  <- length(y)

  # OLS
  ols_fit  <- lm(y ~ x)
  ols_s    <- summary(ols_fit)
  ols_slope <- coef(ols_fit)[2]
  ols_se    <- coef(ols_s)[2, 2]
  ols_ci    <- confint(ols_fit)[2, ]
  ols_r2    <- ols_s$r.squared
  ols_pval_wbe <- if (!is.na(wbe_slope)) {
    2 * pt(abs((ols_slope - wbe_slope) / ols_se), df = n - 2, lower.tail = FALSE)
  } else NA_real_

  # SMA
  sma_formula <- as.formula(paste(y_col, "~", x_col))
  sma_fit <- tryCatch(smatr::sma(sma_formula, data = dat_ok), error = function(e) NULL)
  if (!is.null(sma_fit)) {
    sma_slope  <- sma_fit$coef[[1]][2, 1]
    sma_ci_lo  <- sma_fit$coef[[1]][2, 2]
    sma_ci_hi  <- sma_fit$coef[[1]][2, 3]
    sma_r2     <- sma_fit$r2[[1]]
  } else {
    sma_slope <- sma_ci_lo <- sma_ci_hi <- sma_r2 <- NA_real_
  }
  sma_pval_wbe <- if (!is.na(wbe_slope) && !is.null(sma_fit)) {
    tryCatch(smatr::slope.test(sma_fit, test.value = wbe_slope)$p[[1]], error = function(e) NA_real_)
  } else NA_real_

  # PGLS
  pgls_formula <- as.formula(paste(y_col, "~", x_col))
  pgls_fit <- tryCatch(
    caper::pgls(pgls_formula, data = cd, lambda = "ML",
                bounds = list(lambda = c(1e-6, 1))),
    error = function(e) {
      message("PGLS ML failed for ", dataset_label, " ", y_col, "~", x_col,
              ": ", conditionMessage(e), " — trying lambda=1")
      tryCatch(caper::pgls(pgls_formula, data = cd, lambda = 1), error = function(e2) NULL)
    }
  )
  if (!is.null(pgls_fit)) {
    pgls_s    <- summary(pgls_fit)
    pgls_n    <- nrow(pgls_fit$residuals)   # actual PGLS sample size (may differ from OLS n)
    pgls_slope <- coef(pgls_fit)[2]
    pgls_se    <- coef(pgls_s)[2, 2]
    # Use t-distribution CI with actual PGLS df, not 1.96 (normal approximation)
    t_crit     <- qt(0.975, df = pgls_n - 2)
    pgls_ci    <- c(pgls_slope - t_crit * pgls_se, pgls_slope + t_crit * pgls_se)
    pgls_r2    <- pgls_s$r.squared
    pgls_lambda <- pgls_fit$param["lambda"]
    # Lambda CI via profile likelihood
    pgls_lambda_ci <- tryCatch({
      prof <- caper::pgls.profile(pgls_fit, which.param = "lambda")
      ci   <- caper::pgls.confint(prof, interval = 0.95)$ci.val
      ci
    }, error = function(e) c(NA_real_, NA_real_))
    pgls_pval_wbe <- if (!is.na(wbe_slope)) {
      2 * pt(abs((pgls_slope - wbe_slope) / pgls_se), df = pgls_n - 2, lower.tail = FALSE)
    } else NA_real_
  } else {
    pgls_n <- NA_integer_
    pgls_slope <- pgls_se <- pgls_r2 <- pgls_lambda <- pgls_pval_wbe <- NA_real_
    pgls_ci <- c(NA_real_, NA_real_)
    pgls_lambda_ci <- c(NA_real_, NA_real_)
  }

  tibble(
    dataset          = dataset_label,
    y_var            = y_col,
    x_var            = x_col,
    wbe_slope        = wbe_slope,
    n_species_ols    = n,
    n_species_pgls   = c(NA_integer_, NA_integer_, pgls_n),
    method           = c("OLS", "SMA", "PGLS"),
    slope            = c(ols_slope, sma_slope, pgls_slope),
    slope_se         = c(ols_se, NA_real_, pgls_se),
    ci_lower         = c(ols_ci[1], sma_ci_lo, pgls_ci[1]),
    ci_upper         = c(ols_ci[2], sma_ci_hi, pgls_ci[2]),
    r_squared        = c(ols_r2, sma_r2, pgls_r2),
    lambda           = c(NA_real_, NA_real_, pgls_lambda),
    lambda_ci_lo     = c(NA_real_, NA_real_, pgls_lambda_ci[1]),
    lambda_ci_hi     = c(NA_real_, NA_real_, pgls_lambda_ci[2]),
    p_vs_wbe         = c(ols_pval_wbe, sma_pval_wbe, pgls_pval_wbe)
  )
}

# ── SECTION E: Run scaling relationships ─────────────────────────────────────

ne_bm_ht  <- run_scaling(cd_ne, "log_total_biomass_kg",  "log_height_m",        "Niklas-Enquist", wbe_slope = 8/3)
ne_gr_bm  <- run_scaling(cd_ne, "log_total_growth_kgyr", "log_total_biomass_kg","Niklas-Enquist", wbe_slope = 0.75)
ne_lf_bm  <- run_scaling(cd_ne, "log_leaf_biomass_kg",   "log_total_biomass_kg","Niklas-Enquist", wbe_slope = 0.75)
ne_st_bm  <- run_scaling(cd_ne, "log_stem_biomass_kg",   "log_total_biomass_kg","Niklas-Enquist", wbe_slope = 1.0)

baad_agb_dbh <- run_scaling(cd_baad, "log_AGB_kg",    "log_DBH_cm", "BAAD", wbe_slope = NA_real_)
baad_ht_dbh  <- run_scaling(cd_baad, "log_height_m",  "log_DBH_cm", "BAAD", wbe_slope = 2/3)

results_table <- bind_rows(ne_bm_ht, ne_gr_bm, ne_lf_bm, ne_st_bm, baad_agb_dbh, baad_ht_dbh)

# ── SECTION F: Phylogenetic signal ───────────────────────────────────────────

ne_traits <- c("log_height_m", "log_total_biomass_kg", "log_total_growth_kgyr",
               "log_leaf_biomass_kg", "log_stem_biomass_kg")

phylosig_rows <- lapply(ne_traits, function(tr) {
  vals <- setNames(ne_in_tree[[tr]], ne_in_tree$taxa_tree)
  vals <- vals[is.finite(vals)]
  sp_tree <- ape::keep.tip(ne_tree_pruned, names(vals))

  lam_res <- tryCatch(
    phytools::phylosig(sp_tree, vals, method = "lambda", test = TRUE),
    error = function(e) { message("phylosig lambda failed for ", tr, ": ", conditionMessage(e)); NULL }
  )
  k_res <- tryCatch(
    phytools::phylosig(sp_tree, vals, method = "K", test = TRUE),
    error = function(e) { message("phylosig K failed for ", tr, ": ", conditionMessage(e)); NULL }
  )

  tibble(
    trait       = tr,
    lambda      = if (!is.null(lam_res)) lam_res$lambda    else NA_real_,
    lambda_pval = if (!is.null(lam_res)) lam_res$P         else NA_real_,
    K           = if (!is.null(k_res))   k_res$K           else NA_real_,
    K_pval      = if (!is.null(k_res))   k_res$P           else NA_real_,
    n_species   = length(vals)
  )
})

phylosig_table <- bind_rows(phylosig_rows)

# ── SECTION G: Plots ──────────────────────────────────────────────────────────

results_table <- results_table |>
  mutate(relationship = paste0(y_var, " ~ ", x_var))

p_forest <- ggplot(results_table |> filter(!is.na(slope)),
                   aes(x = slope, y = relationship, color = method, shape = method)) +
  geom_point(position = position_dodge(width = 0.4), size = 3) +
  geom_errorbarh(aes(xmin = ci_lower, xmax = ci_upper),
                 position = position_dodge(width = 0.4), height = 0.2) +
  # Draw WBE prediction lines once per relationship (not 3x per method)
  geom_vline(data = results_table |> dplyr::distinct(dataset, relationship, wbe_slope) |> dplyr::filter(!is.na(wbe_slope)),
             aes(xintercept = wbe_slope), linetype = "dashed", color = "gray40") +
  facet_wrap(~dataset, scales = "free") +
  scale_color_manual(values = c("OLS" = "steelblue", "SMA" = "darkorange", "PGLS" = "forestgreen")) +
  labs(x = "Scaling exponent (slope in log-log)", y = NULL,
       title = "Allometric scaling exponents: OLS vs SMA vs PGLS",
       subtitle = "Dashed line = WBE theoretical prediction") +
  theme_bw(base_size = 12)

ggsave(file.path(proj_dir, "output/forest_plot_slopes.png"), p_forest, width = 12, height = 7, dpi = 150)

ne_plot_dat <- ne_in_tree |> filter(is.finite(log_height_m) & is.finite(log_total_biomass_kg))

p_scatter_ne <- ggplot(ne_plot_dat, aes(x = log_height_m, y = log_total_biomass_kg)) +
  geom_point(alpha = 0.5, size = 1.5) +
  geom_smooth(method = "lm", se = TRUE, color = "steelblue", linetype = "solid") +
  labs(x = "log10(Height [m])", y = "log10(Total biomass [kg])",
       title = "Niklas-Enquist: Biomass ~ Height (species means)",
       subtitle = "Blue = OLS") +
  theme_bw(base_size = 12)

ggsave(file.path(proj_dir, "output/scatter_ne_biomass_height.png"), p_scatter_ne, width = 8, height = 6, dpi = 150)

# ── SECTION H: Save outputs ───────────────────────────────────────────────────

saveRDS(results_table,  file.path(proj_dir, "data/processed/pgls_results_table.rds"))
write_csv(results_table, file.path(proj_dir, "data/processed/pgls_results_table.csv"))

saveRDS(phylosig_table,  file.path(proj_dir, "data/processed/phylosig_table.rds"))
write_csv(phylosig_table, file.path(proj_dir, "data/processed/phylosig_table.csv"))

cat("Done. Results saved to data/processed/\n")
print(results_table)
