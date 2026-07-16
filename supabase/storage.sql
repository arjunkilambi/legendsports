-- LegendSports storage bucket for user-recorded feed clips.
-- Additive only — does not touch any existing tables or data, safe to run
-- alongside real users/content. Paste into Supabase SQL Editor -> New query -> Run.

insert into storage.buckets (id, name, public)
values ('clips', 'clips', true)
on conflict (id) do nothing;

drop policy if exists "Clips are publicly readable" on storage.objects;
create policy "Clips are publicly readable"
on storage.objects for select
using (bucket_id = 'clips');

-- uploaded paths are "<user id>/<filename>", so this only lets someone
-- upload into their own folder, not anyone else's.
drop policy if exists "Users can upload their own clips" on storage.objects;
create policy "Users can upload their own clips"
on storage.objects for insert
with check (bucket_id = 'clips' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Users can delete their own clips" on storage.objects;
create policy "Users can delete their own clips"
on storage.objects for delete
using (bucket_id = 'clips' and (storage.foldername(name))[1] = auth.uid()::text);
