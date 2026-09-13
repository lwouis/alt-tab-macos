#!/usr/bin/env python3
"""Run isolated native-icon checks; public-site requests require --real-sites."""
import argparse
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--real-sites', action='store_true', help='Also fetch the eight reviewed public homepages and icons')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
env = {key: value for key, value in os.environ.items() if not key.startswith('ALTTAB_NATIVE_ICON_')}
env['ALTTAB_NATIVE_ICON_PROTOTYPE'] = '1'
renderer = root / 'src/switcher/main-window/IconRenderer.swift'
resolver = root / 'src/switcher/main-window/FixtureIconResolver.swift'
tests = ['IconRendererTests', 'FixtureIconResolverTests', 'FixtureIconStressTests', 'FixtureIconAdmissionTests', 'PublicWebsiteIconTests']
if args.real_sites:
    tests.append('RealWebsiteIconTests')

with socket.socket() as probe:
    try:
        probe.bind(('127.0.0.1', 18769))
    except OSError:
        raise SystemExit('Fixture port is already in use; no existing process was changed.')

with tempfile.TemporaryDirectory(prefix='alttab-native-tests-') as output:
    executables = []
    for name in tests:
        executable = str(Path(output) / name)
        sources = [str(renderer)] + ([] if name == 'IconRendererTests' else [str(resolver)])
        subprocess.run(['swiftc', *sources, str(root / 'ai' / (name + '.swift')), '-o', executable], check=True, env=env)
        executables.append((name, executable))
    with tempfile.TemporaryFile() as log:
        server = subprocess.Popen([sys.executable, str(root / 'ai/native-icon-server.py')], stdout=log, stderr=log, env=env)
        try:
            deadline = time.monotonic() + 5
            while True:
                if server.poll() is not None:
                    raise RuntimeError('The task fixture server could not start')
                try:
                    with socket.create_connection(('127.0.0.1', 18769), timeout=.2):
                        break
                except OSError:
                    if time.monotonic() >= deadline:
                        raise RuntimeError('The task fixture server did not become ready')
                    time.sleep(.05)
            for name, executable in executables:
                print(name, flush=True)
                command = [executable]
                if name == 'RealWebsiteIconTests':
                    command = [sys.executable, str(root / 'ai/run-native-icon-demo.py'), executable]
                run_env = dict(env)
                if name == 'PublicWebsiteIconTests':
                    run_env.pop('ALTTAB_NATIVE_ICON_PROTOTYPE', None)
                subprocess.run(command, check=True, env=run_env, timeout=180)
        finally:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()
print('All requested native-icon checks passed. Task fixture server stopped.')
