# i2tn - FTSC11 factory package: one-command install + flash (Windows).
# (c) 2026 i2tn - https://github.com/i2tn
# Run in PowerShell:
#   irm https://raw.githubusercontent.com/i2tn/ftsc11-factory/main/install.ps1 | iex
# Downloads the package to %USERPROFILE%\ftsc11-factory and starts the
# interactive flasher. Re-running it updates the package.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repo = 'https://github.com/i2tn/ftsc11-factory'
$dest = Join-Path $env:USERPROFILE 'ftsc11-factory'

Write-Host ''
Write-Host 'i2tn - FTSC11 factory package' -ForegroundColor Cyan
Write-Host 'Downloading...' -ForegroundColor Cyan
$zip = Join-Path $env:TEMP 'ftsc11-factory.zip'
Invoke-WebRequest -UseBasicParsing -Uri "$repo/archive/refs/heads/main.zip" -OutFile $zip

$tmp = Join-Path $env:TEMP ('ftsc11-unzip-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
Expand-Archive -Path $zip -DestinationPath $tmp -Force
# Keep one rolling backup instead of deleting outright: operators keep test
# records and a filled-in wifi.conf in this folder, and re-running the install
# command to update used to wipe them without asking.
$backup = "$dest.previous"
if (Test-Path $dest) {
    if (Test-Path $backup) { Remove-Item $backup -Recurse -Force }
    Move-Item $dest $backup
    Write-Host "Previous install kept at $backup" -ForegroundColor DarkGray
}
Move-Item (Join-Path $tmp 'ftsc11-factory-main') $dest

# Carry a filled-in wifi.conf across; the shipped one is a blank template.
$oldConf = Join-Path $backup 'wifi.conf'
if (Test-Path $oldConf) {
    # Any filled-in setting counts, not just WIFI_SSID: deploy.py also accepts
    # an MQTT-only or DEVICE_ID-only file, and deleting one of those without
    # carrying it forward would destroy the operator's settings.
    if (Select-String -Path $oldConf -Pattern '^\s*[A-Za-z_]+=.+' -Quiet) {
        Copy-Item $oldConf (Join-Path $dest 'wifi.conf') -Force
        Write-Host "Kept your existing wifi.conf." -ForegroundColor DarkGray
    }
    # Credentials in clear text: keep exactly one copy — the live one — rather
    # than accumulating them in every rolling backup.
    Remove-Item $oldConf -Force
}
Remove-Item $zip -Force
Remove-Item $tmp -Recurse -Force
Get-ChildItem $dest -Recurse | Unblock-File -ErrorAction SilentlyContinue

Write-Host "Installed to $dest" -ForegroundColor Green
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest 'flash.ps1')
