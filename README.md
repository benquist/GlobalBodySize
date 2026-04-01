# biodiversity-agents-lab

Agent-orchestrated biodiversity analysis workspace with species distribution modeling, biodiversity informatics pipelines, Shiny apps, and prompt provenance logging.

## Main workspace projects

- **`BIEN Shiny App/`** — interactive BIEN-based species exploration app for occurrence, trait, range, provenance, and QA review.
- **`calipoppySDM/`** and `california_poppy_sdm.Rmd` — California poppy SDM workflow and package resources.
- **`cacti/`** — Cactaceae trait-integration and provenance pipeline.
- **`plant_body_mass_scaling_project/`** — literature synthesis and screening workflows for plant allometric scaling.
- **`EvoPowerEfficiencyExplorer/`** — evolutionary power-efficiency Shiny/package work.

## Repository notes

- Agent and prompt provenance are logged under `agents/` and project-level `chat_provenance_log.md` files.
- The BIEN Shiny app is currently organized for fast occurrence-first loading, with traits, range layers, and optional BIEN total counts loaded on demand.
- This monorepo contains multiple related biodiversity projects rather than a single standalone application.

