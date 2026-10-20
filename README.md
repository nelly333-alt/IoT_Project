# Smart Building - Provincie Antwerpen

PoC en architectuur voor een schaalbare dataketen voor slim gebouwbeheer van DLOG in samenwerking met DICT.
Sensor en metadata verzameld, opgeslagen, gevisualiseerd en gerapporteerd, met het oog op EPBD/BACS-conformiteit.

## Doel

- Een architectuur uitwerken die als **Standaard** in meerdere gebouwen kan worden uitgerold.
- Die architectuur vertalen naar een werkende **PoC** met de bestaande LoRaWAN-gateway en sensoren.
- Alle data in een uniform dataformat opslaan, zodat Grafana en Power BI dezelfde bron gebruiken.

## Architectuur
 ´´´mermaid
 flowchart LR
     subgraph Sensoren
        ESP[ESP32<br/>CO2, temperatuur, <br/>vochtigheid, beweging]
        LS[LoRa-sensoren<br/>temperatuur, CO2,beweging]
     end
    
     ESP -- LoRa RF --> GW[LoRaWAN-gateway]
     LS -- LoRa RF --> GW
     GW -- LoRaWAN --> TTN[The Things Network]
     TTN -- MQTT --> NR[Node-RED]
 
     NR --> DB[(PostgreSQL)]
     DB --> GRA[Grafana <br/> real-time, alarmen]
     DB --> FAB[(MS Fabric)]
     FAB --> PBI[Power BI <br/>management-rapportage]

    subgraph Uitbreiding["Uitbreiding (buiten PoC)"]
        LP[Laadpaal <br/>kWh, kW] -- OCPP --> LPP[Laadpaalplatform]
        EM[Energiemeter <br/>kWh, V, A] -- Modbus --> SIE[Siemens]
        AUT[Bijsturing / automatisering] 
    end
    
    LPP -. API .-> NR
    SIE -. API .-> NR
    NR -.-> AUT
 ´´´

### Datastroom in het kort

1. **Sensoren** sturen hun meetwaarden via LoRa naar de LoRaWAN-gateway.
2. De gateway stuurt de data door naar **The Things Network (TTN)**, dat de LoRaWAN-berichten beheert.
3. **Node-RED** ontvangt de data van TTN via MQTT, decodeert en valideert ze en zet ze om naar het gemeenschappelijke dataformaat.
4. **PostgreSQL** slaat de metingen op als buffer voor real-time gebruik en tijdreeksen.
5. **Grafana** leest uit PostgreSQL voor operationele dashboards en alarmen.
6. **MS Fabric** is het centrale warehouse; **Power BI** maakt daarop de management en EPBD-rapporten.

### Waarom PostgreSQL en MS Fabric
PostgreSQL is het meestt geschikt voor transactioenele opslag, real-time buffering en efficiente verwerking van tijdreeksgegevens op edge-niveau.
Microsoft Fabric blinkt uit in enterprise-analytics, BI-rapportage en de orkestratie van big data.
Elk heeft zijn eigen voordelen, daarol gebruiken we ze allebei.

### Scope van de PoC
| Onderdeel | Status |
|--- |---| 
|LoRa-sensoren en ESP32 -> gateway -> TTN -> Node-RED -> PostgreSQL -> Grafana -> | PoC |
|PostgreSQL -> Ms Fabric -> Power BI | PoC (afhankelijk van toegang tot de Fabric-testomgeving)|
|Laadpalen (OCPP)| Uitbreiding|
| Siemens / Johnson Controls/ E-Sight-koppelingen| Door DICT, 2026-2027|
| Bijsturing/automatisering| Toekomstige toepassing|

## Dataformaat

Alle bronnen worden naar hetzelfde formaat omgezet (tabel `ems_measurements`):

| Veld | Omschrijving |
|---|---|
| `timestamp` | Datum en tijd van de meting |
| `site` | Locatie of campus |
| `building` | Gebouw of ruimte |
| `asset_id` | Unieke identificatie van de sensor of meter |
| `asset_type` | Type installatie of sensor |
| `parameter` | Wat er gemeten wordt |
| `value` | Meetwaarde |
| `unit` | Eenheid (kWh, kW, °C, ppm, %, ...) |
| `source` | Herkomst (LoRaWAN, Johnson Controls, E-Sight, ...) |

Bewaartermijn volgens de business case: minstens 5 jaar, de eerste 13 maanden op de oorspronkelijke granulariteit (elektriciteit kwartaaluur, andere meters uur), daarna maandelijks geaggregeerd.

## De stack opstarten

Vereisten: Docker Desktop en Git.

```bash
git clone https://github.com/nelly333-alt/IoT_Project.git
cd IoT_Project
cp .env.example .env        # Windows PowerShell: Copy-Item .env.example .env
# vul daarna de echte waarden in .env in
docker compose up -d
docker compose ps
```

| Dienst | Adres |
|---|---|
| Node-RED | http://localhost:1880 |
| Grafana | http://localhost:3000 |
| PostgreSQL | `localhost:5433` (binnen Docker: host `postgres`, poort `5432`) |

Het script `database/init.sql` wordt automatisch uitgevoerd bij de eerste start. Wil je de database volledig resetten, gebruik dan `docker compose down -v` (verwijdert alle data).

## Mappenstructuur

```
.
├── database/        # SQL-schema (init.sql)
├── nodered/         # Node-RED-flows en voorbeelddata
├── fabric/          # Notities over de MS Fabric-koppeling
├── docker-compose.yml
├── .env.example     # Voorbeeld van de benodigde variabelen
└── README.md
```

## Team

| Naam | Rol |
|---|---|
| [Kelvin] | [bv. hardware/firmware ESP32] |
| [Nelly] | [bv. Node-RED en database] |
| [Samuel] | [bv. Grafana en alerting] |
| [Jesse-James] | [bv. Fabric en Power BI] |