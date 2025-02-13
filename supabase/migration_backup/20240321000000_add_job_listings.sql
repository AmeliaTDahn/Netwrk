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