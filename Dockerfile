FROM mguentner/renderd-osm

# Database related envinronment variables
ENV PG_DB gis
ENV PG_USER www-data
ENV PG_HOST localhost
ENV PG_PORT 5432
ENV PG_PASS change_password

# Set up apache2 front-end map
RUN mkdir -p /var/www
RUN chmod 755 /var/www
ADD index.html /var/www/index.html
RUN chmod 744 /var/www/index.html

# Set up apache2 config for the front-end to work
RUN mkdir -p /etc/apache2/sites-available
ADD openstreetmap.conf /etc/apache2/sites-available/000-default.conf

COPY ./renderd/run  /etc/service/renderd/run
RUN chown root:root /etc/service/renderd/run
RUN chmod u+x       /etc/service/renderd/run
