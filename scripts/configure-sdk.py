#!/usr/bin/env python3
"""Configure a relocated Mono SDK against a local devkitPro toolchain."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex

root = Path(__file__).resolve().parent
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--devkitpro', type=Path, default=Path(os.environ.get('DEVKITPRO', '/opt/devkitpro')))
a = p.parse_args()
devkit = a.devkitpro.resolve()
if not (devkit / 'devkitA64/bin/aarch64-none-elf-gcc').is_file():
    p.error('Select an installed devkitPro toolchain')
if any(c.isspace() for c in str(root) + str(devkit)):
    p.error('Toolchain and SDK paths must not contain whitespace')
manifest = json.loads((root / 'sdk-manifest.json').read_text())
if manifest.get('format') != 1 or manifest.get('configuration') != 'Release' or not manifest.get('files'):
    raise SystemExit('Unsupported Mono SDK manifest')
for relative, expected in manifest['files'].items():
    item = root / relative
    if not item.resolve().is_relative_to(root) or not item.is_file():
        raise SystemExit('Invalid SDK input: ' + relative)
    if hashlib.sha256(item.read_bytes()).hexdigest() != expected:
        raise SystemExit('SDK hash mismatch: ' + relative)
overlay = root / '.devkitpro'
overlay.mkdir(exist_ok=True)
for source in [*(x for x in devkit.iterdir() if x.name != 'libnx'), root / 'libnx']:
    target = overlay / source.name
    if target.is_symlink(): target.unlink()
    if target.exists(): raise SystemExit('Refusing to replace ' + str(target))
    target.symlink_to(source, target_is_directory=source.is_dir())
values = {'DEVKITPRO': str(overlay), 'DEVKITA64': str(devkit / 'devkitA64'),
          'MONO_NX_ROOT': str(root / 'dotnet_runtime'),
          'ICU_NX_INSTALL_DIR': str(root / 'icu/libnx'),
          'CONFIGURATION': manifest['configuration'], 'MONO_AOT_LLVM': '1'}
lines = ['export ' + key + '=' + shlex.quote(value) for key, value in values.items()]
lines.append('export PATH=' + shlex.quote(str(devkit / 'devkitA64/bin') + ':' + str(devkit / 'tools/bin')) + ':"$PATH"')
(root / 'sdk-env.sh').write_text('\n'.join(lines) + '\n')
print('Source ' + str(root / 'sdk-env.sh') + ' before building applications.')
