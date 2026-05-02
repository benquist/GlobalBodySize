2026-05-01 | Initialized plant_scaling_data project scaffold with reproducible workflow files and starting provenance entry.
2026-05-01 | Created baad_summary.Rmd and baad_summary.html with full BAAD dataset breakdown: species, geography, vegetation, growing conditions, PFTs, scaling exponents, and source study table.
2026-05-01 | Created baad_summary.Rmd and baad_summary.html with full BAAD dataset breakdown: species, geography, vegetation, growing conditions, PFTs, scaling exponents, and source study table.
2026-05-01 | Ingested Niklas-Enquist biomass CSV (2626 rows, 390 taxa, 360 citations). Created niklas_enquist_summary.Rmd/html with full column profile, taxonomy breakdown, and scaling exponents.

## 2025-01-01 — Data Source Inventory

**Prompt:** Profile rFIA with fiaRI demo data; build a combined plant allometry data source inventory Rmd/HTML.

**What was done:**
- Profiled `rFIA::fiaRI` (RI demo): 10,644 TREE rows × 194 cols, 60 species, key allometric columns confirmed (DIA, HT, DRYBIO_AG/BG/BOLE/FOLIAGE, CARBON_AG/BG)
- Profiled `allodb` geographic coverage: 412 equations with lat/lon, temperate forest dominant, coverage across E. Asia, N. America, Europe
- Created `data_source_inventory.Rmd` + rendered `data_source_inventory.html` covering: BAAD, Niklas-Enquist, allodb, BIOMASS wdData + NouraguesHD, rFIA, and 6 pending datasets
- Key content: allodb equation map, Niklas-Enquist keyword-inferred geographic origin map (⚠ approximate), volume comparison chart, unit harmonization notes, merge decision table, acquisition plan for Zanne/Poorter/Chave/TRY/FRED/GlobAllomeTree
- Pushed commit 4650083

**Caveats / decisions recorded:**
- Dryad v2 REST API keyword search is non-functional (returns unrelated results); known DOIs must be used directly
- rFIA biomass is in lbs/acre (plot expansion) — needs per-tree conversion: lbs/acre ÷ TPA_UNADJ × 0.4536 = kg/tree
- allodb/BIOMASS contain equations, not raw observations — must be kept separate from measurement data in merged table
- Niklas-Enquist has NO lat/lon; geographic map is keyword-inferred from citation text and is approximate
2026-05-01 | ForestGEO Panama summary, cross-study allometry, inventory update — forestgeo_panama_summary.Rmd/html; cross_study_allometry.Rmd/html; data_source_inventory updated. Committed 10fe5f9.

2026-05-02 | NEON ForestAGB summary Rmd/HTML and Nouragues H-D summary Rmd/HTML added. Commit 6f082f8.

2026-05-02 | NEON ForestAGB growth rate analysis added (neon_growth_rates.Rmd/html). Commit 39bd72c.

2026-05-02 | NEON growth rate allometry analysis added (neon_growth_allometry.Rmd/html). Commit c1e8ef3.

2026-05-02 | SMA/RMA allometry analyses added: cross_study_allometry_sma.Rmd/html and neon_growth_allometry_sma.Rmd/html. Commit 0abfbe8.

2026-05-02 | PGLS allometric scaling workflow added (scripts 04-06, pgls_allometry_report.Rmd). Smith 2018 tree via V.PhyloMaker2. OLS/SMA/PGLS for 6 relationships. Scholarly rigor review applied and critical issues fixed.

2026-05-02 | Added Kurosawa et al. 2025 respiration scaling analysis (kurosawa_respiration_scaling.Rmd/html) and Forrester et al. 2022 SAPFLUXNET water-use scaling analysis (sapfluxnet_water_use_scaling.Rmd/html). Data sources: Kurosawa Y. et al. 2025 Proc R Soc B 292:20241910 (DOI:10.1098/rspb.2024.1910); Forrester DI, Limousin J-M, Pfautsch S. 2022 Tree Physiology 42:1916–1927 (DOI:10.1093/treephys/tpac018); SAPFLUXNET v0.1.5 (Zenodo DOI:10.5281/zenodo.3971689). Note: Kurosawa Dryad data (10.5061/dryad.sxksn03cj) blocked by Cloudflare — Rmd uses demo data calibrated to published slopes until data.respiration.csv is manually downloaded. SAPFLUXNET 0.1.5.zip (3.0 GB) downloaded and extracted to data/raw/sapfluxnet/0.1.5/csv/plant/ (194 sites, 2458 trees). Both Rmds use SMA regression (smatr ≥3.4), corrected unit conversion (cm³ h⁻¹ × 24/1000 for L/day), and full smatr v3 API (fit$coef[[1]], fit$r2[[1]]).

---
## Session: Inline scientific comments added to SMA Rmd files

**Date**: 2025
**Commit**: `3bf50fe`

**What was done**: Added detailed inline scientific comments to all code chunks in both SMA analysis files, supervised by ecology-user and enhanced-theory agent frameworks. Comments explain the purpose of each code block, the scientific rationale, how each step connects to MST/WBE scaling theory, and key caveats for non-expert readers.

**Files commented**:
- `cross_study_allometry_sma.Rmd`: load-data (part 2), hdbh-sma-table, hdbh-sma-dotplot, hdbh-ols-vs-sma, hdbh-scatter-sma, hdbh-pooled-sma, agb-sma-table, agb-sma-scatter, agb-ht-sma-table, all-exponents-summary, forest-plot
- `neon_growth_allometry_sma.Rmd`: load-data, ddD-global-sma, ddD-scatter-sma, ddD-binned-sma, dAGB-global-sma, dAGB-scatter-sma, per-site-sma, per-site-dotplot, per-site-ols-vs-sma, final-summary

**Recurring comment themes**:
1. smatr API: why two sma() fits per test (one per theoretical value), where slope and CI live in the coef matrix, p-value location in slopetest[[1]]$p
2. OLS vs SMA: attenuation bias explanation at every OLS comparison
3. AGB-DBH dependence: NEON AGBChojnacky caveat repeated in all AGB chunks
4. Positive-increment filter: why negative increments are excluded and what bias this introduces
5. Theoretical anchoring: WBE (2/3, 8/3), MST (1/3, 3/4), Chave 0.65 prediction sources cited in comments

2026-05-02 | Added PGLS (caper, V.PhyloMaker2), intraspecific vs interspecific scaling decomposition (Glazier 2005 framework), and per-family SMA/PGLS to kurosawa_respiration_scaling.Rmd. Demo data regenerated with 52 named species (10 APG IV families). All 65 chunks render clean. HTML: kurosawa_respiration_scaling.html (3.9 MB).
2026-05-02 | sapfluxnet_water_use_scaling.Rmd: Added six advanced scaling analysis sections (theoretical framework, site effects LMM, biome-stratified SMA, climate intercept modulation, size-range invariance, hydraulic normalisation constants). Packages: lme4, performance, quantreg. Rendered successfully.
2026-05-02 | Tallo BIEN export QA — full assessment of 498,838 records: coordinate precision issues (~38%% plot centroids), 12.3%% missing species, no date field, multi-stem diameter flag, T_481206 implausible height, lon=0 Quercus records, GADM reverse geocoding plan.
2026-05-02 | grand_cross_study_allometry.Rmd rendered successfully (7.3MB HTML). Bugs fixed during render: (1) phylo species cap 600 spp to prevent V.PhyloMaker2 timeout; (2) caper::pgls SE extraction via $VCV not vcov(); (3) phytools::phylosig atomic-vector guard in compute_signal(); (4) smatr coef as.numeric() wrappers throughout.
