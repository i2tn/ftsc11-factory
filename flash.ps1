# i2tn — FTSC11 factory flasher. Interactive, no prerequisites (esptool.exe bundled).
# (c) 2026 i2tn · https://github.com/i2tn
# Windows PowerShell 5.1+. Started by install.ps1, or directly:
#   powershell -ExecutionPolicy Bypass -File flash.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ''
Write-Host ' _ ___  _         ' -ForegroundColor Cyan
Write-Host '(_)__ \| |_ _ __  ' -ForegroundColor Cyan
Write-Host '| |  ) | __| ''_ \ ' -ForegroundColor Cyan
Write-Host '| | / /| |_| | | |' -ForegroundColor Cyan
Write-Host '|_|/___|\__|_| |_|' -ForegroundColor Cyan
Write-Host ''
Write-Host 'i2tn - FTSC11 factory flasher' -ForegroundColor Cyan
Write-Host '(c) 2026 i2tn - https://github.com/i2tn' -ForegroundColor DarkGray

function Quote([string]$s) { if ($s -match '\s') { '"' + $s + '"' } else { $s } }

$esptool = Get-ChildItem -Path (Join-Path $root 'esptool') -Filter esptool.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $esptool) {
    Write-Host "esptool.exe not found under $root\esptool — re-run the install command." -ForegroundColor Red
    Read-Host "Press Enter to close" | Out-Null; exit 1
}

while ($true) {
    Write-Host ""
    Write-Host "Rules for v1 boards WITHOUT rework:" -ForegroundColor Yellow
    Write-Host "  * Do NOT plug the PT100 (MAX31865) module into header J7."
    Write-Host "  * On the test page, answer NO to the F2 resistor question."
    Write-Host ""

    # --- serial port ---
    $ports = @([System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object -Unique)
    if ($ports.Count -eq 0) {
        Write-Host "No COM port found. Connect the USB-UART adapter." -ForegroundColor Red
        Write-Host "If it never appears, install the adapter driver:"
        Write-Host "  CP210x: https://www.silabs.com/developer-tools/usb-to-uart-bridge-vcp-drivers"
        Write-Host "  CH340:  https://www.wch-ic.com/downloads/CH341SER_EXE.html"
        Read-Host "Press Enter to close" | Out-Null; exit 1
    }
    if ($ports.Count -eq 1) {
        $port = $ports[0]
        Write-Host "Serial port: $port"
    } else {
        Write-Host "Serial ports:"
        for ($i = 0; $i -lt $ports.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $ports[$i]) }
        do { $sel = Read-Host ("Pick the board's port [1-{0}]" -f $ports.Count) }
        until ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $ports.Count)
        $port = $ports[[int]$sel - 1]
    }

    # --- firmware choice ---
    Write-Host ""
    Write-Host "Firmware:"
    Write-Host "  [1] Board test — test page on the board's own WiFi (default)"
    Write-Host "  [2] Production — fan controller, joins your WiFi/MQTT"
    $fw = if ((Read-Host "Choose [1/2]") -eq '2') { 'app' } else { 'line' }

    $ssid = ''; $pass = ''; $mqtt = ''
    if ($fw -eq 'app') {
        Write-Host ""
        Write-Host "WiFi for the production firmware (leave SSID empty to skip):"
        $ssid = Read-Host "  WiFi name (SSID)"
        if ($ssid) {
            $pass = Read-Host "  WiFi password"
            $mqtt = Read-Host "  MQTT broker URI (optional, e.g. mqtt://192.168.1.10)"
        }
    }

    # --- flash ---
    $imgs = @('0x1000', (Join-Path $root 'bin\bootloader.bin'),
              '0x8000', (Join-Path $root 'bin\partition-table.bin'),
              '0x20000', (Join-Path $root ("bin\ftsc11-{0}.bin" -f $fw)))
    foreach ($f in $imgs[1], $imgs[3], $imgs[5]) {
        if (-not (Test-Path $f)) { Write-Host "Missing $f — re-run the install command." -ForegroundColor Red; Read-Host "Press Enter to close" | Out-Null; exit 1 }
    }

    $flashed = $false
    foreach ($baud in 460800, 115200) {
        Write-Host ("`nFlashing at {0} baud..." -f $baud) -ForegroundColor Cyan
        & $esptool.FullName --chip esp32 -p $port -b $baud --before default_reset --after hard_reset `
            write_flash --flash_mode dio --flash_size 4MB --flash_freq 40m @imgs
        if ($LASTEXITCODE -eq 0) { $flashed = $true; break }
        Write-Host "Failed at $baud baud." -ForegroundColor Yellow
    }
    if (-not $flashed) {
        Write-Host "`nFlashing failed. Check: board powered? right COM port? cable ok?" -ForegroundColor Red
        Write-Host "Close any other program using the port (serial monitor) and try again."
    } else {
        Write-Host "`nFlash OK." -ForegroundColor Green

        # --- WiFi provisioning over the firmware's serial console (production only) ---
        if ($fw -eq 'app' -and $ssid) {
            Write-Host "Sending WiFi settings over the serial console..."
            Start-Sleep -Seconds 4   # firmware boot
            $sp = New-Object System.IO.Ports.SerialPort $port, 115200, 'None', 8, 'One'
            $sp.NewLine = "`n"
            try {
                $sp.Open()
                $sp.WriteLine('')
                Start-Sleep -Milliseconds 300
                $sp.WriteLine("wifi $(Quote $ssid) $(Quote $pass)")
                Start-Sleep -Seconds 1
                if ($mqtt) { $sp.WriteLine("mqtt $(Quote $mqtt)"); Start-Sleep -Seconds 1 }
                $sp.WriteLine('status')
                Start-Sleep -Seconds 2
                Write-Host ($sp.ReadExisting())
                Write-Host "WiFi settings sent." -ForegroundColor Green
            } catch {
                Write-Host ("Could not talk to the console ({0})." -f $_.Exception.Message) -ForegroundColor Yellow
                Write-Host "You can set WiFi manually: open the port at 115200 in any serial terminal"
                Write-Host "and type:  wifi <ssid> <password>"
            } finally { if ($sp.IsOpen) { $sp.Close() } }
        }

        Write-Host ""
        if ($fw -eq 'line') {
            Write-Host "Next steps:" -ForegroundColor Cyan
            Write-Host '  1. Power-cycle the board.'
            Write-Host '  2. On a phone/tablet/PC, join WiFi "FTSC11-XXXXXX", password: ftsc11-line'
            Write-Host '  3. Open http://192.168.4.1 — enter the board serial, run the gates.'
            Write-Host '  Expected on un-reworked boards: RTD gate FAIL (flag F1), F2 question = NO.'
            Write-Host '  Report: board serial + page screenshot + JSON from http://192.168.4.1/api/state'
        } else {
            Write-Host "Production firmware flashed." -ForegroundColor Cyan
            if ($ssid) { Write-Host "  The board joins '$ssid' after power-cycle." }
            else { Write-Host "  WiFi not set — use a serial terminal (115200): wifi <ssid> <password>" }
        }
    }

    Write-Host ""
    if ((Read-Host "Flash another board? [y/N]") -notmatch '^[yY]') { break }
}
