-- Add latitude and longitude columns to profiles table
alter table public.profiles
  add column latitude double precision,
  add column longitude double precision;

-- Create an index for location-based queries
create index idx_profiles_location
  on public.profiles (latitude, longitude)
  where latitude is not null and longitude is not null; 