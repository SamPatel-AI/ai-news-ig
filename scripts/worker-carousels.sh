#!/bin/bash
# Worker: regenerate carousel prompt + caption for rows where generation_status = 'pending'
#
# Sharpens the auto-generated prompt to be per-story-specific (not just passing
# through stories.carousel_prompt) and writes a tight IG caption matching the
# @SamPatel.AI voice.

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

log() { echo "[$(date +%H:%M:%S)] carousel-worker: $*"; }

pending_json=$(supa_get "carousels?select=id,story_id,generation_attempts,story:stories(title,hook,story_details,why_matters,source_name,source_url,tags)&generation_status=eq.pending&generation_attempts=lt.3&order=generation_requested_at.asc&limit=5")

count=$(echo "${pending_json}" | jq 'length')
if [ "${count}" -eq 0 ]; then
  exit 0
fi

log "processing ${count} pending carousel(s)"

echo "${pending_json}" | jq -c '.[]' | while IFS= read -r row; do
  carousel_id=$(echo "${row}" | jq -r '.id')
  attempts=$(echo "${row}" | jq -r '.generation_attempts')
  title=$(echo "${row}" | jq -r '.story.title')
  hook=$(echo "${row}" | jq -r '.story.hook')
  story_details=$(echo "${row}" | jq -r '.story.story_details')
  why_matters=$(echo "${row}" | jq -r '.story.why_matters')
  source_name=$(echo "${row}" | jq -r '.story.source_name')

  log "  -> refining carousel ${carousel_id} (attempt $((attempts + 1))/3) for story: ${title:0:60}"

  prompt=$(cat <<PROMPT_EOF
You are refining a paste-ready Claude Design carousel prompt for @SamPatel.AI — a content creator whose audience is BUSINESS OWNERS (mix of tech-savvy founders and non-technical SMB owners). Tone: practical, numbers over adjectives, every story closes with "what this means for your business", no jargon without translation, zero em-dashes, confident but not hypey.

SOURCE STORY:
Title: ${title}
Hook: ${hook}
Source: ${source_name}

${story_details}

Why it matters:
${why_matters}

OUTPUT — respond with ONLY valid JSON matching this exact shape (no prose, no markdown fences):

{
  "prompt_text": "A complete 7-slide Claude Design carousel prompt at 1080x1350. Include: BRAND TOKENS section (background #0A0A0A, text #FFFFFF, accent #FFD60A, primary #FF4D2E, heading Inter 800, body Inter 500, handle @SamPatel.AI bottom-left of slides 1-6, page number bottom-right), DESIGN DIRECTION (editorial, high-contrast, varied layouts), then 7 slides each with: layout notes and EXACT copy (hook tag/headline/subtext with number, context eyebrow/headline/body, 3 points with headlines and optional stat cards, takeaway with full-yellow flip, CTA with handle pill). Slide headlines ≤9 words, body ≤25 words (context ≤35). No em-dashes. Numbers over adjectives.",
  "caption_text": "IG caption for this post. Format: hook line (≤125 chars, pre-truncation), blank line, 3-5 short bullet or line body text (≤150 words total), blank line, 8-12 hashtags tailored to this story (mix: #AIforBusiness + business-type tags like #SmallBusiness #Entrepreneur + company/tool names from the story + 1-2 general #AI #AINews). Voice matches the brand. No em-dashes anywhere."
}

Hard rules:
- The prompt_text must be copy-paste ready into Claude Design. Not abstract, not generic — reference this specific story's numbers and framing.
- Every string of copy inside the prompt must trace back to a fact in the STORY DETAILS.
- The caption's hook line must have either a number or a business-pain angle in the first 125 chars.
- No em-dashes. No roadmap speculation. No invented stats.
PROMPT_EOF
)

  raw_output=""
  if ! raw_output=$(claude_generate "${prompt}" sonnet 2>/tmp/claude-worker-carousels.err); then
    log "  !! claude CLI failed for carousel ${carousel_id}"
    new_status="pending"
    if [ $((attempts + 1)) -ge 3 ]; then new_status="failed"; fi
    error_msg=$(jq_string_escape "claude CLI failed: $(tail -c 200 /tmp/claude-worker-carousels.err)")
    supa_patch "carousels?id=eq.${carousel_id}&generation_status=eq.pending" "{\"generation_attempts\":$((attempts + 1)),\"generation_status\":\"${new_status}\",\"generation_error\":${error_msg}}" > /dev/null
    continue
  fi

  # Strip ```json fences and anything before the first { / after the last }
  cleaned=$(echo "${raw_output}" | python3 -c "
import sys, re
t = sys.stdin.read()
# Remove leading/trailing fence markers
t = re.sub(r'^\s*\`\`\`(?:json)?\s*\n', '', t)
t = re.sub(r'\n\s*\`\`\`\s*$', '', t)
# Find first '{' and balance braces honoring quoted strings
start = t.find('{')
if start < 0:
    print(t); sys.exit(0)
depth = 0
in_str = False
esc = False
for i in range(start, len(t)):
    c = t[i]
    if esc:
        esc = False
        continue
    if c == '\\\\':
        esc = True
        continue
    if c == '\"':
        in_str = not in_str
        continue
    if in_str:
        continue
    if c == '{':
        depth += 1
    elif c == '}':
        depth -= 1
        if depth == 0:
            print(t[start:i+1])
            sys.exit(0)
print(t[start:])
")

  if ! echo "${cleaned}" | jq -e . >/dev/null 2>&1; then
    log "  !! invalid JSON for carousel ${carousel_id}"
    new_status="pending"
    if [ $((attempts + 1)) -ge 3 ]; then new_status="failed"; fi
    error_msg=$(jq_string_escape "non-JSON: $(echo "${raw_output}" | head -c 200)")
    supa_patch "carousels?id=eq.${carousel_id}&generation_status=eq.pending" "{\"generation_attempts\":$((attempts + 1)),\"generation_status\":\"${new_status}\",\"generation_error\":${error_msg}}" > /dev/null
    continue
  fi

  prompt_text=$(echo "${cleaned}" | jq -r '.prompt_text')
  caption_text=$(echo "${cleaned}" | jq -r '.caption_text')

  patch_body=$(jq -n \
    --arg p "${prompt_text}" \
    --arg c "${caption_text}" \
    '{
      prompt_text: $p,
      caption_text: $c,
      generation_status: "ready",
      generation_error: null,
      generation_attempts: '"$((attempts + 1))"'
    }')

  # Status-gated PATCH — prevents overwriting rows a user modified mid-generation.
  http_code=$(supa_patch "carousels?id=eq.${carousel_id}&generation_status=eq.pending" "${patch_body}")
  if [ "${http_code}" -ge 200 ] && [ "${http_code}" -lt 300 ]; then
    log "  OK carousel ${carousel_id} ready"
  else
    log "  !! PATCH failed HTTP ${http_code}: $(cat /tmp/supa_patch_last.json)"
  fi
done
