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
    local mode=""
    local number_processes=$(nproc)

    # When running for the first time we want to create the tables,
    # next times we just want to append data
    if test "$create" = "true"; then
        _log "Creating osm database"
        mode="--create"
    else
        _log "Updating osm database"
        mode="--append"
    fi

    # Limit to 8 to prevent overwhelming pg with connections
    if test $number_processes -ge 8; then
        number_processes=8
    fi

    opts=""
    test -n "$DB_HOST" && opts="$opts -H $DB_HOST"
    test -n "$DB_USER" && opts="$opts -U $DB_USER"
    test -n "$DB_NAME" && opts="$opts -d $DB_NAME"

    _log "Connection options: $opts"

    export PGPASS=$DB_PASS
    osm2pgsql $mode -C $OSM_IMPORT_CACHE \
              --number-processes $number_processes --hstore \
              $opts --slim "$import_file"
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
    local import_file=$1
    local url="$BASE_URL/${OSM_MAP}-latest.osm.pbf"
    local output="$OSM_DATA/osm_data.pbf"

    if test -z $import_file; then
        _log "Downloading osm data file from $url"
        if which axel &>/dev/null; then
            axel -n5 -o "$output" "$url"
        else
            wget -O "$output" "$url" 
        fi
    fi

    if grep -q '\.pbf$' <<< "$import_file"; then
        # This step is supposed to make the process faster, but this assumption
        # might not be true for all cases.
        # TODO: check whether this is useful or not.
        _log "Converting file $import_file to o5m format"
        osmconvert --out-o5m "$import_file" -o="$CURRENT_OSM_DATA"
        # Original .pdf data is no longer necessary
        rm $output
    elif test "$import_file" != $(basename "$CURRENT_OSM_DATA"); then
        _log "Copying $import_file to $CURRENT_OSM_DATA"
        cp "$import_file" "$CURRENT_OSM_DATA"
    fi

    _run_osm2pgsql $CURRENT_OSM_DATA "true"
}

update() {
    # TODO: allow import file for update
    local update_file=$1
    local url="$BASE_URL/${OSM_MAP}-updates/"
    local chanset_file="$OSM_DATA/chanset_file.o5c"

    if test -n "$update_file"; then
        _die "Update is not yet allowed with a given file"
    fi

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
    echo -e "-f\t Import file. If you already have the map file, pass it on." 
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
DB_HOST=""
DB_USER=$USER
DB_NAME="gis"
OSM_MAP="south-america/brazil"
OSM_DATA="$(dirname $(realpath "$0"))"
OSM_IMPORT_CACHE=2048
ACTION="import"
IMPORT_FILE=""

##
# PARSER COMMAND LINE ARGUMENTS
#

while getopts ":c:o:p:U:d:w:m:hH:a:f:" opt; do
    case "$opt" in
        a)
            ACTION=$OPTARG
            ;;
        p)
            DB_PORT=$OPTARG
            ;;
        f)
            IMPORT_FILE=$OPTARG
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

if test -n "$IMPORT_FILE" -a ! -f "$IMPORT_FILE"; then
    _die "File $IMPORT_FILE was not found"
fi
    
##
# Just.. DO IT!!
#
if test "$ACTION" = "import"; then
    import $IMPORT_FILE
elif test "$ACTION" = "update"; then
    update $IMPORT_FILE
else
    echo "Unrecognized action $ACTION"
    help
fi
