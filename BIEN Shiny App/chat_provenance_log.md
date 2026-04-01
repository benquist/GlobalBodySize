# BIEN Shiny App Chat Provenance Log

Tracks prompts that created or changed work under this project folder.

## Entries

1. Date: 2026-03-30
Prompt: Lets create a new project in a new folder called BIEN Shiny App. Use the BIEN R Package for biendata.org. I would like to make a shiny app where we a user can query for a given species and the shiny app then plots the observation points on a map. THe map can be scaled at different geographic scales. Suggest some important ways that one can explore the species level data for each species. You can query species for traits, and geographic ranges too. The shiny app will allow the user to explore species-level observation data
Source session: current workspace session
Outcome: Created a new BIEN-based Shiny app project with species query, occurrence mapping, trait exploration, range query display, and project documentation.

2. Date: 2026-04-01
Prompt: For the Overview tab, move the occurrence map and the summary statistics onto separate tabs, with the occurrence map first on the tab bar and the statistics after it.
Source session: current workspace session
Outcome: Updated the Shiny UI so the first tab now leads with the occurrence map and the summary statistics appear in their own separate tab.

3. Date: 2026-04-01
Prompt: Speed up slow BIEN species queries, explain to users why some species take longer, and rewrite the native/introduced, cultivated, and geovalid toggles so it is clear which occurrence records are being shown or hidden.
Source session: current workspace session
Outcome: Updated the app with clearer filter labels, more explicit progress/wait messaging, query timing reporting, session caching for repeated searches, and a slower optional range lookup that is now off by default.

4. Date: 2026-04-01
Prompt: Do a second-pass speed optimization focused on lazy-loading BIEN trait and range data only when those tabs are opened.
Source session: current workspace session
Outcome: Refactored the app so the first query now loads occurrences and summary counts first, while the Traits and Range tabs fetch their BIEN data on demand and reuse cached results afterward.

5. Date: 2026-04-01
Prompt: The Shiny app is hung up and frozen.
Source session: current workspace session
Outcome: Removed the count-only BIEN summary queries from the first-load critical path and moved them to on-demand loading in the Summary Statistics tab so the app stays responsive sooner.

6. Date: 2026-04-01
Prompt: Push the new BIEN app details to GitHub, make sure the README is detailed, and add a summarized statement of what records the user is looking at based on the selected filters, including the default biodiversity-oriented setting.
Source session: current workspace session
Outcome: Added a plain-language filter summary panel to the app sidebar, documented the default conservative ecological filter profile and on-demand loading behavior in the README, and prepared the BIEN app updates for GitHub publication.

7. Date: 2026-04-01
Prompt: The app froze again, especially around Summary Statistics.
Source session: current workspace session
Outcome: Changed the BIEN count-only total and source-fraction fetch to a manual button-triggered action in the Summary Statistics tab so opening the tab no longer blocks the whole app.

8. Date: 2026-04-01
Prompt: Make sure the code is commented, README files are updated and useful, clarify that users must click Query BIEN again after changing filters, and push the latest BIEN app updates to GitHub.
Source session: current workspace session
Outcome: Added clearer inline comments to the Shiny app code, expanded the BIEN app README and workspace README, added an explicit re-query notice for filter changes, and prepared the latest app polish updates for publication.

9. Date: 2026-04-01
Prompt: Investigate why some species such as `Juniperus communis` and `Pinus ponderosa` appear overly dominated by plot/FIA records in the returned occurrence sample, and fix the sampling bias if possible.
Source session: current workspace session
Outcome: Verified that the old BIEN occurrence fetch was pulling the first backend rows without randomized ordering, then updated the app to use a randomized occurrence query and exclude trait-linked rows from the main occurrence map/table so the sample better reflects the full BIEN matching pool.

10. Date: 2026-04-01
Prompt: Add balanced occurrence-display sampling by datasource or observation type, then investigate why `Juniperus communis` returned no observations during live app testing.
Source session: current workspace session
Outcome: Added stratified display-sampling controls for occurrence maps/tables, confirmed that the live failure was caused by BIEN public database connection-slot exhaustion rather than a true species-level absence, and updated the app to show a clear backend-capacity warning with retry guidance.

11. Date: 2026-04-01
Prompt: Clarify whether the BIEN app changes were being pushed to the wrong repository and separate the mixed repo setup if needed.
Source session: current workspace session
Outcome: Verified that the BIEN app folder was still nested under the `biodiversity-agents-lab` monorepo, then synced the current app files into the dedicated `BIEN-SpeciesShinyApp` repository so future BIEN app work can be maintained separately.

## Update Rule
Append a new entry whenever prompts lead to created/modified app code, BIEN query logic, or documentation under BIEN Shiny App/.
