# BIEN Shiny App Chat Provenance Log

Tracks prompts that created or changed work under this project folder.

## 2026-05-09 — Multi-agent UX/design redesign

**Prompt:** "@M orchestrate design proposal from @scandinavian-design, @design-atelier, @biodiversity-informatics-checker, @ecology-user for the BIEN Species Shiny app"

**Agents invoked:** ecology-user (use case analysis), biodiversity-informatics-checker (data quality audit), design-atelier + scandinavian-design (Nordic UI/UX spec)

**Changes implemented in `app.R`:**
- CSS flexbox `order` properties on `.nav-tabs > li:nth-child(N)` to visually reorder tabs: Occurrence 1st, Observations 2nd, Traits 3rd, Range 4th, Community 5th, Temporal 6th, Download 7th, External Links 8th, About & Help last — without changing server-side tab IDs.
- Renamed "Overview & About" tab to "About & Help".
- `uiOutput("taxon_match_banner_ui")` added above tabsetPanel — amber banner when BIEN-resolved name ≠ user input; shown on all tabs.
- `uiOutput("recon_callout_ui")` — compact above-map callout showing queried vs. BIEN-matched name and geographic scope.
- `uiOutput("qa_chips_bar_ui")` — pill-style QA chips bar: native/introduced/unknown record counts with amber warnings at >20% unknown or sampling cap active.
- `uiOutput("map_caption_ui")` — amber sampling-cap disclosure below occurrence map.
- Observations tab: added `disclosure-strip` explaining deduplication key (species+lat+lon+observation_type) and heuristic classification.
- Traits tab: added `disclosure-strip` for parsing exclusions (range notation → NA) and no-unit-harmonization warning.
- Range tab: upgraded SDM caveat to prominent left-bordered amber callout placed above the map.
- Community tab: replaced plain `tags$p` with `disclosure-strip` clarifying plot-only scope.
- New CSS classes: `.taxon-match-banner`, `.qa-chip`, `.qa-warn`, `.map-caption-row`, `.recon-callout`, `.disclosure-strip`, `.null-status-note`.
- Syntax verified: `parse('app.R')` passes cleanly.


## Entries

29. Date: 2026-05-08
Prompt: Yes, lets implement these changes — implement next-level recommendations: A2 (shared global cache), U3 (download provenance block), S1 (temporal trend plot), A1 (async BIEN queries), U2 (URL state).
Source session: current workspace session
Outcome: Three features implemented in app.R (S1 already existed; A1 deferred due to architectural risk):
  (1) A2 — Shared cross-session cache: Added `shared_bien_cache` environment, `get_shared_cache()`, and `set_shared_cache()` helpers at global scope. Cache uses 30-min TTL (SHARED_CACHE_TTL_SEC=1800L) and evicts oldest entries over 50-key limit. In `bien_results_live()`: session cache is checked first (fastest), then shared global cache (cross-session hit), then a fresh BIEN query which populates both caches. Popular species now warm instantly across all sessions.
  (2) U3 — Download provenance headers: All three CSV download handlers (occurrence, trait, plot community) now prepend comment lines to the file before writing data. Comments include: species name, UTC download timestamp, filter profile, natives-only and geo-valid flags (occurrence download), BIEN R package version, and app source URL. Uses writeLines() + write.table(append=TRUE) to avoid overwriting CSV headers.
  (3) U2 — URL state: Startup observeEvent(TRUE, once=TRUE) now reads ?species= and ?tab= URL parameters using parseQueryString(session$clientData$url_search). If species is provided, pre-populates the species input; if tab is provided and valid, switches to that tab. A new observeEvent(list(input$species, input$main_tabs)) observer keeps the URL query string synchronized (mode="replace") so users can copy/share bookmarkable links.

27. Date: 2026-05-08
Prompt: Implement Tier 1 science and Tier 2 performance fixes — SC-1, SC-2, H1, H2, H3.
Source session: current workspace session
Outcome: Five fixes applied to app.R:
  (1) SC-1 accuracy — sidebar checkbox "Keep native only" relabeled to "Keep native / unknown-status only"; tooltip updated; Help modal text updated. Accurately reflects that natives_check_with_null_fallback() includes is_introduced IS NULL records (unclassified), not strictly native-only.
  (2) SC-2 SDM caveat — added amber warning banner to Range tab UI explicitly stating BIEN range polygons are SDM model outputs, not verified native range boundaries. Updated Overview map fallback notice with same caveat.
  (3) H1 performance — moved load_accepted_species_suggestions(timeout_sec=60) from per-session observeEvent(TRUE, once=TRUE) to global scope as startup_species_suggestions. Eliminates up to 60s per-session autocomplete stall; all sessions now reuse the preloaded list instantly.
  (4) H2 performance — removed ORDER BY random() from fetch_random_bien_species_pool() SQL (was a full-table sort on 100M+ rows). Now fetches 5x pool_size in natural order and shuffles with sample.int() in R.
  (5) H3 performance — added evict_lru_cache() and set_cache() LRU helpers. Replaced bare assign() for query_cache, trait_cache, and range_cache with set_cache() (max 8 keys each). get_cached_result() now records access timestamps for LRU tracking.

28. Date: 2026-05-08
Prompt: For https://benquist.shinyapps.io/bien-species-shinyapp/ The front page when one immediately loads the app, the observation data points for Pinus ponderosa take a long time to load. It would be great if the observation points loaded immediately.
Source session: current workspace session
Outcome: Moved `build_preloaded_startup_result()` and its call from inside `server <- function(...)` to global scope (before the server function). Previously this ran per-session, re-reading CSVs, running `categorize_observation_records`, `prepare_occurrences`, and `st_read()` for every new user session. Now it runs once at app launch and the result is shared across all sessions via R's lexical scoping, eliminating the per-session startup delay and making observation points appear immediately on first load.

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

12. Date: 2026-04-01
Prompt: Confirm whether BIEN is truly down versus an app issue, then add a retry mechanism when connection-capacity errors occur.
Source session: current workspace session
Outcome: Confirmed the BIEN public database connection-slot error with direct BIEN package calls outside the app UI, then added a `Retry BIEN connection (with backoff)` button and exponential-backoff retries in the occurrence query path, plus README guidance for using this retry workflow.

13. Date: 2026-04-09
Prompt: On the shiny app, for the Settings Filters toggle, the information symbol is not working on hover or click; add pertinent information for each toggle.
Source session: current workspace session
Outcome: Updated filter/help labels to use initialized Bootstrap tooltips and added client-side tooltip initialization so each info icon now shows its explanatory text on hover, focus, or click.

14. Date: 2026-04-09
Prompt: Yes (apply the offered wording improvements for settings tooltip text).
Source session: current workspace session
Outcome: Revised Settings/Filters tooltip copy to be more ecologically explicit, including clearer native/introduced, cultivated, plot-only, geovalid, and human-observation guidance.

15. Date: 2026-04-09
Prompt: Just checked the shiny app and it did not work; please check.
Source session: current workspace session
Outcome: Added cross-framework tooltip compatibility (Bootstrap data attributes plus framework-independent JavaScript fallback tooltip behavior) so Settings info icons work on hover/focus/click even when Bootstrap tooltip plugins are unavailable or version-mismatched, then redeployed to shinyapps.io and confirmed the app is running.

16. Date: 2026-04-09
Prompt: Looks like the shiny app is frozen.
Source session: current workspace session
Outcome: Diagnosed timeout logs tied to sequential BIEN COUNT prechecks in the random-species workflow, changed Lucky selection to an instant curated pick with no blocking BIEN precheck queries, and redeployed to shinyapps.io.

17. Date: 2026-04-09
Prompt: Tooltip hover info now shows two popups (white and black), and the black one does not disappear on mouse leave.
Source session: current workspace session
Outcome: Removed Bootstrap/native tooltip attributes and Bootstrap tooltip initialization from settings info icons so only one custom tooltip system renders and dismisses cleanly.

18. Date: 2026-04-09
Prompt: For the BIEN shiny app species external links, add a link to the species iNaturalist page in addition to other sites.
Source session: current workspace session
Outcome: Added an iNaturalist external-link card to the Species External Links panel, using the current species name to generate an iNaturalist taxon search URL while preserving the existing Wikipedia, POWO, Missouri Botanical Garden, and World Flora Online links.

19. Date: 2026-04-09
Prompt: Add AsianPlant.net to Species External Links, but only show the link when the queried species occurs on that site.
Source session: current workspace session
Outcome: Added a cached AsianPlant species-index lookup from asianplant.net/Species.htm and rendered an AsianPlant external-link card only when an exact binomial match exists for the current species.

## Update Rule
Append a new entry whenever prompts lead to created/modified app code, BIEN query logic, or documentation under BIEN Shiny App/.

20. Date: 2026-04-09
Prompt: Add more species to the random species select list (Capparis micracantha, Clappertonia ficifolia, Dacryodes costata, Ilex cymosa, Lasianthus attenuatus, Ochrosia elliptica, Popowia pisocarpa, Quassia indica, Aquilegia coerulea).
Source session: current workspace session
Outcome: Appended nine new species to the curated random-species starter pool used by the random species button.

21. Date: 2026-04-12
Prompt: Update the Overview/About Occurrence Map copy to mention toggling geo-validated and native/non-native records.
Source session: current workspace session
Outcome: Replaced the Occurrence Map card description text with the requested wording focused on species-level records and filter toggles.

22. Date: 2026-04-13
Prompt: We have an error message in the Temporal Distribution tab: "Temporal stats - An error has occurred. Check your logs or contact the app author for clarification." Why is this? Can you fix it?
Source session: current workspace session
Outcome: Fixed a NULL-reference error in the `output$temporal_stats <- renderUI({...})` handler that occurred when bien_results() returned NULL (e.g., before any species query). Added `req(bien_results())` to gracefully prevent rendering until valid results are available, matching the pattern used in other reactive handlers in the app.

23. Date: 2026-04-13
Prompt: I dont think the error is fixed. We are still seeing it
Source session: current workspace session
Outcome: Diagnosed the remaining Temporal stats runtime error from shinyapps logs (unsupported `sprintf("%,d")` format in `output$temporal_stats`). Replaced it with a safe thousands-separated label via `format(..., big.mark = ",")`, then redeployed the app.

24. Date: 2026-04-14
Prompt: For the BIEN shiny app, timeouts/blank maps still happen for species like Capparis micracantha and Ochrosia elliptica under Conservative default profile; make it clear when effective query settings are auto-relaxed.
Source session: current workspace session
Outcome: Added explicit "Requested vs effective BIEN profile" messaging in query summary and adjusted Lucky-mode query planning to keep fallback strategies enabled (`max_plans = 3`, shorter per-plan timeout) so strict timeouts can still auto-relax and recover mappable records in the same query run.

25. Date: 2026-04-14
Prompt: Annona montana still loads slowly then returns a blank map; auto-run one relaxed fallback pass on timeout or zero mappable points, and notify users when effective settings are auto-relaxed.
Source session: current workspace session
Outcome: Added automatic strict-to-relaxed-geo fallback trigger when strict run yields zero mappable coordinates or timeout indications, while preserving the visible conservative toggle as requested. Added explicit warning notifications describing that conservative remained selected but effective query settings were auto-relaxed to recover records/map points.

26. Date: 2026-04-21
Prompt: bien shiny app I would like to now work on https://benquist.shinyapps.io/bien-species-shinyapp/ For the Species name look up I would like to add a auto look up name based on the accepted species names in the BIEN db We just added such a feature in https://benquist.shinyapps.io/bien-traits-shinyapp/
Source session: current workspace session
Outcome: Replaced the Species name free-text control with a BIEN-backed selectize autocomplete that loads accepted species names from BIEN taxonomy, disables ad-hoc free creation, and keeps random-species selection integrated with the new lookup input.

27. Date: 2026-04-21
Prompt: yes deploy
Source session: current workspace session
Outcome: Deployed BIEN-SpeciesShinyApp to shinyapps.io via deploy_safe.R and verified the public URL loaded the updated app UI successfully.

28. Date: 2026-04-21
Prompt: Something is not working with the entry of text in the box. I start typing and the text dissapears. There also seems to be an arrow in the far right hand side that cannot be clicked
Source session: current workspace session
Outcome: Fixed the Species autocomplete so the selectize control initializes accepted BIEN names once at session start instead of reloading on every keystroke, which stopped typed text from disappearing and restored normal dropdown behavior.

29. Date: 2026-04-21
Prompt: I would like the species name box to be larger
Source session: current workspace session
Outcome: Enlarged the Species name control by widening its sidebar column and increasing the selectize field height and font size so the lookup box is easier to use.

30. Date: 2026-04-21
Prompt: When I launch the app, Pinus ponderosa should come up first populating the species name, but it doesn't show in the box even though the map appears.
Source session: current workspace session
Outcome: Fixed startup species not displaying by initializing selectizeInput with STARTUP_SPECIES in the choices list instead of NULL, so the startup value displays immediately while the once-per-session observer loads all accepted BIEN names and keeps it selected.

31. Date: 2026-04-21
Prompt: What BIEN source populates species-name autofill, and why does typing Sciadoden not match Sciadodendron?
Source session: current workspace session
Outcome: Confirmed autocomplete source is BIEN `bien_taxonomy.scrubbed_species_binomial` with accepted-status filtering; removed the hard 75,000-name SQL limit so later-alphabet accepted species (including Sciadodendron) are included in suggestions.

32. Date: 2026-04-21
Prompt: Add a popup warning when a species name is found in BIEN taxonomy but no mappable occurrence points are available under current filters.
Source session: current workspace session
Outcome: Added query-time popup warning logic that checks BIEN taxonomy presence (with session caching) and shows a clear warning when mappable points are zero under active filters.

32. Date: 2026-04-21
Prompt: Make the Query, random species, and Help controls in BIEN-SpeciesShinyApp feel more like real buttons (similar to BIEN-TraitsShinyApp), and move random species below the species name box.
Source session: current workspace session
Outcome: Updated Species app sidebar layout so random species appears under the species field, and added raised gradient button styles for Query, random species, and Help to match the stronger Traits-style click affordance; redeployed to shinyapps.io.

29. Date: 2026-04-21
Prompt: The random species button is no longer populating the species text automatically
Source session: current workspace session
Outcome: Fixed the random-species and BIEN name-suggestion flows so the selected species is injected into the selectize choices before selection, restoring automatic species-field updates.

30. Date: 2026-04-21
Prompt: When I type "Pinus pinderosa" (a misspelling) and hit Query nothing is returned, even with "Suggest closest match" checked.
Source session: current workspace session
Outcome: Root cause was selectize create=FALSE preventing free-form text submission — misspelled names could never reach the server. Fixed by setting create=TRUE, createOnBlur=TRUE so typed-but-unmatched names are submitted as-is. The existing find_best_species_spelling() fuzzy logic now runs and surfaces "Pinus ponderosa" as a high-confidence suggestion. Deployed to shinyapps.io.

31. Date: 2026-04-21
Prompt: Standardize BIEN-SpeciesShinyApp so its tabs, header, BIEN logo placement, fonts, buttons, and color palette match BIEN-TraitsShinyApp more closely, with the BIEN logo always first on the left.
Source session: current workspace session
Outcome: Reworked the Species app header to use the Traits-style branded page header with the BIEN logo first on the left, aligned typography and color tokens to the Traits portal, and ported the Traits tab/button visual language while preserving the Species app sidebar, tab structure, and server behavior. Deployed to shinyapps.io.

32. Date: 2026-04-24
Prompt: Implement targeted app.R changes for random-species responsiveness, remove post-query blocking taxonomy lookup, and remove the Ingest to BIEN tab plus active ingest server handlers.
Source session: current workspace session
Outcome: Added a guaranteed starter-pool fast fallback (`starter_pool_fast_fallback`) in `find_lucky_species_with_mappable_points()` after verified attempts fail, removed `taxonomy_species_exists()` from the zero-mappable notification gate, deleted the `Ingest to BIEN` tab UI block, removed `ingest_bundle <- reactiveVal(NULL)`, removed the ingest analyze observeEvent and all ingest render/download outputs, and verified `app.R` parses successfully.

33. Date: 2026-04-24
Prompt: Edit BIEN-SpeciesShinyApp app.R with two targeted changes: make Random Species immediate and remove leftover ingest-associated function.
Source session: current workspace session
Outcome: Replaced the starter-pool precheck loop in `find_lucky_species_with_mappable_points()` with immediate random return (`precheck = "starter_pool_fast_pick"`, `attempts = 1`) and removed the full `run_ingest_workflow <- function(file_info) { ... }` block; parse check confirmed `SYNTAX OK`.

34. Date: 2026-04-24
Prompt: Edit BIEN-SpeciesShinyApp/app.R to address two review warnings and one cleanup: conditional lucky notification by precheck state, neutral zero-mappable wording, and removal of dead taxonomy cache/helper.
Source session: current workspace session
Outcome: Updated Lucky notification text to reflect `lucky$precheck` (`range-map verified` vs `fast starter pick; range verification skipped`), replaced zero-mappable opener with neutral filter-based wording, removed `taxonomy_presence_cache` and `taxonomy_species_exists`, and verified `app.R` parse passes.

30. Date: 2026-05-08
Prompt: Yes (implement suggested changes: U4 copy-link, SC-3 cache-hit badge, D1 zip download).
Source session: current workspace session
Outcome: Three features added to app.R (commit f22bcdf, bundle 11967856, image 14900088):
  (1) U4 — Copy link button: Added '🔗 Copy link' button next to Help using vanilla JS navigator.clipboard.writeText(window.location.href). Shows 1.8s 'Copied!' feedback. Falls back to window.prompt for non-HTTPS contexts. Works with U2 URL state so the copied link pre-loads the same species and tab.
  (2) SC-3 — Cache-hit badge: query_summary now displays a green '⚡ Cache hit — X.X min old' badge at the top when results come from either the per-session or shared cross-session cache. Badge shows age in minutes computed from shared_bien_cache$cached_at timestamp. Invisible on fresh queries.
  (3) D1 — ZIP download bundle: New green 'Download all datasets + code (.zip)' button added at the top of the Download tab. Bundles occurrence CSV, trait CSV, plot community CSV + 3 reproducible R scripts into a timestamped .zip file. All CSVs include provenance header block. Uses setwd(tmp_dir) + on.exit cleanup so zip() paths are clean relative paths.

35. Date: 2026-05-09
Prompt: https://benquist.shinyapps.io/bien-species-shinyapp/ does not work now. I would like the optimizer.agent.md and code-checker.agent.md to review the shiny app code and recommend fixes.
Source session: current workspace session
Outcome: Two CRITICALs diagnosed and fixed in app.R (commit 0bc1ec7, bundle 11968347):
  (1) CRITICAL — Synchronous HTTP fetch inside renderUI blocked the Shiny event loop at session startup. Because bien_results() immediately returns startup_preloaded_result, renderUI fired during the initial render flush and called fetch_species_photo() synchronously — up to 10 seconds blocking on shinyapps.io free tier (5s iNaturalist + 5s Wikipedia), causing startup timeouts and session disconnects. Fix: photo fetch moved into observeEvent(bien_results(), ..., ignoreNULL=TRUE) with an is_startup_preloaded guard that returns immediately at startup. renderUI now reads only from species_photo_rv <- reactiveVal(NULL) — no network I/O in the render path.
  (2) CRITICAL — return(NULL) inside both tryCatch({...}) blocks exited the enclosing function rather than the tryCatch block, making the Wikipedia fallback unreachable for every failure mode except a thrown R exception. Fix: replaced all return(NULL) guards inside tryCatch with stop("reason") so the error = function(e) NULL handler returns NULL from the block and execution continues to Wikipedia.
  Additionally: NULL results are no longer cached permanently; only non-NULL photos are assigned to query_cache so transient network failures are retried on the next query.
  App redeployed and working. Commits 0bc1ec7 + 757da51 pushed to origin/master.
Sat May  9 00:14:40 BST 2026: Fixed zero-mapped-coord bug for species like Pouteria reticulata where BIEN returns a mix of coord-valid and coord-null rows. The stratified datasource sampler was selecting predominantly null-coord rows. Fix prioritizes coord-valid rows in the app-level downsample (occ_limit) before prepare_occurrences QA. See app.R ~line 3300.
Sat May  9 2026 (v2): Added SQL-level coord filter plan (fallback_coord_bearing: AND latitude IS NOT NULL) as 4th cascade step in query_occurrence_with_fallback(). Intent: force BIEN to return only lat/lon-bearing rows when strict plan returns 0 mappable. Outcome: made things worse — for Pouteria reticulata BIEN has NULL lat/lon for ALL records in the view, so coord_bearing also returned 0 rows and the strict plan's 2000-record result was discarded entirely, leaving users with 0 records shown. Commit f670207.
Sat May  9 2026 (v3): Root cause confirmed: BIEN view stores is_geovalid=1 but latitude/longitude columns are NULL for every Pouteria reticulata record — a BIEN data quality issue. Fix: added best_nonempty_result tracking in query_occurrence_with_fallback(). When coord_bearing exhausts with 0 rows, returns the first non-empty result from an earlier (non-coord-bearing) plan using that plan's actual strategy label (not a synthetic label — coder agent identified that a synthetic "no_coords_available" label would corrupt repro scripts and count queries). UI detects the condition via "no_coord_bearing_records_in_bien_view" in query_errors notes and shows an amber banner explaining the BIEN data quality issue. Statistics table is populated; map is correctly empty. Syntax verified, deployed, commit bef6b74 pushed to origin/master.
