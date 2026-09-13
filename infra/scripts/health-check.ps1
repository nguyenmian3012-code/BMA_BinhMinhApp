param(
    [string]$BaseUrl = "http://localhost:8790",
    [string]$PathBase = "/bmapp"
)

$ErrorActionPreference = "Stop"
$normalizedPathBase = "/" + $PathBase.Trim("/")
$health = Invoke-RestMethod -Uri "$BaseUrl$normalizedPathBase/health" -TimeoutSec 10
Write-Host "BMA health: $health"

$admin = Invoke-WebRequest -Uri "$BaseUrl$normalizedPathBase/admin/login" -TimeoutSec 10 -UseBasicParsing
if ($admin.StatusCode -ne 200) {
    throw "Admin login returned HTTP $($admin.StatusCode)"
}
Write-Host "BMA Admin login: HTTP 200"

$css = Invoke-WebRequest -Uri "$BaseUrl$normalizedPathBase/css/admin.css" -TimeoutSec 10 -UseBasicParsing
if ($css.StatusCode -ne 200) {
    throw "Admin stylesheet returned HTTP $($css.StatusCode)"
}
Write-Host "BMA Admin stylesheet: HTTP 200"
