# i2tn — FTSC11 factory test package

Flash and test FTSC11 v1 boards. **Windows, one command, nothing to install**
(esptool is bundled; no Python needed).

## Quick start (Windows)

Open **PowerShell** and paste:

```powershell
irm https://raw.githubusercontent.com/i2tn/ftsc11-factory/main/install.ps1 | iex
```

The script downloads this package to `%USERPROFILE%\ftsc11-factory`, then walks
you through everything: it finds the board's COM port, asks which firmware to
flash, flashes it, and (for the production firmware) asks for your WiFi name
and password and configures the board over the same cable. At the end it
offers to flash the next board — run it once per batch.

Re-running the same command updates the package to the latest version.
For later boards you can also just run: `%USERPROFILE%\ftsc11-factory\flash.ps1`
(right-click → Run with PowerShell).

## ⚠ Rules for v1 boards WITHOUT rework

1. **Do NOT plug the PT100 (MAX31865) module into header J7.**
   With it plugged in the board may not boot at all (design flag F1).
   The RTD test gate will show FAIL — expected; include it in the report.
2. **When the test page asks whether the "F2 resistor rework" was done,
   answer honestly (normally: NO).** The triac firing test then stays locked —
   a firmware safety interlock that protects the board (design flag F2).
   Do not try to work around it.

If a board does not boot (no `FTSC11-XXXXXX` WiFi appears): check nothing is
plugged into J7, then report the board.

## What you need

- A Windows PC with PowerShell (any Windows 10/11).
- A **3.3 V USB-UART adapter** with DTR and RTS wired (the board has an
  auto-program circuit — no buttons needed). If no COM port appears, install
  your adapter's driver:
  [CP210x](https://www.silabs.com/developer-tools/usb-to-uart-bridge-vcp-drivers) ·
  [CH340](https://www.wch-ic.com/downloads/CH341SER_EXE.html)
- Internet, for the one-command install.

## The two firmwares

| Choice | What it is |
|---|---|
| **Board test** (default) | The board opens WiFi `FTSC11-XXXXXX` (password `ftsc11-line`); open <http://192.168.4.1>, enter the board serial, run the test gates top to bottom, one PASS/FAIL verdict per board. Low-voltage station first, then mains — detected automatically. |
| **Production** | The fan-controller firmware. The script asks for WiFi (and optional MQTT broker) and sends it to the board over the serial cable. |

## Reporting results

For every tested board, report:

- the board serial number,
- the verdict + per-gate list — screenshot of the page and/or the JSON from
  <http://192.168.4.1/api/state>,
- expected on un-reworked v1 boards: **RTD gate FAIL (F1)** and **F2 = NO**;
  everything else should pass on a good board.

## Troubleshooting

| Problem | Check |
|---|---|
| No COM port | Adapter driver (links above), cable |
| Flashing fails | Board powered? Right port? Close other serial programs; the script auto-retries at a lower speed |
| No `FTSC11-…` WiFi after flashing | Power-cycle; confirm "Board test" firmware was chosen |
| Board does not boot at all | Unplug the J7 module (flag F1); if still dead, report the board |

## Linux / advanced

`deploy.py` does the same non-interactively (needs Python 3.8+):

```sh
pip install -r requirements.txt
./deploy.sh                # board test
./deploy.sh --fw app       # production (WiFi/MQTT from wifi.conf)
```

---

*© 2026 [i2tn](https://github.com/i2tn). This is a build-output distribution
repo — the source of truth is the `ftsc11-firmware` repo (`scripts/factory/`).
`esptool/` contains an unmodified
[esptool](https://github.com/espressif/esptool) Windows release (GPL-2.0);
source at that link.*
