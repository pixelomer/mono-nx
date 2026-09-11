# LLVM AOT for libnx

This fork builds a Linux x64 cross compiler and Horizon ARM64 Mono runtime
with the runtime's pinned LLVM 19.1.0-alpha.1.24575.1 packages.
The public source baselines are mono-nx
fec057748af9121d5cf363e772e817908d57c191 (rel-3) and exelix11/dotnet_runtime
d75fa786b88e10f45ca9263773d84e47033cfb01 (.NET 9.0.3).

The [LLVM-capable runtime source](https://github.com/pixelomer/dotnet-runtime/commit/a1b7b55d04454d003645f01972fffcccfdbb8b88)
supply three required contracts:

- MonoEnableLLVMRuntime enables target support for LLVM AOT modules without
  embedding the LLVM compiler in the target process.
- llvm-runtime.cpp uses C++ exceptions for its explicit throw/catch helpers.
- LLVM static AOT objects are position-independent for the NRO's PIE link.

## Source prerequisites and compiler build

Use Linux x64 with the upstream .NET source-build prerequisites, a .NET 9 SDK,
Git, Bash, CMake, Make, Python, wget, patch, Clang/LLVM and devkitPro's
devkitA64, switch-tools, libnx 4.10.0 or later and Switch portlibs.
See the [upstream build instructions](../README.md#building) and the committed
Dockerfile for the original toolchain setup. Set DEVKITPRO to its installation.

From a dedicated checkout of this repository, acquire the exact LLVM-capable
runtime and build ICU using the included public-source recipe:

```sh
git clone https://github.com/pixelomer/dotnet-runtime.git dotnet_runtime
git -C dotnet_runtime checkout --detach a1b7b55d04454d003645f01972fffcccfdbb8b88
source env.sh
(cd icu && bash build_icu.sh)
bash build_llvm.sh
```

The helper defaults MONO_NX_ROOT to this checkout's dotnet_runtime directory.
An explicit MONO_NX_ROOT must identify an equivalent source checkout, not an
unexplained binary SDK. CONFIGURATION defaults to Release. The helper first
restores the pinned host LLVM package, uses its libclang for target offsets,
then builds the target runtime and the Linux-hosted AOT cross compiler.
ROOTFS_DIR is set for target stages and empty for the host compiler stage.
Package versions and system compiler/package-source configuration are unchanged.

ICU downloads from the Unicode project's public release. Its helper creates
source and host/target build directories under icu/ and installs into icu/libnx.
Use a fresh checkout for that recipe; rerunning it does not clean existing
directories. LLVM/runtime rebuilds update generated artifacts. Preserve needed
outputs and keep user inputs outside generated build locations.

## Managed and native support inputs

build_llvm.sh builds the LLVM compiler and target runtime, not the entire SDK.
The inherited AOT templates also need matching .NET 9 CoreLib/framework,
Mono.Linker and native BCL support. These can be built from the original public
rel-3 sources in a separate source tree; no private SDK directory is required.
For the legacy lifecycle helpers, this separate tree is MONO_SDK_ROOT.

From the current repository root:

```sh
mkdir -p artifacts
git clone https://github.com/exelix11/mono-nx.git artifacts/rel3-sdk
git -C artifacts/rel3-sdk checkout --detach fec057748af9121d5cf363e772e817908d57c191
git clone https://github.com/exelix11/dotnet_runtime.git artifacts/rel3-sdk/dotnet_runtime
git -C artifacts/rel3-sdk/dotnet_runtime checkout --detach d75fa786b88e10f45ca9263773d84e47033cfb01
(
  cd artifacts/rel3-sdk
  source env.sh
  (cd icu && bash build_icu.sh)
  bash build_mono.sh
)
```

This preserves the inherited Debug layout required by the legacy helpers:
dotnet_runtime/artifacts/bin/Mono.Linker/Debug/net9.0,
dotnet_runtime/artifacts/bin/mono/libnx.arm64.Debug and
dotnet_runtime/artifacts/bin/runtime/net9.0-libnx-Debug-arm64.
The separate LLVM runtime/compiler use their Release layout.
Do not substitute arbitrary framework or native libraries merely because a
filename matches, or silently reuse an old target archive after a failed build.

## Static AOT object contract

Supply a managed Program.dll and its compatible dependency closure under
output/ using the [AOT preparation instructions](aot.md). With MONO_NX_ROOT
selecting the LLVM runtime checkout:

```sh
compiler="$MONO_NX_ROOT/artifacts/bin/mono/linux.x64.Release/cross/linux-x64/libnx-arm64/mono-aot-cross"
export PATH="$DEVKITPRO/devkitA64/bin:$PATH"
"$compiler" --llvm --optimize=aggressive-inlining --path=output \
  --aot="full,static,direct-icalls,direct-pinvoke,tool-prefix=aarch64-none-elf-,llvm-outfile=output/Program.dll.llvm.o,llvm-path=${compiler%/*}/" \
  output/Program.dll
```

Static LLVM AOT produces both Program.dll.o and Program.dll.llvm.o.
Compile every dependency the same way, link both object families and retain
AOT registration symbols. Explicit llvm-outfile is required in static mode.
The compiler must report LLVM enabled and invoke opt/llc; backend availability
does not mean that every method uses LLVM.

Use the pinned package's libclang and the restricted mono.aotcross subset.
A host toolchain or package-source problem is not a reason to change target
package versions or the system crypto policy. Object generation alone does not
establish managed exception, GC or thread correctness.

## Native thread ownership

Mono managed threads use joinable pthreads. Thread.Join waits through
mono_thread_join, and runtime threads also participate in a joinable-thread
registry. Normal managed-thread exit can call pthread_exit.
A second reaper on this path would duplicate native lifetime ownership.

SystemNative_CreateThread is a separate native BCL callback contract requesting
detached pthreads without retaining a join handle. Do not assume it shares
Mono's joinable-thread rules or that a callback always returns normally.
