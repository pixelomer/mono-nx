# mono-nx

> [!IMPORTANT]
> This fork contains AI-assisted changes. Most of the work was done by
> GPT-6 Astra. The produced code was not audited or verified by a human beyond
> running it and confirming that it works as expected. Human maintainability or
> readability was not a goal for this project.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

Mono for Nintendo Switch homebrew: an interpreter, AOT launcher and a Linux
x86-64 cross compiler with the LLVM backend. This fork builds on
[exelix11/mono-nx](https://github.com/exelix11/mono-nx) and keeps its MIT license,
examples and original [porting write-up](notes/writeup.md).

The matching source runtime is
[pixelomer/dotnet-runtime](https://github.com/pixelomer/dotnet-runtime), branch
`horizon-net9-mono`. `runtime.lock.json` pins the exact revision. For .NET 10
CoreCLR/RyuJIT or NativeAOT, use
[pixelomer/dotnet-switch](https://github.com/pixelomer/dotnet-switch).
Mono AOT and NativeAOT are different compilation paths.

## Build

Use Linux x86-64, Python 3.12+, Git, Bash, GCC/G++, Clang/LLVM, CMake, Ninja,
Make, patch, pkg-config, zip and .NET SDK 9. Install devkitPro devkitA64,
switch-tools and Switch portlibs (including SDL2/SDL2_image for the interpreter).
Set `DEVKITPRO` to your installation. The compiler baseline is devkitA64 15.2.0.
Install libnx as well; the runtime builds its pinned libnx source in an SDK overlay.

```sh
# From a source checkout of this repository:
python3 build.py --jobs 8
```

This fetches and builds the pinned runtime, libnx and ICU sources, bootstraps
the source-pinned Microsoft SDK and LLVM package, builds the matching IL linker,
and links `native/interpreter/mono_nx.nro`. Dependencies and build products stay
inside this checkout. System SDK installations are not replaced. Internet is
needed for Git, ICU and NuGet downloads. The compiler check requires `LLVM: yes`;
it does not silently substitute ordinary Mono AOT.

```sh
python3 build.py --aot-example       # also build the LLVM AOT example
source env.sh                       # select this checkout's build environment
./gather_sdk.sh                      # package the compiler/runtime development SDK
(cd managed && ./managed_build.sh)  # build the managed demos
./copy_sd_files.sh                   # assemble sd_files.zip after the demos
```

`--runtime-only` omits application linking; `--fetch-only` only fetches source.
An optional `--source-mirrors FILE` maps canonical Git URLs to local Git mirrors
for offline or pre-publication source testing. No built dependency directory is
required. The compatibility entry points `build_mono.sh` and `build_llvm.sh`
invoke this same runtime build.

`gather_sdk.sh` uses the configuration in `env.sh` (Release for this recipe).
Preserve the recorded runtime, LLVM and devkitA64 versions when using a packaged
SDK. The SDK is a cross-development tool, not a universal .NET runtime pack.

Use a dedicated checkout and keep user inputs outside generated output locations.
The source fetcher rejects dirty or mismatched existing dependency checkouts.
Runtime rebuilds update artifacts and the SDK overlay; ICU identity changes
can remove and recreate its generated source/build directories.

gather_sdk.sh deletes and recreates sdk_build and replaces
mono-nx-sdk-linux-x64.zip. The AOT example deletes native/aot/output and replaces
its ROMFS payload, registration header and log; Make replaces generated link
outputs. copy_sd_files.sh updates generated SD payloads and the ZIP in place.
Preserve needed outputs first; do not keep user data in staging directories.

To use the packaged SDK after extraction or relocation, run configure-sdk.py
there with --devkitpro selecting the installed toolchain, then source sdk-env.sh.
The configuration verifies the packaged files, updates .devkitpro symlinks and
writes sdk-env.sh; paths must not contain whitespace. Build applications from a
matching mono-nx source checkout with that environment. Do not source the source
checkout's env.sh over a configured packaged-SDK environment.

## Install the demos

Preserve existing SD files and configuration before extracting `sd_files.zip`
into the SD root: merging its `mono`, `switch` and `config` directories can
replace files with the same names. It includes the Homebrew Menu `.dll`/`.exe` file
association, which launches `/mono/mono_nx.nro` with the selected assembly.
Use the Homebrew Menu in full application mode. The `switch` directory contains
controller, API and GUI demos; `aot_example.nro` is the standalone AOT example.

Build your own .NET 9 program using the `managed/` examples and copy its DLLs to
`switch/` for the interpreter. Logging and runtime settings are described in
[config.ini](sd_files/mono/config.ini). Additional native imports need a custom
launcher build and registration in `native/shared`; see the
[original AOT notes](notes/aot.md) and [LLVM notes](notes/LLVM.md).

## Programs and integration

The `managed/` examples are ordinary .NET 9 assemblies. The interpreter loads
assemblies from the SD card; AOT emits static ARM64 objects and retains managed
metadata. LLVM AOT emits both the normal object and a separately named LLVM
object for each assembly; the example's Makefile links both.

Native imports must be statically linked and registered in `native/shared`.
The original interpreter provides libnx and optional SDL/GUI wrappers. It does
not provide arbitrary dynamic native-library loading. Full application memory
is recommended; Horizon 21+ requires libnx 4.10.0 or newer. The build recipe uses
the pinned public libnx fork and its native threading/filesystem fixes.

HTTPS/security APIs, subprocesses, desktop UI and other OS-specific facilities
are not generally supported. The source workloads document their covered
operations and limits; a successful build does not establish application behavior.

No game files, FMOD libraries, Nintendo SDK or console keys are needed to build
mono-nx. Report this fork's issues here rather than treating them as upstream
.NET support obligations.
