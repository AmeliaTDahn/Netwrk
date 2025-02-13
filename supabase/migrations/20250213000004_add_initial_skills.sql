-- Create a function to initialize skills with embeddings
create or replace function initialize_common_skills()
returns void
language plpgsql
as $$
declare
  common_skills text[] := array[
    'Python',
    'JavaScript',
    'Project Management',
    'Data Analysis',
    'Communication',
    'Leadership',
    'Marketing',
    'Sales',
    'UI/UX Design',
    'Product Management'
  ];
  skill text;
begin
  foreach skill in array common_skills
  loop
    -- Only insert if skill doesn't exist
    if not exists (select 1 from skills where name = skill) then
      -- Insert without embedding first
      insert into skills (name)
      values (skill);
    end if;
  end loop;
end;
$$;

-- Call the function to initialize skills
select initialize_common_skills(); 