# Setup Checklist — ~30 min first time

## Phase 0 — Verify plan
- [x] Claude **Team or Enterprise** plan active (Routines require this tier)
- [ ] Claude Code on the web enabled (Settings → Developer)
- [ ] GitHub account — repo already exists at https://github.com/SamPatel-AI/ai-news-ig
- [ ] Google account with Drive

## Phase 1 — Brand config review (5 min)

`config/brand.json` is pre-filled for `@SamPatel.AI` with niche "AI for business owners". Review and adjust:

- [ ] `handle` — matches your actual IG
- [ ] `brand_name` — free-text, used in Drive folder default
- [ ] `timezone` — IANA zone (default `America/New_York`)
- [ ] `niche` and `voice` — review; these drive all copy generation
- [ ] `colors` and `fonts` — these are injected into the CAROUSEL PROMPT for every story; pick colors/fonts you want the generated carousels to use
- [ ] `drive_parent_folder` — default `AI News Daily`; change if you want a different folder

**Do not leave any `TODO_` prefix anywhere in `brand.json`** — the Routine aborts at Step 0 if it finds one.

## Phase 2 — Connect Google Drive (5 min)
- [ ] `claude.ai` → Settings → Connectors → add **Google Drive**, OAuth
- [ ] Verify **Web Search** and **Web Fetch** are enabled (Settings → Features)
- [ ] In Google Drive, create a folder named `AI News Daily` (or whatever `brand.drive_parent_folder` is set to). The Routine creates dated subfolders inside it.

## Phase 3 — Connect GitHub (5 min, if not already done)
- [ ] `claude.ai` → Settings → Connectors → GitHub → connect the SamPatel-AI account
- [ ] Verify the `SamPatel-AI/ai-news-ig` repo is visible to Claude Code

## Phase 4 — Create the Routine (5 min)
- [ ] Go to `claude.ai/code/routines` → **New routine**
- [ ] Name: `Daily AI Brief` (or anything)
- [ ] Trigger: **Scheduled** → **Daily** → **07:00** (match your `brand.timezone`)
- [ ] Repository: `SamPatel-AI/ai-news-ig`
- [ ] Connectors: **Google Drive**, **Web Search**, **Web Fetch**
- [ ] Prompt: paste the **entire contents** of `ROUTINE_PROMPT.md`
- [ ] Save

## Phase 5 — Test run
- [ ] From the Routines UI, click **Run now**
- [ ] Watch the live log for 6–12 min
- [ ] Check Drive → `AI News Daily` → today's folder should exist with:
  - `_SUMMARY.md` (10-story menu)
  - `_LOG.md` (per-source status, final status)
  - `news01/` through `news10/` each with `newsNN.txt` and any downloaded images
- [ ] Check `_MANIFEST.json` at the parent — today's entry present
- [ ] Open `news01/news01.txt` — are all 4 sections present? (REFERENCE, STORY DETAILS, WHY IT MATTERS FOR BUSINESS OWNERS, CAROUSEL PROMPT)
- [ ] Copy the CAROUSEL PROMPT from one story, paste into Claude Design — does it produce an on-brand carousel?

## Phase 6 — Idempotency + fallback sanity checks (optional but confidence-building)
- [ ] Click **Run now** a second time same day — Routine exits early (`_LOG.md` says "already ran today")
- [ ] Temporarily set most newsletters to `"enabled": false` in `sources.json`, commit, run. Verify RSS + search still yield stories.
- [ ] Re-enable all, set ALL sources to `"enabled": false`, commit, run. Verify `status: fallback` in `_LOG.md` and today's folder contains `fallback_from_YYYY-MM-DD/` with yesterday's briefs.
- [ ] Restore `sources.json`, commit.

## Phase 7 — Go live
- [ ] Let the Routine run on schedule for 3 days
- [ ] On day 4, review:
  - Stories off for the business-owner audience? → adjust `brand.json.ranking_criteria` weights or tighten `niche`
  - Briefs too shallow or too long? → adjust word-count targets in Step 5 of `ROUTINE_PROMPT.md`
  - Carousel prompts producing off-brand designs? → edit the CAROUSEL PROMPT template in Step 5 of `ROUTINE_PROMPT.md`
  - Wrong stories prioritized? → add to `brand.json.deprioritize` or re-weight `ranking_criteria`

## Debug quick-ref

| Symptom | First check |
|---|---|
| Routine didn't fire | `claude.ai/code/routines` → status + logs |
| 0 stories / fallback every day | `_LOG.md` → which sources failed? Are URLs still correct? |
| `newsNN.txt` missing a section | Step 5 of `ROUTINE_PROMPT.md` specifies exact delimiters — check Claude followed them |
| Images missing | `newsNN.txt` → `Media files saved locally` line shows what got saved or failed |
| Drive empty | Re-authorize Drive connector |
| `TODO_` abort at Step 0 | Open `brand.json`; no field starting with `TODO_` should remain |
| Duplicate story day after | Check `_MANIFEST.json.posted_stories` — 7-day window should have prevented it |
| Off-brand tone in briefs | Tighten `brand.json.voice`, adjust ranking criteria, add examples to the Step 5 instructions |
| Carousel prompt giving bad designs | Iterate on the CAROUSEL PROMPT template in `ROUTINE_PROMPT.md` — that's where the design spec lives |
