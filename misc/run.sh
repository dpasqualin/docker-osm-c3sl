#!/bin/bash

# Copyright (C) 2015 Centro de Computacao Cientifica e Software Livre
# Departamento de Informatica - Universidade Federal do Parana - C3SL/UFPR
#
# This file is part of docker-osm-c3sl
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301,
# USA.

# This is a helper to import and update osm data to a database.

set -e

##
# Run OpenStreetMap tile server operations
#

# Print a message and exit
_die () {
    _log_error "$@"
    exit
}

# Echo a message to standard output
_log () {
    local msg="$@"
    echo $(date): $msg
}

# Echo an error message to stderr
_log_error () {
    local msg="$@"
    _log "ERROR: $msg" 1>&2
}

_startservice () {
    _log "Starting service $1"
    sv start $1 || _die "Could not start $1"
}

_run_osm2pgsql () {
    local import_file=$1
    local create=$2
    local opts=""
    local number_processes=$(nproc)

    # When running for the first time we want to create the tables,
    # next times we just want to append data
    if test "$create" = "true"; then
        _log "Creating osm database"
        opts="--create"
    else
        _log "Updating osm database"
        opts="--append"
    fi

    # Limit to 8 to prevent overwhelming pg with connections
    if test $number_processes -ge 8; then
        number_processes=8
    fi

    export PGPASS=$DB_PASS
    osm2pgsql $opts -C $OSM_IMPORT_CACHE \
              --number-processes $number_processes --hstore \
              -d $DB_NAME -H $DB_HOST -U $DB_USER \
              --slim "$import_file"
} 

# TODO: Needs testing
createdb () {
    local dbname=$1
    local dbuser=$2
    _log "Creating database $dbname for user $dbuser"

    # Create the database
    setuser postgres createdb -O $dbuser $dbname

    # Install the Postgis schema
    $asweb psql -d $dbname -f /usr/share/postgresql/9.3/contrib/postgis-2.1/postgis.sql || true
    # Add the Spatial Reference System
    $asweb psql -d $dbname -f /usr/share/postgresql/9.3/contrib/postgis-2.1/spatial_ref_sys.sql || true

    $asweb psql -d $dbname -c 'CREATE EXTENSION HSTORE;'

    # Set the correct table ownership
    $asweb psql -d $dbname -c "ALTER TABLE geometry_columns OWNER TO \"$dbuser\"; ALTER TABLE spatial_ref_sys OWNER TO \"$dbuser\";"
}

import () {
    local url="$BASE_URL/${OSM_MAP}-latest.osm.pbf"
    local output="$OSM_DATA/osm_data.pbf"

    _log "Downloading osm data file from $url"
    if which axel &>/dev/null; then
        axel -n5 -o "$output" "$url"
    else
        wget -O "$output" "$url" 
    fi

    # This step is supposed to make the process faster, but this assumption
    # might not be true for all cases.
    # TODO: check whether this is useful or not.
    _log "Converting file $output to o5m format"
    osmconvert --out-o5m "$output" -o="$CURRENT_OSM_DATA"
    chmod 744 "$CURRENT_OSM_DATA" # make sure www-data can read this file

    # Original .pdf data is no longer necessary
    rm $output

    _run_osm2pgsql $CURRENT_OSM_DATA "true"
}

update() {
    local url="$BASE_URL/${OSM_MAP}-updates/"
    local chanset_file="$OSM_DATA/chanset_file.o5c"

    _log "Downloading osm update and generating chanset file"
    osmupdate -v --base-url=$url "$CURRENT_OSM_DATA" "$chanset_file"
    _run_osm2pgsql $chanset_file
    rm $chanset_file
}

dropdb () {
    echo "Dropping database"
    cd /var/www
    setuser postgres dropdb $DB_NAME
}

help () {
    echo "$0 -H <db_host> -U <db_user> -w <db_password> -p <db_port> -m <osm_map> -o <osm_import_cache> -a <action>"
    echo ""
    echo -e "-a\t The action to be taken. Use 'import' when importing data for the first time and 'update' when updating"
    echo -e "-m\t A link just after http://download.geofabrik.de, example: south-america/brazil"
    echo -e "-H\t Database host"
    echo -e "-U\t Database username. Defaults to the user running the script"
    echo -e "-w\t Database password"
    echo -e "-d\t Database name. Defaults to gis"
    echo -e "-p\t Database port. Defaults to 5432"
    echo -e "-o\t Directory used to store downloaded osm data, defaults to the script dir"
    echo -e "-c\t Cache used to import data from open streetmap to the database"
    echo -e "-h\t Print help message"

    exit 1
}

##
# GLOBAL VARS
#
BASE_URL="http://download.geofabrik.de"
DB_PORT=5432
DB_USER=$USER
DB_NAME="gis"
OSM_MAP="south-america/brazil"
OSM_DATA="$(dirname $(realpath "$0"))"
OSM_IMPORT_CACHE=2048
ACTION="import"

##
# PARSER COMMAND LINE ARGUMENTS
#

while getopts ":c:o:p:U:d:w:m:hH:a:" opt; do
    case "$opt" in
        a)
            ACTION=$OPTARG
            ;;
        p)
            DB_PORT=$OPTARG
            ;;
        U)
            DB_USER=$OPTARG
            ;;
        d)
            DB_NAME=$OPTARG
            ;;
        w)
            DB_PASSWORD=$OPTARG
            ;;
        m)
            OSM_MAP=$OPTARG
            ;;
        H)
            DB_HOST=$OPTARG
            ;;
        o)
            OSM_DATA=$OPTARG
            ;;
        c)
            OSM_IMPORT_CACHE=$OPTARG
            ;;
        h)
            help
            ;;
        \?)
            echo "Invalid option: -$OPTARG"
            help
            ;;
        :)
            echo "Option -$OPTARG requires an argument."
            help
            ;;
        *)
            help
            ;;
    esac
done
shift $((OPTIND-1))

CURRENT_OSM_DATA="$OSM_DATA/current_osm_data.o5m"

##
# Argument sanity check
#

# OSM_DATA must be a valid directory
if test -z "${OSM_DATA}"; then
    _die "OSM_DATA environment variable not set: expected a valid directory"
elif ! test -d "${OSM_DATA}" || ! mkdir -p "${OSM_DATA}"; then
    _die "Unable to create OSM_DATA directory: ${OSM_DATA}"
fi

# OSM_IMPORT_CACHE must be an integer
if ! echo "$OSM_IMPORT_CACHE" | grep -qP '^[0-9]+$'; then
    _die "Unexpected cache type: expected an integer but found: ${OSM_IMPORT_CACHE}"
fi

# DBPORT must be an integer
if ! echo "$DB_PORT" | grep -qP '^[0-9]+$'; then
    _die "Unexpected database port: expected an integer but found: $DB_PORT"
fi

##
# Just.. DO IT!!
#
if test "$ACTION" = "import"; then
    import
elif test "$ACTION" = "update"; then
    update
else
    echo "Unrecognized action $ACTION"
    help
fi
