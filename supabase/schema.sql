-- LegendSports backend schema (v2 — privacy-safe split)
-- This resets and recreates everything. Safe to run since no real data exists yet.
-- Paste all of this into Supabase SQL Editor -> New query -> Run.

drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_user();
drop table if exists public.feedback cascade;
drop table if exists public.feed_posts cascade;
drop table if exists public.answers cascade;
drop table if exists public.questions cascade;
drop table if exists public.session_summaries cascade;
drop table if exists public.sessions cascade;
drop table if exists public.recruit_details cascade;
drop table if exists public.profiles cascade;

-- PUBLIC identity: just a username, visible next to community posts, feed
-- clips, and coach search results. No real name, contact, or location here.
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  created_at timestamptz default now()
);
alter table public.profiles enable row level security;
create policy "Usernames are public" on public.profiles for select using (true);
create policy "Users can update own username" on public.profiles for update using (auth.uid() = id);

-- auto-create a public profile row whenever someone signs up
create function public.handle_new_user() returns trigger as $$
begin
  insert into public.profiles (id, username)
  values (new.id, coalesce(new.raw_user_meta_data->>'username', split_part(new.email,'@',1)));
  return new;
end;
$$ language plpgsql security definer set search_path = public;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- PRIVATE recruiting card details: full name, GPA, height/weight, location,
-- contact info. Only the owner can ever read or write this.
create table public.recruit_details (
  id uuid primary key references public.profiles(id) on delete cascade,
  fullname text,
  grad_year text,
  position text,
  height text,
  weight text,
  gpa text,
  club text,
  location text,
  contact text,
  highlight text,
  updated_at timestamptz default now()
);
alter table public.recruit_details enable row level security;
create policy "Users can view own recruit details" on public.recruit_details for select using (auth.uid() = id);
create policy "Users can insert own recruit details" on public.recruit_details for insert with check (auth.uid() = id);
create policy "Users can update own recruit details" on public.recruit_details for update using (auth.uid() = id);

-- PRIVATE full session data, including tracked-frame images. Owner only.
create table public.sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade not null,
  sport text,
  move text,
  legend text,
  level text,
  grade text,
  report jsonb,
  frames jsonb,
  created_at timestamptz default now()
);
alter table public.sessions enable row level security;
create policy "Users can view own sessions" on public.sessions for select using (auth.uid() = user_id);
create policy "Users can insert own sessions" on public.sessions for insert with check (auth.uid() = user_id);
create policy "Users can delete own sessions" on public.sessions for delete using (auth.uid() = user_id);

-- PUBLIC minimal stats only (no images, no written analysis) so the coach
-- search can show grades/sports/techniques without exposing anything private.
create table public.session_summaries (
  id uuid primary key,
  user_id uuid references public.profiles(id) on delete cascade not null,
  sport text,
  move text,
  grade text,
  created_at timestamptz default now()
);
alter table public.session_summaries enable row level security;
create policy "Session summaries are public" on public.session_summaries for select using (true);
create policy "Users can insert own summaries" on public.session_summaries for insert with check (auth.uid() = user_id);
create policy "Users can delete own summaries" on public.session_summaries for delete using (auth.uid() = user_id);

-- community Q&A (public)
create table public.questions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade not null,
  sport text,
  title text not null,
  body text,
  created_at timestamptz default now()
);
alter table public.questions enable row level security;
create policy "Questions viewable by everyone" on public.questions for select using (true);
create policy "Users can insert own questions" on public.questions for insert with check (auth.uid() = user_id);
create policy "Users can delete own questions" on public.questions for delete using (auth.uid() = user_id);

create table public.answers (
  id uuid primary key default gen_random_uuid(),
  question_id uuid references public.questions(id) on delete cascade not null,
  user_id uuid references public.profiles(id) on delete cascade not null,
  body text not null,
  created_at timestamptz default now()
);
alter table public.answers enable row level security;
create policy "Answers viewable by everyone" on public.answers for select using (true);
create policy "Users can insert own answers" on public.answers for insert with check (auth.uid() = user_id);
create policy "Users can delete own answers" on public.answers for delete using (auth.uid() = user_id);

-- highlights feed (public)
create table public.feed_posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade not null,
  title text not null,
  link text not null,
  description text,
  format text,
  created_at timestamptz default now()
);
alter table public.feed_posts enable row level security;
create policy "Feed viewable by everyone" on public.feed_posts for select using (true);
create policy "Users can insert own feed posts" on public.feed_posts for insert with check (auth.uid() = user_id);
create policy "Users can delete own feed posts" on public.feed_posts for delete using (auth.uid() = user_id);

-- feedback (private — only you and, later, an admin would see it)
create table public.feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade,
  category text,
  message text not null,
  created_at timestamptz default now()
);
alter table public.feedback enable row level security;
create policy "Users can insert own feedback" on public.feedback for insert with check (auth.uid() = user_id);
create policy "Users can view own feedback" on public.feedback for select using (auth.uid() = user_id);

-- teams + realtime chat (only visible to teammates, never public)
drop table if exists public.team_messages cascade;
drop table if exists public.team_members cascade;
drop table if exists public.teams cascade;

create table public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sport text,
  code text unique not null,
  owner uuid references public.profiles(id) on delete cascade not null,
  created_at timestamptz default now()
);

create table public.team_members (
  team_id uuid references public.teams(id) on delete cascade not null,
  user_id uuid references public.profiles(id) on delete cascade not null,
  joined_at timestamptz default now(),
  primary key (team_id, user_id)
);

create table public.team_messages (
  id uuid primary key default gen_random_uuid(),
  team_id uuid references public.teams(id) on delete cascade not null,
  user_id uuid references public.profiles(id) on delete cascade not null,
  text text not null,
  created_at timestamptz default now()
);

alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.team_messages enable row level security;

-- security definer bypasses RLS internally, so checking membership this way
-- (instead of a plain subquery on team_members inside its own policy) avoids
-- the "infinite recursion detected in policy for relation team_members" error.
create or replace function public.is_team_member(p_team_id uuid) returns boolean
language sql security definer set search_path = public stable as $$
  select exists (select 1 from public.team_members where team_id = p_team_id and user_id = auth.uid());
$$;

create policy "Members can view their teams" on public.teams for select using (
  public.is_team_member(id)
);

create policy "Members can view their team roster" on public.team_members for select using (
  public.is_team_member(team_id)
);
create policy "Users can leave a team" on public.team_members for delete using (user_id = auth.uid());

create policy "Members can view their team messages" on public.team_messages for select using (
  public.is_team_member(team_id)
);
create policy "Members can send messages to their teams" on public.team_messages for insert with check (
  user_id = auth.uid() and public.is_team_member(team_id)
);

-- create_team/join_team run with elevated privilege (security definer) so they can
-- create the team row AND the membership row together, since regular users are never
-- allowed to insert into teams/team_members directly (only via these two functions).
create or replace function public.create_team(p_name text, p_sport text) returns public.teams
language plpgsql security definer set search_path = public as $$
declare v_code text; v_team public.teams;
begin
  v_code := upper(substr(md5(random()::text),1,5));
  insert into public.teams (name, sport, code, owner) values (p_name, p_sport, v_code, auth.uid()) returning * into v_team;
  insert into public.team_members (team_id, user_id) values (v_team.id, auth.uid());
  return v_team;
end; $$;

create or replace function public.join_team(p_code text) returns public.teams
language plpgsql security definer set search_path = public as $$
declare v_team public.teams;
begin
  select * into v_team from public.teams where code = upper(p_code);
  if not found then raise exception 'No team found with that code.'; end if;
  insert into public.team_members (team_id, user_id) values (v_team.id, auth.uid()) on conflict do nothing;
  return v_team;
end; $$;

alter publication supabase_realtime add table public.team_messages;
