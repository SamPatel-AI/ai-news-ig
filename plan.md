# plan.md — Daily AI News → Instagram Content (v2)

Living progress tracker. Tick items as they're done. Canonical spec lives here. Edit freely.

---

## Goal

Post to Instagram **every day** about AI news with zero creative work. Pipeline runs daily at 7:00 AM in Anthropic's cloud via **Claude Code Routines** (user confirmed Team/Enterprise plan — Routines available). Researches past 24h AI news from ~10 newsletters + RSS + web search, produces 3–5 stories/day. Each story = one 7-slide 1080×1350 carousel + one 1080×1920 story + a ready-to-paste IG caption. Uploads to Google Drive. Resilient enough to never produce a broken or empty day.

Morning flow: open Drive → drag PNGs → paste caption → post. ~5 min.

**Out of scope:** video scripts, auto-posting, analytics, multi-brand, notifications.

---

## Architecture

Single GitHub repo = deployable unit. `ROUTINE_PROMPT.md` is the pipeline brain — a Claude Code Routine reads it every morning and executes end-to-end in a fresh Ubuntu container with Google Drive + Web Search connectors. Fetches news, generates slide JSON, shells out to `scripts/render.js` (puppeteer) for PNGs at exact IG dimensions, uploads tree to Drive. `_MANIFEST.json` at the Drive parent folder provides cross-run memory (last successful date, posted-story ledger for dedup, run history). Small Node helpers (`validate.js`, `fallback.js`, `dry-run.js`) harden the JSON-in / PNG-out path. No API keys, no Mac required.

---

## Pinned JSON schema (validate.js enforces, render.js accepts)

`slides.json` / `story.json`:
```
{
  story_id: string (YYYY-MM-DD_slug),
  source: { name: string, url: URL, published_at: ISO-8601 },
  aspect: "4:5" | "9:16" | "1:1",
  slides: Array<Slide>   // length 1..10
}

Slide types (discriminated by `type`):
  hook           { type, headline (≤9 words), subtext? (≤25 words) }
  context        { type, headline (≤9 words), body (≤35 words) }
  point          { type, number: 1..5, headline (≤9 words), body (≤25 words) }
  takeaway       { type, headline (≤9 words), body (≤25 words) }
  cta            { type, headline (≤9 words), handle? }
  story_summary  { type, headline, subtext?, source_badge? }
  icymi_banner   { type, original_date: "YYYY-MM-DD", headline? }   // NEW
```

Validation rules:
- Reject unknown `type`.
- Reject missing required fields with precise error (e.g. `slide[2].body: required`).
- Word-count overages = warnings, not errors.
- Headlines must not contain `—` (em-dash) → hard error.
- `source.url` must parse as valid URL.

---

## Pinned `icymi_banner` visual spec

Used as slide 01 of fallback carousels:
- Top: small pill in `colors.accent` reading "ICYMI" (uppercase, 0.1em tracking).
- Center: heading "From {formatted original_date — e.g. 'Tuesday, Apr 19'}" in `fonts.heading` at 88px.
- Body: "Today's newsletters were thin — here's yesterday's top pick" in `fonts.body` at 32px, `colors.muted_text`.
- Handle bottom-left, page-num bottom-right (same as other slides).
- No borders, no backgrounds beyond `colors.background`.

---

## Dedup key

`SHA1(normalize(title) + '|' + canonical_host(source_url))`
- `normalize` = lowercase, strip punctuation, collapse whitespace
- `canonical_host` = `URL(source_url).hostname` with `www.` stripped
- 7-day window in `_MANIFEST.json → posted_stories`

---

## Caption format

- Hook line ≤125 chars (pre-truncate point in IG feed)
- Body ≤150 words total
- 8–12 hashtags selected from `brand.json.hashtags` pool of ≥25, weighted by story keywords; rotated daily.

---

## Timezone rule

All date math (folder names, cutoffs, manifest entries) uses `brand.json → timezone` via:
```
new Intl.DateTimeFormat('en-CA', { timeZone }).format(now)  // → "YYYY-MM-DD"
```

---

## Prerequisites

- [x] Claude plan supports Code Routines (Team/Enterprise confirmed)
- [ ] GitHub account ready
- [ ] Google Drive access
- [ ] Node.js 20+ locally (for pre-push renderer testing)

---

## Phase 1 — Config cleanup (~15 min, local)

- [ ] `brand.json`: remove orphan `_comment` key
- [ ] `brand.json`: remove unused `notification_email` field
- [ ] `brand.json`: add `"timezone": "America/New_York"` (user edits to their TZ)
- [ ] `brand.json`: leave `slack_channel` empty; README notes it's unused
- [ ] Drop `hero_image_url` capture from ROUTINE_PROMPT research (never rendered)
- [ ] Keep `research.md` per story, cap at ≤300 words bullets
- [ ] `config/sources.json`: restructure `newsletters` into tiers (see below)
- [ ] `config/sources.json`: expand `source_credibility` with new domains
- [ ] `brand.json → hashtags`: expand to ≥25 entries for rotation

Source tiers for `sources.json`:

**Tier 1 — daily-ingested, highest signal:**
- TLDR AI — `https://tldr.tech/ai`
- TLDR Founders — `https://tldr.tech/founders`
- TLDR Tech — `https://tldr.tech/tech`
- TLDR Data — `https://tldr.tech/data`
- The Deep View — `https://www.thedeepview.co/`

**Tier 2 — AI-specialist curation:**
- The Rundown AI — `https://www.therundown.ai/`
- Ben's Bites — `https://bensbites.com/`
- The Neuron — `https://www.theneurondaily.com/`
- AlphaSignal — `https://alphasignal.ai/`
- Import AI (Jack Clark) — `https://importai.substack.com/`

**Tier 3 — RSS feeds + web search** (existing `rss_feeds` + `search_queries`).

**Tier 4 — vendor blogs (last resort):**
- openai.com/blog, anthropic.com/news, deepmind.google/discover, huggingface.co/blog

## Phase 2 — New helper scripts

- [ ] `scripts/validate.js` (~80 LOC, stdlib only): enforces schema above, prints precise errors, exits 1 on fail.
- [ ] `scripts/fallback.js` (~100 LOC, stdlib only): `--from <past-day-dir> --to <today-dir>` — copies carousels + stories, prepends `icymi_banner` slide, re-invokes render.js on modified JSON for the banner PNG only.
- [ ] `scripts/dry-run.js` (~40 LOC): runs validate + render on `test/` fixtures into `/tmp/ai-news-dry-run/`.
- [ ] `package.json`: add `"dry-run": "node scripts/dry-run.js"` script.

## Phase 3 — Harden `scripts/render.js`

- [ ] 4s Google Fonts timeout; if hit, log `font_fallback: true` instead of silently shipping system font.
- [ ] Per-slide `try/catch` in the screenshot loop; bad slide logs + skips, rest of carousel continues.
- [ ] Add `--skip-font-check` CLI flag for local testing.
- [ ] Add `icymi_banner` case to slide type switch (matches pinned visual spec above).
- [ ] Startup check: fail fast if any `TODO_` sentinel present in `brand.json` (color/font/handle fields).

## Phase 4 — Rewrite `ROUTINE_PROMPT.md` (the 12-step resilient flow)

- [ ] **Step 0 — Pre-flight.** Read configs. Abort on `TODO_` sentinel. Compute `now`, `today_str` (YYYY-MM-DD in `brand.json.timezone`), `cutoff = now - 24h`. If `output/today_str/_LOG.md` shows `status: success`, exit early (idempotency).
- [ ] **Step 1 — Tiered research.** Fetch Tier 1 → 2 → 3 → 4, 2 retries + 1s backoff per source. Stop when ≥`min_stories` strong candidates. Log each source `ok` / `failed(reason)`. Never abort on one-source failure.
- [ ] **Step 2 — Dedup against ledger.** Load `_MANIFEST.json.posted_stories` (7 days). Drop matches by dedup key.
- [ ] **Step 3 — Rank + select** 3–5 stories: recency × credibility × niche × visual potential.
- [ ] **Step 4 — Scaffold folders** under `output/YYYY-MM-DD/NN_story-slug/`.
- [ ] **Step 5 — Generate copy** per story: `research.md` (≤300w bullets), `slides.json` (7 slides, 4:5), `story.json` (1 slide, 9:16). Copy rules: ≤9w headlines, ≤25w body (≤35 context), no em-dashes, numbers > adjectives, match voice, no fabrication, cite sources.
- [ ] **Step 6 — Validate.** `node scripts/validate.js` per story. Invalid → log error, skip that story's render only.
- [ ] **Step 7 — Render PNGs.** `npm install puppeteer` with 3 retries on first use. Per story: render carousel + story. Per-slide try/catch.
- [ ] **Step 8 — Digest files.** `_SUMMARY.md` (date, counts, per-story links). `_CAPTIONS.md` (per-story IG caption per caption format above).
- [ ] **Step 9 — Drive upload.** Find/create `drive_parent_folder` → `YYYY-MM-DD/` child → upload full tree. Retry once on failure.
- [ ] **Step 10 — Update `_MANIFEST.json`** at Drive parent (last 30 runs, last 7 days posted stories).
- [ ] **Step 11 — Fallback branch.** If selected < `min_stories` OR 0 PNGs rendered: read manifest → most recent `success` → `scripts/fallback.js` → mark `status: fallback`. Missing manifest = `status: partial`, proceed with what exists.
- [ ] **Step 12 — `_LOG.md`.** Always written. Final `status: success|partial|fallback`.

## Phase 5 — Update docs

- [ ] `README.md`: drop Slack section, add fallback/manifest explanation, update troubleshooting table.
- [ ] `docs/SETUP_CHECKLIST.md`: Phase 0 = plan check (marked done for user), remove Slack phase, add `npm run dry-run` verification step before live Routine.

## Phase 6 — Local verification

- [ ] `npm install` succeeds.
- [ ] `npm run dry-run` produces 7 + 1 PNGs in `/tmp/ai-news-dry-run/` at correct dimensions, on-brand.
- [ ] `node scripts/validate.js test/slides.json` exits 0.
- [ ] `echo '{"slides":[]}' > /tmp/bad.json && node scripts/validate.js /tmp/bad.json` exits 1 with readable error.
- [ ] `node scripts/fallback.js --from test/ --to /tmp/fb/` produces ICYMI banner + copied slides.

## Phase 7 — Fill config + push

- [ ] Replace every `TODO_` in `brand.json` (handle, brand_name, niche, niche_queries, voice, hashtags, timezone).
- [ ] Optional: tweak colors/fonts. Re-run `npm run dry-run` after any change.
- [ ] `git init && git add . && git commit -m "initial" && git push` to new GitHub repo.

## Phase 8 — Wire up the Routine

- [ ] `claude.ai` → Settings → Connectors: add Google Drive (OAuth), verify Web Search enabled.
- [ ] Create Drive folder matching `brand.json → drive_parent_folder`.
- [ ] `claude.ai/code/routines` → New routine:
  - Name: `Daily AI IG Content`
  - Trigger: Daily → 07:00 (user's TZ)
  - Repo: the pushed GitHub repo
  - Connectors: Google Drive, Web Search
  - Prompt: full contents of `ROUTINE_PROMPT.md`
  - Save.

## Phase 9 — Live validation

- [ ] Click **Run now**. Watch live log (6–12 min).
- [ ] Open Drive → today's folder. Verify: `_SUMMARY.md`, `_CAPTIONS.md`, `_LOG.md`, 3–5 story subfolders with full PNG sets, `_MANIFEST.json` updated at parent.
- [ ] **Known unknown:** on first run, check whether `npm install puppeteer` was cached from a prior run (look at Step 7 duration in `_LOG.md`). If not cached: either commit `node_modules/puppeteer` or pivot to `puppeteer-core` + container Chromium.
- [ ] Post one carousel + story to IG. Verify on real phone.
- [ ] Re-click **Run now** same day → should exit early with idempotency.

## Phase 10 — Induced-failure tests

- [ ] Disable all Tier-1 sources in `sources.json`. Run. Verify Tier 2+ still produces ≥2 stories.
- [ ] Disable all tiers. Run. Verify fallback branch triggers.
- [ ] Re-enable, commit.

## Phase 11 — 7-day shakedown

- [ ] Let it run unattended 7 days.
- [ ] Day 8: review `_MANIFEST.json` for `partial`/`fallback` statuses. Investigate.
- [ ] Iterate: tighten `niche`/`voice` in `brand.json`, tweak `render.js` CSS.

---

## Critical files (paths)

- `/Users/sahilmedtrics/Downloads/ai-news-ig/ROUTINE_PROMPT.md` — pipeline brain (primary rewrite, Phase 4)
- `/Users/sahilmedtrics/Downloads/ai-news-ig/config/brand.json` — clean + timezone (Phase 1)
- `/Users/sahilmedtrics/Downloads/ai-news-ig/config/sources.json` — tier restructure (Phase 1)
- `/Users/sahilmedtrics/Downloads/ai-news-ig/scripts/render.js` — hardening (Phase 3)
- `/Users/sahilmedtrics/Downloads/ai-news-ig/scripts/validate.js` — **new** (Phase 2)
- `/Users/sahilmedtrics/Downloads/ai-news-ig/scripts/fallback.js` — **new** (Phase 2)
- `/Users/sahilmedtrics/Downloads/ai-news-ig/scripts/dry-run.js` — **new** (Phase 2)
- `/Users/sahilmedtrics/Downloads/ai-news-ig/package.json` — add dry-run script (Phase 2)
- `/Users/sahilmedtrics/Downloads/ai-news-ig/README.md` — trim (Phase 5)
- `/Users/sahilmedtrics/Downloads/ai-news-ig/docs/SETUP_CHECKLIST.md` — update phases (Phase 5)

---

## Risk register

| Risk | Mitigation |
|---|---|
| All newsletters blocked/URL changed same day | Tier 3 (RSS+search) + Tier 4 (vendor blogs) independent fallback; then ICYMI manifest fallback |
| Puppeteer Chromium install fails | 3 retries; if still fail, markdown-only + log; yesterday's fallback keeps IG stream alive |
| **Puppeteer install cost per Routine run** | Known unknown. Verify caching on first live run. Fallbacks: commit `node_modules/puppeteer`, or switch to `puppeteer-core` + system Chromium, or accept ~90s install |
| Drive OAuth expires | Upload fails, logs, container output preserved that run; re-auth; manifest gap visible; next run resumes |
| LLM emits malformed JSON | `validate.js` catches pre-render; skip that one story; rest continues |
| Google Fonts CDN slow | 4s timeout; logs `font_fallback: true`; slides render with system font instead of blocking |
| Same story on consecutive days | 7-day `posted_stories` ledger with SHA1 dedup key |
| `TODO_` left in brand.json after push | Step 0 pre-flight abort + render.js startup check |
| Double-run (manual + scheduled) | Step 0 idempotency check |
| First-run fallback (no manifest) | Treat missing manifest as empty; `status: partial`; day 1 may be thin |
| **IG algorithmic penalty for auto-looking content** | Not a pipeline bug. Calibrate expectations. Vary hook style per day; user can override slides before posting if desired |
| Team plan quota (25 runs/day) | 1 run/day = 4% of quota. Headroom for manual retries. |

---

## Progress notes

_Running log. Date-stamp entries as work happens._

- `2026-04-20` — plan v2 approved. Architecture: Claude Code Routines on Team/Enterprise (confirmed). Tier fallback + manifest + ICYMI fallback design locked. No notifications, no video. Starting Phase 1 next.
