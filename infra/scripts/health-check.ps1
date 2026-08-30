param(
    [string]$BaseUrl = "http://localhost:8790"
)

$ErrorActionPreference = "Stop"
$health = Invoke-RestMethod -Uri "$BaseUrl/bmapp/health" -TimeoutSec 10
Write-Host "BMA health: $health"

$admin = Invoke-WebRequest -Uri "$BaseUrl/bmapp/admin/login" -TimeoutSec 10 -UseBasicParsing
if ($admin.StatusCode -ne 200) {
    throw "Admin login returned HTTP $($admin.StatusCode)"
}
Write-Host "BMA Admin login: HTTP 200"
