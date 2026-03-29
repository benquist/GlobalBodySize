## California Poppy Species Distribution Model

### About the Species

*Eschscholzia californica* (California Poppy) is the official state flower of
California. It is a drought-tolerant annual/perennial found across a wide range
of open habitats in the western United States and Mexico.

---

### About the Model

This app fits a **MaxEnt** species distribution model using the
[`maxnet`](https://CRAN.R-project.org/package=maxnet) R package — a fast,
R-native implementation of the Maxent algorithm.

| Component | Detail |
|-----------|--------|
| Occurrence data | BIEN database via the `BIEN` R package |
| Study region | California (−125–−114 °E, 32–42 °N) |
| Climate predictors | 19 WorldClim v2.1 BIO variables at 2.5 arc-min |
| Background method | Random sampling across the study region |
| Evaluation | 80/20 train-test split, AUC & TSS on held-out data |

---

### How to Use

1. **Adjust settings** in the left sidebar (background points, training
   fraction, MaxEnt feature classes).
2. Click **Run Model** — the app will fetch occurrence data from BIEN,
   load WorldClim rasters, train the model, and generate all outputs.
3. Explore the **Distribution Map** tab for the interactive suitability map.
   Use the **Threshold** slider to toggle the binary suitable-habitat overlay.
4. Switch to **Model Performance** to inspect the ROC curve, score
   distributions, and full diagnostics table.
5. See **Response Curves** for marginal predictor effects and
   **Variable Importance** for permutation-based importance scores.

---

### BIO Variable Key

| Code | Description |
|------|-------------|
| bio1 | Mean Annual Temperature |
| bio5 | Max Temperature of Warmest Month |
| bio6 | Min Temperature of Coldest Month |
| bio12 | Annual Precipitation |
| bio15 | Precipitation Seasonality (CV) |

---

### References

- Fick, S.E. & Hijmans, R.J. (2017). WorldClim 2: new 1-km spatial resolution climate surfaces for global land areas. *International Journal of Climatology*, 37(12), 4302–4315.
- Phillips, S.J., Anderson, R.P., Dudík, M., Schapire, R.E. & Blair, M.E. (2017). Opening the black box: an open-source release of Maxent. *Ecography*, 40, 887–893.
- Maitner, B.S. et al. (2018). The BIEN R package: A tool to access the Botanical Information and Ecology Network (BIEN) database. *Methods in Ecology and Evolution*, 9, 373–379.
