
# Fabric: TimescaleDB -> Warehouse -> Power BI

TimescaleDB blijft de bron van waarheid (business case: één centrale databron). Fabric
leest daaruit via een Data pipeline met een gateway; er wordt niets vanuit Node-RED naar
Fabric gestuurd.

| Tabel in TimescaleDB | Kopie naar Fabric     |             Methode                       |
|       ---            |      ---              |               ---                         |
| `ems_measurements`   |      ja               | incrementeel op `inserted_at` (watermark) |
| `ems_monthly`        |      ja               | volledige herlaad (klein)                 |
| `ems_assets`, `ems_buildings`, `ems_budgets` | ja | volledige herlaad (klein)            |

Op 13 maanden worden ruwe data in TimescaleDB verwijderd; wat in Fabric staat blijft
bewaard. Samen met `ems_monthly` (nooit verwijderd) dekt dit de 5 jaar uit de business case.

## 1. Voorwaarden
- On-premises data gateway op een machine die de VM bereikt (poort 5433).
- Fabric-connectie "TimescaleDB EMS" (PostgreSQL) via die gateway, gebruiker `fabric_reader`
  (enkel SELECT, wachtwoord `FABRIC_DB_PASSWORD` uit `.env`).
- Een Fabric Warehouse, bv. `wh_ems`.

## 2. Eenmalig uitvoeren in de Warehouse (T-SQL)
```sql
CREATE TABLE dbo.ems_measurements (
    [timestamp] datetime2(6) NOT NULL, site varchar(100) NOT NULL, building varchar(100) NOT NULL,
    asset_id varchar(100) NOT NULL, asset_type varchar(100) NOT NULL, parameter varchar(100) NOT NULL,
    value float NULL, value_text varchar(200) NULL, unit varchar(20) NOT NULL,
    source varchar(100) NOT NULL, inserted_at datetime2(6) NOT NULL
);
CREATE TABLE dbo.ems_monthly (
    bucket datetime2(6) NOT NULL, site varchar(100), building varchar(100), asset_id varchar(100),
    asset_type varchar(100), parameter varchar(100), unit varchar(20), source varchar(100),
    avg_value float, min_value float, max_value float, first_val float, last_val float, n_samples bigint
);
CREATE TABLE dbo.ems_assets (
    asset_id varchar(100) NOT NULL, site varchar(100), building varchar(100), asset_type varchar(100),
    energy_carrier varchar(50), expected_interval_minutes int, source varchar(100)
);
CREATE TABLE dbo.ems_buildings (
    site varchar(100) NOT NULL, building varchar(100) NOT NULL, floor_area_m2 float, heating_power_kw float
);
CREATE TABLE dbo.ems_budgets (
    site varchar(100), building varchar(100), energy_carrier varchar(50), year int, budget float, unit varchar(20)
);
CREATE TABLE dbo.etl_watermark (table_name varchar(100) NOT NULL, last_ts datetime2(6) NOT NULL);
INSERT INTO dbo.etl_watermark VALUES ('ems_measurements', '1900-01-01');
```
Alle tijden zijn UTC (de containers draaien met `TZ=UTC`).

## 3. Pipeline `pl_ems_incremental` (trigger: elke 15 minuten)

**a) Lookup `Get old watermark`** (bron: Warehouse, first row only)
```sql
SELECT CONVERT(varchar(30), last_ts, 121) AS last_ts
FROM dbo.etl_watermark WHERE table_name = 'ems_measurements'
```

**b) Lookup `Get new watermark`** (bron: PostgreSQL, first row only). De minuut marge voorkomt
dat rijen van nog lopende transacties gemist worden.
```sql
SELECT to_char(date_trunc('second', now() - interval '1 minute') AT TIME ZONE 'UTC',
               'YYYY-MM-DD HH24:MI:SS') AS new_ts
```

**c) Copy `Copy measurements`** (bron: PostgreSQL, bestemming: `dbo.ems_measurements`, append)
```sql
SELECT timestamp, site, building, asset_id, asset_type, parameter,
       value, value_text, unit, source, inserted_at
FROM ems_measurements
WHERE inserted_at >  '@{activity('Get old watermark').output.firstRow.last_ts}+00'
  AND inserted_at <= '@{activity('Get new watermark').output.firstRow.new_ts}+00'
```

**d) Script `Update watermark`** (Warehouse, enkel na succes van c)
```sql
UPDATE dbo.etl_watermark
SET last_ts = '@{activity('Get new watermark').output.firstRow.new_ts}'
WHERE table_name = 'ems_measurements'
```

**e) Kleine tabellen** (`ems_monthly`, `ems_assets`, `ems_buildings`, `ems_budgets`): per tabel
een Copy-activiteit met bron `SELECT * FROM <tabel>` en als pre-copy script in de Warehouse
`TRUNCATE TABLE dbo.<tabel>` (volledige herlaad).

## 4. Power BI
Verbind Power BI met de Warehouse. Verbruik per maand en EUI (kWh/m²) staan in TimescaleDB als
views `ems_consumption_monthly` en `ems_eui_yearly`; in Power BI reken je hetzelfde uit op
`ems_monthly` + `ems_buildings` (of kopieer de views met dezelfde methode als e).
