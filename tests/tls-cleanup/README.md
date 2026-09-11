# Horizon Mono TLS cleanup contract

This host harness extracts the HOST_LIBNX implementation block from the
selected runtime's src/mono/mono/utils/mono-tls.c and compiles that block
against a small libnx TLS shim. It models libnx clearing the physical slot
before one destructor invocation.

Use Python 3, a C11 host compiler named cc, Bash and a source checkout of the
[TLS-capable runtime](https://github.com/pixelomer/dotnet-runtime/commit/a1b7b55d04454d003645f01972fffcccfdbb8b88).
No target runtime binary or console is needed. For a dedicated source checkout,
from this repository root:

```sh
git clone https://github.com/pixelomer/dotnet-runtime.git artifacts/tls-runtime
git -C artifacts/tls-runtime checkout --detach a1b7b55d04454d003645f01972fffcccfdbb8b88
MONO_LLVM_RUNTIME_ROOT="$(pwd)/artifacts/tls-runtime" bash tests/tls-cleanup/run.sh
```

The harness checks container reclamation, allocation-free null reads/writes,
callback values, bounded callback repetition and exclusion of freed keys.
The runtime must keep its TLS container visible during callbacks, clear values
before callbacks, enforce the four-pass bound, clear the physical slot and free
the container at thread exit. This contract is independent of LLVM optimization.

The helper writes the extracted source, its fingerprint, executable and output
to artifacts/tls-cleanup-host, replacing existing generated files. Keep user
inputs outside that directory. It executes the compiled host harness; assertion
failure is an error, not a captured baseline to reproduce.
This single-thread model does not establish concurrent key-reuse correctness
or the separate native BCL detached-callback contract.
