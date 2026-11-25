# The Quran Journey — PHP web app.
# Build from the quran-journey/ folder (it needs app/assets/db/quran.db):
#   docker build -f web/Dockerfile -t quran-journey-web .
#   docker run -p 8080:80 -v qj-web-data:/var/www/web/data quran-journey-web
FROM php:8.3-apache
RUN a2enmod rewrite headers \
 && sed -ri 's#DocumentRoot /var/www/html#DocumentRoot /var/www/web/public#' /etc/apache2/sites-available/000-default.conf \
 && printf '<Directory /var/www/web/public>\n  AllowOverride All\n  Require all granted\n</Directory>\nServerTokens Prod\nServerSignature Off\n' > /etc/apache2/conf-enabled/qj.conf
COPY web /var/www/web
COPY app/assets/db/quran.db /var/www/app/assets/db/quran.db
COPY app/assets/content/groupings.json /var/www/app/assets/content/groupings.json
RUN mkdir -p /var/www/web/data && chown www-data:www-data /var/www/web/data && chmod 700 /var/www/web/data
VOLUME /var/www/web/data
