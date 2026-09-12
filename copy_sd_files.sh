#!/bin/sh

set -e
CONFIGURATION=${CONFIGURATION:-Release}

# Copy the icu data file to the sd card files
mkdir -p sd_files/mono/etc/
cp $ICU_NX_INSTALL_DIR/share/icu/77.1/icudt77l.dat  sd_files/mono/etc/

# Copy the dotnet runtime dlls
mkdir -p sd_files/mono/lib_net9.0
mkdir -p sd_files/mono/framework_net9.0
cp $MONO_NX_ROOT/artifacts/bin/mono/libnx.arm64.${CONFIGURATION}/*.dll sd_files/mono/lib_net9.0/
cp $MONO_NX_ROOT/artifacts/bin/runtime/net9.0-libnx-${CONFIGURATION}-arm64/*.dll sd_files/mono/framework_net9.0/

# Copy mono and the fallback dll
cp native/interpreter/mono_nx.nro sd_files/mono/
cp managed/pad_input/bin/Release/net9.0/pad_input.dll sd_files/mono/

# Copy the managed binaries to the switch folder
mkdir -p sd_files/switch/
cp managed/pad_input/bin/Release/net9.0/pad_input.dll sd_files/switch/
cp managed/example/bin/Release/net9.0/example.dll sd_files/switch/

# We commit this binary file in the repo cause there is no way to build it on linux but it's one of the demos that can be run by mono-nx
cp native/aot/managed/guess_number.exe sd_files/switch/

mkdir -p sd_files/switch/explorer_demo/
cp managed/explorer_demo/bin/Release/net9.0/explorer_demo.dll sd_files/switch/explorer_demo/
cp managed/explorer_demo/bin/Release/net9.0/OpenSans-Regular.ttf sd_files/switch/explorer_demo/

# Copy the aot demo if it has been built
if [ -f native/aot/aot_example.nro ]; then
    cp native/aot/aot_example.nro sd_files/switch/
fi

# Preserve notices for the runtime and source-built native dependencies.
mkdir -p sd_files/mono/licenses
cp LICENSE sd_files/mono/licenses/mono-nx-MIT.txt
cp "$MONO_NX_ROOT/LICENSE.TXT" sd_files/mono/licenses/dotnet-MIT.txt
cp "$MONO_NX_ROOT/THIRD-PARTY-NOTICES.TXT" sd_files/mono/licenses/dotnet-third-party.txt
cp "$ICU_NX_INSTALL_DIR/share/icu/77.1/LICENSE" sd_files/mono/licenses/ICU.txt
if [ -f "$DEVKITPRO/libnx/LICENSE.md" ]; then
    cp "$DEVKITPRO/libnx/LICENSE.md" sd_files/mono/licenses/libnx.txt
else
    cp "$MONO_NX_ROOT/artifacts/horizon/sources/libnx/LICENSE.md" sd_files/mono/licenses/libnx.txt
fi

# Prepare the release
(cd sd_files && zip -r -9 ../sd_files.zip .)
