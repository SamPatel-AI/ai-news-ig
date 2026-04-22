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

  # Quick check: are there any pending rows across all 3 tables? If not,
  # skip even loading env + auth check — we'd just exit fast anyway.
  if [ -f .env.local ]; then
    set -a
    # shellcheck disable=SC1091
    source .env.local
    set +a
  fi
  pending_count=$(curl -sSL \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY:-}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY:-}" \
    -H "Prefer: count=exact" -H "Range: 0-0" -I \
    "${SUPABASE_URL:-}/rest/v1/scripts?generation_status=eq.pending&select=id" 2>/dev/null \
    | awk -F'/' 'tolower($0) ~ /content-range:/ {print $2+0; exit}' \
  )
  pending_count=${pending_count:-0}
  if [ "${pending_count}" -eq 0 ]; then
    # Also check carousels + ig_stories before skipping
    cc=$(curl -sSL -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY:-}" -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY:-}" \
      "${SUPABASE_URL:-}/rest/v1/carousels?generation_status=eq.pending&select=id" 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
    ic=$(curl -sSL -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY:-}" -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY:-}" \
      "${SUPABASE_URL:-}/rest/v1/ig_stories?generation_status=eq.pending&select=id" 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
    if [ "${cc:-0}" -eq 0 ] && [ "${ic:-0}" -eq 0 ]; then
      echo "no pending rows — skipping all workers"
      echo "== $(date -Iseconds) workers done (no-op) =="
      exit 0
    fi
  fi

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
