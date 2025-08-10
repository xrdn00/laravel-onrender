# --- Build frontend assets (Vite) ---
FROM node:20-alpine AS frontend
WORKDIR /app

# Only copy what's needed to build assets
COPY package*.json ./
COPY vite.config.js postcss.config.js tailwind.config.js jsconfig.json ./
COPY resources ./resources

RUN npm ci --no-audit --no-fund \
    && npm run build


# --- Install PHP dependencies with Composer ---
FROM composer:2 AS vendor
WORKDIR /app

COPY composer.json composer.lock ./
RUN composer install \
    --no-dev \
    --prefer-dist \
    --no-progress \
    --no-interaction \
    --optimize-autoloader


# --- Final runtime image (Apache + PHP) ---
FROM php:8.3-apache

ENV APP_ENV=production \
    APP_DEBUG=false \
    LOG_CHANNEL=stderr

WORKDIR /var/www/html

# System deps and PHP extensions commonly required by Laravel
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libzip-dev \
        libpng-dev \
        libjpeg62-turbo-dev \
        libfreetype6-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" \
        pdo_mysql \
        bcmath \
        exif \
        gd \
        zip \
        opcache; \
    a2enmod rewrite headers; \
    rm -rf /var/lib/apt/lists/*

# Configure Apache to serve from /public and allow .htaccess
RUN sed -ri -e 's!/var/www/html!/var/www/html/public!g' /etc/apache2/sites-available/000-default.conf /etc/apache2/apache2.conf \
    && sed -ri -e 's/AllowOverride None/AllowOverride All/g' /etc/apache2/apache2.conf \
    && sed -ri -e 's/^ServerTokens .*/ServerTokens Prod/' /etc/apache2/conf-available/security.conf \
    && sed -ri -e 's/^ServerSignature .*/ServerSignature Off/' /etc/apache2/conf-available/security.conf \
    && printf "<Directory /var/www/html>\n    Options -Indexes\n</Directory>\n" > /etc/apache2/conf-available/hardening.conf \
    && printf "Header always set X-Content-Type-Options \"nosniff\"\nHeader always set X-Frame-Options \"SAMEORIGIN\"\nHeader always set Referrer-Policy \"no-referrer-when-downgrade\"\n" > /etc/apache2/conf-available/security-headers.conf \
    && a2enconf hardening security-headers

# Copy application source
COPY . .

# Bring in Composer vendor deps built in previous stage
COPY --from=vendor /app/vendor ./vendor

# Bring in built frontend assets
COPY --from=frontend /app/public/build ./public/build

# Ensure storage and cache are writable
RUN chown -R www-data:www-data storage bootstrap/cache \
    && chmod -R ug+rwx storage bootstrap/cache

# PHP production settings and Opcache
RUN { \
      echo 'expose_php=0'; \
      echo 'display_errors=0'; \
      echo 'log_errors=1'; \
      echo 'memory_limit=256M'; \
      echo 'post_max_size=16M'; \
      echo 'upload_max_filesize=16M'; \
      echo 'opcache.enable=1'; \
      echo 'opcache.enable_cli=1'; \
      echo 'opcache.validate_timestamps=0'; \
      echo 'opcache.jit_buffer_size=0'; \
    } > /usr/local/etc/php/conf.d/zzz-production.ini

# Entry script to adjust port and warm caches at runtime
COPY docker/entrypoint.sh /usr/local/bin/app-entrypoint
RUN chmod +x /usr/local/bin/app-entrypoint

# Default command (Render will set PORT; entrypoint adjusts Apache to use it)
ENTRYPOINT ["/usr/local/bin/app-entrypoint"]
CMD ["apache2-foreground"]


