#!/bin/bash
# run-daily.sh — invoked by the LaunchAgent at 07:00 daily.
# Runs the Claude Code CLI with ROUTINE_PROMPT.md against this repo,
# writing output to ~/AINewsDaily/ (on the user's Mac).

set -euo pipefail

REPO_DIR="/Users/sahilmedtrics/Downloads/ai-news-ig"
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

  # Pass the entire prompt via stdin (safer than -p for very long prompts).
  # --permission-mode bypassPermissions lets the non-interactive run use
  # WebFetch, Bash, Write without prompting. All tools run locally on the user's Mac.
  claude \
    --permission-mode bypassPermissions \
    --model sonnet \
    < "${PROMPT_FILE}"

  echo "========================================================"
  echo "run finished: $(date -Iseconds)"
  echo "========================================================"
} > "${RUN_LOG}" 2>&1

# Keep last 30 run logs
ls -1t "${LOG_DIR}"/run-*.log 2>/dev/null | tail -n +31 | xargs -r rm -f
