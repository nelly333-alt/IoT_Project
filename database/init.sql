CREATE TABLE sensor_date(
    id serial PRIMARY KEY,
    sensor VARCHAR(100),
    value NUMERIC,
    unit VARCHAR(20)
)