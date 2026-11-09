CREATE EXTENSION IF NOT EXISTS timescaledb;

CREATE TABLE IF NOT EXISTS ems_measurements (
    timestamp   TIMESTAMPTZ      NOT NULL,
    site        TEXT             NOT NULL,
    building    TEXT             NOT NULL,
    asset_id    TEXT             NOT NULL,
    asset_type  TEXT             NOT NULL,
    parameter   TEXT             NOT NULL,
    value       DOUBLE PRECISION NOT NULL,
    unit        TEXT             NOT NULL,
    source      TEXT             NOT NULL
);

SELECT create_hypertable('ems_measurements', 'timestamp', if_not_exists => TRUE);

CREATE UNIQUE INDEX IF NOT EXISTS ems_measurements_uq
    ON ems_measurements (asset_id, parameter, timestamp);

CREATE MATERIALIZED VIEW IF NOT EXISTS ems_hourly
WITH (timescaledb.continuous) AS
SELECT time_bucket(INTERVAL '1 hour', timestamp) AS bucket,
       site, building, asset_id, asset_type, parameter, unit, source,
       avg(value)              AS avg_value,
       min(value)              AS min_value,
       max(value)              AS max_value,
       first(value, timestamp) AS first_val,
       last(value, timestamp)  AS last_val,
       count(*)                AS n_samples
FROM ems_measurements
GROUP BY bucket, site, building, asset_id, asset_type, parameter, unit, source
WITH NO DATA;

SELECT add_continuous_aggregate_policy('ems_hourly',
    start_offset      => INTERVAL '3 hours',
    end_offset        => INTERVAL '1 hour',
    schedule_interval => INTERVAL '30 minutes',
    if_not_exists     => TRUE);

CREATE MATERIALIZED VIEW IF NOT EXISTS ems_monthly
WITH (timescaledb.continuous) AS
SELECT time_bucket(INTERVAL '1 month', timestamp) AS bucket,
       site, building, asset_id, asset_type, parameter, unit, source,
       avg(value)              AS avg_value,
       min(value)              AS min_value,
       max(value)              AS max_value,
       first(value, timestamp) AS first_val,
       last(value, timestamp)  AS last_val,
       count(*)                AS n_samples
FROM ems_measurements
GROUP BY bucket, site, building, asset_id, asset_type, parameter, unit, source
WITH NO DATA;

SELECT add_continuous_aggregate_policy('ems_monthly',
    start_offset      => INTERVAL '3 months',
    end_offset        => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 day',
    if_not_exists     => TRUE);

ALTER TABLE ems_measurements SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'asset_id, parameter',
    timescaledb.compress_orderby   = 'timestamp DESC'
);
SELECT add_compression_policy('ems_measurements', INTERVAL '7 days', if_not_exists => TRUE);

SELECT add_retention_policy('ems_measurements', INTERVAL '13 months', if_not_exists => TRUE);
