import { createHash } from "node:crypto";

function requiredText(value, field) {
  const text = value === null || value === undefined ? "" : String(value).trim();
  if (!text) throw new Error(`BMKCS_${field.toUpperCase()}_REQUIRED`);
  return text;
}

function optionalText(value) {
  const text = value === null || value === undefined ? "" : String(value).trim();
  return text || null;
}

function requiredNumber(value, field) {
  const number = Number(value);
  if (!Number.isFinite(number)) throw new Error(`BMKCS_${field.toUpperCase()}_INVALID`);
  return number;
}

function optionalNumber(value, field) {
  if (value === null || value === undefined || value === "") return null;
  return requiredNumber(value, field);
}

function isoDate(value, field) {
  const text = requiredText(value, field);
  const date = new Date(text);
  if (Number.isNaN(date.getTime())) throw new Error(`BMKCS_${field.toUpperCase()}_INVALID`);
  return date.toISOString();
}

export function toBmaQualityEvent(legacy) {
  if (!legacy || Array.isArray(legacy) || typeof legacy !== "object") {
    throw new Error("BMKCS_PAYLOAD_MUST_BE_OBJECT");
  }

  const resultId = requiredText(legacy.id, "id");
  if (resultId.length > 100) throw new Error("BMKCS_ID_TOO_LONG");
  const occurredAt = isoDate(legacy.ts, "ts");
  const sourceDeviceId = requiredText(legacy.station, "station");
  if (sourceDeviceId.length > 100) throw new Error("BMKCS_STATION_TOO_LONG");

  const payload = {
    result_id: resultId,
    lot_code: requiredText(legacy.lot, "lot"),
    measured_at: occurredAt,
    production_date: optionalText(legacy.pd),
    ph: requiredNumber(legacy.ph, "ph"),
    whiteness: requiredNumber(legacy.w, "w"),
    moisture: requiredNumber(legacy.m, "m"),
    fineness: null,
    fineness_unit: null,
    viscosity: optionalNumber(legacy.v, "v"),
    viscosity_unit: null,
    extra_value: optionalNumber(legacy.x, "x"),
    product_code: optionalText(legacy.prod),
    operator_code: optionalText(legacy.op),
    quality_code: optionalText(legacy.qc),
    customer_code: optionalText(legacy.cust),
  };

  return {
    event_id: resultId,
    event_type: "QUALITY_RESULT_PUBLISHED",
    source_system: "BMKCS",
    source_device_id: sourceDeviceId,
    sequence: null,
    occurred_at: occurredAt,
    schema_version: "1.0",
    correlation_id: resultId,
    payload,
    payload_hash: createHash("sha256").update(JSON.stringify(payload)).digest("hex"),
    signature: null,
  };
}

export async function publishBmkcsResult(legacy, options) {
  const bmaUrl = String(options?.bmaUrl || "").trim();
  const bmaGatewayKey = String(options?.bmaGatewayKey || "").trim();
  const fetchImpl = options?.fetchImpl || fetch;
  let parsedUrl;
  try {
    parsedUrl = new URL(bmaUrl);
  } catch {
    throw new Error("BMA_INTEGRATION_URL_INVALID");
  }
  const localHttp = parsedUrl.protocol === "http:" &&
    ["127.0.0.1", "localhost", "::1"].includes(parsedUrl.hostname) &&
    options?.allowInsecureLocalBma === true;
  if ((parsedUrl.protocol !== "https:" && !localHttp) ||
      !parsedUrl.pathname.endsWith("/api/v1/integrations/events")) {
    throw new Error("BMA_INTEGRATION_URL_INVALID");
  }
  if (!bmaGatewayKey) throw new Error("BMA_GATEWAY_KEY_REQUIRED");

  const canonical = toBmaQualityEvent(legacy);
  const response = await fetchImpl(parsedUrl, {
    method: "POST",
    headers: {
      accept: "application/json",
      "content-type": "application/json",
      "idempotency-key": canonical.event_id,
      "x-bma-gateway-key": bmaGatewayKey,
    },
    body: JSON.stringify(canonical),
    signal: AbortSignal.timeout(10_000),
  });
  const responseBody = await response.text();
  if (response.status !== 200 && response.status !== 202) {
    const error = new Error(`BMA_HTTP_${response.status}:${responseBody.slice(0, 350)}`);
    error.retryable = response.status === 408 || response.status === 429 || response.status >= 500;
    error.status = response.status;
    throw error;
  }

  return { canonical, status: response.status, body: responseBody };
}
