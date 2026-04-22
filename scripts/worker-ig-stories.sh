#!/bin/bash
# Worker: regenerate IG Story (9:16) prompt for rows where generation_status = 'pending'

set -euo pipefail

REPO_DIR="/Users/sahilmedtrics/ai-news-ig"
cd "${REPO_DIR}"

if [ -f .env.local ]; then
  set -a
  # shellcheck disable=SC1091
  source .env.local
  set +a
fi

# shellcheck disable=SC1091
source scripts/lib/supabase-helpers.sh

log() { echo "[$(date +%H:%M:%S)] ig-story-worker: $*"; }

pending_json=$(supa_get "ig_stories?select=id,story_id,generation_attempts,story:stories(title,hook,story_details,why_matters,source_name,source_url,tags)&generation_status=eq.pending&generation_attempts=lt.3&order=generation_requested_at.asc&limit=5")

count=$(echo "${pending_json}" | jq 'length')
if [ "${count}" -eq 0 ]; then
  exit 0
fi

log "processing ${count} pending IG story/stories"

echo "${pending_json}" | jq -c '.[]' | while IFS= read -r row; do
  ig_id=$(echo "${row}" | jq -r '.id')
  attempts=$(echo "${row}" | jq -r '.generation_attempts')
  title=$(echo "${row}" | jq -r '.story.title')
  hook=$(echo "${row}" | jq -r '.story.hook')
  why_matters=$(echo "${row}" | jq -r '.story.why_matters')
  source_name=$(echo "${row}" | jq -r '.story.source_name')

  log "  -> refining IG story ${ig_id} (attempt $((attempts + 1))/3) for story: ${title:0:60}"

  prompt=$(cat <<PROMPT_EOF
You are writing a paste-ready Claude Design prompt for a 1080x1920 Instagram Story slide for @SamPatel.AI — audience is BUSINESS OWNERS who follow a creator for AI-for-business updates.

SOURCE STORY:
Title: ${title}
Hook: ${hook}
Source: ${source_name}
Why it matters: ${why_matters}

OUTPUT — respond with ONLY the complete design prompt text (no JSON, no markdown fences, no preamble). It will be pasted directly into Claude Design.

Structure:
Line 1: "Create a single Instagram Story at 1080x1920 pixels for @SamPatel.AI."
Then a BRAND TOKENS block (background #0A0A0A, text #FFFFFF, accent #FFD60A, primary #FF4D2E, heading Inter 800, body Inter 500).
Then a single-slide spec with:
  - Source badge at top (red primary pill, white uppercase text, ≤20 chars — e.g. "NEW FROM ANTHROPIC", "OPENAI LAUNCH", "POLICY ALERT")
  - Mega headline (128px Inter 800, white) — the scroll-stopper for this specific story, ≤9 words, lead with a number or stakes
  - Yellow 6x88 divider
  - Subtext (40px Inter 500, white) — ≤15 words, reads like a tease for the carousel
  - Handle bottom-left: @SamPatel.AI

End the prompt with a COPY section listing each exact text string in order:
  - Badge: "..."
  - Headline: "..."
  - Subtext: "..."

Hard rules:
- No em-dashes. No jargon without translation. Numbers over adjectives. Never fabricate stats.
- The headline and subtext must trace to specific facts in the source story.
PROMPT_EOF
)

  raw_output=""
  if ! raw_output=$(claude_generate "${prompt}" sonnet 2>/tmp/claude-worker-ig.err); then
    log "  !! claude CLI failed for IG story ${ig_id}"
    new_status="pending"
    if [ $((attempts + 1)) -ge 3 ]; then new_status="failed"; fi
    error_msg=$(jq_string_escape "claude CLI failed: $(tail -c 200 /tmp/claude-worker-ig.err)")
    supa_patch "ig_stories?id=eq.${ig_id}&generation_status=eq.pending" "{\"generation_attempts\":$((attempts + 1)),\"generation_status\":\"${new_status}\",\"generation_error\":${error_msg}}" > /dev/null
    continue
  fi

  # Output is plain prompt text (not JSON). Trim leading/trailing blank lines.
  # Pure awk — BSD sed's multiline idiom is fragile on macOS.
  cleaned=$(echo "${raw_output}" | awk '
    NF { lines[++n] = $0; last = n; next }
    n { lines[++n] = $0 }
    END { for (i = 1; i <= last; i++) print lines[i] }
  ')

  # Must contain brand tokens and copy section to be valid
  if ! echo "${cleaned}" | grep -q "BRAND TOKENS"; then
    log "  !! output missing BRAND TOKENS for IG story ${ig_id}"
    new_status="pending"
    if [ $((attempts + 1)) -ge 3 ]; then new_status="failed"; fi
    error_msg=$(jq_string_escape "missing BRAND TOKENS: $(echo "${cleaned}" | head -c 200)")
    supa_patch "ig_stories?id=eq.${ig_id}&generation_status=eq.pending" "{\"generation_attempts\":$((attempts + 1)),\"generation_status\":\"${new_status}\",\"generation_error\":${error_msg}}" > /dev/null
    continue
  fi

  patch_body=$(jq -n \
    --arg p "${cleaned}" \
    '{
      prompt_text: $p,
      generation_status: "ready",
      generation_error: null,
      generation_attempts: '"$((attempts + 1))"'
    }')

  # Status-gated PATCH — prevents overwriting rows a user modified mid-generation.
  http_code=$(supa_patch "ig_stories?id=eq.${ig_id}&generation_status=eq.pending" "${patch_body}")
  if [ "${http_code}" -ge 200 ] && [ "${http_code}" -lt 300 ]; then
    log "  OK IG story ${ig_id} ready"
  else
    log "  !! PATCH failed HTTP ${http_code}: $(cat /tmp/supa_patch_last.json)"
  fi
done
