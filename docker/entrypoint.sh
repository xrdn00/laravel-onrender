#!/usr/bin/env sh
set -e

# Default to port 8080 if not provided (Render sets $PORT)
: "${PORT:=8080}"

# Update Apache listen port if PORT provided by platform
if [ -n "$PORT" ]; then
  sed -ri "s/^Listen .*/Listen ${PORT}/" /etc/apache2/ports.conf
  # Also update VirtualHost if present
  if grep -q "<VirtualHost \*:80>" /etc/apache2/sites-available/000-default.conf; then
    sed -ri "s/<VirtualHost \*:80>/<VirtualHost *:${PORT}>/" /etc/apache2/sites-available/000-default.conf
  fi
fi

# Ensure storage structure (handles empty persistent disk)
if [ ! -d "storage/framework" ]; then
  mkdir -p storage/app/public \
           storage/framework/cache \
           storage/framework/sessions \
           storage/framework/testing \
           storage/framework/views
fi

# Permissions for storage and cache
chown -R www-data:www-data storage bootstrap/cache 2>/dev/null || true
chmod -R ug+rwx storage bootstrap/cache 2>/dev/null || true

# Generate APP_KEY if missing
if [ ! -f "/var/www/html/storage/app_key_set" ]; then
  if ! grep -q '^APP_KEY=' .env 2>/dev/null || [ -z "$(grep '^APP_KEY=' .env | cut -d= -f2)" ]; then
    php artisan key:generate --force --no-interaction || true
  fi
  touch /var/www/html/storage/app_key_set || true
fi

# Run Laravel package discovery (Composer scripts were skipped during build)
php artisan package:discover --ansi --no-interaction || true

# Cache config and routes for performance (ignore failures if any)
php artisan config:cache --no-interaction || true
php artisan route:cache --no-interaction || true
php artisan view:cache --no-interaction || true

# Ensure public storage symlink
php artisan storage:link --no-interaction || true

exec "$@"


