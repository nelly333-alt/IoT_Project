// Node-RED function node: ChirpStack v4 uplink event (MQTT) -> rows in the EMS data format.
// Needs on the device in ChirpStack: tags site / building / asset_type, and a codec
// that returns the decoded values in "object" (see configuration/chirpstack/codec-esp32.js).
const m = msg.payload;
if (!m || !m.deviceInfo) {
    node.warn('Not a ChirpStack uplink event');
    return null;
}
const tags = m.deviceInfo.tags || {};
const obj  = m.object || {};
const UNITS = { temperature: '°C', humidity: '%', co2: 'ppm', power: 'W',
                energy: 'kWh', voltage: 'V', current: 'A' };
const ts = m.time || new Date().toISOString();

const rows = [];
for (const [param, val] of Object.entries(obj)) {
    let value = null, text = null;
    if (typeof val === 'number' && isFinite(val)) value = val;
    else if (typeof val === 'boolean') value = val ? 1 : 0;
    else if (typeof val === 'string') text = val;
    else continue;
    rows.push({
        timestamp:  ts,
        site:       tags.site       || 'unknown',
        building:   tags.building   || 'unknown',
        asset_id:   m.deviceInfo.devEui,
        asset_type: tags.asset_type || 'sensor',
        parameter:  param,
        value:      value,
        value_text: text,
        unit:       UNITS[param] || (text !== null ? 'Tekst' : 'n/a'),
        source:     'LoRaWAN'
    });
}
if (rows.length === 0) return null;
msg.payload = rows;
return msg;
