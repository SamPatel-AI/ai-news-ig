# AI-for-Business Daily Research Brief

Autonomous daily research pipeline for **[@SamPatel.AI](https://instagram.com/SamPatel.AI)**. Every morning at 7:00 AM, a Claude Code Routine runs in Anthropic's cloud — reads 10 AI newsletters + RSS + web search, ranks stories for **business owners** (tech and non-tech), and produces **10 text briefs** with carousel prompts and downloaded images. You open the Drive folder, pick the stories you want to post, paste the carousel prompt into Claude Design / Canva / any design tool, and post.

**No API keys. Mac can be off. Cloud = cloud.**

```
7:00 AM  Routine fires (Anthropic cloud, via your Team/Enterprise plan)
7:04 AM  10 newsletters + RSS + web search fetched
7:08 AM  Top 10 stories ranked for business-owner relevance
7:12 AM  Per-story briefs written, hero images downloaded
7:14 AM  Uploaded to Google Drive, _MANIFEST.json updated
         Done. No notification — just check Drive.

You:     Open Drive → pick 1–3 stories you want to post → paste
         the CAROUSEL PROMPT into Claude Design / Canva / your tool →
         post the result. ~5–10 min end-to-end.
```

## The audience this is built for

**Business owners who don't have time to keep up with AI** — a mix of tech-savvy founders and traditional owners (retail, services, agencies, e-commerce, SMB). Content translates today's AI news into **"what does this mean for running your business?"** — tool recommendations, cost/time impact, action items. No jargon without translation. Numbers over adjectives.

This isn't AI news for AI people. It's AI news for people who have a business to run.

## What you get every morning

```
output/YYYY-MM-DD/
├── _SUMMARY.md                  ← 10-story menu with one-liners
├── _LOG.md                      ← per-source status, final status line
├── news01/
│   ├── news01.txt               ← 4 sections: REFERENCE, STORY DETAILS,
│   │                              WHY IT MATTERS FOR BUSINESS OWNERS,
│   │                              CAROUSEL PROMPT
│   ├── news01_1.png             ← hero image from the source article
│   ├── news01_2.png             ← additional inline images
│   └── ...
├── news02/
│   └── ...
└── news10/
    └── ...
```

The `CAROUSEL PROMPT` section inside each `newsNN.txt` is a self-contained, Claude-Design-ready prompt. Paste it into Claude Design (or any AI design tool) and you get a finished 7-slide carousel in your brand style.

## Why this works (no API keys needed)

Claude Code inside the Routine can:
- Search the web and fetch pages (for research)
- Write the briefs fresh each morning
- Download hero images from article pages
- Use the Google Drive connector to upload

One repo + one Routine = the whole system. Your Team/Enterprise Claude subscription powers everything.

## Project layout

```
ai-news-ig/
├── ROUTINE_PROMPT.md        ← The 11-step prompt the Routine runs every morning
├── plan.md                  ← Progress tracker / spec
├── config/
│   ├── brand.json           ← Handle, niche, voice, colors, fonts, timezone, ranking weights
│   └── sources.json         ← 10 newsletters, RSS, search queries, retry config
├── docs/
│   └── SETUP_CHECKLIST.md   ← ~30 min setup walkthrough
└── output/                  ← Routine writes here each morning (gitignored; real copy in Drive)
```

A second file lives in Drive alongside your daily folders: **`_MANIFEST.json`** — tracks last 30 runs + last 7 days of posted stories. This is how the pipeline dedupes across days and knows what to fall back to when today is thin.

## One-time setup (~30 min)

See [`docs/SETUP_CHECKLIST.md`](docs/SETUP_CHECKLIST.md) for the full walkthrough. In brief:

1. Your GitHub repo is already set up at [SamPatel-AI/ai-news-ig](https://github.com/SamPatel-AI/ai-news-ig)
2. `config/brand.json` is pre-filled for `@SamPatel.AI` — adjust if desired
3. Connect Google Drive in `claude.ai` → Settings → Connectors
4. Create Drive folder `AI News Daily` (or whatever `brand.drive_parent_folder` is set to)
5. Create the Routine at `claude.ai/code/routines`:
   - Trigger: Daily → 07:00 America/New_York
   - Repo: SamPatel-AI/ai-news-ig
   - Connectors: Google Drive, Web Search, Web Fetch
   - Prompt: paste the entire contents of `ROUTINE_PROMPT.md`
6. Click **Run now** to verify. First run is 6–12 min.

## Resilience — why this won't break

The pipeline has multiple independent layers so no single failure kills your daily brief:

| Failure mode | Mitigation |
|---|---|
| One newsletter down or URL changed | 10 newsletters + RSS + web search run every day; any 4+ surviving = enough stories |
| All newsletters fail the same day | RSS + search provide independent fallback pool |
| Fewer than 5 qualifying stories | **Fallback day**: yesterday's full folder is re-linked under `fallback_from_YYYY-MM-DD/` in today's output. You still have briefs to work from. |
| Image download fails | Per-image log, brief kept, continue. Missing image doesn't break the story. |
| Video embed found | URL listed in `newsNN.txt`, never downloaded (would be fragile) — you click through and save manually if you want it |
| Google Drive OAuth expires | Upload fails, logs it, local container output preserved that run; re-auth in connectors; next run resumes normally |
| Same story as yesterday | 7-day `posted_stories` dedup ledger in `_MANIFEST.json` with SHA1 title+host key |
| Double-run (manual + scheduled) | Step 0 idempotency check — exits early if today already has `status: success` |
| `TODO_` placeholder left in brand.json | Step 0 pre-flight abort |

Every run writes `_LOG.md` with per-source status and a final `status: success|partial|fallback` line.

## Daily flow (after setup)

- **7:00 AM** — Routine fires, you do nothing
- **7:14 AM** — Drive folder ready (no notification — you check when you're ready)
- **Whenever** — open the Drive folder, pick 1–3 stories, paste the `CAROUSEL PROMPT` into your design tool, post the result

## Iterating

**Want to refine story selection?** Edit `brand.json.ranking_criteria` weights or `brand.json.deprioritize`.

**Want a different tone?** Edit `brand.json.voice` and the WHY IT MATTERS FOR BUSINESS OWNERS instructions in `ROUTINE_PROMPT.md`.

**Want the carousel prompt to match a different design style?** Edit the CAROUSEL PROMPT section of `ROUTINE_PROMPT.md` Step 5 — that's the template. Different layouts, different copy structure, whatever you want.

**Want different schedule?** Edit the Routine trigger at `claude.ai/code/routines`.

## Plan limits (Team/Enterprise)

- **25 routine runs/day** — this uses 1. 96% headroom.
- Tokens draw from your Team seat usage, no separate bill.

## What's NOT included

- Automated image/carousel rendering — you design carousels yourself using the prompt, which is actually better because you have taste
- Reel / TikTok video scripts — text briefs only
- Auto-posting to Instagram — you post manually
- Analytics on what performed — add later if you want
- Multi-brand support — clone the repo + routine for a second brand
- Email / Slack notifications — you check Drive each morning

## Troubleshooting

| Symptom | First check |
|---|---|
| Routine didn't fire | `claude.ai/code/routines` → status + logs |
| 0 stories / fallback every day | `_LOG.md` → which sources failed? URLs still correct? |
| Images missing | `newsNN.txt` → `Media files saved locally` line shows what got saved or failed |
| Drive empty | Re-authorize Google Drive in Settings → Connectors |
| Off-brand tone | Tighten `brand.json.voice`, adjust `ranking_criteria`, edit the WHY IT MATTERS FOR BUSINESS OWNERS instructions in `ROUTINE_PROMPT.md` |
| Same story twice in a week | Check `_MANIFEST.json.posted_stories` — dedupe should have caught it |
| Carousel prompt outputs off-brand design | Tweak the CAROUSEL PROMPT template in `ROUTINE_PROMPT.md` Step 5 |

---

`ROUTINE_PROMPT.md` is the single source of truth the routine reads every morning — edit that to change behavior.
