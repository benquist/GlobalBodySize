# sPlot Open Data

Purpose: Organize open-data discovery, retrieval, and processing for the sPlotOpen global vegetation-plot dataset.

## Goal

Build a clear, repeatable workflow for downloading, documenting, and preparing sPlotOpen for downstream analysis (trait-environment relationships, climate niche modeling, global diversity patterns).

---

## Canonical Dataset

| Field            | Value |
|------------------|-------|
| **Name**         | sPlotOpen — An environmentally-balanced, open-access, global dataset of vegetation plots |
| **Version**      | 2.0 (latest public; internal version 76) |
| **DOI**          | 10.25829/idiv.3474-40-3292 |
| **Landing page** | https://idata.idiv.de/ddm/Data/ShowData/3474?version=55 |
| **Download**     | https://idata.idiv.de/ddm/Data/DownloadZip/3474?version=5779 |
| **Size**         | ~8 GB (full zip) |
| **License**      | CC BY (acceptance of data policy required on portal) |
| **Host**         | iDiv Data Management Platform (iData), German Centre for Integrative Biodiversity Research |
| **Reference**    | Sabatini et al. 2021, Global Ecology and Biogeography, doi:10.1111/geb.13346 |

---

## Data Content (sPlotOpen v2.0)

sPlotOpen is an environmentally-balanced subset of the full sPlot database (v2.1), containing:
- Global vegetation plots with species cover/abundance data
- Plot-level metadata (location, date, sampling design, biome)
- Derived environmental variables per plot
- Taxonomically standardized species names

Key tables (inside the downloaded zip):
- `sPlotOpen_header.RData` — plot metadata (lat/lon, date, biome, country, etc.)
- `sPlotOpen_DT.RData` — species-by-plot data table (cover values)
- `sPlotOpen_TRY.RData` — linked TRY trait data per plot-species
- `sPlotOpen_Metadata.xlsx` — field descriptions

---

## Data Sources and Repositories

| Resource | URL |
|----------|-----|
| iDiv data portal (canonical) | https://idata.idiv.de/ddm/Data/ShowData/3474?version=55 |
| Manuscript repo | https://github.com/fmsabatini/sPlotOpen_Manuscript |
| Code repo (construction workflow) | https://github.com/fmsabatini/sPlotOpen_Code |
| Published paper | https://onlinelibrary.wiley.com/doi/10.1111/geb.13346 |

---

## Access Notes

- **Download requires manual agreement** to the iDiv data policy on the landing page before the zip link activates.
- The full zip (~8 GB) contains RData files; R is the primary analysis environment.
- No Zenodo mirror was found as of 2026-04-28; iDiv iData is the sole official source.
- The iDiv ShowData/3 (old URL) returns HTTP 500; use ShowData/3474 (the correct numeric ID).

---

## Next Steps

- [ ] Download the full zip after accepting data policy on the landing page
- [ ] Unpack and inventory the RData files
- [ ] Write an R script to load and inspect header + DT tables
- [ ] Document schema and column definitions from Metadata xlsx
- [ ] Align species names against BIEN/TRY taxonomy if joining with other trait sources
- [ ] Add scripts for climate extraction and diversity-metric computation
