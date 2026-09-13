import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

function maybeJson(value) {
  if (typeof value !== "string") return value;
  const trimmed = value.trim();
  if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) return value;
  try {
    return JSON.parse(trimmed);
  } catch {
    return value;
  }
}

function formDataToObject(formData) {
  const result = {};
  for (const [key, value] of formData.entries()) {
    const normalized = typeof value === "string"
      ? maybeJson(value)
      : { file_name: value.name, content_type: value.type, size: value.size };
    if (key in result) {
      result[key] = Array.isArray(result[key])
        ? [...result[key], normalized]
        : [result[key], normalized];
    } else {
      result[key] = normalized;
    }
  }
  return result;
}

export function loadEmployeeMap(filePath) {
  const absolutePath = resolve(filePath);
  const document = JSON.parse(readFileSync(absolutePath, "utf8"));
  const source = document.terminal_person_to_employee ?? document;
  if (!source || Array.isArray(source) || typeof source !== "object") {
    throw new Error("EMPLOYEE_MAP_INVALID");
  }
  const entries = Object.entries(source)
    .map(([terminalPersonId, employeeCode]) => [terminalPersonId.trim(), String(employeeCode).trim()])
    .filter(([terminalPersonId, employeeCode]) => terminalPersonId && employeeCode);
  if (entries.length === 0) throw new Error("EMPLOYEE_MAP_EMPTY");
  return new Map(entries);
}

export async function parseTerminalData(event) {
  const body = Buffer.from(event.body);
  const contentType = String(event.content_type || "").toLowerCase();
  let parsedBody;

  if (contentType.includes("multipart/form-data")) {
    const form = await new Response(body, { headers: { "content-type": contentType } }).formData();
    parsedBody = formDataToObject(form);
  } else if (contentType.includes("application/x-www-form-urlencoded")) {
    parsedBody = Object.fromEntries(new URLSearchParams(body.toString("utf8")));
  } else {
    parsedBody = maybeJson(body.toString("utf8"));
  }

  return {
    body: parsedBody,
    query: Object.fromEntries(new URLSearchParams(event.query_string || "")),
  };
}

export function valueAt(root, fieldPath) {
  if (!fieldPath) return undefined;
  return fieldPath.split(".").reduce((value, part) => {
    if (value === null || value === undefined || typeof value !== "object") return undefined;
    return value[part];
  }, root);
}

function requiredText(value, code) {
  const text = value === null || value === undefined ? "" : String(value).trim();
  if (!text) throw new Error(code);
  return text;
}

function occurredAt(value, fallback) {
  if (value === null || value === undefined || value === "") return fallback;
  const number = typeof value === "number" ? value : Number(value);
  const date = Number.isFinite(number)
    ? new Date(number > 10_000_000_000 ? number : number * 1_000)
    : new Date(String(value));
  if (Number.isNaN(date.getTime())) throw new Error("INVALID_OCCURRED_AT");
  return date.toISOString();
}

function confidenceAt(value) {
  if (value === null || value === undefined || value === "") return null;
  const confidence = Number(value);
  if (!Number.isFinite(confidence) || confidence < 0 || confidence > 1) {
    throw new Error("INVALID_CONFIDENCE");
  }
  return confidence;
}

export async function toCanonicalEvent(event, config) {
  const parsed = await parseTerminalData(event);
  const terminalPersonId = requiredText(
    valueAt(parsed, config.personField),
    `PERSON_FIELD_NOT_FOUND:${config.personField}`,
  );
  const employeeId = config.employeeMap.get(terminalPersonId);
  if (!employeeId) throw new Error(`PERSON_NOT_MAPPED:${terminalPersonId}`);

  const payload = {
    employee_id: employeeId,
    evidence_ref: `bmbridge://${config.deviceId}/events/${event.event_id}`,
    verification_method: "FACE_TERMINAL",
    confidence: config.confidenceField
      ? confidenceAt(valueAt(parsed, config.confidenceField))
      : null,
  };

  return {
    event_id: event.event_id,
    event_type: "EMPLOYEE_SCAN",
    source_system: "FACE_TERMINAL",
    source_device_id: config.deviceId,
    sequence: Number(event.sequence),
    occurred_at: occurredAt(
      config.occurredAtField ? valueAt(parsed, config.occurredAtField) : undefined,
      event.received_at,
    ),
    schema_version: "1.0",
    correlation_id: null,
    payload,
    payload_hash: createHash("sha256").update(JSON.stringify(payload)).digest("hex"),
    signature: null,
  };
}
