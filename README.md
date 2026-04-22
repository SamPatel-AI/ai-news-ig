# AI-for-Business Daily Research Brief (Local)

Autonomous daily research pipeline for **[@SamPatel.AI](https://instagram.com/SamPatel.AI)**. Every morning at 7:00 AM, a macOS LaunchAgent on your Mac invokes Claude Code CLI, which reads 10 AI newsletters + RSS + web search, filters stories through an explicit 4-gate framework for **business owners** (tech and non-tech), and writes every qualifying story as a text brief with carousel prompt and downloaded images to `~/AINewsDaily/YYYY-MM-DD/`. Stories are tagged `🔥 Priority / ⭐ Solid / 💡 FYI` so you can skim by relevance. You open the folder, pick the ones you want, paste the carousel prompt into Claude Design, and post.

**Generous collection, not a fixed top-10.** Quiet days yield 3–5 stories, busy days 15–20. The gates — not an arbitrary cap — decide the count.

**No API keys. No cloud. No Google Drive. No GitHub OAuth required at runtime.** Just your Claude Max subscription and your Mac.

```
7:00 AM  LaunchAgent fires (on your Mac)
7:04 AM  10 newsletters + RSS + web search fetched
7:08 AM  Candidates filtered through 4 gates (business applicability,
         concrete substance, niche match, dedup)
7:12 AM  Every passing story tagged Priority / Solid / FYI and written
         with hero images
7:14 AM  Output ready at ~/AINewsDaily/YYYY-MM-DD/ (grouped by tier)

You:     Open folder → skim _SUMMARY.md → pick stories that catch your
         eye → paste CAROUSEL PROMPT into Claude Design → post. ~5-10 min.
```

## Audience this is built for

**Business owners who don't have time to keep up with AI** — a mix of tech-savvy founders and traditional owners (retail, services, agencies, e-commerce, SMB). Content translates today's AI news into **"what does this mean for running your business?"** — tool recommendations, cost/time impact, action items. No jargon without translation.

## What you get every morning

```
~/AINewsDaily/YYYY-MM-DD/
├── _SUMMARY.md                  ← 10-story menu with one-liners
├── _LOG.md                      ← per-source status, final status
├── news01/
│   ├── news01.txt               ← 4 sections: REFERENCE / STORY DETAILS /
│   │                              WHY IT MATTERS FOR BUSINESS OWNERS /
│   │                              CAROUSEL PROMPT
│   ├── news01_1.png             ← hero image
│   └── news01_2.png             ← inline images
├── news02/ ...
└── news10/ ...

~/AINewsDaily/_MANIFEST.json     ← cross-day state: last 30 runs,
                                    7-day story dedup ledger
~/AINewsDaily/_runs/             ← launchd + script logs
```

The `CAROUSEL PROMPT` section inside each `newsNN.txt` is a self-contained, Claude-Design-ready prompt. Paste into Claude Design (or Canva / ChatGPT / any AI design tool) to get a finished 7-slide carousel in your brand style.

## Why this works

Claude Code CLI runs locally on your Mac. It can:
- Fetch newsletter pages (WebFetch)
- Run web searches (WebSearch)
- Download images (curl via Bash)
- Write files (Write)
- Update the manifest (Read + Write)

All powered by your existing Claude Max login. No API keys, no external auth.

A `launchd` LaunchAgent (scheduled system job) fires the job at 07:00 daily. Your Mac needs to be on or sleeping — not powered off. If it's asleep at 07:00, launchd runs the job when the Mac next wakes. If it's been off for days, the next launchd fire catches you up with whatever sources are still valid (the fallback branch keeps posting content).

## Project layout

```
ai-news-ig/
├── ROUTINE_PROMPT.md           ← The 10-step prompt the CLI runs every morning
├── plan.md                     ← Progress tracker / spec
├── config/
│   ├── brand.json              ← Handle, niche, voice, colors, fonts, ranking weights
│   └── sources.json            ← 10 newsletters, RSS, search queries, retry config
├── scripts/
│   ├── run-daily.sh            ← Shell wrapper invoked by LaunchAgent
│   └── com.sampatel.ainews.plist  ← LaunchAgent definition (install to ~/Library/LaunchAgents/)
└── docs/
    └── SETUP_CHECKLIST.md      ← ~10 min setup walkthrough
```

## One-time setup (~10 min)

See [`docs/SETUP_CHECKLIST.md`](docs/SETUP_CHECKLIST.md) for full steps. In brief:

1. Install LaunchAgent:
   ```bash
   cp scripts/com.sampatel.ainews.plist ~/Library/LaunchAgents/
   launchctl load ~/Library/LaunchAgents/com.sampatel.ainews.plist
   ```
2. Smoke test: `./scripts/run-daily.sh` — wait 6–12 min, check `~/AINewsDaily/YYYY-MM-DD/`
3. Confirm scheduled with `launchctl list | grep com.sampatel.ainews`

## Resilience

| Failure mode | Mitigation |
|---|---|
| One newsletter down | 10 newsletters + RSS + web search; any 4+ = enough |
| All newsletters fail | RSS + search as independent fallback pool |
| Fewer than 5 qualifying stories | **Fallback day**: yesterday's folder linked into today's as `fallback_from_YYYY-MM-DD/` |
| Image download fails | Brief kept, image line says "none" or partial |
| Mac was off at 07:00 | launchd runs at next wake; missed days show as gaps in `_MANIFEST.json` |
| Same story as yesterday | 7-day SHA1 dedup ledger in `_MANIFEST.json` |
| Manual re-run same day | Step 0 idempotency check |

## Daily flow

- **07:00** — LaunchAgent fires on your Mac
- **07:14** — `~/AINewsDaily/YYYY-MM-DD/` ready
- **Whenever** — open folder, pick stories, paste CAROUSEL PROMPT into Claude Design, post

## Iterating

- **Story selection off?** Edit the 4 gates in Step 3 of `ROUTINE_PROMPT.md`, or the `deprioritize` list in `config/brand.json`. Tiers are defined in `brand.json.selection_framework.tiers`.
- **Tone off?** Edit `config/brand.json.voice` and the WHY IT MATTERS instructions in `ROUTINE_PROMPT.md`.
- **Carousel prompt giving off-brand designs?** Edit the CAROUSEL PROMPT template in `ROUTINE_PROMPT.md` Step 5.
- **Different schedule?** Edit `scripts/com.sampatel.ainews.plist` → `StartCalendarInterval` → reload: `launchctl unload ... && launchctl load ...`.

## What's NOT included

- Automated image/carousel rendering (you design carousels yourself using the prompt)
- Reel / TikTok scripts
- Auto-posting to Instagram
- Analytics
- Multi-brand
- Notifications
- Video download (URLs only)
- Google Drive / cloud sync (pure local)

## Troubleshooting

| Symptom | First check |
|---|---|
| No run at 07:00 | `launchctl list \| grep com.sampatel.ainews` and `~/AINewsDaily/_runs/` for logs |
| `claude: command not found` in run logs | `PATH` in `scripts/run-daily.sh` — Claude installs to `~/.local/bin` by default |
| 0 stories / fallback daily | `_LOG.md` → source fetch failures; update URLs in `sources.json` |
| `TODO_` abort | Fill missing field in `brand.json` |
| Images missing | `newsNN.txt` → `Media files saved locally` line |
| Off-brand tone | Tighten `brand.json.voice`, add examples to Step 5 of `ROUTINE_PROMPT.md` |

---

`ROUTINE_PROMPT.md` is the single source of truth. Edit that to change behavior.
