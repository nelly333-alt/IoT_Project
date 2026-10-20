CREATE TABLE IF NOT EXISTS ems_measurements.public(
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

