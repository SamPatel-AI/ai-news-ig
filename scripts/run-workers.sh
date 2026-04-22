#!/bin/bash
# Invoked every 2 minutes by com.sampatel.ainews.workers.plist.
# Runs all three agent workers sequentially. Each one processes up to 5 pending
# rows per run; a backlog of >5 catches up over subsequent ticks.

set -euo pipefail

REPO_DIR="/Users/sahilmedtrics/Downloads/ai-news-ig"
LOG_DIR="${HOME}/AINewsDaily/_runs"
mkdir -p "${LOG_DIR}"

TS="$(date +%Y-%m-%dT%H-%M-%S)"
LOG="${LOG_DIR}/workers-${TS}.log"

# PATH for launchd (no user shell profile)
export PATH="${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH}"

cd "${REPO_DIR}"

{
  echo "== $(date -Iseconds) workers run =="
  for worker in worker-scripts.sh worker-carousels.sh worker-ig-stories.sh; do
    echo "-- ${worker} --"
    if ! bash "scripts/${worker}"; then
      echo "  (${worker} exited non-zero; continuing with next worker)"
    fi
  done
  echo "== $(date -Iseconds) workers done =="
} > "${LOG}" 2>&1

# Keep last 60 worker-run logs (about 2 hours of history)
ls -1t "${LOG_DIR}"/workers-*.log 2>/dev/null | tail -n +61 | xargs -r rm -f

exit 0
