#!/usr/bin/env bash
# Build a Linux x64 -> Horizon ARM64 LLVM AOT compiler and target runtime.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
runtime=${MONO_NX_ROOT:-"$here/dotnet_runtime"}
configuration=${CONFIGURATION:-Release}
: "${DEVKITPRO:?Set DEVKITPRO to the devkitPro installation}"
[[ -f "$runtime/src/mono/mono.proj" ]] || { echo "MONO_NX_ROOT must point to the runtime source tree" >&2; exit 1; }
[[ -f "$DEVKITPRO/libnx/include/switch.h" ]] || { echo "libnx headers are missing" >&2; exit 1; }
runtime=$(cd "$runtime" && pwd)
cd "$runtime"

# Restore the official, pinned host LLVM package before generating target offsets.
# No host-wide compiler or package-source configuration is changed here.
ROOTFS_DIR= ./dotnet.sh msbuild src/mono/llvm/llvm-init.proj -restore -t:Build \
 /p:Configuration="$configuration" /p:TargetOS=linux /p:TargetArchitecture=x64 \
 /p:BuildArchitecture=x64 /p:AotHostArchitecture=x64 /p:AotHostOS=linux
libclang="$runtime/artifacts/obj/mono/linux.x64.$configuration/llvm/x64/lib/libclang.so"
[[ -f "$libclang" ]] || { echo "Pinned libclang was not restored: $libclang" >&2; exit 1; }

ROOTFS_DIR="$DEVKITPRO" ./build.sh -s mono.runtime -c "$configuration" \
 --cross -a arm64 --os libnx /p:MonoEnableLLVMRuntime=true
ROOTFS_DIR="$DEVKITPRO" ./build.sh -s mono.aotcross -c "$configuration" \
 /p:MonoGenerateOffsetsOSGroups=libnx /p:MonoLibClang="$libclang" /p:MonoEnableLLVMRuntime=true

# Restrict the subset: rebuilding unrelated managed tools can introduce signing
# and package requirements that are irrelevant to the native cross compiler.
ROOTFS_DIR= ./build.sh -s mono.aotcross -c "$configuration" \
 /p:AotHostArchitecture=x64 /p:AotHostOS=linux /p:MonoCrossAOTTargetOS=libnx \
 /p:SkipMonoCrossJitConfigure=true /p:BuildMonoAOTCrossCompilerOnly=true \
 /p:BuildMonoAOTCrossCompiler=true /p:MonoAOTEnableLLVM=true
compiler="$runtime/artifacts/bin/mono/linux.x64.$configuration/cross/linux-x64/libnx-arm64/mono-aot-cross"
"$compiler" --version
"$compiler" --version | grep -Eq 'LLVM:[[:space:]]+yes' || {
 echo "Cross compiler has no active LLVM backend" >&2; exit 1;
}
echo "Compiler: $compiler"
echo "Runtime: $runtime/artifacts/obj/mono/libnx.arm64.$configuration/out/lib/libmonosgen-2.0.a"
