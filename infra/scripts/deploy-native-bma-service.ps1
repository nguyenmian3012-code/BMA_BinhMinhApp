param(
    [ValidateSet("Staging", "Production")]
    [string]$Target = "Staging",
    [string]$EnvFile = "",
    [string]$InstallRoot = "C:\ABMT\BMA-Services",
    [string]$PackagePath = "",
    [string]$PostgresBin = "C:\Program Files\PostgreSQL\17\bin",
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-DotEnvValue {
    param([string]$Path, [string]$Name, [string]$Default = "")

    $escaped = [regex]::Escape($Name)
    $line = Get-Content -LiteralPath $Path | Where-Object {
        $_ -match "^\s*$escaped\s*="
    } | Select-Object -Last 1
    if (!$line) { return $Default }
    $value = ($line -split "=", 2)[1].Trim()
    if ($value.Length -ge 2 -and (
        ($value.StartsWith('"') -and $value.EndsWith('"')) -or
        ($value.StartsWith("'") -and $value.EndsWith("'")))) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    return $value
}

function Get-RequiredEnvValue {
    param([string]$Path, [string]$Name, [string]$FallbackName = "")

    $value = Get-DotEnvValue -Path $Path -Name $Name
    if (!$value -and $FallbackName) {
        $value = Get-DotEnvValue -Path $Path -Name $FallbackName
    }
    if (!$value -or $value -like "*CHANGE_ME*") {
        throw "$Name is missing or still uses a placeholder in $Path."
    }
    return $value
}

function ConvertTo-ConnectionStringValue {
    param([string]$Value)

    return '"' + $Value.Replace('"', '""') + '"'
}

function Get-PlainText {
    param([Security.SecureString]$SecureValue)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

function Invoke-Psql {
    param(
        [string]$Sql,
        [string]$Database,
        [string]$User,
        [string]$Password,
        [switch]$Scalar
    )

    $previousPassword = $env:PGPASSWORD
    try {
        $env:PGPASSWORD = $Password
        $arguments = @(
            "-X", "-v", "ON_ERROR_STOP=1",
            "--host", $script:DatabaseHost,
            "--port", $script:DatabasePort,
            "--username", $User,
            "--dbname", $Database
        )
        if ($Scalar) { $arguments += @("--quiet", "--tuples-only", "--no-align") }
        $output = @($Sql | & $script:PsqlPath @arguments 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "psql failed for database '$Database': $($output -join [Environment]::NewLine)"
        }
        if (!$Scalar) { return }
        $lines = @($output | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ })
        if ($lines.Count -eq 0) { throw "psql returned no scalar value." }
        return $lines[-1]
    }
    finally {
        $env:PGPASSWORD = $previousPassword
    }
}

function Test-DatabaseLogin {
    param([string]$Database, [string]$User, [string]$Password)

    try {
        return (Invoke-Psql -Sql "SELECT 1;" -Database $Database -User $User `
            -Password $Password -Scalar) -eq "1"
    }
    catch { return $false }
}

function Wait-BmaHealth {
    param([string]$Url, [int]$Seconds)

    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    $lastError = "No response"
    do {
        try {
            $result = Invoke-RestMethod -Uri $Url -TimeoutSec 5
            if ($result.ok -eq $true) { return $result }
            $lastError = "Response did not contain ok=true"
        }
        catch { $lastError = $_.Exception.Message }
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Health check failed for '$Url': $lastError"
}

function Test-PackageChecksums {
    param([string]$Root)

    $manifest = Get-ChildItem -Path $Root -Filter "SHA256SUMS.txt" -Recurse |
        Select-Object -First 1
    if (!$manifest) { throw "Native package has no SHA256SUMS.txt manifest." }
    foreach ($line in Get-Content -LiteralPath $manifest.FullName) {
        if (!$line.Trim()) { continue }
        if ($line -notmatch '^([a-fA-F0-9]{64})\s+\*?(.+)$') {
            throw "Invalid checksum manifest line: $line"
        }
        $expected = $Matches[1].ToUpperInvariant()
        $relativePath = $Matches[2].Trim().Replace('/', '\')
        $file = Join-Path $manifest.DirectoryName $relativePath
        if (!(Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "Package file missing: $relativePath"
        }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash -ne $expected) {
            throw "Package checksum failed: $relativePath"
        }
    }
}

function Invoke-Sc {
    param([string[]]$Arguments)

    & sc.exe @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "sc.exe failed: $($Arguments -join ' ')"
    }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run PowerShell as Administrator."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if (!$EnvFile) {
    $EnvFile = if ($Target -eq "Staging") { ".env.staging" } else { ".env.production" }
}
$resolvedEnvFile = if ([IO.Path]::IsPathRooted($EnvFile)) {
    $EnvFile
} else {
    Join-Path $repoRoot $EnvFile
}
if (!(Test-Path -LiteralPath $resolvedEnvFile -PathType Leaf)) {
    throw "Environment file not found: $resolvedEnvFile"
}

$targetDefaults = if ($Target -eq "Staging") {
    @{
        ServiceName = "BMA-Staging"
        DisplayName = "BMA Staging API"
        Port = 8791
        PathBase = "/bmapp-staging"
        Database = "binhminh_data_staging"
        User = "bma_staging_runtime"
        Migrate = $true
    }
} else {
    @{
        ServiceName = "BMA-Production"
        DisplayName = "BMA Production API"
        Port = 8790
        PathBase = "/bmapp"
        Database = "binhminh_data"
        User = "bma_runtime"
        Migrate = $false
    }
}

$configuredPort = [int](Get-DotEnvValue -Path $resolvedEnvFile -Name "BMA_HOST_PORT" `
    -Default $targetDefaults.Port)
$configuredPathBase = Get-DotEnvValue -Path $resolvedEnvFile -Name "BMA_PATH_BASE" `
    -Default $targetDefaults.PathBase
if ($configuredPort -ne $targetDefaults.Port -or $configuredPathBase -ne $targetDefaults.PathBase) {
    throw "Safety stop: $Target must use port $($targetDefaults.Port) and path $($targetDefaults.PathBase)."
}

$script:DatabaseHost = Get-DotEnvValue -Path $resolvedEnvFile -Name "BMA_DB_HOST" -Default "127.0.0.1"
$script:DatabasePort = Get-DotEnvValue -Path $resolvedEnvFile -Name "BMA_DB_PORT" -Default "5432"
$databaseName = Get-DotEnvValue -Path $resolvedEnvFile -Name "BMA_DB_NAME" -Default $targetDefaults.Database
$databaseUser = Get-DotEnvValue -Path $resolvedEnvFile -Name "BMA_DB_USER" -Default $targetDefaults.User
$databasePassword = Get-DotEnvValue -Path $resolvedEnvFile -Name "BMA_DB_PASSWORD"
if (!$databasePassword) {
    $databasePassword = Get-DotEnvValue -Path $resolvedEnvFile -Name "BMA_NATIVE_DB_PASSWORD"
}
if (!$databasePassword) {
    $databasePassword = Get-DotEnvValue -Path $resolvedEnvFile -Name "POSTGRES_PASSWORD"
}
if (!$databasePassword -or $databasePassword -like "*CHANGE_ME*") {
    throw "BMA_DB_PASSWORD is missing or still uses a placeholder in $resolvedEnvFile."
}
$jwtKey = Get-RequiredEnvValue -Path $resolvedEnvFile -Name "BMA_JWT_SIGNING_KEY"
$gatewayKey = Get-RequiredEnvValue -Path $resolvedEnvFile -Name "BMA_GATEWAY_INBOUND_KEY"
$bootstrapUser = Get-DotEnvValue -Path $resolvedEnvFile -Name "BMA_BOOTSTRAP_ADMIN_USERNAME"
$bootstrapPassword = Get-DotEnvValue -Path $resolvedEnvFile -Name "BMA_BOOTSTRAP_ADMIN_PASSWORD"
$allowedHosts = Get-DotEnvValue -Path $resolvedEnvFile -Name "BMA_ALLOWED_HOSTS" `
    -Default "gateway.redtigerhead.com;localhost;127.0.0.1"

foreach ($identifier in @($databaseName, $databaseUser)) {
    if ($identifier -notmatch "^[A-Za-z0-9_]+$") {
        throw "Database names and users may contain only letters, numbers, and underscore."
    }
}
if ($Target -eq "Staging" -and $databaseName -eq "binhminh_data") {
    throw "Safety stop: staging cannot use production database binhminh_data."
}
if ($Target -eq "Production" -and $databaseName -ne "binhminh_data") {
    throw "Safety stop: production must use binhminh_data."
}

$script:PsqlPath = Join-Path $PostgresBin "psql.exe"
if (!(Test-Path -LiteralPath $script:PsqlPath -PathType Leaf)) {
    $psqlCommand = Get-Command psql.exe -ErrorAction SilentlyContinue
    if (!$psqlCommand) { throw "psql.exe not found. Expected: $script:PsqlPath" }
    $script:PsqlPath = $psqlCommand.Source
}

if (!(Test-DatabaseLogin -Database $databaseName -User $databaseUser -Password $databasePassword)) {
    if ($Target -ne "Staging") {
        throw "Production database login failed. No automatic production provisioning performed."
    }

    Write-Host "Native staging database needs provisioning." -ForegroundColor Yellow
    $adminPassword = Get-PlainText (Read-Host "PostgreSQL postgres password" -AsSecureString)
    try {
        if (!(Test-DatabaseLogin -Database "postgres" -User "postgres" -Password $adminPassword)) {
            throw "PostgreSQL administrator login failed."
        }

        $roleExists = Invoke-Psql -Sql "SELECT count(*) FROM pg_roles WHERE rolname = '$databaseUser';" `
            -Database "postgres" -User "postgres" -Password $adminPassword -Scalar
        $escapedPassword = $databasePassword.Replace("'", "''")
        if ($roleExists -eq "0") {
            Invoke-Psql -Sql "CREATE ROLE `"$databaseUser`" LOGIN PASSWORD '$escapedPassword';" `
                -Database "postgres" -User "postgres" -Password $adminPassword
        } else {
            Invoke-Psql -Sql "ALTER ROLE `"$databaseUser`" LOGIN PASSWORD '$escapedPassword';" `
                -Database "postgres" -User "postgres" -Password $adminPassword
        }

        $databaseExists = Invoke-Psql -Sql "SELECT count(*) FROM pg_database WHERE datname = '$databaseName';" `
            -Database "postgres" -User "postgres" -Password $adminPassword -Scalar
        if ($databaseExists -eq "0") {
            Invoke-Psql -Sql "CREATE DATABASE `"$databaseName`" OWNER `"$databaseUser`";" `
                -Database "postgres" -User "postgres" -Password $adminPassword
        }
    }
    finally { $adminPassword = $null }

    if (!(Test-DatabaseLogin -Database $databaseName -User $databaseUser -Password $databasePassword)) {
        throw "Native staging database provisioning did not produce a working runtime login."
    }
}
Write-Host "[1/5] Native PostgreSQL: PASS" -ForegroundColor Green

$serviceRoot = Join-Path $InstallRoot $targetDefaults.ServiceName
$releaseName = (Get-Date -Format "yyyyMMdd-HHmmss") + "-" + `
    [Guid]::NewGuid().ToString("N").Substring(0, 6)
try {
    $shortCommit = (& git -C $repoRoot rev-parse --short HEAD 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -eq 0 -and $shortCommit) { $releaseName += "-$shortCommit" }
} catch {}
$releaseRoot = Join-Path (Join-Path $serviceRoot "releases") $releaseName
$keysRoot = Join-Path $serviceRoot "data-protection"
New-Item -ItemType Directory -Force -Path $releaseRoot, $keysRoot | Out-Null

if ($PackagePath) {
    $resolvedPackage = (Resolve-Path $PackagePath).Path
    if (Test-Path $resolvedPackage -PathType Container) {
        Copy-Item (Join-Path $resolvedPackage "*") $releaseRoot -Recurse -Force
    } elseif ([IO.Path]::GetExtension($resolvedPackage) -eq ".zip") {
        Expand-Archive -LiteralPath $resolvedPackage -DestinationPath $releaseRoot -Force
    } else {
        throw "PackagePath must be a directory or ZIP file."
    }
    Test-PackageChecksums -Root $releaseRoot
} else {
    if (!(Get-Command dotnet -ErrorAction SilentlyContinue)) {
        throw "No native package supplied and .NET SDK was not found."
    }
    & dotnet publish (Join-Path $repoRoot "backend\src\Bma.Api\Bma.Api.csproj") `
        --configuration Release --runtime win-x64 --self-contained true `
        --output $releaseRoot /p:PublishSingleFile=false
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed." }
}

$appExe = Get-ChildItem -Path $releaseRoot -Filter "Bma.Api.exe" -Recurse | Select-Object -First 1
if (!$appExe) { throw "Bma.Api.exe not found in native package." }
if ($appExe.DirectoryName -ne $releaseRoot) {
    $nestedRoot = $appExe.DirectoryName
    Copy-Item (Join-Path $nestedRoot "*") $releaseRoot -Recurse -Force
    $appExe = Get-Item (Join-Path $releaseRoot "Bma.Api.exe")
}

$connectionString = @(
    "Host=$(ConvertTo-ConnectionStringValue $script:DatabaseHost)"
    "Port=$($script:DatabasePort)"
    "Database=$(ConvertTo-ConnectionStringValue $databaseName)"
    "Username=$(ConvertTo-ConnectionStringValue $databaseUser)"
    "Password=$(ConvertTo-ConnectionStringValue $databasePassword)"
    "Include Error Detail=false"
) -join ";"
$config = [ordered]@{
    Urls = "http://127.0.0.1:$configuredPort"
    AllowedHosts = $allowedHosts
    App = @{ PathBase = $configuredPathBase }
    ConnectionStrings = @{ Bma = $connectionString }
    Database = @{
        MigrateOnStartup = $targetDefaults.Migrate
        Deployment = "postgresql-native"
    }
    Runtime = @{ Mode = "windows-service" }
    Service = @{ Name = $targetDefaults.ServiceName }
    DataProtection = @{ KeysPath = $keysRoot }
    Jwt = @{ SigningKey = $jwtKey }
    Gateway = @{ InboundKey = $gatewayKey }
    BMA_BOOTSTRAP_ADMIN_USERNAME = $bootstrapUser
    BMA_BOOTSTRAP_ADMIN_PASSWORD = $bootstrapPassword
}
$configPath = Join-Path $releaseRoot "appsettings.Production.json"
$config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configPath -Encoding UTF8
Write-Host "[2/5] Native release prepared: $releaseName" -ForegroundColor Green

$serviceName = $targetDefaults.ServiceName
$existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
$previousPath = $null
$previousWasRunning = $false
if ($existingService) {
    $serviceInfo = Get-CimInstance Win32_Service -Filter "Name='$serviceName'"
    $previousPath = $serviceInfo.PathName
    $previousWasRunning = $existingService.Status -eq "Running"
    if ($existingService.Status -ne "Stopped") {
        Stop-Service -Name $serviceName -Force
        (Get-Service -Name $serviceName).WaitForStatus("Stopped", [TimeSpan]::FromSeconds(30))
    }
}
$listeners = @(Get-NetTCPConnection -LocalPort $configuredPort -State Listen `
    -ErrorAction SilentlyContinue)
if ($listeners.Count -gt 0) {
    $owners = ($listeners | Select-Object -ExpandProperty OwningProcess -Unique) -join ","
    if ($previousWasRunning) { Start-Service -Name $serviceName }
    throw "Port $configuredPort is already owned by process $owners."
}
if (!$existingService) {
    New-Service -Name $serviceName -BinaryPathName ('"{0}"' -f $appExe.FullName) `
        -DisplayName $targetDefaults.DisplayName -StartupType Automatic | Out-Null
}

try {
    Invoke-Sc @("config", $serviceName, "binPath=", ('"{0}"' -f $appExe.FullName), `
        "start=", "delayed-auto", "obj=", "NT SERVICE\$serviceName", "password=", "")
    Invoke-Sc @("failure", $serviceName, "reset=", "86400", "actions=", `
        "restart/5000/restart/15000/restart/30000")

    & icacls.exe $releaseRoot /inheritance:r /grant:r `
        "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" `
        "NT SERVICE\${serviceName}:(OI)(CI)RX" /T /C | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to protect native release ACL." }
    & icacls.exe $keysRoot /inheritance:r /grant:r `
        "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" `
        "NT SERVICE\${serviceName}:(OI)(CI)M" /T /C | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to protect Data Protection key ACL." }

    Start-Service -Name $serviceName
    $localHealthUrl = "http://127.0.0.1:$configuredPort$configuredPathBase/health/details"
    $health = Wait-BmaHealth -Url $localHealthUrl -Seconds $TimeoutSeconds
    if ($health.runtime -ne "windows-service" -or $health.database -ne "postgresql-native") {
        throw "Health endpoint does not confirm the native runtime."
    }
    Write-Host "[3/5] Windows Service: PASS" -ForegroundColor Green
    Write-Host "[4/5] Local health: PASS" -ForegroundColor Green
}
catch {
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    if ($previousPath) {
        Invoke-Sc @("config", $serviceName, "binPath=", $previousPath)
        if ($previousWasRunning) { Start-Service -Name $serviceName }
    }
    throw
}

$service = Get-CimInstance Win32_Service -Filter "Name='$serviceName'"
Write-Host "[5/5] Native deployment complete" -ForegroundColor Green
[PSCustomObject]@{
    Result = "PASS"
    Target = $Target
    Service = $serviceName
    ServiceState = $service.State
    Runtime = $health.runtime
    DatabaseDeployment = $health.database
    DatabaseName = $databaseName
    LocalUrl = $localHealthUrl
    Release = $releaseName
}

$databasePassword = $null
$jwtKey = $null
$gatewayKey = $null
$bootstrapPassword = $null
