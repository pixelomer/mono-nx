#!/usr/bin/env python3
"""Compare first/last round native allocation owners using the exact linked ELF."""
import argparse
import json
from pathlib import Path
import re
import subprocess

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('elf',type=Path)
p.add_argument('log',type=Path)
p.add_argument('--legacy-base',type=lambda x:int(x,0),help='Explicit calibrated base for pre-anchor logs')
p.add_argument('--output',type=Path)
a=p.parse_args()
symbols=subprocess.check_output(['aarch64-none-elf-nm',str(a.elf)],text=True)
match=re.search(r'^([0-9a-f]+) T lifecycle_allocation_snapshot$',symbols,re.M)
if not match:raise SystemExit('Missing snapshot symbol')
offset=int(match[1],16)
snapshots={};tag='startup';current=None;base=a.legacy_base
for line in a.log.read_text().splitlines():
    if line.startswith('phase='):tag=line.split(' native_used=')[0]
    if line.startswith('PASS'):tag='final'
    if line.startswith('OWNERS begin'):
        if 'overflow=0 missed=0' not in line:raise SystemExit('Incomplete owner trace')
        anchor=re.search(r'anchor=(0x[0-9a-f]+)',line)
        if anchor:
            candidate=int(anchor[1],16)-offset
            if candidate%4096 or (base is not None and base!=candidate):raise SystemExit('Inconsistent image base')
            base=candidate
        if base is None:raise SystemExit('Legacy trace needs an explicitly calibrated --legacy-base')
        current={};snapshots[tag]=current
    record=re.match(r'owner pc=(0x[0-9a-f]+) count=(\d+) bytes=(\d+)',line)
    if record:
        current[int(record[1],16)-base]=(int(record[2]),int(record[3]))
results={}
for phase in ['threads-only','threads-alloc','threads-eh','main-eh']:
    first=snapshots['phase='+phase+' round=0'];last=snapshots['phase='+phase+' round=47']
    changes=[]
    for pc in first.keys()|last.keys():
        c0,b0=first.get(pc,(0,0));c1,b1=last.get(pc,(0,0))
        if b1!=b0 or c1!=c0:changes.append({'pc':hex(pc),'bytes_delta':b1-b0,'count_delta':c1-c0})
    changes.sort(key=lambda item:item['bytes_delta'],reverse=True)
    for item in changes:
        item['symbol']=subprocess.check_output(['aarch64-none-elf-addr2line','-f','-e',str(a.elf),item['pc']],text=True).strip().splitlines()
    results[phase]=changes
text=json.dumps({'image_base':hex(base),'changes':results},indent=2)+'\n'
if a.output:a.output.write_text(text)
else:print(text,end='')
