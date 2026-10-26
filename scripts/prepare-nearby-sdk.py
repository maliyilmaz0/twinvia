#!/usr/bin/env python3
"""Prepare the pinned Apache-2.0 Google Nearby source and reviewed local patch."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
source = root / '.tooling/google-nearby'
revision = 'f3e0f907adef395fd20fd8554e103bcc7d1b8fd7'
patch = root / 'vendor/nearby/ble-transport.patch'
if not source.exists():
    source.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['git','clone','--no-checkout','--depth','1','https://github.com/google/nearby.git',str(source)],check=True)
    subprocess.run(['git','fetch','--depth','1','origin',revision],cwd=source,check=True)
    subprocess.run(['git','checkout','--detach',revision],cwd=source,check=True)
head = subprocess.check_output(['git','rev-parse','HEAD'],cwd=source,text=True).strip()
if head != revision:
    raise SystemExit('Nearby tooling checkout differs from the pinned revision; preserve it and select the expected checkout explicitly.')
subprocess.run(['git','submodule','update','--init','--depth','1'],cwd=source,check=True)
already = subprocess.run(['git','apply','--reverse','--check',str(patch)],cwd=source,capture_output=True)
if already.returncode != 0:
    subprocess.run(['git','apply','--check',str(patch)],cwd=source,check=True)
    subprocess.run(['git','apply',str(patch)],cwd=source,check=True)
print('Nearby SDK pinned revision and local transport patch ready.')
