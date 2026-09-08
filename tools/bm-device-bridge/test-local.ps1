$ErrorActionPreference = "Stop"

$heartbeat = Invoke-WebRequest `
    -Uri "http://127.0.0.1:8789/Subscribe/heartbeat" `
    -Method Post `
    -ContentType "application/json" `
    -Body '{"deviceId":"1605063","status":"online","source":"local-test"}'

$event = Invoke-WebRequest `
    -Uri "http://127.0.0.1:8789/Subscribe/verify" `
    -Method Post `
    -ContentType "application/json" `
    -Body '{"deviceId":"1605063","personId":"TEST-001","source":"local-test"}'

$health = Invoke-RestMethod -Uri "http://127.0.0.1:8789/health"

if ($heartbeat.Content -ne "OK" -or $event.Content -ne "OK") {
    throw "Bridge khong tra ve OK."
}

$health | Format-List
Write-Host "PASS: listener va SQLite hoat dong; xem gatewayEnabled trong health." -ForegroundColor Green
