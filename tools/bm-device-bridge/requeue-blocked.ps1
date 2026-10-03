$ErrorActionPreference = "Stop"

$result = Invoke-RestMethod `
    -Uri "http://127.0.0.1:8789/control/requeue-blocked" `
    -Method Post

$result | Format-List
Write-Host "Da dua cac su kien blocked ve hang doi. Bridge se thu lai theo cau hinh hien tai." -ForegroundColor Green
