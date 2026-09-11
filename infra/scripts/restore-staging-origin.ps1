param(
    [string]$EnvFile = ".env.staging",
    [string]$ProjectName = "bma-staging",
    [string]$PublicBaseUrl = "https://gateway.redtigerhead.com/bmapp-staging",
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"

function Get-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    foreach ($rawLine in Get-Content -LiteralPath $Path) {
        $line = $rawLine.Trim()
        if (!$line -or $line.StartsWith("#")) { continue }
        $parts = $line -split "=", 2
        if ($parts.Count -ne 2 -or $parts[0].Trim() -ne $Name) { continue }
        return $parts[1].Trim().Trim('"').Trim("'")
    }
    return $null
}

function Wait-BmaHealth {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][int]$Seconds
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    $lastError = $null
    do {
        try {
            $result = Invoke-RestMethod -Uri $Url -TimeoutSec 8
            if ($result.ok -eq $true) { return $result }
            $lastError = "Health response did not contain ok=true."
        }
        catch {
            $lastError = $_.Exception.Message
        }
        Start-Sleep -Seconds 3
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Health check failed for '$Url': $lastError"
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$resolvedEnvFile = if ([System.IO.Path]::IsPathRooted($EnvFile)) {
    $EnvFile
} else {
    Join-Path $repoRoot $EnvFile
}

if (!(Test-Path -LiteralPath $resolvedEnvFile -PathType Leaf)) {
    throw "Staging environment file not found: $resolvedEnvFile"
}
if (!(Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker CLI was not found. Start Docker Desktop, then retry."
}
if ($ProjectName -ne "bma-staging") {
    throw "Safety stop: ProjectName must be 'bma-staging'."
}

$hostPort = Get-DotEnvValue -Path $resolvedEnvFile -Name "BMA_HOST_PORT"
$pathBase = Get-DotEnvValue -Path $resolvedEnvFile -Name "BMA_PATH_BASE"
if ($hostPort -ne "8791") {
    throw "Safety stop: BMA_HOST_PORT must be 8791 in the staging env file."
}
if ($pathBase -ne "/bmapp-staging") {
    throw "Safety stop: BMA_PATH_BASE must be /bmapp-staging in the staging env file."
}

$compose = @("compose", "--project-name", $ProjectName, "--env-file", $resolvedEnvFile)
$localHealthUrl = "http://127.0.0.1:8791/bmapp-staging/health/details"
$publicHealthUrl = $PublicBaseUrl.TrimEnd("/") + "/health/details"

Push-Location $repoRoot
try {
    & docker info *> $null
    if ($LASTEXITCODE -ne 0) { throw "Docker Desktop is not running." }

    Write-Host "[1/4] Validate isolated staging Compose configuration" -ForegroundColor Cyan
    & docker @compose config --quiet
    if ($LASTEXITCODE -ne 0) { throw "docker compose config failed." }

    Write-Host "[2/4] Build and start origin 127.0.0.1:8791" -ForegroundColor Cyan
    & docker @compose up -d --build
    if ($LASTEXITCODE -ne 0) { throw "docker compose up failed." }

    Write-Host "[3/4] Verify local origin" -ForegroundColor Cyan
    $local = Wait-BmaHealth -Url $localHealthUrl -Seconds $TimeoutSeconds
    if ($local.supported_event_types -notcontains "EMPLOYEE_SCAN") {
        throw "Local BMA does not advertise EMPLOYEE_SCAN."
    }

    Write-Host "[4/4] Verify public Cloudflare route" -ForegroundColor Cyan
    try {
        $public = Wait-BmaHealth -Url $publicHealthUrl -Seconds $TimeoutSeconds
    }
    catch {
        Write-Host "Local origin is healthy; public route is still unavailable." -ForegroundColor Yellow
        Write-Host "Check that the RedTiger tunnel route targets http://localhost:8791." -ForegroundColor Yellow
        & docker @compose ps
        throw
    }

    [PSCustomObject]@{
        Result = "PASS"
        Project = $ProjectName
        LocalUrl = $localHealthUrl
        LocalVersion = $local.version
        PublicUrl = $publicHealthUrl
        PublicVersion = $public.version
        EmployeeScan = ($public.supported_event_types -contains "EMPLOYEE_SCAN")
    } | Format-List
}
finally {
    Pop-Location
}
