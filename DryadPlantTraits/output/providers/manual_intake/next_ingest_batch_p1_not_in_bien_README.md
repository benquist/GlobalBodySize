# next_ingest_batch_p1_not_in_bien.csv

## Filter logic

Derived from: `output/providers/manual_intake/priority_queue_observation_sources.csv`

Inclusion rules (both must be true):
- `priority_tier == "P1"`
- `likely_already_in_bien == "no"`

## Sort order (batch_order column)

1. `observation_readiness` priority: `direct_observation` → `likely_observation` → `salvageable` → `low`
2. Within same readiness tier: `source_id` ascending (alphabetical)

## Output

- Date generated: 2026-04-29
- Row count: 5
- All 5 rows are `observation_readiness = direct_observation`

## Sources included

| batch_order | source_id |
|-------------|-----------|
| 1 | manual_arroyo_high_andes_chile |
| 2 | manual_central_african_plot_network_cafriplot |
| 3 | manual_herbase_amazon_herbs |
| 4 | manual_red_argentina_parcelas_permanentes |
| 5 | manual_russian_arctic_vegetation_archive |
