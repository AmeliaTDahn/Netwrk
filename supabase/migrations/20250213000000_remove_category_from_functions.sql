-- Drop the category index since we removed the column
DROP INDEX IF EXISTS skills_category_idx;

-- Drop existing functions first
DROP FUNCTION IF EXISTS get_similar_skills(vector, float, int);
DROP FUNCTION IF EXISTS get_skill_suggestions(uuid, int, float);
DROP FUNCTION IF EXISTS test_similarity(text);

-- Update get_similar_skills function to remove category
CREATE OR REPLACE FUNCTION get_similar_skills(
  query_embedding vector(384),
  match_threshold float,
  match_count int
)
RETURNS TABLE (
  id bigint,
  name text,
  similarity float
)
LANGUAGE plpgsql
AS $$
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

-- Update get_skill_suggestions function to remove category
CREATE OR REPLACE FUNCTION get_skill_suggestions(
  user_id uuid,
  match_count int default 5,
  similarity_threshold float default 0.7
)
RETURNS TABLE (
  skill_name text,
  similarity float,
  based_on text
)
LANGUAGE plpgsql
AS $$
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

-- Update test_similarity function to remove category
CREATE OR REPLACE FUNCTION test_similarity(skill_name text)
RETURNS TABLE (
  similar_skill text,
  similarity float
)
LANGUAGE plpgsql
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
    1 - (s.embedding <=> target_embedding) as similarity
  from skills s
  where s.name != skill_name
  order by similarity desc
  limit 5;
end;
$$; 