-- Schema for application-scoped helpers
create schema if not exists app;

-- Helper to fetch the current application user id from a connection setting
create or replace function app.current_user_id()
returns bigint
language sql
stable
as $$
  select nullif(current_setting('app.user_id', true), '')::bigint
$$;

-- Enable and force RLS on users and add owner-scoped policies
alter table if exists public.users enable row level security;
alter table if exists public.users force row level security;

do $$
begin
  if not exists (
    select 1 from pg_policy p
    join pg_class c ON p.polrelid = c.oid
    join pg_namespace n ON c.relnamespace = n.oid
    where n.nspname = 'public' 
    and c.relname = 'users' 
    and p.polname = 'select_own_user'
  ) then
    create policy select_own_user
    on public.users
    for select
    using (id = app.current_user_id());
  end if;

  if not exists (
    select 1 from pg_policy p
    join pg_class c ON p.polrelid = c.oid
    join pg_namespace n ON c.relnamespace = n.oid
    where n.nspname = 'public' 
    and c.relname = 'users' 
    and p.polname = 'update_own_user'
  ) then
    create policy update_own_user
    on public.users
    for update
    using (id = app.current_user_id())
    with check (id = app.current_user_id());
  end if;

  if not exists (
    select 1 from pg_policy p
    join pg_class c ON p.polrelid = c.oid
    join pg_namespace n ON c.relnamespace = n.oid
    where n.nspname = 'public' 
    and c.relname = 'users' 
    and p.polname = 'insert_user_open'
  ) then
    create policy insert_user_open
    on public.users
    for insert
    with check (true);
  end if;
end
$$;