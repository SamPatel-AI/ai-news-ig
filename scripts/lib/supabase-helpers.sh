#!/bin/bash
# Shared helpers for Supabase REST API calls from worker scripts.
# Sourced by worker-*.sh scripts. Never run directly.
#
# Expects these env vars to be set by the caller (loaded from .env.local):
#   SUPABASE_URL              e.g. https://viklcouyjeufloxfyzzl.supabase.co
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
# Returns HTTP status code.
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

# supa_post <table> <json-body>
supa_post() {
  local table="$1"
  local body="$2"
  curl -sSL -o /tmp/supa_post_last.json -w "%{http_code}" -X POST \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=minimal,resolution=merge-duplicates" \
    --data "${body}" \
    "${SUPABASE_URL}/rest/v1/${table}"
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
