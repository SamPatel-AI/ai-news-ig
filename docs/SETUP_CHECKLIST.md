# Setup Checklist — ~30 min first time

## Phase 0 — Verify plan (1 min)
- [x] Claude **Team or Enterprise** plan active — Claude Code Routines require this tier
- [ ] Claude Code on the web enabled (Settings → Developer → enable Claude Code)
- [ ] GitHub account
- [ ] Google account with Drive
- [ ] Node.js 20+ installed locally (only needed for pre-push smoke test)

## Phase 1 — Repo (5 min)
- [ ] Create a new GitHub repo: `ai-news-ig` (or your chosen name)
- [ ] Push the contents of this folder into it
- [ ] Clone locally if you want to test the renderer

## Phase 2 — Brand config (5 min)

`config/brand.json` is pre-filled for `@SamPatel.AI` with niche "AI for business owners". Review and adjust:

- [ ] `handle` — matches your actual IG
- [ ] `brand_name` — free-text, used in Drive folder default
- [ ] `timezone` — IANA zone (default `America/New_York`)
- [ ] `niche` and `voice` — review; these drive all copy generation
- [ ] `colors` and `fonts` — tweak if desired, re-run dry-run after any change
- [ ] `drive_parent_folder` — default `AI News Daily`; change if you want a different folder

**Do not leave any `TODO_` prefix anywhere in `brand.json`** — the Routine aborts at Step 0 if it finds one.

## Phase 3 — Local renderer smoke test (5 min, strongly recommended)
- [ ] `cd ai-news-ig && npm install`
- [ ] `npm run dry-run`
- [ ] Open `/tmp/ai-news-dry-run/carousel/slide_01.png` — looks on-brand?
- [ ] Open `/tmp/ai-news-dry-run/story/story_01.png` — 9:16 story looks right?
- [ ] If not: edit CSS in `scripts/render.js`, re-run `npm run dry-run`. Iterate until happy.

The dry-run also validates JSON schemas — if validation fails, fix the test fixtures before proceeding.

## Phase 4 — Connect Google Drive (5 min)
- [ ] `claude.ai` → Settings → Connectors → add **Google Drive**, OAuth
- [ ] Verify **Web Search** is enabled (Settings → Features)
- [ ] In Google Drive, create a folder named `AI News Daily` (or whatever `brand.drive_parent_folder` is set to). The Routine will create dated subfolders inside it.

## Phase 5 — Create the Routine (5 min)
- [ ] Go to `claude.ai/code/routines` → **New routine**
- [ ] Name: `Daily AI IG Content` (or anything)
- [ ] Trigger: **Scheduled** → **Daily** → **07:00** (match your `brand.timezone`)
- [ ] Repository: your `ai-news-ig` GitHub repo
- [ ] Connectors: **Google Drive**, **Web Search**
- [ ] Prompt: paste the **entire contents** of `ROUTINE_PROMPT.md`
- [ ] Save

## Phase 6 — Test run
- [ ] From the Routines UI, click **Run now**
- [ ] Watch the live log for 6–12 min
- [ ] Check Drive → `AI News Daily` → today's folder should exist with:
  - `_SUMMARY.md`, `_CAPTIONS.md`, `_LOG.md`
  - 3–5 story subfolders, each with `research.md`, `slides.json`, `story.json`, full `carousel/` and `story/` PNGs
- [ ] Check `_MANIFEST.json` at the parent — today's entry present
- [ ] Open a carousel's `slide_01.png` — looks on-brand?
- [ ] Read `_CAPTIONS.md` — does the first caption feel like it speaks to a business owner?

## Phase 7 — Idempotency + fallback sanity checks (optional but confidence-building)
- [ ] Click **Run now** a second time same day — Routine should exit early (`_LOG.md` says "already ran today")
- [ ] Temporarily set most newsletters to `"enabled": false` in `sources.json`, commit, run. Verify RSS + search still yield stories.
- [ ] Re-enable all, set ALL sources to `"enabled": false`, commit, run. Verify `status: fallback` in `_LOG.md` and today's folder contains ICYMI content from yesterday.
- [ ] Restore `sources.json`, commit.

## Phase 8 — Go live
- [ ] Let the Routine run on schedule for 3 days
- [ ] On day 4, review:
  - Stories off for the business-owner audience? → adjust `brand.json.ranking_criteria` weights or tighten `niche`
  - Copy off-voice? → tighten `brand.json.voice` + add 1–2 example slide bodies to `ROUTINE_PROMPT.md` Step 5
  - Slides visually off? → iterate CSS in `scripts/render.js`
  - Missing a story type you'd want? → tell Claude in the prompt; adjust de-prioritize rules

## Debug quick-ref

| Symptom | First check |
|---|---|
| Routine didn't fire | `claude.ai/code/routines` → status + logs |
| 0 stories / fallback every day | `_LOG.md` → which sources failed? Are the URLs still correct? |
| Render failed | `_LOG.md` → puppeteer install or per-slide render errors |
| Drive empty | Re-authorize Drive connector |
| `TODO_` abort at Step 0 | Open `brand.json`; no field starting with `TODO_` should remain |
| Duplicate story day after | Check `_MANIFEST.json.posted_stories` — 7-day window should have prevented it |
| Off-brand copy | Tighten `brand.json.voice`, adjust `ranking_criteria`, add examples in `ROUTINE_PROMPT.md` |
| Font fallback every day | Google Fonts CDN slow; usually transient. Consider self-hosting fonts if persistent. |
