param(
    [string]$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..")),
    [string]$EnvFile = ".env.staging",
    [string]$ComposeProject = "bma-staging",
    [string]$OutputDirectory = "artifacts\backups"
)

$ErrorActionPreference = "Stop"
Set-Location $RepoRoot

$envPath = if ([IO.Path]::IsPathRooted($EnvFile)) {
    $EnvFile
} else {
    Join-Path $RepoRoot $EnvFile
}

if (!(Test-Path $envPath)) {
    throw "Environment file not found: $envPath"
}

function Get-EnvValue([string]$Name) {
    $escapedName = [regex]::Escape($Name)
    $line = Get-Content $envPath |
        Where-Object { $_ -match "^\s*$escapedName=(.*)$" } |
        Select-Object -Last 1

    if (!$line) {
        throw "Missing $Name in $envPath"
    }

    $value = ($line -replace "^\s*$escapedName=", "").Trim().Trim('"').Trim("'")
    if (!$value) {
        throw "$Name is empty in $envPath"
    }

    return $value
}

$database = Get-EnvValue "POSTGRES_DB"
$databaseUser = Get-EnvValue "POSTGRES_USER"

foreach ($identifier in @($database, $databaseUser)) {
    if ($identifier -notmatch "^[A-Za-z0-9_]+$") {
        throw "PostgreSQL database and user names may contain only letters, numbers, and underscore."
    }
}

$composeArgs = @("compose", "--project-name", $ComposeProject, "--env-file", $envPath)
$sourceContainer = (& docker @composeArgs ps -q postgres | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or !$sourceContainer) {
    throw "The $ComposeProject PostgreSQL container is not running."
}

$outputPath = if ([IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory
} else {
    Join-Path $RepoRoot $OutputDirectory
}
New-Item -ItemType Directory -Force -Path $outputPath | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupName = "bma-staging-$timestamp.dump"
$backupPath = Join-Path $outputPath $backupName
$containerBackup = "/tmp/$backupName"

& docker @composeArgs exec -T postgres pg_dump --username $databaseUser --dbname $database --format custom --file $containerBackup
if ($LASTEXITCODE -ne 0) {
    throw "pg_dump failed with exit code $LASTEXITCODE"
}

try {
    & docker cp ($sourceContainer + ":" + $containerBackup) $backupPath
    if ($LASTEXITCODE -ne 0) {
        throw "docker cp failed with exit code $LASTEXITCODE"
    }
}
finally {
    & docker @composeArgs exec -T postgres rm -f $containerBackup | Out-Null
}

$hash = Get-FileHash -Algorithm SHA256 $backupPath
"$($hash.Hash)  $backupName" | Set-Content -Encoding ascii "$backupPath.sha256"

$restoreContainer = "bma-restore-check-" + [Guid]::NewGuid().ToString("N").Substring(0, 12)
$restoreDatabase = "bma_restore"
$restoreUser = "bma_restore"
$restorePassword = [Guid]::NewGuid().ToString("N")

try {
    & docker run -d --name $restoreContainer -e "POSTGRES_DB=$restoreDatabase" -e "POSTGRES_USER=$restoreUser" -e "POSTGRES_PASSWORD=$restorePassword" postgres:17-alpine | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not start isolated restore container."
    }

    $ready = $false
    for ($attempt = 1; $attempt -le 30; $attempt++) {
        & docker exec $restoreContainer pg_isready --username $restoreUser --dbname $restoreDatabase | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $ready = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    if (!$ready) {
        throw "Isolated PostgreSQL did not become ready."
    }

    & docker cp $backupPath ($restoreContainer + ":/tmp/bma.dump")
    if ($LASTEXITCODE -ne 0) {
        throw "Could not copy backup into isolated restore container."
    }

    & docker exec $restoreContainer pg_restore --username $restoreUser --dbname $restoreDatabase --no-owner --no-privileges /tmp/bma.dump
    if ($LASTEXITCODE -ne 0) {
        throw "pg_restore failed with exit code $LASTEXITCODE"
    }

    $migrationCount = (& docker exec $restoreContainer psql --username $restoreUser --dbname $restoreDatabase --tuples-only --no-align --command 'SELECT COUNT(*) FROM "__EFMigrationsHistory";' | Out-String).Trim()
    $tableCount = (& docker exec $restoreContainer psql --username $restoreUser --dbname $restoreDatabase --tuples-only --no-align --command "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';" | Out-String).Trim()

    if ($migrationCount -notmatch "^\d+$" -or [int]$migrationCount -lt 1) {
        throw "Restored database has no EF migration history."
    }
    if ($tableCount -notmatch "^\d+$" -or [int]$tableCount -lt 2) {
        throw "Restored database has too few application tables."
    }

    Write-Host "Backup file        : $backupPath"
    Write-Host "Backup SHA-256     : $($hash.Hash)"
    Write-Host "Restored migrations: $migrationCount"
    Write-Host "Restored tables    : $tableCount"
    Write-Host "Clean restore      : PASS"
    Write-Host "Result             : PASS"
}
finally {
    & docker rm -f $restoreContainer 2>$null | Out-Null
}
