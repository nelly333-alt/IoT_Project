
-- EMS DATABASE

CREATE EXTENSION IF NOT EXISTS timescaledb; 

-- Granualiteit (13 maanden)
CREATE TABLE IF NOT EXISTS ems_measurements (
	timestamp   TIMESTAMPZ   NOT NULL, 
	site        TEXT         NOT NULL, 
	building    TEXT         NOT NULL, 
	asset_id    TEXT         NOT NULL, 
	asset_type  TEXT         NOT NULL, 
	parameter   TEXT         NOT NULL, 
	value       DOUBLE PRECISION, 
	value_text  TEXT, 
	unit        TEXT         NOT NULL,
	source      TEXT         NOT NULL, 
	inserted_at TEXT         NOT NULL DEFAULT now(), 
	CONSTRAINT ems_value_present CHECK (value IS NOT NULL OR value_text IS NOT NULL)
); 

SELECT create_hypertable ('ems_measurements', 'timestamp', 
	chunk_time_interval => INTERVAL '7 days', if_not_exists => TRUE); 

CREATE UNIQUE INDEX IF NOT EXISTS ems_measurements_uq
    ON ems_measurements (asset_id, parameter, timestamp); 
CREATE INDEX IF NOT EXISTS ems_measurements_site_idx
    ON ems_measurements (site, building, timestamp DESC); 
CREATE INDEX IF NOT EXISTS ems_measurements_inserted_idx
    ON ems_measurements (inserted_at);

-- Hourly aggregate
CREATE MATERIALIZED VIEW IF NOT EXISTS ems_hourly
WITH (timescaledb.continous) AS
SELECT time_bucket(INTERVAL '1 hour', timestamp) AS bucket,
       site, building, asset_id, asset_type, parameter, unit, source, 
       avg(value)              AS avg_value, 
       min(value)              AS min_value, 
       max(value)              AS max_value,
       first(value, timestamp) AS first_val, 
       last(value, timestamp)  AS last_val,
       count(*)                AS n_samples
FROM ems_measurements
WHERE value IS NOT NULL
GROUP BY bucket, site, building, asset_id, asset_type, parameter, unit, source
WITH NO DATA; 

SELECT add_continous_aggregate_policy('ems_hourly', 
     start_offset      => INTERVAL '3 hours', 
     end_offset        => INTERVAL '1 hour', 
     schedule_interval => INTERVAL '30 minutes', 
     if_not_exists     => TRUE); 

-- Monthly aggregate
CREATE MATERIALIZED VIEW IF NOT EXISTS ems_monthly
WITH (timescaledb_continuous) AS
SELECT time_bucket(INTERVAL '1 month', timestamp) AS bucket, 
       site, building, asset_id, asset_type, parameter, unit, source, 
       avg(value)               AS avg_value, 
       min(value)               AS min_value, 
       max (value)              AS max_value, 
       first(value, timestamp)  AS first_val, 
       last(value, timestamp)   AS last_val, 
       count(*)                 AS n_samples
FROM ems_measurements
WHERE value IS NOT NULL
GROUP BY bucket, site, building, asset_id, asset_type, parameter, unit, source
WITH NO DATA; 

SELECT add_continuous_aggregate_policy ('ems_monthly', 
    start_offset      => INTERVAL '3 months', 
    end_offset        => INTERVAL '1 hour', 
    schedule_interval => INTERVAL '1 day', 
    if_not_exists     => TRUE); 

-- Compression and retention
ALTER TABLE ems_measurements SET (
	timescaledb.compress, 
	timescaledb.compress_segmentby = 'asset_id, parameter', 
	timescaledn.compress_orderby = 'timestamp DESC'
); 
SELECT add_compression_policy('ems_measurements', INTERVAL '7 days', if_not_exists => TRUE); 

-- Raw + hourly: 13 months
SELECT add_retention_policy('ems_measurements', INTERVAL '13 months', if_not_exists => TRUE); 
SELECT add_retention_policy('ems_hourly'        INTERVAL '13 months', if_not_exists => TRUE); 

-- Reference Data
-- Needed for EUI and benchmarking
CREATE TABLE IF NOT EXISTS ems_buildings (
	site             TEXT NOT NULL, 
	building         TEXT NOT NULL, 
	floor_area_m2    DOUBLE PRECISION, 
	heating_power_kw DOUBLE PRECISION, 
	PRIMARY KEY (site, building)
); 

-- Asset registry
CREATE TABLE IF NOT EXISTS ems_assets (
	asset_id                  TEXT PRIMARY KEY, 
	site                      TEXT NOT NULL, 
        building                  TEXT NOT NULL, 
	asset_type                TEXT NOT NULL, 
	energy_carrier            TEXT, 
	expected_inteval_minutes  INT NOT NULL DEFAULT 60,
        source                    TEXT, 
        CONSTRAINT ems_assets_interval_chk CHECK (
	    expected_interval_minutes > 0 AND
             (energy_carrier IS NULL OR
              expected_interval_minutes <= CASE WHEN energy_carrier = 'electriciteit' THEN 15 ELSE 60 END))	
);

-- index counters
CREATE TABLE IF NOT EXISTS ems_counter_parameters (
	parameter       TEXT PRIMARY KEY, 
	energy_carrier  TEXT NOT NULL
); 

INSERT INTO ems_counter_parameters VALUES
   ('Electriciteitsverbruik', 'electriciteit'),
   ('Gasverbruik',            'gas'),
   ('Waterverbruik',          'water')
ON CONFLICT DO NOTHING; 

-- Power BI
CREATE TABLE IF NOT EXISTS ems_budgets (
	site            TEXT NOT NULL, 
	building        TEXT NOT NULL, 
	energy_carrier  TEXT NOT NULL, 
	year            INT NOT NULL, 
	budget          DOUBLE PRECISION NOT NULL, 
	unit            TEXT NOT NULL, 
	PRIMARY KEY (site, building, energy_carrier, year)
);

-- alarm thresholds
CREATE TABLE IF NOT EXISTS ems_alarms_rules (
	id           SERIAL PRIMARY KEY, 
	asset_id     TEXT NOT NULL, 
	parameters   TEXT NOT NULL, 
	time_from    TIME, 
	time_to      TIME, 
	min_value    DOUBLE PRECISION, 
	max_value    DOUBLE PRECISION, 
	description  TEXT
); 

-- Reporting views Grafana/ Power BI

CREATE OR REPLACE VIEW ems_consumption_monthly AS
SELECT x.bucket AS month, x.site, x.building, x.asset_id, x.parameter, x.unit, x.energy_carrier, 
        CASE WHEN x.last_val >= COALESCE(x.prev_last, x.first_val)
		THEN x.last_val - COALESCE(x.prev_last, x.first_val) END AS consumption

FROM  (SELECT m.*, lag(m.last_val) OVER (PARTITION BY m.asset_id, m_parameter ORDER BY m.bucket) AS prev_last FROM ems_monthly m) x

JOIN ems_counter _parameters p ON p.parameter = x.parameter; 

-- Yearly consumption and EUI per building
CREATE OR REPLACE VIEW ems_eui_yearly AS
SELECT date_trunc('year', c.month) AS year, c.site, c.building, c.energy_carrier, 
       sum(c.consumption)          AS consumption_Kwh, 
       b.floor_area_m2, 
       sum(c.consumption) / NULLIF(b.floor_area_m2, 0) AS kwh_per_m2
FROM ems_consumption_monthly c
LEFT JOIN ems_buildings b ON b.site = c.site AND b.building = c.building
WHERE c.unit = 'KWh'
GROUB BY 1, 2, 3, 4, b.floor_area_m2; 

-- Connectivity / granularity check
CREATE OR REPLACE VIEW ems_asset_status AS
SELECT a.asset_id, a.site, a.building, a.asset_type, a.energy_carrier, 
       a.expected_interval_minutes, l.last_seen, 
       (l.last_seen IS NULL
         OR now() - l.last_seen > a.expected_interval_minutes * 3 * INTERVAL '1 minute') AS offline
FROM ems_assets a
LEFT JOIN LATERAL (
	SELECT max(m.timestamp) AS last_seen
	FROM ems_measurements m
	WHERE m.asset_id = a.asset_id AND m.timestamp > now () - INTERVAL '7 days'
) 1 ON TRUE;
