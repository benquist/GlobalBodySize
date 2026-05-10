#!/usr/bin/env zsh
setopt NO_BANG_HIST
cd "$(dirname "$0")/.."
/usr/local/bin/Rscript -e 'source("providers/fishbase/load_fishbase.R"); run_fishbase_intake(output_file="output/fishbase_compiled.csv")' > output/fishbase_run_log.txt 2>&1
echo "FishBase done: exit $?"
