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
- [ ] `colors` and `fonts` — injected into every CAROUSEL PROMPT; pick what you want your carousels to use
- [ ] Remove any `TODO_` values — the routine aborts at Step 0 if any remain

## Phase 2 — Install the LaunchAgent (2 min)

```bash
cd /Users/sahilmedtrics/Downloads/ai-news-ig
cp scripts/com.sampatel.ainews.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.sampatel.ainews.plist
```

Verify it's loaded:
```bash
launchctl list | grep com.sampatel.ainews
```
You should see a line like: `-  0  com.sampatel.ainews` (the `-` means not currently running; `0` is the last exit code).

## Phase 3 — First smoke test (6–12 min)

Run the job manually (don't wait until 7 AM):

```bash
./scripts/run-daily.sh
```

This does exactly what the LaunchAgent will do every morning. Watch the live output for 6–12 min. When it finishes:

- [ ] `~/AINewsDaily/2026-04-21/` (or today's date) exists
- [ ] Inside, `_SUMMARY.md` + `_LOG.md` + `news01/` through `news10/`
- [ ] Each `newsNN/` has `newsNN.txt` with all 4 sections (REFERENCE / STORY DETAILS / WHY IT MATTERS FOR BUSINESS OWNERS / CAROUSEL PROMPT)
- [ ] `_LOG.md` final line says `status: success`
- [ ] `~/AINewsDaily/_MANIFEST.json` has today's entry

Paste the CAROUSEL PROMPT from `news01/news01.txt` into Claude Design (claude.ai → Design). Does it produce an on-brand carousel?

## Phase 4 — Idempotency + fallback sanity checks (optional)

- [ ] Run `./scripts/run-daily.sh` again same day → exits early (`_LOG.md` says "already ran today")
- [ ] Temporarily disable all sources in `config/sources.json` (`"enabled": false`), run → verify `status: fallback` and yesterday's folder copied in as `fallback_from_YYYY-MM-DD/`
- [ ] Restore `sources.json`

## Phase 5 — Let it run (7 days)

The LaunchAgent now fires every morning at 07:00. Each morning:

- [ ] Open `~/AINewsDaily/` in Finder (drag to sidebar for one-click access)
- [ ] Open today's dated folder → skim `_SUMMARY.md`
- [ ] Pick 1-3 stories you want to post
- [ ] Open the chosen `newsNN.txt`, copy the `=== CAROUSEL PROMPT ===` section
- [ ] Paste into Claude Design, adjust if needed, export
- [ ] Post to Instagram; write caption based on the `WHY IT MATTERS` section

## Phase 6 — Iterate after first week

Day 8 review:
- Stories off for the business-owner audience? → edit the 4 gates in Step 3 of `ROUTINE_PROMPT.md` OR add to `brand.json.deprioritize` OR tighten `niche`. Stories now carry a `Tier: Priority|Solid|FYI` field and a `Why kept:` sentence so you can see exactly what earned a tier.
- Briefs too shallow / too long? → adjust word-count targets in Step 5 of `ROUTINE_PROMPT.md`
- Carousel prompts giving off-brand designs? → edit the CAROUSEL PROMPT template in Step 5
- Same story appearing twice? → check `_MANIFEST.json.posted_stories` dedup window

## Debug quick-ref

| Symptom | First check |
|---|---|
| Didn't run at 07:00 | `~/AINewsDaily/_runs/launchd-stderr.log` and `run-*.log` — any errors? |
| `claude: command not found` | `scripts/run-daily.sh` PATH — ensure `~/.local/bin` is first |
| 0 stories / fallback every day | `_LOG.md` per-source lines → are URLs reachable? |
| Mac was off at 7am | Job runs at next wake; check `_MANIFEST.json` for gaps |
| `TODO_` abort at Step 0 | Fill the missing field in `brand.json` |
| Carousel prompt gives off-brand design | Iterate on CAROUSEL PROMPT template in `ROUTINE_PROMPT.md` |

## Uninstall (if you ever need to)

```bash
launchctl unload ~/Library/LaunchAgents/com.sampatel.ainews.plist
rm ~/Library/LaunchAgents/com.sampatel.ainews.plist
```

`~/AINewsDaily/` stays until you delete it manually.
