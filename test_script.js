msg.query = `
    INSERT INTO sensor_data (sensor,value, unit)
    VALUES ($1, $2, $3)
`;

msg.params = [
    msg.payload.sensor,
    msg.payload.value,
    msg.payload.unit
];

return msg;