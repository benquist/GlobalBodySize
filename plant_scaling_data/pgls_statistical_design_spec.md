# PGLS Allometric Scaling Analysis — Statistical Design Specification

**Project:** Plant body mass scaling (Niklas-Enquist + BAAD)  
**Date:** 2026-05-02  
**Status:** Pre-implementation design spec  

---

## 1. Species-Mean Aggregation

### Arithmetic mean of log10 vs geometric mean of raw values

These are **algebraically equivalent**:

$$\bar{x}_{\log} = \frac{1}{n}\sum_{i=1}^n \log_{10}(x_i) = \log_{10}\!\left(\prod_{i=1}^n x_i\right)^{1/n} = \log_{10}(\bar{x}_{\text{geom}})$$

**Use arithmetic mean of log10-transformed values.** Rationale:

- Biological size variables are approximately lognormal; the geometric mean is the appropriate central tendency
- Averaging on the log scale is robust to outliers compared to raw-scale means
- Directly interpretable as the "typical log-trait value" for the species
- Consistent with how PGLS will use the data (all analyses are in log10 space)

### Weighting by N per species

**Recommendation: unweighted (equal weight per species).** Justification:

- The scientific unit of analysis is the *species*, not the individual — overrepresenting Pinus or Quercus (many herbarium records) would bias estimates
- Weighting by N implicitly assumes within-species variance is homogeneous, which is unlikely across a dataset spanning measurement methods and geography
- Warton et al. (2006) and Harvey & Pagel (1991) both note that cross-species comparative analyses should treat species as exchangeable

**However:** Retain `n_obs` (count of records per species) as a metadata column and run one sensitivity check — regress absolute PGLS residuals on log10(n_obs) to detect whether well-sampled species cluster in residual space (funnel plot diagnostic).

### Species with a single observation

Include singletons in all OLS regressions. For PGLS, include them — their value enters the analysis like any other species-level mean. Add a binary flag `singleton = TRUE/FALSE` and run sensitivity analyses dropping singletons to confirm that conclusions are robust.

**Never impute or smooth single-observation species means** — that would introduce circular assumptions about the very scaling relationships being estimated.

### Recommended aggregation code

```r
library(dplyr)

species_means_ne <- niklas_enquist_clean |>
  filter(!is.na(total_biomass_kg), !is.na(height_m),
         total_biomass_kg > 0, height_m > 0) |>
  group_by(taxa) |>
  summarise(
    log_total_biomass  = mean(log10(total_biomass_kg), na.rm = TRUE),
    log_height         = mean(log10(height_m),         na.rm = TRUE),
    log_total_growth   = mean(log10(total_growth_kgyr), na.rm = TRUE),
    log_leaf_biomass   = mean(log10(leaf_biomass_kg),  na.rm = TRUE),
    log_stem_biomass   = mean(log10(stem_biomass_kg),  na.rm = TRUE),
    n_obs              = n(),
    singleton          = (n() == 1),
    .groups = "drop"
  ) |>
  # back-transform means for table display only
  mutate(
    total_biomass_kg_gmean = 10^log_total_biomass,
    height_m_gmean         = 10^log_height
  )
```

---

## 2. Regression Method Comparison

### OLS (ordinary least squares on log-log data)

**Model:** $\log_{10}(Y) = \alpha + \beta \log_{10}(X) + \varepsilon$, $\varepsilon \sim N(0, \sigma^2)$

- Minimises sum of squared **vertical** residuals
- Assumes X is measured without error (or error is negligible relative to Y's variance)
- Yields the **best linear predictor** of Y given X
- **Limitation:** When X has measurement error, OLS produces *attenuation bias* — the slope is biased toward zero by the factor $\rho_{XX'}$ (reliability ratio). For field-measured height or DBH, this is non-trivial
- **Appropriate for:** BAAD individual-level AGB~DBH when DBH is measured with calipers (low error) and prediction of biomass is the goal
- Does **not** account for phylogenetic non-independence among species

### SMA (Standardised Major Axis = Reduced Major Axis)

**Model:** Minimises sum of the product of horizontal and vertical residuals

$$\hat{\beta}_{\text{SMA}} = \frac{\hat{\beta}_{\text{OLS}(Y|X)}}{r_{XY}} = \text{sign}(r_{XY}) \sqrt{\frac{SS_Y / SS_X}{1}} $$

Equivalently: $\hat{\beta}_{\text{SMA}} = \hat{\beta}_{\text{OLS}(Y|X)} / r_{XY}$, so $|\hat{\beta}_{\text{SMA}}| \geq |\hat{\beta}_{\text{OLS}}|$ always.

- Appropriate when **both** X and Y carry measurement error and the goal is to describe the *functional* (structural) relationship, not predict Y
- Preferred by Warton et al. (2006, *Biol. Rev.*) for allometric scaling across species
- The SMA slope equals the OLS slope only when $r_{XY} = 1$ (no error)
- **Critical limitation:** No natural PGLS extension exists for SMA — you cannot simply apply a phylogenetic variance-covariance correction to SMA minimisation. Use SMA for OLS comparisons and for testing against theoretical slopes, but **PGLS is OLS-based**
- Report SMA 95% CI (bootstrapped by default in `smatr`) alongside PGLS results

### PGLS (phylogenetic generalised least squares)

**Model:** $\log_{10}(Y) = \alpha + \beta \log_{10}(X) + \boldsymbol{\varepsilon}$, where $\boldsymbol{\varepsilon} \sim MVN(\mathbf{0},\ \sigma^2 \mathbf{V})$

$\mathbf{V} = \lambda \mathbf{C} + (1-\lambda)\mathbf{I}$

where $\mathbf{C}$ is the phylogenetic variance-covariance matrix derived from the tree (branch lengths scaled so $C_{ii} = 1$), $\lambda \in [0,1]$ is Pagel's lambda, and $\mathbf{I}$ is identity.

- Directly models the **non-independence** of species due to shared evolutionary history
- Without PGLS, OLS on species means violates the i.i.d. assumption: closely related species share recent common ancestors, so their trait values are correlated — this inflates effective sample size and narrows standard errors
- Felsenstein (1985) showed that untransformed species means give Type I error inflation for comparative tests when traits are phylogenetically structured
- **Appropriate for:** all four Niklas-Enquist scaling relationships; BAAD species-mean relationships

### Which method to use for cross-species allometry?

| Method | Correct for phylogenetic non-independence | Handles error in X | Goal |
|--------|------------------------------------------|-------------------|------|
| OLS (species means) | No | No | Baseline/literature comparison |
| SMA (species means) | No | Yes | Structural relationship estimate |
| PGLS (species means) | **Yes** | No (OLS-based) | **Primary inferential method** |
| OLS (individual-level, BAAD) | N/A (not species-level) | No | Individual-level allometry |

**Primary inferential method:** PGLS on species-level log-means.  
**Report alongside:** SMA slope (species-level) and OLS slope (species-level) for comparison and to assess attenuation bias magnitude.

---

## 3. PGLS Specifics

### Pagel's λ — ecological interpretation

λ is estimated by maximum likelihood on the residual variance-covariance matrix.

| λ value | Ecological meaning |
|---------|-------------------|
| **λ = 1** | Residuals from the regression covary exactly as predicted by Brownian motion along the phylogeny — strong phylogenetic conservatism in the *relationship* (after accounting for the predictor), consistent with trait evolution being random walk with no additional selection |
| **λ = 0** | Residuals are independent of phylogeny — equivalent to OLS on species means; implies the covariate fully explains species-level variance or that trait evolution is highly labile / convergent |
| **0 < λ < 1** | Intermediate signal; Pagel's lambda rescales internal branch lengths by λ while leaving tip branches unchanged |
| **λ > 1** | Possible in bounded implementations; indicates more clustering than BM — can arise with stabilising selection or overdispersion relative to BM |

Note: λ estimated here is the lambda for the *regression residuals*, not for the traits themselves — it measures residual phylogenetic signal after the predictor is accounted for.

### Model specification in caper

```r
library(caper)
library(ape)

# Step 1: build comparative.data object
comp_data <- comparative.data(
  phy       = pruned_tree,          # ultrametric, fully resolved where possible
  data      = species_means_ne,
  names.col = "taxa",               # column matching tip labels
  vcv       = TRUE,                 # pre-compute VCV matrix
  na.omit   = FALSE,                # handle NAs manually before this step
  warn.dropped = TRUE               # always inspect dropped species
)

# Step 2: fit with ML lambda
pgls_bm_height <- pgls(
  log_total_biomass ~ log_height,
  data   = comp_data,
  lambda = "ML",
  bounds = list(lambda = c(1e-6, 1))  # keep lambda in [0,1]
)
summary(pgls_bm_height)

# Step 3: profile likelihood for lambda (check for flat/multimodal)
lam_profile <- pgls.profile(pgls_bm_height)
plot(lam_profile)

# Step 4: compare fixed lambda values (sensitivity)
pgls_lam0 <- pgls(log_total_biomass ~ log_height, data = comp_data, lambda = 0)
pgls_lam1 <- pgls(log_total_biomass ~ log_height, data = comp_data, lambda = 1)
AIC(pgls_bm_height, pgls_lam0, pgls_lam1)  # confirms ML lambda is preferred
```

Use `lambda = "REML"` as a sensitivity check when N < 50 species, as REML is less biased for variance component estimation in small samples.

### Species–tree mismatches

**Species in data but not in tree** → must be dropped from PGLS (no vcv row/column). Never silently ignore; document count and proportion.

**Species in tree but not in data** → automatically pruned by caper. No action needed.

**Workflow:**

```r
library(ape)

# 1. Standardise names in both data and tree tips
# Use TNRS or taxize::gnr_resolve() — do NOT manually guess synonyms

# 2. Identify mismatches
name_check <- name.check(phy = tree, data = species_means_ne,
                          data.names = species_means_ne$taxa)
cat("In data, not tree:", length(name_check$data_not_tree), "\n")
cat("In tree, not data:", length(name_check$tree_not_data), "\n")

# 3. Prune tree to matched species only
pruned_tree <- drop.tip(tree, name_check$tree_not_data)

# 4. For species missing from tree: option to graft as polytomy at genus level
# Use phytools::bind.tip() only when genus is represented in tree
# Flag grafted species in a 'tree_source' column: "original" | "grafted_genus"
```

**Minimum species count for reliable PGLS:** At least **20 species** for λ estimation to be non-degenerate; at least **30** for narrow enough CI on λ to be interpretable. With the Niklas-Enquist dataset (2,626 rows → expected ~200–400 unique species depending on tree coverage), this is not a limiting concern. If any individual scaling relationship drops below 30 species after tree pruning, fix λ = 1 and report as a sensitivity result.

---

## 4. Exponent Comparison Tests

### OLS vs PGLS: testing whether slopes differ

The OLS and PGLS slope estimates are not from nested models (different covariance assumptions), so a likelihood ratio test cannot be used directly. Use:

**Method 1 — z-test (practical, commonly used):**

$$z = \frac{\hat{\beta}_{\text{OLS}} - \hat{\beta}_{\text{PGLS}}}{\sqrt{SE_{\text{OLS}}^2 + SE_{\text{PGLS}}^2}}$$

This assumes the two estimates are approximately independent (they are correlated in practice, so treat p-values as approximate). Under $H_0$: same true slope, $z \sim N(0,1)$.

**Method 2 — Bootstrap overlap (preferred for SMA):**

Bootstrap SMA: use `smatr::sma(..., method = "SMA", n = 1000)` which returns bootstrap CIs. Inspect whether PGLS slope ± 2·SE falls outside the SMA bootstrap CI. Non-overlap is evidence of attenuation bias in OLS/SMA.

**Method 3 — Cross-validation (informal):** Fit PGLS on a randomly selected half of species; predict held-out species; compare predictive RMSE between PGLS and OLS. Preferred when the goal is prediction rather than inference.

### Testing against WBE theoretical predictions

For each relationship, test $H_0: \beta = \beta_{\text{WBE}}$:

**OLS / PGLS t-test:**

$$t = \frac{\hat{\beta} - \beta_{\text{WBE}}}{SE_{\hat{\beta}}}, \quad df = n_{\text{species}} - 2$$

```r
# PGLS example — test against WBE 3/4 prediction
pgls_coef <- summary(pgls_growth_biomass)$coefficients
beta_hat <- pgls_coef["log_total_biomass", "Estimate"]
se_beta  <- pgls_coef["log_total_biomass", "Std. Error"]
df_resid <- pgls_growth_biomass$n - 2

t_stat <- (beta_hat - 0.75) / se_beta
p_val  <- 2 * pt(abs(t_stat), df = df_resid, lower.tail = FALSE)
ci_95  <- beta_hat + c(-1, 1) * qt(0.975, df = df_resid) * se_beta

cat(sprintf("β = %.3f (95%% CI: %.3f–%.3f), t = %.3f, p = %.4f\n",
            beta_hat, ci_95[1], ci_95[2], t_stat, p_val))
```

**SMA-specific test against theoretical slope:**

```r
library(smatr)
sma_fit <- sma(log_total_biomass ~ log_height, data = species_means_ne,
               method = "SMA")
# Test slope against WBE prediction (8/3 ≈ 2.667 for biomass ~ height)
slope.test(sma_fit, test.value = 8/3, method = "likelihood")
```

`smatr::slope.test()` uses a Wald-type likelihood ratio test specifically designed for SMA — this is the correct approach for testing SMA slopes against theoretical values (do not use a naive t-test on SMA, as the SMA SE is not the same as OLS SE).

### WBE theoretical predictions summary

| Relationship | WBE / E&N prediction | Exponent value |
|-------------|---------------------|----------------|
| Total biomass ~ height | West et al. 1999 (WBE) | 8/3 ≈ 2.667 |
| Total growth ~ total biomass | Enquist et al. 1999 (WBE) | 3/4 = 0.75 |
| Leaf biomass ~ total biomass | Enquist & Niklas 2002 | 3/4 = 0.75 |
| Stem biomass ~ total biomass | Partition isometry | ≈ 1.0 |
| AGB ~ DBH (BAAD) | Chave et al. 2014 (empirical) | ≈ 2.3–2.7 |
| Height ~ DBH (BAAD) | WBE | 2/3 ≈ 0.667 |

---

## 5. Diagnostics

### Residual phylogenetic signal after PGLS

If PGLS with ML-estimated λ is correctly specified, residuals should have **no remaining phylogenetic signal**. Test this formally:

```r
library(phytools)
library(ape)

pgls_resids <- residuals(pgls_bm_height)

# Blomberg's K on residuals (expect K near 0 if PGLS worked)
K_resid <- phylosig(pruned_tree, pgls_resids, method = "K", test = TRUE, nsim = 999)
cat("K on residuals:", K_resid$K, "p =", K_resid$P, "\n")

# Moran's I (requires a pairwise distance matrix as weights)
phylo_dist <- cophenetic(pruned_tree)                  # patristic distances
w_mat <- 1 / phylo_dist                                # inverse-distance weights
diag(w_mat) <- 0
w_mat <- w_mat / rowSums(w_mat)                        # row-standardise
moran_result <- Moran.I(pgls_resids, w_mat)
cat("Moran's I =", moran_result$observed,
    "p =", moran_result$p.value, "\n")
```

**Interpretation:** K residuals >> 0 or Moran's I significantly positive after PGLS suggests model misspecification. Possible remedies: (a) recheck tree topology for the relevant clade; (b) allow κ or δ transformation of branch lengths (see `caper::pgls()` `kappa` and `delta` arguments); (c) add a taxonomic random effect (Family or Genus) as a fixed covariate if the PGLS tree coverage is sparse.

### Influential species (jackknife leverage for PGLS)

No closed-form Cook's D exists for PGLS. Use leave-one-out jackknife:

```r
species_list <- species_means_ne$taxa
jackknife_slopes <- numeric(length(species_list))

for (i in seq_along(species_list)) {
  jk_data  <- species_means_ne[species_means_ne$taxa != species_list[i], ]
  jk_tree  <- drop.tip(pruned_tree, species_list[i])
  jk_cdata <- comparative.data(jk_tree, jk_data, names.col = "taxa",
                                vcv = TRUE, na.omit = FALSE)
  jk_fit <- tryCatch(
    pgls(log_total_biomass ~ log_height, data = jk_cdata, lambda = "ML"),
    error = function(e) NULL
  )
  jackknife_slopes[i] <- if (!is.null(jk_fit)) coef(jk_fit)[2] else NA
}

slope_mean  <- mean(jackknife_slopes, na.rm = TRUE)
slope_sd    <- sd(jackknife_slopes,   na.rm = TRUE)
influential <- species_list[abs(jackknife_slopes - slope_mean) > 2 * slope_sd]
cat("Potentially influential species:\n"); print(influential)
```

Flag any species whose removal shifts the slope by more than 2 SD of the jackknife distribution. Report the full model result and the result excluding those species.

### Heteroscedasticity on log-log scale

Homoscedasticity should be approximately satisfied after log-transformation if the data span a biologically realistic range. Test formally:

```r
library(lmtest)

# For OLS (baseline check before PGLS)
ols_fit <- lm(log_total_biomass ~ log_height, data = species_means_ne)
bptest(ols_fit)            # Breusch–Pagan test; H0 = homoscedastic
plot(ols_fit, which = 3)   # scale-location plot

# For PGLS residuals (informal): plot |residuals| vs fitted
plot(fitted(pgls_bm_height), abs(residuals(pgls_bm_height)),
     xlab = "PGLS fitted", ylab = "|PGLS residuals|")
abline(lm(abs(residuals(pgls_bm_height)) ~ fitted(pgls_bm_height)), col = "red")
```

**If heteroscedasticity is detected:** Consider (a) checking whether very small-bodied species (e.g., herbs) form a separate cluster; (b) adding a life-form covariate (woody vs herbaceous); (c) fitting separate scaling models by plant functional type.

---

## 6. Phylogenetic Signal Before Regression

Estimate Blomberg's K and Pagel's λ **independently for each log-transformed trait** before fitting any regression. This answers: *are these traits phylogenetically conserved in themselves?*

```r
library(phytools)

traits <- c("log_total_biomass", "log_height", "log_total_growth",
            "log_leaf_biomass", "log_stem_biomass")

signal_results <- lapply(traits, function(tr) {
  trait_vec <- setNames(species_means_ne[[tr]], species_means_ne$taxa)
  trait_vec <- trait_vec[!is.na(trait_vec)]
  common    <- intersect(names(trait_vec), pruned_tree$tip.label)
  trait_vec <- trait_vec[common]
  local_tree <- drop.tip(pruned_tree, setdiff(pruned_tree$tip.label, common))

  K_res  <- phylosig(local_tree, trait_vec, method = "K",
                     test = TRUE, nsim = 999)
  lam_res <- phylosig(local_tree, trait_vec, method = "lambda",
                      test = TRUE)
  data.frame(
    trait   = tr,
    K       = K_res$K,
    K_p     = K_res$P,
    lambda  = lam_res$lambda,
    lambda_p = lam_res$P
  )
})
signal_table <- do.call(rbind, signal_results)
print(signal_table)
```

### Interpretation

| Pattern | Implication for regression choice |
|---------|-----------------------------------|
| K ≈ 1, λ ≈ 1 for both X and Y | BM model is appropriate; PGLS with λ = 1 may fit well; OLS seriously invalid |
| K >> 1 | Strong niche conservatism; stabilising selection around a clade mean; PGLS still appropriate |
| K << 1, λ ≈ 0 | Labile/convergent trait evolution; PGLS reduces to OLS; both are defensible |
| High signal in Y, low in X (or vice versa) | Asymmetric phylogenetic structuring; ML-estimated λ in PGLS is most appropriate |

If λ is near 0 for all traits: PGLS is still the formally correct approach but the numerical difference from OLS will be small. **Always report PGLS as primary** even in this case, because the decision to use PGLS should be based on the biological expectation (phylogenetic non-independence is real) not on whether signal happens to be detected in a given sample.

---

## 7. Multiple Comparisons

### Are the 4–6 scaling relationships statistically independent?

**No.** Multiple sources of dependence exist:

1. **Shared species:** The same species appears across multiple relationships; their residuals are correlated
2. **Mathematical dependencies:** `total_biomass = root + stem + leaf` — so regressions on `leaf_biomass ~ total_biomass` and `stem_biomass ~ total_biomass` use a Y that is a component of X; their slopes are not independent
3. **Correlated predictors:** Height and DBH are strongly correlated (r ≈ 0.6–0.8 in most datasets)

### Recommended approach

**Primary comparisons (pre-specified hypothesis tests vs WBE theory):**  
These are **pre-specified, theoretically motivated tests**, not data-dredging. Under this framing, no adjustment for multiple comparisons is required — each test has its own type I error rate of α = 0.05 and addresses a distinct WBE prediction. This is consistent with standard practice in comparative physiology (e.g., Enquist & Niklas 2002; West et al. 1999). State this explicitly in the Methods.

**Exploratory components (e.g., variation among plant functional types, sensitivity analyses):**  
Apply Benjamini–Hochberg FDR correction:

```r
p_values_exploratory <- c(...)   # collect raw p-values
p_adjusted <- p.adjust(p_values_exploratory, method = "BH")
```

**Presentation guidelines:**

- Report a **single results table** with all relationships: estimated slope, 95% CI, N species, λ_ML, K_residual, p-value (raw), and for exploratory tests also p_BH
- Focus narrative on **effect sizes and CIs, not p-values** — a slope of 0.71 vs WBE 0.75 is scientifically informative regardless of whether p < 0.05
- Flag the mathematical dependency between `leaf_biomass ~ total_biomass` and `stem_biomass ~ total_biomass` in a footnote

---

## 8. R Packages and Functions — Master Reference

| Task | Package | Key functions |
|------|---------|--------------|
| Species-mean aggregation | `dplyr` | `group_by()`, `summarise()` |
| OLS regression | base R | `lm()`, `coef()`, `confint()` |
| SMA regression | `smatr` ≥ 3.4 | `sma()`, `slope.test()`, `elev.test()` |
| PGLS | `caper` ≥ 1.0 | `comparative.data()`, `pgls()`, `pgls.profile()` |
| Tree manipulation | `ape` ≥ 5.0 | `drop.tip()`, `name.check()`, `cophenetic()` |
| Phylogenetic signal | `phytools` ≥ 1.0 | `phylosig()` (K and lambda) |
| Tip grafting | `phytools` | `bind.tip()` |
| Moran's I | `ape` | `Moran.I()` |
| Breusch–Pagan test | `lmtest` | `bptest()` |
| FDR correction | base R | `p.adjust(..., method = "BH")` |
| Bootstrap (general) | `boot` | `boot()`, `boot.ci()` |
| Taxonomy matching | `taxize` | `gnr_resolve()`, `tnrs_match_names()` |

### Critical package versions

```r
# Verify versions before analysis
stopifnot(packageVersion("caper")   >= "1.0.1")
stopifnot(packageVersion("phytools") >= "1.5")
stopifnot(packageVersion("smatr")   >= "3.4.8")
stopifnot(packageVersion("ape")     >= "5.7")
```

---

## 9. Analysis Execution Order

```
1. Data prep
   ├── Recode -999 → NA in Niklas-Enquist
   ├── Filter non-positive values before log-transform
   ├── Compute species-level log-means (Section 1)
   └── Harmonise BAAD species names

2. Phylogenetic tree
   ├── Fetch V.PhyloMaker2 or GBOTB.extended mega-tree
   ├── TNRS name matching for both datasets
   ├── Prune / graft to study species
   └── Force ultrametric if needed: ape::force.ultrametric()

3. Pre-regression diagnostics
   ├── Phylogenetic signal (K, λ) for each trait
   └── Pairwise trait correlations

4. OLS (species means, log-log)
   └── All 6 relationships → save slopes, CIs, r²

5. SMA (species means, log-log)
   └── All 6 relationships → save slopes, bootstrap CIs

6. PGLS (species means, ML λ)
   ├── All 6 relationships
   ├── Profile λ for each model
   └── Jackknife influential species

7. Post-PGLS diagnostics
   ├── K and Moran's I on PGLS residuals
   └── Heteroscedasticity plots

8. Hypothesis tests
   ├── OLS vs PGLS slope comparison (z-test)
   ├── Each PGLS slope vs WBE prediction (t-test)
   └── SMA slope vs WBE prediction (slope.test)

9. Results table + figures
   └── Report raw p-values; BH-adjusted p for exploratory tests
```

---

## 10. Flagged Statistical Risks

| Risk | Severity | Mitigation |
|------|---------|------------|
| Niklas-Enquist "taxa" strings are not clean species names — some share names for different populations | **CRITICAL** | Inspect taxa strings before grouping; do not merge populations of different species that happen to share a name. Manual or TNRS-assisted deduplication required |
| Mathematical dependency of leaf + stem + root = total biomass causes spurious correlation in component ~ total regressions (regression dilution / spurious allometry) | **WARNING** | Report these relationships explicitly noting the dependency; consider using independent components (e.g., leaf biomass ~ stem biomass as X instead) or report alongside known artifact literature (Packard 2017) |
| Lambda profile may be flat (non-identifiable) with few species or a poorly-resolved phylogeny | **WARNING** | Always plot pgls.profile(); if profile is flat, fix λ at values 0, 0.5, 1 and report sensitivity |
| Height-DBH collinearity in any multi-predictor model | **WARNING** | Check VIF; keep as separate bivariate regressions, not a joint model |
| BAAD m.to (total biomass) may include roots for some species and exclude roots for others | **WARNING** | Inspect baad.data metadata; consider restricting to aboveground biomass (m.ao) for consistency |

---

## References

- Felsenstein J (1985) Phylogenies and the comparative method. *Am Nat* 125:1–15
- West GB, Brown JH, Enquist BJ (1999) A general model for the structure and allometry of plant vascular systems. *Nature* 400:664–667
- Enquist BJ, Niklas KJ (2002) Global allocation rules for patterns of biomass partitioning in seed plants. *Science* 295:1517–1520
- Warton DI, Wright IJ, Falster DS, Westoby M (2006) Bivariate line-fitting methods for allometry. *Biol Rev* 81:259–291
- Pagel M (1999) Inferring the historical patterns of biological evolution. *Nature* 401:877–884
- Harvey PH, Pagel MD (1991) *The Comparative Method in Evolutionary Biology*. Oxford University Press
- Orme D et al. (2018) caper: Comparative Analyses of Phylogenetics and Evolution in R. CRAN
- Revell LJ (2012) phytools: An R package for phylogenetic comparative biology. *Methods Ecol Evol* 3:217–223
