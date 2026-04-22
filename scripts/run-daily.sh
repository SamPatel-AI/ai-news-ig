#!/bin/bash
# run-daily.sh — invoked by the LaunchAgent at 10:00 daily.
# Runs the Claude Code CLI with ROUTINE_PROMPT.md against this repo,
# writing output to ~/AINewsDaily/ (on the user's Mac).

set -euo pipefail

REPO_DIR="/Users/sahilmedtrics/ai-news-ig"
OUTPUT_ROOT="${HOME}/AINewsDaily"
PROMPT_FILE="${REPO_DIR}/ROUTINE_PROMPT.md"
LOG_DIR="${OUTPUT_ROOT}/_runs"
TIMESTAMP="$(date +%Y-%m-%dT%H-%M-%S)"
RUN_LOG="${LOG_DIR}/run-${TIMESTAMP}.log"

mkdir -p "${OUTPUT_ROOT}" "${LOG_DIR}"

# Ensure PATH can find claude even under launchd (no user shell profile loaded)
export PATH="${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH}"

cd "${REPO_DIR}"

{
  echo "========================================================"
  echo "run started: $(date -Iseconds)"
  echo "repo: ${REPO_DIR}"
  echo "output root: ${OUTPUT_ROOT}"
  echo "========================================================"

  # Supabase reachability check — fail fast before spending 20 min on a run
  # whose output we can't push. Loads .env.local to get SUPABASE_URL.
  if [ -f .env.local ]; then
    set -a
    # shellcheck disable=SC1091
    source .env.local
    set +a
  fi
  if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]; then
    echo "PRE-FLIGHT FAIL: SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY missing from .env.local"
    exit 1
  fi
  ping_code=$(curl -sS --max-time 10 -o /dev/null -w "%{http_code}" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    "${SUPABASE_URL}/rest/v1/stories?select=id&limit=1" || echo "000")
  if [ "${ping_code}" -lt 200 ] || [ "${ping_code}" -ge 300 ]; then
    echo "PRE-FLIGHT FAIL: Supabase unreachable (HTTP ${ping_code} at ${SUPABASE_URL})"
    echo "Aborting before the expensive Claude run. Fix connectivity and re-trigger:"
    echo "  launchctl start com.sampatel.ainews"
    exit 1
  fi
  echo "pre-flight OK: Supabase reachable (HTTP ${ping_code})"
  echo "--------------------------------------------------------"

  # Pass the entire prompt via stdin (safer than -p for very long prompts).
  # --permission-mode bypassPermissions lets the non-interactive run use
  # WebFetch, Bash, Write without prompting. All tools run locally on the user's Mac.
  claude \
    --permission-mode bypassPermissions \
    --model sonnet \
    < "${PROMPT_FILE}"

  echo "--------------------------------------------------------"
  echo "pushing today's briefs to Supabase (dashboard)…"
  if ./scripts/push-stories-to-supabase.sh; then
    echo "push OK"
  else
    echo "push FAILED (briefs are still on disk at ~/AINewsDaily/)"
  fi

  echo "========================================================"
  echo "run finished: $(date -Iseconds)"
  echo "========================================================"
} > "${RUN_LOG}" 2>&1

# Keep last 30 run logs
ls -1t "${LOG_DIR}"/run-*.log 2>/dev/null | tail -n +31 | xargs -r rm -f
