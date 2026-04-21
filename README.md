# AI News → Instagram Content Routine

Autonomous daily pipeline for [@SamPatel.AI](https://instagram.com/SamPatel.AI) (or whatever handle you set). Every morning, a Claude Code Routine runs in Anthropic's cloud — researches AI news from 10 newsletters + RSS + web search, writes slide copy framed for **business owners** (tech and non-tech), renders branded PNGs via a headless browser, and uploads a dated folder to Google Drive. You wake up, drag PNGs to Instagram, post.

**Mac can be off. No API keys. Cloud = cloud.**

```
7:00 AM  Routine fires (Anthropic cloud, via your Team/Enterprise plan)
7:04 AM  Research done — 3–5 stories selected
7:08 AM  Copy written (slides.json + story.json + captions)
7:11 AM  PNGs rendered via puppeteer (1080×1350 carousel, 1080×1920 story)
7:12 AM  Uploaded to Google Drive, _MANIFEST.json updated
7:12 AM  Done. No notification — just check Drive.

You:     Open Drive → drag PNGs into IG → paste caption from _CAPTIONS.md → post. ~5 min.
```

## The audience this is built for

**Business owners who don't have time to keep up with AI** — a mix of tech-savvy founders and traditional owners (retail, services, agencies, e-commerce, SMB). Content translates today's AI news into **"what does this mean for running your business?"** — tool recommendations, cost/time impact, action items. No jargon without translation. Numbers over adjectives.

This isn't AI news for AI people. It's AI news for people who have a business to run.

## Why this works (no API keys needed)

Claude Code inside the Routine can:
- Search the web and fetch pages (for research)
- Write HTML/CSS fresh each morning (same rendering quality as Claude Design)
- Run `npm install puppeteer` and screenshot HTML pages at exact Instagram pixel dimensions
- Use the Google Drive connector to upload

One repo + one Routine = the whole system. Your Team/Enterprise Claude subscription powers everything.

## Project layout

```
ai-news-ig/
├── ROUTINE_PROMPT.md        ← The 12-step prompt the Routine runs every morning
├── plan.md                  ← Living progress tracker / spec
├── config/
│   ├── brand.json           ← Handle, niche, voice, colors, fonts, timezone, ranking weights
│   └── sources.json         ← 10 newsletters, RSS, search queries, retry config, credibility
├── scripts/
│   ├── render.js            ← Puppeteer PNG renderer (hardened: font timeout, per-slide try/catch)
│   ├── render.py            ← Playwright local-test mirror (optional)
│   ├── validate.js          ← JSON-schema check before render — catches malformed LLM output
│   ├── fallback.js          ← Builds ICYMI carousels from yesterday when today is thin
│   └── dry-run.js           ← Local smoke test: npm run dry-run
├── package.json             ← Node deps (puppeteer)
├── test/                    ← Reference slides.json + story.json fixtures
├── docs/
│   └── SETUP_CHECKLIST.md   ← ~30 min setup walkthrough
└── output/                  ← Routine writes here each morning (gitignored)
    └── YYYY-MM-DD/
        ├── _SUMMARY.md       ← stories + folder paths
        ├── _CAPTIONS.md      ← ready-to-paste IG captions
        ├── _LOG.md           ← per-source status, render status, final status
        └── 01_story-slug/
            ├── research.md           ← facts, stats, sources (≤300w bullets)
            ├── slides.json
            ├── story.json
            ├── carousel/slide_01.png ... slide_07.png  (1080×1350)
            └── story/story_01.png                       (1080×1920)
```

A second file lives in Drive alongside your daily folders: **`_MANIFEST.json`** — tracks last 30 runs + last 7 days of posted stories. This is how the pipeline dedupes across days and knows what to fall back to when today is thin.

## One-time setup (~30 min)

See [`docs/SETUP_CHECKLIST.md`](docs/SETUP_CHECKLIST.md) for the full walkthrough. In brief:

1. Push this folder to a new GitHub repo (e.g., `ai-news-ig`)
2. `brand.json` is pre-filled for [@SamPatel.AI](https://instagram.com/SamPatel.AI) — adjust if yours differs
3. Locally test the renderer: `npm install && npm run dry-run`
4. Connect Google Drive in `claude.ai` → Settings → Connectors
5. Create Drive folder `AI News Daily` (or whatever `brand.drive_parent_folder` is set to)
6. Create the Routine at `claude.ai/code/routines`:
   - Trigger: Daily → 07:00 America/New_York
   - Repo: your GitHub fork
   - Connectors: Google Drive, Web Search
   - Prompt: paste entire contents of `ROUTINE_PROMPT.md`
7. Click **Run now** to verify. First run is 6–12 min.

## Resilience — why this won't break

The pipeline has multiple independent layers so no single failure kills your daily post:

| Failure mode | Mitigation |
|---|---|
| One newsletter down or URL changed | 10 newsletters + RSS + web search run every day; any 2–3 surviving = enough stories |
| All newsletters fail the same day | RSS + search provide independent fallback pool |
| Still no qualifying stories | **ICYMI fallback**: rebuild today's folder from yesterday's successful run, prepended with a branded "ICYMI" slide. You still have content to post. |
| Puppeteer Chromium install flakes | 3 retries on `npm install`; if still fails, markdown is kept and fallback fills the gap |
| Google Fonts CDN slow | 4s timeout in `render.js`, logs `font_fallback: true`, slides render with system font rather than hanging |
| LLM emits malformed slide JSON | `validate.js` catches it pre-render, that one story's render is skipped, rest continue |
| Google Drive OAuth expires | Upload fails, logs it, local container output preserved that run; re-auth in connectors; next run resumes normally |
| Same story as yesterday | 7-day `posted_stories` dedup ledger in `_MANIFEST.json` with SHA1 title+host key |
| Double-run (manual + scheduled) | Step 0 idempotency check — exits early if today already has `status: success` |
| `TODO_` placeholder left in brand.json | Step 0 pre-flight abort + `render.js` startup check — fails loudly before producing off-brand output |

Every run writes `_LOG.md` with per-source status and a final `status: success|partial|fallback` line.

## Daily flow (after setup)

- **7:00 AM** — Routine fires, you do nothing
- **7:12 AM** — Drive folder ready (no notification — you check when you're ready)
- **Whenever** — open the Drive folder, drag PNGs into IG, paste caption from `_CAPTIONS.md`

## Iterating

**Want different slide style?** Edit `scripts/render.js` — the HTML/CSS per slide type is right there. Commit and the next Routine run picks it up.

**Want to refine story selection?** Edit `brand.json.ranking_criteria` weights (`business_applicability` is currently weighted highest) or `brand.json.deprioritize`.

**Want different tone?** Edit `brand.json.voice` and add 1–2 example slide bodies in `ROUTINE_PROMPT.md` Step 5.

**Want different schedule?** Edit the Routine trigger at `claude.ai/code/routines`. No code change.

## Plan limits (Team/Enterprise)

- **25 routine runs/day** — this uses 1. 96% headroom for manual re-runs.
- Tokens draw from your Team seat usage, no separate bill.

## What's NOT included

- Reel / TikTok video scripts — PNGs only.
- Auto-posting to Instagram — you drag PNGs in manually (~60 sec).
- Analytics on what performed — add later if you want.
- Multi-brand support — clone the repo + routine for a second brand.
- Email / Slack notifications — you check Drive each morning.

## Troubleshooting

| Symptom | First check |
|---|---|
| Routine didn't fire | `claude.ai/code/routines` → status + logs |
| 0 stories in folder | `_LOG.md` → `status: fallback`? which sources failed? |
| PNGs missing | `_LOG.md` → puppeteer install errors or per-slide render failures |
| Drive empty | Re-authorize Google Drive in Settings → Connectors |
| Off-brand copy | Tighten `brand.json.voice`, adjust `ranking_criteria` weights, add examples to `ROUTINE_PROMPT.md` Step 5 |
| Same story twice in a week | Check `_MANIFEST.json.posted_stories` — dedupe should have caught it; file a note |
| Routine runs but folder is "ICYMI" daily | Upstream sources are genuinely thin OR fetch is broken; inspect `_LOG.md` per-source lines |
| Font wrong on slides | `_LOG.md` shows `font_fallback`? Google Fonts CDN was slow. Usually self-resolves next run. |

---

Questions → open an issue on your fork. `ROUTINE_PROMPT.md` is the single source of truth the routine reads every morning — edit that to change behavior.
