#!/bin/bash
# Least-privilege roles. Runs once, after the schema, on the first start with an empty volume.
# Passwords are passed as psql variables and quoted with format(%L), so special characters are safe.
set -euo pipefail
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
     -v nodered_pw="$NODERED_DB_PASSWORD" -v grafana_pw="$GRAFANA_DB_PASSWORD" -v fabric_pw="$FABRIC_DB_PASSWORD" <<'EOSQL'
SELECT format('CREATE ROLE nodered_writer LOGIN PASSWORD %L', :'nodered_pw') \gexec
SELECT format('CREATE ROLE grafana_reader LOGIN PASSWORD %L', :'grafana_pw') \gexec
SELECT format('CREATE ROLE fabric_reader  LOGIN PASSWORD %L', :'fabric_pw')  \gexec

GRANT USAGE ON SCHEMA public TO nodered_writer, grafana_reader, fabric_reader;

-- Node-RED may only add measurements (SELECT is needed for ON CONFLICT DO NOTHING)
GRANT SELECT, INSERT ON ems_measurements TO nodered_writer;

-- Grafana and Fabric are read-only (tables, continuous aggregates and views)
GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana_reader, fabric_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO grafana_reader, fabric_reader;
EOSQL

