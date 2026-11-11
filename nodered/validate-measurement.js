// Node-RED function node (2 outputs): validation before the INSERT in PostgreSQL.
// Input : msg.payload = array of rows in the EMS data format (see README, table ems_measurements)
// Output 1: valid rows, as JSON text in msg.params[0] (for the postgresql node)
// Output 2: rejected rows with the reason(s), for the debug sidebar
const REQUIRED = ['timestamp', 'site', 'building', 'asset_id', 'asset_type', 'parameter', 'unit', 'source'];
const rows = Array.isArray(msg.payload) ? msg.payload : [msg.payload];
const now = Date.now();
const valid = [];
const rejected = [];

for (const r of rows) {
    if (!r || typeof r !== 'object') {
        rejected.push({ row: r, reasons: ['not an object'] });
        continue;
    }
    const reasons = [];
    for (const f of REQUIRED) {
        if (typeof r[f] !== 'string' || r[f].trim() === '') reasons.push('missing ' + f);
    }
    const hasNum = r.value !== null && r.value !== undefined;
    const hasTxt = typeof r.value_text === 'string' && r.value_text !== '';
    if (hasNum && (typeof r.value !== 'number' || !isFinite(r.value))) reasons.push('value is not a finite number');
    if (!hasNum && !hasTxt) reasons.push('no value or value_text');
    const t = Date.parse(r.timestamp);
    if (isNaN(t)) reasons.push('invalid timestamp');
    else if (t > now + 5 * 60 * 1000) reasons.push('timestamp in the future');

    if (reasons.length) {
        rejected.push({ row: r, reasons: reasons });
    } else {
        valid.push({
            timestamp:  r.timestamp,
            site:       r.site.trim(),
            building:   r.building.trim(),
            asset_id:   r.asset_id.trim(),
            asset_type: r.asset_type.trim(),
            parameter:  r.parameter.trim(),
            value:      hasNum ? r.value : null,
            value_text: hasTxt ? r.value_text : null,
            unit:       r.unit.trim(),
            source:     r.source.trim()
        });
    }
}
node.status({ fill: rejected.length ? 'yellow' : 'green', shape: 'dot',
              text: valid.length + ' ok / ' + rejected.length + ' rejected' });

msg.params = [JSON.stringify(valid)];
return [valid.length ? msg : null,
        rejected.length ? { payload: rejected } : null];
