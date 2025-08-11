-- php artisan migrate should run first before this script

-- Laravel Database Setup Script

-- Create schemas if not exists
CREATE SCHEMA IF NOT EXISTS laravel;

-- Create a dedicated role for Laravel application users
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user NOLOGIN;
    END IF;
END $$;

-- Helper function to get current user ID
CREATE OR REPLACE FUNCTION app.current_user_id()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, app
AS $$
DECLARE
    current_uid bigint;
BEGIN
    current_uid := nullif(current_setting('app.user_id', true), '')::bigint;
    RETURN current_uid;
END;
$$;

-- Harden function privileges
REVOKE EXECUTE ON FUNCTION app.current_user_id() FROM PUBLIC;

-- Helper function to get login email
CREATE OR REPLACE FUNCTION app.current_login_email()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, app
AS $$
DECLARE
    login_email text;
BEGIN
    login_email := nullif(current_setting('app.login_email', true), '')::text;
    RETURN login_email;
END;
$$;

-- Harden function privileges
REVOKE EXECUTE ON FUNCTION app.current_login_email() FROM PUBLIC;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION app.current_user_id() TO authenticated';
    EXECUTE 'GRANT EXECUTE ON FUNCTION app.current_login_email() TO authenticated';
  END IF;
END $$;

-- Move users table to laravel schema
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'users') THEN
        ALTER TABLE public.users SET SCHEMA laravel;
    END IF;
END $$;

-- Ensure users table has proper RLS
DO $$
DECLARE 
    v_table_exists BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'laravel' AND c.relname = 'users'
    ) INTO v_table_exists;

    IF v_table_exists THEN
        -- Enable RLS
        EXECUTE 'ALTER TABLE laravel.users ENABLE ROW LEVEL SECURITY';
        EXECUTE 'ALTER TABLE laravel.users FORCE ROW LEVEL SECURITY';

        -- Drop existing policies
        EXECUTE 'DROP POLICY IF EXISTS select_own_user ON laravel.users';
        EXECUTE 'DROP POLICY IF EXISTS update_own_user ON laravel.users';
        EXECUTE 'DROP POLICY IF EXISTS insert_user_registration ON laravel.users';
        EXECUTE 'DROP POLICY IF EXISTS select_login_by_email ON laravel.users';

        -- Select own user policy
        EXECUTE 'CREATE POLICY select_own_user 
        ON laravel.users 
        FOR SELECT 
        TO authenticated 
        USING (id = app.current_user_id())';

        -- Update own user policy
        EXECUTE 'CREATE POLICY update_own_user 
        ON laravel.users 
        FOR UPDATE 
        TO authenticated 
        USING (id = app.current_user_id()) 
        WITH CHECK (id = app.current_user_id())';

        -- Flexible user insertion policy for new user registration
        EXECUTE 'CREATE POLICY insert_user_registration 
        ON laravel.users 
        FOR INSERT 
        TO authenticated 
        WITH CHECK (
            app.current_user_id() IS NULL 
            AND length(email) > 0 
            AND length(password) > 0
        )';

        -- Login by email policy
        EXECUTE 'CREATE POLICY select_login_by_email 
        ON laravel.users 
        FOR SELECT 
        TO authenticated 
        USING (
            coalesce(current_setting(''app.user_id'', true), '''') = ''''
            AND lower(email) = lower(coalesce(current_setting(''app.login_email'', true), ''''))
        )';
    END IF;
END $$;

-- Grant schema and table permissions
DO $$
BEGIN
    IF to_regclass('laravel.users') IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
            EXECUTE 'GRANT USAGE ON SCHEMA laravel TO authenticated';
            EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON laravel.users TO authenticated';
        END IF;
        
        -- Grant sequence privileges if exists
        IF to_regclass('laravel.users_id_seq') IS NOT NULL THEN
            IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
                EXECUTE 'GRANT USAGE, SELECT, UPDATE ON SEQUENCE laravel.users_id_seq TO authenticated';
            END IF;
        END IF;
    END IF;
END $$;

-- Optional: Enable RLS on other tables in Laravel schema
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT n.nspname AS schema_name, c.relname AS table_name
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'laravel'
        AND c.relkind IN ('r','p')
        AND c.relname NOT IN (
            'users', 'migrations', 'jobs', 'job_batches', 
            'cache', 'sessions', 'password_reset_tokens', 
            'personal_access_tokens'
        )
    LOOP
        EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', r.schema_name, r.table_name);
        EXECUTE format('ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY', r.schema_name, r.table_name);
    END LOOP;
END $$;
