# i2tn — FTSC11 factory package: one-command install + flash (Windows).
# (c) 2026 i2tn · https://github.com/i2tn
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
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
Move-Item (Join-Path $tmp 'ftsc11-factory-main') $dest
Remove-Item $zip -Force
Remove-Item $tmp -Recurse -Force
Get-ChildItem $dest -Recurse | Unblock-File -ErrorAction SilentlyContinue

Write-Host "Installed to $dest" -ForegroundColor Green
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest 'flash.ps1')
