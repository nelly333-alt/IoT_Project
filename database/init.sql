CREATE TABLE IF NOT EXISTS ems_measurements (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    timestamp TIMESTAMP NOT NULL,
    site TEXT NOT NULL,
    building TEXT NOT NULL,
    asset_id TEXT NOT NULL,
    asset_type TEXT NOT NULL,
    parameter TEXT NOT NULL,
    value NUMERIC NOT NULL,
    unit TEXT NOT NULL,
    source TEXT NOT NULL,

    CONSTRAINT ems_measurements_unique
        UNIQUE (timestamp, site, asset_id, parameter)
);

INSERT INTO ems_measurements (
    timestamp,
    site,
    building,
    asset_id,
    asset_type,
    parameter,
    value,
    unit,
    source

)
VALUES (
           '2026-01-15 10:15:00',
           'Site X',
           'Gebouw A',
           'ELEC-001',
           'Energiemeter',
           'Elektriciteitsverbruik',
           1256.4,
           'kWh',
           'Johnson Controls'
        )
ON CONFLICT (timestamp, site, asset_id, parameter)
DO NOTHING;

SELECT
    timestamp,
    site,
    building,
    asset_id,
    asset_type,
    parameter,
    value,
    unit,
    source
FROM ems_measurements
ORDER BY timestamp, asset_id, parameter;