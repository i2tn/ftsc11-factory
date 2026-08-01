#!/usr/bin/env python3
"""i2tn — FTSC11 board flasher. Works on Windows, Linux and macOS.

(c) 2026 i2tn · https://github.com/i2tn

Usage:
  python deploy.py                 # flash the line-test firmware (default)
  python deploy.py --fw app        # flash the production firmware
  python deploy.py -p COM5         # pick the serial port yourself
  python deploy.py --erase-all     # wipe the whole flash first
  python deploy.py --dry-run       # show the commands, flash nothing

Needs Python 3.8+ and `pip install -r requirements.txt`.
WiFi/MQTT for the production firmware comes from wifi.conf next to this file.
"""
import argparse
import csv
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
BIN = HERE / "bin"

# Offsets: bootloader/table fixed by ESP32 + sdkconfig; nvs/app from partitions.csv.
OFF_BOOT, OFF_TABLE, OFF_NVS, OFF_APP = "0x1000", "0x8000", "0x9000", "0x20000"
NVS_SIZE = "0x6000"
STR_MAX = 63  # net_cfg NVS strings are char[64]

NVS_KEYS = {  # wifi.conf key -> NVS key in namespace "net" (components/net/net_cfg.c)
    "WIFI_SSID": "ssid",
    "WIFI_PASS": "pass",
    "MQTT_URI": "muri",
    "MQTT_USER": "muser",
    "MQTT_PASS": "mpass",
    "DEVICE_ID": "id",
}


def read_conf(path):
    vals = {}
    if not path.exists():
        return vals
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        k, v = k.strip(), v.strip()
        if k in NVS_KEYS and v:
            if len(v) > STR_MAX:
                sys.exit(f"error: {k} is longer than {STR_MAX} characters")
            vals[NVS_KEYS[k]] = v
    return vals


def run(cmd, dry=False):
    print("+", " ".join(map(str, cmd)))
    if dry:
        return
    if subprocess.run(cmd).returncode != 0:
        sys.exit("error: command failed (see output above)")


NO_PORT_HELP = """\
No USB serial adapter found.

The FTSC11 board has NO USB socket of its own - plugging the BOARD into the
PC does nothing, no port will ever appear. It is reached through a separate
3.3 V USB-UART adapter:

  PC --USB--> adapter --TX/RX/GND/DTR/RTS--> board programming header

Check: adapter plugged in, a data cable (not a charge-only one), driver
installed.
  CP210x: https://www.silabs.com/developer-tools/usb-to-uart-bridge-vcp-drivers
  CH340:  https://www.wch-ic.com/downloads/CH341SER_EXE.html
  FTDI:   https://ftdichip.com/drivers/vcp-drivers/"""


def usb_ports():
    """Serial ports that are real USB devices.

    Only USB devices report a vid, and that is the whole filter: a PC exposes
    plenty of serial ports that can never be the board (Linux enumerates
    /dev/ttyS0..31 whether or not anything is attached, Windows has COM1 and
    Bluetooth ports). esptool's auto-detect walks those and fails with a
    connection timeout, which reads as broken hardware rather than "you are
    talking to the wrong port".
    """
    try:
        from serial.tools import list_ports
    except ImportError:
        sys.exit("error: pyserial is missing - run: pip install -r requirements.txt")
    return sorted(list_ports.comports(), key=lambda p: p.device)


def pick_port(explicit):
    if explicit:
        return explicit
    while True:
        ports = [p for p in usb_ports() if p.vid is not None]
        if len(ports) == 1:
            print(f"Serial port: {ports[0].device} - {ports[0].description}")
            return ports[0].device
        if ports:
            print("USB serial adapters:")
            for i, p in enumerate(ports, 1):
                print(f"  [{i}] {p.device}  {p.description}")
            sel = input(f"Pick the board's port [1-{len(ports)}]: ").strip()
            if sel.isdigit() and 1 <= int(sel) <= len(ports):
                return ports[int(sel) - 1].device
            continue
        print(NO_PORT_HELP)
        if sys.platform.startswith("linux"):
            print("\nOn Linux you must also be in the 'dialout' group:")
            print("  sudo usermod -aG dialout $USER   (then log out and back in)")
        if not sys.stdin.isatty():
            sys.exit("error: no adapter found (and no terminal to prompt on)")
        if input("\nPlug it in, then press Enter to look again (q to quit): "
                 ).strip().lower() == "q":
            sys.exit(1)
        print()


def gen_nvs(vals, out):
    # csv.writer, not an f-string: credentials legitimately contain commas and
    # quotes, and hand-joining them silently produced the wrong fields.
    csv_path = out.with_suffix(".csv")
    with csv_path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["key", "type", "encoding", "value"])
        w.writerow(["net", "namespace", "", ""])
        for k, v in vals.items():
            w.writerow([k, "data", "string", v])
    run([sys.executable, "-m", "esp_idf_nvs_partition_gen", "generate",
         str(csv_path), str(out), NVS_SIZE])


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--fw", choices=["line", "app"], default="line",
                    help="line = board test (default), app = production firmware")
    ap.add_argument("-p", "--port", help="serial port, e.g. COM5 or /dev/ttyUSB0 "
                    "(default: auto-detect)")
    ap.add_argument("-b", "--baud", default="460800",
                    help="use 115200 if flashing is unreliable")
    ap.add_argument("--wifi", default=str(HERE / "wifi.conf"))
    ap.add_argument("--erase-all", action="store_true",
                    help="erase the entire flash before writing")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    fw = BIN / f"ftsc11-{a.fw}.bin"
    for f in (fw, BIN / "bootloader.bin", BIN / "partition-table.bin"):
        if not f.exists():
            sys.exit(f"error: missing {f} — run from the unpacked package folder")

    if a.fw == "app":
        print("WARNING: the production firmware has no triac interlock - flash it")
        print("only on boards with the F2 resistor rework, or keep mains and the")
        print("fan disconnected (firing damages an un-reworked board).")

    # Always resolve a port ourselves rather than leaving esptool to auto-detect:
    # its scan cannot tell a real adapter from the PC's own idle serial ports.
    if a.dry_run:
        port = a.port or "<port>"   # a dry run must not require hardware
    else:
        port = pick_port(a.port)

    esptool = [sys.executable, "-m", "esptool", "--chip", "esp32", "-p", port,
               "-b", a.baud, "--before", "default-reset", "--after", "hard-reset"]

    if a.erase_all:
        run(esptool + ["erase-flash"], a.dry_run)

    imgs = [OFF_BOOT, str(BIN / "bootloader.bin"),
            OFF_TABLE, str(BIN / "partition-table.bin"),
            OFF_APP, str(fw)]

    vals = read_conf(Path(a.wifi))
    # One scope covering generation AND flashing: gen_nvs writes the
    # credentials to a CSV, so a failure inside it must not leak the directory.
    with tempfile.TemporaryDirectory() as tmpdir:
        if vals:
            # Writing the nvs partition replaces ALL of it, including the
            # "params" namespace holding the user parameter blob -- so a board
            # that was already configured comes back on FCSV05 defaults.
            print(f"WiFi/MQTT settings taken from {a.wifi}")
            print("note: this rewrites the nvs partition, which also resets")
            print("      stored user parameters to defaults.")
            nvs = Path(tmpdir) / "nvs.bin"
            gen_nvs(vals, nvs)
            imgs = [OFF_NVS, str(nvs)] + imgs
        elif a.fw == "app":
            print("note: wifi.conf is empty — production firmware will boot "
                  "with WiFi unconfigured (set it later over the serial "
                  "console: wifi <ssid> <pass>)")

        run(esptool + ["write-flash", "--flash-mode", "dio",
                       "--flash-size", "4MB", "--flash-freq", "40m"] + imgs,
            a.dry_run)

    print()
    if a.fw == "line":
        print("Done. Power-cycle the board, then on a phone/tablet/PC:")
        print('  join WiFi "FTSC11-XXXXXX" (password: ftsc11-line)')
        print("  and open http://192.168.4.1")
    else:
        print("Done. The production firmware joins the WiFi set in wifi.conf.")


if __name__ == "__main__":
    main()
