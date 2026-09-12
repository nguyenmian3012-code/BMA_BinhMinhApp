param(
    [string]$BmaEnvPath = "",
    [string]$BridgePath = "C:\ABMT\BM-Device-Bridge",
    [string]$InstallRoot = "C:\ABMT\BMA-Services",
    [string]$PackagePath = "",
    [string]$PersonField = "body.info.PersonID"
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$bridgeSource = Join-Path $root "tools\bm-device-bridge"
$nativeDeploy = Join-Path $root "infra\scripts\restore-staging-origin.ps1"
$bmaVersion = "0.3.1"
$bridgeVersion = "0.3.2"

if (!$BmaEnvPath) { $BmaEnvPath = Join-Path $root ".env.staging" }

function Get-EnvValue([string]$Name, [string]$Default) {
    $escaped = [regex]::Escape($Name)
    $line = Get-Content $BmaEnvPath | Where-Object {
        $_ -match "^\s*$escaped\s*="
    } | Select-Object -Last 1
    if (-not $line) { return $Default }
    return (($line -split "=", 2)[1].Trim()).Trim('"').Trim("'")
}

function Wait-Json([string]$Url, [int]$Seconds = 90) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        try { return Invoke-RestMethod $Url -TimeoutSec 5 }
        catch { Start-Sleep 3 }
    } while ((Get-Date) -lt $deadline)
    throw "Khong ket noi duoc: $Url"
}

if (-not (Test-Path $BmaEnvPath -PathType Leaf)) {
    throw "Khong tim thay: $BmaEnvPath"
}
if (-not (Test-Path (Join-Path $bridgeSource "start-staging.ps1") -PathType Leaf)) {
    throw "Goi deploy khong hop le. Thieu Bridge."
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "Khong tim thay Node.js."
}

$pathBase = Get-EnvValue "BMA_PATH_BASE" "/bmapp-staging"
$port = [int](Get-EnvValue "BMA_HOST_PORT" "8791")
if ($pathBase -ne "/bmapp-staging" -or $port -ne 8791) {
    throw "Safety stop: staging phai dung BMA_PATH_BASE=/bmapp-staging va BMA_HOST_PORT=8791."
}
$localBase = "http://127.0.0.1:$port$pathBase"
$publicBase = "https://gateway.redtigerhead.com$pathBase"

Write-Host "[1/5] Deploy native BMA $bmaVersion" -ForegroundColor Cyan
$deployArguments = @("-EnvFile", $BmaEnvPath, "-InstallRoot", $InstallRoot)
if ($PackagePath) { $deployArguments += @("-PackagePath", $PackagePath) }
& $nativeDeploy @deployArguments

Write-Host "[2/5] Compatibility handshake" -ForegroundColor Cyan
$localDetails = Wait-Json "$localBase/health/details"
$publicDetails = Wait-Json "$publicBase/health/details"
foreach ($details in @($localDetails, $publicDetails)) {
    if ($details.version -ne $bmaVersion -or
        $details.runtime -ne "windows-service" -or
        $details.database -ne "postgresql-native" -or
        $details.supported_event_types -notcontains "EMPLOYEE_SCAN") {
        throw "BMA runtime khong tuong thich Bridge $bridgeVersion."
    }
}

Write-Host "[3/5] Install Bridge $bridgeVersion" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $BridgePath | Out-Null
Get-ChildItem $bridgeSource -Force | Where-Object {
    $_.Name -notin @("data", "employee-map.json")
} | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $BridgePath $_.Name) -Recurse -Force
}
if (-not (Test-Path (Join-Path $BridgePath "employee-map.json") -PathType Leaf)) {
    throw "Thieu $BridgePath\employee-map.json."
}

Write-Host "[4/5] Restart Bridge" -ForegroundColor Cyan
Get-NetTCPConnection -LocalPort 8789 -State Listen -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -Unique |
    ForEach-Object { Stop-Process -Id $_ -Force }
Start-Sleep 2

$startScript = Join-Path $BridgePath "start-staging.ps1"
$arguments = '-NoExit -ExecutionPolicy Bypass -File "{0}" -PersonField "{1}" -BmaEnvPath "{2}"' -f `
    $startScript, $PersonField, $BmaEnvPath
Start-Process powershell.exe -WorkingDirectory $BridgePath -ArgumentList $arguments
$bridge = Wait-Json "http://127.0.0.1:8789/health" 60
if ($bridge.version -ne $bridgeVersion -or $bridge.direction -ne "AUTO") {
    throw "Bridge runtime khong dung phien ban."
}

Write-Host "[5/5] Requeue va verify" -ForegroundColor Cyan
$requeue = Invoke-RestMethod "http://127.0.0.1:8789/control/requeue-blocked" -Method Post
Start-Sleep 10
$bridge = Invoke-RestMethod "http://127.0.0.1:8789/health"

[PSCustomObject]@{
    Result = "PASS"
    BmaVersion = $localDetails.version
    PublicGateway = $publicDetails.ok
    BridgeVersion = $bridge.version
    Direction = $bridge.direction
    RawRetentionDays = $bridge.rawRetentionDays
    Received = $bridge.received
    Sent = $bridge.sent
    Pending = $bridge.pending
    Blocked = $bridge.blocked
    Requeued = $requeue.requeued
    GatewayError = $bridge.lastForwardError
}
