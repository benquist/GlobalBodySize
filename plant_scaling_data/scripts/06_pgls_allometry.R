# scripts/06_pgls_allometry.R
# ─────────────────────────────────────────────────────────────────────────────
# PURPOSE:  Step 6 of 6. Core allometric scaling analysis. Fits OLS, SMA, and
#           PGLS regressions for multiple allometric relationships in both the
#           Niklas-Enquist and BAAD datasets. Tests estimated slopes against
#           theoretical WBE / MST predictions. Quantifies phylogenetic signal
#           (Pagel's lambda, Blomberg's K) in each trait. Produces a forest
#           plot comparing methods and a scatter plot for the key biomass ~
#           height relationship.
#
# INPUTS:   data/processed/ne_species_means.rds
#           data/processed/baad_species_means.rds
#           data/processed/pgls_tree_smith2018_s2.rds
#
# OUTPUTS:  data/processed/pgls_results_table.rds / .csv
#           data/processed/phylosig_table.rds / .csv
#           output/forest_plot_slopes.png
#           output/scatter_ne_biomass_height.png
#
# KEY CONCEPTS:
#   * OLS (Ordinary Least Squares): minimises squared residuals in Y only.
#     Appropriate when Y has error and X is measured without error. In allometry
#     both variables carry error, so OLS systematically underestimates the true
#     slope (attenuation bias). It is included here for comparison and because
#     it is the most commonly reported regression in the literature.
#
#   * SMA (Standardised/Reduced Major Axis): minimises perpendicular distances
#     to the line, treating X and Y symmetrically. Appropriate when both
#     variables carry proportional measurement error -- the standard assumption
#     in allometric scaling. SMA slope = OLS slope / sqrt(R2). The smatr
#     package (Warton et al. 2012 Methods Ecol Evol) provides the SMA fit and
#     a formal test of whether the slope equals a specified value (slope.test).
#
#   * PGLS (Phylogenetic Generalised Least Squares): OLS on phylogenetically
#     transformed data. The covariance structure of residuals is modelled as
#     proportional to the phylogenetic variance-covariance matrix, scaled by
#     Pagel's lambda. lambda = "ML" lets the data determine the degree of
#     phylogenetic correction:
#       - lambda approx 1: strong phylogenetic signal (Brownian motion); full
#         phylogenetic correction applied.
#       - lambda approx 0: residuals are phylogenetically independent; PGLS
#         converges on OLS.
#     Implemented via caper::pgls() (Orme et al. 2013).
#
#   * WBE / MST theoretical predictions (dashed line in forest plot):
#       - Total biomass ~ Height^(8/3) approx 2.667  [West et al. 1997, 1999]
#       - Growth rate ~ Total biomass^(3/4) = 0.75   [metabolic scaling]
#       - Leaf biomass ~ Total biomass^(3/4) = 0.75  [pipe model]
#       - Stem biomass ~ Total biomass^1.0 = 1.0     [isometric trunk]
#       - Height ~ DBH^(2/3) approx 0.667            [pipe model constraint]
#     p_vs_wbe tests whether the estimated slope is significantly different
#     from the theoretical value using a two-tailed t-test.
#
#   * Phylogenetic signal metrics (Section F):
#       - Pagel's lambda: estimated within each PGLS model (see above).
#       - Blomberg's K (phytools::phylosig, method = "K"): K = 1 indicates
#         Brownian motion evolution; K < 1 = weaker-than-Brownian signal;
#         K > 1 = stronger conservatism than Brownian motion.
#     Both metrics are computed per-trait on Niklas-Enquist data, which spans
#     a broader taxonomic range than BAAD.
# ─────────────────────────────────────────────────────────────────────────────

library(caper)    # PGLS via comparative.data() and pgls()
library(ape)      # tree manipulation: keep.tip(), Ntip(), is.ultrametric()
library(dplyr)    # data wrangling
library(ggplot2)  # forest plots and scatter plots
library(smatr)    # SMA regression: sma(), slope.test()
library(phytools) # phylogenetic signal: phylosig(); force.ultrametric()
library(tibble)   # tibble() for row assembly in run_scaling()
library(readr)    # write_csv()
library(tidyr)    # available for reshaping if needed

# proj_dir: resolves to an absolute path, making file references portable
# when the script is run from different working directories (e.g. via Rscript).
proj_dir <- normalizePath(".")

dir.create(file.path(proj_dir, "output"), showWarnings = FALSE, recursive = TRUE)

# ── SECTION A: Load data ──────────────────────────────────────────────────────
# All three inputs were produced by scripts 04 and 05. Loading from RDS rather
# than re-computing ensures that species means and the phylogeny are consistent
# with what was validated in previous steps.
ne_species_means   <- readRDS(file.path(proj_dir, "data/processed/ne_species_means.rds"))
baad_species_means <- readRDS(file.path(proj_dir, "data/processed/baad_species_means.rds"))
pruned_tree        <- readRDS(file.path(proj_dir, "data/processed/pgls_tree_smith2018_s2.rds"))

cat("Tree tips:", ape::Ntip(pruned_tree), "\n")

# ── SECTION B: Match data to tree ────────────────────────────────────────────
# V.PhyloMaker2 produces tip labels with underscores (Genus_species), whereas
# the species means tables use space-separated names (Genus species).
# A new column storing the underscore version is added to each data frame so
# that row-to-tip matching is explicit and auditable.

ne_species_means   <- ne_species_means   |> dplyr::mutate(taxa_tree = gsub(" ", "_", taxa))
baad_species_means <- baad_species_means |> dplyr::mutate(sp_tree   = gsub(" ", "_", speciesMatched))

# Subset each dataset to species present in the tree.
# Species not in the tree cannot be included in PGLS; they are silently dropped
# here. The match table from script 05 (pgls_tree_match_table.csv) identifies
# which species were dropped and why (missing genus or family from backbone).
ne_in_tree     <- ne_species_means[ne_species_means$taxa_tree %in% pruned_tree$tip.label, ]
ne_tree_pruned <- ape::keep.tip(pruned_tree, ne_in_tree$taxa_tree)
cat("NE species in tree:", nrow(ne_in_tree), "\n")

baad_in_tree     <- baad_species_means[baad_species_means$sp_tree %in% pruned_tree$tip.label, ]
baad_tree_pruned <- ape::keep.tip(pruned_tree, baad_in_tree$sp_tree)
cat("BAAD species in tree:", nrow(baad_in_tree), "\n")

# ── SECTION C: Caper comparative.data objects ─────────────────────────────────
# caper::comparative.data() links a data frame to a phylogenetic tree.
# Requirements:
#   1. names.col must be a column whose values exactly match tree tip labels.
#      We use the underscore-format columns added in Section B.
#   2. rownames(df) must also match tip labels (caper uses both).
#   3. node.label must be NULL or empty -- if node labels duplicate tip labels,
#      caper throws a "Labels duplicated between tips and nodes" error.
#   4. vcv = TRUE pre-computes the phylogenetic variance-covariance matrix,
#      which is required for PGLS but can be slow for large trees (>5000 tips).

ne_df           <- as.data.frame(ne_in_tree)
rownames(ne_df) <- ne_df$taxa_tree
ne_tree_pruned$node.label <- NULL  # prevent label duplication error in caper
cd_ne <- caper::comparative.data(phy      = ne_tree_pruned,
                                  data     = ne_df,
                                  names.col = "taxa_tree",
                                  vcv      = TRUE,
                                  warn.dropped = FALSE)

baad_df           <- as.data.frame(baad_in_tree)
rownames(baad_df) <- baad_df$sp_tree
baad_tree_pruned$node.label <- NULL
cd_baad <- caper::comparative.data(phy      = baad_tree_pruned,
                                    data     = baad_df,
                                    names.col = "sp_tree",
                                    vcv      = TRUE,
                                    warn.dropped = FALSE)

# ── SECTION D: Helper -- run OLS, SMA, PGLS ───────────────────────────────────
# run_scaling() fits all three regression methods for one y ~ x pair within one
# dataset and returns a tidy tibble of results. Using a helper function keeps
# the call site (Section E) concise and ensures consistent output structure
# across all relationships.
#
# Arguments:
#   cd            -- caper comparative.data object (contains tree + data)
#   y_col, x_col  -- column names of the response and predictor (log10 scale)
#   dataset_label -- string label for output table (e.g. "Niklas-Enquist")
#   wbe_slope     -- theoretical WBE/MST slope to test against (or NA_real_)
#
# Returns NULL if fewer than 10 complete pairs are available (too few for
# meaningful regression). This guards against attempting regression on a
# trait column that is nearly entirely missing.

run_scaling <- function(cd, y_col, x_col, dataset_label, wbe_slope = NA_real_) {
  dat <- cd$data
  y   <- dat[[y_col]]; x <- dat[[x_col]]
  ok  <- is.finite(y) & is.finite(x)     # exclude NA, NaN, Inf from both vars
  if (sum(ok) < 10) return(NULL)         # minimum n guard
  y      <- y[ok]; x <- x[ok]
  dat_ok <- dat[ok, ]
  n      <- length(y)

  # ── OLS ─────────────────────────────────────────────────────────────────────
  # Standard linear regression of y on x. In log-log space, the slope is the
  # allometric exponent. OLS is biased low (attenuation bias) when x also has
  # measurement error, so OLS slopes are expected to be lower than SMA slopes.
  # p_vs_wbe: two-tailed t-test of H0: slope = wbe_slope.
  ols_fit      <- lm(y ~ x)
  ols_s        <- summary(ols_fit)
  ols_slope    <- coef(ols_fit)[2]
  ols_se       <- coef(ols_s)[2, 2]
  ols_ci       <- confint(ols_fit)[2, ]
  ols_r2       <- ols_s$r.squared
  ols_pval_wbe <- if (!is.na(wbe_slope)) {
    2 * pt(abs((ols_slope - wbe_slope) / ols_se), df = n - 2, lower.tail = FALSE)
  } else NA_real_

  # ── SMA ─────────────────────────────────────────────────────────────────────
  # Standardised Major Axis regression via smatr::sma().
  # SMA treats both axes symmetrically: it minimises the sum of areas of right
  # triangles formed by each point and the fitted line. This is the recommended
  # method for allometric scaling when both variables carry proportional error
  # (Warton et al. 2006 Biol Rev; Warton et al. 2012 Methods Ecol Evol).
  # SMA slope = OLS slope / sqrt(R2): always >= OLS slope for the same data.
  # slope.test() performs a one-sample test of SMA slope against wbe_slope.
  sma_formula  <- as.formula(paste(y_col, "~", x_col))
  sma_fit      <- tryCatch(smatr::sma(sma_formula, data = dat_ok), error = function(e) NULL)
  if (!is.null(sma_fit)) {
    sma_slope  <- sma_fit$coef[[1]][2, 1]  # row 2 = slope (row 1 = intercept)
    sma_ci_lo  <- sma_fit$coef[[1]][2, 2]  # lower 95% CI for slope
    sma_ci_hi  <- sma_fit$coef[[1]][2, 3]  # upper 95% CI for slope
    sma_r2     <- sma_fit$r2[[1]]
  } else {
    sma_slope  <- sma_ci_lo <- sma_ci_hi <- sma_r2 <- NA_real_
  }
  sma_pval_wbe <- if (!is.na(wbe_slope) && !is.null(sma_fit)) {
    tryCatch(smatr::slope.test(sma_fit, test.value = wbe_slope)$p[[1]], error = function(e) NA_real_)
  } else NA_real_

  # ── PGLS ────────────────────────────────────────────────────────────────────
  # Phylogenetic GLS via caper::pgls(). lambda = "ML" estimates the optimal
  # phylogenetic correction strength from the data using maximum likelihood.
  # Fall-back: if ML optimisation fails (can happen with small n or poorly
  # conditioned covariance matrices), retry with lambda = 1 (full Brownian
  # motion correction). If both fail, all PGLS outputs are set to NA.
  #
  # Caveat: caper::pgls() does not provide a vcov() method, so confidence
  # intervals are computed as Wald +/- 1.96 * SE. For large samples this is
  # adequate, but for small n (< 30) profile likelihood CIs are preferable.
  pgls_formula <- as.formula(paste(y_col, "~", x_col))
  pgls_fit <- tryCatch(
    caper::pgls(pgls_formula, data = cd, lambda = "ML"),
    error = function(e) {
      message("PGLS ML failed for ", dataset_label, " ", y_col, "~", x_col,
              ": ", conditionMessage(e), " -- trying lambda=1")
      tryCatch(caper::pgls(pgls_formula, data = cd, lambda = 1), error = function(e2) NULL)
    }
  )
  if (!is.null(pgls_fit)) {
    pgls_s        <- summary(pgls_fit)
    pgls_slope    <- coef(pgls_fit)[2]
    pgls_se       <- coef(pgls_s)[2, 2]
    # Wald 95% CI: slope +/- 1.96 * SE (approximate; see caveat above)
    pgls_ci       <- c(pgls_slope - 1.96 * pgls_se, pgls_slope + 1.96 * pgls_se)
    pgls_r2       <- pgls_s$r.squared
    pgls_lambda   <- pgls_fit$param["lambda"]  # ML-estimated lambda for this relationship
    pgls_pval_wbe <- if (!is.na(wbe_slope)) {
      2 * pt(abs((pgls_slope - wbe_slope) / pgls_se), df = n - 2, lower.tail = FALSE)
    } else NA_real_
  } else {
    pgls_slope <- pgls_se <- pgls_r2 <- pgls_lambda <- pgls_pval_wbe <- NA_real_
    pgls_ci    <- c(NA_real_, NA_real_)
  }

  # ── Assemble output row ──────────────────────────────────────────────────────
  # One row per method (OLS / SMA / PGLS). The wbe_slope column records the
  # theoretical prediction so the forest plot can draw the reference line
  # automatically without hard-coding values outside this function.
  tibble(
    dataset   = dataset_label,
    y_var     = y_col,
    x_var     = x_col,
    wbe_slope = wbe_slope,       # theoretical reference slope (NA if none)
    n_species = n,               # number of species with complete x and y
    method    = c("OLS", "SMA", "PGLS"),
    slope     = c(ols_slope,  sma_slope,  pgls_slope),
    slope_se  = c(ols_se,     NA_real_,   pgls_se),   # SMA SE not applicable
    ci_lower  = c(ols_ci[1],  sma_ci_lo,  pgls_ci[1]),
    ci_upper  = c(ols_ci[2],  sma_ci_hi,  pgls_ci[2]),
    r_squared = c(ols_r2,     sma_r2,     pgls_r2),
    lambda    = c(NA_real_,   NA_real_,   pgls_lambda), # lambda meaningful only for PGLS
    p_vs_wbe  = c(ols_pval_wbe, sma_pval_wbe, pgls_pval_wbe)
  )
}

# ── SECTION E: Run scaling relationships ─────────────────────────────────────
# Each call to run_scaling() specifies one allometric relationship and the
# WBE/MST theoretical slope to test against. See the header for the biological
# meaning of each exponent.

# Niklas-Enquist: Total biomass ~ Height
# WBE predicts AGB ~ H^(8/3) approx 2.667 under fractal vascular geometry
# combined with isometric trunk cross-section (West et al. 1999 Science).
ne_bm_ht  <- run_scaling(cd_ne, "log_total_biomass_kg",  "log_height_m",
                          "Niklas-Enquist", wbe_slope = 8/3)

# Niklas-Enquist: Growth rate ~ Total biomass
# MST predicts metabolic rate (approx growth) ~ M^(3/4) (West et al. 1997).
# This is the quarter-power scaling prediction central to metabolic theory.
ne_gr_bm  <- run_scaling(cd_ne, "log_total_growth_kgyr", "log_total_biomass_kg",
                          "Niklas-Enquist", wbe_slope = 0.75)

# Niklas-Enquist: Leaf biomass ~ Total biomass
# Pipe model (Shinozaki et al. 1964) predicts leaf area proportional to
# conducting sapwood area, which under WBE also scales as M^(3/4). Tests
# organ-level resource allocation theory.
ne_lf_bm  <- run_scaling(cd_ne, "log_leaf_biomass_kg",   "log_total_biomass_kg",
                          "Niklas-Enquist", wbe_slope = 0.75)

# Niklas-Enquist: Stem biomass ~ Total biomass
# Under isometric scaling, stem should scale as M^1 (constant fraction of
# total biomass). Departures from slope = 1 indicate size-dependent allocation
# to structural support (e.g. wood investment increases with tree size).
ne_st_bm  <- run_scaling(cd_ne, "log_stem_biomass_kg",   "log_total_biomass_kg",
                          "Niklas-Enquist", wbe_slope = 1.0)

# BAAD: AGB ~ DBH
# No WBE slope specified because AGB ~ DBH^b combines H~DBH scaling with the
# biomass-height relationship, and the compound exponent varies with species
# and stand conditions. Fitted slopes can be compared against local allometric
# equations (e.g. Chave et al. 2005 Oecologia for tropical forests).
baad_agb_dbh <- run_scaling(cd_baad, "log_AGB_kg",   "log_DBH_cm",
                             "BAAD", wbe_slope = NA_real_)

# BAAD: Height ~ DBH
# WBE / pipe model predicts H ~ DBH^(2/3) approx 0.667.
# Chave et al. (2005) report a global empirical exponent of ~0.65, suggesting
# mild deviation from the geometric prediction.
baad_ht_dbh  <- run_scaling(cd_baad, "log_height_m", "log_DBH_cm",
                             "BAAD", wbe_slope = 2/3)

# Combine all relationships into a single results table for export and plotting.
results_table <- bind_rows(ne_bm_ht, ne_gr_bm, ne_lf_bm, ne_st_bm, baad_agb_dbh, baad_ht_dbh)

# ── SECTION F: Phylogenetic signal ───────────────────────────────────────────
# Quantify the degree of phylogenetic signal in each trait across the
# Niklas-Enquist dataset (broader taxon sampling than BAAD).
# Two complementary metrics are computed:
#   Pagel's lambda (phytools::phylosig, method = "lambda"):
#     Tested via likelihood ratio test. H0: lambda = 0 (no signal).
#     lambda_pval < 0.05 indicates significant phylogenetic signal.
#   Blomberg's K (phytools::phylosig, method = "K"):
#     K = 1 indicates Brownian motion evolution.
#     K < 1: weaker-than-expected signal; K > 1: stronger conservatism.
#     K_pval from randomisation test (default 1000 permutations).
# Traits with high lambda and K indicate that phylogenetic correction in PGLS
# is important; traits with low values suggest OLS and PGLS slopes will agree.

ne_traits <- c("log_height_m", "log_total_biomass_kg", "log_total_growth_kgyr",
               "log_leaf_biomass_kg", "log_stem_biomass_kg")

phylosig_rows <- lapply(ne_traits, function(tr) {
  # Extract trait values as a named numeric vector (names = tree tip labels).
  # Only finite values are retained; the tree is pruned to matching tips.
  # This pruning step is required because phylosig() expects complete data.
  vals    <- setNames(ne_in_tree[[tr]], ne_in_tree$taxa_tree)
  vals    <- vals[is.finite(vals)]
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
    lambda      = if (!is.null(lam_res)) lam_res$lambda else NA_real_,
    lambda_pval = if (!is.null(lam_res)) lam_res$P      else NA_real_,
    K           = if (!is.null(k_res))   k_res$K        else NA_real_,
    K_pval      = if (!is.null(k_res))   k_res$P        else NA_real_,
    n_species   = length(vals)
  )
})

phylosig_table <- bind_rows(phylosig_rows)

# ── SECTION G: Plots ──────────────────────────────────────────────────────────

# Add a human-readable relationship label for the y-axis of the forest plot.
results_table <- results_table |>
  mutate(relationship = paste0(y_var, " ~ ", x_var))

# Forest plot: allometric exponents (slopes) across methods and relationships.
# Each point = one regression method; horizontal bars = 95% CI.
# Dashed vertical line = WBE/MST theoretical prediction (from wbe_slope column).
# When the CI does not overlap the dashed line, the estimated slope differs
# significantly from the theoretical prediction for that method.
# Faceted by dataset to keep BAAD and Niklas-Enquist panels visually separate.
p_forest <- ggplot(results_table |> filter(!is.na(slope)),
                   aes(x = slope, y = relationship, color = method, shape = method)) +
  geom_point(position = position_dodge(width = 0.4), size = 3) +
  geom_errorbarh(aes(xmin = ci_lower, xmax = ci_upper),
                 position = position_dodge(width = 0.4), height = 0.2) +
  # na.rm = TRUE suppresses warnings for relationships where wbe_slope = NA.
  geom_vline(aes(xintercept = wbe_slope), linetype = "dashed", color = "gray40", na.rm = TRUE) +
  facet_wrap(~dataset, scales = "free") +
  scale_color_manual(values = c("OLS" = "steelblue", "SMA" = "darkorange", "PGLS" = "forestgreen")) +
  labs(x = "Scaling exponent (slope in log-log)", y = NULL,
       title = "Allometric scaling exponents: OLS vs SMA vs PGLS",
       subtitle = "Dashed line = WBE theoretical prediction") +
  theme_bw(base_size = 12)

ggsave(file.path(proj_dir, "output/forest_plot_slopes.png"), p_forest,
       width = 12, height = 7, dpi = 150)

# Scatter plot: Niklas-Enquist Biomass ~ Height (species means, log-log).
# Points represent species means; spread around the OLS line reflects both
# biological variance across taxa and measurement uncertainty across studies.
# This plot is diagnostic -- verifies that the data cloud is linear in
# log-log space before interpreting slope estimates.
ne_plot_dat <- ne_in_tree |> filter(is.finite(log_height_m) & is.finite(log_total_biomass_kg))

p_scatter_ne <- ggplot(ne_plot_dat, aes(x = log_height_m, y = log_total_biomass_kg)) +
  geom_point(alpha = 0.5, size = 1.5) +
  geom_smooth(method = "lm", se = TRUE, color = "steelblue", linetype = "solid") +
  labs(x = "log10(Height [m])", y = "log10(Total biomass [kg])",
       title = "Niklas-Enquist: Biomass ~ Height (species means)",
       subtitle = "Blue = OLS trend with 95% CI") +
  theme_bw(base_size = 12)

ggsave(file.path(proj_dir, "output/scatter_ne_biomass_height.png"), p_scatter_ne,
       width = 8, height = 6, dpi = 150)

# ── SECTION H: Save outputs ───────────────────────────────────────────────────
# Both RDS and CSV are written for the two main result tables.
# RDS: preserves numeric precision and column types for downstream R analyses.
# CSV: readable by reviewers; can be imported into supplementary tables.

saveRDS(results_table,   file.path(proj_dir, "data/processed/pgls_results_table.rds"))
write_csv(results_table, file.path(proj_dir, "data/processed/pgls_results_table.csv"))

saveRDS(phylosig_table,   file.path(proj_dir, "data/processed/phylosig_table.rds"))
write_csv(phylosig_table, file.path(proj_dir, "data/processed/phylosig_table.csv"))

cat("Done. Results saved to data/processed/\n")
# Print the full results table to the console for a quick sanity check.
# Key columns to inspect: slope (plausible given the theoretical exponent?),
# lambda (is PGLS providing meaningful correction?), p_vs_wbe (is the
# relationship significantly different from the WBE prediction?).
print(results_table)
