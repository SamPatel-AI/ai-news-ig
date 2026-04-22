-- Adds a generation_status column to each derived table so the Mac-based
-- agent workers know which rows need agentic refinement.
--
-- Lifecycle per row:
--   1. Frontend inserts a row with placeholder content and generation_status = 'pending'
--   2. Mac worker polls for generation_status = 'pending', regenerates content
--      via Claude Code CLI with a niche-specific prompt
--   3. Worker updates the row with real content and sets generation_status = 'ready'
--   4. If generation fails 3 times, worker sets generation_status = 'failed' with
--      the error in generation_error
--
-- The frontend's UI shows a "Generating..." indicator while status = 'pending'
-- and swaps in the real content when status = 'ready'.

-- scripts: already has hook_line/beats/cta_line/script_text; add generation tracking
alter table public.scripts
  add column if not exists generation_status text not null default 'ready',
  add column if not exists generation_error text,
  add column if not exists generation_attempts int not null default 0,
  add column if not exists generation_requested_at timestamptz;

-- carousels: regenerate prompt_text + caption_text per-story to sharpen niche fit
alter table public.carousels
  add column if not exists generation_status text not null default 'ready',
  add column if not exists generation_error text,
  add column if not exists generation_attempts int not null default 0,
  add column if not exists generation_requested_at timestamptz;

-- ig_stories: regenerate prompt_text into a tight 9:16 spec
alter table public.ig_stories
  add column if not exists generation_status text not null default 'ready',
  add column if not exists generation_error text,
  add column if not exists generation_attempts int not null default 0,
  add column if not exists generation_requested_at timestamptz;

-- Workers pick up rows where status = 'pending'. Indexed for fast lookup.
create index if not exists scripts_pending_idx on public.scripts (generation_status)
  where generation_status in ('pending', 'failed');
create index if not exists carousels_pending_idx on public.carousels (generation_status)
  where generation_status in ('pending', 'failed');
create index if not exists ig_stories_pending_idx on public.ig_stories (generation_status)
  where generation_status in ('pending', 'failed');

-- Existing rows stay 'ready' (default) — workers will not retroactively regenerate
-- them. Only rows inserted after this migration with status 'pending' get processed.
