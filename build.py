#!/usr/bin/env python3
"""Fetch the matching Mono runtime, build LLVM/AOT and produce the interpreter."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent / 'scripts'))
from source_support import git_source, read_mirrors, run

ROOT = Path(__file__).resolve().parent
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--jobs', type=int, default=min(os.cpu_count() or 2, 8))
p.add_argument('--fetch-only', action='store_true')
p.add_argument('--runtime-only', action='store_true')
p.add_argument('--aot-example', action='store_true', help='Also compile/link the AOT example with LLVM')
p.add_argument('--source-mirrors', type=Path)
a = p.parse_args()
if a.jobs < 1: p.error('--jobs must be positive')
spec = json.loads((ROOT / 'runtime.lock.json').read_text())
runtime = git_source(spec, ROOT / 'dotnet_runtime', read_mirrors(a.source_mirrors))
if a.fetch_only:
    print(runtime)
    raise SystemExit(0)
command = [sys.executable, runtime / 'eng/libnx/build.py', '--flavor', 'mono', '--llvm', '--jobs', a.jobs]
if a.source_mirrors: command += ['--source-mirrors', a.source_mirrors.resolve()]
run(command)
env = os.environ | json.loads((runtime / 'artifacts/horizon/environment.json').read_text())
env.update(MONO_NX_ROOT=str(runtime), CONFIGURATION='Release', MONO_AOT_LLVM='1')
env['PATH'] = str(Path(env['DEVKITA64']) / 'bin') + ':' + env.get('PATH', '')
(ROOT / 'artifacts').mkdir(exist_ok=True)
(ROOT / 'artifacts/build-environment.json').write_text(json.dumps({k: env[k] for k in
    ['DEVKITPRO', 'DEVKITA64', 'ICU_NX_INSTALL_DIR', 'MONO_NX_ROOT', 'CONFIGURATION', 'MONO_AOT_LLVM']}, indent=2) + '\n')
if not a.runtime_only:
    run(['make', '-j', a.jobs], cwd=ROOT / 'native/interpreter', env=env)
    if a.aot_example:
        run(['bash', 'build_aot.sh'], cwd=ROOT / 'native/aot', env=env)
        run(['make', '-j', a.jobs], cwd=ROOT / 'native/aot', env=env)
print('Build environment: ' + str(ROOT / 'artifacts/build-environment.json'))
