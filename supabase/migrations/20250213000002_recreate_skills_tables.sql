-- Enable the pgvector extension if not already enabled
create extension if not exists vector;

-- Create a skills table to store all available skills
create table if not exists public.skills (
  id bigint primary key generated always as identity,
  name text not null unique,
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

-- Profile skills policies
create policy "Profile skills are viewable by everyone"
  on profile_skills for select
  using (true);

create policy "Users can manage their own profile skills"
  on profile_skills for all
  using (auth.uid() = profile_id);

-- Create indexes
create index if not exists skills_name_idx on skills(name);
create index if not exists profile_skills_profile_id_idx on profile_skills(profile_id);
create index if not exists profile_skills_skill_id_idx on profile_skills(skill_id);

-- Create function to insert skill with embedding
create or replace function insert_skill_with_embedding(
  skill_name text,
  embedding_vector text
)
returns bigint
language plpgsql
as $$
declare
  new_skill_id bigint;
begin
  -- Insert the skill and get its ID
  insert into skills (name, embedding)
  values (skill_name, embedding_vector::vector)
  returning id into new_skill_id;
  
  return new_skill_id;
end;
$$;

-- Create function to find similar skills
create or replace function get_similar_skills(
  query_embedding vector(384),
  match_threshold float,
  match_count int
)
returns table (
  id bigint,
  name text,
  similarity float
)
language plpgsql
as $$
begin
  return query
  select
    skills.id,
    skills.name,
    1 - (skills.embedding <=> query_embedding) as similarity
  from skills
  where 1 - (skills.embedding <=> query_embedding) > match_threshold
  order by similarity desc
  limit match_count;
end;
$$;

-- Create function to get skill suggestions for a user
create or replace function get_skill_suggestions(
  user_id uuid,
  match_count int default 5,
  similarity_threshold float default 0.7
)
returns table (
  skill_name text,
  similarity float,
  based_on text
)
language plpgsql
as $$
begin
  return query
  with user_skills as (
    -- Get all the user's current skills
    select s.id, s.name, s.embedding
    from profile_skills ps
    join skills s on s.id = ps.skill_id
    where ps.profile_id = user_id
  )
  , similar_skills as (
    -- Find similar skills for each of user's skills
    select 
      s.name as suggested_skill,
      us.name as based_on_skill,
      1 - (s.embedding <=> us.embedding) as similarity_score
    from user_skills us
    cross join lateral (
      select s.name, s.embedding
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
    similarity_score,
    based_on_skill
  from similar_skills
  order by similarity_score desc
  limit match_count;
end;
$$;

-- Create function to test similarity between skills
create or replace function test_similarity(skill_name text)
returns table (
  similar_skill text,
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
    1 - (s.embedding <=> target_embedding) as similarity
  from skills s
  where s.name != skill_name
  order by similarity desc
  limit 5;
end;
$$;

-- Add update trigger for skills
create trigger update_skills_updated_at
  before update on skills
  for each row
  execute function update_updated_at_column(); 