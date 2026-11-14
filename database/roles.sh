#!/bin/bash
# Least-privilege roles. Runs once, after the schema, on the first start with an empty volume.
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
CREATE ROLE nodered_writer LOGIN PASSWORD '${NODERED_DB_PASSWORD}';
CREATE ROLE grafana_reader LOGIN PASSWORD '${GRAFANA_DB_PASSWORD}';
CREATE ROLE fabric_reader  LOGIN PASSWORD '${FABRIC_DB_PASSWORD}';

-- Node-RED may only add measurements
GRANT SELECT, INSERT ON ems_measurements TO nodered_writer;

-- Grafana and Fabric are read-only (tables, continuous aggregates and views)
GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana_reader, fabric_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO grafana_reader, fabric_reader;
EOSQL
