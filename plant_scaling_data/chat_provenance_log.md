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
