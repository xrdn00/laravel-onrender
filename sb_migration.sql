-- php artisan migrate should run first before this script

create schema if not exists app;
create schema if not exists laravel;

-- Helper to fetch the current application user id from a connection setting
create or replace function app.current_user_id()
returns bigint
language sql
stable
as $$
  select nullif(current_setting('app.user_id', true), '')::bigint
$$;

-- Helper to fetch the login email (used only during unauthenticated login)
create or replace function app.current_login_email()
returns text
language sql
stable
as $$
  select nullif(current_setting('app.login_email', true), '')::text
$$;

-- Move users table to laravel schema if it exists in public
alter table if exists public.users set schema laravel;

-- Enable and force RLS on users and add owner-scoped policies
alter table if exists laravel.users enable row level security;
alter table if exists laravel.users force row level security;

do $$
begin
  -- Only attempt to create policies if the target table exists
  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'laravel' and c.relname = 'users'
  ) then
  if not exists (
    select 1 from pg_policy p
    join pg_class c ON p.polrelid = c.oid
    join pg_namespace n ON c.relnamespace = n.oid
    where n.nspname = 'laravel' 
    and c.relname = 'users' 
    and p.polname = 'select_own_user'
  ) then
    create policy select_own_user
    on laravel.users
    for select
    using (id = app.current_user_id());
  end if;

  if not exists (
    select 1 from pg_policy p
    join pg_class c ON p.polrelid = c.oid
    join pg_namespace n ON c.relnamespace = n.oid
    where n.nspname = 'laravel' 
    and c.relname = 'users' 
    and p.polname = 'update_own_user'
  ) then
    create policy update_own_user
    on laravel.users
    for update
    using (id = app.current_user_id())
    with check (id = app.current_user_id());
  end if;

  if not exists (
    select 1 from pg_policy p
    join pg_class c ON p.polrelid = c.oid
    join pg_namespace n ON c.relnamespace = n.oid
    where n.nspname = 'laravel' 
    and c.relname = 'users' 
    and p.polname = 'insert_user_open'
  ) then
    create policy insert_user_open
    on laravel.users
    for insert
    with check (true);
  end if;

  -- Allow selecting a user row for login using the attempted email (unauthenticated)
  if not exists (
    select 1 from pg_policy p
    join pg_class c ON p.polrelid = c.oid
    join pg_namespace n ON c.relnamespace = n.oid
    where n.nspname = 'laravel'
      and c.relname = 'users'
      and p.polname = 'select_login_by_email'
  ) then
    create policy select_login_by_email
    on laravel.users
    for select
    using (
      coalesce(current_setting('app.user_id', true), '') = ''
      and lower(email) = lower(coalesce(current_setting('app.login_email', true), ''))
    );
  end if;
  end if;
end
$$;

-- Enable and force RLS on every table in the `laravel` schema except `users`
do $$
declare r record;
begin
  for r in
    select n.nspname as schema_name, c.relname as table_name
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'laravel'
      and c.relkind in ('r','p') -- ordinary and partitioned tables
      and c.relname not in (
        'users',
        'migrations',
        'jobs',
        'job_batches',
        'cache',
        'sessions',
        'password_reset_tokens',
        'personal_access_tokens'
      )
  loop
    execute format('alter table %I.%I enable row level security', r.schema_name, r.table_name);
    execute format('alter table %I.%I force row level security', r.schema_name, r.table_name);
  end loop;
end
$$;