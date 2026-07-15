-- Impact Quest v0.9.6: profiles + Community Quest system
-- Run this in Supabase SQL Editor. It is safe to run more than once.

create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null unique,
  display_name text,
  bio text default '', city text default '', languages text[] default '{}',
  skills text[] default '{}', interests text[] default '{}', availability text default '',
  avatar_url text, verification_status text default 'not_submitted',
  created_at timestamptz default now(), updated_at timestamptz default now()
);

create table if not exists public.quests (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid references auth.users(id) on delete cascade not null,
  title text not null check (char_length(title) between 3 and 120),
  category text not null, description text not null check (char_length(description) between 10 and 2000),
  why_it_matters text not null check (char_length(why_it_matters) between 10 and 800),
  city text not null, barangay text not null, meeting_point text,
  quest_date date, quest_time time, duration text,
  volunteer_limit integer not null default 1 check (volunteer_limit between 1 and 500),
  joined_count integer not null default 0 check (joined_count >= 0),
  verification_method text not null, safety_notes text,
  status text not null default 'draft' check (status in ('draft','submitted','pending_review','needs_changes','approved','rejected','archived')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

-- Drafts may be incomplete. Submitted quests must include meaningful details.
-- These ALTER statements also repair databases created by the first v0.9.6 script.
alter table public.quests drop constraint if exists quests_description_check;
alter table public.quests drop constraint if exists quests_why_it_matters_check;
alter table public.quests add constraint quests_description_check
  check (status = 'draft' or char_length(description) between 10 and 2000);
alter table public.quests add constraint quests_why_it_matters_check
  check (status = 'draft' or char_length(why_it_matters) between 10 and 800);

create table if not exists public.quest_participants (
  id uuid primary key default gen_random_uuid(), quest_id uuid references public.quests(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  status text not null default 'joined' check (status in ('joined','waitlisted','cancelled','completed')),
  joined_at timestamptz not null default now(), unique (quest_id, user_id)
);

create table if not exists public.quest_bookmarks (
  id uuid primary key default gen_random_uuid(), quest_id uuid references public.quests(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null, created_at timestamptz not null default now(), unique (quest_id, user_id)
);

alter table public.profiles enable row level security;
alter table public.quests enable row level security;
alter table public.quest_participants enable row level security;
alter table public.quest_bookmarks enable row level security;

-- v0.9.7: assigned moderators can review submitted quests.
alter table public.profiles add column if not exists role text not null default 'member'
  check (role in ('member', 'moderator', 'admin'));
alter table public.quests add column if not exists review_notes text;
alter table public.quests add column if not exists reviewed_by uuid references auth.users(id);
alter table public.quests add column if not exists reviewed_at timestamptz;

drop policy if exists "Users can view own profile" on public.profiles;
drop policy if exists "Users can update own profile" on public.profiles;
drop policy if exists "Users can insert own profile" on public.profiles;
create policy "Users can view own profile" on public.profiles for select using (auth.uid() = user_id);
create policy "Users can update own profile" on public.profiles for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "Users can insert own profile" on public.profiles for insert with check (auth.uid() = user_id);

drop policy if exists "Anyone can read approved quests" on public.quests;
drop policy if exists "Creators can read own quests" on public.quests;
drop policy if exists "Members can create own quests" on public.quests;
drop policy if exists "Creators can update drafts" on public.quests;
create policy "Anyone can read approved quests" on public.quests for select using (status = 'approved');
create policy "Creators can read own quests" on public.quests for select using (auth.uid() = creator_id);
create policy "Members can create own quests" on public.quests for insert with check (auth.uid() = creator_id);
create policy "Creators can update drafts" on public.quests for update using (auth.uid() = creator_id and status in ('draft','needs_changes')) with check (auth.uid() = creator_id);

drop policy if exists "Moderators can view review queue" on public.quests;
drop policy if exists "Moderators can update review queue" on public.quests;
create policy "Moderators can view review queue" on public.quests for select
using (exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('moderator','admin')));
create policy "Moderators can update review queue" on public.quests for update
using (exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('moderator','admin')))
with check (exists (select 1 from public.profiles p where p.user_id = auth.uid() and p.role in ('moderator','admin')));

drop policy if exists "Members can read their participation" on public.quest_participants;
drop policy if exists "Members can join once" on public.quest_participants;
drop policy if exists "Members can manage own bookmarks" on public.quest_bookmarks;
create policy "Members can read their participation" on public.quest_participants for select using (auth.uid() = user_id);
create policy "Members can join once" on public.quest_participants for insert with check (auth.uid() = user_id);
create policy "Members can manage own bookmarks" on public.quest_bookmarks for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create index if not exists quests_status_created_at_idx on public.quests(status, created_at desc);
create index if not exists quests_creator_id_idx on public.quests(creator_id);
