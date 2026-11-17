
Beste optie om alle services in een plaats te bewaren is deze commando op jouw localhost runnen:



notepad $env:USERPROFILE\.ssh\config
   -> in de config file!!!
        |
        |
        |
  Host smartbuilding
      HostName 10.160.10.2
      User root
      IdentityFile ~/.ssh/id_ed25519
      ServerAliveInterval 30
      ExitOnForwardFailure yes

      LocalForward 5050 localhost:5050       # pgAdmin
      LocalForward 3000 localhost:3000       # Grafana
      LocalForward 1880 localhost:1880       # Node-RED
      LocalForward 8080 localhost:8080       # ChirpStack
      LocalForward 5433 localhost:5433       # PostgreSQL (DBeaver / psql)
      LocalForward 1883 localhost:1883       # MQTT (optional)

En daarna gewoon smartbuilding activeren door:
  ssh -N smartbuilding (op localhost run)

Login

Chirpstack
  username:Admin
  Password:Admin

Grafana
   username: admin
   password: smartbuildings
      PostgreSQL connective met Grafana
        name:ems-postgres
        host url: ems-postgres:5432
        Database: smartbuildings
        user:admin
        password:admin
        TLS/SSL:disable
       TimescaleDB:on

pgAdmin4
  email: smartbuildings@gmail.com
  password: pgadmin4
    smartbuildings database connectie
       Host: postgres
       Port:5432
       maintenance database: smartbuildings
       username: admin
       password: admin

login smartbuildings database:
docker exec -it ems-postgres psql -U admin -d smartbuildings

\dt -> list tables
\dm -> Continuous aggregates
\dx -> Timescaledb




