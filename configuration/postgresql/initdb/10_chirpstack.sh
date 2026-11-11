#!/bin/bash
# ChirpStack gets its own database and role (it must not share the EMS database).
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
CREATE ROLE chirpstack WITH LOGIN PASSWORD '${CHIRPSTACK_DB_PASSWORD}';
CREATE DATABASE chirpstack WITH OWNER chirpstack;
EOSQL
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname chirpstack <<EOSQL
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS hstore;
EOSQL
