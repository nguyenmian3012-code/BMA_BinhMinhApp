param(
    [string]$EnvFile = ".env.staging",
    [string]$PostgresBin = "C:\Program Files\PostgreSQL\17\bin",
    [string]$OutputDirectory = "artifacts\backups"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-DotEnvValue([string]$Path, [string]$Name, [string]$Default = "") {
    $escaped = [regex]::Escape($Name)
    $line = Get-Content -LiteralPath $Path | Where-Object {
        $_ -match "^\s*$escaped\s*="
    } | Select-Object -Last 1
    if (!$line) { return $Default }
    return (($line -split "=", 2)[1].Trim()).Trim('"').Trim("'")
}

function Get-PlainText([Security.SecureString]$Value) {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

function Invoke-PsqlScalar {
    param([string]$Sql, [string]$Database, [string]$User, [string]$Password)

    $previousPassword = $env:PGPASSWORD
    try {
        $env:PGPASSWORD = $Password
        $output = @($Sql | & $script:Psql -X -v ON_ERROR_STOP=1 `
            --host $script:DatabaseHost --port $script:DatabasePort `
            --username $User --dbname $Database --quiet --tuples-only --no-align 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "psql failed: $($output -join [Environment]::NewLine)"
        }
        $lines = @($output | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ })
        if ($lines.Count -eq 0) { throw "psql returned no scalar value." }
        return $lines[-1]
    }
    finally { $env:PGPASSWORD = $previousPassword }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$envPath = if ([IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $repoRoot $EnvFile }
if (!(Test-Path -LiteralPath $envPath -PathType Leaf)) { throw "Environment file not found: $envPath" }

$script:DatabaseHost = Get-DotEnvValue $envPath "BMA_DB_HOST" "127.0.0.1"
$script:DatabasePort = Get-DotEnvValue $envPath "BMA_DB_PORT" "5432"
$sourceDatabase = Get-DotEnvValue $envPath "BMA_DB_NAME" "binhminh_data_staging"
$sourceUser = Get-DotEnvValue $envPath "BMA_DB_USER" "bma_staging_runtime"
$sourcePassword = Get-DotEnvValue $envPath "BMA_DB_PASSWORD"
if (!$sourcePassword) { $sourcePassword = Get-DotEnvValue $envPath "POSTGRES_PASSWORD" }
if (!$sourcePassword -or $sourcePassword -like "*CHANGE_ME*") { throw "BMA_DB_PASSWORD is missing." }

foreach ($identifier in @($sourceDatabase, $sourceUser)) {
    if ($identifier -notmatch "^[A-Za-z0-9_]+$") { throw "Invalid PostgreSQL identifier: $identifier" }
}

$script:Psql = Join-Path $PostgresBin "psql.exe"
$pgDump = Join-Path $PostgresBin "pg_dump.exe"
$pgRestore = Join-Path $PostgresBin "pg_restore.exe"
$createdb = Join-Path $PostgresBin "createdb.exe"
$dropdb = Join-Path $PostgresBin "dropdb.exe"
foreach ($tool in @($script:Psql, $pgDump, $pgRestore, $createdb, $dropdb)) {
    if (!(Test-Path -LiteralPath $tool -PathType Leaf)) { throw "PostgreSQL tool not found: $tool" }
}

$outputRoot = if ([IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory
} else {
    Join-Path $repoRoot $OutputDirectory
}
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupName = "bma-native-$sourceDatabase-$timestamp.dump"
$backupPath = Join-Path $outputRoot $backupName

$previousPassword = $env:PGPASSWORD
try {
    $env:PGPASSWORD = $sourcePassword
    & $pgDump --host $script:DatabaseHost --port $script:DatabasePort `
        --username $sourceUser --dbname $sourceDatabase --format custom `
        --no-owner --no-privileges --file $backupPath
    if ($LASTEXITCODE -ne 0) { throw "pg_dump failed." }
}
finally {
    $env:PGPASSWORD = $previousPassword
    $sourcePassword = $null
}

$hash = Get-FileHash -Algorithm SHA256 $backupPath
"$($hash.Hash)  $backupName" | Set-Content -Encoding ASCII "$backupPath.sha256"
$restoreDatabase = "bma_restore_check_" + [Guid]::NewGuid().ToString("N").Substring(0, 12)
$adminPassword = Get-PlainText (Read-Host "PostgreSQL postgres password" -AsSecureString)

try {
    if ((Invoke-PsqlScalar -Sql "SELECT 1;" -Database "postgres" -User "postgres" `
        -Password $adminPassword) -ne "1") { throw "PostgreSQL administrator login failed." }

    $env:PGPASSWORD = $adminPassword
    & $createdb --host $script:DatabaseHost --port $script:DatabasePort `
        --username postgres $restoreDatabase
    if ($LASTEXITCODE -ne 0) { throw "Could not create isolated restore database." }

    & $pgRestore --host $script:DatabaseHost --port $script:DatabasePort `
        --username postgres --dbname $restoreDatabase --no-owner --no-privileges $backupPath
    if ($LASTEXITCODE -ne 0) { throw "pg_restore failed." }

    $migrationCount = Invoke-PsqlScalar -Sql 'SELECT count(*) FROM "__EFMigrationsHistory";' `
        -Database $restoreDatabase -User "postgres" -Password $adminPassword
    $tableCount = Invoke-PsqlScalar `
        -Sql "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE';" `
        -Database $restoreDatabase -User "postgres" -Password $adminPassword
    if ([int]$migrationCount -lt 1) { throw "Restored database has no EF migration history." }
    if ([int]$tableCount -lt 2) { throw "Restored database has too few tables." }

    [PSCustomObject]@{
        Result = "PASS"
        Backup = $backupPath
        Sha256 = $hash.Hash
        RestoredMigrations = [int]$migrationCount
        RestoredTables = [int]$tableCount
    } | Format-List
}
finally {
    if ($restoreDatabase -match '^bma_restore_check_[a-f0-9]{12}$') {
        $env:PGPASSWORD = $adminPassword
        & $dropdb --host $script:DatabaseHost --port $script:DatabasePort `
            --username postgres --if-exists --force $restoreDatabase 2>$null
    }
    $env:PGPASSWORD = $previousPassword
    $adminPassword = $null
}
