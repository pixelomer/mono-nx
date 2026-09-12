# LLVM managed lifecycle probe

This source workload exercises explicit exceptions, moving collections,
thread-static isolation and joined managed threads using the Mono LLVM runtime.
It does not establish completeness of the runtime or every SDK configuration.

## Build inputs

Follow the [root build guide](../../README.md#build) for source inputs and
host/toolchain prerequisites. The helper uses the checkout's matching Release
runtime, framework, IL linker and LLVM compiler. It also needs Python,
ripgrep and a .NET 9 SDK on PATH.

From the repository root:

```sh
python3 build.py
source env.sh
bash tests/lifecycle/build.sh
```

The helper trims MonoLifecycle.dll with the selected SDK, checks LLVM support,
AOT-compiles every managed dependency and links both ordinary and LLVM objects.
It includes ICU data and uses the existing Mono launcher and native AOT template.
Generated sources, ROMFS inputs, logs, NRO and input fingerprints are written
under artifacts/lifecycle-llvm. Rebuilding updates those files in place; preserve
needed outputs and keep user inputs outside that generated directory.

## Workload and output ownership

The workload creates and joins eight managed threads in each of twenty rounds.
Workers check initially empty and isolated thread-static values and array
contents through collections, exercise explicit catch/finally and create
finalizable objects. Main requests full collections while workers run, joins
them, drains finalizers and records native allocator and managed live estimates.
The counters are workload parameters and expected checks, not captured results.
The source does not assert flat native allocator usage.

Run artifacts/lifecycle-llvm/mono-llvm-lifecycle.nro in full application mode.
Its logger overwrites sdmc:/switch/mono-llvm-lifecycle.txt on the first message,
then appends. Preserve any existing log before running. The launcher returns
normally when managed execution ends; inspect failure records and the final
summary rather than treating NRO creation or process exit as a pass.

Implicit null faults, stack overflow, arbitrary detached native callbacks,
async/networking and other runtime configurations are outside this workload.
Mono's managed Thread.Join path owns native joins; the separate native BCL
detached callback API requires its own lifetime contract.
