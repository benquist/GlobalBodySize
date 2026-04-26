# Workspace Agent Policy

## Mandatory Final Gate
Before returning any result to the user, run the always agent as the final pre-return check.

## Required Pass Condition
Do not return to the user unless always reports PASS.

## Always Agent Scope
The always agent must verify all of the following:
- Prompt is recorded in agents/prompt_log.md
- Updated Rmd files compile successfully
- Updated R packages build successfully
- Git push status is confirmed

## Update Discipline
If the task changed agent behavior or agent files, append a new entry to:
- agents/agent_chat_provenance_log.txt

## Architecture
- This is a biodiversity monorepo with multiple independent projects (Shiny apps, R packages, Rmd analyses, ETL workflows).
- Treat each top-level project as a separate build/deploy target with its own conventions and provenance file.
- Primary app targets are BIEN-SpeciesShinyApp and BIEN-TraitsShinyApp; both deploy via shinyapps.io.

## Build And Test
- Shiny local run:
	- `shiny::runApp("BIEN-TraitsShinyApp")`
	- `shiny::runApp("BIEN-SpeciesShinyApp")`
- Deploy pattern: use each project's `deploy.R` and `rsconnect::deployApp(...)`.
- R package check trigger: if a changed project has `DESCRIPTION`, run package build/check for that changed project.
- Rmd trigger: if `.Rmd` files changed, render and verify them before return.
- Cacti ETL run command: `PATH="/opt/homebrew/bin:$PATH" Rscript cacti/scripts/fetch_cacti_traits.R`.

## Conventions
- Keep prompt provenance current in `agents/prompt_log.md` for user prompts that drive implementation.
- Keep per-project provenance current in `<project>/chat_provenance_log.md` when that project is changed.
- Prefer explicit ecological/data-quality transparency:
	- Do not hide record caps, filters, QA losses, or fallback behavior.
	- Preserve taxonomic reconciliation outputs and source/citation fields in exports.
	- Treat native/introduced/cultivated interpretations as context-dependent, not absolute truth.
- For complex multi-step work, route through specialist agents (for example `m`, `code-checker`, `code-verifier`, `biodiversity-science-guard`, `stats-specialist`, `bio-units-specialist`) before final gate.

## Linked Docs
- Workspace overview: `README.md`
- BIEN Species app workflow and scientific caveats: `BIEN-SpeciesShinyApp/CODE_WORKFLOW_DOCUMENTATION.md`
- BIEN Species taxonomy strategy: `BIEN-SpeciesShinyApp/TAXONOMY_INTEGRATION_STRATEGY.md`
- BIEN Traits app usage/deploy notes: `BIEN-TraitsShinyApp/README.md`
- Cacti trait pipeline details: `cacti/README.md`
