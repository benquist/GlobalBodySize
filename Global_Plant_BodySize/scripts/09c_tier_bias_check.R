## Global_Plant_BodySize/scripts/09c_tier_bias_check.R
## Stage 9c: Bland-Altman bias analysis across AGB estimation tiers.
##
## PURPOSE:
##   For the 1,978 "allometric-ready" species (those with both height_m_mean
##   AND dbh_cm_mean AND any wood density), compute AGB three ways and
##   test for systematic bias between tiers on the log10 scale:
##
##   AGB_T1  = Brown 1997 height-only (or Muukkonen for shrubs; herb proxy for herbs)
##   AGB_T2  = Chave 2005 DBH-only   (or Muukkonen DBH for shrubs)
##   AGB_T34 = Chave 2014 DBH+H+rho  (reference — Tier 3 or 4 depending on rho level)
##
##   Bland-Altman analysis (log10 scale) per tier comparison × growth form:
##     D_i = log10(AGB_T1_i) - log10(AGB_T34_i)   [Tier1 vs reference]
##     D_i = log10(AGB_T2_i) - log10(AGB_T34_i)   [Tier2 vs reference]
##
##   Reports: mean bias (D-bar), 95% limits of agreement (±1.96 SD),
##   and whether mean bias is significantly ≠ 0 (one-sample t-test).
##
## CORRECTION FACTORS:
##   If mean bias is significant (|D-bar| > 0.1 log10 units AND p < 0.05),
##   a growth-form-specific additive correction on the log10 scale is stored
##   in output/tier_bias_corrections.csv for optional application in Stage 9b.
##   NOTE: Corrections are only applied to growth forms with n ≥ 10 species.
##
## Inputs:
##   output/plant_biomass_estimates.csv   — Tier 1-4 AGB estimates per species
##   output/plant_bodysize_final.csv      — height + DBH per species
##   output/species_wood_density.csv      — rho per species
##
## Outputs:
##   output/tier_bias_summary.csv         — Bland-Altman results by comparison × GF
##   output/tier_bias_corrections.csv     — correction factors where bias is significant
##   output/tier_bias_check.html          — diagnostic plots (Bland-Altman + histograms)
##
## Run from project root:
##   Rscript scripts/09c_tier_bias_check.R

if (basename(getwd()) == "scripts") setwd("..")

suppressPackageStartupMessages(library(data.table))

CHAVE2014_a <- 0.0673
CHAVE2014_b <- 0.976

chave2005_dbh_only <- function(D) {
  exp(-1.499 + 2.148 * log(D) + 0.207 * log(D)^2 - 0.0281 * log(D)^3)
}

brown1997_height_only <- function(H) {
  exp(-2.289 + 2.649 * log(H) - 0.021 * log(H)^2)
}

MUUKKONEN_SHRUB_a <- 0.174
MUUKKONEN_SHRUB_b <- 1.940
HERB_a <- 0.04
HERB_b <- 1.50

message("=== Stage 9c: Tier bias check (Bland-Altman) ===")

## ---- Load data -------------------------------------------------------------
stopifnot(file.exists("output/plant_bodysize_final.csv"),
          file.exists("output/species_wood_density.csv"))

final <- fread("output/plant_bodysize_final.csv")
wd    <- fread("output/species_wood_density.csv",
               select = c("species_name", "rho_mean", "rho_sd",
                          "rho_match_level", "rho_source"))

dt <- merge(final, wd, by = "species_name", all.x = TRUE)

## ---- Restrict to allometric-ready species (Tiers 3 + 4) --------------------
## These species have height + DBH + any rho — our calibration set.
cal <- dt[!is.na(height_m_mean) & !is.na(dbh_cm_mean) &
          height_m_mean > 0 & dbh_cm_mean > 0 &
          !is.na(rho_mean) & rho_mean > 0]

message("[9c] Allometric-ready species (calibration set): ", nrow(cal))

## ---- Compute AGB three ways for each calibration species -------------------

## Reference: Chave 2014 (T3/T4, same equation — rho level distinguishes 3 vs 4)
cal[, agb_ref_kg := CHAVE2014_a * (rho_mean * dbh_cm_mean^2 * height_m_mean)^CHAVE2014_b]

## T1: height-only allometry (growth-form specific)
cal[, agb_t1_kg := {
  agb <- rep(NA_real_, .N)
  tree_mask  <- growth_form_canonical %in% c("tree", "bamboo")
  shrub_mask <- growth_form_canonical %in% c("shrub", "subshrub", "vine", "epiphyte")
  herb_mask  <- growth_form_canonical %in% c("herb", "graminoid", "aquatic", "parasite",
                                              "unknown")
  agb[tree_mask]  <- brown1997_height_only(height_m_mean[tree_mask])
  agb[shrub_mask] <- MUUKKONEN_SHRUB_a * height_m_mean[shrub_mask]^MUUKKONEN_SHRUB_b
  agb[herb_mask]  <- HERB_a * height_m_mean[herb_mask]^HERB_b
  agb
}]

## T2: DBH-only allometry (growth-form specific)
cal[, agb_t2_kg := {
  agb <- rep(NA_real_, .N)
  tree_mask  <- growth_form_canonical %in% c("tree", "bamboo", "vine", "epiphyte")
  shrub_mask <- growth_form_canonical %in% c("shrub", "subshrub")
  agb[tree_mask]  <- chave2005_dbh_only(dbh_cm_mean[tree_mask])
  agb[shrub_mask] <- MUUKKONEN_SHRUB_a * dbh_cm_mean[shrub_mask]^MUUKKONEN_SHRUB_b
  agb
}]

## Remove any cases where reference or comparison is NA / non-positive
cal_t1 <- cal[!is.na(agb_ref_kg) & !is.na(agb_t1_kg) &
               agb_ref_kg > 0 & agb_t1_kg > 0]
cal_t2 <- cal[!is.na(agb_ref_kg) & !is.na(agb_t2_kg) &
               agb_ref_kg > 0 & agb_t2_kg > 0]

message("[9c] T1 vs Ref pairs: ", nrow(cal_t1))
message("[9c] T2 vs Ref pairs: ", nrow(cal_t2))

## ---- Bland-Altman function (log10 scale) -----------------------------------
## Returns a named list: mean_bias, sd_bias, loa_lower, loa_upper, p_value, n
bland_altman_log10 <- function(agb_test, agb_ref) {
  D    <- log10(agb_test) - log10(agb_ref)
  mean_D <- mean(D, na.rm = TRUE)
  sd_D   <- sd(D, na.rm = TRUE)
  n      <- sum(!is.na(D))
  ## one-sample t-test: is mean bias significantly ≠ 0?
  ttest <- tryCatch(t.test(D, mu = 0), error = function(e) list(p.value = NA))
  list(
    mean_bias = mean_D,
    sd_bias   = sd_D,
    loa_lower = mean_D - 1.96 * sd_D,
    loa_upper = mean_D + 1.96 * sd_D,
    p_value   = ttest$p.value,
    n         = n
  )
}

## ---- Run Bland-Altman by comparison × growth form --------------------------
gf_levels <- unique(c(cal_t1$growth_form_canonical, cal_t2$growth_form_canonical))
gf_levels <- gf_levels[!is.na(gf_levels)]

results <- list()

for (gf in c("all", gf_levels)) {
  ## T1 vs Reference
  sub_t1 <- if (gf == "all") cal_t1 else cal_t1[growth_form_canonical == gf]
  if (nrow(sub_t1) >= 3) {
    ba <- bland_altman_log10(sub_t1$agb_t1_kg, sub_t1$agb_ref_kg)
    results[[length(results) + 1]] <- data.table(
      comparison    = "T1_vs_Ref",
      growth_form   = gf,
      n             = ba$n,
      mean_bias_log10 = round(ba$mean_bias, 4),
      sd_bias_log10 = round(ba$sd_bias, 4),
      loa_lower     = round(ba$loa_lower, 4),
      loa_upper     = round(ba$loa_upper, 4),
      p_value       = signif(ba$p_value, 3),
      bias_significant = !is.na(ba$p_value) & ba$p_value < 0.05 & abs(ba$mean_bias) > 0.1,
      note          = "log10(AGB_T1) - log10(AGB_Chave2014)"
    )
  }

  ## T2 vs Reference
  sub_t2 <- if (gf == "all") cal_t2 else cal_t2[growth_form_canonical == gf]
  if (nrow(sub_t2) >= 3) {
    ba <- bland_altman_log10(sub_t2$agb_t2_kg, sub_t2$agb_ref_kg)
    results[[length(results) + 1]] <- data.table(
      comparison    = "T2_vs_Ref",
      growth_form   = gf,
      n             = ba$n,
      mean_bias_log10 = round(ba$mean_bias, 4),
      sd_bias_log10 = round(ba$sd_bias, 4),
      loa_lower     = round(ba$loa_lower, 4),
      loa_upper     = round(ba$loa_upper, 4),
      p_value       = signif(ba$p_value, 3),
      bias_significant = !is.na(ba$p_value) & ba$p_value < 0.05 & abs(ba$mean_bias) > 0.1,
      note          = "log10(AGB_T2) - log10(AGB_Chave2014)"
    )
  }
}

bias_summary <- rbindlist(results)
fwrite(bias_summary, "output/tier_bias_summary.csv")
message("[9c] Bland-Altman summary written: output/tier_bias_summary.csv")

## ---- Report key findings ---------------------------------------------------
message("[9c] === Bias summary ===")
all_t1 <- bias_summary[comparison == "T1_vs_Ref" & growth_form == "all"]
all_t2 <- bias_summary[comparison == "T2_vs_Ref" & growth_form == "all"]

if (nrow(all_t1) > 0) {
  message(sprintf("  T1 vs Ref (all GF): bias=%.3f log10-kg, LoA=[%.3f, %.3f], p=%s, sig=%s",
    all_t1$mean_bias_log10, all_t1$loa_lower, all_t1$loa_upper,
    all_t1$p_value, all_t1$bias_significant))
}
if (nrow(all_t2) > 0) {
  message(sprintf("  T2 vs Ref (all GF): bias=%.3f log10-kg, LoA=[%.3f, %.3f], p=%s, sig=%s",
    all_t2$mean_bias_log10, all_t2$loa_lower, all_t2$loa_upper,
    all_t2$p_value, all_t2$bias_significant))
}

## GF-specific results
sig_rows <- bias_summary[bias_significant == TRUE]
if (nrow(sig_rows) > 0) {
  message("[9c] Significant biases found by growth form:")
  for (i in seq_len(nrow(sig_rows))) {
    r <- sig_rows[i]
    message(sprintf("  %s | GF=%s | bias=%.3f | n=%d",
      r$comparison, r$growth_form, r$mean_bias_log10, r$n))
  }
} else {
  message("[9c] No growth-form-specific biases exceed threshold (|bias| > 0.1 AND p < 0.05).")
}

## ---- Compute correction factors where bias is significant ------------------
## Correction = subtract mean_bias_log10 from log10(AGB_estimated)
## i.e., log10(AGB_corrected) = log10(AGB_T1) - mean_bias_log10
## Only produced for n >= 10 species.

corrections <- bias_summary[bias_significant == TRUE & n >= 10,
  .(comparison, growth_form, n,
    correction_log10 = -mean_bias_log10,   # additive on log10 scale
    correction_factor = 10^(-mean_bias_log10),   # multiplicative on natural scale
    loa_lower, loa_upper, p_value,
    note = paste0("Apply as: log10(AGB_corrected) = log10(AGB_", comparison,
                  ") + correction_log10"))]

fwrite(corrections, "output/tier_bias_corrections.csv")
if (nrow(corrections) > 0) {
  message("[9c] Correction factors written: output/tier_bias_corrections.csv")
  message("[9c] NOTE: Review corrections before applying — they are derived from")
  message("[9c]       the ", nrow(cal), " overlap species, which may not represent")
  message("[9c]       the full compositional range of each growth form.")
} else {
  message("[9c] No corrections needed (all biases below threshold or n < 10).")
  message("[9c] Empty corrections file written: output/tier_bias_corrections.csv")
}

## ---- Diagnostic HTML report ------------------------------------------------
message("[9c] Generating diagnostic HTML report...")

tryCatch({
  if (!requireNamespace("ggplot2", quietly = TRUE) ||
      !requireNamespace("rmarkdown", quietly = TRUE) ||
      !requireNamespace("knitr", quietly = TRUE)) {
    message("[9c] ggplot2/rmarkdown/knitr not available — skipping HTML report")
  } else {
    ## Inline Rmd for the diagnostic plot
    rmd_text <- '---
title: "Stage 9c: Tier Bias Diagnostics (Bland-Altman)"
date: "2026-05-13"
output:
  html_document:
    self_contained: true
---

```{r setup, include=FALSE}
knitr::opts_chunk$set(echo=FALSE, warning=FALSE, message=FALSE, fig.width=8, fig.height=5)
library(data.table); library(ggplot2)
if (basename(getwd()) == "scripts") setwd("..")
```

## Calibration set

Species with height + DBH + wood density: **`r nrow(cal_t1)` (T1 pairs)** and
**`r nrow(cal_t2)` (T2 pairs)**.

## Bland-Altman: T1 vs Reference (Chave 2014)

Difference on log₁₀ scale: log₁₀(AGB_T1) − log₁₀(AGB_ref)

```{r ba-t1}
ba_t1 <- copy(cal_t1)
ba_t1[, diff_log10 := log10(agb_t1_kg) - log10(agb_ref_kg)]
ba_t1[, mean_log10 := (log10(agb_t1_kg) + log10(agb_ref_kg)) / 2]
mean_d <- mean(ba_t1$diff_log10)
sd_d   <- sd(ba_t1$diff_log10)
ggplot(ba_t1, aes(mean_log10, diff_log10, colour = growth_form_canonical)) +
  geom_point(alpha = 0.5, size = 1.2) +
  geom_hline(yintercept = mean_d, linetype = "solid", colour = "black") +
  geom_hline(yintercept = mean_d + 1.96*sd_d, linetype = "dashed", colour = "red") +
  geom_hline(yintercept = mean_d - 1.96*sd_d, linetype = "dashed", colour = "red") +
  labs(x = "Mean log10(AGB) [log10 kg]",
       y = "Difference T1 - Ref [log10 kg]",
       title = "Bland-Altman: Height-only (T1) vs Chave 2014 (Ref)",
       subtitle = sprintf("Mean bias = %.3f log10 kg; 95%% LoA = [%.3f, %.3f]",
                          mean_d, mean_d - 1.96*sd_d, mean_d + 1.96*sd_d)) +
  theme_bw()
```

## Bland-Altman: T2 vs Reference (Chave 2014)

Difference on log₁₀ scale: log₁₀(AGB_T2) − log₁₀(AGB_ref)

```{r ba-t2}
ba_t2 <- copy(cal_t2)
ba_t2[, diff_log10 := log10(agb_t2_kg) - log10(agb_ref_kg)]
ba_t2[, mean_log10 := (log10(agb_t2_kg) + log10(agb_ref_kg)) / 2]
mean_d2 <- mean(ba_t2$diff_log10)
sd_d2   <- sd(ba_t2$diff_log10)
ggplot(ba_t2, aes(mean_log10, diff_log10, colour = growth_form_canonical)) +
  geom_point(alpha = 0.5, size = 1.2) +
  geom_hline(yintercept = mean_d2, linetype = "solid", colour = "black") +
  geom_hline(yintercept = mean_d2 + 1.96*sd_d2, linetype = "dashed", colour = "red") +
  geom_hline(yintercept = mean_d2 - 1.96*sd_d2, linetype = "dashed", colour = "red") +
  labs(x = "Mean log10(AGB) [log10 kg]",
       y = "Difference T2 - Ref [log10 kg]",
       title = "Bland-Altman: DBH-only (T2) vs Chave 2014 (Ref)",
       subtitle = sprintf("Mean bias = %.3f log10 kg; 95%% LoA = [%.3f, %.3f]",
                          mean_d2, mean_d2 - 1.96*sd_d2, mean_d2 + 1.96*sd_d2)) +
  theme_bw()
```

## Bias summary table

```{r bias-table}
knitr::kable(fread("output/tier_bias_summary.csv"), digits = 3)
```

## Calibration coverage caveat

The `r nrow(cal)` calibration species represent species with all three measurements
(height, DBH, wood density). These are systematically biased toward well-studied,
commercially important taxa — predominantly tropical trees. Bias corrections derived
here should be interpreted with caution when applied to herbs, graminoids, or
high-latitude growth forms.
'
    tmp_rmd <- tempfile(fileext = ".Rmd")
    writeLines(rmd_text, tmp_rmd)
    rmarkdown::render(tmp_rmd,
                      output_file = file.path(getwd(), "output/tier_bias_check.html"),
                      envir       = environment(),
                      quiet       = TRUE)
    message("[9c] Diagnostic HTML written: output/tier_bias_check.html")
  }
}, error = function(e) {
  message("[9c] HTML report failed (non-fatal): ", conditionMessage(e))
})

message("=== Stage 9c complete ===")
