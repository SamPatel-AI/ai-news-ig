# Daily AI-for-Business Research Brief (Local Edition)

You are running an autonomous daily research pipeline locally on the user's Mac, invoked by a launchd LaunchAgent at 07:00 America/New_York. Execute end-to-end without asking the user questions. The goal is **never produce an empty day** — if research is thin, fall back to yesterday's briefs. **Text + media only — no image rendering, no PNG generation.** The user writes and designs carousels themselves using the prompts you produce.

## Audience (keep front of mind)

Business owners — a **mix of tech-savvy founders and non-technical owners** (retail, services, agencies, e-commerce, small/mid-sized businesses). What they share: **no time to keep up with AI**. Translate today's AI news into what it means for running a business. Not "what's the new model" — "what new thing can they use, what will it cost, who's it for, what's the impact."

## Environment

- You are running as Claude Code CLI on the user's Mac (macOS)
- Current working directory is the repo: `/Users/sahilmedtrics/Downloads/ai-news-ig/`
- `config/brand.json` — brand tokens (handle, niche, voice, timezone, ranking_criteria, deprioritize, colors, fonts)
- `config/sources.json` — 10 newsletters, RSS feeds, search queries, retry config
- All output goes under `~/AINewsDaily/` (the user's home folder — absolute path expands to `/Users/sahilmedtrics/AINewsDaily/`)
- Tools available: WebFetch, WebSearch, Bash, Read, Write, Glob, Grep
- **No cloud connectors needed.** No Google Drive. No GitHub. Pure local I/O.

---

## Step 0 — Pre-flight

1. Read `config/brand.json` and `config/sources.json` via the Read tool.
2. **Abort** with a clear message printed to stdout if any string field in `brand.json` still starts with `TODO_`.
3. Compute `today_str` = `YYYY-MM-DD` in `brand.json.timezone` using `date +%Y-%m-%d` via Bash (ensuring the system timezone is either set correctly or computed explicitly with `TZ=America/New_York date +%Y-%m-%d`).
4. Compute `cutoff` = `now - sources.time_window_hours` (default 24h). All recency checks use this explicit cutoff.
5. **Idempotency:** if `~/AINewsDaily/{today_str}/_LOG.md` exists AND its final line says `status: success`, exit early. Print: `already ran today, exiting.`
6. **Ensure output directory exists:** `mkdir -p ~/AINewsDaily/{today_str}/` via Bash.

## Step 1 — Research (fetch all sources)

Fetch every enabled source in `config/sources.json.newsletters` (currently 10: TLDR AI, TLDR Founders, TLDR Tech, TLDR Data, The Deep View, The Rundown AI, Ben's Bites, The Neuron, AlphaSignal, Import AI).

Use WebFetch for each newsletter URL. A single source failure **never aborts the run**. Record `ok` or `failed(reason)` per source for `_LOG.md`. Retry up to `retries_per_source` times (default 2) with `retry_backoff_ms` delay between attempts.

Also fetch every RSS feed in `sources.rss_feeds` and run every query in `sources.search_queries` via WebSearch (restricted to last 24h). These are fallback sources — fetch them even when newsletters succeed.

For each candidate story, extract at minimum: `title`, `source_name`, `source_url`, `published_at` (ISO-8601), `one_line_summary`. Skip anything older than `cutoff`.

Then for each candidate that looks strong enough to keep, visit the article URL with WebFetch to gather: full article body, all hero/inline image URLs, all embedded video URLs (YouTube, Vimeo, Twitter/X, native `<video>` — just URLs, do not attempt video download).

## Step 2 — Dedupe against the local ledger

1. Read `~/AINewsDaily/_MANIFEST.json` via the Read tool. If it doesn't exist (first run), treat `posted_stories` as an empty array.
2. Dedup key per candidate:
   ```
   sha1( normalize(title) + '|' + canonical_host(source_url) )
   normalize = lowercase, strip punctuation, collapse whitespace
   canonical_host = hostname with "www." stripped
   ```
   Compute SHA-1 via `echo -n "..." | shasum | cut -d' ' -f1` in Bash.
3. Drop any candidate whose dedup key matches a `_MANIFEST.json.posted_stories` entry from the **last 7 days**.
4. Within today's candidate set, dedupe same company + same topic (keep highest-credibility source per `sources.json.source_credibility`).

## Step 3 — Rank and select top 10

Score every surviving candidate using `brand.json.ranking_criteria` weights:

- **business_applicability** (weight 5): can a business owner use this?
- **cost_or_time_savings_hook** (4): a concrete number
- **recognizable_name** (4): OpenAI, Google, Microsoft, Anthropic, Meta, Shopify, Amazon, Canva, etc.
- **accessible_today** (4): exists now, tryable this week
- **operations_or_jobs_impact** (3): changes how businesses hire, serve, market, operate
- **plain_english_explainable** (3): explainable in 25 words without jargon
- **recency** (2)
- **visual_hook** (2)

**De-prioritize** (see `brand.json.deprioritize`):
- Pure research papers, benchmarks, architecture debates
- Developer-only tooling without a business framing
- AI-for-AI-researchers content
- Pure drama without business implication
- Roadmap-only announcements (2026+)

**Select top 10 stories.** If fewer than 10 qualify, keep what you have (minimum 5 — if fewer, trigger fallback in Step 10).

## Step 4 — Scaffold output folders

Via Bash:
```
mkdir -p ~/AINewsDaily/{today_str}/news01 ~/AINewsDaily/{today_str}/news02 ...
```

Numbering matches rank order. `news01` = highest-scoring story.

## Step 5 — Per-story text brief

For each of the N selected stories, write `~/AINewsDaily/{today_str}/newsNN/newsNN.txt` with **exactly these four sections** in this order, using the exact delimiters shown. Plain text only — no markdown inside the `.txt` file.

```
=== REFERENCE ===
Source: {source_name}
URL: {source_url}
Published: {published_at ISO-8601}
Author / Newsletter: {author or source_name}
Fetched: {iso timestamp of when you ran this step}
Media files saved locally: newsNN_1.png, newsNN_2.png, ... (list actual filenames saved in Step 6; "none" if no images)
Video URLs referenced (not downloaded): {list each URL on its own line; "none" if no videos}

=== STORY DETAILS ===
{500–700 words. Factual, neutral, dense. Cover:
- What happened (the news)
- Who is involved (companies, people, products)
- Key numbers, pricing, dates, availability
- Quotes (paraphrase ≤15 words; cite who said it)
- Prior context if materially relevant
- What's confirmed vs. rumored
No hedging filler. No "revolutionary" / "game-changing" adjectives.
Numbers over adjectives. If unverified, say "reported" or omit.
Never fabricate — every fact traces to source(s).}

=== WHY IT MATTERS FOR BUSINESS OWNERS ===
{300–500 words. Translate into our audience's domain.
Structure:
- Plain-English summary (2–3 sentences, no jargon)
- Who benefits most (retail / services / agencies / e-commerce / solo / small team — and why)
- Concrete use cases (3–5 specific scenarios: "a 5-person agency could...", "a restaurant owner could...")
- Cost / time impact (numbers where available)
- Tool alternatives (1–3 named competing options)
- A "try this week" action (one concrete step, under an hour)
- What NOT to do (one common mistake to avoid)
Match brand.json.voice.}

=== CAROUSEL PROMPT ===
{A complete, Claude-Design-ready prompt the user can paste into Claude
Design or Claude artifact. Self-contained — do not assume the design tool
has seen earlier sections. Include:

Create a 7-slide Instagram carousel at 1080×1350 pixels for @{handle}.

BRAND TOKENS:
- Background: {brand.colors.background}
- Text: {brand.colors.text}
- Accent: {brand.colors.accent}
- Primary: {brand.colors.primary}
- Muted text: {brand.colors.muted_text}
- Heading font: {brand.fonts.heading}, weight {brand.fonts.heading_weight}
- Body font: {brand.fonts.body}, weight {brand.fonts.body_weight}
- Handle bottom-left of slides 1–6: @{handle}
- Page number bottom-right of slides 1–6

DESIGN DIRECTION:
Editorial, high-contrast. Accent as bold shapes/fills, not just text color.
Each slide has a distinct layout. Generous whitespace. Headlines in Inter 800 at scale; body in Inter 500 at 32-38px.

SLIDE 1 — HOOK
- Yellow accent circle top-right (600px, bleeding off edge)
- Red-primary pill top-left: "{company/tool name}"
- Big headline bottom-left (120px): "{hook copy ≤9 words}"
- Yellow 6×88 divider below
- Subtext (38px): "{subtext ≤20 words}"

SLIDE 2 — CONTEXT
- Eyebrow label top-left (22px yellow uppercase letter-spaced): "THE CONTEXT"
- Headline (64px): "{context headline ≤9 words}"
- Yellow divider
- Body (36px): "{context body ≤35 words}"

SLIDE 3 — POINT 01 ("What it is")
- "01" watermark top-right (520px, yellow at 8% opacity)
- Yellow "01" heading + short divider on same baseline
- Headline (76px): "What it is"
- Stat card (yellow bg, black text, red drop-shadow, 72px): "{key stat}"
- Body (36px): "{explanation ≤25 words}"

SLIDE 4 — POINT 02 ("Who it's for")
- Same layout, "02" watermark
- Headline: "{who-it-is-for ≤9 words}"
- Stat card: "{stat}"
- Body: "{body ≤25 words}"

SLIDE 5 — POINT 03 ("What to try this week")
- Same layout, "03" watermark, no stat card
- Headline: "What to try this week"
- Body (36px): "{action ≤25 words}"

SLIDE 6 — TAKEAWAY (full yellow flip)
- Entire background yellow
- Eyebrow (22px black at 75% opacity): "WHY IT MATTERS"
- Headline (88px black): "{takeaway ≤9 words}"
- 6×88 black divider
- Body (38px black at 90% opacity): "{takeaway body ≤35 words}"

SLIDE 7 — CTA
- Red primary circle top-right
- Eyebrow: "YOUR MOVE"
- Headline (96px): "Daily AI news, built for business owners"
- Handle pill: yellow bg, black text, arrow → — "@{handle}"

COPY (exact strings):
- Slide 1 tag: "{company}"
- Slide 1 headline: "{copy}"
- Slide 1 subtext: "{copy}"
- Slide 2 eyebrow: "THE CONTEXT"
- Slide 2 headline: "{copy}"
- Slide 2 body: "{copy}"
- Slide 3 headline: "What it is"
- Slide 3 stat: "{copy}"
- Slide 3 body: "{copy}"
- Slide 4 headline: "{copy}"
- Slide 4 stat: "{copy}"
- Slide 4 body: "{copy}"
- Slide 5 headline: "What to try this week"
- Slide 5 body: "{copy}"
- Slide 6 eyebrow: "WHY IT MATTERS"
- Slide 6 headline: "{copy}"
- Slide 6 body: "{copy}"
- Slide 7 eyebrow: "YOUR MOVE"
- Slide 7 headline: "Daily AI news, built for business owners"
- Slide 7 handle: "@{handle}"

OPTIONAL INSTAGRAM STORY (1080×1920):
- Red primary badge at top (pill, white text): "{badge e.g. 'NEW FROM ANTHROPIC'}"
- Mega headline (128px): "{story headline}"
- Yellow divider + subtext (40px): "{subtext}"
- Handle bottom-left: @{handle}
}
```

**Copy rules inside CAROUSEL PROMPT section:**
- Headlines ≤ 9 words
- Body ≤ 25 words (context body ≤ 35, takeaway body ≤ 35)
- No em-dashes anywhere
- Numbers over adjectives
- No jargon without translation
- Match `brand.json.voice`
- Never fabricate stats; all stats trace to STORY DETAILS above

## Step 6 — Media download (images only)

For each story:

1. For every hero/inline image URL found in Step 1, download via Bash `curl -sSL -o ~/AINewsDaily/{today_str}/newsNN/newsNN_N.png "{url}"` (use `.jpg` / `.gif` extension as appropriate — otherwise `.png`).
2. Skip files > 10 MB (check with `curl -sSI` and Content-Length; skip if exceeded).
3. If download fails for a specific image: log in `_LOG.md`, continue.
4. Enumerate every video URL found and record in the `Video URLs referenced` line of `newsNN.txt`. Do not attempt video download.
5. If no images downloaded successfully, `Media files saved locally` reads `none`.

## Step 7 — Daily summary

Write `~/AINewsDaily/{today_str}/_SUMMARY.md`:

```
# {today_str} — AI-for-Business Daily Brief

- Stories: N
- Status: success | partial | fallback

## Quick menu

1. **{title}** — {one-liner} → [news01/](news01/)
2. **{title}** — {one-liner} → [news02/](news02/)
...

## Sources fetched today
- TLDR AI: ok
- TLDR Founders: ok
- The Rundown AI: failed (HTTP 503)
- ...
```

## Step 8 — Update `~/AINewsDaily/_MANIFEST.json`

Read the current file (or initialize empty). Update:

```json
{
  "last_successful_run": "YYYY-MM-DD",
  "recent_runs": [
    {"date": "YYYY-MM-DD", "status": "success|partial|fallback", "story_count": N, "local_path": "/Users/.../AINewsDaily/YYYY-MM-DD"}
  ],
  "posted_stories": [
    {"dedup_key": "sha1hex", "slug": "...", "source_url": "...", "date": "YYYY-MM-DD"}
  ]
}
```

Rules:
- Prepend today's run entry; keep `recent_runs` at most 30.
- For every story produced today, append to `posted_stories`. Keep last 7 days only.
- Set `last_successful_run = today_str` if final status is `success`.
- Write via the Write tool.

## Step 9 — Fallback branch (thin days)

Trigger **only if**: selected stories < 5 OR every `newsNN.txt` failed to write.

Fallback logic:
1. Read `~/AINewsDaily/_MANIFEST.json.recent_runs`. Find most recent `success`. Call its date `fallback_from_date`.
2. If no manifest / no prior success (day 1): log `status: partial`, skip to Step 10 with whatever you produced.
3. Via Bash: `cp -r ~/AINewsDaily/{fallback_from_date}/ ~/AINewsDaily/{today_str}/fallback_from_{fallback_from_date}/`
4. Prepend a line to `_SUMMARY.md`: `⚠️ Fallback day: today's sources were thin. Content from {fallback_from_date} re-linked under fallback_from_{fallback_from_date}/.`
5. Mark today's manifest entry `status: fallback`.

## Step 10 — Write `_LOG.md`

Always written. Final line is one of:
```
status: success
status: partial
status: fallback
```

Structure:
```
run_start: {iso}
run_end: {iso}
duration_seconds: N
timezone: America/New_York

sources:
  TLDR AI: ok (12 candidates)
  ...

stories_considered: N
stories_selected: M

per_story:
  news01: txt=ok images=3/3 videos_referenced=1
  news02: txt=ok images=0/2 (download failures) videos_referenced=0
  ...

manifest_updated: yes | no
fallback_triggered: yes (from {date}) | no
errors: [...]
status: success
```

---

## Failure handling

| What breaks | What happens |
|---|---|
| One newsletter down | Log, use others. No abort. |
| All 10 newsletters down | RSS + search still run. If < 5 stories → fallback. |
| Image download fails | Log per-file, keep the `.txt`, continue. |
| Video URL broken | Listed in `.txt`, no download attempted anyway. |
| Same story as yesterday | Step 2 dedupe via 7-day ledger. |
| Manual re-run same day | Step 0 idempotency — exits early. |
| `TODO_` left in brand.json | Step 0 abort. |
| Mac was off at 7am | launchd runs the job at the next wake if `RunAtLoad` on boot, OR queues for the next 7am. Check `_MANIFEST.json` gaps. |

## What NOT to do

- Do not fabricate stories, quotes, or stats.
- Do not quote > 15 words from any single source — paraphrase.
- Do not produce empty `.txt` files. If a story can't be written, skip it and log.
- Do not download videos (reliability gate — just URLs).
- Do not emit markdown inside `newsNN.txt` — plain text only, with the exact `=== SECTION ===` delimiters.
- Do not skip `_LOG.md` — always write it.
