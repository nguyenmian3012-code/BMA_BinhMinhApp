param(
    [string]$EnvFile = ".env.staging",
    [string]$InstallRoot = "C:\ABMT\BMA-Services",
    [string]$PackagePath = "",
    [string]$PostgresBin = "C:\Program Files\PostgreSQL\17\bin",
    [string]$PublicBaseUrl = "https://gateway.redtigerhead.com/bmapp-staging",
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"

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
$nativeDeploy = Join-Path $PSScriptRoot "deploy-native-bma-service.ps1"
$publicHealthUrl = $PublicBaseUrl.TrimEnd("/") + "/health/details"

Push-Location $repoRoot
try {
    $arguments = @(
        "-Target", "Staging",
        "-EnvFile", $EnvFile,
        "-InstallRoot", $InstallRoot,
        "-PostgresBin", $PostgresBin,
        "-TimeoutSeconds", $TimeoutSeconds
    )
    if ($PackagePath) { $arguments += @("-PackagePath", $PackagePath) }
    & $nativeDeploy @arguments

    Write-Host "Verify public Cloudflare route" -ForegroundColor Cyan
    try {
        $public = Wait-BmaHealth -Url $publicHealthUrl -Seconds $TimeoutSeconds
    }
    catch {
        Write-Host "Local origin is healthy; public route is still unavailable." -ForegroundColor Yellow
        Write-Host "Check that the RedTiger tunnel route targets http://localhost:8791." -ForegroundColor Yellow
        Get-Service BMA-Staging, cloudflared -ErrorAction SilentlyContinue |
            Format-Table Name, Status, StartType
        throw
    }
    if ($public.runtime -ne "windows-service" -or $public.database -ne "postgresql-native" -or
        $public.supported_event_types -notcontains "EMPLOYEE_SCAN") {
        throw "Public endpoint does not expose the expected native BMA runtime."
    }

    [PSCustomObject]@{
        Result = "PASS"
        Service = "BMA-Staging"
        PublicUrl = $publicHealthUrl
        PublicVersion = $public.version
        Runtime = $public.runtime
        Database = $public.database
        EmployeeScan = ($public.supported_event_types -contains "EMPLOYEE_SCAN")
    } | Format-List
}
finally {
    Pop-Location
}
