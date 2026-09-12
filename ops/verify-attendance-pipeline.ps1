param(
    [string]$EnvFile = ".env.staging",
    [string]$PostgresBin = "C:\Program Files\PostgreSQL\17\bin",
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

function Get-DotEnvValue([string]$Path, [string]$Name, [string]$Default = "") {
    $line = Get-Content $Path | Where-Object { $_ -match "^\s*$Name\s*=" } | Select-Object -Last 1
    if (-not $line) { return $Default }
    return (($line -split '=', 2)[1].Trim()).Trim('"').Trim("'")
}

$postgresHost = Get-DotEnvValue -Path $envPath -Name "BMA_DB_HOST" -Default "127.0.0.1"
$postgresPort = Get-DotEnvValue -Path $envPath -Name "BMA_DB_PORT" -Default "5432"
$postgresUser = Get-DotEnvValue -Path $envPath -Name "BMA_DB_USER" -Default "bma_staging_runtime"
$postgresDatabase = Get-DotEnvValue -Path $envPath -Name "BMA_DB_NAME" -Default "binhminh_data_staging"
$postgresPassword = Get-DotEnvValue -Path $envPath -Name "BMA_DB_PASSWORD"
if (!$postgresPassword) { $postgresPassword = Get-DotEnvValue -Path $envPath -Name "POSTGRES_PASSWORD" }
if (!$postgresPassword -or $postgresPassword -like "*CHANGE_ME*") { throw "Thieu BMA_DB_PASSWORD trong $envPath" }
if ($postgresDatabase -eq "binhminh_data") { throw "Synthetic test cannot use production database." }
$psql = Join-Path $PostgresBin "psql.exe"
if (!(Test-Path $psql -PathType Leaf)) {
    $psqlCommand = Get-Command psql.exe -ErrorAction SilentlyContinue
    if (!$psqlCommand) { throw "psql.exe not found: $psql" }
    $psql = $psqlCommand.Source
}
$sql = Get-Content $sqlPath -Raw

$previousPassword = $env:PGPASSWORD
try {
    $env:PGPASSWORD = $postgresPassword
    $sql | & $psql -X -v ON_ERROR_STOP=1 -v "device_id=$DeviceId" `
        --host $postgresHost --port $postgresPort --username $postgresUser `
        --dbname $postgresDatabase
    if ($LASTEXITCODE -ne 0) { throw "psql verification failed with exit code $LASTEXITCODE" }
} finally {
    $env:PGPASSWORD = $previousPassword
    $postgresPassword = $null
}
