# LLVM lifecycle allocation controls

Four source workloads separate managed thread creation, array allocation and
explicit exception handling within one process:

- 48 rounds of eight created/joined threads with thread-static checks;
- the same thread pattern with 128 arrays of 16 KiB per worker;
- the same thread pattern with 128 catch/finally cases per worker;
- the equivalent exception workload on the existing main thread.

All phases force post-round collections, drain finalizers and allow 100 ms for
the join registry. Local Thread references leave a no-inline method before
sampling. During threaded phases main can collect while workers execute.
Each round records mallinfo used bytes and managed live estimates; the source
does not assert flat native memory.

Phases share a process and inherit its caches and allocator state. A phase's
growth is an association, not a unique allocation owner. Allocator used bytes
are not reserved address space, allocation traffic or RSS.
The separate native BCL detached callback API is outside this workload.

Use the source inputs and prerequisites in the
[lifecycle build guide](../lifecycle/README.md), including the public rel-3
Debug SDK layout and separate Release LLVM runtime/compiler:

```sh
MONO_SDK_ROOT="$(pwd)/artifacts/rel3-sdk" \
MONO_LLVM_RUNTIME_ROOT="$(pwd)/dotnet_runtime" \
bash tests/lifecycle-controls/build.sh
```

Run these commands from the repository root. The helper trims the managed
dependency closure, requires LLVM support and links both AOT object families.
It updates generated sources, ROMFS files, logs, input fingerprints and the NRO
under artifacts/lifecycle-controls-llvm; preserve needed outputs before rebuilding.

Run mono-llvm-lifecycle-controls.nro from that output directory in full
application mode. The first logger call overwrites
sdmc:/switch/mono-llvm-lifecycle-controls.txt; later calls append.
Preserve any existing log first and inspect all failure records and the final
summary. No deployment or system configuration is performed by the build helper.

## Plain native pthread control

The native logger runs a control when the managed BEGIN message arrives,
before the managed phases. It creates eight joinable pthreads per round across
48 rounds using the same libc/libnx implementation, without attaching those
callbacks to Mono. Every successfully created handle has one join owner.
The callbacks return their argument, and the control checks both join status
and returned identity, flushing each round's record to the same log.

These callbacks do not exercise formatting, TLS destructor edge cases or
arbitrary native libraries. Native counters alone do not prove allocation
ownership or justify adding another reaper to Mono's managed join path.
