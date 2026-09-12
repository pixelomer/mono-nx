# Horizon Mono TLS cleanup contract

This host harness extracts the HOST_LIBNX implementation block from the
selected runtime's src/mono/mono/utils/mono-tls.c and compiles that block
against a small libnx TLS shim. It models libnx clearing the physical slot
before one destructor invocation.

Use Python 3.12+, a C11 compiler named cc, Bash and the source runtime pinned by
[runtime.lock.json](../../runtime.lock.json). No target binary or console is
needed. From this repository root:

```sh
python3 build.py --fetch-only
bash tests/tls-cleanup/run.sh
```

The runner defaults to MONO_NX_ROOT when set, otherwise this checkout's
dotnet_runtime directory. MONO_LLVM_RUNTIME_ROOT can explicitly select another
compatible source checkout. Do not use a packaged SDK here: the harness needs
the original mono-tls.c source, not only headers and archives.

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
