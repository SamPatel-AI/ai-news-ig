# Daily AI-for-Business → Research Brief Routine (Text + Media)

You are running an autonomous daily research pipeline in a fresh cloud container. Execute end-to-end without asking the user questions. The goal is **never to produce an empty day** — if research is thin, fall back to yesterday's briefs. **Text + media only — no image rendering, no PNG generation.** The user writes and designs carousels themselves using the prompts you produce.

## Audience (keep front of mind)

Business owners — a **mix of tech-savvy founders and non-technical owners** (retail, services, agencies, e-commerce, small/mid-sized businesses). What they share: **no time to keep up with AI**. Your job is to translate today's AI news into what it means for running a business. Not "what's the new model" — "what new thing can they use, what will it cost, who's it for, what's the impact."

## Environment

- This repo is cloned in the container at cwd
- `config/brand.json` — brand tokens (handle, niche, voice, timezone, ranking_criteria, deprioritize, colors, fonts)
- `config/sources.json` — 10 newsletters, RSS feeds, search queries, retry config
- Connectors: **Google Drive**, **Web Search**, **Web Fetch**
- Ubuntu container, Node.js available (no external dependencies needed — this pipeline is pure text + file I/O)

---

## Step 0 — Pre-flight

1. Read `config/brand.json` and `config/sources.json`.
2. **Abort** with a clear message if any string field in `brand.json` still starts with `TODO_`.
3. Compute `today_str` = `YYYY-MM-DD` in `brand.json.timezone`:
   ```
   new Intl.DateTimeFormat('en-CA', { timeZone: brand.timezone }).format(new Date())
   ```
4. Compute `cutoff` = `now - sources.time_window_hours` (default 24h). All recency checks use this explicit cutoff.
5. **Idempotency:** if `output/{today_str}/_LOG.md` exists AND its final line says `status: success`, exit early. Log: `already ran today, exiting.`

## Step 1 — Research (fetch all sources)

Fetch every source in `config/sources.json.newsletters` (currently 10: TLDR AI, TLDR Founders, TLDR Tech, TLDR Data, The Deep View, The Rundown AI, Ben's Bites, The Neuron, AlphaSignal, Import AI).

Fetching rules:
- Up to `retries_per_source` attempts (default 2), `retry_backoff_ms` between attempts.
- A single source failure **never aborts the run**. Record `ok` or `failed(reason)` per source for `_LOG.md`.
- Also fetch every RSS feed in `sources.rss_feeds` and run every query in `sources.search_queries` (web search restricted to last 24h). These are fallback sources — fetch them even when newsletters succeed.

For each candidate story, extract at minimum:
- `title`, `source_name`, `source_url`, `published_at` (ISO-8601), `one_line_summary`
- Skip anything older than `cutoff`.

**Then** for each candidate that looks strong enough to keep, visit the actual article URL with web_fetch to gather:
- Full article body (or as much as the page exposes)
- All hero images, inline images, and screenshots (capture **direct image URLs**)
- All embedded video URLs (YouTube, Vimeo, Twitter/X, native `<video>` tags) — just URLs, do not attempt download of videos

## Step 2 — Dedupe against the posted-story ledger

1. Using the Google Drive connector, locate `{brand.drive_parent_folder}/_MANIFEST.json` (default parent: `AI News Daily`). If it doesn't exist yet (first run), treat `posted_stories` as an empty array.
2. Dedup key per candidate:
   ```
   sha1( normalize(title) + '|' + canonical_host(source_url) )
   normalize = lowercase, strip punctuation, collapse whitespace
   canonical_host = URL(source_url).hostname with "www." stripped
   ```
3. Drop any candidate whose dedup key matches an entry in `_MANIFEST.json.posted_stories` from the **last 7 days**.
4. Within today's candidate set, dedupe same company + same topic (keep highest-credibility source).

## Step 3 — Rank and select top 10

Score every surviving candidate using `brand.json.ranking_criteria` weights. Criteria (business-outcome focused — this is the whole point):

- **business_applicability** (weight 5): can a business owner *use* this?
- **cost_or_time_savings_hook** (4): a concrete number ("cuts support cost 40%", "saves 10 hrs/week", "replaces $500/mo tool")
- **recognizable_name** (4): OpenAI, Google, Microsoft, Anthropic, Meta, Shopify, Amazon, Canva — household names
- **accessible_today** (4): exists now, tryable this week
- **operations_or_jobs_impact** (3): changes how businesses hire, serve customers, market, operate
- **plain_english_explainable** (3): if you can't explain in 25 words without jargon, skip
- **recency** (2)
- **visual_hook** (2)

**De-prioritize** (see `brand.json.deprioritize`):
- Pure research papers, benchmarks, architecture debates
- Developer-only tooling without a business framing
- AI-for-AI-researchers content
- Pure drama without business implication
- Roadmap-only announcements (2026+)

**Select top 10 stories.** The user will pick which ones to actually post — your job is to give a strong menu, not to narrow for them. If fewer than 10 qualify, keep what you have (minimum 5 — if fewer, trigger fallback in Step 10).

## Step 4 — Scaffold output folders

```
output/{today_str}/
  news01/
  news02/
  ...
  news10/
```

Numbering matches rank order — `news01` = highest-scoring story.

## Step 5 — Per-story text brief

For each of the N selected stories, write `output/{today_str}/newsNN/newsNN.txt` with **exactly these four sections** in this order, using the exact delimiters shown. The file is plain text — no markdown.

```
=== REFERENCE ===
Source: {source_name}
URL: {source_url}
Published: {published_at ISO-8601}
Author / Newsletter: {author if available, otherwise source_name}
Fetched: {iso timestamp of when you ran this step}
Media files saved locally: newsNN_1.png, newsNN_2.png, ... (list actual filenames saved in Step 6; "none" if no images)
Video URLs referenced (not downloaded): {list each URL on its own line; "none" if no videos}

=== STORY DETAILS ===
{Aim for 500–700 words. Factual, neutral, dense. Cover:
- What happened (the news itself)
- Who is involved (companies, people, products)
- Key numbers, pricing, dates, availability
- Quotes (paraphrase ≤15 words; cite who said it)
- Prior context if it materially changes meaning (e.g. "this replaces X which cost $Y")
- What's confirmed vs. rumored

No hedging filler. No "revolutionary" / "game-changing" adjectives.
Use numbers. If unverified, say "reported" or omit.
Do not fabricate — every fact must trace to the source(s).}

=== WHY IT MATTERS FOR BUSINESS OWNERS ===
{Aim for 300–500 words. Translate the news into our audience's domain.
Structure as:
- Plain-English summary (2–3 sentences, no jargon)
- Who benefits most (which types of business — retail, services, agencies, e-commerce, solo founders, mid-sized teams — and why)
- Concrete use cases (3–5 specific scenarios: "a 5-person agency could...", "a restaurant owner could...")
- Cost / time impact (numbers where available — "replaces a $500/mo tool", "saves ~10 hrs/week on X")
- Tool suggestions / competing options (name real tools they could try — 1–3 named alternatives)
- A "try this week" action (one concrete step they can do in under an hour)
- What NOT to do (common mistake to avoid — e.g. "don't replace your entire support team yet because...")

Match brand.json.voice. Currently: "your smart friend who reads the AI
news so you don't have to — practical, numbers over adjectives, every
story ends with 'what this means for your business', no jargon without
translation, confident but not hypey."}

=== CAROUSEL PROMPT ===
{A complete, Claude-Design-ready prompt the user can paste into Claude
Design (or any AI design tool) to get a finished 7-slide Instagram carousel.
Self-contained — do not assume the design tool has seen the REFERENCE or
STORY DETAILS sections. Format it as follows:

Create a 7-slide Instagram carousel at 1080×1350 pixels for @{handle}.

BRAND TOKENS:
- Background: {brand.colors.background}
- Text: {brand.colors.text}
- Accent: {brand.colors.accent}
- Primary: {brand.colors.primary}
- Muted text: {brand.colors.muted_text}
- Heading font: {brand.fonts.heading}, weight {brand.fonts.heading_weight}
- Body font: {brand.fonts.body}, weight {brand.fonts.body_weight}
- Handle shown bottom-left of every slide except slide 7: @{handle}
- Page number bottom-right (e.g. "1 / 7")

DESIGN DIRECTION:
Editorial, high-contrast. Accent color used as bold shapes/fills, not just text.
Each slide has a distinct layout — no two slides look identical. Generous
whitespace. Headlines in heading font at scale; body in body font at 32-38px.

SLIDE 1 — HOOK
- Layout: yellow accent circle in top-right corner (bleeding off edge),
  bold company/tool pill in top-left (red primary color, white text)
- Headline (bottom-left, 120px heading): "{the hook copy ≤9 words}"
- Subtext (below headline, 38px body, white): "{subtext ≤20 words}"
- Small yellow accent divider (6px tall, 88px wide) between headline and subtext

SLIDE 2 — CONTEXT
- Layout: eyebrow label top-left, centered heading, divider, body below
- Eyebrow (yellow, 22px, uppercase, letter-spaced): "THE CONTEXT"
- Headline (64px heading): "{context headline ≤9 words}"
- Body (36px, white): "{context body ≤35 words}"

SLIDE 3 — POINT 01 ("What it is")
- Huge "01" as a watermark in the top-right (520px, yellow at 8% opacity)
- Heading "01" in accent color + short divider line on same baseline
- Headline (76px, white): "What it is"
- Stat card (yellow pill with red bottom shadow, 72px): "{key stat e.g. $1/M tokens}"
- Body (36px, white): "{what-it-is explanation ≤25 words}"

SLIDE 4 — POINT 02 ("Who it's for" or "What you can build")
- Same layout as SLIDE 3 but "02" watermark and "02" accent heading
- Headline: "{who-it-is-for headline ≤9 words}"
- Stat card: "{stat e.g. "Small teams" or "24/7 voice"}"
- Body (36px): "{body ≤25 words}"

SLIDE 5 — POINT 03 ("What to try this week")
- Same layout, "03" watermark. No stat card (narrative point).
- Headline: "What to try this week"
- Body (36px): "{action ≤25 words}"

SLIDE 6 — TAKEAWAY (full yellow background flip)
- Background: yellow (accent color) covering the whole slide
- Eyebrow: "WHY IT MATTERS" (22px, black with 75% opacity, uppercase, letter-spaced)
- Headline (88px heading, black): "{takeaway ≤9 words}"
- Divider (6px black, 88px wide)
- Body (38px, black at 90% opacity): "{takeaway body ≤35 words}"

SLIDE 7 — CTA
- Layout: red primary-color accent circle in top-right, eyebrow label,
  big heading, handle in yellow pill with arrow at bottom-left
- Eyebrow: "YOUR MOVE"
- Headline (96px heading): "Daily AI news, built for business owners"
- Handle pill: yellow background, black text, arrow →, 40px handle text
- No page number on this slide

COPY (use these exact strings):
- Slide 1 tag: "{company/tool name e.g. OpenAI}"
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

STORY STAT (if you also want a 1-slide 1080×1920 Instagram Story alongside):
- Source badge at top (red primary color pill, uppercase, white text): "{badge e.g. 'NEW FROM ANTHROPIC'}"
- Mega headline (128px heading, white): "{story headline}"
- Divider + subtext below (40px, white): "{subtext}"
- Handle bottom-left: @{handle}
}
```

**Copy rules for every string you emit inside the CAROUSEL PROMPT section:**
- Headlines ≤ 9 words
- Body ≤ 25 words (context body may go to 35, takeaway body to 35)
- **No em-dashes anywhere**
- Numbers over adjectives
- No jargon without translation
- Match `brand.json.voice`
- Never fabricate stats
- All stats must trace to the STORY DETAILS section of the same file

## Step 6 — Media download (images only, video URLs referenced)

For each story:

1. From the candidate's media URLs (gathered in Step 1), download **every image** to `output/{today_str}/newsNN/` as `newsNN_1.png`, `newsNN_2.png`, etc. (ordered by prominence on the source page: hero first, then inline).
2. Skip files > 10 MB (likely not a relevant image). Skip `.svg` / `.webp` / `.gif` → convert to `.png` only if trivially possible; otherwise save with original extension.
3. If download fails for a specific image: log it in `_LOG.md`, continue (do not abort the story).
4. Enumerate every video URL found (YouTube, Vimeo, Twitter/X, native `<video>`) and record them in the `Video URLs referenced` line of `newsNN.txt`. **Do not attempt video downloads** — just URLs.
5. If the story has zero images that downloaded successfully, the `Media files saved locally` line in `newsNN.txt` reads `none`.

## Step 7 — Daily summary

Write `output/{today_str}/_SUMMARY.md`:

```
# {today_str} — AI-for-Business Daily Brief

- Stories: N
- Status: success | partial | fallback

## Quick menu

1. **{title}** — {one-liner} → [news01/](news01/)
2. **{title}** — {one-liner} → [news02/](news02/)
...
10. **{title}** — {one-liner} → [news10/](news10/)

## Sources fetched today
- TLDR AI: ok / failed
- TLDR Founders: ok / failed
- ...
```

## Step 8 — Drive upload

Using Google Drive:
1. Find or create `{brand.drive_parent_folder}` (default `AI News Daily`).
2. Create subfolder `{today_str}` inside.
3. Upload the entire local `output/{today_str}/` tree, preserving structure (all `newsNN/` subfolders + their `.txt` and image files, plus `_SUMMARY.md` and `_LOG.md`).
4. Note the Drive folder URL.
5. On upload failure: retry once after 10s. If still fails, log and proceed — next run sees the manifest gap.

## Step 9 — Update `_MANIFEST.json` at Drive parent

```json
{
  "last_successful_run": "YYYY-MM-DD",
  "recent_runs": [
    {"date": "YYYY-MM-DD", "status": "success|partial|fallback", "story_count": N, "drive_url": "..."}
  ],
  "posted_stories": [
    {"dedup_key": "sha1hex", "slug": "...", "source_url": "...", "date": "YYYY-MM-DD"}
  ]
}
```

Rules:
- Prepend today's run entry; keep `recent_runs` at most recent 30.
- For every story produced today, append to `posted_stories`. Keep last 7 days only.
- Set `last_successful_run = today_str` if final status is `success`.

## Step 10 — Fallback branch (thin days)

Trigger **only if**: selected stories < 5 OR every story's `newsNN.txt` failed to write.

Fallback logic:
1. Read `_MANIFEST.json.recent_runs`. Find most recent `success`. Call its date `fallback_from_date`.
2. If no manifest / no prior success (day-1 case): log `status: partial`, skip Step 10 entirely, proceed to Step 11 with whatever you produced.
3. Copy `{fallback_from_date}/` from Drive into `output/{today_str}/` under a subfolder `fallback_from_{fallback_from_date}/`. Do not modify the content — these are yesterday's briefs, still usable.
4. Add a line at the top of `_SUMMARY.md`: `⚠️ Fallback day: today's sources were thin. Content from {fallback_from_date} is re-linked under fallback_from_{fallback_from_date}/.`
5. Mark today's manifest entry `status: fallback`.

## Step 11 — Write `_LOG.md`

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
  TLDR Founders: failed (HTTP 503 after 2 retries)
  ...

stories_considered: N
stories_selected: M

per_story:
  news01: txt=ok images=3/3 videos_referenced=1
  news02: txt=ok images=0/2 (2 download failures) videos_referenced=0
  ...

drive_upload: ok ({url}) | failed ({reason})
manifest_updated: yes | no
fallback_triggered: yes (from {date}) | no
errors: [...]
status: success
```

---

## Failure handling (quick reference)

| What breaks | What happens |
|---|---|
| One newsletter down | Log, use others. No abort. |
| All 10 newsletters down | RSS + search still run. If < 5 stories → fallback. |
| Image download fails | Log per-file, keep the `.txt`, continue. |
| Video URL broken | Just listed in `.txt`, no download attempted anyway. |
| Drive OAuth expired | Upload fails, retry once, log. Next run resumes. |
| Same story as yesterday | Step 2 dedupe via 7-day ledger. |
| Manual re-run same day | Step 0 idempotency — exits early. |
| `TODO_` left in brand.json | Step 0 abort with clear message. |

## What NOT to do

- Do not fabricate stories, quotes, or stats.
- Do not quote > 15 words from any single source — paraphrase.
- Do not produce empty `.txt` files. If a story can't be written, skip it and log.
- Do not download videos (reliability gate — just URLs).
- Do not emit markdown inside `newsNN.txt` — plain text only, with the exact `=== SECTION ===` delimiters.
- Do not skip `_LOG.md` — always write it.
