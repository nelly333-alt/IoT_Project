
#!/bin/bash
# Simulates a ChirpStack v4 uplink so you can test Node-RED -> TimescaleDB without hardware.
# Usage: ./send-test-uplink.sh <mqtt_host> [temperature] [humidity] [co2]
HOST=${1:-localhost}
TEMP=${2:-21.5}
HUM=${3:-48}
CO2=${4:-650}
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

mosquitto_pub -h "$HOST" -t "application/1/device/0102030405060708/event/up" -m "{
  \"time\": \"$NOW\",
  \"deviceInfo\": {
    \"devEui\": \"0102030405060708\",
    \"tags\": { \"site\": \"Site X\", \"building\": \"Vergaderzaal 2\", \"asset_type\": \"Comfortsensor\" }
  },
  \"object\": { \"temperature\": $TEMP, \"humidity\": $HUM, \"co2\": $CO2 }
}"
echo "sent uplink at $NOW"
