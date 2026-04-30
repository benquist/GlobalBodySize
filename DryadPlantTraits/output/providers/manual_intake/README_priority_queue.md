# Priority Queue for Observation-Focused Manual Intake

Date generated: 2026-04-29

## Scope
This queue is derived from `data/manual_source_intake.csv` rows where `harvest_status == pending_review` after removing `manual_rainbio_central_africa`.

The queue includes only pending sources that are:
- observation-likely (`direct_observation` or `likely_observation`), or
- salvageable (`salvageable`) when a plausible path to observation records exists.

Checklist-only or registry-only sources are excluded from top ingest tiers and are retained only in `P3` when they can plausibly lead to observation-level data via linked repositories or follow-up.

## Output Columns
- `priority_tier`: `P1`, `P2`, `P3`
- `observation_readiness`: `direct_observation`, `likely_observation`, `salvageable`, `low`
- `likely_already_in_bien`: `yes`, `possible`, `no`
- `likely_bien_reason`: short heuristic rationale for BIEN overlap likelihood
- `queue_reason`: short rationale for queue placement
- `recommended_next_action`: concrete next ingest step

Additional copied context fields: `source_id`, `display_name`, `source_group`, `intake_type`, `canonical_url_or_doi`.

## Heuristic Caveat
`likely_already_in_bien` is a triage heuristic based on metadata text (`display_name`, `source_group`, `intake_type`, DOI/URL, notes) and known ingestion pathways. It is not a definitive duplication check and should be confirmed using BIEN-side key matching before ingestion.
