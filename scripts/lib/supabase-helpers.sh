#!/bin/bash
# Shared helpers for Supabase REST API calls + Claude CLI health check.
# Sourced by worker-*.sh scripts. Never run directly.
#
# Expects these env vars set by the caller (loaded from .env.local):
#   SUPABASE_URL              e.g. https://dmstbdlyhabfjzwduxmj.supabase.co
#   SUPABASE_SERVICE_ROLE_KEY service role JWT (bypasses RLS)

set -euo pipefail

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]; then
  echo "ERROR: SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not set" >&2
  echo "Expected at /Users/sahilmedtrics/Downloads/ai-news-ig/.env.local" >&2
  exit 1
fi

# supa_get <path-with-query>
# Returns JSON body. Caller should pipe to jq to parse.
supa_get() {
  local path="$1"
  curl -sSL \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Accept: application/json" \
    "${SUPABASE_URL}/rest/v1/${path}"
}

# supa_patch <path-with-query> <json-body>
# Returns HTTP status code. Response body written to /tmp/supa_patch_last.json.
supa_patch() {
  local path="$1"
  local body="$2"
  curl -sSL -o /tmp/supa_patch_last.json -w "%{http_code}" -X PATCH \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=minimal" \
    --data "${body}" \
    "${SUPABASE_URL}/rest/v1/${path}"
}

# Check that the Claude Code CLI has a valid, non-expired auth session.
# Returns 0 if auth is OK, 1 otherwise. On failure, prints a guidance message
# to stderr so users know what to do (log in interactively once).
#
# Called by worker entry points before any claude_generate invocation to avoid
# burning all 3 generation_attempts on rows when the issue is actually auth.
claude_auth_ok() {
  # `claude --version` never hits the network; it just prints the binary version.
  # To actually test auth, send the shortest possible prompt and time-limit it.
  local test_out
  test_out=$(echo 'echo ping' | timeout 20 claude --permission-mode bypassPermissions --model sonnet -p 'Reply with exactly: pong' 2>&1)
  local rc=$?
  if [ $rc -eq 0 ] && echo "${test_out}" | grep -qi "pong"; then
    return 0
  fi
  echo "WARNING: Claude CLI auth check failed." >&2
  echo "  Last 200 chars of response: $(printf '%s' "${test_out}" | tail -c 200)" >&2
  echo "  Fix: open a terminal, run 'claude' interactively once, complete any login prompt." >&2
  return 1
}

# Generate content via Claude Code CLI. Writes the prompt to a tmp file,
# invokes claude in non-interactive mode, captures stdout. No API key used —
# relies on the user's CLI login (Claude Max).
#
# Usage: claude_generate <prompt-string> [model=sonnet]
claude_generate() {
  local prompt="$1"
  local model="${2:-sonnet}"
  local tmp_prompt
  tmp_prompt=$(mktemp -t claudegenXXXX)
  printf '%s' "${prompt}" > "${tmp_prompt}"
  # --permission-mode bypassPermissions: non-interactive context, no tool prompts
  # --model sonnet: fastest capable model for content generation
  claude --permission-mode bypassPermissions --model "${model}" < "${tmp_prompt}"
  local rc=$?
  rm -f "${tmp_prompt}"
  return $rc
}

# Escape a string for safe JSON embedding via jq.
# Usage: jq_string_escape "<text>"
jq_string_escape() {
  printf '%s' "$1" | jq -R -s '.'
}
