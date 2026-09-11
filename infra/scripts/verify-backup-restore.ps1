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

function Invoke-DockerCapture([string[]]$DockerArguments) {
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& docker @DockerArguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output = $output
    }
}

function Invoke-PostgresScalar {
    param(
        [Parameter(Mandatory = $true)][string]$Sql,
        [Parameter(Mandatory = $true)][string]$Container,
        [Parameter(Mandatory = $true)][string]$User,
        [Parameter(Mandatory = $true)][string]$Database
    )

    # SQL must travel through stdin. Command-line SQL loses quotes at the
    # Windows PowerShell -> docker.exe boundary.
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @($Sql | & docker exec -i $Container psql -v ON_ERROR_STOP=1 --username $User --dbname $Database --quiet --tuples-only --no-align 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($exitCode -ne 0) {
        throw "PostgreSQL verification failed (exit $exitCode): $($output -join [Environment]::NewLine)"
    }

    $lines = @(
        foreach ($item in $output) {
            if ($null -eq $item) { continue }
            $line = $item.ToString().Trim()
            if (![string]::IsNullOrWhiteSpace($line)) { $line }
        }
    )
    if ($lines.Count -eq 0) {
        throw "PostgreSQL verification returned no scalar value."
    }

    return $lines[-1]
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

    $initialized = $false
    $lastContainerLogs = @()
    for ($attempt = 1; $attempt -le 60; $attempt++) {
        $logResult = Invoke-DockerCapture @("logs", $restoreContainer)
        $lastContainerLogs = $logResult.Output
        if (($lastContainerLogs | Out-String) -match "PostgreSQL init process complete; ready for start up") {
            $initialized = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    if (!$initialized) {
        $lastContainerLogs | ForEach-Object { Write-Host $_ }
        throw "Isolated PostgreSQL initialization did not complete."
    }

    & docker exec $restoreContainer pg_isready --username $restoreUser --dbname $restoreDatabase | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Isolated PostgreSQL did not become ready after initialization."
    }

    & docker cp $backupPath ($restoreContainer + ":/tmp/bma.dump")
    if ($LASTEXITCODE -ne 0) {
        throw "Could not copy backup into isolated restore container."
    }

    $restoreResult = Invoke-DockerCapture @(
        "exec", $restoreContainer,
        "pg_restore",
        "--username", $restoreUser,
        "--dbname", $restoreDatabase,
        "--no-owner",
        "--no-privileges",
        "/tmp/bma.dump"
    )
    $restoreResult.Output | ForEach-Object { Write-Host $_ }
    if ($restoreResult.ExitCode -ne 0) {
        throw "pg_restore failed with exit code $($restoreResult.ExitCode)"
    }

    $preflight = Invoke-PostgresScalar -Sql "SELECT 1;" -Container $restoreContainer -User $restoreUser -Database $restoreDatabase
    if ($preflight -ne "1") {
        throw "Restored PostgreSQL scalar preflight failed."
    }

    $migrationCount = Invoke-PostgresScalar -Sql 'SELECT COUNT(*) FROM "__EFMigrationsHistory";' -Container $restoreContainer -User $restoreUser -Database $restoreDatabase
    $tableCount = Invoke-PostgresScalar -Sql "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';" -Container $restoreContainer -User $restoreUser -Database $restoreDatabase

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
