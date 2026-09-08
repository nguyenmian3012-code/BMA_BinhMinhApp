param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^(body|query)\.")]
    [string]$PersonField,

    [string]$OccurredAtField = "",
    [string]$ConfidenceField = "",
    [ValidateRange(0, 3600)]
    [int]$DedupeSeconds = 120,
    [string]$EmployeeMapPath = ".\employee-map.json",
    [string]$BmaEnvPath = "C:\ABMT\BMA_BinhMinhApp\.env.staging",
    [switch]$ReplayShadow
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "Khong tim thay Node.js. Can Node.js 24 tro len."
}
if (-not (Test-Path $BmaEnvPath -PathType Leaf)) {
    throw "Khong tim thay file BMA staging: $BmaEnvPath"
}

$keyLine = Get-Content $BmaEnvPath | Where-Object {
    $_ -match '^\s*BMA_GATEWAY_INBOUND_KEY\s*='
} | Select-Object -Last 1
if (-not $keyLine) {
    throw "Thieu BMA_GATEWAY_INBOUND_KEY trong $BmaEnvPath"
}
$gatewayKey = ($keyLine -split '=', 2)[1].Trim()
if ([string]::IsNullOrWhiteSpace($gatewayKey) -or $gatewayKey -match '^CHANGE_ME') {
    throw "BMA_GATEWAY_INBOUND_KEY chua duoc cau hinh bang secret that."
}

$resolvedMap = if ([System.IO.Path]::IsPathRooted($EmployeeMapPath)) {
    $EmployeeMapPath
} else {
    Join-Path $scriptRoot $EmployeeMapPath
}
if (-not (Test-Path $resolvedMap -PathType Leaf)) {
    throw "Khong tim thay employee map: $resolvedMap. Hay copy employee-map.example.json thanh employee-map.json va sua mapping."
}

New-Item -ItemType Directory -Force -Path (Join-Path $scriptRoot "data") | Out-Null
$env:BM_BRIDGE_HOST = "0.0.0.0"
$env:BM_BRIDGE_PORT = "8789"
$env:BM_TERMINAL_IP = "192.168.1.227"
$env:BM_DEVICE_ID = "1605063"
$env:BM_DB_PATH = Join-Path $scriptRoot "data\bm-device-bridge.sqlite"
$env:BM_GATEWAY_URL = "https://gateway.redtigerhead.com/bmapp-staging/api/v1/integrations/events"
$env:BM_GATEWAY_KEY = $gatewayKey
$env:BM_PERSON_FIELD = $PersonField
$env:BM_EMPLOYEE_MAP_PATH = $resolvedMap
$env:BM_DEDUPE_SECONDS = [string]$DedupeSeconds

if ($OccurredAtField) { $env:BM_OCCURRED_AT_FIELD = $OccurredAtField }
else { Remove-Item Env:BM_OCCURRED_AT_FIELD -ErrorAction SilentlyContinue }
if ($ConfidenceField) { $env:BM_CONFIDENCE_FIELD = $ConfidenceField }
else { Remove-Item Env:BM_CONFIDENCE_FIELD -ErrorAction SilentlyContinue }
if ($ReplayShadow) { $env:BM_FORWARD_REPLAY = "1" }
else { Remove-Item Env:BM_FORWARD_REPLAY -ErrorAction SilentlyContinue }

Remove-Item Env:BM_ATTENDANCE_DIRECTION -ErrorAction SilentlyContinue

Write-Host "BM Device Bridge v0.3.0 -> BMA STAGING" -ForegroundColor Cyan
Write-Host "Direction: AUTO (BMA quyet dinh theo tung nhan vien); Person field: $PersonField" -ForegroundColor Cyan
Write-Host "Debounce: $DedupeSeconds giay" -ForegroundColor Cyan
if (-not $ReplayShadow) {
    Write-Host "Van an toan BAT: cac callback shadow cu se khong duoc gui. Chi callback moi sau lan khoi dong nay." -ForegroundColor Yellow
} else {
    Write-Host "CANH BAO: ReplayShadow da bat; cac callback cu co the duoc gui." -ForegroundColor Red
}
Write-Host "Nhan Ctrl+C de dung." -ForegroundColor Yellow
& node (Join-Path $scriptRoot "bridge.mjs")
