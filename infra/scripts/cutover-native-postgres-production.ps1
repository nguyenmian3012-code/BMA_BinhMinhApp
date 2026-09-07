[CmdletBinding()]
param(
    [string]$NativeDatabase = 'binhminh_data',
    [string]$NativeAdminUser = 'postgres',
    [int]$NativePort = 5432,
    [int]$BmaHostPort = 8790,
    [string]$NewContainerName = 'bma-native-production'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run PowerShell as Administrator for the production cutover.'
    }
}

function Find-PostgresTool([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $base = 'C:\Program Files\PostgreSQL'
    $items = @()
    if (Test-Path $base) {
        $items = @(Get-ChildItem $base -Directory | ForEach-Object {
            $p = Join-Path $_.FullName "bin\$Name.exe"
            if (Test-Path $p) { [pscustomobject]@{ Path=$p; Version=$_.Name } }
        } | Sort-Object { try { [version]$_.Version } catch { [version]'0.0' } } -Descending)
    }
    if ($items.Count -eq 0) { throw "$Name.exe was not found." }
    return $items[0].Path
}

function Get-EnvMapFromContainer([string]$ContainerId) {
    $obj = (docker inspect $ContainerId | ConvertFrom-Json)[0]
    $map = @{}
    foreach ($line in @($obj.Config.Env)) {
        $i = $line.IndexOf('=')
        if ($i -gt 0) { $map[$line.Substring(0,$i)] = $line.Substring($i+1) }
    }
    return $map
}

function Invoke-NativePsql([string]$Sql, [switch]$TuplesOnly) {
    $args = @('-X','-v','ON_ERROR_STOP=1','-h','127.0.0.1','-p',"$NativePort",'-U',$NativeAdminUser,'-d',$NativeDatabase)
    if ($TuplesOnly) { $args += @('-tA') }
    $args += @('-c',$Sql)
    $out = & $script:Psql @args
    if ($LASTEXITCODE -ne 0) { throw "psql failed (exit $LASTEXITCODE)." }
    return $out
}

function Stream-PublicSchema([string]$PgContainer,[string]$SourceUser,[string]$SourceDb) {
    Write-Host 'Streaming BMA public schema directly into native PostgreSQL (no backup artifact)...' -ForegroundColor Yellow

    $dump = New-Object System.Diagnostics.Process
    $dump.StartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $dump.StartInfo.FileName = 'docker.exe'
    $dump.StartInfo.Arguments = "exec $PgContainer pg_dump -U $SourceUser -d $SourceDb --schema=public --no-owner --no-privileges --format=plain"
    $dump.StartInfo.UseShellExecute = $false
    $dump.StartInfo.RedirectStandardOutput = $true
    $dump.StartInfo.RedirectStandardError = $false
    $dump.StartInfo.CreateNoWindow = $true

    $restore = New-Object System.Diagnostics.Process
    $restore.StartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $restore.StartInfo.FileName = $script:Psql
    $restore.StartInfo.Arguments = "-X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p $NativePort -U $NativeAdminUser -d $NativeDatabase"
    $restore.StartInfo.UseShellExecute = $false
    $restore.StartInfo.RedirectStandardInput = $true
    $restore.StartInfo.RedirectStandardError = $false
    $restore.StartInfo.CreateNoWindow = $true

    [void]$restore.Start()
    [void]$dump.Start()
    $dump.StandardOutput.BaseStream.CopyTo($restore.StandardInput.BaseStream)
    $restore.StandardInput.Close()
    $dump.WaitForExit()
    $restore.WaitForExit()

    if ($dump.ExitCode -ne 0) { throw "pg_dump failed (exit $($dump.ExitCode))." }
    if ($restore.ExitCode -ne 0) { throw "native restore failed (exit $($restore.ExitCode))." }
}

function Get-DockerHostSubnet {
    $bridge = (docker network inspect bridge --format '{{(index .IPAM.Config 0).Subnet}}' 2>$null | Out-String).Trim()
    if (-not $bridge) { $bridge = '172.16.0.0/12' }

    $hostLine = (docker run --rm postgres:17-alpine getent hosts host.docker.internal 2>$null | Select-Object -First 1)
    $hostSubnet = '192.168.65.0/24'
    if ($hostLine -match '^\s*(\d+)\.(\d+)\.(\d+)\.(\d+)') {
        $hostSubnet = "$($matches[1]).$($matches[2]).$($matches[3]).0/24"
    }
    return @($bridge,$hostSubnet | Select-Object -Unique)
}

function Write-SecureComposeEnv([hashtable]$AppEnv,[string]$RuntimePassword) {
    $dir = 'C:\ProgramData\ABMT\BMA'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $path = Join-Path $dir 'bma-native-production.env'

    $lines = @(
        "BMA_JWT_SIGNING_KEY=$($AppEnv['Jwt__SigningKey'])",
        "BMA_GATEWAY_INBOUND_KEY=$($AppEnv['Gateway__InboundKey'])",
        "BMA_BOOTSTRAP_ADMIN_USERNAME=$($AppEnv['BMA_BOOTSTRAP_ADMIN_USERNAME'])",
        "BMA_BOOTSTRAP_ADMIN_PASSWORD=$($AppEnv['BMA_BOOTSTRAP_ADMIN_PASSWORD'])",
        "BMA_ALLOWED_HOSTS=$($AppEnv['AllowedHosts'])",
        "BMA_PATH_BASE=$($AppEnv['App__PathBase'])",
        "BMA_HOST_PORT=$BmaHostPort",
        "BMA_NATIVE_DB_PASSWORD=$RuntimePassword"
    )
    [IO.File]::WriteAllLines($path, $lines, (New-Object Text.UTF8Encoding($false)))
    try {
        & icacls $path '/inheritance:r' '/grant:r' "$env:USERNAME`:F" '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
    } catch {
        Write-Warning "Could not harden ACL on $path automatically: $($_.Exception.Message)"
    }
    return $path
}

Assert-Administrator
$script:Psql = Find-PostgresTool 'psql'
$postgresService = Get-Service | Where-Object { $_.Name -like 'postgresql*x64*17*' -or $_.Name -eq 'postgresql-x64-17' } | Select-Object -First 1
if (-not $postgresService) { throw 'PostgreSQL 17 Windows service was not found.' }
if ($postgresService.Status -ne 'Running') { Start-Service $postgresService.Name }

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker CLI was not found.' }
docker info *> $null
if ($LASTEXITCODE -ne 0) { throw 'Docker engine is not running.' }

Write-Host '=== BMA direct production cutover -> native binhminh_data ===' -ForegroundColor Cyan
Write-Host 'Mode: direct stream, no backup checkpoint.' -ForegroundColor Yellow

$bmaIds = @(docker ps -q --filter "publish=$BmaHostPort")
if ($bmaIds.Count -eq 0) {
    $bmaIds = @(docker ps -q --filter 'label=com.docker.compose.service=bma')
}
$bmaIds = @($bmaIds | Where-Object { $_ })
if ($bmaIds.Count -ne 1) { throw "Expected exactly one running production BMA container; found $($bmaIds.Count)." }
$oldBma = $bmaIds[0]
$oldInfo = (docker inspect $oldBma | ConvertFrom-Json)[0]
$project = $oldInfo.Config.Labels.'com.docker.compose.project'
if (-not $project) { throw 'Could not identify the current BMA compose project.' }
Write-Host "Current BMA: $($oldInfo.Name.TrimStart('/')) / project=$project"

$pgIds = @(docker ps -q --filter "label=com.docker.compose.project=$project" --filter 'label=com.docker.compose.service=postgres')
if ($pgIds.Count -ne 1) { throw "Expected one running PostgreSQL container in project '$project'; found $($pgIds.Count)." }
$oldPg = $pgIds[0]
$pgEnv = Get-EnvMapFromContainer $oldPg
$sourceDb = $pgEnv['POSTGRES_DB']
$sourceUser = $pgEnv['POSTGRES_USER']
if ($sourceDb -notmatch '^[A-Za-z0-9_]+$' -or $sourceUser -notmatch '^[A-Za-z0-9_]+$') { throw 'Unsafe source DB/user name.' }
Write-Host "Source PostgreSQL container: $((docker inspect -f '{{.Name}}' $oldPg).TrimStart('/')) / db=$sourceDb / user=$sourceUser"

$appEnv = Get-EnvMapFromContainer $oldBma
foreach ($required in @('Jwt__SigningKey','Gateway__InboundKey','App__PathBase','AllowedHosts')) {
    if (-not $appEnv.ContainsKey($required) -or [string]::IsNullOrWhiteSpace($appEnv[$required])) {
        throw "Current BMA container does not expose required environment key: $required"
    }
}

$secureAdmin = Read-Host "Password for native PostgreSQL admin '$NativeAdminUser'" -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureAdmin)
$previousPgPassword = [Environment]::GetEnvironmentVariable('PGPASSWORD','Process')
$previousEncoding = [Environment]::GetEnvironmentVariable('PGCLIENTENCODING','Process')

try {
    $adminPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    $env:PGPASSWORD = $adminPassword
    $env:PGCLIENTENCODING = 'UTF8'

    $dbCheck = (& $script:Psql -X -tA -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$NativePort" -U $NativeAdminUser -d postgres -c "SELECT 1 FROM pg_database WHERE datname='$NativeDatabase';" | Out-String).Trim()
    if ($dbCheck -ne '1') { throw "Native database '$NativeDatabase' does not exist. Phase 1 is required first." }

    $already = (Invoke-NativePsql "SELECT CASE WHEN to_regclass('public.\"__EFMigrationsHistory\"') IS NULL THEN 0 ELSE 1 END;" -TuplesOnly | Out-String).Trim()
    if ($already -eq '1') { throw 'Target public schema already contains BMA EF migration history; refusing a duplicate direct import.' }

    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $rng.Dispose()
    $runtimePassword = [Convert]::ToBase64String($bytes)

    $roleExists = (Invoke-NativePsql "SELECT 1 FROM pg_roles WHERE rolname='bma_runtime';" -TuplesOnly | Out-String).Trim()
    if ($roleExists -ne '1') { [void](Invoke-NativePsql 'CREATE ROLE bma_runtime LOGIN;') }
    [void](Invoke-NativePsql "ALTER ROLE bma_runtime LOGIN PASSWORD '$runtimePassword';")
    [void](Invoke-NativePsql "GRANT CONNECT ON DATABASE $NativeDatabase TO bma_runtime;")

    $hba = (Invoke-NativePsql 'SHOW hba_file;' -TuplesOnly | Out-String).Trim()
    if (-not (Test-Path $hba)) { throw "pg_hba.conf not found: $hba" }
    $subnets = @(Get-DockerHostSubnet)
    $existingHba = Get-Content $hba -Raw
    foreach ($subnet in $subnets) {
        $line = "host    $NativeDatabase    bma_runtime    $subnet    scram-sha-256"
        if ($existingHba -notmatch [regex]::Escape($line)) { Add-Content -Path $hba -Value $line -Encoding ASCII }
    }
    [void](Invoke-NativePsql "ALTER SYSTEM SET listen_addresses='*';")

    $fwName = 'Binh Minh PostgreSQL - Docker Desktop'
    Get-NetFirewallRule -DisplayName $fwName -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $fwName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $NativePort -RemoteAddress $subnets -Profile Any | Out-Null

    Restart-Service $postgresService.Name
    Start-Sleep -Seconds 3

    $env:PGPASSWORD = $runtimePassword
    $networkTest = (docker run --rm -e PGPASSWORD postgres:17-alpine psql -h host.docker.internal -p "$NativePort" -U bma_runtime -d $NativeDatabase -tA -c 'SELECT 1;' | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $networkTest -ne '1') { throw 'Docker -> native PostgreSQL connectivity test failed.' }
    Write-Host 'Docker -> native PostgreSQL: PASS' -ForegroundColor Green

    $env:PGPASSWORD = $adminPassword
    Write-Host "Stopping current BMA container to freeze writes: $($oldInfo.Name.TrimStart('/'))"
    docker stop $oldBma | Out-Null

    try {
        Stream-PublicSchema -PgContainer $oldPg -SourceUser $sourceUser -SourceDb $sourceDb

        $migrationCount = (Invoke-NativePsql 'SELECT count(*) FROM public."__EFMigrationsHistory";' -TuplesOnly | Out-String).Trim()
        if (-not $migrationCount -or [int]$migrationCount -lt 1) { throw 'BMA EF migration history was not restored.' }
        Write-Host "EF migrations restored: $migrationCount" -ForegroundColor Green

        [void](Invoke-NativePsql 'GRANT USAGE ON SCHEMA public TO bma_runtime;')
        [void](Invoke-NativePsql 'GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO bma_runtime;')
        [void](Invoke-NativePsql 'GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO bma_runtime;')
        [void](Invoke-NativePsql 'GRANT bm_app_reader, bm_app_writer TO bma_runtime;')

        $composeEnvPath = Write-SecureComposeEnv -AppEnv $appEnv -RuntimePassword $runtimePassword
        Write-Host "Secure production env: $composeEnvPath"

        $runEnv = @{}
        foreach ($k in $appEnv.Keys) { $runEnv[$k] = $appEnv[$k] }
        $runEnv['ConnectionStrings__Bma'] = "Host=host.docker.internal;Port=$NativePort;Database=$NativeDatabase;Username=bma_runtime;Password=$runtimePassword;Include Error Detail=false"
        $runEnv['Database__MigrateOnStartup'] = 'false'

        $tempEnv = Join-Path $env:TEMP ("bma-cutover-{0}.env" -f [guid]::NewGuid().ToString('N'))
        $envLines = @($runEnv.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" })
        [IO.File]::WriteAllLines($tempEnv, $envLines, (New-Object Text.UTF8Encoding($false)))

        try {
            docker rm -f $NewContainerName 2>$null | Out-Null
            $image = $oldInfo.Image
            $dpMount = @($oldInfo.Mounts | Where-Object { $_.Destination -eq '/home/app/.aspnet/DataProtection-Keys' }) | Select-Object -First 1
            $args = @('run','-d','--name',$NewContainerName,'--restart','unless-stopped','-p',"127.0.0.1:$BmaHostPort`:8080",'--read-only','--tmpfs','/tmp','--add-host','host.docker.internal:host-gateway','--env-file',$tempEnv)
            if ($dpMount) {
                $mountSource = if ($dpMount.Type -eq 'volume') { $dpMount.Name } else { $dpMount.Source }
                $args += @('-v',"${mountSource}:/home/app/.aspnet/DataProtection-Keys")
            }
            $args += $image
            $newId = (& docker @args | Out-String).Trim()
            if ($LASTEXITCODE -ne 0 -or -not $newId) { throw 'Failed to start native-DB BMA container.' }
        }
        finally {
            Remove-Item $tempEnv -Force -ErrorAction SilentlyContinue
        }

        $healthUrl = "http://127.0.0.1:$BmaHostPort$($appEnv['App__PathBase'])/health"
        $healthy = $false
        for ($i=0; $i -lt 30; $i++) {
            Start-Sleep -Seconds 2
            try {
                $r = Invoke-WebRequest -UseBasicParsing -Uri $healthUrl -TimeoutSec 3
                if ($r.StatusCode -eq 200) { $healthy = $true; break }
            } catch {}
        }
        if (-not $healthy) { throw "New production BMA health check failed: $healthUrl" }

        Write-Host "BMA health: PASS ($healthUrl)" -ForegroundColor Green
        Write-Host 'Stopping legacy Docker PostgreSQL source; native PostgreSQL is now authoritative.' -ForegroundColor Yellow
        docker stop $oldPg | Out-Null

        Write-Host ''
        Write-Host 'PHASE 2 DIRECT PRODUCTION CUTOVER: PASS' -ForegroundColor Green
        Write-Host "BMA -> native PostgreSQL 17 / $NativeDatabase / bma_runtime"
        Write-Host "Production endpoint remains 127.0.0.1:$BmaHostPort; gateway routing does not need to change."
        Write-Host 'Legacy PostgreSQL volume was not deleted, but it is no longer active.'
    }
    catch {
        Write-Warning "Cutover failed: $($_.Exception.Message)"
        docker rm -f $NewContainerName 2>$null | Out-Null
        docker start $oldPg 2>$null | Out-Null
        docker start $oldBma 2>$null | Out-Null
        throw 'Automatic service rollback attempted; investigate before retrying.'
    }
}
finally {
    if ($null -eq $previousPgPassword) { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue } else { $env:PGPASSWORD = $previousPgPassword }
    if ($null -eq $previousEncoding) { Remove-Item Env:PGCLIENTENCODING -ErrorAction SilentlyContinue } else { $env:PGCLIENTENCODING = $previousEncoding }
    if ($ptr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    $adminPassword = $null
    $runtimePassword = $null
}
