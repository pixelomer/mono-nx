# LLVM AOT for libnx

The source-pinned build produces a Linux x64 LLVM cross compiler, matching
Horizon ARM64 Mono runtime, managed framework and IL linker. The runtime
revision in [runtime.lock.json](../runtime.lock.json) selects all of these
inputs; its source also pins LLVM, libnx and ICU dependencies.
Use the [root build guide](../README.md#build) for host and toolchain prerequisites.

## Build and package

From this repository root:

```sh
python3 build.py --aot-example
source env.sh
./gather_sdk.sh
```

build_llvm.sh and build_mono.sh forward to the same runtime-only source build.
The standalone recipe uses one matching Release configuration; it does not
require an older Debug SDK or another source workspace.

The runtime enables MonoEnableLLVMRuntime for LLVM AOT modules, compiles its
C++ exception helpers with exceptions enabled, and emits position-independent
LLVM objects for the NRO's PIE link. LLVM is a host compiler dependency, not a
compiler embedded in the target process. Offset generation uses the pinned
libclang with the target sysroot; the host AOT compiler uses the host toolchain.
Do not substitute unrelated managed or native libraries after a failed build.

See the root guide for generated paths, SDK staging deletion, dependency reuse
and relocation. A packaged SDK must keep its runtime, LLVM, native libraries,
managed inputs and toolchain version together. Source its sdk-env.sh rather
than the source-build env.sh when linking an application from that package.

## Static AOT objects

The example's native/aot/build_aot.sh builds and trims its managed program,
compiles the dependency closure and emits an AOT registration header.
The Makefile links all generated ordinary and LLVM objects. Managed DLLs are
also retained for metadata.

For a prepared Program.dll dependency closure under output/:

```sh
compiler="$MONO_NX_ROOT/artifacts/bin/mono/linux.x64.Release/cross/linux-x64/libnx-arm64/mono-aot-cross"
export PATH="$DEVKITPRO/devkitA64/bin:$PATH"
"$compiler" --llvm --optimize=aggressive-inlining --path=output \
  --aot="full,static,direct-icalls,direct-pinvoke,tool-prefix=aarch64-none-elf-,llvm-outfile=output/Program.dll.llvm.o,llvm-path=${compiler%/*}/" \
  output/Program.dll
```

Link both Program.dll.o and Program.dll.llvm.o, compile dependencies likewise
and retain their AOT registration symbols. Explicit llvm-outfile is required
in static mode. Native imports selected by direct-pinvoke must exist in the
linked native application even if managed code does not execute every import.
See [AOT integration notes](aot.md) for the registration and metadata model.

The compiler must report LLVM enabled and invoke opt/llc. Backend availability
does not imply that every method uses LLVM, and AOT output is not proof of
trimming compatibility for arbitrary applications or dynamic managed code.

## Thread and TLS contracts

Mono managed threads use joinable pthreads. Thread.Join and the runtime's
joinable-thread registry own their native termination. Do not add a second
reaper or assume all callbacks return normally; managed exit can use pthread_exit.
The native BCL's detached callback API is a separate lifetime contract.

The runtime keeps TLS containers visible during destructor callbacks, clears
values before callbacks, bounds callback repetition, then clears and frees the
container at thread exit. Source checks are in the
[TLS cleanup harness](../tests/tls-cleanup/README.md); managed workloads are in
[lifecycle](../tests/lifecycle/README.md) and
[allocation controls](../tests/lifecycle-controls/README.md).
Their guides specify scope and output ownership, not captured results.
