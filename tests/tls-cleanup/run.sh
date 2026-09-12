#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
MONO_LLVM_RUNTIME_ROOT=${MONO_LLVM_RUNTIME_ROOT:-${MONO_NX_ROOT:-$here/../../dotnet_runtime}}
out="$here/../../artifacts/tls-cleanup-host"
mkdir -p "$out"
python3 - "$MONO_LLVM_RUNTIME_ROOT" "$out" <<'PY'
from pathlib import Path
import sys,hashlib
runtime,out=map(Path,sys.argv[1:])
source=runtime/'src/mono/mono/utils/mono-tls.c'
text=source.read_text();marker='#if HOST_LIBNX\n'
assert text.count(marker)==1 and text.rstrip().endswith('#endif')
block=text.split(marker,1)[1].rsplit('#endif',1)[0]
(out/'tls-under-test.inc').write_text(block)
(out/'source.sha256').write_text(hashlib.sha256(source.read_bytes()).hexdigest()+'\n')
PY
cc -std=c11 -Wall -Wextra -Werror -I"$here/stubs" -I"$out" "$here/test.c" -o "$out/test"
"$out/test" | tee "$out/result.txt"
