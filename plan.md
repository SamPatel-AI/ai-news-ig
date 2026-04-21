# plan.md — Daily AI-for-Business Research Brief (v3, text-only)

Living progress tracker. Tick items as done. Edit freely.

---

## Goal

Every morning at 7:00 AM, a Claude Code Routine reads ~10 AI newsletters + RSS + web search, ranks stories for **business owners** (tech and non-tech), and produces **10 text briefs** in Google Drive. Each brief has: reference metadata, detailed story (500–700 words), business-owner translation (300–500 words), and a self-contained Claude-Design-ready carousel prompt. Downloaded hero images sit alongside each brief. User picks which stories to post, pastes the carousel prompt into their design tool of choice, posts.

Morning flow: open Drive → skim `_SUMMARY.md` → pick 1–3 stories → paste `CAROUSEL PROMPT` into Claude Design → post. ~5–10 min.

**Out of scope:** rendering PNGs, auto-posting, analytics, multi-brand, notifications, video download.

## Why text-only (v3 pivot from v2)

v2 rendered carousels via puppeteer + CSS. That worked but:
- User has better design taste than my CSS
- Puppeteer install per cloud run is a fragility point (Chromium download)
- Design iteration was round-trip: fix CSS, re-render, inspect — slow

v3 scope: Claude is best at text and ranking. User is best at design. Pipeline hands off at the point where Claude's contribution is highest-leverage (researched brief + copy + structured design spec), user owns the visual execution.

---

## Architecture (one paragraph)

Single GitHub repo at `SamPatel-AI/ai-news-ig` is the deployable unit. `ROUTINE_PROMPT.md` is the brain — a Claude Code Routine reads it every morning and executes end-to-end in a fresh Ubuntu container with Google Drive + Web Search + Web Fetch connectors. Fetches news, ranks for business-owner relevance, writes 10 per-story `.txt` files (each with 4 named sections including a paste-ready Claude Design prompt), downloads hero images, writes daily summary, uploads tree to Drive, updates `_MANIFEST.json` at the Drive parent for cross-run memory (dedup, fallback, idempotency). Pure text + file I/O — zero runtime deps.

---

## Prerequisites (blocking)

- [x] Claude Team/Enterprise plan (confirmed)
- [x] GitHub repo exists at https://github.com/SamPatel-AI/ai-news-ig
- [ ] Google Drive access (user to connect)
- [ ] `claude.ai` → Connectors → Google Drive, Web Search, Web Fetch enabled

---

## Phase 1 — Repo pushed ✓
- [x] Config files: `brand.json` (pre-filled for @SamPatel.AI), `sources.json` (10 newsletters)
- [x] `ROUTINE_PROMPT.md` — 11-step text-only pipeline
- [x] `README.md`, `docs/SETUP_CHECKLIST.md`, `plan.md`

## Phase 2 — Dress rehearsal (local, with real data)
- [ ] Fetch today's newsletters via WebFetch
- [ ] Generate 10 `newsNN.txt` briefs for `output/2026-04-21/` with all 4 sections
- [ ] Download available hero images
- [ ] Write `_SUMMARY.md`
- [ ] Review — does a business owner think each brief is useful?
- [ ] Paste one CAROUSEL PROMPT into Claude Design — does it produce something on-brand?

## Phase 3 — Live Routine setup
- [ ] Connect Google Drive in `claude.ai`
- [ ] Create Drive folder `AI News Daily`
- [ ] Connect SamPatel-AI GitHub in `claude.ai`
- [ ] Create Routine: daily 07:00 America/New_York, repo `SamPatel-AI/ai-news-ig`, connectors: Google Drive + Web Search + Web Fetch, prompt = full `ROUTINE_PROMPT.md`
- [ ] Click **Run now** — first live test (6–12 min)

## Phase 4 — Live validation
- [ ] Drive folder has `_SUMMARY.md`, `_LOG.md`, 10 `newsNN/` subfolders each with `newsNN.txt` + images
- [ ] `_MANIFEST.json` updated at parent
- [ ] Paste one CAROUSEL PROMPT into Claude Design, verify finished carousel is on-brand
- [ ] Post one carousel to IG, evaluate on real phone
- [ ] Re-click **Run now** same day → should exit early with idempotency

## Phase 5 — Induced-failure tests (optional, confidence-building)
- [ ] Disable most newsletters in `sources.json`, push, verify RSS + search still yield stories
- [ ] Disable all sources, push, verify fallback branch triggers and `fallback_from_YYYY-MM-DD/` folder appears
- [ ] Re-enable everything, commit

## Phase 6 — 7-day shakedown
- [ ] Let it run unattended 7 days
- [ ] Day 8: review `_MANIFEST.json` for `partial`/`fallback` statuses; investigate
- [ ] Iterate on: `brand.json.voice`, `ranking_criteria` weights, CAROUSEL PROMPT template, deprioritize list

---

## Critical files

- `ROUTINE_PROMPT.md` — 11-step pipeline (primary ongoing edit target)
- `config/brand.json` — handle, niche, voice, timezone, colors/fonts (injected into CAROUSEL PROMPT), ranking weights, deprioritize
- `config/sources.json` — 10 newsletters, RSS, search queries, retry config, source_credibility map

---

## Per-story brief structure (what's in each `newsNN.txt`)

Four sections, exact delimiters:

```
=== REFERENCE ===
Source, URL, Published date, Author, Fetched timestamp, Media files saved,
Video URLs referenced (not downloaded)

=== STORY DETAILS ===
500–700 words, factual, dense. What happened, who's involved, numbers,
paraphrased quotes (≤15 words), prior context if materially relevant.

=== WHY IT MATTERS FOR BUSINESS OWNERS ===
300–500 words. Plain-English summary, who benefits most, 3–5 concrete use cases,
cost/time impact, 1–3 named tool alternatives, a "try this week" action, one
common mistake to avoid.

=== CAROUSEL PROMPT ===
Self-contained Claude-Design-ready prompt: brand tokens, design direction,
slide-by-slide layout + exact copy for all 7 slides + optional story slide.
Paste directly into Claude Design or any AI design tool.
```

Plus: `newsNN_1.png`, `newsNN_2.png`, ... for any hero/inline images that downloaded successfully.

---

## Risk register

| Risk | Mitigation |
|---|---|
| All newsletters blocked/URL changed same day | RSS + search independent fallback; then `fallback_from_YYYY-MM-DD/` link to yesterday |
| Image download fails | Per-image log, brief kept, continue. Missing images don't break anything. |
| Drive OAuth expires | Upload fails, logs, container output preserved; re-auth; next run resumes |
| Same story as yesterday | 7-day `posted_stories` SHA1 dedup ledger |
| `TODO_` left in brand.json | Step 0 abort with clear message |
| Double-run (manual + scheduled) | Step 0 idempotency |
| First-run fallback (no manifest) | Treat missing manifest as empty; `status: partial`; day 1 may be thinner |
| Brief-generation produces off-voice or shallow content | Iterate on Step 5 instructions + `brand.json.voice` over first few days |
| Team plan quota (25 runs/day) | 1 run/day = 4% of quota |

---

## Progress notes

- `2026-04-20` — v3 pivot. v2 PNG renderer + puppeteer scaffolding deleted. `ROUTINE_PROMPT.md` rewritten as 11-step text-only pipeline. README/SETUP_CHECKLIST updated. Repo pushed to `SamPatel-AI/ai-news-ig`. Awaiting local dress rehearsal (Phase 2) before live Routine setup (Phase 3).
