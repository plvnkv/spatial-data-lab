#!/bin/sh
set -eu

export PGPASSWORD="$POSTGRES_PASSWORD"
psql --host db --username postgres --dbname postgres --set ON_ERROR_STOP=1 \
  --set catalog_password="$GEONODE_DATABASE_PASSWORD" \
  --set spatial_password="$GEONODE_GEODATABASE_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE geonode LOGIN PASSWORD %L', :'catalog_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'geonode') \gexec
SELECT format('CREATE ROLE geonode_data LOGIN PASSWORD %L', :'spatial_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'geonode_data') \gexec
SELECT 'CREATE DATABASE geonode OWNER geonode'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'geonode') \gexec
SELECT 'CREATE DATABASE geonode_data OWNER geonode_data'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'geonode_data') \gexec
\connect geonode
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS hstore;
\connect geonode_data
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS hstore;
SQL
