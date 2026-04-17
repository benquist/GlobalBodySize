# Chat Provenance Log

- Date: 2026-04-17
- Prompt summary: Create a new project folder for the BIEN trait shiny app, then scaffold it into a full Shiny project structure.
- Requested outcomes: Build runnable app scaffold with app.R, R helpers/UI/server modules, and deployment script.
- Completed by: GitHub Copilot

- Date: 2026-04-17
- Prompt summary: Confirm migration of full production BIEN trait app feature set into BIEN-TraitsShinyApp-Project.
- Requested outcomes: Replace scaffold entrypoint with full production app code and align deploy script to new project path.
- Completed by: GitHub Copilot

- Date: 2026-04-17
- Prompt summary: Deploy BIEN-TraitsShinyApp-Project to shinyapps.io.
- Requested outcomes: Execute deployment with forceUpdate=TRUE, verify app is live at https://benquist.shinyapps.io/bien-traits-shinyapp/, and update provenance.
- Completed by: GitHub Copilot

- Date: 2026-04-17
- Prompt summary: Redesign BIEN Traits app filter UX: show all traits by default, display counts by filter combo, filter only on download.
- Requested outcomes: Query with no filters, show unfiltered traits + filter counts in Coverage tab, apply filters only when user downloads.
- Completed by: GitHub Copilot

- Date: 2026-04-17
- Prompt summary: Fix zero-trait-record bug and add error diagnostics.
- Requested outcomes: Capture and report errors that were previously silent; test Pinus ponderosa query; redeploy with fixes.
- Completed by: GitHub Copilot

- Date: 2026-04-17
- Prompt summary: Fix Pinus ponderosa zero-results when user enters mixed common+scientific name text.
- Requested outcomes: Extract scientific binomial from mixed text input and redeploy.
- Completed by: GitHub Copilot

- Date: 2026-04-17
- Prompt summary: Fix lingering Pinus ponderosa empty-table behavior after prior patch.
- Requested outcomes: Reinstate max_records limit in BIEN_trait_species query to prevent oversized query failures/timeouts and redeploy.
- Completed by: GitHub Copilot

- Date: 2026-04-17
- Prompt summary: Add a GitHub-ready README with a practical tutorial for BIEN Trait Shiny App users.
- Requested outcomes: Expand project documentation with setup steps, usage guidance, worked tutorial, troubleshooting, and deployment notes.
- Completed by: GitHub Copilot

- Date: 2026-04-17
- Prompt summary: Publish BIEN Trait Shiny App as a standalone GitHub repository named BIEN_Trait_Shiny_App.
- Requested outcomes: Prepare the project for standalone publication, ensure README is at repo root, and push the project to its own GitHub repository.
- Completed by: GitHub Copilot
