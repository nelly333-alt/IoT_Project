const row = msg.payload;

// Validate required EMS fields.
const required = [
    "timestamp",
    "site",
    "building",
    "asset_id",
    "asset_type",
    "parameter",
    "value",
    "unit",
    "source"
];

for (const field of required) {
    if (
        row[field] === undefined ||
        row[field] === null ||
        row[field] === ""
    ) {
        node.error(`Missing field: ${field}`, msg);
        return null;
    }
}

if (
    typeof row.value !== "number" ||
    !Number.isFinite(row.value)
) {
    node.error("Measurement value must be numeric.", msg);
    return null;
}

// Prepare values for the PostgreSQL query.
msg.params = [
    row.timestamp,
    row.site,
    row.building,
    row.asset_id,
    row.asset_type,
    row.parameter,
    row.value,
    row.unit,
    row.source
];

return msg;