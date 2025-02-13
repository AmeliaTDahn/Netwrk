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
  -- Debug logging
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
      where s.id != us.id  -- Don't suggest the same skill
      and s.id not in (select id from user_skills)  -- Don't suggest skills user already has
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