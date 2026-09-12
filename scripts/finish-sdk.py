#!/usr/bin/env python3
"""Add relocation support, notices and binary identity to the SDK staging tree."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
stage = Path(sys.argv[1]).resolve()
runtime = Path(os.environ['MONO_NX_ROOT'])
configuration = os.environ.get('CONFIGURATION', 'Release')
shutil.copytree(Path(os.environ['DEVKITPRO']) / 'libnx', stage / 'libnx')
for name in ['LICENSE.TXT', 'THIRD-PARTY-NOTICES.TXT']:
    shutil.copy2(runtime / name, stage / 'dotnet_runtime' / name)
shutil.copy2(runtime / 'artifacts/horizon/sources/libnx/LICENSE.md', stage / 'libnx/LICENSE.md')
notices = stage / 'licenses'
notices.mkdir()
for origin, name in [(root / 'LICENSE', 'mono-nx-MIT.txt'),
                     (runtime / 'LICENSE.TXT', 'dotnet-MIT.txt'),
                     (runtime / 'THIRD-PARTY-NOTICES.TXT', 'dotnet-third-party.txt'),
                     (runtime / 'artifacts/horizon/sources/libnx/LICENSE.md', 'libnx.txt'),
                     (runtime / 'artifacts/horizon/sources/icu/icu/LICENSE', 'ICU.txt')]:
    shutil.copy2(origin, notices / name)
shutil.copy2(root / 'scripts/configure-sdk.py', stage / 'configure-sdk.py')
(stage / 'README.md').write_text('''# Mono Horizon SDK

This SDK contains the Release LLVM cross compiler, matching runtime/framework,
ICU data and libnx. It requires a Linux x86-64 host, .NET SDK 9 and the devkitPro
compiler/portlibs recorded in sdk-manifest.json. Keep the licenses with it.

Python 3.12 or newer is required. Use SDK/toolchain paths without whitespace.
Configuration checks the packaged file hashes, updates .devkitpro symlinks
and replaces sdk-env.sh. Preserve any existing generated environment first.

After extracting or moving the SDK:

```sh
python3 configure-sdk.py --devkitpro /opt/devkitpro
source sdk-env.sh
```

Use a matching mono-nx source checkout (the repository containing gather_sdk.sh)
with this environment. Keep that source with the SDK or obtain it from the
same SDK distribution's source release. Its Release/LLVM application Makefiles
honor MONO_NX_ROOT and CONFIGURATION.
Do not run the application's source-build env.sh when using this SDK override.
The interpreter loads managed IL; LLVM AOT requires recompiling each application.
No game data, FMOD, Nintendo SDK or console files are included.
''')
compiler = stage / f'dotnet_runtime/artifacts/bin/mono/linux.x64.{configuration}/cross/linux-x64/libnx-arm64/mono-aot-cross'
information = subprocess.check_output([str(compiler), '--version'], text=True)
manifest = {'format': 1, 'configuration': configuration,
    'source_revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=runtime, text=True).strip(),
    'compiler': information, 'dependencies': json.loads((runtime / 'eng/libnx/dependencies.json').read_text()),
    'devkitA64': subprocess.check_output([os.environ['DEVKITA64'] + '/bin/aarch64-none-elf-gcc', '-dumpfullversion'], text=True).strip(),
    'files': {str(x.relative_to(stage)): hashlib.sha256(x.read_bytes()).hexdigest()
              for x in sorted(stage.rglob('*')) if x.is_file()}}
(stage / 'sdk-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
