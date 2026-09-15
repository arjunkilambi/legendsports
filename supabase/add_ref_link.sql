-- Additive migration: adds an optional reference-clip link (e.g. a YouTube,
-- TikTok, or Facebook video someone is comparing their clip against) to the
-- highlights feed. Safe to run against a live database with real data —
-- does not drop or touch anything else. Paste into Supabase SQL Editor ->
-- New query -> Run.

alter table public.feed_posts add column if not exists ref_link text;
