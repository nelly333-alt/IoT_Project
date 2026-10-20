CREATE EXTENSION IF NOT EXISTS timescaledb;

CREATE TABLE IF NOT EXISTS ems_measurements (
    tijdstip  TIMESTAMPTZ NOT NULL,
    site TEXT NOT NULL,
    ruimte TEXT NOT NULL,
    asset_id TEXT NOT NULL,
    asset_type TEXT NOT NULL,
    paramaters TEXT NOT NULL,
    waarde NUMERIC NOT NULL,
    eenheid TEXT NOT NULL,
    bron TEXT NOT NULL
);