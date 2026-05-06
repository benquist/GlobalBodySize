# Tree Longevity Data Curation — Chat Provenance Log

## 2026-05-06
**Prompt:** Create a new project to curate published large datasets related to tree longevity, traits, and climate. Organize into separate folders, attempt downloads, and maintain a running .Rmd/.html catalog documenting each data source, summary, download status, issues, and steps needed. Starting datasets sourced from a tree longevity study spanning Figshare, ITRDB, GBIF, Zenodo, Dryad, TRY, WorldClim, CHELSA, and web-scraped oldlist sources.

**Agents:** scholarly-rigor-reviewer, biodiversity-science-guard, biodiversity-informatics-checker (framework design); coder (implementation); step-compliance-checker + always (gates).

**Key design decisions:**
- 20 dataset subfolders numbered 01–20 under `data/raw/`
- `catalog.Rmd` / `catalog.html` as the running summary document
- `logs/download_log.csv` (committed) tracks all download attempts with SHA-256 hashes
- All download scripts use `stop()` — no silent synthetic data fallbacks
- TRY data (D16) is not redistributable; GBIF download (D20) has 6-month expiry
- P50 sign convention must be audited before merging Datasets 13 and 14
- Web-scraped datasets (D4–D7, D9–D10) require ToS review and raw HTML archiving

**Files created:** README.md, .gitignore, catalog.Rmd, download_all.R, R/download_utils.R, R/qa_utils.R, R/catalog_utils.R, R/download_01_*.R through R/download_20_*.R, logs/download_log.csv, logs/qa_log.csv, chat_provenance_log.md
