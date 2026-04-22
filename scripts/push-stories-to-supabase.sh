#!/bin/bash
# push-stories-to-supabase.sh
#
# Reads today's briefs from ~/AINewsDaily/{date}/ and upserts them into the
# Supabase `stories` table. Uses dedup_key conflict resolution so reruns don't
# duplicate rows.
#
# Invoked at the end of run-daily.sh. Can be run manually with:
#   ./scripts/push-stories-to-supabase.sh [YYYY-MM-DD]

set -euo pipefail

REPO_DIR="/Users/sahilmedtrics/ai-news-ig"
cd "${REPO_DIR}"

if [ -f .env.local ] && [ -z "${SUPABASE_URL:-}" ]; then
  set -a
  # shellcheck disable=SC1091
  source .env.local
  set +a
fi

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]; then
  echo "push-stories: SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY missing (expected in .env.local)" >&2
  exit 1
fi

TODAY="${1:-$(TZ=America/New_York date +%Y-%m-%d)}"
DAY_DIR="${HOME}/AINewsDaily/${TODAY}"

if [ ! -d "${DAY_DIR}" ]; then
  echo "push-stories: ${DAY_DIR} does not exist — nothing to push"
  exit 0
fi

log() { echo "[$(date +%H:%M:%S)] push-stories: $*"; }

# Build a map of newsNN -> {title, hook} from _SUMMARY.md where the real
# headlines live. Each numbered line looks like:
#   1. **Story Title** — hook text → [newsNN/](newsNN/)
SUMMARY_FILE="${DAY_DIR}/_SUMMARY.md"

SUMMARY_MAP=$(python3 - <<PYEOF
import re, json, pathlib, sys
p = pathlib.Path("${SUMMARY_FILE}")
if not p.exists():
    print("{}")
    sys.exit(0)
text = p.read_text()
out = {}
# Match: "1. **Title** — hook → [newsNN/](newsNN/)" or similar variations
pattern = re.compile(r'\d+\.\s+\*\*(?P<title>[^*]+?)\*\*\s*[—–-]+\s*(?P<hook>.+?)\s*(?:→|->|-->)\s*\[(?P<folder>news\d+)/?\]', re.DOTALL)
for m in pattern.finditer(text):
    title = m.group('title').strip().rstrip('.')
    hook = m.group('hook').strip().rstrip('.')
    folder = m.group('folder').strip()
    out[folder] = {'title': title, 'hook': hook}
print(json.dumps(out))
PYEOF
)

# Parse individual brief and merge title/hook from _SUMMARY.md map
parse_brief() {
  local file="$1"
  local summary_map="$2"

  python3 - "$file" "$summary_map" "$TODAY" <<'PYEOF'
import json, re, sys, os, pathlib, hashlib, datetime
from urllib.parse import urlparse

path = sys.argv[1]
summary_map = json.loads(sys.argv[2]) if sys.argv[2] else {}
today = sys.argv[3]

text = pathlib.Path(path).read_text()

# Split on === HEADER === lines
sections = {}
current = None
buf = []
for line in text.splitlines():
    m = re.match(r'^=== (.+) ===\s*$', line)
    if m:
        if current is not None:
            sections[current] = '\n'.join(buf).strip()
        current = m.group(1).strip()
        buf = []
    else:
        buf.append(line)
if current is not None:
    sections[current] = '\n'.join(buf).strip()

ref = sections.get('REFERENCE', '')
story_details = sections.get('STORY DETAILS', '')
why_matters = sections.get('WHY IT MATTERS FOR BUSINESS OWNERS', '')
carousel_prompt = sections.get('CAROUSEL PROMPT', '')

# Extract reference fields line-by-line (handles multi-source lines with "/")
ref_fields = {}
for line in ref.splitlines():
    if ':' not in line:
        continue
    k, _, v = line.partition(':')
    ref_fields[k.strip().lower()] = v.strip()

# If source contains "/" take the first (authoritative) one
source_name_raw = ref_fields.get('source', 'Unknown')
source_name = source_name_raw.split('/')[0].strip() if '/' in source_name_raw else source_name_raw

# URL: first URL if multiple
source_url = ref_fields.get('url', '').split()[0] if ref_fields.get('url') else ''
published_at = ref_fields.get('published', '')
tier_raw = ref_fields.get('tier', '').strip()

folder = os.path.basename(os.path.dirname(path))
rank_match = re.search(r'news(\d+)', folder)
rank = int(rank_match.group(1)) if rank_match else 99

# Prefer title + hook from _SUMMARY.md, which has the clean editorial headline
sm = summary_map.get(folder, {})
if sm.get('title'):
    title = sm['title'][:200]
    hook = sm.get('hook', title)[:400]
else:
    # Fallback: first 9 words of why_matters
    why_first = (why_matters.split('\n')[0] if why_matters else '').strip()
    words = why_first.split()
    title = ' '.join(words[:9]).rstrip('.').rstrip(',')[:200] or folder
    hook = why_first[:400] or title

# Tags: from tier + any clear company names at start of source
tags = []
if tier_raw:
    tags.append(tier_raw.lower())
# Heuristic: detect common company names in title
for company in ['OpenAI', 'Anthropic', 'Claude', 'Google', 'Microsoft', 'Meta', 'Amazon',
                 'Apple', 'Canva', 'Shopify', 'Adobe', 'GitHub', 'Cloudflare', 'xAI',
                 'Moonshot', 'Kimi', 'Deezer', 'Notion', 'Bezos']:
    if company.lower() in (title + ' ' + hook).lower() and company not in tags:
        tags.append(company)
        if len(tags) >= 5:
            break

# Dedup key
host = ''
try:
    host = urlparse(source_url).hostname or ''
    host = host.replace('www.', '')
except Exception:
    pass
norm_title = re.sub(r'[^a-z0-9]+', ' ', title.lower()).strip()
dedup_key = hashlib.sha1(f"{norm_title}|{host}".encode()).hexdigest()

# Published at
pub_iso = None
if published_at:
    try:
        dt = datetime.datetime.fromisoformat(published_at.replace('Z', '+00:00'))
        pub_iso = dt.isoformat()
    except Exception:
        pass

obj = {
    'run_date': today,
    'rank': rank,
    'source_name': source_name,
    'source_url': source_url,
    'published_at': pub_iso,
    'fetched_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'title': title,
    'hook': hook,
    'story_details': story_details,
    'why_matters': why_matters,
    'carousel_prompt': carousel_prompt,
    'story_prompt_9_16': None,
    'hero_image_url': None,
    'video_urls': [],
    'dedup_key': dedup_key,
    'tags': tags,
    'selected': False,
}
print(json.dumps(obj))
PYEOF
}

# Upload the first local image (if any) for a story to Supabase Storage and
# return the public URL. Uses the `carousel-uploads` bucket that's already
# configured as public-read. Path scheme: hero/{today}/{folder_name}.{ext}
# Returns empty string on no-image or any failure (non-fatal).
upload_hero_image() {
  local story_dir="$1"
  local folder_name
  folder_name=$(basename "${story_dir}")

  # Pick the first newsNN_1.* image if present, fallback to any newsNN_*.*
  local img
  img=$(ls "${story_dir}"/${folder_name}_1.* 2>/dev/null | head -1)
  if [ -z "${img}" ]; then
    img=$(ls "${story_dir}"/${folder_name}_*.* 2>/dev/null | grep -iE '\.(png|jpg|jpeg|gif|webp)$' | head -1)
  fi
  if [ -z "${img}" ] || [ ! -f "${img}" ]; then
    echo ""
    return
  fi

  local ext="${img##*.}"
  local content_type
  case "${ext,,}" in
    png)   content_type="image/png" ;;
    jpg|jpeg) content_type="image/jpeg" ;;
    gif)   content_type="image/gif" ;;
    webp)  content_type="image/webp" ;;
    *)     content_type="application/octet-stream" ;;
  esac

  local storage_path="hero/${TODAY}/${folder_name}.${ext}"
  local upload_url="${SUPABASE_URL}/storage/v1/object/${storage_path}"

  # x-upsert: true allows re-runs to overwrite yesterday's upload for the same path
  local http_code
  http_code=$(curl -sSL -o /tmp/push_upload.json -w "%{http_code}" \
    -X PUT \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Content-Type: ${content_type}" \
    -H "x-upsert: true" \
    --data-binary "@${img}" \
    "${upload_url}")

  if [ "${http_code}" -ge 200 ] && [ "${http_code}" -lt 300 ]; then
    # Bucket is public-read; construct public URL directly.
    echo "${SUPABASE_URL}/storage/v1/object/public/${storage_path}"
  else
    echo ""
  fi
}

ok=0
fail=0

for brief in "${DAY_DIR}"/news*/news*.txt; do
  [ -f "${brief}" ] || continue
  story_dir="$(dirname "${brief}")"
  folder_name=$(basename "${story_dir}")

  if ! json_body=$(parse_brief "${brief}" "${SUMMARY_MAP}"); then
    log "  !! parse failed for ${folder_name}"
    fail=$((fail + 1))
    continue
  fi

  # Upload hero image (if present) and inject the URL into the JSON before POST.
  hero_url=$(upload_hero_image "${story_dir}" 2>/dev/null || true)
  if [ -n "${hero_url}" ]; then
    json_body=$(echo "${json_body}" | jq --arg u "${hero_url}" '.hero_image_url = $u')
    log "  -> ${folder_name} hero image uploaded"
  fi

  # Retry up to 3 times with 1s → 2s → 4s backoff. Treats 5xx and network
  # errors (http_code == 000) as retryable. 4xx bails out immediately since
  # retrying a malformed payload is pointless.
  http_code=""
  attempt=0
  while [ "${attempt}" -lt 3 ]; do
    http_code=$(curl -sSL --max-time 30 -o /tmp/push_resp.json -w "%{http_code}" -X POST \
      -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "Content-Type: application/json" \
      -H "Prefer: resolution=merge-duplicates,return=minimal" \
      --data "${json_body}" \
      "${SUPABASE_URL}/rest/v1/stories?on_conflict=dedup_key" || echo "000")

    if [ "${http_code}" -ge 200 ] && [ "${http_code}" -lt 300 ]; then
      break
    fi
    # 4xx = client error, don't retry
    if [ "${http_code}" -ge 400 ] && [ "${http_code}" -lt 500 ]; then
      break
    fi
    attempt=$((attempt + 1))
    if [ "${attempt}" -lt 3 ]; then
      sleep_s=$((1 << (attempt - 1)))  # 1, 2, 4
      log "  .. ${folder_name} HTTP ${http_code} — retrying in ${sleep_s}s (attempt ${attempt}/3)"
      sleep "${sleep_s}"
    fi
  done

  if [ "${http_code}" -ge 200 ] && [ "${http_code}" -lt 300 ]; then
    log "  OK ${folder_name} pushed (HTTP ${http_code})"
    ok=$((ok + 1))
  else
    log "  !! ${folder_name} HTTP ${http_code}: $(cat /tmp/push_resp.json | head -c 200)"
    fail=$((fail + 1))
  fi
done

log "done — ${ok} pushed, ${fail} failed"
