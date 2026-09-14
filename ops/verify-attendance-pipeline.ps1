param(
    [string]$ProjectName = "bma-staging",
    [string]$EnvFile = ".env.staging",
    [ValidatePattern("^[A-Za-z0-9._:-]+$")]
    [string]$DeviceId = "1605063"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = if ([System.IO.Path]::IsPathRooted($EnvFile)) {
    $EnvFile
} else {
    Join-Path $repoRoot $EnvFile
}
$sqlPath = Join-Path $PSScriptRoot "sql\verify-attendance-pipeline.sql"

if (-not (Test-Path $envPath -PathType Leaf)) { throw "Khong tim thay env file: $envPath" }
if (-not (Test-Path $sqlPath -PathType Leaf)) { throw "Khong tim thay SQL: $sqlPath" }

function Read-EnvValue([string]$Name) {
    $line = Get-Content $envPath | Where-Object { $_ -match "^\s*$Name\s*=" } | Select-Object -Last 1
    if (-not $line) { throw "Thieu $Name trong $envPath" }
    return ($line -split '=', 2)[1].Trim()
}

$postgresUser = Read-EnvValue "POSTGRES_USER"
$postgresDatabase = Read-EnvValue "POSTGRES_DB"
$sql = Get-Content $sqlPath -Raw

Push-Location $repoRoot
try {
    $sql | docker compose `
        --project-name $ProjectName `
        --env-file $envPath `
        exec -T postgres `
        psql -X -v ON_ERROR_STOP=1 -v "device_id=$DeviceId" -U $postgresUser -d $postgresDatabase
    if ($LASTEXITCODE -ne 0) { throw "psql verification failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
}
