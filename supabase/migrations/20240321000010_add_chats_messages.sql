-- Create chats table
create table if not exists public.chats (
    id uuid default gen_random_uuid() primary key,
    user1_id uuid references public.profiles(id) on delete cascade not null,
    user2_id uuid references public.profiles(id) on delete cascade not null,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at timestamp with time zone default timezone('utc'::text, now()) not null,
    unique(user1_id, user2_id)
);

-- Create messages table
create table if not exists public.messages (
    id uuid default gen_random_uuid() primary key,
    chat_id uuid references public.chats(id) on delete cascade not null,
    sender_id uuid references public.profiles(id) on delete cascade not null,
    content text not null,
    read_at timestamp with time zone,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null,
    updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Add trigger for chats updated_at
create trigger handle_chats_updated_at
    before update on public.chats
    for each row
    execute function public.handle_updated_at();

-- Add trigger for messages updated_at
create trigger handle_messages_updated_at
    before update on public.messages
    for each row
    execute function public.handle_updated_at();

-- Enable RLS
alter table public.chats enable row level security;
alter table public.messages enable row level security;

-- Add RLS policies for chats
create policy "Users can view their own chats"
    on public.chats
    for select
    using (auth.uid() in (user1_id, user2_id));

create policy "Users can create chats with other users"
    on public.chats
    for insert
    with check (auth.uid() in (user1_id, user2_id));

-- Add RLS policies for messages
create policy "Users can view messages in their chats"
    on public.messages
    for select
    using (
        exists (
            select 1
            from public.chats
            where chats.id = messages.chat_id
            and auth.uid() in (user1_id, user2_id)
        )
    );

create policy "Users can send messages in their chats"
    on public.messages
    for insert
    with check (
        auth.uid() = sender_id
        and exists (
            select 1
            from public.chats
            where chats.id = messages.chat_id
            and auth.uid() in (user1_id, user2_id)
        )
    );

create policy "Users can update read status of messages sent to them"
    on public.messages
    for update
    using (
        exists (
            select 1
            from public.chats
            where chats.id = messages.chat_id
            and auth.uid() in (user1_id, user2_id)
            and auth.uid() != sender_id
        )
    ); 