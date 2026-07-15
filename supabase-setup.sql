-- Create profiles table
create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users not null unique,
  display_name text,
  bio text default '',
  city text default '',
  languages text[] default '{}',
  skills text[] default '{}',
  interests text[] default '{}',
  availability text default '',
  avatar_url text,
  verification_status text default 'not_submitted',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Enable Row Level Security
alter table public.profiles enable row level security;

-- Policy: users can view their own profile
create policy "Users can view own profile"
on public.profiles for select
using (auth.uid() = user_id);

-- Policy: users can update their own profile
create policy "Users can update own profile"
on public.profiles for update
using (auth.uid() = user_id);

-- Policy: users can insert their own profile (for registration)
create policy "Users can insert own profile"
on public.profiles for insert
with check (auth.uid() = user_id);