param(
    [Parameter(Mandatory = $true)][string]$Database,
    [Parameter(Mandatory = $true)][string]$User,
    [string]$HostName = "localhost",
    [string]$OutputDirectory = ".\backups"
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$file = Join-Path $OutputDirectory "bma-$timestamp.dump"
& pg_dump --host $HostName --username $User --format custom --file $file $Database
if ($LASTEXITCODE -ne 0) { throw "pg_dump failed with exit code $LASTEXITCODE" }
$hash = Get-FileHash -Algorithm SHA256 $file
"$($hash.Hash)  $($hash.Path)" | Set-Content "$file.sha256"
Write-Host "Backup created: $file"
