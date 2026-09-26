import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { toCanonicalEvent, valueAt } from "./canonical.mjs";

const event = {
  event_id: "3fdba5a3-c9b4-40f7-a4f4-e4b4cf7b44da",
  sequence: 9,
  received_at: "2026-09-07T07:00:00.000Z",
  query_string: "",
  content_type: "application/json",
  body: Buffer.from(JSON.stringify({
    data: {
      personId: "1605063-001",
      capturedAt: "2026-09-07T13:59:58+07:00",
      confidence: 0.98,
    },
  })),
};

const canonical = await toCanonicalEvent(event, {
  deviceId: "1605063",
  personField: "body.data.personId",
  occurredAtField: "body.data.capturedAt",
  confidenceField: "body.data.confidence",
  employeeMap: new Map([["1605063-001", "BM-001"]]),
});

assert.equal(valueAt({ body: { personId: "P-1" } }, "body.personId"), "P-1");
assert.equal(canonical.event_type, "EMPLOYEE_SCAN");
assert.equal(canonical.source_system, "FACE_TERMINAL");
assert.equal(canonical.source_device_id, "1605063");
assert.equal(canonical.sequence, 9);
assert.equal(canonical.occurred_at, "2026-09-07T06:59:58.000Z");
assert.equal(canonical.payload.employee_id, "BM-001");
assert.equal(canonical.payload.confidence, 0.98);
assert.equal(
  canonical.payload_hash,
  createHash("sha256").update(JSON.stringify(canonical.payload)).digest("hex"),
);

await assert.rejects(
  () => toCanonicalEvent(event, {
    deviceId: "1605063",
    personField: "body.data.personId",
    occurredAtField: "",
    confidenceField: "",
    employeeMap: new Map(),
  }),
  /PERSON_NOT_MAPPED/,
);

console.log("PASS: canonical attendance payload, UTC, hash và mapping.");
