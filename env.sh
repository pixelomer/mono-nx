#!/usr/bin/env bash
# Source after python3 build.py to select this checkout's built dependencies.
mono_nx_env_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ ! -f "$mono_nx_env_root/artifacts/build-environment.json" ]]; then
    echo "Run python3 build.py first." >&2
    return 1 2>/dev/null || exit 1
fi
eval "$(python3 - "$mono_nx_env_root/artifacts/build-environment.json" <<'PYENV'
import json, shlex, sys
for name, value in json.load(open(sys.argv[1])).items():
    print('export ' + name + '=' + shlex.quote(value))
PYENV
)"
export BUILT_SD_ROOT="$mono_nx_env_root/sd_files/mono"
export PATH="$DEVKITA64/bin:$PATH"
unset mono_nx_env_root
