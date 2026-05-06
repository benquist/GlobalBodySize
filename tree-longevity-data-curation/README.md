# Tree Longevity Data Curation Project

A curated collection of published large datasets supporting tree longevity, traits, and climate research. Each dataset is organized in its own subfolder with a standardized download script and QA manifest.

## Structure

```
tree-longevity-data-curation/
├── catalog.Rmd          # Master running catalog (render to catalog.html)
├── catalog.html         # Rendered output (committed)
├── download_all.R       # Orchestrator — calls all per-dataset scripts
├── R/
│   ├── download_utils.R # Shared helpers: API calls, manifest writing, hash
│   ├── qa_utils.R       # Unit checks, coordinate validators, DwC audits
│   └── catalog_utils.R  # Catalog status badge helpers
├── data/raw/            # Gitignored — immutable once downloaded
│   ├── 01_main_study/   # Figshare 29876984
│   ├── 02_itrdb/        # NOAA ITRDB tree ring data
│   ├── ...              # (20 dataset subfolders)
│   └── 20_gbif_occurrence/
├── logs/
│   ├── download_log.csv # One row per download attempt
│   └── qa_log.csv       # Per-dataset QA results
└── chat_provenance_log.md
```

## Datasets Cataloged

| # | Dataset | Status |
|---|---------|--------|
| 01 | Main study longevity/traits/climate (Figshare 29876984) | see catalog |
| 02 | ITRDB tree ring data (NOAA) | see catalog |
| 03 | Tropical tree rings — Locoselli et al. 2020 (Figshare) | see catalog |
| 04 | OldList West (RMTRR) | see catalog |
| 05 | OldList East (LDEO) | see catalog |
| 06 | Native Tree Society dendro ages | see catalog |
| 07 | Old Growth Canada | see catalog |
| 08 | Tree height (Zenodo 6637599) | see catalog |
| 09 | Conifer max height (conifers.org) | see catalog |
| 10 | MonumentalTrees max height | see catalog |
| 11 | Wood density (Zenodo 13322441) | see catalog |
| 12 | Wood density (CIRAD DataVerse) | see catalog |
| 13 | Conduit density + P50 + HSM (Dryad) | see catalog |
| 14 | P50 + HSM additional (Science Advances supp.) | see catalog |
| 15 | GLOPNET leaf traits (Wright et al. 2004) | see catalog |
| 16 | Seed mass (TRY request 30569) | see catalog |
| 17 | TreeGOER climate/soil (Zenodo 10008994) | see catalog |
| 18 | WorldClim 2.1 gridded climate/elevation | see catalog |
| 19 | CHELSA growing season + NPP | see catalog |
| 20 | GBIF species occurrence (dl.77gcvq) | see catalog |

## Usage

```r
# Render the catalog
rmarkdown::render("catalog.Rmd")

# Run all downloads (will skip already-downloaded files)
source("download_all.R")

# Run a single dataset download
source("R/download_01_main_study.R")
```

## Design

Framework designed by scholarly-rigor-reviewer, biodiversity-science-guard, and biodiversity-informatics-checker agents (2025-05-06). See `agents/prompt_log.md` for provenance.

## Data Policy

- `data/raw/` is gitignored. Downloads are tracked via `logs/download_log.csv` (committed).
- Each download script writes a companion `*_manifest.txt` (filename, URL, SHA-256, timestamp).
- No simulated data fallbacks — scripts `stop()` if real data are absent.
- TRY data (Dataset 16) cannot be redistributed; see `data/raw/16_try_seed_mass/README_try_download.txt`.
- GBIF downloads (Dataset 20) expire after ~6 months; re-download instructions in catalog.
