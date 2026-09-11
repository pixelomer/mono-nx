#!/usr/bin/env bash
# Build a lifecycle probe with the rel3 managed/native BCL and a separately
# built Mono LLVM runtime/compiler; source inputs are documented in README.md.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
: "${MONO_SDK_ROOT:?Set MONO_SDK_ROOT to a compatible rel3 SDK checkout}"
: "${MONO_LLVM_RUNTIME_ROOT:?Set MONO_LLVM_RUNTIME_ROOT to the rebuilt runtime fork}"
: "${DEVKITPRO:?Set DEVKITPRO}"
export MONO_NX_ROOT="$MONO_SDK_ROOT/dotnet_runtime"
export ICU_NX_INSTALL_DIR="$MONO_SDK_ROOT/icu/libnx"
export PATH="$DEVKITPRO/devkitA64/bin:$PATH"
compiler="$MONO_LLVM_RUNTIME_ROOT/artifacts/bin/mono/linux.x64.Release/cross/linux-x64/libnx-arm64/mono-aot-cross"
target="$MONO_LLVM_RUNTIME_ROOT/artifacts/obj/mono/libnx.arm64.Release"
out="$root/artifacts/lifecycle-controls-llvm"
if [[ "${MONO_ALLOC_OWNER_TRACE:-0}" == 1 ]]; then out+="-owners"; fi
mkdir -p "$out"/{source,romfs,logs}
dotnet build "$here/Controls.csproj" -c Release > "$out/logs/managed.log" 2>&1
cp "$here/native.c" "$out/source/"
if [[ "${MONO_ALLOC_OWNER_TRACE:-0}" == 1 ]]; then cp "$here/allocation-owners.c" "$out/source/"; fi
cp "$root/native/aot/source/main.c" "$out/source/"
python3 - "$root" "$out" "$target" <<'PY'
from pathlib import Path
import sys,os
root,out,target=map(Path,sys.argv[1:])
s=(root/'native/aot/Makefile').read_text()
s=s.replace('aot_example','mono-llvm-lifecycle-controls')
s=s.replace('../shared',os.path.relpath(root/'native/shared',out))
s=s.replace('$(MONO_NX_ROOT)/artifacts/obj/mono/libnx.arm64.Debug',str(target))
s=s.replace('$(OUTPUT).elf\t:\t$(OFILES)', '$(OUTPUT).elf\t:\t$(OFILES) $(AOT_FILES) $(TOPDIR)/Makefile')
if os.environ.get('MONO_ALLOC_OWNER_TRACE') == '1':
    names=['malloc','calloc','realloc','free','monoeg_malloc','monoeg_malloc0',
           'monoeg_try_malloc','monoeg_g_calloc','monoeg_realloc',
           'monoeg_try_realloc','monoeg_g_free']
    s+='\nCFLAGS += -DMONO_ALLOC_OWNER_TRACE\nLDFLAGS += '+ ' '.join('-Wl,--wrap='+n for n in names)+'\n'
(out/'Makefile').write_text(s)
s=(root/'native/aot/romfs/aot_config.ini').read_text().replace('/program.dll','/MonoLifecycleControls.dll')
s=s.replace(';force_full_application = true','force_full_application = true')
(out/'romfs/aot_config.ini').write_text(s)
PY
cd "$out"
cfg="$MONO_NX_ROOT/src/mono/System.Private.CoreLib/src/ILLink"
dotnet "$MONO_NX_ROOT/artifacts/bin/Mono.Linker/Debug/net9.0/illink.dll" \
 -x "$cfg/ILLink.Descriptors.xml" -x "$cfg/ILLink.LinkAttributes.xml" \
 --feature System.Resources.UseSystemResourceKeys true \
 -d "$MONO_NX_ROOT/artifacts/bin/mono/libnx.arm64.Debug" \
 -d "$MONO_NX_ROOT/artifacts/bin/runtime/net9.0-libnx-Debug-arm64" \
 -d "$here/bin/Release/net9.0" --trim-mode link \
 -a "$here/bin/Release/net9.0/MonoLifecycleControls.dll" all > logs/linker.log 2>&1
"$compiler" --version > logs/compiler-version.txt
rg -q 'LLVM:\s+yes' logs/compiler-version.txt || { echo 'Real LLVM backend required' >&2; exit 1; }
: > logs/aot.log
for dll in output/*.dll; do
 "$compiler" --llvm --optimize=aggressive-inlining --path=output/ \
 --aot="full,static,direct-icalls,direct-pinvoke,ntrampolines=65536,nrgctx-trampolines=32768,nimt-trampolines=4096,ngsharedvt-trampolines=8192,tool-prefix=aarch64-none-elf-,llvm-outfile=$dll.llvm.o,llvm-path=${compiler%/*}/" \
 "$dll" >> logs/aot.log 2>&1
 test -s "$dll.llvm.o"
done
cp output/*.dll romfs/
cp "$ICU_NX_INSTALL_DIR/share/icu/77.1/icudt77l.dat" romfs/
sed -n "s/Linking symbol: '\([^']*\)'\./STATIC_MONO_SYM(\1);/p" logs/aot.log > source/mono_symbols.h
make -j4 > logs/native.log 2>&1
sha256sum mono-llvm-lifecycle-controls.nro > SHA256SUMS
printf '%s\n' "$out/mono-llvm-lifecycle-controls.nro"
