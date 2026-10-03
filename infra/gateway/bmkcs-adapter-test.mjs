import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createServer } from "node:http";
import { publishBmkcsResult, toBmaQualityEvent } from "./bmkcs-adapter.mjs";

const legacy = {
  id: "BMKCS-SYNTHETIC-001",
  lot: "BO-1109-1020-P-D-BM",
  ts: "2026-09-11T03:20:00+07:00",
  pd: "2026-09-11",
  prod: "BO",
  op: "P",
  qc: "D",
  cust: "BM",
  ph: 5.8,
  w: 93.4,
  m: 12.4,
  v: 18.6,
  x: null,
  station: "BMKCSLAB-001",
};

const mapped = toBmaQualityEvent(legacy);
assert.equal(mapped.event_id, legacy.id);
assert.equal(mapped.event_type, "QUALITY_RESULT_PUBLISHED");
assert.equal(mapped.source_system, "BMKCS");
assert.equal(mapped.source_device_id, legacy.station);
assert.equal(mapped.occurred_at, "2026-09-10T20:20:00.000Z");
assert.equal(mapped.payload.result_id, legacy.id);
assert.equal(mapped.payload.lot_code, legacy.lot);
assert.equal(mapped.payload.production_date, legacy.pd);
assert.equal(mapped.payload.viscosity, legacy.v);
assert.equal(mapped.payload.fineness, null);
assert.equal(
  mapped.payload_hash,
  createHash("sha256").update(JSON.stringify(mapped.payload)).digest("hex"),
);

let received;
const gateway = createServer(async (request, response) => {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  received = {
    headers: request.headers,
    body: JSON.parse(Buffer.concat(chunks).toString("utf8")),
  };
  response.writeHead(202, { "content-type": "application/json" });
  response.end('{"status":"ACCEPTED"}');
});
await new Promise((resolve) => gateway.listen(0, "127.0.0.1", resolve));

try {
  const port = gateway.address().port;
  const result = await publishBmkcsResult(legacy, {
    bmaUrl: `http://127.0.0.1:${port}/api/v1/integrations/events`,
    bmaGatewayKey: "synthetic-key",
    allowInsecureLocalBma: true,
  });
  assert.equal(result.status, 202);
  assert.equal(received.headers["x-bma-gateway-key"], "synthetic-key");
  assert.equal(received.headers["idempotency-key"], legacy.id);
  assert.deepEqual(received.body, mapped);

  assert.throws(() => toBmaQualityEvent({ ...legacy, ph: "not-a-number" }), /BMKCS_PH_INVALID/);
  console.log("PASS: BMKCS legacy payload -> canonical BMA synthetic publish.");
} finally {
  await new Promise((resolve) => gateway.close(resolve));
}
