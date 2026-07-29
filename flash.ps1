# i2tn - FTSC11 factory flasher. Interactive, no prerequisites (esptool.exe bundled).
# (c) 2026 i2tn - https://github.com/i2tn
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

# esp_console_split_argv unescapes \\, \" and "\ " inside a quoted argument,
# so always quote and escape both metacharacters. The old "quote only if it
# contains a space" rule silently mangled any credential holding " or \.
# Backslashes first, then quotes, or the escapes we insert get doubled.
# -replace replacement strings are literal (only $ is special), so '\\' emits
# two backslashes and '\"' emits backslash-quote.
function Quote([string]$s) {
    '"' + ($s -replace '\\', '\\' -replace '"', '\"') + '"'
}

function Show-DriverHelp {
    Write-Host "Install the adapter driver, then re-run:"
    Write-Host "  CP210x: https://www.silabs.com/developer-tools/usb-to-uart-bridge-vcp-drivers"
    Write-Host "  CH340:  https://www.wch-ic.com/downloads/CH341SER_EXE.html"
    Write-Host "  FTDI:   https://ftdichip.com/drivers/vcp-drivers/"
}

# Enumerate COM ports WITH their device names. GetPortNames() returns bare
# "COM3" strings, so a Bluetooth or motherboard port is indistinguishable from
# the board - and picking the wrong one fails inside esptool with a timeout
# that looks like broken hardware. Get-CimInstance also works on PowerShell 7,
# where System.IO.Ports is not available at all.
function Get-SerialPorts {
    $list = @()
    try {
        $list = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop |
            Where-Object { $_.Name -match '\(COM\d+\)' } |
            ForEach-Object {
                $nm = $_.Name
                [pscustomobject]@{
                    Port        = [regex]::Match($nm, '\((COM\d+)\)').Groups[1].Value
                    Name        = ($nm -replace '\s*\(COM\d+\)\s*$', '')
                    Problem     = [int]$_.ConfigManagerErrorCode
                    IsUsbSerial = $nm -match 'CP210|CH34|FTDI|FT232|Silicon Labs|USB.*Serial|USB-SERIAL|Serial Device|CDC'
                }
            })
    } catch { }
    if ($list.Count -eq 0) {
        # Fallback when WMI/CIM is unavailable: the registry knows the ports
        # but not their names.
        try {
            $k = Get-ItemProperty 'HKLM:\HARDWARE\DEVICEMAP\SERIALCOMM' -ErrorAction Stop
            $list = @($k.PSObject.Properties |
                Where-Object { $_.Value -match '^COM\d+$' } |
                ForEach-Object {
                    [pscustomobject]@{ Port = $_.Value; Name = '(name unavailable)'
                                       Problem = 0; IsUsbSerial = $true }
                })
        } catch { }
    }
    ,@($list | Sort-Object { [int]($_.Port -replace '\D', '') })
}

$esptool = Get-ChildItem -Path (Join-Path $root 'esptool') -Filter esptool.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $esptool) {
    Write-Host "esptool.exe not found under $root\esptool - re-run the install command." -ForegroundColor Red
    Read-Host "Press Enter to close" | Out-Null; exit 1
}

while ($true) {
    Write-Host ""
    Write-Host "Rules for v1 boards WITHOUT rework:" -ForegroundColor Yellow
    Write-Host "  * Do NOT plug the PT100 (MAX31865) module into header J7."
    Write-Host "  * On the test page, answer NO to the F2 resistor question."
    Write-Host ""

    # --- serial port ---
    $ports = @(Get-SerialPorts)
    if ($ports.Count -eq 0) {
        Write-Host "No COM port found. Connect the USB-UART adapter." -ForegroundColor Red
        Show-DriverHelp
        Read-Host "Press Enter to close" | Out-Null; exit 1
    }

    # Flag anything Windows has enumerated but not driven (yellow-bang in
    # Device Manager) - it shows up as a port yet cannot be opened.
    foreach ($p in $ports | Where-Object { $_.Problem -ne 0 }) {
        Write-Host ("WARNING: {0} '{1}' has a driver problem (code {2}) - it will not open." -f `
            $p.Port, $p.Name, $p.Problem) -ForegroundColor Yellow
    }

    $likely = @($ports | Where-Object { $_.IsUsbSerial -and $_.Problem -eq 0 })

    Write-Host "Serial ports:"
    foreach ($p in $ports) {
        $tag = if ($p.IsUsbSerial) { "  <- USB-UART adapter" } else { "" }
        Write-Host ("  [{0}] {1,-6} {2}{3}" -f ($ports.IndexOf($p) + 1), $p.Port, $p.Name, $tag)
    }

    if ($likely.Count -eq 1) {
        $port = $likely[0].Port
        Write-Host ("Using {0} ({1})." -f $port, $likely[0].Name) -ForegroundColor Green
    } elseif ($likely.Count -eq 0) {
        # The old code auto-picked whatever single port existed here, so a
        # Bluetooth or motherboard COM port was silently handed to esptool and
        # the flash failed with a confusing timeout instead of a real answer.
        Write-Host ""
        Write-Host "None of these look like a USB-UART adapter." -ForegroundColor Red
        Write-Host "The board is probably not connected, or its driver is missing."
        Show-DriverHelp
        Write-Host ""
        if ((Read-Host "Try one anyway? [y/N]") -notmatch '^[yY]') { continue }
        do { $sel = Read-Host ("Pick a port [1-{0}]" -f $ports.Count) }
        until ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $ports.Count)
        $port = $ports[[int]$sel - 1].Port
    } else {
        do { $sel = Read-Host ("Pick the board's port [1-{0}]" -f $ports.Count) }
        until ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $ports.Count)
        $port = $ports[[int]$sel - 1].Port
    }

    # --- firmware choice ---
    Write-Host ""
    Write-Host "Firmware:"
    Write-Host "  [1] Board test - test page on the board's own WiFi (default)"
    Write-Host "  [2] Production - fan controller, joins your WiFi/MQTT"
    $fw = if ((Read-Host "Choose [1/2]") -eq '2') { 'app' } else { 'line' }

    $ssid = ''; $pass = ''; $mqtt = ''
    if ($fw -eq 'app') {
        Write-Host ""
        Write-Host "WARNING: the production firmware has NO safety interlock for the triac." -ForegroundColor Yellow
        Write-Host "Flash it ONLY on boards with the F2 resistor rework done, or keep mains"
        Write-Host "and the fan disconnected. Firing on an un-reworked board damages it."
        if ((Read-Host "Continue with the production firmware? [y/N]") -notmatch '^[yY]') { continue }
        Write-Host ""
        Write-Host "WiFi for the production firmware (leave SSID empty to skip):"
        $ssid = Read-Host "  WiFi name (SSID)"
        if ($ssid) {
            $secure = Read-Host "  WiFi password" -AsSecureString
            # PtrToStringBSTR (not ...Auto) honours the BSTR length prefix, and
            # ZeroFreeBSTR wipes the plaintext copy from unmanaged memory.
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            try   { $pass = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
            finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
            $mqtt = Read-Host "  MQTT broker URI (optional, e.g. mqtt://192.168.1.10)"
        }
    }

    # --- flash ---
    $imgs = @('0x1000', (Join-Path $root 'bin\bootloader.bin'),
              '0x8000', (Join-Path $root 'bin\partition-table.bin'),
              '0x20000', (Join-Path $root ("bin\ftsc11-{0}.bin" -f $fw)))
    foreach ($f in $imgs[1], $imgs[3], $imgs[5]) {
        if (-not (Test-Path $f)) { Write-Host "Missing $f - re-run the install command." -ForegroundColor Red; Read-Host "Press Enter to close" | Out-Null; exit 1 }
    }

    $flashed = $false
    foreach ($baud in 460800, 115200) {
        Write-Host ("`nFlashing at {0} baud..." -f $baud) -ForegroundColor Cyan
        # Hyphenated esptool v5 syntax (the underscore aliases still work but
        # print a deprecation warning per flag, which reads as a failure to an
        # operator). '4MB' MUST stay quoted: PowerShell parses a bare 4MB as
        # the number 4194304, which esptool rejects.
        & $esptool.FullName --chip esp32 -p $port -b $baud --before default-reset --after hard-reset `
            write-flash --flash-mode dio --flash-size '4MB' --flash-freq 40m @imgs
        if ($LASTEXITCODE -eq 0) { $flashed = $true; break }
        Write-Host "Failed at $baud baud." -ForegroundColor Yellow
    }
    if (-not $flashed) {
        Write-Host "`nFlashing failed on $port." -ForegroundColor Red
        Write-Host "  * Wrong port? Re-run and pick a different one."
        Write-Host "  * Port busy? Close any serial monitor / Arduino IDE / PuTTY."
        Write-Host "  * 'No serial data received' means the board never entered the"
        Write-Host "    bootloader: hold BOOT, tap EN/RST, release BOOT, then retry."
        Write-Host "  * Board powered, and is the USB cable a data cable (not charge-only)?"
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
                $echo = $sp.ReadExisting()
                if ($pass) { $echo = $echo.Replace($pass, '********') }
                # a broker URI can embed credentials: mqtt://user:pass@host
                if ($mqtt -and $mqtt -match '@') { $echo = $echo.Replace($mqtt, 'mqtt://********') }
                Write-Host $echo
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
            Write-Host '  3. Open http://192.168.4.1 - enter the board serial, run the gates.'
            Write-Host '  Expected on un-reworked boards: RTD gate FAIL (flag F1), F2 question = NO.'
            Write-Host '  Report: board serial + page screenshot + JSON from http://192.168.4.1/api/state'
        } else {
            Write-Host "Production firmware flashed." -ForegroundColor Cyan
            if ($ssid) { Write-Host "  The board joins '$ssid' after power-cycle." }
            else { Write-Host "  WiFi not set - use a serial terminal (115200): wifi <ssid> <password>" }
        }
    }

    Write-Host ""
    if ((Read-Host "Flash another board? [y/N]") -notmatch '^[yY]') { break }
}
