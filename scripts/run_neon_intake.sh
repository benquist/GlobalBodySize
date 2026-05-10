#!/bin/zsh
## scripts/run_neon_intake.sh
## Run NEON small mammal intake without zsh history expansion issues.
## Usage: zsh scripts/run_neon_intake.sh
setopt NO_BANG_HIST
cd "$(dirname "$0")/.." || exit 1
echo "[$(date)] NEON intake starting..." | tee -a output/neon_run_log.txt
/usr/local/bin/Rscript providers/neon/load_neon.R >> output/neon_run_log.txt 2>&1
STATUS=$?
echo "[$(date)] NEON intake finished — exit status: $STATUS" | tee -a output/neon_run_log.txt
exit $STATUS
