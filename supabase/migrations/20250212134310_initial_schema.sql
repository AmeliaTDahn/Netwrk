
-- ==============================
-- MIGRATION #1 (Reordered): 20240321000001_update_profiles_schema.sql
-- We place this first because it creates public.profiles, needed by job_listings
-- ==============================

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


-- ==============================
-- MIGRATION #2 (Reordered): 20240321000000_add_job_listings.sql
-- Placed second because it references public.profiles (business_id)
-- ==============================

-- Create job_listings table
create table if not exists public.job_listings (
    id uuid default gen_random_uuid() primary key,
    business_id uuid references public.profiles(id) on delete cascade not null,
    title text not null,
    description text not null,
    location text not null,
    salary text not null,
    requirements text not null,
    employment_type text not null,
    is_active boolean default true,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Add RLS policies for job_listings
alter table public.job_listings enable row level security;

-- Allow businesses to manage their own listings
create policy "Businesses can manage their own listings"
    on public.job_listings
    for all
    using (auth.uid() = business_id);

-- Allow all authenticated users to view active listings
create policy "Anyone can view active listings"
    on public.job_listings
    for select
    using (is_active = true);

-- Add function to update updated_at timestamp
create or replace function public.handle_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    new.updated_at = timezone('utc'::text, now());
    return new;
end;
$$;

-- Add trigger for updated_at
create trigger handle_job_listings_updated_at
    before update on public.job_listings
    for each row
    execute function public.handle_updated_at();


-- ==============================
-- MIGRATION #3: 20240321000002_update_job_listings_salary.sql
-- Adds numeric salary column to job_listings
-- ==============================

-- Add salary column
alter table public.job_listings
  add column salary numeric;

-- Copy existing salary data to new column
update public.job_listings
set salary = (
  select 
    case 
      when min_salary is not null then min_salary
      else max_salary
    end
);

-- Drop old salary columns
alter table public.job_listings
  drop column if exists min_salary,
  drop column if exists max_salary;


-- ==============================
-- MIGRATION #4: 20240321000003_add_location_coordinates.sql
-- Adds latitude and longitude to profiles
-- ==============================

-- Add latitude and longitude columns to profiles table
alter table public.profiles
  add column latitude double precision,
  add column longitude double precision;

-- Create an index for location-based queries
create index idx_profiles_location
  on public.profiles (latitude, longitude)
  where latitude is not null and longitude is not null;


-- ==============================
-- MIGRATION #5: 20240321000004_add_job_applications.sql
-- Drops existing job_applications table/policies, re-creates them
-- Also sets up notifications, storage policies, triggers
-- ==============================

-- Drop ALL existing storage policies first
drop policy if exists "Anyone can view application files" on storage.objects;
drop policy if exists "Authenticated users can upload application files" on storage.objects;
drop policy if exists "Applicants can access their own application files" on storage.objects;
drop policy if exists "Businesses can access application files for their listings" on storage.objects;
drop policy if exists "Users can upload avatar images" on storage.objects;
drop policy if exists "Avatar images are publicly accessible" on storage.objects;
drop policy if exists "Users can update their own avatar images" on storage.objects;
drop policy if exists "temp_allow_all" on storage.objects;

-- Drop all existing policies first
drop policy if exists "Users can view their own applications" on public.job_applications;
drop policy if exists "Users can create applications" on public.job_applications;
drop policy if exists "Businesses can view applications for their listings" on public.job_applications;
drop policy if exists "Businesses can update application status" on public.job_applications;

-- Drop all notification policies
drop policy if exists "Users can view their own notifications" on public.notifications;
drop policy if exists "System can create notifications" on public.notifications;
drop policy if exists "Users can update their own notifications" on public.notifications;

-- Drop existing table if it exists with CASCADE to handle dependencies
drop table if exists public.job_applications cascade;

-- Create applications storage bucket if it doesn't exist
insert into storage.buckets (id, name, public)
values ('applications', 'applications', false)
on conflict (id) do nothing;

-- Create a temporary permissive policy
create policy "temp_allow_all"
    on storage.objects for all
    using ( bucket_id = 'applications' )
    with check ( bucket_id = 'applications' );

-- Create job_applications table
create table public.job_applications (
    id uuid default gen_random_uuid() primary key,
    job_listing_id uuid references public.job_listings(id) on delete cascade not null,
    applicant_id uuid references public.profiles(id) on delete cascade not null,
    video_url text not null,
    resume_url text,
    cover_note text,
    status text check (status in ('pending', 'interviewing', 'accepted', 'rejected', 'saved')),
    viewed_at timestamp with time zone,
    processed boolean default false,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at timestamp with time zone default timezone('utc'::text, now()) not null,
    unique(job_listing_id, applicant_id)
);

-- Drop temporary policy
drop policy if exists "temp_allow_all" on storage.objects;

-- Create proper storage policies
create policy "Applicants can access their own application files"
    on storage.objects for all
    using (
        bucket_id = 'applications'
        and auth.role() = 'authenticated'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

create policy "Businesses can access application files for their listings"
    on storage.objects for all
    using (
        bucket_id = 'applications'
        and auth.role() = 'authenticated'
        and exists (
            select 1
            from job_applications ja
            join job_listings jl on jl.id = ja.job_listing_id
            where storage.foldername(name) = array[ja.applicant_id::text]
            and jl.business_id = auth.uid()
        )
    );

create policy "Authenticated users can upload application files"
    on storage.objects for insert
    with check (
        bucket_id = 'applications'
        and auth.role() = 'authenticated'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

-- Add trigger for updated_at
create trigger handle_job_applications_updated_at
    before update on public.job_applications
    for each row
    execute function public.handle_updated_at();

-- Enable RLS
alter table public.job_applications enable row level security;

-- Add RLS policies
create policy "Users can view their own applications"
    on public.job_applications
    for select
    using (auth.uid() = applicant_id);

create policy "Users can create applications"
    on public.job_applications
    for insert
    with check (auth.uid() = applicant_id);

create policy "Businesses can view applications for their listings"
    on public.job_applications
    for select
    using (
        exists (
            select 1
            from public.job_listings
            where job_listings.id = job_applications.job_listing_id
            and job_listings.business_id = auth.uid()
        )
    );

create policy "Businesses can update application status"
    on public.job_applications
    for update
    using (
        exists (
            select 1
            from public.job_listings
            where job_listings.id = job_applications.job_listing_id
            and job_listings.business_id = auth.uid()
        )
    );

-- Create notifications table for job applications
create table if not exists public.notifications (
    id uuid default gen_random_uuid() primary key,
    user_id uuid references public.profiles(id) on delete cascade not null,
    title text not null,
    message text not null,
    type text not null,
    is_read boolean default false,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable RLS on notifications
alter table public.notifications enable row level security;

-- Add RLS policies for notifications
create policy "Users can view their own notifications"
    on public.notifications
    for select
    using (auth.uid() = user_id);

create policy "System can create notifications"
    on public.notifications
    for insert
    with check (true);

create policy "Users can update their own notifications"
    on public.notifications
    for update
    using (auth.uid() = user_id);

-- Add function to create application status notification
create or replace function create_application_status_notification()
returns trigger
language plpgsql
security definer
as $$
declare
    job_title text;
    business_name text;
begin
    -- Get job title and business name
    select 
        job_listings.title,
        profiles.business_name
    into
        job_title,
        business_name
    from job_listings
    join profiles on profiles.id = job_listings.business_id
    where job_listings.id = NEW.job_listing_id;

    -- Create notification based on status
    insert into notifications (
        user_id,
        title,
        message,
        type
    )
    values (
        NEW.applicant_id,
        case
            when NEW.status = 'accepted' then 'Application Accepted!'
            when NEW.status = 'rejected' then 'Application Update'
            when NEW.status = 'interviewing' then 'Interview Request'
            else 'Application Update'
        end,
        case
            when NEW.status = 'accepted' then 'Congratulations! Your application for ' || job_title || ' at ' || business_name || ' has been accepted!'
            when NEW.status = 'rejected' then 'Thank you for your interest in ' || job_title || ' at ' || business_name || '. Unfortunately, we have decided to move forward with other candidates.'
            when NEW.status = 'interviewing' then business_name || ' would like to interview you for the ' || job_title || ' position!'
            else 'Your application status for ' || job_title || ' has been updated to: ' || NEW.status
        end,
        NEW.status
    );

    return NEW;
end;
$$;

-- Add trigger for application status changes
create trigger on_application_status_change
    after update of status on job_applications
    for each row
    when (OLD.status is distinct from NEW.status)
    execute function create_application_status_notification();


-- ==============================
-- MIGRATION #6: 20240321000005_add_video_saves.sql
-- Creates video_saves table referencing auth.users
-- ==============================

-- Create video_saves table to track saved videos
CREATE TABLE IF NOT EXISTS video_saves (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  video_id UUID NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  UNIQUE(user_id, video_id)
);

-- Add RLS policies
ALTER TABLE video_saves ENABLE ROW LEVEL SECURITY;

-- Users can view their own saves
CREATE POLICY "Users can view their own saves"
ON video_saves FOR SELECT
USING (auth.uid() = user_id);

-- Users can save videos
CREATE POLICY "Users can save videos"
ON video_saves FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Users can unsave videos
CREATE POLICY "Users can delete their own saves"
ON video_saves FOR DELETE
USING (auth.uid() = user_id);


-- ==============================
-- MIGRATION #7: 20240321000006_add_shared_listings.sql
-- Creates shared_listings referencing job_listings and profiles
-- ==============================

-- Create shared_listings table
CREATE TABLE IF NOT EXISTS shared_listings (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  listing_id UUID REFERENCES job_listings(id) ON DELETE CASCADE NOT NULL,
  shared_by UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  shared_with UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  shared_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  UNIQUE(listing_id, shared_with)
);

-- Enable RLS
ALTER TABLE shared_listings ENABLE ROW LEVEL SECURITY;

-- Users can view listings shared with them
CREATE POLICY "Users can view listings shared with them"
ON shared_listings FOR SELECT
USING (auth.uid() = shared_with);

-- Users can share listings
CREATE POLICY "Users can share listings"
ON shared_listings FOR INSERT
WITH CHECK (
  auth.uid() = shared_by AND
  EXISTS (
    SELECT 1 FROM job_listings
    WHERE id = listing_id
    AND business_id = auth.uid()
  )
);

-- Update job_listings policies to allow shared users to view
CREATE POLICY "Users can view shared listings"
ON job_listings FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM shared_listings
    WHERE listing_id = id
    AND shared_with = auth.uid()
  )
);

-- Update job_applications policies to allow shared users to view and update
CREATE POLICY "Shared users can view applications"
ON job_applications FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM shared_listings
    WHERE listing_id = job_listing_id
    AND shared_with = auth.uid()
  )
);

CREATE POLICY "Shared users can update application status"
ON job_applications FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM shared_listings
    WHERE listing_id = job_listing_id
    AND shared_with = auth.uid()
  )
);


-- ==============================
-- MIGRATION #8: 20240321000007_update_storage_policies.sql
-- Updates storage policies to accommodate shared listings
-- ==============================

-- Update storage policies to allow shared users to access application files
CREATE POLICY "Shared users can access application files"
ON storage.objects FOR ALL
USING (
  bucket_id = 'applications'
  AND auth.role() = 'authenticated'
  AND EXISTS (
    SELECT 1
    FROM job_applications ja
    JOIN shared_listings sl ON sl.listing_id = ja.job_listing_id
    WHERE storage.foldername(name) = array[ja.applicant_id::text]
    AND sl.shared_with = auth.uid()
  )
);

-- Update existing policy for businesses to include shared listings
DROP POLICY IF EXISTS "Businesses can access application files for their listings" ON storage.objects;

CREATE POLICY "Businesses can access application files for their listings"
ON storage.objects FOR ALL
USING (
  bucket_id = 'applications'
  AND auth.role() = 'authenticated'
  AND (
    EXISTS (
      SELECT 1
      FROM job_applications ja
      JOIN job_listings jl ON jl.id = ja.job_listing_id
      WHERE storage.foldername(name) = array[ja.applicant_id::text]
      AND jl.business_id = auth.uid()
    )
    OR
    EXISTS (
      SELECT 1
      FROM job_applications ja
      JOIN shared_listings sl ON sl.listing_id = ja.job_listing_id
      WHERE storage.foldername(name) = array[ja.applicant_id::text]
      AND sl.shared_with = auth.uid()
    )
  )
);

-- Update job_listings policies to prevent shared users from modifying listings
DROP POLICY IF EXISTS "Users can view shared listings" ON job_listings;
DROP POLICY IF EXISTS "Businesses can manage their own listings" ON job_listings;

-- Separate policies for different operations
CREATE POLICY "Businesses can view their own listings"
ON job_listings
FOR SELECT
USING (auth.uid() = business_id);

CREATE POLICY "Businesses can insert their own listings"
ON job_listings
FOR INSERT
WITH CHECK (auth.uid() = business_id);

CREATE POLICY "Businesses can update their own listings"
ON job_listings
FOR UPDATE
USING (auth.uid() = business_id);

CREATE POLICY "Businesses can delete their own listings"
ON job_listings
FOR DELETE
USING (auth.uid() = business_id);

CREATE POLICY "Users can view shared listings"
ON job_listings
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM shared_listings
    WHERE listing_id = id
    AND shared_with = auth.uid()
  )
);


-- ==============================
-- MIGRATION #9: 20240321000008_add_interview_message_template.sql
-- Adds interview_message_template column to job_listings
-- ==============================

-- Add interview_message_template column to job_listings table
ALTER TABLE job_listings
ADD COLUMN interview_message_template TEXT;

-- Set default template for existing listings
UPDATE job_listings
SET interview_message_template = 'Hi! Thanks for applying. We would like to schedule an interview with you. Please let me know your availability for this week.';

-- Drop column from profiles if it exists
ALTER TABLE profiles
DROP COLUMN IF EXISTS interview_message_template;


-- ==============================
-- MIGRATION #10: 20240321000009_add_acceptance_rejection_templates.sql
-- Adds acceptance and rejection templates columns
-- ==============================

-- Add acceptance and rejection message template columns to job_listings table
ALTER TABLE job_listings
ADD COLUMN acceptance_message_template TEXT,
ADD COLUMN rejection_message_template TEXT;

-- Set default templates for existing listings
UPDATE job_listings
SET acceptance_message_template = 'Congratulations! We are pleased to inform you that we would like to offer you the position. We believe your skills and experience will be a great addition to our team.',
    rejection_message_template = 'Thank you for your interest in the position and for taking the time to go through our interview process. After careful consideration, we have decided to move forward with another candidate who more closely matches our current needs.';


-- ==============================
-- MIGRATION #11: 20240321000010_add_chats_messages.sql
-- Creates chats, messages referencing profiles
-- ==============================

-- Create chats table
create table if not exists public.chats (
    id uuid default gen_random_uuid() primary key,
    user1_id uuid references public.profiles(id) on delete cascade not null,
    user2_id uuid references public.profiles(id) on delete cascade not null,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at timestamp with time zone default timezone('utc'::text, now()) not null,
    unique(user1_id, user2_id)
);

-- Create messages table
create table if not exists public.messages (
    id uuid default gen_random_uuid() primary key,
    chat_id uuid references public.chats(id) on delete cascade not null,
    sender_id uuid references public.profiles(id) on delete cascade not null,
    content text not null,
    read_at timestamp with time zone,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Add trigger for chats updated_at
create trigger handle_chats_updated_at
    before update on public.chats
    for each row
    execute function public.handle_updated_at();

-- Add trigger for messages updated_at
create trigger handle_messages_updated_at
    before update on public.messages
    for each row
    execute function public.handle_updated_at();

-- Enable RLS
alter table public.chats enable row level security;
alter table public.messages enable row level security;

-- Add RLS policies for chats
create policy "Users can view their own chats"
    on public.chats
    for select
    using (auth.uid() in (user1_id, user2_id));

create policy "Users can create chats with other users"
    on public.chats
    for insert
    with check (auth.uid() in (user1_id, user2_id));

-- Add RLS policies for messages
create policy "Users can view messages in their chats"
    on public.messages
    for select
    using (
        exists (
            select 1
            from public.chats
            where chats.id = messages.chat_id
            and auth.uid() in (user1_id, user2_id)
        )
    );

create policy "Users can send messages in their chats"
    on public.messages
    for insert
    with check (
        auth.uid() = sender_id
        and exists (
            select 1
            from public.chats
            where chats.id = messages.chat_id
            and auth.uid() in (user1_id, user2_id)
        )
    );

create policy "Users can update read status of messages sent to them"
    on public.messages
    for update
    using (
        exists (
            select 1
            from public.chats
            where chats.id = messages.chat_id
            and auth.uid() in (user1_id, user2_id)
            and auth.uid() != sender_id
        )
    );


-- ==============================
-- MIGRATION #12: 20240321000011_remove_rejection_template.sql
-- Removes the rejection_message_template column
-- ==============================

-- Remove rejection message template column from job_listings table
ALTER TABLE job_listings
DROP COLUMN IF EXISTS rejection_message_template;


-- ==============================
-- MIGRATION #13: 20240321000013_add_skills_tables.sql
-- Drops old skills/profile_skills and re-creates them with vector(384)
-- ==============================

-- Enable the pgvector extension
create extension if not exists vector;

-- Drop existing tables and functions if they exist
drop function if exists get_skill_suggestions(uuid,integer,double precision);
drop function if exists get_similar_skills(vector(384),float,int);
drop table if exists public.profile_skills;
drop table if exists public.skills;

-- Create a skills table to store all available skills
create table if not exists public.skills (
  id bigint primary key generated always as identity,
  name text not null unique,
  category text not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null,
  embedding vector(384)
);

-- Create a junction table for user skills
create table if not exists public.profile_skills (
  profile_id uuid references public.profiles(id) on delete cascade,
  skill_id bigint references public.skills(id) on delete cascade,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  primary key (profile_id, skill_id)
);

-- Enable RLS
alter table public.skills enable row level security;
alter table public.profile_skills enable row level security;

-- Skills policies
create policy "Skills are viewable by everyone"
  on skills for select
  using (true);

create policy "Authenticated users can create skills"
  on skills for insert
  with check (auth.role() = 'authenticated');

create policy "Skills can be updated by authenticated users"
  on skills for update
  using (auth.role() = 'authenticated');

-- Profile skills policies
create policy "Profile skills are viewable by everyone"
  on profile_skills for select
  using (true);

create policy "Users can manage their own profile skills"
  on profile_skills for all
  using (auth.uid() = profile_id);

-- Create indexes
create index if not exists skills_name_idx on skills(name);
create index if not exists skills_category_idx on skills(category);
create index if not exists profile_skills_profile_id_idx on profile_skills(profile_id);
create index if not exists profile_skills_skill_id_idx on profile_skills(skill_id);

-- Add update trigger for skills
create trigger update_skills_updated_at
  before update on skills
  for each row
  execute function update_updated_at_column();

-- Add initial diverse set of skills with placeholder embeddings
insert into public.skills (name, category, embedding) values
  -- Technical
  ('Python', 'Technical', array_fill(0::float, array[384])),
  ('Data Analysis', 'Technical', array_fill(0::float, array[384])),
  -- Healthcare
  ('Patient Care', 'Healthcare', array_fill(0::float, array[384])),
  ('Medical Records', 'Healthcare', array_fill(0::float, array[384])),
  -- Service Industry
  ('Customer Service', 'Service', array_fill(0::float, array[384])),
  ('Food Service', 'Service', array_fill(0::float, array[384])),
  -- Business/Management
  ('Project Management', 'Business', array_fill(0::float, array[384])),
  ('Team Leadership', 'Business', array_fill(0::float, array[384])),
  -- Creative
  ('Graphic Design', 'Creative', array_fill(0::float, array[384])),
  ('Content Writing', 'Creative', array_fill(0::float, array[384])),
  -- Trade Skills
  ('Electrical Work', 'Trade', array_fill(0::float, array[384])),
  ('Carpentry', 'Trade', array_fill(0::float, array[384]))
on conflict (name) do nothing;

-- Create function to find similar skills
create or replace function get_similar_skills(
  query_embedding vector(384),
  match_threshold float,
  match_count int
)
returns table (
  id bigint,
  name text,
  category text,
  similarity float
)
language plpgsql
as $$
begin
  return query
  select
    skills.id,
    skills.name,
    skills.category,
    1 - (skills.embedding <=> query_embedding) as similarity
  from skills
  where 1 - (skills.embedding <=> query_embedding) > match_threshold
  order by similarity desc
  limit match_count;
end;
$$;

-- Create function to get skill suggestions
create or replace function get_skill_suggestions(
  user_id uuid,
  match_count int default 5,
  similarity_threshold float default 0.7
)
returns table (
  skill_name text,
  category text,
  similarity float,
  based_on text
)
language plpgsql
as $$
begin
  -- Debug logging
  raise notice 'Getting suggestions for user: %', user_id;
  
  return query
  with user_skills as (
    -- Get all the user's current skills
    select s.id, s.name, s.category, s.embedding
    from profile_skills ps
    join skills s on s.id = ps.skill_id
    where ps.profile_id = user_id
  )
  , debug as (
    select count(*) as skill_count from user_skills
  )
  , similar_skills as (
    -- Find similar skills for each of user's skills
    select 
      s.name as suggested_skill,
      s.category as skill_category,
      us.name as based_on_skill,
      1 - (s.embedding <=> us.embedding) as similarity_score
    from user_skills us
    cross join lateral (
      select s.name, s.category, s.embedding
      from skills s
      where s.id != us.id
      and s.id not in (select id from user_skills)
      and 1 - (s.embedding <=> us.embedding) > similarity_threshold
      order by 1 - (s.embedding <=> us.embedding) desc
      limit match_count
    ) s
  )
  select 
    suggested_skill,
    skill_category,
    similarity_score,
    based_on_skill
  from similar_skills
  order by similarity_score desc
  limit match_count;
  
  -- Debug logging at the end
  raise notice 'Finished getting suggestions';
end;
$$;

-- Add a test function to directly test similarity
create or replace function test_similarity(skill_name text)
returns table (
  similar_skill text,
  category text,
  similarity float
)
language plpgsql
as $$
declare
  target_embedding vector(384);
begin
  -- Get the embedding for the target skill
  select embedding into target_embedding
  from skills
  where name = skill_name;
  
  -- Find similar skills
  return query
  select 
    s.name,
    s.category,
    1 - (s.embedding <=> target_embedding) as similarity
  from skills s
  where s.name != skill_name
  order by similarity desc
  limit 5;
end;
$$;

-- Add helper function to update embeddings
create or replace function update_skill_embedding(
  skill_id bigint,
  embedding_vector text
)
returns void
language plpgsql
as $$
begin
  update skills 
  set embedding = embedding_vector::vector
  where id = skill_id;
end;
$$;


-- ==============================
-- MIGRATION #14: 20240321000014_restore_avatar_policies.sql
-- Restores avatar policies that were accidentally dropped
-- ==============================

-- Restore avatar storage policies that were accidentally dropped

-- Avatar images are publicly accessible
create policy "Avatar images are publicly accessible"
  on storage.objects for select
  using (bucket_id = 'avatars');

-- Users can upload avatar images
create policy "Users can upload avatar images"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars' 
    and auth.role() = 'authenticated'
  );

-- Users can update their own avatar images
create policy "Users can update their own avatar images"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and auth.role() = 'authenticated'
    and (storage.foldername(name))[1] = auth.uid()::text
  );


-- ==============================
-- SUPABASE BACKUP (FINAL STEP): supabase_backup_20250212.sql
-- Kept verbatim. This will not fail due to IF NOT EXISTS usage, and ensures final schema
-- ==============================

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE EXTENSION IF NOT EXISTS "pgsodium" WITH SCHEMA "pgsodium";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "vector" WITH SCHEMA "public";






CREATE OR REPLACE FUNCTION "public"."accept_connection"("p_requester_id" "uuid", "p_receiver_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Update connection status to accepted
    UPDATE connections
    SET status = 'accepted'
    WHERE (requester_id = p_requester_id AND receiver_id = p_receiver_id)
       OR (requester_id = p_receiver_id AND receiver_id = p_requester_id);

    -- Create chat for the connected users
    INSERT INTO chats (user1_id, user2_id)
    VALUES (
        LEAST(p_requester_id, p_receiver_id),
        GREATEST(p_requester_id, p_receiver_id)
    )
    ON CONFLICT ON CONSTRAINT unique_chat_participants DO NOTHING;
END;
$$;


ALTER FUNCTION "public"."accept_connection"("p_requester_id" "uuid", "p_receiver_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."accept_connection_and_create_chat"("connection_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_requester_id UUID;
    v_receiver_id UUID;
    v_user1_id UUID;
    v_user2_id UUID;
    v_chat_id UUID;
BEGIN
    -- Get the connection details
    SELECT requester_id, receiver_id INTO v_requester_id, v_receiver_id
    FROM connections
    WHERE id = connection_id AND status = 'pending';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Connection not found or not pending';
    END IF;

    -- Determine the order of user IDs (smaller ID first)
    IF v_requester_id < v_receiver_id THEN
        v_user1_id := v_requester_id;
        v_user2_id := v_receiver_id;
    ELSE
        v_user1_id := v_receiver_id;
        v_user2_id := v_requester_id;
    END IF;

    -- Update connection status to accepted
    UPDATE connections
    SET status = 'accepted'
    WHERE id = connection_id;

    -- Create a new chat if one doesn't exist
    INSERT INTO chats (user1_id, user2_id)
    VALUES (v_user1_id, v_user2_id)
    ON CONFLICT ON CONSTRAINT unique_chat_participants 
    DO UPDATE SET updated_at = NOW()
    RETURNING id INTO v_chat_id;

    RETURN v_chat_id;
END;
$$;


ALTER FUNCTION "public"."accept_connection_and_create_chat"("connection_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_application_status_notification"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
    job_title text;
    business_name text;
begin
    -- Get job title and business name
    select 
        job_listings.title,
        profiles.business_name
    into
        job_title,
        business_name
    from job_listings
    join profiles on profiles.id = job_listings.business_id
    where job_listings.id = NEW.job_listing_id;

    -- Create notification based on status
    insert into notifications (
        user_id,
        title,
        message,
        type
    )
    values (
        NEW.applicant_id,
        case
            when NEW.status = 'accepted' then 'Application Accepted!'
            when NEW.status = 'rejected' then 'Application Update'
            when NEW.status = 'interviewing' then 'Interview Request'
            else 'Application Update'
        end,
        case
            when NEW.status = 'accepted' then 'Congratulations! Your application for ' || job_title || ' at ' || business_name || ' has been accepted!'
            when NEW.status = 'rejected' then 'Thank you for your interest in ' || job_title || ' at ' || business_name || '. Unfortunately, we have decided to move forward with other candidates.'
            when NEW.status = 'interviewing' then business_name || ' would like to interview you for the ' || job_title || ' position!'
            else 'Your application status for ' || job_title || ' has been updated to: ' || NEW.status
        end,
        NEW.status
    );

    return NEW;
end;
$$;


ALTER FUNCTION "public"."create_application_status_notification"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_random_username"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
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
$$;


ALTER FUNCTION "public"."generate_random_username"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_similar_skills"("query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) RETURNS TABLE("id" bigint, "name" "text", "category" "text", "similarity" double precision)
    LANGUAGE "plpgsql"
    AS $$
begin
  return query
  select
    skills.id,
    skills.name,
    skills.category,
    1 - (skills.embedding <=> query_embedding) as similarity
  from skills
  where 1 - (skills.embedding <=> query_embedding) > match_threshold
  order by similarity desc
  limit match_count;
end;
$$;


ALTER FUNCTION "public"."get_similar_skills"("query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_skill_suggestions"("user_id" "uuid", "match_count" integer DEFAULT 5) RETURNS TABLE("skill_name" "text", "similarity" double precision)
    LANGUAGE "plpgsql"
    AS $$
declare
  avg_embedding vector(384);
begin
  -- Get average embedding of user's current skills
  select avg(s.embedding) into avg_embedding
  from profile_skills ps
  join skills s on s.id = ps.skill_id
  where ps.profile_id = user_id;

  -- Return similar skills that user doesn't already have
  return query
  select 
    s.name,
    1 - (s.embedding <=> avg_embedding) as similarity
  from skills s
  where s.id not in (
    select skill_id 
    from profile_skills 
    where profile_id = user_id
  )
  and avg_embedding is not null
  order by s.embedding <=> avg_embedding
  limit match_count;
end;
$$;


ALTER FUNCTION "public"."get_skill_suggestions"("user_id" "uuid", "match_count" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_skill_suggestions"("user_id" "uuid", "match_count" integer DEFAULT 5, "similarity_threshold" double precision DEFAULT 0.7) RETURNS TABLE("skill_name" "text", "category" "text", "similarity" double precision, "based_on" "text")
    LANGUAGE "plpgsql"
    AS $$
begin
  -- Debug logging
  raise notice 'Getting suggestions for user: %', user_id;
  
  return query
  with user_skills as (
    -- Get all the user's current skills
    select s.id, s.name, s.category, s.embedding
    from profile_skills ps
    join skills s on s.id = ps.skill_id
    where ps.profile_id = user_id
  )
  , debug as (
    select count(*) as skill_count from user_skills
  )
  , similar_skills as (
    -- Find similar skills for each of user's skills
    select 
      s.name as suggested_skill,
      s.category as skill_category,
      us.name as based_on_skill,
      1 - (s.embedding <=> us.embedding) as similarity_score
    from user_skills us
    cross join lateral (
      select s.name, s.category, s.embedding
      from skills s
      where s.id != us.id
      and s.id not in (select id from user_skills)
      and 1 - (s.embedding <=> us.embedding) > similarity_threshold
      order by 1 - (s.embedding <=> us.embedding) desc
      limit match_count
    ) s
  )
  select 
    suggested_skill,
    skill_category,
    similarity_score,
    based_on_skill
  from similar_skills
  order by similarity_score desc
  limit match_count;
  
  -- Debug logging at the end
  raise notice 'Finished getting suggestions';
end;
$$;


ALTER FUNCTION "public"."get_skill_suggestions"("user_id" "uuid", "match_count" integer, "similarity_threshold" double precision) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_videos"("category_filter" "text") RETURNS SETOF "public"."videos_with_profiles"
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
    select *
    from videos_with_profiles
    where category = category_filter
    order by created_at desc;
$$;


ALTER FUNCTION "public"."get_videos"("category_filter" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_connection_accept"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Create a chat when connection is accepted
    IF NEW.status = 'accepted' AND OLD.status = 'pending' THEN
        INSERT INTO chats (user1_id, user2_id)
        VALUES (
            LEAST(NEW.requester_id, NEW.receiver_id),
            GREATEST(NEW.requester_id, NEW.receiver_id)
        );
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_connection_accept"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
    new.updated_at = timezone('utc'::text, now());
    return new;
end;
$$;


ALTER FUNCTION "public"."handle_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_shared_application"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
    application_data record;
    business_name text;
begin
    -- Get application and business details
    select 
        ja.*,
        p.name as applicant_name,
        bp.business_name,
        jl.title as job_title
    into application_data
    from job_applications ja
    join profiles p on p.id = ja.applicant_id
    join job_listings jl on jl.id = ja.job_listing_id
    join profiles bp on bp.id = jl.business_id
    where ja.id = NEW.application_id;

    -- Create notification for shared_with user
    insert into notifications (
        user_id,
        title,
        message,
        type
    )
    values (
        NEW.shared_with,
        'Application Shared With You',
        business_name || ' shared ' || application_data.applicant_name || '''s application for ' || application_data.job_title || ' with you.',
        'shared_application'
    );

    return NEW;
end;
$$;


ALTER FUNCTION "public"."notify_shared_application"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."test_similarity"("skill_name" "text") RETURNS TABLE("similar_skill" "text", "category" "text", "similarity" double precision)
    LANGUAGE "plpgsql"
    AS $$
declare
  target_embedding vector(384);
begin
  -- Get the embedding for the target skill
  select embedding into target_embedding
  from skills
  where name = skill_name;
  
  -- Find similar skills
  return query
  select 
    s.name,
    s.category,
    1 - (s.embedding <=> target_embedding) as similarity
  from skills s
  where s.name != skill_name
  order by similarity desc
  limit 5;
end;
$$;


ALTER FUNCTION "public"."test_similarity"("skill_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_skill_embedding"("skill_id" bigint, "embedding_vector" "text") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
begin
  update skills 
  set embedding = embedding_vector::vector
  where id = skill_id;
end;
$$;


ALTER FUNCTION "public"."update_skill_embedding"("skill_id" bigint, "embedding_vector" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "username" "text",
    "display_name" "text",
    "bio" "text",
    "contact_email" "text",
    "phone" "text",
    "photo_url" "text",
    "resume_url" "text",
    "skills" "text" DEFAULT ''::"text",
    "role" "text" DEFAULT 'employee'::"text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "education" "text",
    "experience" "text",
    "location" "text",
    "website" "text",
    "is_hiring" boolean DEFAULT false,
    "hiring_position" "text",
    "position_description" "text",
    "onboarding_completed" boolean DEFAULT false,
    "account_type" "text",
    "business_name" "text",
    "industry" "text",
    "experience_years" integer,
    "name" "text",
    "email" "text",
    "latitude" double precision,
    "longitude" double precision,
    CONSTRAINT "profiles_account_type_check" CHECK (("account_type" = ANY (ARRAY['business'::"text", 'employee'::"text"])))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."videos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "url" "text" NOT NULL,
    "thumbnail_url" "text" NOT NULL,
    "category" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "videos_category_check" CHECK (("category" = ANY (ARRAY['business'::"text", 'employee'::"text"])))
);


ALTER TABLE "public"."videos" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."videos_with_profiles" AS
 SELECT "v"."id",
    "v"."user_id",
    "v"."title",
    "v"."description",
    "v"."url",
    "v"."thumbnail_url",
    "v"."category",
    "v"."created_at",
    "v"."updated_at",
    "p"."username",
    "p"."display_name",
    "p"."photo_url",
    "p"."role"
   FROM ("public"."videos" "v"
     JOIN "public"."profiles" "p" ON (("v"."user_id" = "p"."id")));


ALTER TABLE "public"."videos_with_profiles" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_videos"("category_filter" "text") RETURNS SETOF "public"."videos_with_profiles"
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
    select *
    from videos_with_profiles
    where category = category_filter
    order by created_at desc;
$$;


ALTER FUNCTION "public"."get_videos"("category_filter" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_connection_accept"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Create a chat when connection is accepted
    IF NEW.status = 'accepted' AND OLD.status = 'pending' THEN
        INSERT INTO chats (user1_id, user2_id)
        VALUES (
            LEAST(NEW.requester_id, NEW.receiver_id),
            GREATEST(NEW.requester_id, NEW.receiver_id)
        );
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_connection_accept"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
    new.updated_at = timezone('utc'::text, now());
    return new;
end;
$$;


ALTER FUNCTION "public"."handle_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_shared_application"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
    application_data record;
    business_name text;
begin
    -- Get application and business details
    select 
        ja.*,
        p.name as applicant_name,
        bp.business_name,
        jl.title as job_title
    into application_data
    from job_applications ja
    join profiles p on p.id = ja.applicant_id
    join job_listings jl on jl.id = ja.job_listing_id
    join profiles bp on bp.id = jl.business_id
    where ja.id = NEW.application_id;

    -- Create notification for shared_with user
    insert into notifications (
        user_id,
        title,
        message,
        type
    )
    values (
        NEW.shared_with,
        'Application Shared With You',
        business_name || ' shared ' || application_data.applicant_name || '''s application for ' || application_data.job_title || ' with you.',
        'shared_application'
    );

    return NEW;
end;
$$;


ALTER FUNCTION "public"."notify_shared_application"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."test_similarity"("skill_name" "text") RETURNS TABLE("similar_skill" "text", "category" "text", "similarity" double precision)
    LANGUAGE "plpgsql"
    AS $$
declare
  target_embedding vector(384);
begin
  -- Get the embedding for the target skill
  select embedding into target_embedding
  from skills
  where name = skill_name;
  
  -- Find similar skills
  return query
  select 
    s.name,
    s.category,
    1 - (s.embedding <=> target_embedding) as similarity
  from skills s
  where s.name != skill_name
  order by similarity desc
  limit 5;
end;
$$;


ALTER FUNCTION "public"."test_similarity"("skill_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_skill_embedding"("skill_id" bigint, "embedding_vector" "text") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
begin
  update skills 
  set embedding = embedding_vector::vector
  where id = skill_id;
end;
$$;


ALTER FUNCTION "public"."update_skill_embedding"("skill_id" bigint, "embedding_vector" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ai_recommendations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "job_listing_id" "uuid" NOT NULL,
    "recommendations" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."ai_recommendations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chats" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user1_id" "uuid" NOT NULL,
    "user2_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "no_self_chat" CHECK (("user1_id" <> "user2_id"))
);


ALTER TABLE "public"."chats" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."comments" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "content" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "video_id" "uuid" NOT NULL,
    "profile_id" "uuid" NOT NULL
);


ALTER TABLE "public"."comments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."connections" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "requester_id" "uuid" NOT NULL,
    "receiver_id" "uuid" NOT NULL,
    "status" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "connections_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text"]))),
    CONSTRAINT "no_self_connections" CHECK (("requester_id" <> "receiver_id"))
);


ALTER TABLE "public"."connections" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."job_applications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "job_listing_id" "uuid" NOT NULL,
    "applicant_id" "uuid" NOT NULL,
    "video_url" "text" NOT NULL,
    "resume_url" "text",
    "cover_note" "text",
    "status" "text",
    "viewed_at" timestamp with time zone,
    "processed" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "job_applications_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'interviewing'::"text", 'accepted'::"text", 'rejected'::"text", 'saved'::"text"])))
);


ALTER TABLE "public"."job_applications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."job_embeddings" (
    "id" "uuid" NOT NULL,
    "embedding" "public"."vector"(1536),
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."job_embeddings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."job_listings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "business_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text" NOT NULL,
    "location" "text" NOT NULL,
    "requirements" "text" NOT NULL,
    "employment_type" "text" NOT NULL,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "is_remote" boolean DEFAULT false,
    "salary" numeric,
    "interview_message_template" "text",
    "acceptance_message_template" "text"
);


ALTER TABLE "public"."job_listings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."messages" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "chat_id" "uuid" NOT NULL,
    "sender_id" "uuid" NOT NULL,
    "content" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "read_at" timestamp with time zone
);

ALTER TABLE ONLY "public"."messages" REPLICA IDENTITY FULL;


ALTER TABLE "public"."messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "message" "text" NOT NULL,
    "type" "text" NOT NULL,
    "is_read" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."notifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profile_embeddings" (
    "id" "uuid" NOT NULL,
    "embedding" "public"."vector"(1536),
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."profile_embeddings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profile_skills" (
    "profile_id" "uuid" NOT NULL,
    "skill_id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."profile_skills" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."saves" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "video_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."saves" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shared_applications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "application_id" "uuid" NOT NULL,
    "shared_by" "uuid" NOT NULL,
    "shared_with" "uuid" NOT NULL,
    "shared_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."shared_applications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shared_listings" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "listing_id" "uuid" NOT NULL,
    "shared_by" "uuid" NOT NULL,
    "shared_with" "uuid" NOT NULL,
    "shared_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."shared_listings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."skills" (
    "id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "category" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "embedding" "public"."vector"(384)
);


ALTER TABLE "public"."skills" OWNER TO "postgres";


ALTER TABLE "public"."skills" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."skills_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."video_saves" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "video_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."video_saves" OWNER TO "postgres";


ALTER TABLE ONLY "public"."ai_recommendations"
    ADD CONSTRAINT "ai_recommendations_job_listing_id_key" UNIQUE ("job_listing_id");



ALTER TABLE ONLY "public"."ai_recommendations"
    ADD CONSTRAINT "ai_recommendations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."comments"
    ADD CONSTRAINT "comments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."connections"
    ADD CONSTRAINT "connections_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."job_applications"
    ADD CONSTRAINT "job_applications_job_listing_id_applicant_id_key" UNIQUE ("job_listing_id", "applicant_id");



ALTER TABLE ONLY "public"."job_applications"
    ADD CONSTRAINT "job_applications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."job_embeddings"
    ADD CONSTRAINT "job_embeddings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."job_listings"
    ADD CONSTRAINT "job_listings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profile_embeddings"
    ADD CONSTRAINT "profile_embeddings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profile_skills"
    ADD CONSTRAINT "profile_skills_pkey" PRIMARY KEY ("profile_id", "skill_id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_username_key" UNIQUE ("username");



ALTER TABLE ONLY "public"."saves"
    ADD CONSTRAINT "saves_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."saves"
    ADD CONSTRAINT "saves_user_id_video_id_key" UNIQUE ("user_id", "video_id");



ALTER TABLE ONLY "public"."shared_applications"
    ADD CONSTRAINT "shared_applications_application_id_shared_by_shared_with_key" UNIQUE ("application_id", "shared_by", "shared_with");



ALTER TABLE ONLY "public"."shared_applications"
    ADD CONSTRAINT "shared_applications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."shared_listings"
    ADD CONSTRAINT "shared_listings_listing_id_shared_with_key" UNIQUE ("listing_id", "shared_with");



ALTER TABLE ONLY "public"."shared_listings"
    ADD CONSTRAINT "shared_listings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."skills"
    ADD CONSTRAINT "skills_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."skills"
    ADD CONSTRAINT "skills_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "unique_chat_participants" UNIQUE ("user1_id", "user2_id");



ALTER TABLE ONLY "public"."connections"
    ADD CONSTRAINT "unique_connection" UNIQUE ("requester_id", "receiver_id");



ALTER TABLE ONLY "public"."video_saves"
    ADD CONSTRAINT "video_saves_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."video_saves"
    ADD CONSTRAINT "video_saves_user_id_video_id_key" UNIQUE ("user_id", "video_id");



ALTER TABLE ONLY "public"."videos"
    ADD CONSTRAINT "videos_pkey" PRIMARY KEY ("id");



CREATE INDEX "comments_profile_id_idx" ON "public"."comments" USING "btree" ("profile_id");



CREATE INDEX "comments_video_id_idx" ON "public"."comments" USING "btree" ("video_id");



CREATE INDEX "idx_connections_status" ON "public"."connections" USING "btree" ("status");



CREATE INDEX "idx_connections_users" ON "public"."connections" USING "btree" ("requester_id", "receiver_id");



CREATE INDEX "idx_profiles_location" ON "public"."profiles" USING "btree" ("latitude", "longitude") WHERE (("latitude" IS NOT NULL) AND ("longitude" IS NOT NULL));



CREATE INDEX "messages_chat_id_idx" ON "public"."messages" USING "btree" ("chat_id");



CREATE INDEX "messages_created_at_idx" ON "public"."messages" USING "btree" ("created_at");



CREATE INDEX "messages_sender_id_idx" ON "public"."messages" USING "btree" ("sender_id");



CREATE INDEX "profile_skills_profile_id_idx" ON "public"."profile_skills" USING "btree" ("profile_id");



CREATE INDEX "profile_skills_skill_id_idx" ON "public"."profile_skills" USING "btree" ("skill_id");



CREATE INDEX "skills_category_idx" ON "public"."skills" USING "btree" ("category");



CREATE INDEX "skills_name_idx" ON "public"."skills" USING "btree" ("name");



CREATE INDEX "videos_category_created_at_idx" ON "public"."videos" USING "btree" ("category", "created_at" DESC);



CREATE INDEX "videos_user_id_idx" ON "public"."videos" USING "btree" ("user_id");



CREATE OR REPLACE TRIGGER "ensure_username_trigger" BEFORE INSERT ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."generate_random_username"();



CREATE OR REPLACE TRIGGER "handle_job_applications_updated_at" BEFORE UPDATE ON "public"."job_applications" FOR EACH ROW EXECUTE FUNCTION "public"."handle_updated_at"();



CREATE OR REPLACE TRIGGER "handle_job_listings_updated_at" BEFORE UPDATE ON "public"."job_listings" FOR EACH ROW EXECUTE FUNCTION "public"."handle_updated_at"();



CREATE OR REPLACE TRIGGER "handle_updated_at" BEFORE UPDATE ON "public"."ai_recommendations" FOR EACH ROW EXECUTE FUNCTION "public"."handle_updated_at"();



CREATE OR REPLACE TRIGGER "on_application_shared" AFTER INSERT ON "public"."shared_applications" FOR EACH ROW EXECUTE FUNCTION "public"."notify_shared_application"();



CREATE OR REPLACE TRIGGER "on_application_status_change" AFTER UPDATE OF "status" ON "public"."job_applications" FOR EACH ROW WHEN (("old"."status" IS DISTINCT FROM "new"."status")) EXECUTE FUNCTION "public"."create_application_status_notification"();



CREATE OR REPLACE TRIGGER "on_connection_accept" AFTER UPDATE ON "public"."connections" FOR EACH ROW EXECUTE FUNCTION "public"."handle_connection_accept"();



CREATE OR REPLACE TRIGGER "update_connections_updated_at" BEFORE UPDATE ON "public"."connections" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_skills_updated_at" BEFORE UPDATE ON "public"."skills" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



ALTER TABLE ONLY "public"."ai_recommendations"
    ADD CONSTRAINT "ai_recommendations_job_listing_id_fkey" FOREIGN KEY ("job_listing_id") REFERENCES "public"."job_listings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_user1_id_fkey" FOREIGN KEY ("user1_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_user2_id_fkey" FOREIGN KEY ("user2_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."comments"
    ADD CONSTRAINT "comments_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."comments"
    ADD CONSTRAINT "comments_video_id_fkey" FOREIGN KEY ("video_id") REFERENCES "public"."videos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."connections"
    ADD CONSTRAINT "connections_receiver_id_fkey" FOREIGN KEY ("receiver_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."connections"
    ADD CONSTRAINT "connections_requester_id_fkey" FOREIGN KEY ("requester_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."videos"
    ADD CONSTRAINT "fk_user_id" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."job_applications"
    ADD CONSTRAINT "job_applications_applicant_id_fkey" FOREIGN KEY ("applicant_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."job_applications"
    ADD CONSTRAINT "job_applications_job_listing_id_fkey" FOREIGN KEY ("job_listing_id") REFERENCES "public"."job_listings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."job_embeddings"
    ADD CONSTRAINT "job_embeddings_id_fkey" FOREIGN KEY ("id") REFERENCES "public"."job_listings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."job_listings"
    ADD CONSTRAINT "job_listings_business_id_fkey" FOREIGN KEY ("business_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_chat_id_fkey" FOREIGN KEY ("chat_id") REFERENCES "public"."chats"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profile_embeddings"
    ADD CONSTRAINT "profile_embeddings_id_fkey" FOREIGN KEY ("id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profile_skills"
    ADD CONSTRAINT "profile_skills_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profile_skills"
    ADD CONSTRAINT "profile_skills_skill_id_fkey" FOREIGN KEY ("skill_id") REFERENCES "public"."skills"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."saves"
    ADD CONSTRAINT "saves_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."saves"
    ADD CONSTRAINT "saves_video_id_fkey" FOREIGN KEY ("video_id") REFERENCES "public"."videos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shared_applications"
    ADD CONSTRAINT "shared_applications_application_id_fkey" FOREIGN KEY ("application_id") REFERENCES "public"."job_applications"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shared_applications"
    ADD CONSTRAINT "shared_applications_shared_by_fkey" FOREIGN KEY ("shared_by") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shared_applications"
    ADD CONSTRAINT "shared_applications_shared_with_fkey" FOREIGN KEY ("shared_with") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shared_listings"
    ADD CONSTRAINT "shared_listings_listing_id_fkey" FOREIGN KEY ("listing_id") REFERENCES "public"."job_listings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shared_listings"
    ADD CONSTRAINT "shared_listings_shared_by_fkey" FOREIGN KEY ("shared_by") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shared_listings"
    ADD CONSTRAINT "shared_listings_shared_with_fkey" FOREIGN KEY ("shared_with") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."video_saves"
    ADD CONSTRAINT "video_saves_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."videos"
    ADD CONSTRAINT "videos_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."videos"
    ADD CONSTRAINT "videos_user_id_fkey1" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



CREATE POLICY "Anyone can create a profile during signup" ON "public"."profiles" FOR INSERT WITH CHECK (true);



CREATE POLICY "Anyone can view active listings" ON "public"."job_listings" FOR SELECT USING (("is_active" = true));



CREATE POLICY "Anyone can view job embeddings" ON "public"."job_embeddings" FOR SELECT USING (true);



CREATE POLICY "Anyone can view profile embeddings" ON "public"."profile_embeddings" FOR SELECT USING (true);



CREATE POLICY "Anyone can view recommendations" ON "public"."ai_recommendations" FOR SELECT USING (true);



CREATE POLICY "Authenticated users can create skills" ON "public"."skills" FOR INSERT WITH CHECK (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "Business users can update their job embeddings" ON "public"."job_embeddings" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."job_listings"
  WHERE (("job_listings"."id" = "job_embeddings"."id") AND ("job_listings"."business_id" = "auth"."uid"())))));



CREATE POLICY "Businesses can delete their own listings" ON "public"."job_listings" FOR DELETE USING (("auth"."uid"() = "business_id"));



CREATE POLICY "Businesses can insert their own listings" ON "public"."job_listings" FOR INSERT WITH CHECK (("auth"."uid"() = "business_id"));



CREATE POLICY "Businesses can update application status" ON "public"."job_applications" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."job_listings"
  WHERE (("job_listings"."id" = "job_applications"."job_listing_id") AND ("job_listings"."business_id" = "auth"."uid"())))));



CREATE POLICY "Businesses can update their own listings" ON "public"."job_listings" FOR UPDATE USING (("auth"."uid"() = "business_id"));



CREATE POLICY "Businesses can view applications for their listings" ON "public"."job_applications" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."job_listings"
  WHERE (("job_listings"."id" = "job_applications"."job_listing_id") AND ("job_listings"."business_id" = "auth"."uid"())))));



CREATE POLICY "Businesses can view their own listings" ON "public"."job_listings" FOR SELECT USING (("auth"."uid"() = "business_id"));



CREATE POLICY "Comments are viewable by everyone" ON "public"."comments" FOR SELECT USING (true);



CREATE POLICY "Profile skills are viewable by everyone" ON "public"."profile_skills" FOR SELECT USING (true);



CREATE POLICY "Public profiles are viewable by everyone" ON "public"."profiles" FOR SELECT USING (true);



CREATE POLICY "Shared users can update application status" ON "public"."job_applications" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."shared_listings"
  WHERE (("shared_listings"."listing_id" = "job_applications"."job_listing_id") AND ("shared_listings"."shared_with" = "auth"."uid"())))));



CREATE POLICY "Shared users can view applications" ON "public"."job_applications" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."shared_listings"
  WHERE (("shared_listings"."listing_id" = "job_applications"."job_listing_id") AND ("shared_listings"."shared_with" = "auth"."uid"())))));



CREATE POLICY "Skills are viewable by everyone" ON "public"."skills" FOR SELECT USING (true);



CREATE POLICY "Skills can be updated by authenticated users" ON "public"."skills" FOR UPDATE USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "System can create notifications" ON "public"."notifications" FOR INSERT WITH CHECK (true);



CREATE POLICY "Users can create applications" ON "public"."job_applications" FOR INSERT WITH CHECK (("auth"."uid"() = "applicant_id"));



CREATE POLICY "Users can create connections as requester" ON "public"."connections" FOR INSERT WITH CHECK (("auth"."uid"() = "requester_id"));



CREATE POLICY "Users can create recommendations" ON "public"."ai_recommendations" FOR INSERT WITH CHECK (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "Users can create saves" ON "public"."saves" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create their own comments" ON "public"."comments" FOR INSERT WITH CHECK (("profile_id" IN ( SELECT "profiles"."id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "Users can delete chats they're part of" ON "public"."chats" FOR DELETE USING ((("auth"."uid"() = "user1_id") OR ("auth"."uid"() = "user2_id")));



CREATE POLICY "Users can delete own videos" ON "public"."videos" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own comments" ON "public"."comments" FOR DELETE USING (("profile_id" IN ( SELECT "profiles"."id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "Users can delete their own connections" ON "public"."connections" FOR DELETE USING ((("auth"."uid"() = "requester_id") OR ("auth"."uid"() = "receiver_id")));



CREATE POLICY "Users can delete their own messages" ON "public"."messages" FOR DELETE USING (("sender_id" = "auth"."uid"()));



CREATE POLICY "Users can delete their own saves" ON "public"."saves" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own saves" ON "public"."video_saves" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own videos" ON "public"."videos" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert chats they're part of" ON "public"."chats" FOR INSERT WITH CHECK ((("auth"."uid"() = "user1_id") OR ("auth"."uid"() = "user2_id")));



CREATE POLICY "Users can insert messages in their chats" ON "public"."messages" FOR INSERT WITH CHECK (((EXISTS ( SELECT 1
   FROM "public"."chats"
  WHERE (("chats"."id" = "messages"."chat_id") AND (("chats"."user1_id" = "auth"."uid"()) OR ("chats"."user2_id" = "auth"."uid"()))))) AND ("sender_id" = "auth"."uid"())));



CREATE POLICY "Users can insert their own profile" ON "public"."profiles" FOR INSERT WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Users can insert their own videos" ON "public"."videos" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can manage their own profile skills" ON "public"."profile_skills" USING (("auth"."uid"() = "profile_id"));



CREATE POLICY "Users can save videos" ON "public"."video_saves" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can share applications" ON "public"."shared_applications" FOR INSERT WITH CHECK ((("auth"."uid"() = "shared_by") AND (EXISTS ( SELECT 1
   FROM ("public"."job_applications" "ja"
     JOIN "public"."job_listings" "jl" ON (("jl"."id" = "ja"."job_listing_id")))
  WHERE (("ja"."id" = "shared_applications"."application_id") AND ("jl"."business_id" = "auth"."uid"()))))));



CREATE POLICY "Users can share listings" ON "public"."shared_listings" FOR INSERT WITH CHECK ((("auth"."uid"() = "shared_by") AND (EXISTS ( SELECT 1
   FROM "public"."job_listings"
  WHERE (("job_listings"."id" = "shared_listings"."listing_id") AND ("job_listings"."business_id" = "auth"."uid"()))))));



CREATE POLICY "Users can update chats they're part of" ON "public"."chats" FOR UPDATE USING ((("auth"."uid"() = "user1_id") OR ("auth"."uid"() = "user2_id")));



CREATE POLICY "Users can update connections they are part of" ON "public"."connections" FOR UPDATE USING ((("auth"."uid"() = "requester_id") OR ("auth"."uid"() = "receiver_id"))) WITH CHECK ((("auth"."uid"() = "requester_id") OR ("auth"."uid"() = "receiver_id")));



CREATE POLICY "Users can update messages in their chats" ON "public"."messages" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."chats"
  WHERE (("chats"."id" = "messages"."chat_id") AND (("chats"."user1_id" = "auth"."uid"()) OR ("chats"."user2_id" = "auth"."uid"()))))));



CREATE POLICY "Users can update own profile" ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can update own videos" ON "public"."videos" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update shared applications" ON "public"."job_applications" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."shared_applications"
  WHERE (("shared_applications"."application_id" = "job_applications"."id") AND ("shared_applications"."shared_with" = "auth"."uid"())))));



CREATE POLICY "Users can update their own notifications" ON "public"."notifications" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own profile" ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can update their own profile embeddings" ON "public"."profile_embeddings" FOR INSERT WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Users can view applications shared with them" ON "public"."shared_applications" FOR SELECT USING ((("auth"."uid"() = "shared_with") OR ("auth"."uid"() = "shared_by")));



CREATE POLICY "Users can view chats they're part of" ON "public"."chats" FOR SELECT USING ((("auth"."uid"() = "user1_id") OR ("auth"."uid"() = "user2_id")));



CREATE POLICY "Users can view listings shared with them" ON "public"."shared_listings" FOR SELECT USING (("auth"."uid"() = "shared_with"));



CREATE POLICY "Users can view messages in their chats" ON "public"."messages" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."chats"
  WHERE (("chats"."id" = "messages"."chat_id") AND (("chats"."user1_id" = "auth"."uid"()) OR ("chats"."user2_id" = "auth"."uid"()))))));



CREATE POLICY "Users can view shared listings" ON "public"."job_listings" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."shared_listings"
  WHERE (("shared_listings"."listing_id" = "shared_listings"."id") AND ("shared_listings"."shared_with" = "auth"."uid"())))));



CREATE POLICY "Users can view their own applications" ON "public"."job_applications" FOR SELECT USING (("auth"."uid"() = "applicant_id"));



CREATE POLICY "Users can view their own connections" ON "public"."connections" FOR SELECT USING ((("auth"."uid"() = "requester_id") OR ("auth"."uid"() = "receiver_id")));



CREATE POLICY "Users can view their own notifications" ON "public"."notifications" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own saves" ON "public"."saves" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own saves" ON "public"."video_saves" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Videos are viewable by everyone" ON "public"."videos" FOR SELECT USING (true);



ALTER TABLE "public"."ai_recommendations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."chats" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."comments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."connections" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."job_applications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."job_embeddings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."job_listings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profile_embeddings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profile_skills" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."saves" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."shared_applications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."shared_listings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."skills" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."video_saves" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."videos" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


CREATE PUBLICATION "supabase_realtime_messages_publication" WITH (publish = 'insert, update, delete, truncate');


ALTER PUBLICATION "supabase_realtime_messages_publication" OWNER TO "supabase_admin";


ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."ai_recommendations";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."chats";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."comments";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."connections";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."job_applications";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."job_embeddings";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."job_listings";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."messages";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."notifications";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."profile_embeddings";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."profiles";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."saves";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."shared_applications";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."shared_listings";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."video_saves";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."videos";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(real[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(real[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(real[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(real[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(double precision[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(double precision[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(double precision[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(double precision[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(integer[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(integer[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(integer[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(integer[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(numeric[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(numeric[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(numeric[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(numeric[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "service_role";




















































































































































































GRANT ALL ON FUNCTION "public"."accept_connection"("p_requester_id" "uuid", "p_receiver_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."accept_connection"("p_requester_id" "uuid", "p_receiver_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."accept_connection"("p_requester_id" "uuid", "p_receiver_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."accept_connection_and_create_chat"("connection_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."accept_connection_and_create_chat"("connection_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."accept_connection_and_create_chat"("connection_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_application_status_notification"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_application_status_notification"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_application_status_notification"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_random_username"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_random_username"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_random_username"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_similar_skills"("query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_similar_skills"("query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_similar_skills"("query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_skill_suggestions"("user_id" "uuid", "match_count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_skill_suggestions"("user_id" "uuid", "match_count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_skill_suggestions"("user_id" "uuid", "match_count" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_skill_suggestions"("user_id" "uuid", "match_count" integer, "similarity_threshold" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."get_skill_suggestions"("user_id" "uuid", "match_count" integer, "similarity_threshold" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_skill_suggestions"("user_id" "uuid", "match_count" integer, "similarity_threshold" double precision) TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."videos" TO "anon";
GRANT ALL ON TABLE "public"."videos" TO "authenticated";
GRANT ALL ON TABLE "public"."videos" TO "service_role";



GRANT ALL ON TABLE "public"."videos_with_profiles" TO "anon";
GRANT ALL ON TABLE "public"."videos_with_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."videos_with_profiles" TO "service_role";



GRANT ALL ON FUNCTION "public"."get_videos"("category_filter" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_videos"("category_filter" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_videos"("category_filter" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "postgres";
GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "anon";
GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "authenticated";
GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_connection_accept"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_connection_accept"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_connection_accept"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "postgres";
GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "anon";
GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "authenticated";
GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "service_role";



GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_shared_application"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_shared_application"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_shared_application"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."test_similarity"("skill_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."test_similarity"("skill_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."test_similarity"("skill_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_skill_embedding"("skill_id" bigint, "embedding_vector" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."update_skill_embedding"("skill_id" bigint, "embedding_vector" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_skill_embedding"("skill_id" bigint, "embedding_vector" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "service_role";


















GRANT ALL ON TABLE "public"."ai_recommendations" TO "anon";
GRANT ALL ON TABLE "public"."ai_recommendations" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_recommendations" TO "service_role";



GRANT ALL ON TABLE "public"."chats" TO "anon";
GRANT ALL ON TABLE "public"."chats" TO "authenticated";
GRANT ALL ON TABLE "public"."chats" TO "service_role";



GRANT ALL ON TABLE "public"."comments" TO "anon";
GRANT ALL ON TABLE "public"."comments" TO "authenticated";
GRANT ALL ON TABLE "public"."comments" TO "service_role";



GRANT ALL ON TABLE "public"."connections" TO "anon";
GRANT ALL ON TABLE "public"."connections" TO "authenticated";
GRANT ALL ON TABLE "public"."connections" TO "service_role";



GRANT ALL ON TABLE "public"."job_applications" TO "anon";
GRANT ALL ON TABLE "public"."job_applications" TO "authenticated";
GRANT ALL ON TABLE "public"."job_applications" TO "service_role";



GRANT ALL ON TABLE "public"."job_embeddings" TO "anon";
GRANT ALL ON TABLE "public"."job_embeddings" TO "authenticated";
GRANT ALL ON TABLE "public"."job_embeddings" TO "service_role";



GRANT ALL ON TABLE "public"."job_listings" TO "anon";
GRANT ALL ON TABLE "public"."job_listings" TO "authenticated";
GRANT ALL ON TABLE "public"."job_listings" TO "service_role";



GRANT ALL ON TABLE "public"."messages" TO "anon";
GRANT ALL ON TABLE "public"."messages" TO "authenticated";
GRANT ALL ON TABLE "public"."messages" TO "service_role";



GRANT ALL ON TABLE "public"."notifications" TO "anon";
GRANT ALL ON TABLE "public"."notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."notifications" TO "service_role";



GRANT ALL ON TABLE "public"."profile_embeddings" TO "anon";
GRANT ALL ON TABLE "public"."profile_embeddings" TO "authenticated";
GRANT ALL ON TABLE "public"."profile_embeddings" TO "service_role";



GRANT ALL ON TABLE "public"."profile_skills" TO "anon";
GRANT ALL ON TABLE "public"."profile_skills" TO "authenticated";
GRANT ALL ON TABLE "public"."profile_skills" TO "service_role";



GRANT ALL ON TABLE "public"."saves" TO "anon";
GRANT ALL ON TABLE "public"."saves" TO "authenticated";
GRANT ALL ON TABLE "public"."saves" TO "service_role";



GRANT ALL ON TABLE "public"."shared_applications" TO "anon";
GRANT ALL ON TABLE "public"."shared_applications" TO "authenticated";
GRANT ALL ON TABLE "public"."shared_applications" TO "service_role";



GRANT ALL ON TABLE "public"."shared_listings" TO "anon";
GRANT ALL ON TABLE "public"."shared_listings" TO "authenticated";
GRANT ALL ON TABLE "public"."shared_listings" TO "service_role";



GRANT ALL ON TABLE "public"."skills" TO "anon";
GRANT ALL ON TABLE "public"."skills" TO "authenticated";
GRANT ALL ON TABLE "public"."skills" TO "service_role";



GRANT ALL ON SEQUENCE "public"."skills_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."skills_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."skills_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."video_saves" TO "anon";
GRANT ALL ON TABLE "public"."video_saves" TO "authenticated";
GRANT ALL ON TABLE "public"."video_saves" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";






























RESET ALL;
