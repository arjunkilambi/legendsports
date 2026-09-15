-- Additive migration: adds thumbnail support to the highlights feed.
-- Safe to run against a live database with real data — does not drop or
-- touch anything else. Paste into Supabase SQL Editor -> New query -> Run.

alter table public.feed_posts add column if not exists thumbnail text;
