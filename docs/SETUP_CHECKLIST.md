# Setup Checklist — ~10 min first time (Local Edition)

## Phase 0 — Prerequisites
- [x] Claude Code CLI installed (`which claude` returns a path; `claude --version` works)
- [x] Claude Max (or any paid plan) — CLI uses your login, no API key
- [x] macOS (for `launchd`)

## Phase 1 — Review brand config (2 min)

Open `config/brand.json`. Fields currently pre-filled for `@SamPatel.AI`. Review:

- [ ] `handle` — your IG handle
- [ ] `brand_name` — free text
- [ ] `timezone` — default `America/New_York` (drives "today" calculation in the prompt)
- [ ] `niche` and `voice` — review; drives copy generation
- [ ] `colors` and `fonts` — injected into every CAROUSEL PROMPT
- [ ] Remove any `TODO_` values — the routine aborts at Step 0 if any remain

## Phase 2 — macOS permissions (1 min)

`launchd` on recent macOS (Ventura+) refuses to execute scripts living under `~/Downloads`, `~/Desktop`, or `~/Documents` unless `/bin/bash` has Full Disk Access. Symptom if skipped: `launchd-stderr.log` shows `Operation not permitted`.

**Grant it once:**

1. Open **System Settings** → **Privacy & Security** → **Full Disk Access**
2. Click the **`+`** button (unlock with your password)
3. Press **`⌘ + Shift + G`**, type `/bin/bash`
4. Select `bash`, click **Open**, make sure toggle is **on**
5. Do the same for `/bin/zsh`

Alternative: move this repo out of `~/Downloads` to `~/ai-news-ig` and update every hardcoded path in `scripts/*.plist` and `scripts/*.sh`.

## Phase 3 — Install the LaunchAgents (2 min)

Two LaunchAgents:
- **Daily news routine** — fires once a day at 10:00 local time, writes briefs and pushes them to Supabase
- **Worker poller** — fires every 120 seconds, refines script/carousel/IG rows the frontend marked as pending

```bash
cd /Users/sahilmedtrics/Downloads/ai-news-ig
cp scripts/com.sampatel.ainews.plist         ~/Library/LaunchAgents/
cp scripts/com.sampatel.ainews.workers.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.sampatel.ainews.plist
launchctl load ~/Library/LaunchAgents/com.sampatel.ainews.workers.plist
```

Verify:
```bash
launchctl list | grep com.sampatel
```
Expected output:
```
-  0  com.sampatel.ainews          # dash = not running right now, 0 = last exit ok
-  0  com.sampatel.ainews.workers
```

If either shows a non-zero exit code, check `~/AINewsDaily/_runs/launchd-stderr.log` for the error — usually "Operation not permitted" means Phase 2 was skipped.

## Phase 4 — First smoke test (6–12 min)

Run the daily routine manually (don't wait until 10 AM):

```bash
./scripts/run-daily.sh
```

When it finishes, verify:

- [ ] `~/AINewsDaily/YYYY-MM-DD/` (today's date) exists
- [ ] Inside: `_SUMMARY.md`, `_LOG.md`, and `newsNN/` subfolders
- [ ] Each `newsNN/newsNN.txt` contains all 4 sections (REFERENCE, STORY DETAILS, WHY IT MATTERS FOR BUSINESS OWNERS, CAROUSEL PROMPT)
- [ ] `_LOG.md` final line says `status: success`
- [ ] `~/AINewsDaily/_MANIFEST.json` has today's entry
- [ ] In Supabase: the `stories` table has today's rows (check the dashboard)

Paste the CAROUSEL PROMPT from any `newsNN.txt` into Claude Design → does it produce an on-brand carousel?

## Phase 5 — Idempotency + fallback sanity checks (optional)

- [ ] Run `./scripts/run-daily.sh` again same day → exits early with `already ran today`
- [ ] Disable all sources in `config/sources.json` (`"enabled": false`), run → verify `status: fallback` and yesterday's content surfaces under `fallback_from_YYYY-MM-DD/`
- [ ] Restore `sources.json`

## Phase 6 — Let it run (7 days)

The daily agent fires at 10:00 every morning. The worker poller runs every 2 minutes while the Mac is on. Each morning:

- [ ] Open the dashboard → pick 1–3 stories → click Script / Carousel / IG icons
- [ ] Within ~2 minutes the "Refining" chip clears and real content appears
- [ ] Paste carousel prompts into Claude Design, record scripts, post

## Phase 7 — Iterate after first week

Day 8 review:
- Stories off for the business-owner audience? → edit the 4 gates in Step 3 of `ROUTINE_PROMPT.md`, `brand.json.deprioritize`, or tighten `niche`. Each brief's REFERENCE section shows `Tier` and `Why kept` for transparency.
- Briefs too shallow / too long? → adjust word-count targets in Step 5 of `ROUTINE_PROMPT.md`
- Carousel prompts giving off-brand designs? → edit the CAROUSEL PROMPT template in Step 5, or the worker prompt in `scripts/worker-carousels.sh`
- Same story appearing twice? → check `_MANIFEST.json.posted_stories` dedup window

## Debug quick-ref

| Symptom | First check |
|---|---|
| Didn't run at 10:00 | `~/AINewsDaily/_runs/launchd-stderr.log` and `run-*.log` — any errors? |
| `claude: command not found` in logs | `scripts/run-daily.sh` PATH should include `~/.local/bin` (it does by default) |
| `Operation not permitted` | Phase 2 — grant bash Full Disk Access |
| 0 stories / fallback every day | `_LOG.md` per-source lines — are newsletter URLs reachable? |
| Mac was off at 10 AM | Runs on next wake. If powered off all day, that day is skipped; next fire is tomorrow at 10. |
| `TODO_` abort at Step 0 | Fill missing field in `brand.json` |
| Dashboard card stuck on "Refining" | `~/AINewsDaily/_runs/workers-*.log` — auth expired, or `generation_attempts` hit 3 |
| Carousel prompt gives off-brand design | Iterate on CAROUSEL PROMPT template in `ROUTINE_PROMPT.md` Step 5 |

## Uninstall (if needed)

```bash
launchctl unload ~/Library/LaunchAgents/com.sampatel.ainews.plist
launchctl unload ~/Library/LaunchAgents/com.sampatel.ainews.workers.plist
rm ~/Library/LaunchAgents/com.sampatel.ainews*.plist
```

`~/AINewsDaily/` stays until you delete it manually.
