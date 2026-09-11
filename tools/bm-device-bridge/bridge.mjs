import { createHash, randomUUID } from "node:crypto";
import { mkdirSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, resolve } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { loadEmployeeMap, parseTerminalData, toCanonicalEvent } from "./canonical.mjs";

const host = process.env.BM_BRIDGE_HOST || "0.0.0.0";
const port = Number(process.env.BM_BRIDGE_PORT || 8789);
const deviceId = process.env.BM_DEVICE_ID || "1605063";
const databasePath = resolve(process.env.BM_DB_PATH || "data/bm-device-bridge.sqlite");
const gatewayUrl = (process.env.BM_GATEWAY_URL || "").trim();
const gatewayKey = (process.env.BM_GATEWAY_KEY || "").trim();
const personField = (process.env.BM_PERSON_FIELD || "").trim();
const occurredAtField = (process.env.BM_OCCURRED_AT_FIELD || "").trim();
const confidenceField = (process.env.BM_CONFIDENCE_FIELD || "").trim();
const employeeMapPath = (process.env.BM_EMPLOYEE_MAP_PATH || "").trim();
const dedupeSeconds = Number(process.env.BM_DEDUPE_SECONDS || 120);
const rawRetentionDays = Number(process.env.BM_RAW_RETENTION_DAYS || 30);
const replayShadow = process.env.BM_FORWARD_REPLAY === "1";
const allowInsecureLocalGateway = process.env.BM_ALLOW_INSECURE_LOCAL_GATEWAY === "1";
const allowedIps = new Set(
  (process.env.BM_TERMINAL_IP || "192.168.1.227")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean),
);
const maxBodyBytes = 2 * 1024 * 1024;

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error("BM_BRIDGE_PORT phải nằm trong khoảng 1-65535");
}
if (!Number.isInteger(dedupeSeconds) || dedupeSeconds < 0 || dedupeSeconds > 3600) {
  throw new Error("BM_DEDUPE_SECONDS phải nằm trong khoảng 0-3600");
}
if (!Number.isInteger(rawRetentionDays) || rawRetentionDays < 1 || rawRetentionDays > 3650) {
  throw new Error("BM_RAW_RETENTION_DAYS phải nằm trong khoảng 1-3650");
}

let forwarding = null;
if (gatewayUrl) {
  const parsedGateway = new URL(gatewayUrl);
  const localHttp = parsedGateway.protocol === "http:" &&
    ["127.0.0.1", "localhost", "::1"].includes(parsedGateway.hostname) &&
    allowInsecureLocalGateway;
  if (parsedGateway.protocol !== "https:" && !localHttp) {
    throw new Error("BM_GATEWAY_URL phải dùng HTTPS");
  }
  if (!gatewayKey) throw new Error("BM_GATEWAY_KEY không được trống");
  if (!gatewayUrl.endsWith("/api/v1/integrations/events")) {
    throw new Error("BM_GATEWAY_URL phải trỏ tới /api/v1/integrations/events");
  }
  if (!personField.startsWith("body.") && !personField.startsWith("query.")) {
    throw new Error("BM_PERSON_FIELD phải bắt đầu bằng body. hoặc query.");
  }
  if (!employeeMapPath) throw new Error("BM_EMPLOYEE_MAP_PATH không được trống");
  forwarding = {
    gatewayUrl,
    gatewayKey,
    deviceId,
    personField,
    occurredAtField,
    confidenceField,
    employeeMap: loadEmployeeMap(employeeMapPath),
  };
}

mkdirSync(dirname(databasePath), { recursive: true });
const db = new DatabaseSync(databasePath);
db.exec(`
  PRAGMA journal_mode = WAL;
  PRAGMA synchronous = FULL;
  PRAGMA foreign_keys = ON;

  CREATE TABLE IF NOT EXISTS raw_events (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id TEXT NOT NULL UNIQUE,
    received_at TEXT NOT NULL,
    source_ip TEXT NOT NULL,
    method TEXT NOT NULL,
    path TEXT NOT NULL,
    query_string TEXT NOT NULL,
    event_kind TEXT NOT NULL,
    content_type TEXT NOT NULL,
    headers_json TEXT NOT NULL,
    body BLOB NOT NULL,
    body_sha256 TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS outbox (
    event_id TEXT PRIMARY KEY REFERENCES raw_events(event_id),
    state TEXT NOT NULL DEFAULT 'pending',
    attempt_count INTEGER NOT NULL DEFAULT 0,
    next_attempt_at TEXT NOT NULL,
    last_error TEXT,
    sent_at TEXT
  );

  CREATE TABLE IF NOT EXISTS runtime_state (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS delivery_guard (
    dedupe_key TEXT PRIMARY KEY,
    event_id TEXT NOT NULL,
    occurred_at TEXT NOT NULL
  );

  CREATE INDEX IF NOT EXISTS idx_raw_events_received_at
    ON raw_events(received_at DESC);
  CREATE INDEX IF NOT EXISTS idx_outbox_pending
    ON outbox(state, next_attempt_at);
`);

const insertEvent = db.prepare(`
  INSERT INTO raw_events (
    event_id, received_at, source_ip, method, path, query_string,
    event_kind, content_type, headers_json, body, body_sha256
  ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
`);
const insertOutbox = db.prepare(`INSERT INTO outbox (event_id, next_attempt_at) VALUES (?, ?)`);
const upsertState = db.prepare(`
  INSERT INTO runtime_state (key, value, updated_at) VALUES (?, ?, ?)
  ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
`);
const getState = db.prepare(`SELECT value FROM runtime_state WHERE key = ?`);
const maximumSequence = db.prepare(`SELECT COALESCE(MAX(sequence), 0) AS value FROM raw_events`);
const markCapturedBeforeForwarding = db.prepare(`
  UPDATE outbox SET state = 'shadowed', last_error = 'CAPTURED_BEFORE_FORWARDING'
  WHERE state = 'pending' AND event_id IN (
    SELECT event_id FROM raw_events WHERE sequence <= ?
  )
`);
const statusCounts = db.prepare(`
  SELECT
    (SELECT COUNT(*) FROM raw_events) AS received,
    (SELECT COUNT(*) FROM outbox WHERE state = 'pending') AS pending,
    (SELECT COUNT(*) FROM outbox WHERE state = 'sent') AS sent,
    (SELECT COUNT(*) FROM outbox WHERE state = 'deduplicated') AS deduplicated,
    (SELECT COUNT(*) FROM outbox WHERE state = 'blocked') AS blocked,
    (SELECT COUNT(*) FROM outbox WHERE state = 'shadowed') AS shadowed,
    (SELECT MAX(received_at) FROM raw_events) AS last_event_at,
    (SELECT value FROM runtime_state WHERE key = 'last_heartbeat_at') AS last_heartbeat_at,
    (SELECT last_error FROM outbox WHERE last_error IS NOT NULL AND state IN ('pending', 'blocked')
      ORDER BY next_attempt_at DESC LIMIT 1) AS last_forward_error
`);
const pendingEvents = db.prepare(`
  SELECT r.*, o.attempt_count
  FROM outbox o
  JOIN raw_events r ON r.event_id = o.event_id
  WHERE o.state = 'pending' AND o.next_attempt_at <= ? AND r.sequence > ?
  ORDER BY r.sequence
  LIMIT 10
`);
const recentEvents = db.prepare(`
  SELECT sequence, event_id, received_at, source_ip, method, path, query_string,
         content_type, headers_json, body, body_sha256
  FROM raw_events
  WHERE event_kind <> 'heartbeat'
  ORDER BY sequence DESC
  LIMIT ?
`);
const markSent = db.prepare(`
  UPDATE outbox SET state = 'sent', sent_at = ?, last_error = NULL WHERE event_id = ?
`);
const markDeduplicated = db.prepare(`
  UPDATE outbox SET state = 'deduplicated', sent_at = ?, last_error = ? WHERE event_id = ?
`);
const getDeliveryGuard = db.prepare(`
  SELECT event_id, occurred_at FROM delivery_guard WHERE dedupe_key = ?
`);
const upsertDeliveryGuard = db.prepare(`
  INSERT INTO delivery_guard (dedupe_key, event_id, occurred_at) VALUES (?, ?, ?)
  ON CONFLICT(dedupe_key) DO UPDATE SET
    event_id = excluded.event_id,
    occurred_at = excluded.occurred_at
`);
const markRetry = db.prepare(`
  UPDATE outbox
  SET attempt_count = attempt_count + 1, next_attempt_at = ?, last_error = ?
  WHERE event_id = ?
`);
const markBlocked = db.prepare(`
  UPDATE outbox SET state = 'blocked', last_error = ? WHERE event_id = ?
`);
const requeueBlocked = db.prepare(`
  UPDATE outbox
  SET state = 'pending', attempt_count = 0, next_attempt_at = ?, last_error = NULL
  WHERE state = 'blocked'
`);
const deleteExpiredDeliveryGuards = db.prepare(`
  DELETE FROM delivery_guard WHERE occurred_at < ?
`);
const deleteExpiredOutbox = db.prepare(`
  DELETE FROM outbox
  WHERE state IN ('sent', 'deduplicated', 'shadowed') AND event_id IN (
    SELECT o.event_id
    FROM outbox o
    JOIN raw_events r ON r.event_id = o.event_id
    WHERE r.received_at < ?
  )
`);
const deleteExpiredRawEvents = db.prepare(`
  DELETE FROM raw_events
  WHERE received_at < ? AND (
    event_kind = 'heartbeat' OR
    NOT EXISTS (SELECT 1 FROM outbox o WHERE o.event_id = raw_events.event_id)
  )
`);

let forwardAfterSequence = 0;
if (forwarding) {
  const stored = getState.get("forward_after_sequence");
  if (stored) {
    forwardAfterSequence = Number(stored.value);
  } else {
    forwardAfterSequence = replayShadow ? 0 : Number(maximumSequence.get().value);
    const now = new Date().toISOString();
    upsertState.run("forward_after_sequence", String(forwardAfterSequence), now);
    if (!replayShadow) markCapturedBeforeForwarding.run(forwardAfterSequence);
  }
}

function normalizeIp(address = "") {
  return address.startsWith("::ffff:") ? address.slice(7) : address;
}

function isLocalhost(address) {
  return address === "127.0.0.1" || address === "::1";
}

function safeHeaders(headers) {
  const sensitiveName = /(authorization|cookie|token|secret|api[-_]?key|signature)/i;
  return Object.fromEntries(
    Object.entries(headers).map(([key, value]) => [
      key,
      sensitiveName.test(key) ? "[REDACTED]" : value,
    ]),
  );
}

function cleanupRetention() {
  const now = new Date();
  const cutoff = new Date(now.getTime() - rawRetentionDays * 86_400_000).toISOString();
  const cleanedAt = now.toISOString();
  db.exec("BEGIN IMMEDIATE");
  try {
    const guards = deleteExpiredDeliveryGuards.run(cutoff);
    const outbox = deleteExpiredOutbox.run(cutoff);
    const raw = deleteExpiredRawEvents.run(cutoff);
    upsertState.run("last_cleanup_at", cleanedAt, cleanedAt);
    db.exec("COMMIT");
    return {
      cutoff,
      deliveryGuards: Number(guards.changes),
      outboxRows: Number(outbox.changes),
      rawEvents: Number(raw.changes),
    };
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}

async function readBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > maxBodyBytes) throw new Error("PAYLOAD_TOO_LARGE");
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

function saveRawEvent(request, url, sourceIp, body) {
  const receivedAt = new Date().toISOString();
  const eventId = randomUUID();
  const kind = url.pathname.toLowerCase().includes("heartbeat") ? "heartbeat" : "terminal_callback";
  const checksum = createHash("sha256").update(body).digest("hex");

  db.exec("BEGIN IMMEDIATE");
  try {
    insertEvent.run(
      eventId,
      receivedAt,
      sourceIp,
      request.method || "UNKNOWN",
      url.pathname,
      url.search.slice(1),
      kind,
      request.headers["content-type"] || "",
      JSON.stringify(safeHeaders(request.headers)),
      body,
      checksum,
    );
    if (kind === "heartbeat") {
      upsertState.run("last_heartbeat_at", receivedAt, receivedAt);
    } else {
      insertOutbox.run(eventId, receivedAt);
    }
    db.exec("COMMIT");
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }

  return { eventId, receivedAt, kind };
}

function sendJson(response, status, body) {
  response.writeHead(status, {
    "cache-control": "no-store",
    "content-type": "application/json; charset=utf-8",
  });
  response.end(JSON.stringify(body));
}

const server = createServer(async (request, response) => {
  const sourceIp = normalizeIp(request.socket.remoteAddress);
  const url = new URL(request.url || "/", "http://bridge.local");

  if (request.method === "GET" && url.pathname === "/health") {
    if (!isLocalhost(sourceIp) && !allowedIps.has(sourceIp)) {
      return sendJson(response, 403, { ok: false, error: "SOURCE_IP_NOT_ALLOWED" });
    }
    const counts = statusCounts.get();
    return sendJson(response, 200, {
      ok: true,
      version: "0.3.2",
      mode: forwarding ? "forwarding-staging" : "shadow-local-only",
      deviceId,
      direction: forwarding ? "AUTO" : null,
      allowedTerminalIps: [...allowedIps],
      received: Number(counts.received),
      pending: Number(counts.pending),
      sent: Number(counts.sent),
      deduplicated: Number(counts.deduplicated),
      blocked: Number(counts.blocked),
      shadowed: Number(counts.shadowed),
      lastEventAt: counts.last_event_at,
      lastHeartbeatAt: counts.last_heartbeat_at,
      lastForwardError: counts.last_forward_error,
      gatewayEnabled: Boolean(forwarding),
      forwardAfterSequence: forwarding ? forwardAfterSequence : null,
      mappedPeople: forwarding ? forwarding.employeeMap.size : 0,
      dedupeSeconds: forwarding ? dedupeSeconds : null,
      rawRetentionDays,
      lastCleanupAt: getState.get("last_cleanup_at")?.value ?? null,
    });
  }

  if (request.method === "GET" && url.pathname === "/diagnostics/recent") {
    if (!isLocalhost(sourceIp)) {
      return sendJson(response, 403, { ok: false, error: "LOCALHOST_ONLY" });
    }
    const requestedLimit = Number(url.searchParams.get("limit") || 5);
    const limit = Number.isFinite(requestedLimit)
      ? Math.min(10, Math.max(1, Math.trunc(requestedLimit)))
      : 5;
    const items = await Promise.all(recentEvents.all(limit).map(async (event) => {
      const body = Buffer.from(event.body);
      let parsed = null;
      let parseError = null;
      try {
        parsed = await parseTerminalData(event);
      } catch (error) {
        parseError = error instanceof Error ? error.message : "PARSE_FAILED";
      }
      const binaryBody = String(event.content_type).toLowerCase().includes("multipart/form-data") ||
        String(event.content_type).toLowerCase().startsWith("image/") ||
        String(event.content_type).toLowerCase().includes("application/octet-stream");
      return {
        sequence: Number(event.sequence),
        eventId: event.event_id,
        receivedAt: event.received_at,
        sourceIp: event.source_ip,
        method: event.method,
        path: event.path,
        queryString: event.query_string,
        contentType: event.content_type,
        headers: JSON.parse(event.headers_json),
        parsed,
        parseError,
        bodyUtf8Preview: binaryBody ? null : body.subarray(0, 65_536).toString("utf8"),
        bodyBytes: body.length,
        bodyTruncated: body.length > 65_536,
        bodySha256: event.body_sha256,
      };
    }));
    return sendJson(response, 200, { items });
  }

  if (request.method === "POST" && url.pathname === "/control/requeue-blocked") {
    if (!isLocalhost(sourceIp)) {
      return sendJson(response, 403, { ok: false, error: "LOCALHOST_ONLY" });
    }
    const result = requeueBlocked.run(new Date().toISOString());
    return sendJson(response, 200, { ok: true, requeued: Number(result.changes) });
  }

  if (request.method === "POST" && url.pathname === "/control/cleanup") {
    if (!isLocalhost(sourceIp)) {
      return sendJson(response, 403, { ok: false, error: "LOCALHOST_ONLY" });
    }
    return sendJson(response, 200, { ok: true, ...cleanupRetention() });
  }

  if (request.method !== "POST" || !url.pathname.startsWith("/Subscribe/")) {
    return sendJson(response, 404, { ok: false, error: "CALLBACK_ROUTE_NOT_FOUND" });
  }

  if (!isLocalhost(sourceIp) && !allowedIps.has(sourceIp)) {
    return sendJson(response, 403, { ok: false, error: "SOURCE_IP_NOT_ALLOWED" });
  }

  try {
    const body = await readBody(request);
    const saved = saveRawEvent(request, url, sourceIp, body);
    console.log(`${saved.receivedAt} ${sourceIp} ${request.method} ${url.pathname} ${saved.kind} ${saved.eventId}`);
    response.writeHead(200, { "content-type": "text/plain; charset=utf-8" });
    response.end("OK");
  } catch (error) {
    const tooLarge = error instanceof Error && error.message === "PAYLOAD_TOO_LARGE";
    console.error(new Date().toISOString(), "Không thể lưu callback:", error);
    sendJson(response, tooLarge ? 413 : 503, {
      ok: false,
      error: tooLarge ? "PAYLOAD_TOO_LARGE" : "LOCAL_PERSISTENCE_FAILED",
    });
  }
});

server.requestTimeout = 15_000;
server.headersTimeout = 10_000;
server.keepAliveTimeout = 5_000;
server.maxHeadersCount = 64;

function retryableStatus(status) {
  return status === 408 || status === 429 || status >= 500;
}

function retryLater(event, message) {
  const attempts = Number(event.attempt_count) + 1;
  const exponential = Math.min(300_000, 2 ** Math.min(attempts, 8) * 1_000);
  const jitter = Math.floor(Math.random() * Math.min(5_000, exponential / 4));
  markRetry.run(
    new Date(Date.now() + exponential + jitter).toISOString(),
    message.slice(0, 500),
    event.event_id,
  );
}

function deliveryKey(canonical) {
  return [
    canonical.source_device_id,
    canonical.payload.employee_id,
    canonical.event_type,
  ].join("|");
}

function duplicateOf(canonical) {
  if (dedupeSeconds === 0) return null;
  const previous = getDeliveryGuard.get(deliveryKey(canonical));
  if (!previous) return null;
  const elapsed = Date.parse(canonical.occurred_at) - Date.parse(previous.occurred_at);
  return elapsed >= 0 && elapsed <= dedupeSeconds * 1_000 ? previous : null;
}

function markDelivered(eventId, canonical) {
  const deliveredAt = new Date().toISOString();
  db.exec("BEGIN IMMEDIATE");
  try {
    markSent.run(deliveredAt, eventId);
    upsertDeliveryGuard.run(
      deliveryKey(canonical),
      eventId,
      canonical.occurred_at,
    );
    db.exec("COMMIT");
  } catch (error) {
    db.exec("ROLLBACK");
    throw error;
  }
}

let flushing = false;
async function flushOutbox() {
  if (!forwarding || flushing) return;
  flushing = true;
  try {
    for (const event of pendingEvents.all(new Date().toISOString(), forwardAfterSequence)) {
      let canonical;
      try {
        canonical = await toCanonicalEvent(event, forwarding);
      } catch (error) {
        const message = error instanceof Error ? error.message : "CANONICALIZATION_FAILED";
        markBlocked.run(message.slice(0, 500), event.event_id);
        continue;
      }

      const previous = duplicateOf(canonical);
      if (previous) {
        markDeduplicated.run(
          new Date().toISOString(),
          `DUPLICATE_WITHIN_${dedupeSeconds}_SECONDS:${previous.event_id}`,
          event.event_id,
        );
        continue;
      }

      try {
        const response = await fetch(forwarding.gatewayUrl, {
          method: "POST",
          headers: {
            accept: "application/json",
            "content-type": "application/json",
            "idempotency-key": canonical.event_id,
            "x-bma-gateway-key": forwarding.gatewayKey,
          },
          body: JSON.stringify(canonical),
          signal: AbortSignal.timeout(10_000),
        });
        if (response.status === 200 || response.status === 202) {
          markDelivered(event.event_id, canonical);
          continue;
        }
        const detail = (await response.text()).slice(0, 350);
        const message = `HTTP ${response.status}${detail ? `: ${detail}` : ""}`;
        if (retryableStatus(response.status)) retryLater(event, message);
        else markBlocked.run(message.slice(0, 500), event.event_id);
      } catch (error) {
        const message = error instanceof Error ? error.message : "NETWORK_ERROR";
        retryLater(event, message);
      }
    }
  } finally {
    flushing = false;
  }
}

const flushTimer = setInterval(flushOutbox, 2_000);
flushTimer.unref();
cleanupRetention();
const cleanupTimer = setInterval(() => {
  try {
    cleanupRetention();
  } catch (error) {
    console.error(new Date().toISOString(), "Retention cleanup failed:", error);
  }
}, 6 * 60 * 60 * 1_000);
cleanupTimer.unref();

server.listen(port, host, () => {
  console.log(`BM Device Bridge v0.3.2 đang nghe tại http://${host}:${port}`);
  console.log(`Terminal được phép: ${[...allowedIps].join(", ")}`);
  console.log(`Chế độ: ${forwarding ? "STAGING AUTO" : "SHADOW (chỉ lưu cục bộ)"}`);
  if (forwarding) {
    console.log(`Chỉ chuyển tiếp sự kiện có sequence > ${forwardAfterSequence}; đã map ${forwarding.employeeMap.size} nhân viên.`);
    console.log(`Chống trùng cùng người/thiết bị: ${dedupeSeconds} giây.`);
  }
  console.log(`Raw callback đã xử lý được giữ ${rawRetentionDays} ngày; pending/blocked không bị xóa.`);
});

function shutdown() {
  clearInterval(flushTimer);
  clearInterval(cleanupTimer);
  server.close(() => {
    db.close();
    process.exit(0);
  });
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
