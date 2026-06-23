# Use the official PHP image with Apache.
# PHP 8.2 (PHP 7.4 is end-of-life and receives no security fixes).
FROM php:8.2-apache
EXPOSE 80
# Install necessary PHP extensions
RUN apt-get update && apt-get install -y \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    zlib1g-dev \
    libzip-dev \
    zip \
    unzip \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd \
    && docker-php-ext-install pdo pdo_mysql \
    && docker-php-ext-install zip \
    && a2enmod rewrite \
    && rm -rf /var/lib/apt/lists/*

# copy contents into directory
COPY . /var/www/html

# Activate the shipped firewall/rewrite rules (.htaccess_firewall) and allow
# .htaccess overrides so they take effect. The installer keeps working because
# install/.htaccess re-grants its scripts and install/_guard.php blocks re-runs.
RUN if [ -f /var/www/html/.htaccess_firewall ] && [ ! -f /var/www/html/.htaccess ]; then \
        cp /var/www/html/.htaccess_firewall /var/www/html/.htaccess; \
    fi \
    && sed -ri 's!AllowOverride None!AllowOverride All!g' /etc/apache2/apache2.conf

# Set appropriate permissions
RUN chown -R www-data:www-data /var/www/html
RUN chmod -R 755 /var/www/html

# Set working directory
WORKDIR /var/www/html
