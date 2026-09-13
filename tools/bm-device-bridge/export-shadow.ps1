$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$outputPath = Join-Path $scriptRoot "data\shadow-sample.json"

$sample = Invoke-RestMethod `
    -Uri "http://127.0.0.1:8789/diagnostics/recent?limit=5" `
    -Method Get

$sample | ConvertTo-Json -Depth 30 | Set-Content -Path $outputPath -Encoding UTF8
Write-Host "Da xuat mau callback: $outputPath" -ForegroundColor Green
Write-Host "File co the chua ma nhan vien/du lieu Terminal. Chi gui qua kenh du an tin cay." -ForegroundColor Yellow
