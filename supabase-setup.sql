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
drop policy if exists "Anyone can view an approved quest's organizer profile" on public.profiles;
drop policy if exists "Organizers can view their participants' profiles" on public.profiles;
create policy "Users can view own profile" on public.profiles for select using (auth.uid() = user_id);
-- v0.10.0: quest-details.html shows the organizer's name/trust/verification badge to
-- anyone viewing an approved quest, and quest-details.html's participant list (Feature 5)
-- lets the organizer see the same for each of their volunteers. Without these, both
-- reads would silently return null under the self-only policy above.
create policy "Anyone can view an approved quest's organizer profile" on public.profiles for select
using (exists (select 1 from public.quests q where q.creator_id = profiles.user_id and q.status = 'approved'));
create policy "Organizers can view their participants' profiles" on public.profiles for select
using (exists (
  select 1 from public.quest_participants qp
  join public.quests q on q.id = qp.quest_id
  where qp.user_id = profiles.user_id and q.creator_id = auth.uid()
));
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

-- ============================================================
-- Impact Quest v0.10.0: Quest Participation & Notifications
-- Safe to run more than once (idempotent).
-- ============================================================

-- ---------- Reputation columns on profiles ----------
alter table public.profiles add column if not exists impact_points integer not null default 0;
alter table public.profiles add column if not exists trust_score numeric(4,1) not null default 0.0 check (trust_score between 0 and 10);
alter table public.profiles add column if not exists completed_quests_count integer not null default 0;
alter table public.profiles add column if not exists joined_quests_count integer not null default 0;
alter table public.profiles add column if not exists people_helped_count integer not null default 0;

-- ---------- Pinned announcement surfaced in the Quest Lobby ----------
alter table public.quests add column if not exists pinned_announcement text;
alter table public.quests add column if not exists pinned_announcement_at timestamptz;
alter table public.quests add column if not exists cancelled_at timestamptz;
alter table public.quests add column if not exists cancel_reason text;
alter table public.quests drop constraint if exists quests_status_check;
alter table public.quests add constraint quests_status_check
  check (status in ('draft','submitted','pending_review','needs_changes','approved','rejected','archived','cancelled','completed'));

-- ---------- quest_participants: participation lifecycle ----------
-- Table already exists from v0.9.6. Extend it for v0.10.0 participation flows.
alter table public.quest_participants drop constraint if exists quest_participants_status_check;
alter table public.quest_participants add constraint quest_participants_status_check
  check (status in ('joined','waitlisted','cancelled','left','completed'));
alter table public.quest_participants add column if not exists left_at timestamptz;

create index if not exists quest_participants_quest_id_idx on public.quest_participants(quest_id);
create index if not exists quest_participants_user_id_idx on public.quest_participants(user_id);
create index if not exists quest_participants_status_idx on public.quest_participants(quest_id, status);

-- ---------- notifications ----------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  type text not null check (type in (
    'quest_joined','quest_left','quest_approved','quest_rejected',
    'organizer_announcement','quest_cancelled','quest_reminder','new_participant'
  )),
  title text not null,
  body text not null default '',
  quest_id uuid references public.quests(id) on delete cascade,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists notifications_user_id_created_at_idx on public.notifications(user_id, created_at desc);
create index if not exists notifications_user_unread_idx on public.notifications(user_id) where is_read = false;

alter table public.notifications enable row level security;
drop policy if exists "Users can read own notifications" on public.notifications;
drop policy if exists "Users can mark own notifications read" on public.notifications;
create policy "Users can read own notifications" on public.notifications for select using (auth.uid() = user_id);
create policy "Users can mark own notifications read" on public.notifications for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
-- Intentionally NO insert policy for regular users: notifications are only ever created
-- by the SECURITY DEFINER trigger functions below, which run as the table owner and
-- therefore bypass RLS. This prevents any client from forging notifications for other users.

-- ---------- quest_activity (lobby feed: announcements, joins, leaves, system events) ----------
create table if not exists public.quest_activity (
  id uuid primary key default gen_random_uuid(),
  quest_id uuid references public.quests(id) on delete cascade not null,
  actor_id uuid references auth.users(id) on delete set null,
  type text not null check (type in ('joined','left','announcement','approved','cancelled','system')),
  message text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists quest_activity_quest_id_created_at_idx on public.quest_activity(quest_id, created_at desc);

alter table public.quest_activity enable row level security;
drop policy if exists "Participants and creators can read quest activity" on public.quest_activity;
create policy "Participants and creators can read quest activity" on public.quest_activity for select
using (
  exists (select 1 from public.quests q where q.id = quest_activity.quest_id and q.creator_id = auth.uid())
  or exists (select 1 from public.quest_participants qp where qp.quest_id = quest_activity.quest_id and qp.user_id = auth.uid() and qp.status = 'joined')
);
-- No direct insert policy: activity rows are written by the SECURITY DEFINER trigger
-- functions/RPCs below (owner bypasses RLS), keeping the feed tamper-proof.

-- ---------- Participants can always read a quest they joined, even after it's
-- cancelled or completed (not just while status='approved'), so My Quests
-- (Joined / Completed / Cancelled tabs) can resolve the embedded quest row. ----------
drop policy if exists "Participants can read their joined quests" on public.quests;
create policy "Participants can read their joined quests" on public.quests for select
using (exists (select 1 from public.quest_participants qp where qp.quest_id = quests.id and qp.user_id = auth.uid()));

-- ---------- Quest organizers can view their participants (Feature 5) ----------
drop policy if exists "Creators can view their quest participants" on public.quest_participants;
create policy "Creators can view their quest participants" on public.quest_participants for select
using (exists (select 1 from public.quests q where q.id = quest_participants.quest_id and q.creator_id = auth.uid()));

-- ---------- Members can leave a quest they joined (Feature 2) ----------
drop policy if exists "Members can leave own participation" on public.quest_participants;
create policy "Members can leave own participation" on public.quest_participants for delete
using (auth.uid() = user_id);

-- ============================================================
-- Capacity + duplicate-join enforcement (server-side, race-safe)
-- ============================================================
create or replace function public.enforce_quest_join_rules()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quest record;
begin
  select id, status, volunteer_limit, joined_count, quest_date, creator_id
    into v_quest
    from public.quests
    where id = new.quest_id
    for update;

  if v_quest.id is null then
    raise exception 'Quest not found';
  end if;

  if v_quest.status <> 'approved' then
    raise exception 'This quest is not open for joining';
  end if;

  if v_quest.creator_id = new.user_id then
    raise exception 'Quest organizers cannot join their own quest as a volunteer';
  end if;

  if v_quest.quest_date is not null and v_quest.quest_date < current_date then
    raise exception 'This quest has already started or finished';
  end if;

  if v_quest.joined_count >= v_quest.volunteer_limit then
    raise exception 'Quest is full';
  end if;

  new.status := 'joined';
  return new;
end;
$$;

drop trigger if exists trg_enforce_quest_join_rules on public.quest_participants;
create trigger trg_enforce_quest_join_rules
  before insert on public.quest_participants
  for each row execute function public.enforce_quest_join_rules();

-- ============================================================
-- After a volunteer joins: bump counters, log activity, notify
-- ============================================================
create or replace function public.handle_quest_participant_joined()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quest record;
  v_display_name text;
begin
  update public.quests set joined_count = joined_count + 1, updated_at = now()
    where id = new.quest_id
    returning id, title, creator_id into v_quest;

  update public.profiles set joined_quests_count = joined_quests_count + 1
    where user_id = new.user_id;

  select coalesce(display_name, 'A community member') into v_display_name
    from public.profiles where user_id = new.user_id;

  insert into public.quest_activity (quest_id, actor_id, type, message)
    values (new.quest_id, new.user_id, 'joined', v_display_name || ' joined this quest.');

  insert into public.notifications (user_id, type, title, body, quest_id)
    values (new.user_id, 'quest_joined', 'You joined a quest', 'You joined "' || v_quest.title || '". See you there!', new.quest_id);

  insert into public.notifications (user_id, type, title, body, quest_id)
    values (v_quest.creator_id, 'new_participant', 'New volunteer joined', v_display_name || ' joined "' || v_quest.title || '".', new.quest_id);

  return new;
end;
$$;

drop trigger if exists trg_quest_participant_joined on public.quest_participants;
create trigger trg_quest_participant_joined
  after insert on public.quest_participants
  for each row execute function public.handle_quest_participant_joined();

-- ============================================================
-- Before a volunteer leaves: block leaving after the quest date
-- ============================================================
create or replace function public.enforce_quest_leave_rules()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quest_date date;
begin
  select quest_date into v_quest_date from public.quests where id = old.quest_id;
  if v_quest_date is not null and v_quest_date < current_date then
    raise exception 'You cannot leave a quest that has already happened. Contact the organizer instead.';
  end if;
  return old;
end;
$$;

drop trigger if exists trg_enforce_quest_leave_rules on public.quest_participants;
create trigger trg_enforce_quest_leave_rules
  before delete on public.quest_participants
  for each row execute function public.enforce_quest_leave_rules();

-- ============================================================
-- After a volunteer leaves: bump counters down, log, notify
-- ============================================================
create or replace function public.handle_quest_participant_left()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quest record;
  v_display_name text;
begin
  update public.quests set joined_count = greatest(joined_count - 1, 0), updated_at = now()
    where id = old.quest_id
    returning id, title, creator_id into v_quest;

  update public.profiles set joined_quests_count = greatest(joined_quests_count - 1, 0)
    where user_id = old.user_id;

  select coalesce(display_name, 'A community member') into v_display_name
    from public.profiles where user_id = old.user_id;

  insert into public.quest_activity (quest_id, actor_id, type, message)
    values (old.quest_id, old.user_id, 'left', v_display_name || ' left this quest.');

  insert into public.notifications (user_id, type, title, body, quest_id)
    values (old.user_id, 'quest_left', 'You left a quest', 'You left "' || v_quest.title || '".', old.quest_id);

  insert into public.notifications (user_id, type, title, body, quest_id)
    values (v_quest.creator_id, 'quest_left', 'A volunteer left', v_display_name || ' left "' || v_quest.title || '".', old.quest_id);

  return old;
end;
$$;

drop trigger if exists trg_quest_participant_left on public.quest_participants;
create trigger trg_quest_participant_left
  after delete on public.quest_participants
  for each row execute function public.handle_quest_participant_left();

-- ============================================================
-- After a moderator approves/rejects/cancels a quest: notify the creator
-- and, on cancellation, every joined participant.
-- ============================================================
create or replace function public.handle_quest_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_participant record;
begin
  if new.status = old.status then
    return new;
  end if;

  if new.status = 'approved' then
    insert into public.notifications (user_id, type, title, body, quest_id)
      values (new.creator_id, 'quest_approved', 'Quest approved', '"' || new.title || '" is now live for the community.', new.id);

  elsif new.status = 'rejected' then
    insert into public.notifications (user_id, type, title, body, quest_id)
      values (new.creator_id, 'quest_rejected', 'Quest needs attention', '"' || new.title || '" was not approved. ' || coalesce(new.review_notes, ''), new.id);

  elsif new.status = 'cancelled' then
    insert into public.quest_activity (quest_id, actor_id, type, message)
      values (new.id, new.creator_id, 'cancelled', 'The organizer cancelled this quest.' || case when new.cancel_reason is not null then ' Reason: ' || new.cancel_reason else '' end);

    for v_participant in
      select user_id from public.quest_participants where quest_id = new.id and status = 'joined'
    loop
      insert into public.notifications (user_id, type, title, body, quest_id)
        values (v_participant.user_id, 'quest_cancelled', 'Quest cancelled', '"' || new.title || '" was cancelled by the organizer.', new.id);
    end loop;

    update public.quest_participants set status = 'cancelled', left_at = now()
      where quest_id = new.id and status = 'joined';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_quest_status_change on public.quests;
create trigger trg_quest_status_change
  after update of status on public.quests
  for each row execute function public.handle_quest_status_change();

-- ============================================================
-- RPC: organizer cancels their own approved quest
-- ============================================================
create or replace function public.cancel_quest(p_quest_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.quests
    set status = 'cancelled', cancelled_at = now(), cancel_reason = p_reason
    where id = p_quest_id and creator_id = auth.uid() and status = 'approved';

  if not found then
    raise exception 'Only the organizer can cancel an active, approved quest.';
  end if;
end;
$$;

-- ============================================================
-- RPC: organizer posts a pinned announcement, visible in the Quest Lobby
-- ============================================================
create or replace function public.post_quest_announcement(p_quest_id uuid, p_message text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quest record;
  v_participant record;
begin
  if p_message is null or length(trim(p_message)) = 0 then
    raise exception 'Announcement cannot be empty';
  end if;

  update public.quests
    set pinned_announcement = p_message, pinned_announcement_at = now()
    where id = p_quest_id and creator_id = auth.uid()
    returning id, title into v_quest;

  if v_quest.id is null then
    raise exception 'Only the organizer can post an announcement for this quest.';
  end if;

  insert into public.quest_activity (quest_id, actor_id, type, message)
    values (p_quest_id, auth.uid(), 'announcement', p_message);

  for v_participant in
    select user_id from public.quest_participants where quest_id = p_quest_id and status = 'joined'
  loop
    insert into public.notifications (user_id, type, title, body, quest_id)
      values (v_participant.user_id, 'organizer_announcement', 'Organizer announcement', p_message, p_quest_id);
  end loop;
end;
$$;

-- ============================================================
-- Prepared for future scheduling (pg_cron / edge function cron):
-- sends a "Quest Reminder" notification to everyone joined on a quest
-- happening tomorrow. Not invoked automatically by this script — see
-- docs/FOUNDER_NOTES.md for the one-time pg_cron setup step.
-- ============================================================
create or replace function public.send_quest_reminders()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sent integer := 0;
  v_row record;
begin
  for v_row in
    select qp.user_id, q.id as quest_id, q.title
      from public.quest_participants qp
      join public.quests q on q.id = qp.quest_id
      where qp.status = 'joined'
        and q.status = 'approved'
        and q.quest_date = current_date + 1
        and not exists (
          select 1 from public.notifications n
          where n.user_id = qp.user_id and n.quest_id = q.id and n.type = 'quest_reminder'
            and n.created_at > now() - interval '2 days'
        )
  loop
    insert into public.notifications (user_id, type, title, body, quest_id)
      values (v_row.user_id, 'quest_reminder', 'Quest tomorrow', '"' || v_row.title || '" is happening tomorrow. Don''t forget!', v_row.quest_id);
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end;
$$;

-- ============================================================
-- Impact Quest v0.10.1 — HOTFIX: infinite recursion in RLS policies
-- ============================================================
-- v0.10.0 added policies where quests' policy reads quest_participants,
-- and quest_participants' policy reads quests (and similarly profiles
-- <-> quests). Postgres evaluates a policy's subquery under that target
-- table's own RLS, so checking policy A re-triggers policy B, which
-- re-triggers policy A — "infinite recursion detected in policy for
-- relation quest_participants". This showed up on Save Profile because
-- profile.js calls .select() after .update(), which forces Postgres to
-- re-check every SELECT policy on profiles, including the recursive ones.
--
-- Fix: move every cross-table check into a small SECURITY DEFINER
-- function. Such functions run as the table owner, and the owner
-- bypasses RLS on their own tables by default — so the lookup inside
-- the function does NOT re-trigger policy evaluation, breaking the
-- cycle. This is idempotent and safe to run even if v0.10.0's policies
-- were never applied.

create or replace function public.quest_creator(p_quest_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select creator_id from public.quests where id = p_quest_id;
$$;

create or replace function public.is_quest_participant(p_quest_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.quest_participants
    where quest_id = p_quest_id and user_id = p_user_id
  );
$$;

create or replace function public.user_role(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where user_id = p_user_id;
$$;

-- ---------- quests: replace recursive policies with function-based ones ----------
drop policy if exists "Moderators can view review queue" on public.quests;
drop policy if exists "Moderators can update review queue" on public.quests;
create policy "Moderators can view review queue" on public.quests for select
using (public.user_role(auth.uid()) in ('moderator', 'admin'));
create policy "Moderators can update review queue" on public.quests for update
using (public.user_role(auth.uid()) in ('moderator', 'admin'))
with check (public.user_role(auth.uid()) in ('moderator', 'admin'));

drop policy if exists "Participants can read their joined quests" on public.quests;
create policy "Participants can read their joined quests" on public.quests for select
using (public.is_quest_participant(id, auth.uid()));

-- ---------- quest_participants: replace recursive policy ----------
drop policy if exists "Creators can view their quest participants" on public.quest_participants;
create policy "Creators can view their quest participants" on public.quest_participants for select
using (public.quest_creator(quest_id) = auth.uid());

-- ---------- profiles: replace recursive policies ----------
drop policy if exists "Anyone can view an approved quest's organizer profile" on public.profiles;
drop policy if exists "Organizers can view their participants' profiles" on public.profiles;
create policy "Anyone can view an approved quest's organizer profile" on public.profiles for select
using (
  exists (
    select 1 from public.quests q
    where q.creator_id = profiles.user_id and q.status = 'approved'
  )
);
create policy "Organizers can view their participants' profiles" on public.profiles for select
using (
  exists (
    select 1 from public.quest_participants qp
    where qp.user_id = profiles.user_id
      and public.quest_creator(qp.quest_id) = auth.uid()
  )
);

-- ---------- quest_activity: replace recursive policy ----------
drop policy if exists "Participants and creators can read quest activity" on public.quest_activity;
create policy "Participants and creators can read quest activity" on public.quest_activity for select
using (
  public.quest_creator(quest_activity.quest_id) = auth.uid()
  or public.is_quest_participant(quest_activity.quest_id, auth.uid())
);

-- ============================================================
-- Impact Quest v0.11.0 — Community Reputation & Achievement System
-- Safe to run more than once (idempotent).
--
-- Adds: XP/Level progression, tunable reputation scoring, an
-- attendance-verified quest completion flow (volunteer submits proof,
-- organizer confirms present/no-show), achievements/badges, a
-- reputation history ledger, and a global leaderboard.
--
-- Follows the v0.10.1 convention throughout: every cross-table check
-- goes through a small SECURITY DEFINER function, never a raw
-- cross-table RLS subquery, to avoid recursive policy evaluation.
-- ============================================================

-- ---------- XP / Level columns on profiles ----------
alter table public.profiles add column if not exists xp integer not null default 0 check (xp >= 0);
alter table public.profiles add column if not exists level integer not null default 1 check (level >= 1);

-- ---------- Tunable scoring constants (server-side only, never exposed to clients) ----------
create table if not exists public.reputation_config (
  key text primary key,
  value numeric not null,
  description text not null default '',
  updated_at timestamptz not null default now()
);

insert into public.reputation_config (key, value, description) values
  ('xp_per_completed_quest', 25, 'XP awarded when an organizer confirms a volunteer attended a quest.'),
  ('impact_points_per_completed_quest', 10, 'Impact Points awarded per confirmed quest completion.'),
  ('trust_score_gain_per_completion', 0.2, 'Trust Score increase per confirmed quest completion (capped at 10).'),
  ('trust_score_penalty_per_no_show', 0.5, 'Trust Score decrease when an organizer records a no-show (floored at 0).'),
  ('people_helped_per_completion', 1, 'People Helped counter increase per confirmed quest completion.')
on conflict (key) do nothing;

alter table public.reputation_config enable row level security;
-- Intentionally no select/insert/update policies for any client role. These
-- constants are read only from inside SECURITY DEFINER functions below,
-- which run as the table owner and bypass RLS. Tune values directly in the
-- Supabase SQL Editor: update public.reputation_config set value = ... where key = '...';

-- ---------- XP thresholds per level ----------
create table if not exists public.xp_levels (
  level integer primary key check (level >= 1),
  xp_required integer not null check (xp_required >= 0),
  title text not null
);

insert into public.xp_levels (level, xp_required, title) values
  (1, 0, 'Newcomer'),
  (2, 100, 'Helper'),
  (3, 250, 'Contributor'),
  (4, 500, 'Changemaker'),
  (5, 1000, 'Champion'),
  (6, 2000, 'Community Hero'),
  (7, 4000, 'Legend')
on conflict (level) do nothing;

alter table public.xp_levels enable row level security;
drop policy if exists "Anyone can read xp levels" on public.xp_levels;
create policy "Anyone can read xp levels" on public.xp_levels for select using (true);

-- ---------- Badge catalog ----------
create table if not exists public.badges (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text not null,
  icon text not null default '🏅',
  criteria_type text not null check (criteria_type in ('quests_completed','trust_score','impact_points','people_helped','joined_quests')),
  criteria_value numeric not null,
  created_at timestamptz not null default now()
);

insert into public.badges (code, name, description, icon, criteria_type, criteria_value) values
  ('first_quest', 'First Steps', 'Completed your first quest.', '🌱', 'quests_completed', 1),
  ('five_quests', 'Dedicated Volunteer', 'Completed 5 quests.', '🔥', 'quests_completed', 5),
  ('ten_quests', 'Community Pillar', 'Completed 10 quests.', '🏛️', 'quests_completed', 10),
  ('twentyfive_quests', 'Impact Veteran', 'Completed 25 quests.', '🎖️', 'quests_completed', 25),
  ('trust_builder', 'Trust Builder', 'Reached a Trust Score of 5.0.', '🤝', 'trust_score', 5),
  ('trusted_pillar', 'Trusted Pillar', 'Reached a Trust Score of 9.0.', '⭐', 'trust_score', 9),
  ('point_collector', 'Point Collector', 'Earned 100 Impact Points.', '💠', 'impact_points', 100),
  ('impact_master', 'Impact Master', 'Earned 500 Impact Points.', '👑', 'impact_points', 500),
  ('helping_hand', 'Helping Hand', 'Helped 10 people through completed quests.', '🙌', 'people_helped', 10),
  ('community_champion', 'Community Champion', 'Helped 50 people through completed quests.', '🏆', 'people_helped', 50)
on conflict (code) do nothing;

alter table public.badges enable row level security;
drop policy if exists "Anyone can read the badge catalog" on public.badges;
create policy "Anyone can read the badge catalog" on public.badges for select using (true);

-- ---------- Earned badges ----------
create table if not exists public.profile_badges (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete cascade not null,
  badge_id uuid references public.badges(id) on delete cascade not null,
  earned_at timestamptz not null default now(),
  unique (profile_id, badge_id)
);

create index if not exists profile_badges_profile_id_idx on public.profile_badges(profile_id);

alter table public.profile_badges enable row level security;
drop policy if exists "Anyone signed in can view earned badges" on public.profile_badges;
create policy "Anyone signed in can view earned badges" on public.profile_badges for select
using (auth.uid() is not null);
-- No insert/update/delete policy: badges are only ever awarded by
-- check_and_award_badges() below, a SECURITY DEFINER function.

-- ---------- Reputation history ledger ----------
create table if not exists public.reputation_history (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete cascade not null,
  quest_id uuid references public.quests(id) on delete set null,
  event_type text not null check (event_type in ('quest_completed','no_show','badge_earned','level_up')),
  xp_delta integer not null default 0,
  impact_points_delta integer not null default 0,
  trust_score_delta numeric(4,2) not null default 0,
  description text not null,
  created_at timestamptz not null default now()
);

create index if not exists reputation_history_profile_id_created_at_idx on public.reputation_history(profile_id, created_at desc);

create or replace function public.owns_profile(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.profiles where id = p_profile_id and user_id = auth.uid());
$$;

alter table public.reputation_history enable row level security;
drop policy if exists "Users can view their own reputation history" on public.reputation_history;
create policy "Users can view their own reputation history" on public.reputation_history for select
using (public.owns_profile(profile_id));
-- No insert/update/delete policy: history rows are only ever written by the
-- SECURITY DEFINER functions below.

-- ---------- Quest attendance / completion verification ----------
create table if not exists public.quest_attendance (
  id uuid primary key default gen_random_uuid(),
  quest_id uuid references public.quests(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  proof_text text not null default '',
  proof_url text,
  submitted_at timestamptz,
  status text not null default 'pending' check (status in ('pending','present','no_show')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  review_notes text,
  created_at timestamptz not null default now(),
  unique (quest_id, user_id)
);

create index if not exists quest_attendance_quest_id_idx on public.quest_attendance(quest_id);
create index if not exists quest_attendance_user_id_idx on public.quest_attendance(user_id);

alter table public.quest_attendance enable row level security;
drop policy if exists "Volunteers can view their own attendance record" on public.quest_attendance;
drop policy if exists "Organizers can view attendance for their quests" on public.quest_attendance;
create policy "Volunteers can view their own attendance record" on public.quest_attendance for select
using (auth.uid() = user_id);
create policy "Organizers can view attendance for their quests" on public.quest_attendance for select
using (public.quest_creator(quest_id) = auth.uid());
-- No insert/update policy: rows are only ever written by
-- submit_quest_completion() and decide_quest_completion() below, which
-- enforce the business rules (must be a joined participant, quest date
-- must have passed, only the organizer may decide, no re-deciding).

-- ---------- Notifications: new v0.11.0 types ----------
alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in (
    'quest_joined','quest_left','quest_approved','quest_rejected',
    'organizer_announcement','quest_cancelled','quest_reminder','new_participant',
    'completion_submitted','completion_approved','completion_rejected','badge_earned','level_up'
  ));

-- ============================================================
-- Recompute a profile's level from its current XP and, if it just
-- crossed a threshold, log it and notify the member. Called only from
-- decide_quest_completion() below, never directly by clients.
-- ============================================================
create or replace function public.recompute_level(p_user_id uuid, p_profile_id uuid, p_quest_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_xp integer;
  v_old_level integer;
  v_new_level integer;
  v_title text;
begin
  select xp, level into v_xp, v_old_level from public.profiles where id = p_profile_id;

  select level into v_new_level from public.xp_levels
    where xp_required <= v_xp order by level desc limit 1;

  if v_new_level is null or v_new_level = v_old_level then
    return;
  end if;

  select title into v_title from public.xp_levels where level = v_new_level;

  update public.profiles set level = v_new_level where id = p_profile_id;

  insert into public.reputation_history (profile_id, quest_id, event_type, description)
    values (p_profile_id, p_quest_id, 'level_up', 'Reached Level ' || v_new_level || ' — ' || v_title || '.');

  insert into public.notifications (user_id, type, title, body, quest_id)
    values (p_user_id, 'level_up', 'Level up!', 'You reached Level ' || v_new_level || ' — ' || v_title || '.', p_quest_id);
end;
$$;

-- ============================================================
-- Award any newly-qualifying badges for a profile. Called only from
-- decide_quest_completion() below, never directly by clients.
-- ============================================================
create or replace function public.check_and_award_badges(p_profile_id uuid, p_quest_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile record;
  v_user_id uuid;
  v_badge record;
  v_qualifies boolean;
begin
  select * into v_profile from public.profiles where id = p_profile_id;
  v_user_id := v_profile.user_id;

  for v_badge in
    select b.* from public.badges b
    where not exists (
      select 1 from public.profile_badges pb where pb.profile_id = p_profile_id and pb.badge_id = b.id
    )
  loop
    v_qualifies := case v_badge.criteria_type
      when 'quests_completed' then v_profile.completed_quests_count >= v_badge.criteria_value
      when 'trust_score' then v_profile.trust_score >= v_badge.criteria_value
      when 'impact_points' then v_profile.impact_points >= v_badge.criteria_value
      when 'people_helped' then v_profile.people_helped_count >= v_badge.criteria_value
      when 'joined_quests' then v_profile.joined_quests_count >= v_badge.criteria_value
      else false
    end;

    if v_qualifies then
      insert into public.profile_badges (profile_id, badge_id) values (p_profile_id, v_badge.id)
        on conflict (profile_id, badge_id) do nothing;

      insert into public.reputation_history (profile_id, quest_id, event_type, description)
        values (p_profile_id, p_quest_id, 'badge_earned', 'Earned the "' || v_badge.name || '" badge.');

      insert into public.notifications (user_id, type, title, body, quest_id)
        values (v_user_id, 'badge_earned', 'New badge earned', 'You earned the "' || v_badge.name || '" badge: ' || v_badge.description, p_quest_id);
    end if;
  end loop;
end;
$$;

-- ============================================================
-- RPC: a volunteer submits proof of completion for a quest they joined,
-- after the quest date has passed. Upserts a pending attendance record;
-- cannot overwrite a record the organizer has already decided.
-- ============================================================
create or replace function public.submit_quest_completion(p_quest_id uuid, p_proof_text text, p_proof_url text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quest record;
  v_participation record;
  v_existing record;
  v_display_name text;
begin
  if p_proof_text is null or length(trim(p_proof_text)) < 5 then
    raise exception 'Please describe what you did, in a few words.';
  end if;

  select id, title, creator_id, quest_date into v_quest from public.quests where id = p_quest_id;
  if v_quest.id is null then
    raise exception 'Quest not found';
  end if;

  if v_quest.quest_date is null or v_quest.quest_date > current_date then
    raise exception 'You can submit proof of completion once the quest date has passed.';
  end if;

  select id, status into v_participation from public.quest_participants
    where quest_id = p_quest_id and user_id = auth.uid();
  if v_participation.id is null or v_participation.status not in ('joined', 'completed') then
    raise exception 'Only volunteers who joined this quest can submit proof of completion.';
  end if;

  select status into v_existing from public.quest_attendance
    where quest_id = p_quest_id and user_id = auth.uid();
  if v_existing.status is not null and v_existing.status <> 'pending' then
    raise exception 'This quest''s completion has already been reviewed by the organizer.';
  end if;

  insert into public.quest_attendance (quest_id, user_id, proof_text, proof_url, submitted_at, status)
    values (p_quest_id, auth.uid(), trim(p_proof_text), p_proof_url, now(), 'pending')
  on conflict (quest_id, user_id) do update
    set proof_text = excluded.proof_text, proof_url = excluded.proof_url, submitted_at = now(), status = 'pending';

  select coalesce(display_name, 'A community member') into v_display_name
    from public.profiles where user_id = auth.uid();

  insert into public.quest_activity (quest_id, actor_id, type, message)
    values (p_quest_id, auth.uid(), 'system', v_display_name || ' submitted proof of completion for organizer review.');

  insert into public.notifications (user_id, type, title, body, quest_id)
    values (v_quest.creator_id, 'completion_submitted', 'Completion submitted for review', v_display_name || ' submitted proof of completion for "' || v_quest.title || '".', p_quest_id);
end;
$$;

-- ============================================================
-- RPC: the organizer confirms a volunteer's attendance (present or
-- no-show). On 'present', this is the single place reputation is
-- actually awarded: XP, Impact Points, Trust Score, People Helped,
-- the level-up check, and the badge check all happen here, inside one
-- transaction, keyed off the tunable reputation_config values.
-- ============================================================
create or replace function public.decide_quest_completion(p_quest_id uuid, p_target_user_id uuid, p_decision text, p_notes text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quest record;
  v_attendance record;
  v_profile record;
  v_xp_gain integer;
  v_points_gain integer;
  v_trust_gain numeric;
  v_trust_penalty numeric;
  v_people_gain integer;
begin
  if p_decision not in ('present', 'no_show') then
    raise exception 'Decision must be "present" or "no_show".';
  end if;

  select id, title, creator_id into v_quest from public.quests where id = p_quest_id;
  if v_quest.id is null or v_quest.creator_id <> auth.uid() then
    raise exception 'Only the organizer of this quest can review attendance.';
  end if;

  select * into v_attendance from public.quest_attendance
    where quest_id = p_quest_id and user_id = p_target_user_id;
  if v_attendance.id is null or v_attendance.status <> 'pending' then
    raise exception 'No pending completion submission was found for this volunteer.';
  end if;

  update public.quest_attendance
    set status = p_decision, reviewed_by = auth.uid(), reviewed_at = now(), review_notes = p_notes
    where id = v_attendance.id;

  if p_decision = 'present' then
    update public.quest_participants set status = 'completed'
      where quest_id = p_quest_id and user_id = p_target_user_id and status = 'joined';

    select value into v_xp_gain from public.reputation_config where key = 'xp_per_completed_quest';
    select value into v_points_gain from public.reputation_config where key = 'impact_points_per_completed_quest';
    select value into v_trust_gain from public.reputation_config where key = 'trust_score_gain_per_completion';
    select value into v_people_gain from public.reputation_config where key = 'people_helped_per_completion';

    update public.profiles set
        xp = xp + v_xp_gain,
        impact_points = impact_points + v_points_gain,
        trust_score = least(10, trust_score + v_trust_gain),
        completed_quests_count = completed_quests_count + 1,
        people_helped_count = people_helped_count + v_people_gain
      where user_id = p_target_user_id
      returning * into v_profile;

    insert into public.reputation_history (profile_id, quest_id, event_type, xp_delta, impact_points_delta, trust_score_delta, description)
      values (v_profile.id, p_quest_id, 'quest_completed', v_xp_gain, v_points_gain, v_trust_gain, 'Completed "' || v_quest.title || '".');

    insert into public.notifications (user_id, type, title, body, quest_id)
      values (p_target_user_id, 'completion_approved', 'Quest completion confirmed', 'Your organizer confirmed you attended "' || v_quest.title || '". +' || v_xp_gain || ' XP, +' || v_points_gain || ' Impact Points.', p_quest_id);

    perform public.recompute_level(p_target_user_id, v_profile.id, p_quest_id);
    perform public.check_and_award_badges(v_profile.id, p_quest_id);
  else
    select value into v_trust_penalty from public.reputation_config where key = 'trust_score_penalty_per_no_show';

    update public.profiles set trust_score = greatest(0, trust_score - v_trust_penalty)
      where user_id = p_target_user_id
      returning * into v_profile;

    insert into public.reputation_history (profile_id, quest_id, event_type, trust_score_delta, description)
      values (v_profile.id, p_quest_id, 'no_show', -v_trust_penalty, 'Recorded as a no-show for "' || v_quest.title || '".');

    insert into public.notifications (user_id, type, title, body, quest_id)
      values (p_target_user_id, 'completion_rejected', 'Attendance not confirmed', 'Your organizer recorded a no-show for "' || v_quest.title || '".' || case when p_notes is not null then ' ' || p_notes else '' end, p_quest_id);
  end if;
end;
$$;

-- ============================================================
-- RPC: global leaderboard. Returns only the whitelisted columns
-- meant to be public, regardless of the profiles table's own RLS.
-- ============================================================
create or replace function public.get_leaderboard(p_limit integer default 20)
returns table (
  user_id uuid, display_name text, avatar_url text, level integer, xp integer,
  impact_points integer, trust_score numeric, completed_quests_count integer, badge_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select p.user_id, p.display_name, p.avatar_url, p.level, p.xp,
         p.impact_points, p.trust_score, p.completed_quests_count,
         (select count(*) from public.profile_badges pb where pb.profile_id = p.id) as badge_count
  from public.profiles p
  order by p.impact_points desc, p.trust_score desc, p.xp desc
  limit greatest(1, least(p_limit, 100));
$$;
