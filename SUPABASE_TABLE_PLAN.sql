-- Mimi Locks starter table plan for a real shared backend.
-- This is a starter schema, not a finished security policy set.
-- In Supabase, enable Row Level Security and add policies so:
-- - users can read public feed/server data
-- - users can insert their own content
-- - users can update/delete only rows where owner_email = auth user's email
-- - admins can manage everything

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text unique not null,
  display_name text,
  role text default 'user' check (role in ('user', 'admin')),
  profile_picture text,
  bio text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table public.artworks (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete cascade,
  owner_email text not null,
  title text not null,
  description text,
  image_url text,
  music_url text,
  medium text,
  featured boolean default false,
  likes text[] default '{}',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  artwork_id uuid references public.artworks(id) on delete cascade,
  owner_id uuid references auth.users(id) on delete cascade,
  owner_email text not null,
  content text not null,
  likes text[] default '{}',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table public.communities (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete cascade,
  owner_email text not null,
  name text not null,
  description text,
  icon_url text,
  icon_emoji text,
  banner_url text,
  member_emails text[] default '{}',
  welcome_message text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table public.server_channels (
  id uuid primary key default gen_random_uuid(),
  community_id uuid references public.communities(id) on delete cascade,
  name text not null,
  type text default 'text' check (type in ('text', 'voice')),
  description text,
  position int default 0,
  allowed_roles text[] default '{}',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table public.channel_messages (
  id uuid primary key default gen_random_uuid(),
  community_id uuid references public.communities(id) on delete cascade,
  channel_id uuid references public.server_channels(id) on delete cascade,
  owner_id uuid references auth.users(id) on delete cascade,
  owner_email text not null,
  user_display_name text,
  user_profile_picture text,
  content text,
  image_url text,
  reply_to_id uuid,
  reactions jsonb default '{}'::jsonb,
  is_pinned boolean default false,
  is_edited boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table public.site_config (
  key text primary key,
  announcement text,
  announcement_active boolean default false,
  announcement_color text,
  primary_color text,
  updated_at timestamptz default now()
);
