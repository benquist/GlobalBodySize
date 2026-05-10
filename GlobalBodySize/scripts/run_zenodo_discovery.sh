#!/bin/zsh
## Run Zenodo discovery — call this as: zsh scripts/run_zenodo_discovery.sh
setopt NO_BANG_HIST
cd "$(dirname "$0")/.."
/usr/local/bin/Rscript scripts/discover_body_mass_datasets.R \
  --repos=zenodo \
  --pages-per-term=2 \
  --per-page=100 \
  --min-score=6 \
  > output/zenodo_discovery_log2.txt 2>&1
echo "Zenodo discovery complete. Exit: $?"
