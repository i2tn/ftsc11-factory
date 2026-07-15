#!/bin/sh
# i2tn — FTSC11 factory deploy, Linux / macOS.  e.g.:  ./deploy.sh --fw app -p /dev/ttyUSB0
cd "$(dirname "$0")" || exit 1
command -v python3 >/dev/null 2>&1 || { echo "python3 not found — install Python 3"; exit 1; }
python3 -m pip install -q -r requirements.txt || exit 1
python3 deploy.py "$@"
