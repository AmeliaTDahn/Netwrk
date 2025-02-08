-- Drop existing policies if they exist
drop policy if exists "Users can view their own applications" on public.job_applications;
drop policy if exists "Users can create applications" on public.job_applications;
drop policy if exists "Businesses can view applications for their listings" on public.job_applications;
drop policy if exists "Businesses can update application status" on public.job_applications;

-- Drop existing table if it exists
drop table if exists public.job_applications;

-- Create applications storage bucket if it doesn't exist
insert into storage.buckets (id, name, public)
values ('applications', 'applications', true)
on conflict (id) do nothing;

-- Storage policies for applications bucket
create policy "Anyone can view application files"
    on storage.objects for select
    using ( bucket_id = 'applications' );

create policy "Authenticated users can upload application files"
    on storage.objects for insert
    with check (
        bucket_id = 'applications'
        and auth.role() = 'authenticated'
    );

-- Create job_applications table
create table public.job_applications (
    id uuid default gen_random_uuid() primary key,
    job_listing_id uuid references public.job_listings(id) on delete cascade not null,
    applicant_id uuid references public.profiles(id) on delete cascade not null,
    video_url text not null,
    resume_url text,
    cover_note text,
    status text check (status in ('pending', 'rejected', 'interviewing', 'accepted', 'saved', 'viewed')) default 'pending',
    viewed_at timestamp with time zone,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at timestamp with time zone default timezone('utc'::text, now()) not null,
    unique(job_listing_id, applicant_id)
);

-- Add trigger for updated_at
create trigger handle_job_applications_updated_at
    before update on public.job_applications
    for each row
    execute function public.handle_updated_at();

-- Enable RLS
alter table public.job_applications enable row level security;

-- Add RLS policies
create policy "Users can view their own applications"
    on public.job_applications
    for select
    using (auth.uid() = applicant_id);

create policy "Users can create applications"
    on public.job_applications
    for insert
    with check (auth.uid() = applicant_id);

create policy "Businesses can view applications for their listings"
    on public.job_applications
    for select
    using (
        exists (
            select 1
            from public.job_listings
            where job_listings.id = job_applications.job_listing_id
            and job_listings.business_id = auth.uid()
        )
    );

create policy "Businesses can update application status"
    on public.job_applications
    for update
    using (
        exists (
            select 1
            from public.job_listings
            where job_listings.id = job_applications.job_listing_id
            and job_listings.business_id = auth.uid()
        )
    );

-- Create notifications table for job applications
create table if not exists public.notifications (
    id uuid default gen_random_uuid() primary key,
    user_id uuid references public.profiles(id) on delete cascade not null,
    title text not null,
    message text not null,
    type text not null,
    is_read boolean default false,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable RLS on notifications
alter table public.notifications enable row level security;

-- Add RLS policies for notifications
create policy "Users can view their own notifications"
    on public.notifications
    for select
    using (auth.uid() = user_id);

create policy "System can create notifications"
    on public.notifications
    for insert
    with check (true);

create policy "Users can update their own notifications"
    on public.notifications
    for update
    using (auth.uid() = user_id);

-- Add function to create application status notification
create or replace function create_application_status_notification()
returns trigger
language plpgsql
security definer
as $$
declare
    job_title text;
    business_name text;
begin
    -- Get job title and business name
    select 
        job_listings.title,
        profiles.business_name
    into
        job_title,
        business_name
    from job_listings
    join profiles on profiles.id = job_listings.business_id
    where job_listings.id = NEW.job_listing_id;

    -- Create notification based on status
    insert into notifications (
        user_id,
        title,
        message,
        type
    )
    values (
        NEW.applicant_id,
        case
            when NEW.status = 'accepted' then 'Application Accepted!'
            when NEW.status = 'rejected' then 'Application Update'
            when NEW.status = 'interviewing' then 'Interview Request'
            else 'Application Update'
        end,
        case
            when NEW.status = 'accepted' then 'Congratulations! Your application for ' || job_title || ' at ' || business_name || ' has been accepted!'
            when NEW.status = 'rejected' then 'Thank you for your interest in ' || job_title || ' at ' || business_name || '. Unfortunately, we have decided to move forward with other candidates.'
            when NEW.status = 'interviewing' then business_name || ' would like to interview you for the ' || job_title || ' position!'
            else 'Your application status for ' || job_title || ' has been updated to: ' || NEW.status
        end,
        NEW.status
    );

    return NEW;
end;
$$;

-- Add trigger for application status changes
create trigger on_application_status_change
    after update of status on job_applications
    for each row
    when (OLD.status is distinct from NEW.status)
    execute function create_application_status_notification(); 