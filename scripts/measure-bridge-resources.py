#!/usr/bin/env python3
"""Bounded, read-only CPU/RSS/PSS observations; never reset battery statistics."""
import argparse
import json
from pathlib import Path
import re
import statistics
import subprocess
import time

root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--label',required=True);parser.add_argument('--seconds',type=int,default=120)
args=parser.parse_args()
assert re.fullmatch(r'[a-zA-Z0-9-]+',args.label) and 30<=args.seconds<=600
directory=root/'.artifacts/resource-measurements';directory.mkdir(parents=True,exist_ok=True)
target=directory/(args.label+'.json');assert not target.exists()
adb=str(Path.home()/'Library/Android/sdk/platform-tools/adb')
def phone(*parts):return subprocess.check_output([adb,'shell',*parts],text=True,timeout=20)
def battery():
    text=phone('dumpsys','battery');record={}
    for line in text.splitlines():
        key,_,value=line.strip().partition(':')
        if key in ('AC powered','USB powered','Wireless powered','status','level','voltage','temperature'):record[key]=value.strip()
    return record
def cpu_seconds(text):
    parts=text.split(':');return sum(float(v)*(60**i) for i,v in enumerate(reversed(parts)))
def mac_processes():
    rows=subprocess.check_output(['ps','-axo','pid=,time=,rss=,comm='],text=True)
    result={}
    for row in rows.splitlines():
        parts=row.strip().split(None,3)
        if len(parts)==4 and parts[3].startswith('/Applications/Twinvia.app/'):
            result[parts[0]]={'cpuSeconds':cpu_seconds(parts[1]),'rssKiB':int(parts[2]),'name':Path(parts[3]).name}
    return result
before=battery();samples=[];previous=mac_processes();last=time.monotonic();deadline=last+args.seconds
print('Measuring '+args.label+' for '+str(args.seconds)+' seconds',flush=True)
while time.monotonic()<deadline:
    time.sleep(min(10,max(0,deadline-time.monotonic())))
    now=time.monotonic();current=mac_processes()
    cpu=sum(max(0,p['cpuSeconds']-previous[pid]['cpuSeconds']) for pid,p in current.items() if pid in previous)/(now-last)*100
    cpuinfo=phone('dumpsys','cpuinfo')
    android={}
    for line in cpuinfo.splitlines():
        match=re.match(r'\s*([0-9.]+)%\s+\d+/((?:dev\.androfest\.android|com\.google\.android\.gms)[^ :]*):',line)
        if match:android[match[2]]=float(match[1])
    mem=phone('dumpsys','meminfo','dev.androfest.android')
    pss=re.search(r'TOTAL PSS:\s*(\d+)',mem) or re.search(r'^\s*TOTAL\s+(\d+)',mem,re.M)
    samples.append({'at':time.time(),'macCPUPercentOneCore':round(cpu,3),'macRSSMiB':round(sum(p['rssKiB'] for p in current.values())/1024,2),
                    'macProcesses':current,'androidReportedCPUPercent':android,'androidPSSMiB':round(int(pss[1])/1024,2) if pss else None})
    previous=current;last=now
after=battery()
summary={'label':args.label,'durationSeconds':args.seconds,'batteryBefore':before,'batteryAfter':after,
         'batteryDrainMeasurementValid':False,'batteryNote':'USB remains attached; charge state and short duration do not establish battery drain or battery life.',
         'attributionNote':'Mac is summed process CPU and RSS; RSS double-counts shared pages. Android CPU uses dumpsys rolling intervals. Google Play services is shared with other apps.',
         'samples':samples,'macMedianCPUPercentOneCore':statistics.median(s['macCPUPercentOneCore'] for s in samples),
         'macMedianRSSMiB':statistics.median(s['macRSSMiB'] for s in samples),
         'androidMedianPSSMiB':statistics.median(s['androidPSSMiB'] for s in samples if s['androidPSSMiB'] is not None)}
target.write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps({k:summary[k] for k in ('label','macMedianCPUPercentOneCore','macMedianRSSMiB','androidMedianPSSMiB','batteryDrainMeasurementValid')}),flush=True)
