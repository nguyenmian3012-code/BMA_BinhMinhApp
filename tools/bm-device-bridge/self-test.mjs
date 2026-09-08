import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";

const testDirectory = mkdtempSync(join(tmpdir(), "bm-device-bridge-"));
const databasePath = join(testDirectory, "bridge.sqlite");
const employeeMapPath = join(testDirectory, "employee-map.json");
const bridgePort = 18789;
let childOutput = "";
const receivedByGateway = [];

writeFileSync(employeeMapPath, JSON.stringify({
  terminal_person_to_employee: { "TEST-001": "BM-TEST-001" },
}));

const gateway = createServer(async (request, response) => {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  receivedByGateway.push({
    headers: request.headers,
    body: JSON.parse(Buffer.concat(chunks).toString("utf8")),
  });
  response.writeHead(202, { "content-type": "application/json" });
  response.end('{"status":"ACCEPTED"}');
});
await new Promise((resolve) => gateway.listen(0, "127.0.0.1", resolve));
const gatewayPort = gateway.address().port;

const child = spawn(process.execPath, [fileURLToPath(new URL("bridge.mjs", import.meta.url))], {
  env: {
    ...process.env,
    BM_BRIDGE_HOST: "127.0.0.1",
    BM_BRIDGE_PORT: String(bridgePort),
    BM_DB_PATH: databasePath,
    BM_TERMINAL_IP: "192.168.1.227",
    BM_GATEWAY_URL: `http://127.0.0.1:${gatewayPort}/api/v1/integrations/events`,
    BM_GATEWAY_KEY: "test-gateway-key",
    BM_PERSON_FIELD: "body.personId",
    BM_OCCURRED_AT_FIELD: "body.occurredAt",
    BM_DEDUPE_SECONDS: "120",
    BM_EMPLOYEE_MAP_PATH: employeeMapPath,
    BM_ALLOW_INSECURE_LOCAL_GATEWAY: "1",
  },
  stdio: ["ignore", "pipe", "pipe"],
});
child.stdout.on("data", (chunk) => { childOutput += chunk; });
child.stderr.on("data", (chunk) => { childOutput += chunk; });

async function waitUntil(check, message) {
  for (let attempt = 0; attempt < 60; attempt += 1) {
    try {
      if (await check()) return;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error(`${message}\n${childOutput}`);
}

try {
  await waitUntil(async () => {
    const response = await fetch(`http://127.0.0.1:${bridgePort}/health`);
    return response.ok;
  }, "Bridge không khởi động trong thời gian chờ");

  const heartbeat = await fetch(`http://127.0.0.1:${bridgePort}/Subscribe/heartbeat`, {
    method: "POST",
    body: JSON.stringify({ deviceId: "1605063", status: "online" }),
    headers: { "content-type": "application/json" },
  });
  assert.equal(heartbeat.status, 200);
  assert.equal(await heartbeat.text(), "OK");

  const attendance = await fetch(`http://127.0.0.1:${bridgePort}/Subscribe/verify`, {
    method: "POST",
    body: JSON.stringify({
      deviceId: "1605063",
      personId: "TEST-001",
      occurredAt: "2026-09-08T00:00:00Z",
    }),
    headers: { "content-type": "application/json" },
  });
  assert.equal(attendance.status, 200);
  await waitUntil(() => receivedByGateway.length === 1, "Gateway không nhận canonical event");

  const canonical = receivedByGateway[0].body;
  assert.equal(receivedByGateway[0].headers["x-bma-gateway-key"], "test-gateway-key");
  assert.equal(receivedByGateway[0].headers["idempotency-key"], canonical.event_id);
  assert.equal(canonical.event_type, "EMPLOYEE_SCAN");
  assert.equal(canonical.source_system, "FACE_TERMINAL");
  assert.equal(canonical.source_device_id, "1605063");
  assert.equal(canonical.payload.employee_id, "BM-TEST-001");
  assert.equal(canonical.payload.verification_method, "FACE_TERMINAL");
  assert.equal(
    canonical.payload_hash,
    createHash("sha256").update(JSON.stringify(canonical.payload)).digest("hex"),
  );

  await waitUntil(async () => {
    const health = await fetch(`http://127.0.0.1:${bridgePort}/health`).then((response) => response.json());
    return health.sent === 1;
  }, "Bridge chưa đánh dấu sự kiện đã gửi");

  const diagnostics = await fetch(
    `http://127.0.0.1:${bridgePort}/diagnostics/recent?limit=1`,
  ).then((response) => response.json());
  assert.equal(diagnostics.items.length, 1);
  assert.match(diagnostics.items[0].bodyUtf8Preview, /TEST-001/);

  const duplicateEvent = await fetch(`http://127.0.0.1:${bridgePort}/Subscribe/verify`, {
    method: "POST",
    body: JSON.stringify({
      deviceId: "1605063",
      personId: "TEST-001",
      occurredAt: "2026-09-08T00:01:00Z",
    }),
    headers: { "content-type": "application/json" },
  });
  assert.equal(duplicateEvent.status, 200);
  await waitUntil(async () => {
    const health = await fetch(`http://127.0.0.1:${bridgePort}/health`).then((response) => response.json());
    return health.deduplicated === 1;
  }, "Callback lap chua duoc deduplicate");
  assert.equal(receivedByGateway.length, 1);

  const laterEvent = await fetch(`http://127.0.0.1:${bridgePort}/Subscribe/verify`, {
    method: "POST",
    body: JSON.stringify({
      deviceId: "1605063",
      personId: "TEST-001",
      occurredAt: "2026-09-08T00:02:01Z",
    }),
    headers: { "content-type": "application/json" },
  });
  assert.equal(laterEvent.status, 200);
  await waitUntil(() => receivedByGateway.length === 2, "Event ngoai cua so debounce khong duoc gui");

  const blockedEvent = await fetch(`http://127.0.0.1:${bridgePort}/Subscribe/verify`, {
    method: "POST",
    body: JSON.stringify({ deviceId: "1605063", personId: "UNKNOWN" }),
    headers: { "content-type": "application/json" },
  });
  assert.equal(blockedEvent.status, 200);
  await waitUntil(async () => {
    const health = await fetch(`http://127.0.0.1:${bridgePort}/health`).then((response) => response.json());
    return health.blocked === 1;
  }, "Sự kiện chưa map không được chuyển sang blocked");

  const health = await fetch(`http://127.0.0.1:${bridgePort}/health`).then((response) => response.json());
  assert.equal(health.version, "0.3.0");
  assert.equal(health.direction, "AUTO");
  assert.equal(health.mode, "forwarding-staging");
  assert.equal(health.received, 5);
  assert.equal(health.sent, 2);
  assert.equal(health.deduplicated, 1);
  assert.equal(health.blocked, 1);
  assert.equal(health.pending, 0);
  assert.ok(health.lastHeartbeatAt);

  const db = new DatabaseSync(databasePath, { readOnly: true });
  const stored = db.prepare("SELECT COUNT(*) AS count FROM raw_events").get();
  assert.equal(Number(stored.count), 5);
  db.close();
  console.log("PASS: raw-first, canonical BMA, idempotency, mapping và quarantine hoạt động.");
} finally {
  if (child.exitCode === null) {
    const exited = new Promise((resolve) => child.once("exit", resolve));
    child.kill("SIGTERM");
    await exited;
  }
  await new Promise((resolve) => gateway.close(resolve));
  rmSync(testDirectory, { recursive: true, force: true });
}
