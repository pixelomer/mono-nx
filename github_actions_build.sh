#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
python3 build.py --aot-example "$@"
source env.sh
./gather_sdk.sh
(cd managed && ./managed_build.sh)
./copy_sd_files.sh
