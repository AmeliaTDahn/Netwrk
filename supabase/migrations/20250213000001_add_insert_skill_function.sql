-- Create function to insert skill with embedding
CREATE OR REPLACE FUNCTION insert_skill_with_embedding(
  skill_name text,
  embedding_vector text,
  skill_category text DEFAULT 'Other'
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  new_skill_id bigint;
BEGIN
  -- Insert the skill and get its ID
  INSERT INTO skills (name, category, embedding)
  VALUES (skill_name, skill_category, embedding_vector::vector)
  RETURNING id INTO new_skill_id;
  
  RETURN new_skill_id;
END;
$$; 