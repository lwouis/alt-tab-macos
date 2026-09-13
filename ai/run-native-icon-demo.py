#!/usr/bin/env python3
"""Launch a supplied test executable, or AltTab bundle, with only reviewed public URLs enabled."""
import json, os, pathlib, subprocess, sys
sites = json.loads(pathlib.Path(__file__).with_name('native-icon-sites.json').read_text())
env = dict(os.environ, ALTTAB_NATIVE_ICON_PROTOTYPE='1',
           ALTTAB_NATIVE_ICON_TEST_PAGES='|'.join(sites['pages']),
           ALTTAB_NATIVE_ICON_TEST_ASSETS='|'.join(sites['assets']))
if len(sys.argv) < 2: raise SystemExit('Usage: run-native-icon-demo.py <test-executable-or-AltTab.app> [arguments]')
print('Experimental website icons: independently fetches reviewed public homepages and icons, including for private windows. '
      'Document paths and queries are omitted; browser cookies and credentials are not used.', file=sys.stderr, flush=True)
if sys.argv[1].endswith('.app'):
    args = ['open', '-n']
    for key in ['ALTTAB_NATIVE_ICON_PROTOTYPE', 'ALTTAB_NATIVE_ICON_TEST_PAGES', 'ALTTAB_NATIVE_ICON_TEST_ASSETS']:
        args += ['--env', key + '=' + env[key]]
    args += ['--stdout', '/tmp/alttab-real-native.log', '--stderr', '/tmp/alttab-real-native.log', '-a', sys.argv[1], '--args'] + sys.argv[2:]
else: args = sys.argv[1:]
raise SystemExit(subprocess.call(args, env=env))
