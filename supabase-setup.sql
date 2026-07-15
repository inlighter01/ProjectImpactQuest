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
