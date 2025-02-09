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