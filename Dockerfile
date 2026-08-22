FROM nextcloud:33.0.6-apache

RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*

COPY apache.conf /etc/apache2/sites-available/nextcloud.conf

RUN a2enmod ssl headers rewrite \
    && a2dissite 000-default \
    && a2ensite nextcloud
