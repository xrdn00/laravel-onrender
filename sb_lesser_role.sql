-- This script should be executed by role that can CREATE ROLE (e.g., Supabase SQL Editor running as superuser). Don’t run this from Laravel using a restricted role; it will fail. 
-- Safely create role if it doesn't exist
-- replace STRONG_PASSWORD placeholders with your real password
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user LOGIN PASSWORD 'STRONG_PASSWORD';
    ELSE
        ALTER ROLE app_user WITH PASSWORD 'STRONG_PASSWORD';
    END IF;
END
$$;

-- 1b) Ensure the role can connect to the target database
GRANT CONNECT ON DATABASE postgres TO app_user;

-- 2) give it access only to your app schema
GRANT USAGE, CREATE ON SCHEMA laravel TO app_user;

-- Optional: set a default search_path for this role (Laravel also sets this via config)
ALTER ROLE app_user SET search_path = 'laravel, public';

-- 3) grant needed privileges on existing objects
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA laravel TO app_user;
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA laravel TO app_user;

-- 4) ensure future tables/sequences get the same grants
-- If objects are created by postgres (or your CI admin role), grant app_user rights by default
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA laravel
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA laravel
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO app_user;