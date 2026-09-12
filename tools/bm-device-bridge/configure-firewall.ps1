$ErrorActionPreference = "Stop"
$ruleName = "BM Device Bridge Shadow 8789"
$existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

if ($existing) {
    Set-NetFirewallRule -DisplayName $ruleName -Enabled True -Action Allow -Direction Inbound
    Set-NetFirewallAddressFilter -AssociatedNetFirewallRule $existing -RemoteAddress "192.168.1.227"
    Set-NetFirewallPortFilter -AssociatedNetFirewallRule $existing -Protocol TCP -LocalPort 8789
    Write-Host "Da cap nhat firewall: chi Terminal 192.168.1.227 duoc vao TCP 8789." -ForegroundColor Green
} else {
    New-NetFirewallRule `
        -DisplayName $ruleName `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalPort 8789 `
        -RemoteAddress "192.168.1.227" `
        -Profile Private | Out-Null
    Write-Host "Da tao firewall: chi Terminal 192.168.1.227 duoc vao TCP 8789." -ForegroundColor Green
}
