# Daily AI-for-Business → Instagram Content Routine

You are running an autonomous daily content pipeline in a fresh cloud container. Execute end-to-end without asking the user questions. If any step fails, log the error and continue with remaining steps. **The goal is to never produce a broken or empty day** — if real news is thin, fall back to yesterday; if one source is down, use the others; if one story's JSON is malformed, skip only that story's render.

## Audience (keep this front of mind every step)

Business owners — a **mix of tech-savvy founders and non-technical owners** (retail, services, agencies, e-commerce, small/mid-sized businesses). What they share: **no time to keep up with AI**. Your job is to translate today's AI news into what it means for running a business. Not "what's the new model" — "what new thing can they use, what will it cost, who's it for, what's the impact."

## Environment you have

- This repo is cloned in the container at the cwd
- `config/brand.json` — brand tokens (colors, fonts, handle, niche, voice, timezone, ranking_criteria, deprioritize list)
- `config/sources.json` — newsletter URLs, RSS feeds, search queries, retry config, credibility map
- Connectors available: **Google Drive**, **Web Search**
- Ubuntu container with Node.js — puppeteer must be `npm install`-ed on first use
- Helper scripts: `scripts/render.js`, `scripts/validate.js`, `scripts/fallback.js`

---

## Step 0 — Pre-flight

1. Read `config/brand.json` and `config/sources.json`.
2. **Abort** with a clear message if any string field in `brand.json` still starts with `TODO_`. Do not produce output.
3. Compute `today_str` = `YYYY-MM-DD` in `brand.json.timezone` using this exact approach (consistency across all date math):
   ```js
   new Intl.DateTimeFormat('en-CA', { timeZone: brand.timezone }).format(new Date())
   ```
4. Compute `cutoff` = `now - sources.time_window_hours` (24h default). All story recency checks use this explicit cutoff.
5. **Idempotency**: if `output/{today_str}/_LOG.md` exists AND its final `status:` line is `success`, exit early. Do not re-run. Log one line: `already ran today, exiting.`

## Step 1 — Research (fetch all newsletters in parallel)

Fetch the full list of sources from `config/sources.json.newsletters` (currently 10: TLDR AI, TLDR Founders, TLDR Tech, TLDR Data, The Deep View, The Rundown AI, Ben's Bites, The Neuron, AlphaSignal, Import AI).

Fetching rules:
- Attempt each enabled source **up to `retries_per_source`** (default 2), with `retry_backoff_ms` delay between attempts.
- A single source failure **never aborts the run**. Record `ok` or `failed(reason)` per source for `_LOG.md`.
- Also fetch each RSS feed in `sources.rss_feeds` and run each query in `sources.search_queries` (web search restricted to last 24h). These are fallback sources; still fetch them even if newsletters succeed.
- Extract candidate stories from everything fetched. Per candidate capture: `title`, `source_name`, `source_url`, `published_at` (ISO-8601), `one_line_summary`. Skip any candidate older than `cutoff`.

## Step 2 — Dedupe against the posted-story ledger

1. Using the Google Drive connector, locate `{brand.drive_parent_folder}/_MANIFEST.json` (default parent: `AI News Daily`). If it doesn't exist yet (first run), treat `posted_stories` as an empty array.
2. Dedup key per candidate:
   ```
   sha1( normalize(title) + '|' + canonical_host(source_url) )
   normalize  = lowercase, strip punctuation, collapse whitespace
   canonical_host = URL(source_url).hostname with leading "www." stripped
   ```
3. Drop any candidate whose dedup key matches an entry in `_MANIFEST.json.posted_stories` from the **last 7 days**.
4. Also dedupe within today's candidate set (same company + same topic = keep the highest-credibility source).

## Step 3 — Rank + select

Score each surviving candidate using `brand.json.ranking_criteria` weights. The criteria are business-outcome focused — **this is what makes the content work for our audience**:

- **business_applicability** (weight 5): can a business owner use this? A new consumer chatbot that could handle customer support → yes. A new transformer architecture paper → no.
- **cost_or_time_savings_hook** (4): does the story give you a number to cite? "cuts support cost 40%", "replaces $500/mo tool", "saves 10 hrs/week"
- **recognizable_name** (4): OpenAI, Google, Microsoft, Anthropic, Meta, Shopify, Amazon, etc. — household names your audience already trusts
- **accessible_today** (4): tools that exist now and can be tried this week, not research or "coming in 2026"
- **operations_or_jobs_impact** (3): affects how businesses hire, serve customers, market, or operate
- **plain_english_explainable** (3): if you can't explain it in 25 words without jargon, don't pick it
- **recency** (2): more recent = slightly better, but not decisive
- **visual_hook** (2): can slide 1 be a headline that stops scroll?

**De-prioritize (see `brand.json.deprioritize` — skip unless clearly reframeable for business):**
- Pure research papers, benchmarks, architecture debates
- Developer-only tooling without a business framing
- AI-for-AI-researchers content
- Pure drama without business implication
- Features only usable in 2026+ (roadmap / vapor)

Select **3–5 stories** (`sources.min_stories` = 2, `sources.max_stories` = 5). Fewer is fine if genuinely fewer qualify — never pad. If selected count < `min_stories`, jump to Step 11 (fallback branch).

## Step 4 — Set up today's output folder

```
output/{today_str}/
  01_<story-slug>/
  02_<story-slug>/
  ...
```

Slugs: lowercase kebab-case from title, max 40 chars, ASCII-only.

## Step 5 — Generate copy per story

For each story folder, write these three files:

### `research.md`
Bullets only, ≤ 300 words. Include: key facts, notable quotes (≤ 15 words each, paraphrase the rest), hard stats, relevant URLs. This is for the user's fact-check reference — concise, no fluff.

### `slides.json` (7-slide carousel, `"aspect": "4:5"`)

```json
{
  "story_id": "{today_str}_<slug>",
  "source": { "name": "...", "url": "...", "published_at": "...ISO-8601..." },
  "aspect": "4:5",
  "slides": [
    {"type": "hook",     "tag": "OpenAI", "headline": "...", "subtext": "..."},
    {"type": "context",  "eyebrow": "THE CONTEXT", "headline": "...", "body": "..."},
    {"type": "point",    "number": 1, "headline": "...", "stat": "$1/M", "body": "..."},
    {"type": "point",    "number": 2, "headline": "...", "stat": "< $0.01", "body": "..."},
    {"type": "point",    "number": 3, "headline": "...", "body": "..."},
    {"type": "takeaway", "eyebrow": "WHY IT MATTERS", "headline": "...", "body": "..."},
    {"type": "cta",      "headline": "Daily AI news for business owners", "handle": "{brand.handle}"}
  ]
}
```

**Optional visual-hint fields** (use when they make the slide stronger; omit when they don't):
- `hook.tag` — short pill label in top corner, usually the company name (e.g. `"OpenAI"`, `"Shopify"`, `"New Tool"`) ≤ 15 chars.
- `context.eyebrow`, `takeaway.eyebrow` — short label above the headline (e.g. `"THE CONTEXT"`, `"WHY IT MATTERS"`, `"THE CATCH"`) ≤ 20 chars, uppercase.
- `point.stat` — the punchiest number from that point, rendered as a big stat card. Use when you have a concrete stat (`"60% cheaper"`, `"$1/M"`, `"10 hrs/week"`). Omit for narrative points.

These fields make slides visually punchier for scroll-stop on a business-owner audience. Do not force them; a point without a clean stat should omit `stat` rather than invent one.

### `story.json` (1-slide 9:16 IG story)

```json
{
  "story_id": "{today_str}_<slug>",
  "source": { "name": "...", "url": "...", "published_at": "..." },
  "aspect": "9:16",
  "slides": [
    {"type": "story_summary", "headline": "...", "subtext": "...", "source_badge": "BREAKING"}
  ]
}
```

### Copy rules (strict — optimized for this audience)

- Headlines ≤ 9 words. Body ≤ 25 words (context slide may go to 35).
- **No em-dashes anywhere** (hard rule — validator rejects).
- **Numbers over adjectives**: "60% cheaper" beats "much cheaper". "Replaces $500/mo tool" beats "affordable alternative".
- **No jargon without translation**. If you use "LLM" or "agent" or "RAG", define it in the same slide.
- **Every story must answer: what is it / what does it cost / who's it for / what's the impact.** Usually point_1/point_2/point_3 cover three of these. Takeaway is "one thing to do this week."
- Match `brand.json.voice`. Currently: *"your smart friend who reads the AI news so you don't have to — practical, numbers over adjectives, every story ends with 'what this means for your business', no jargon without translation, confident but not hypey."*
- `handle` on CTA slide = exact value from `brand.json.handle`.
- **Never fabricate stats, quotes, or facts.** If unverified, omit. Cite source URLs in `research.md`.
- **Audience test every slide**: would a non-technical restaurant owner understand this? Would a tech founder find it useful? Both must be yes.

## Step 6 — Validate each story's JSON

For every story, run:

```bash
node scripts/validate.js output/{today_str}/NN_<slug>/slides.json
node scripts/validate.js output/{today_str}/NN_<slug>/story.json
```

If either exits non-zero: log the precise error to `_LOG.md`, **skip only that story's render** (keep its `research.md`), and continue with the other stories. Do not attempt to fix the JSON — the error indicates the copy step has a bug that needs investigation later.

## Step 7 — Render PNGs

First-use setup in this container: `npm install puppeteer` with up to **3 retries** (Chromium download occasionally flakes).

For each validated story:

```bash
node scripts/render.js \
  --slides output/{today_str}/NN_<slug>/slides.json \
  --brand  config/brand.json \
  --out    output/{today_str}/NN_<slug>/carousel/

node scripts/render.js \
  --slides output/{today_str}/NN_<slug>/story.json \
  --brand  config/brand.json \
  --out    output/{today_str}/NN_<slug>/story/
```

Expected outputs:
- Carousel: `slide_01.png`..`slide_07.png` at 1080×1350
- Story: `story_01.png` at 1080×1920

The renderer has per-slide try/catch, so a single bad slide doesn't kill a carousel. Check stderr for `font_fallback` — log it if observed but don't treat as failure.

## Step 8 — Daily digest files

### `output/{today_str}/_SUMMARY.md`
- Header: today's date, story count, total slide count.
- Per story: `## NN — {Title}` then `- source: {source_name}` · `- link: {source_url}` · `- folder: {relative path}` · one-liner summary.

### `output/{today_str}/_CAPTIONS.md`
Per story, one ready-to-paste IG caption with this structure:
- **Hook** (first line): ≤ 125 characters. Pattern interrupt. Use a number, a question, or a stakes-raising statement. This is what shows before "...more" truncation in feed.
- **Body**: ≤ 150 words total (including hook). Format as 3–5 short lines or bullets. Delivers the "what it is / what it costs / who it's for / what this means for your business."
- **Close**: a 1-line "your move / try this / watch for X" action cue.
- **8–12 hashtags** — generate them per story from the actual content. Mix:
  - topic (e.g. `#CustomerService` `#Marketing` `#Ecommerce`)
  - company/tool named (e.g. `#OpenAI` `#Shopify` `#Claude`)
  - business audience (e.g. `#SmallBusiness` `#BusinessOwner` `#Entrepreneur` `#AIforBusiness`)
  - 1–2 broad AI (e.g. `#AI` `#AINews`)
  - No banned/shadowbanned tags. No repetition across stories in the same day.

## Step 9 — Upload to Google Drive

Using the Google Drive connector:
1. Find or create parent folder named `{brand.drive_parent_folder}` (default `AI News Daily`).
2. Create subfolder `{today_str}` inside.
3. Upload the entire local `output/{today_str}/` tree, preserving structure.
4. Note the resulting Drive folder URL.

If upload fails: retry once after 10s. If still fails, log the error — container output is ephemeral but today's `_MANIFEST.json` update won't happen and the next run will see the gap.

## Step 10 — Update `_MANIFEST.json` at the Drive parent

Read (or initialize) `{brand.drive_parent_folder}/_MANIFEST.json`:

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

Update rules:
- Prepend today's run entry; keep `recent_runs` at **most recent 30**.
- For each story actually produced today (including fallback), append to `posted_stories`. Keep **last 7 days** only; drop older.
- Set `last_successful_run = today_str` if final status is `success`.
- Write the file back to Drive (overwrite).

## Step 11 — Fallback branch (only when today is thin)

Trigger this branch **only if** one of the following is true after Steps 3/7:
- Selected stories < `sources.min_stories` (fewer than 2 qualify)
- Zero PNGs rendered total across all stories

Otherwise skip to Step 12.

Fallback logic:
1. Read `_MANIFEST.json.recent_runs`. Find the most recent entry with `status: success`. Call its date `fallback_from_date`.
2. If `_MANIFEST.json` is missing or no successful run exists: log `status: partial` (day-1 case, nothing to fall back to), skip to Step 12.
3. Download the entire `{fallback_from_date}/` folder tree from Drive into `output/{today_str}_fallback_src/`.
4. Run: `node scripts/fallback.js --from output/{today_str}_fallback_src --to output/{today_str} --brand config/brand.json`.
5. Re-run Step 8 (digest files) with a note at the top of `_SUMMARY.md`: `⚠️ ICYMI fallback: today's sources were thin. Content from {fallback_from_date}.`
6. Re-run Step 9 (Drive upload) for the fallback content.
7. Mark today's entry in `_MANIFEST.json` as `status: fallback`.

## Step 12 — Write `_LOG.md`

Always write, even on partial success. Final line must be one of:
```
status: success
status: partial
status: fallback
```

Full structure:
- `run_start` / `run_end` / `duration_seconds`
- `timezone` used
- Per source: `{source_name}: ok` or `{source_name}: failed ({reason})`
- `stories_considered: N` → `stories_selected: M`
- Per selected story: `NN_<slug>: validate=ok render=ok|failed(n) captions=ok`
- `drive_upload: ok ({url})` or `drive_upload: failed ({reason})`
- `manifest_updated: yes|no`
- `fallback_triggered: yes|no (from {date})`
- `errors: [...]`
- `status: <success|partial|fallback>`

---

## Failure handling (quick reference)

| What breaks | What happens |
|---|---|
| One newsletter down | Log, use others. No abort. |
| All 10 newsletters down | RSS + search still run. If still < 2 stories → fallback branch. |
| Single story has malformed JSON | `validate.js` flags it, that story's render is skipped, markdown kept, rest continue. |
| Puppeteer install fails | 3 retries. Still fails → log, continue with whatever rendered, fallback branch for missing content. |
| Google Fonts CDN slow | 4s timeout in `render.js`, logs `font_fallback: true`, slides render with system font. |
| Drive OAuth expired | Upload fails, retry once, log. Next run sees manifest gap and proceeds normally. |
| Same story as yesterday | Step 2 dedupe via 7-day `posted_stories` ledger. |
| Manual re-run same day | Step 0 idempotency check — exits early if today already succeeded. |

## What NOT to do

- Do not fabricate stories, quotes, or stats.
- Do not quote more than 15 words from any single source — paraphrase.
- Do not generate generic AI hype content that isn't tied to a specific business use case.
- Do not post to Instagram directly (out of scope).
- Do not skip `_LOG.md` — always write it, even on partial success.
- Do not re-attempt failed JSON — the validator error is the signal to investigate later, not to patch on the fly.
