-- Create profiles table if it doesn't exist
create table if not exists public.profiles (
    id uuid references auth.users on delete cascade primary key,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Add columns for both business and employee profiles
alter table public.profiles
  add column if not exists account_type text check (account_type in ('business', 'employee')),
  add column if not exists email text,
  add column if not exists business_name text,
  add column if not exists industry text,
  add column if not exists website text,
  add column if not exists skills text[],
  add column if not exists experience_years integer,
  add column if not exists education text,
  add column if not exists resume_url text,
  add column if not exists name text,
  add column if not exists phone text,
  add column if not exists location text,
  add column if not exists bio text,
  add column if not exists photo_url text;

-- Update RLS policies
alter table public.profiles enable row level security;

-- Allow public read access to profiles
create policy "Public profiles are viewable by everyone"
  on profiles for select
  using (true);

-- Allow authenticated users to insert their own profile
create policy "Users can insert their own profile"
  on profiles for insert
  with check (auth.uid() = id);

-- Allow users to update their own profile
create policy "Users can update their own profile"
  on profiles for update
  using (auth.uid() = id);

-- Create storage bucket for avatars if it doesn't exist
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- Storage policies for avatars bucket
create policy "Avatar images are publicly accessible"
  on storage.objects for select
  using (bucket_id = 'avatars');

create policy "Users can upload avatar images"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars' 
    and auth.role() = 'authenticated'
  );

create policy "Users can update their own avatar images"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
  ); 