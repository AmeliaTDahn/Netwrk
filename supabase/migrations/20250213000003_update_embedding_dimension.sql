-- Drop existing functions that depend on the embedding column
drop function if exists get_similar_skills(vector(384), float, int);
drop function if exists get_skill_suggestions(uuid, int, float);
drop function if exists test_similarity(text);
drop function if exists insert_skill_with_embedding(text, text);

-- Alter the skills table to change embedding dimension
alter table skills 
alter column embedding type vector(1536) using embedding::vector(1536);

-- Recreate functions with updated embedding dimension
create or replace function get_similar_skills(
  query_embedding vector(1536),
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
    select s.id, s.name, s.embedding
    from profile_skills ps
    join skills s on s.id = ps.skill_id
    where ps.profile_id = user_id
  )
  , similar_skills as (
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

create or replace function test_similarity(skill_name text)
returns table (
  similar_skill text,
  similarity float
)
language plpgsql
as $$
declare
  target_embedding vector(1536);
begin
  select embedding into target_embedding
  from skills
  where name = skill_name;
  
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
  insert into skills (name, embedding)
  values (skill_name, embedding_vector::vector)
  returning id into new_skill_id;
  
  return new_skill_id;
end;
$$; 