# plan.md — Daily AI-for-Business Research Brief (v4, Local Edition)

Living progress tracker. Tick items as done. Edit freely.

---

## Goal

Every morning at 7:00 AM, a macOS LaunchAgent invokes Claude Code CLI on the user's Mac, which reads ~10 AI newsletters + RSS + web search, ranks stories for **business owners** (tech and non-tech), and produces **10 text briefs** in `~/AINewsDaily/YYYY-MM-DD/`. Each brief has: reference metadata, detailed story (500–700 words), business-owner translation (300–500 words), and a self-contained Claude-Design-ready carousel prompt. Downloaded hero images sit alongside each brief. User picks which stories to post, pastes the carousel prompt into their design tool of choice, posts.

Morning flow: open `~/AINewsDaily/YYYY-MM-DD/` in Finder → skim `_SUMMARY.md` → pick 1–3 stories → paste `CAROUSEL PROMPT` into Claude Design → post. ~5–10 min.

**Out of scope:** rendering PNGs, auto-posting, analytics, multi-brand, notifications, video download, Google Drive, any cloud OAuth.

## Why local-only (v4 pivot from v3)

v3 used Claude Code Routines (cloud) + Google Drive upload. User's Claude Team account and Google Drive account are on different emails — Google OAuth keeps failing with a 400. Rather than keep fighting OAuth, pivot to the simplest possible architecture: Claude Code CLI on the user's Mac, scheduled by launchd, output to `~/AINewsDaily/`. No cloud, no OAuth, no cross-account friction.

Trade-off: Mac must be on or asleep at 07:00 (not powered off). For a morning schedule this is essentially always true.

---

## Architecture (one paragraph)

Single GitHub repo at `SamPatel-AI/ai-news-ig` hosts the pipeline definition. On the user's Mac, a `launchd` LaunchAgent at `~/Library/LaunchAgents/com.sampatel.ainews.plist` fires daily at 07:00 and runs `scripts/run-daily.sh`. The wrapper invokes `claude --permission-mode bypassPermissions < ROUTINE_PROMPT.md`, which starts the Claude Code CLI against the repo. Claude reads configs, fetches news (WebFetch, WebSearch), writes per-story `.txt` files to `~/AINewsDaily/YYYY-MM-DD/newsNN/newsNN.txt`, downloads hero images via `curl`, writes `_SUMMARY.md`, updates the cross-run manifest at `~/AINewsDaily/_MANIFEST.json`, and writes `_LOG.md`. Per-run stdout/stderr logs live in `~/AINewsDaily/_runs/`. No API keys — the CLI uses the user's existing Claude Max login.

---

## Phase 1 — Repo in place ✓
- [x] `ROUTINE_PROMPT.md` rewritten for local execution (10 steps, writes to `~/AINewsDaily/`)
- [x] `scripts/run-daily.sh` wrapper invokes `claude` with prompt via stdin
- [x] `scripts/com.sampatel.ainews.plist` LaunchAgent (StartCalendarInterval 07:00)
- [x] README.md + docs/SETUP_CHECKLIST.md updated for local-only
- [x] package.json pared down (no runtime deps)

## Phase 2 — Install the LaunchAgent on the Mac
- [ ] `cp scripts/com.sampatel.ainews.plist ~/Library/LaunchAgents/`
- [ ] `launchctl load ~/Library/LaunchAgents/com.sampatel.ainews.plist`
- [ ] Confirm: `launchctl list | grep com.sampatel.ainews`

## Phase 3 — First smoke test
- [ ] `./scripts/run-daily.sh` — run manually (6–12 min)
- [ ] `~/AINewsDaily/YYYY-MM-DD/_SUMMARY.md` exists
- [ ] 10 `newsNN/` folders, each with `newsNN.txt` (4 sections)
- [ ] `_LOG.md` final line: `status: success`
- [ ] `~/AINewsDaily/_MANIFEST.json` updated with today's entry
- [ ] Paste one `CAROUSEL PROMPT` into Claude Design — on-brand?

## Phase 4 — Idempotency + fallback verification (optional)
- [ ] Re-run `./scripts/run-daily.sh` same day → exits early
- [ ] Temporarily disable all sources, run → fallback branch triggers
- [ ] Restore sources

## Phase 5 — 7-day shakedown
- [ ] Let LaunchAgent run unattended 7 days
- [ ] Day 8: review `_MANIFEST.json` for partial/fallback statuses
- [ ] Iterate: `brand.json.voice`, `ranking_criteria` weights, CAROUSEL PROMPT template

---

## Critical files

- `ROUTINE_PROMPT.md` — 10-step local pipeline (primary ongoing edit target)
- `config/brand.json` — handle, niche, voice, timezone, colors/fonts, ranking weights
- `config/sources.json` — 10 newsletters, RSS, search queries
- `scripts/run-daily.sh` — shell wrapper (chmod +x, runs via launchd)
- `scripts/com.sampatel.ainews.plist` — LaunchAgent definition
- `~/AINewsDaily/` — output root (outside the repo, user's home)

---

## Risk register

| Risk | Mitigation |
|---|---|
| Mac off at 07:00 | launchd runs at next wake; missed days visible as manifest gap |
| Mac awake but locked | launchd runs regardless of login state; tools work headless |
| Claude CLI not in PATH under launchd | `run-daily.sh` sets explicit PATH including `~/.local/bin` and homebrew dirs |
| All newsletters down | RSS + search independent fallback pool |
| Fewer than 5 stories | Fallback branch copies yesterday's folder into today's |
| Image download fails | Per-image log, brief kept |
| Same story as yesterday | 7-day SHA1 dedup ledger in `_MANIFEST.json` |
| `TODO_` left in brand.json | Step 0 abort |
| Tone/depth off | Iterate on prompt + brand.json.voice |
| CLI auth expires | User re-runs `claude` interactively once to refresh session |

---

## Progress notes

- `2026-04-20` — v3 text-only pipeline pushed to GitHub. Cloud Routines + Drive design.
- `2026-04-21` — v4 pivot to pure local. Reason: Google Drive OAuth failing due to user's Claude email ≠ Drive email. Switched from Routines (cloud) to Claude Code CLI + launchd (local). No cross-account OAuth needed. All code rewritten to write to `~/AINewsDaily/` instead of Drive.
- `2026-04-21 later` — Smoke tests confirmed pipeline works end-to-end. Run 1 produced 5 stories (6/10 newsletter URLs returned JS-rendered landing pages with no content). Audited all URLs, replaced with working permalinks (`/api/latest/<slug>` for TLDR, `/feed` for Substacks, archive domains). Run 2 produced 10 full-length stories from 48 candidates across 11 sources with dedup working against run 1. Pipeline repeatability verified.
- `2026-04-21 evening` — v4.1: Story selection rewritten from soft-score ranking (top 10 always) to explicit 4-gate filter + tier tagging in generous mode. `brand.json.ranking_criteria` removed, replaced with `selection_framework` (Priority / Solid / FYI tiers). `sources.json.max_stories` dropped — story count now follows the news, not a fixed cap. Brief's REFERENCE section gains `Tier:`, `Gate scores:`, and `Why kept:` fields for transparency. User runs the taste filter via the dashboard; pipeline over-collects rather than prunes aggressively.
