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
  add column if not exists photo_url text,
  add column if not exists username text;

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

-- Make username nullable in profiles table
ALTER TABLE profiles 
ALTER COLUMN username DROP NOT NULL;

-- Add a trigger to generate a random username if none is provided
CREATE OR REPLACE FUNCTION generate_random_username()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.username IS NULL THEN
    -- Generate a random username using the first part of email and random numbers
    NEW.username := LOWER(
      SPLIT_PART(NEW.email, '@', 1) || 
      '_' || 
      FLOOR(RANDOM() * 100000)::TEXT
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS ensure_username_trigger ON profiles;

-- Create new trigger
CREATE TRIGGER ensure_username_trigger
BEFORE INSERT ON profiles
FOR EACH ROW
EXECUTE FUNCTION generate_random_username();

-- Create a skills table
create table if not exists public.skills (
    id uuid default gen_random_uuid() primary key,
    name text not null unique
);

-- Create a junction table for user skills
create table if not exists public.profile_skills (
    profile_id uuid references public.profiles(id) on delete cascade,
    skill_id uuid references public.skills(id) on delete cascade,
    primary key (profile_id, skill_id)
);

-- Add some common skills
insert into public.skills (name) values
    ('JavaScript'),
    ('Python'),
    ('React'),
    ('Flutter'),
    ('SQL'),
    ('Java'),
    ('C++'),
    ('Project Management'),
    ('UI/UX Design'),
    ('Data Analysis'); 