-- php artisan migrate should run first before this script

-- Create schemas
CREATE SCHEMA IF NOT EXISTS app;
CREATE SCHEMA IF NOT EXISTS laravel;

-- Create a dedicated role for Laravel application users
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'laravel_app_user') THEN
        CREATE ROLE laravel_app_user WITH LOGIN;
    END IF;
END $$;

-- Grant necessary schema privileges
GRANT USAGE ON SCHEMA laravel TO laravel_app_user;
GRANT CREATE ON SCHEMA laravel TO laravel_app_user;

-- Enhanced helper function to fetch the current application user id
CREATE OR REPLACE FUNCTION app.current_user_id()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    current_uid bigint;
BEGIN
    -- Ensure the current role has appropriate access
    IF NOT pg_has_role(SESSION_USER, 'laravel_app_user', 'MEMBER') THEN
        RAISE EXCEPTION 'Unauthorized access to current_user_id()';
    END IF;

    -- Fetch user ID from connection setting
    current_uid := nullif(current_setting('app.user_id', true), '')::bigint;
    
    RETURN current_uid;
END;
$$;

-- Enhanced helper function to fetch login email
CREATE OR REPLACE FUNCTION app.current_login_email()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    login_email text;
BEGIN
    -- Ensure the current role has appropriate access
    IF NOT pg_has_role(SESSION_USER, 'laravel_app_user', 'MEMBER') THEN
        RAISE EXCEPTION 'Unauthorized access to current_login_email()';
    END IF;

    -- Fetch login email from connection setting
    login_email := nullif(current_setting('app.login_email', true), '')::text;
    
    RETURN login_email;
END;
$$;

-- Move users table to laravel schema if it exists in public
ALTER TABLE IF EXISTS public.users SET SCHEMA laravel;

-- Enable and force RLS on users table
ALTER TABLE IF EXISTS laravel.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS laravel.users FORCE ROW LEVEL SECURITY;

-- Create RLS Policies for Users Table
DO $$
DECLARE 
    v_table_exists BOOLEAN;
BEGIN
    -- Check if users table exists
    SELECT EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'laravel' AND c.relname = 'users'
    ) INTO v_table_exists;

    IF v_table_exists THEN
        -- Select own user policy
        IF NOT EXISTS (
            SELECT 1 FROM pg_policy p
            JOIN pg_class c ON p.polrelid = c.oid
            JOIN pg_namespace n ON c.relnamespace = n.oid
            WHERE n.nspname = 'laravel' 
            AND c.relname = 'users' 
            AND p.polname = 'select_own_user'
        ) THEN
            EXECUTE 'CREATE POLICY select_own_user
            ON laravel.users
            FOR SELECT
            USING (id = app.current_user_id())';
        END IF;

        -- Update own user policy
        IF NOT EXISTS (
            SELECT 1 FROM pg_policy p
            JOIN pg_class c ON p.polrelid = c.oid
            JOIN pg_namespace n ON c.relnamespace = n.oid
            WHERE n.nspname = 'laravel' 
            AND c.relname = 'users' 
            AND p.polname = 'update_own_user'
        ) THEN
            EXECUTE 'CREATE POLICY update_own_user
            ON laravel.users
            FOR UPDATE
            USING (id = app.current_user_id())
            WITH CHECK (id = app.current_user_id())';
        END IF;

        -- Open user insertion policy
        IF NOT EXISTS (
            SELECT 1 FROM pg_policy p
            JOIN pg_class c ON p.polrelid = c.oid
            JOIN pg_namespace n ON c.relnamespace = n.oid
            WHERE n.nspname = 'laravel' 
            AND c.relname = 'users' 
            AND p.polname = 'insert_user_open'
        ) THEN
            EXECUTE 'CREATE POLICY insert_user_open
            ON laravel.users
            FOR INSERT
            WITH CHECK (true)';
        END IF;

        -- Login by email policy
        IF NOT EXISTS (
            SELECT 1 FROM pg_policy p
            JOIN pg_class c ON p.polrelid = c.oid
            JOIN pg_namespace n ON c.relnamespace = n.oid
            WHERE n.nspname = 'laravel'
            AND c.relname = 'users'
            AND p.polname = 'select_login_by_email'
        ) THEN
            EXECUTE 'CREATE POLICY select_login_by_email
            ON laravel.users
            FOR SELECT
            USING (
                coalesce(current_setting(''app.user_id'', true), '''') = ''''
                AND lower(email) = lower(coalesce(current_setting(''app.login_email'', true), ''''))
            )';
        END IF;

        -- Comprehensive Users Table RLS Policies
        -- Detailed user management policies
        IF NOT EXISTS (
            SELECT 1 FROM pg_policy p
            JOIN pg_class c ON p.polrelid = c.oid
            JOIN pg_namespace n ON c.relnamespace = n.oid
            WHERE n.nspname = 'laravel'
            AND c.relname = 'users'
            AND p.polname = 'detailed_user_management'
        ) THEN
            EXECUTE 'CREATE POLICY detailed_user_management
            ON laravel.users
            FOR ALL
            USING (
                -- Allow full access to own record
                id = app.current_user_id() 
                OR 
                -- Optional: Allow admin users full access
                COALESCE(
                    (current_setting(''app.user_role'', true) = ''admin''),
                    false
                )
            )
            WITH CHECK (
                -- Restrict updates to specific columns
                id = app.current_user_id()
                AND (
                    -- Define which columns can be updated
                    name IS NOT NULL 
                    AND length(name) BETWEEN 2 AND 255
                    AND email ~* ''^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$''
                )
            )';
        END IF;
    END IF;
END $$;

-- Rest of the script remains the same (the code you originally provided)
-- ... (continue with the existing script from here)

-- Enable RLS on all tables in laravel schema (except specific system tables)
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT n.nspname AS schema_name, c.relname AS table_name
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'laravel'
      AND c.relkind IN ('r','p') -- ordinary and partitioned tables
      AND c.relname NOT IN (
        'users',
        'migrations',
        'jobs',
        'job_batches',
        'cache',
        'sessions',
        'password_reset_tokens',
        'personal_access_tokens'
      )
  LOOP
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', r.schema_name, r.table_name);
    EXECUTE format('ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY', r.schema_name, r.table_name);
  END LOOP;
END $$;

-- (Rest of the script continues...)