# docker-osm-c3sl

A basic image for rendering/serving tiles using OpenStreetMap data from an external
PostgreSQL instance.

## Build instructions

Build using

    # docker build -t dpasqualin/docker-osm-c3sl github.com/dpasqualin/docker-osm-c3sl

## Creating a database

There is a file called run.sh inside misc directory that is not part of the
docker container. This file can help you create and set up a database with
osm data in it, as well as helping you to keep this database updated.

It doesn't cover all scenarios, but it can be helpful.

## Running

This document assumes that OpenStreetMap data has already been imported in an external database.

    # docker run -i -t --name osm -p 8080:80 -e PG_DB=<dbname> -e PG_HOST=<dbhost> -e PG_PASS=<dbpassword> -e PG_USER=<dbuser> dpasqualin/docker-osm-c3sl

Once the container is up you should be able to see a map of the
world once you point your browser to [http://127.0.0.1:8080](http://127.0.0.1:8080)

Notice in the top right corner a menu where you can select between available styles.

## Available Styles

 * [openstreetmap-carto](https://github.com/gravitystorm/openstreetmap-carto),
   available at [http://host/osm/0/0/0.png](http://host/osm/0/0/0.png)
 * [osm-bright](https://github.com/mapbox/osm-bright)
   available at [http://host/osmb/0/0/0.png](http://host/osmb/0/0/0.png)

## Use our instance

There is (or should be) a running instance of this container at
[http://openstreetmap.c3sl.ufpr.br]. Currently only Brazil is available, but
feel free to use it on your application.

## About

This Dockerfile is based on [mguentner/docker-renderd-osm](https://github.com/mguentner/docker-renderd-osm).
