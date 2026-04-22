-- Drop the legacy `story_on_select` trigger + function.
--
-- History: this trigger was created in the initial Lovable-generated schema
-- when the UX concept was "flip stories.selected=true to auto-create child
-- rows with placeholder content." The Mac-side agentic worker architecture
-- replaced that with explicit Script/Carousel/IG icon clicks in TodaysNews.tsx,
-- which insert rows directly with generation_status='pending' so workers
-- refine them.
--
-- Leaving the old trigger in place creates a silent hazard: if any code path
-- sets stories.selected=true (manually, via a future UI button, or during a
-- data import), it would insert child rows with generation_status='ready'
-- (the column default), which workers skip entirely — so those rows would
-- permanently display placeholder content with no refinement, no error.
--
-- Safe to drop: no code flips stories.selected=true today; the column stays
-- for informational use but no longer triggers auto-creation.

drop trigger if exists stories_on_select on public.stories;
drop function if exists public.story_on_select();
