-- Add min_salary and max_salary columns
alter table public.job_listings
  add column min_salary numeric,
  add column max_salary numeric;

-- Copy existing salary data to new columns
-- This handles empty strings and null values
update public.job_listings
set 
  min_salary = (
    select 
      case 
        when salary is null or salary = '' then null
        when regexp_replace(split_part(salary, '-', 1), '[^0-9]', '', 'g') = '' then null
        else cast(regexp_replace(split_part(salary, '-', 1), '[^0-9]', '', 'g') as numeric)
      end
  ),
  max_salary = (
    select 
      case 
        when salary is null or salary = '' then null
        when position('-' in salary) > 0 then
          case 
            when regexp_replace(split_part(salary, '-', 2), '[^0-9]', '', 'g') = '' then null
            else cast(regexp_replace(split_part(salary, '-', 2), '[^0-9]', '', 'g') as numeric)
          end
        else
          case 
            when regexp_replace(split_part(salary, '-', 1), '[^0-9]', '', 'g') = '' then null
            else cast(regexp_replace(split_part(salary, '-', 1), '[^0-9]', '', 'g') as numeric)
          end
      end
  );

-- Drop old salary column
alter table public.job_listings
  drop column if exists salary; 