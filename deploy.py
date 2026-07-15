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


def gen_nvs(vals, out):
    csv = out.with_suffix(".csv")
    rows = ["key,type,encoding,value", "net,namespace,,"]
    rows += [f"{k},data,string,{v}" for k, v in vals.items()]
    csv.write_text("\n".join(rows) + "\n", encoding="utf-8")
    run([sys.executable, "-m", "esp_idf_nvs_partition_gen", "generate",
         str(csv), str(out), NVS_SIZE])


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

    esptool = [sys.executable, "-m", "esptool", "--chip", "esp32"]
    if a.port:
        esptool += ["-p", a.port]
    esptool += ["-b", a.baud, "--before", "default_reset", "--after", "hard_reset"]

    if a.erase_all:
        run(esptool + ["erase_flash"], a.dry_run)

    imgs = [OFF_BOOT, str(BIN / "bootloader.bin"),
            OFF_TABLE, str(BIN / "partition-table.bin"),
            OFF_APP, str(fw)]

    vals = read_conf(Path(a.wifi))
    if vals:
        nvs = Path(tempfile.mkdtemp()) / "nvs.bin"
        gen_nvs(vals, nvs)
        imgs = [OFF_NVS, str(nvs)] + imgs
        print(f"WiFi/MQTT settings taken from {a.wifi}")
    elif a.fw == "app":
        print("note: wifi.conf is empty — production firmware will boot with "
              "WiFi unconfigured (set it later over the serial console: "
              "wifi <ssid> <pass>)")

    run(esptool + ["write_flash", "--flash_mode", "dio", "--flash_size", "4MB",
                   "--flash_freq", "40m"] + imgs, a.dry_run)

    print()
    if a.fw == "line":
        print("Done. Power-cycle the board, then on a phone/tablet/PC:")
        print('  join WiFi "FTSC11-XXXXXX" (password: ftsc11-line)')
        print("  and open http://192.168.4.1")
    else:
        print("Done. The production firmware joins the WiFi set in wifi.conf.")


if __name__ == "__main__":
    main()
