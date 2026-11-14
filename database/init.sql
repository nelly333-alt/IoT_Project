-- =====================================================
-- EMS DATABASE
-- Energiebeheersysteem (Energy Management System)
-- PostgreSQL + TimescaleDB
-- Bron van waarheid voor Grafana en MS Fabric (-> Power BI)
-- =====================================================

CREATE EXTENSION IF NOT EXISTS timescaledb;

-- =====================================================
-- REFERENTIETABELLEN
-- =====================================================

CREATE TABLE IF NOT EXISTS ems_energy_carriers (
    code TEXT PRIMARY KEY
);

INSERT INTO ems_energy_carriers (code)
VALUES
    ('elektriciteit'),
    ('gas'),
    ('water'),
    ('warmte'),
    ('koeling')
ON CONFLICT DO NOTHING;

-- =====================================================
-- GEBOUWEN
-- =====================================================

CREATE TABLE IF NOT EXISTS ems_buildings (
    site              TEXT NOT NULL,
    building          TEXT NOT NULL,
    floor_area_m2     DOUBLE PRECISION,
    heating_power_kw  DOUBLE PRECISION,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (site, building)
);

-- =====================================================
-- ASSETREGISTER
-- Legt per asset het vereiste uitleesinterval vast
-- (elektriciteit max. 15 min, andere energiemeters max. 60 min).
-- ems_measurements heeft bewust GEEN foreign key naar deze tabel:
-- metingen van niet-geregistreerde toestellen moeten toch opgeslagen worden.
-- =====================================================

CREATE TABLE IF NOT EXISTS ems_assets (
    asset_id                   TEXT PRIMARY KEY,
    site                       TEXT NOT NULL,
    building                   TEXT NOT NULL,
    asset_type                 TEXT NOT NULL,
    energy_carrier             TEXT,
    expected_interval_minutes  INT NOT NULL DEFAULT 60,
    source                     TEXT,
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fk_asset_building
        FOREIGN KEY (site, building)
        REFERENCES ems_buildings(site, building),

    CONSTRAINT fk_energy_carrier
        FOREIGN KEY (energy_carrier)
        REFERENCES ems_energy_carriers(code),

    CONSTRAINT ems_assets_interval_chk
        CHECK (
            expected_interval_minutes > 0
            AND (
                energy_carrier IS NULL
                OR expected_interval_minutes <=
                    CASE
                        WHEN energy_carrier = 'elektriciteit'
                        THEN 15
                        ELSE 60
                    END
            )
        )
);

-- =====================================================
-- RUWE METINGEN (13 maanden bewaard)
-- =====================================================

CREATE TABLE IF NOT EXISTS ems_measurements (
    timestamp     TIMESTAMPTZ NOT NULL,
    site          TEXT NOT NULL,
    building      TEXT NOT NULL,
    asset_id      TEXT NOT NULL,
    asset_type    TEXT NOT NULL,
    parameter     TEXT NOT NULL,

    value         DOUBLE PRECISION,        -- numerieke metingen
    value_text    TEXT,                    -- statuswaarden, bv. 'Laden' (eenheid 'Tekst')

    unit          TEXT NOT NULL,
    source        TEXT NOT NULL,

    inserted_at   TIMESTAMPTZ NOT NULL DEFAULT now(),   -- laadtijd: watermark voor de Fabric-kopie

    -- precies één van value / value_text
    CONSTRAINT ems_single_value_chk
        CHECK (
            (value IS NOT NULL AND value_text IS NULL)
            OR
            (value IS NULL AND value_text IS NOT NULL)
        )
);

-- =====================================================
-- HYPERTABLE
-- =====================================================

SELECT create_hypertable(
    'ems_measurements',
    'timestamp',
    chunk_time_interval => INTERVAL '7 days',
    if_not_exists => TRUE
);

-- =====================================================
-- INDEXEN
-- =====================================================

CREATE UNIQUE INDEX IF NOT EXISTS ems_measurements_uq
ON ems_measurements (
    asset_id,
    parameter,
    timestamp
);

CREATE INDEX IF NOT EXISTS ems_measurements_site_idx
ON ems_measurements (
    site,
    building,
    timestamp DESC
);

CREATE INDEX IF NOT EXISTS ems_measurements_inserted_idx
ON ems_measurements (
    inserted_at
);

CREATE INDEX IF NOT EXISTS ems_measurements_asset_time_idx
ON ems_measurements (
    asset_id,
    timestamp DESC
);

-- =====================================================
-- UURLIJKSE CONTINUOUS AGGREGATE (enkel numerieke waarden)
-- =====================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS ems_hourly
WITH (timescaledb.continuous) AS

SELECT
    time_bucket(
        INTERVAL '1 hour',
        timestamp
    ) AS bucket,

    site,
    building,
    asset_id,
    asset_type,
    parameter,
    unit,
    source,

    avg(value)              AS avg_value,
    min(value)              AS min_value,
    max(value)              AS max_value,

    first(value, timestamp) AS first_val,
    last(value, timestamp)  AS last_val,

    count(*)                AS n_samples

FROM ems_measurements

WHERE value IS NOT NULL

GROUP BY
    bucket,
    site,
    building,
    asset_id,
    asset_type,
    parameter,
    unit,
    source

WITH NO DATA;

SELECT add_continuous_aggregate_policy(
    'ems_hourly',
    start_offset      => INTERVAL '3 hours',
    end_offset        => INTERVAL '1 hour',
    schedule_interval => INTERVAL '30 minutes',
    if_not_exists     => TRUE
);

-- =====================================================
-- MAANDELIJKSE CONTINUOUS AGGREGATE
-- Onbeperkt bewaard (business case: minstens 5 jaar)
-- =====================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS ems_monthly
WITH (timescaledb.continuous) AS

SELECT
    time_bucket(
        INTERVAL '1 month',
        timestamp
    ) AS bucket,

    site,
    building,
    asset_id,
    asset_type,
    parameter,
    unit,
    source,

    avg(value)              AS avg_value,
    min(value)              AS min_value,
    max(value)              AS max_value,

    first(value, timestamp) AS first_val,
    last(value, timestamp)  AS last_val,

    count(*)                AS n_samples

FROM ems_measurements

WHERE value IS NOT NULL

GROUP BY
    bucket,
    site,
    building,
    asset_id,
    asset_type,
    parameter,
    unit,
    source

WITH NO DATA;

-- start_offset moet ruim onder de retention van de ruwe data (13 maanden) blijven,
-- anders worden ruwe data verwijderd voordat ze geaggregeerd zijn.
SELECT add_continuous_aggregate_policy(
    'ems_monthly',
    start_offset      => INTERVAL '3 months',
    end_offset        => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 day',
    if_not_exists     => TRUE
);

-- =====================================================
-- COMPRESSIE
-- =====================================================

ALTER TABLE ems_measurements
SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'asset_id,parameter',
    timescaledb.compress_orderby = 'timestamp DESC'
);

SELECT add_compression_policy(
    'ems_measurements',
    INTERVAL '7 days',
    if_not_exists => TRUE
);

-- =====================================================
-- RETENTION (BEWAARTERMIJN)
-- Ruwe en uurlijkse data: 13 maanden.
-- ems_monthly heeft bewust GEEN retention policy (minstens 5 jaar vereist).
-- =====================================================

SELECT add_retention_policy(
    'ems_measurements',
    INTERVAL '13 months',
    if_not_exists => TRUE
);

SELECT add_retention_policy(
    'ems_hourly',
    INTERVAL '13 months',
    if_not_exists => TRUE
);

-- =====================================================
-- TELLERDEFINITIES (cumulatieve meterstanden)
-- =====================================================

CREATE TABLE IF NOT EXISTS ems_counter_parameters (
    parameter       TEXT PRIMARY KEY,
    energy_carrier  TEXT NOT NULL
        REFERENCES ems_energy_carriers(code)
);

INSERT INTO ems_counter_parameters
(parameter, energy_carrier)
VALUES
    ('Elektriciteitsverbruik', 'elektriciteit'),
    ('Gasverbruik', 'gas'),
    ('Waterverbruik', 'water')
ON CONFLICT DO NOTHING;

-- =====================================================
-- BUDGETTEN
-- =====================================================

CREATE TABLE IF NOT EXISTS ems_budgets (
    site            TEXT NOT NULL,
    building        TEXT NOT NULL,
    energy_carrier  TEXT NOT NULL,
    year            INT NOT NULL,
    budget          DOUBLE PRECISION NOT NULL,
    unit            TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (
        site,
        building,
        energy_carrier,
        year
    ),

    FOREIGN KEY (energy_carrier)
        REFERENCES ems_energy_carriers(code),

    FOREIGN KEY (site, building)
        REFERENCES ems_buildings(site, building)
);

-- =====================================================
-- ALARMREGELS (tijds- en/of gebruiksgebonden drempels per meter)
-- =====================================================

CREATE TABLE IF NOT EXISTS ems_alarm_rules (
    id           SERIAL PRIMARY KEY,

    asset_id     TEXT NOT NULL,
    parameter    TEXT NOT NULL,

    time_from    TIME,          -- NULL = hele dag
    time_to      TIME,

    min_value    DOUBLE PRECISION,
    max_value    DOUBLE PRECISION,

    description  TEXT,

    CONSTRAINT fk_alarm_asset
        FOREIGN KEY (asset_id)
        REFERENCES ems_assets(asset_id)
        ON DELETE CASCADE,

    CONSTRAINT ems_alarm_limits_chk
        CHECK (
            min_value IS NULL
            OR max_value IS NULL
            OR min_value <= max_value
        )
);

-- =====================================================
-- VIEW MAANDVERBRUIK
-- Laatste stand van de maand min laatste stand van de vorige maand.
-- Negatieve waarden (meter vervangen/gereset) -> NULL.
-- =====================================================

CREATE OR REPLACE VIEW ems_consumption_monthly AS

SELECT
    x.bucket AS month,
    x.site,
    x.building,
    x.asset_id,
    x.parameter,
    x.unit,

    p.energy_carrier,

    CASE
        WHEN x.last_val >= COALESCE(x.prev_last, x.first_val)
        THEN x.last_val - COALESCE(x.prev_last, x.first_val)
    END AS consumption

FROM (

    SELECT
        m.*,

        lag(m.last_val)
        OVER (
            PARTITION BY
                m.asset_id,
                m.parameter
            ORDER BY m.bucket
        ) AS prev_last

    FROM ems_monthly m

) x

JOIN ems_counter_parameters p
    ON p.parameter = x.parameter;

-- =====================================================
-- VIEW EUI (kWh/m2 per gebouw, vergelijking jaar op jaar)
-- =====================================================

CREATE OR REPLACE VIEW ems_eui_yearly AS

SELECT
    date_trunc('year', c.month) AS year,
    c.site,
    c.building,
    c.energy_carrier,

    sum(c.consumption) AS consumption_kwh,

    b.floor_area_m2,

    sum(c.consumption)
        / NULLIF(b.floor_area_m2, 0)
        AS kwh_per_m2

FROM ems_consumption_monthly c

LEFT JOIN ems_buildings b
    ON b.site = c.site
   AND b.building = c.building

WHERE c.unit = 'kWh'

GROUP BY
    1,
    2,
    3,
    4,
    b.floor_area_m2;

-- =====================================================
-- CONNECTIVITEITSSTATUS VAN ASSETS
-- offline = niets ontvangen gedurende 3 verwachte intervallen
-- =====================================================

CREATE OR REPLACE VIEW ems_asset_status AS

SELECT
    a.asset_id,
    a.site,
    a.building,
    a.asset_type,
    a.energy_carrier,

    a.expected_interval_minutes,

    l.last_seen,

    (
        l.last_seen IS NULL
        OR
        now() - l.last_seen >
        (
            a.expected_interval_minutes
            * 3
            * INTERVAL '1 minute'
        )
    ) AS offline

FROM ems_assets a

LEFT JOIN LATERAL (

    SELECT
        max(m.timestamp) AS last_seen

    FROM ems_measurements m

    WHERE m.asset_id = a.asset_id
      AND m.timestamp > now() - INTERVAL '7 days'

) l ON TRUE;

-- =====================================================
-- OPTIONEEL: voorbeeldgebouwen en -assets uit de PDF
-- (haal de commentaar weg om te proberen; voeg je echte ChirpStack DevEUI op dezelfde manier toe)
-- =====================================================

INSERT INTO ems_buildings (site, building) VALUES
    ('Site X','Gebouw A'), ('Site X','Vergaderzaal 2'),
    ('Site X','Buitenomgeving'), ('Site X','Parking')
ON CONFLICT DO NOTHING;

INSERT INTO ems_assets (asset_id, site, building, asset_type, energy_carrier, expected_interval_minutes, source) VALUES
    ('ELEC001',  'Site X','Gebouw A',       'Energiemeter', 'elektriciteit', 15, 'Johnson Controls'),
    ('COMF101',  'Site X','Vergaderzaal 2', 'Comfortsensor', NULL,           15, 'LoRaWAN'),
    ('PEIL-001', 'Site X','Buitenomgeving', 'Peilbuis',      NULL,           60, 'LoRaWAN'),
    ('EV-023',   'Site X','Parking',        'Laadpaal',      NULL,           15, 'Laadpaalbeheer')
ON CONFLICT DO NOTHING;

-- =====================================================
-- OPTIONEEL: aggregaten handmatig verversen (bv. na het importeren van oude data)
-- =====================================================

-- CALL refresh_continuous_aggregate('ems_hourly',  now() - INTERVAL '30 days', now());
-- CALL refresh_continuous_aggregate('ems_monthly', now() - INTERVAL '1 year',  now());
