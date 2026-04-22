#!/bin/bash
# Worker: regenerate script content for rows where generation_status = 'pending'
#
# Invoked every 2 minutes by com.sampatel.ainews.workers.plist.
# Reads stories + pending scripts, calls Claude CLI to write a niche-specific
# 30-50s Reel script, updates row and flips status to 'ready'.
#
# Runs through all pending rows in one pass. Safe to run concurrently with
# itself — Supabase UPDATE is atomic per row and we re-check status inside
# the update predicate.

set -euo pipefail

REPO_DIR="/Users/sahilmedtrics/Downloads/ai-news-ig"
cd "${REPO_DIR}"

# Load .env.local
if [ -f .env.local ]; then
  set -a
  # shellcheck disable=SC1091
  source .env.local
  set +a
fi

# shellcheck disable=SC1091
source scripts/lib/supabase-helpers.sh

log() { echo "[$(date +%H:%M:%S)] script-worker: $*"; }

# Fetch up to 5 pending scripts with their parent story joined in.
# Uses PostgREST's embedded resource syntax: ?select=*,story:stories(...)
pending_json=$(supa_get "scripts?select=id,story_id,generation_attempts,story:stories(title,hook,story_details,why_matters,source_name,source_url,tags)&generation_status=eq.pending&generation_attempts=lt.3&order=generation_requested_at.asc&limit=5")

# If empty array, nothing to do
count=$(echo "${pending_json}" | jq 'length')
if [ "${count}" -eq 0 ]; then
  exit 0
fi

log "processing ${count} pending script(s)"

# Iterate
echo "${pending_json}" | jq -c '.[]' | while IFS= read -r row; do
  script_id=$(echo "${row}" | jq -r '.id')
  story_id=$(echo "${row}" | jq -r '.story_id')
  attempts=$(echo "${row}" | jq -r '.generation_attempts')
  title=$(echo "${row}" | jq -r '.story.title')
  hook=$(echo "${row}" | jq -r '.story.hook')
  story_details=$(echo "${row}" | jq -r '.story.story_details')
  why_matters=$(echo "${row}" | jq -r '.story.why_matters')
  source_name=$(echo "${row}" | jq -r '.story.source_name')

  log "  -> refining script ${script_id} (attempt $((attempts + 1))/3) for story: ${title:0:60}"

  # Build the generation prompt. Tailored to @SamPatel.AI niche: business owners,
  # tech and non-tech, practical "what this means for running your business."
  prompt=$(cat <<PROMPT_EOF
You are writing a 35-50 second Instagram Reel script for @SamPatel.AI — a content creator whose audience is BUSINESS OWNERS (a mix of tech-savvy founders and non-technical owners running retail, services, agencies, e-commerce, SMB operations). They have no time to keep up with AI but need to know what new AI updates mean for RUNNING THEIR BUSINESS.

Voice: confident but not hypey, practical, numbers over adjectives, every story ends with a clear "what this means for your business" angle, no jargon without immediate translation, zero em-dashes.

SOURCE STORY:
Title: ${title}
Hook: ${hook}
Source: ${source_name}

Full story:
${story_details}

Why it matters for business owners:
${why_matters}

OUTPUT FORMAT — respond with ONLY valid JSON matching this exact shape (no prose before or after, no markdown fences):

{
  "hook_line": "string, ≤125 chars, ≤3 seconds to say aloud, scroll-stopping, leads with a number or a business-pain hook",
  "beats": [
    {
      "beat_number": 1,
      "seconds": "3-12s",
      "on_camera": "what to say plainly on camera, no jargon, 1-2 sentences",
      "b_roll": "one concrete visual suggestion (screen recording of tool, comparison chart, stock footage concept)"
    },
    {
      "beat_number": 2,
      "seconds": "12-25s",
      "on_camera": "the money/time/risk impact — specific business types and a dollar or hours number",
      "b_roll": "another concrete visual"
    },
    {
      "beat_number": 3,
      "seconds": "25-40s",
      "on_camera": "one specific 'try this week' action the owner can do in under an hour",
      "b_roll": "another visual"
    }
  ],
  "cta_line": "Follow for daily AI updates built for business owners.",
  "script_text": "Full teleprompter-ready script as plain text, sections labeled HOOK / BEAT 1 / BEAT 2 / BEAT 3 / CTA with the on_camera text under each, no b-roll notes (teleprompter-only version).",
  "duration_estimate_sec": 45
}

Hard rules:
- No em-dashes anywhere (replace with commas or periods).
- Numbers over adjectives ("cuts support cost 40%" beats "massive savings").
- If the story has a named tool/company/price, use it in beat 1.
- If there's no concrete number anywhere in the source material, do not invent one.
- Beat 3 must be a concrete action, not generic advice.
- Audience test: both a tech founder AND a restaurant owner should understand every sentence.
PROMPT_EOF
)

  # Invoke Claude CLI
  raw_output=""
  if ! raw_output=$(claude_generate "${prompt}" sonnet 2>/tmp/claude-worker-scripts.err); then
    log "  !! claude CLI failed for script ${script_id}, see /tmp/claude-worker-scripts.err"
    # Bump attempts and mark failed if third attempt
    new_status="pending"
    if [ $((attempts + 1)) -ge 3 ]; then new_status="failed"; fi
    error_msg=$(jq_string_escape "claude CLI invocation failed: $(tail -c 200 /tmp/claude-worker-scripts.err)")
    supa_patch "scripts?id=eq.${script_id}&generation_status=eq.pending" "{\"generation_attempts\":$((attempts + 1)),\"generation_status\":\"${new_status}\",\"generation_error\":${error_msg}}" > /dev/null
    continue
  fi

  # Extract the top-level JSON object (strips ```json fences and any extra prose)
  cleaned=$(echo "${raw_output}" | python3 -c "
import sys, re
t = sys.stdin.read()
t = re.sub(r'^\s*\`\`\`(?:json)?\s*\n', '', t)
t = re.sub(r'\n\s*\`\`\`\s*$', '', t)
start = t.find('{')
if start < 0:
    print(t); sys.exit(0)
depth = 0; in_str = False; esc = False
for i in range(start, len(t)):
    c = t[i]
    if esc: esc = False; continue
    if c == '\\\\': esc = True; continue
    if c == '\"': in_str = not in_str; continue
    if in_str: continue
    if c == '{': depth += 1
    elif c == '}':
        depth -= 1
        if depth == 0:
            print(t[start:i+1]); sys.exit(0)
print(t[start:])
")

  # Validate JSON
  if ! echo "${cleaned}" | jq -e . >/dev/null 2>&1; then
    log "  !! Claude output wasn't valid JSON for script ${script_id}"
    new_status="pending"
    if [ $((attempts + 1)) -ge 3 ]; then new_status="failed"; fi
    error_msg=$(jq_string_escape "Claude returned non-JSON: $(echo "${raw_output}" | head -c 200)")
    supa_patch "scripts?id=eq.${script_id}&generation_status=eq.pending" "{\"generation_attempts\":$((attempts + 1)),\"generation_status\":\"${new_status}\",\"generation_error\":${error_msg}}" > /dev/null
    continue
  fi

  # Extract fields and patch the scripts row
  hook_line=$(echo "${cleaned}" | jq -r '.hook_line')
  beats_json=$(echo "${cleaned}" | jq -c '.beats')
  cta_line=$(echo "${cleaned}" | jq -r '.cta_line')
  script_text=$(echo "${cleaned}" | jq -r '.script_text')
  duration=$(echo "${cleaned}" | jq -r '.duration_estimate_sec // 45')

  # Build the PATCH body via jq (safest way to embed multi-line strings)
  patch_body=$(jq -n \
    --arg hook "${hook_line}" \
    --argjson beats "${beats_json}" \
    --arg cta "${cta_line}" \
    --arg text "${script_text}" \
    --argjson dur "${duration}" \
    '{
      hook_line: $hook,
      beats: $beats,
      cta_line: $cta,
      script_text: $text,
      duration_estimate_sec: $dur,
      generation_status: "ready",
      generation_error: null,
      generation_attempts: '"$((attempts + 1))"'
    }')

  # Status-gated PATCH: only apply refinement if row is still pending.
  # Prevents races with user edits/deletes between our read and write.
  http_code=$(supa_patch "scripts?id=eq.${script_id}&generation_status=eq.pending" "${patch_body}")
  if [ "${http_code}" -ge 200 ] && [ "${http_code}" -lt 300 ]; then
    log "  OK script ${script_id} ready"
  else
    log "  !! PATCH failed HTTP ${http_code}: $(cat /tmp/supa_patch_last.json)"
  fi
done
