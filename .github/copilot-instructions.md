# Copilot Instructions for biodiversity-agents-lab

## Repository overview

This repository is a biodiversity analysis workspace centered on agent-orchestrated science workflows, data provenance, and reproducible code. It contains multiple independent projects and tools rather than a single packaged application.

Key components:
- `BIEN-SpeciesShinyApp/` — standalone BIEN species Shiny app and deployment scaffolding.
- `BIEN-TraitsShinyApp/` — trait-focused Shiny app project.
- `Literature_Data_To_BIENdb/` — literature ingestion and BIEN occurrence pipeline.
- `DryadPlantTraits/` — trait ingestion, QA, and publication-grade data integration.
- `cacti/` — Cactaceae trait integration pipeline.
- `plant_body_mass_scaling_project/` — plant allometry literature synthesis.
- `random_BIEN_species/` — random BIEN species climate niche exploration workflow.
- `agents/` — agent prompts, provenance logs, and agent-related policies.

This repo uses prompt provenance logging heavily, with changes recorded in `agents/prompt_log.md`, `agents/agent_chat_provenance_log.txt`, and per-project `chat_provenance_log.md` files.

## Tech stack

- **R / Shiny**: primary analysis and visualization code.
- **R Markdown**: reports and reproducible narratives.
- **Data.table / terra / ggplot2**: common R libraries for data processing and geospatial work.
- **JavaScript / HTML**: some Shiny UI and static site content.
- **GitHub Actions / Git**: provenance and CI flow assumptions, though the repo may rely on manual project-level checks.

## What Copilot should do

- Prefer minimal, safe edits that respect agent provenance and existing project structure.
- Avoid adding large new infrastructure unless the user specifically requests it.
- Preserve scientific provenance, explicit data sources, and reproducibility statements.
- Use the Scientific Implementation Agent as the main working agent for building code, workflows, documentation, and reproducible project structure.
- Use the Scholarly Rigor Reviewer before merging pull requests, sharing code with collaborators, posting a repository publicly, submitting a manuscript, uploading a preprint, sending a report, freezing a dataset, or making strong claims in a README.
- Use the Scholarly Rigor Reviewer to audit citations, statistical inference, claims, and reproducibility before those actions.
- All scientific claims, citations, statistical analyses, and reproducibility claims must be reviewed by the Scholarly Rigor Reviewer before merging.
- Do not invent citations, DOIs, URLs, data sources, package functions, or results.
- All citations suggested need to be double checked for accuracy.
- Flag uncertainty explicitly.
- For code changes, ensure the relevant project-level workflow or `chat_provenance_log.md` is updated if appropriate.
- When asked about missing agents or files, search both `agents/` and `.github/agents/`.

## Repository conventions

- Agent definitions may live in both `agents/` and `.github/agents/`.
- User-facing provenance entries should be appended, not overwritten.
- New agent files should be added to both `agents/` and `.github/agents/` when visibility is important.
- Shiny apps and R projects are typically validated with `shiny::runApp()` or `Rscript` checks rather than a single repo-wide build.

## Usage guidelines

- When the user requests a file by path, create or update it exactly at that path unless they ask otherwise.
- When asked to explain the repository, summarize the main projects and provenance conventions.
- When asked to add a new agent, ensure the file is present in the visible agent folder the user is checking.
- If the user asks for work across multiple projects, clarify which top-level project should be treated as the target.

## Notes for editors

- Keep this file short and focused on repo-specific conventions.
- Do not include personal opinions or unrelated editorial content.
- Assume the workspace is a research-oriented monorepo with multiple biodiversity science projects.
