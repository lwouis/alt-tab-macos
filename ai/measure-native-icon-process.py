#!/usr/bin/env python3
"""Compare five equal-duration switcher cycles. Requires other AltTab instances to be stopped."""
import argparse, json, pathlib, subprocess, time
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('app', type=pathlib.Path)
args = parser.parse_args()
app = args.app.resolve()
binary = str(app / 'Contents/MacOS/AltTab')
sites = json.loads(pathlib.Path(__file__).with_name('native-icon-sites.json').read_text())
def samples():
    output = subprocess.check_output(['ps', '-axo', 'pid=,rss=,time=,comm='], text=True)
    rows = []
    for line in output.splitlines():
        fields = line.strip().split(None, 3)
        if len(fields) == 4 and fields[3] == binary:
            cpu = fields[2].split(':')
            seconds = float(cpu[-1]) + int(cpu[-2]) * 60
            if len(cpu) == 3: seconds += int(cpu[0]) * 3600
            rows.append((int(fields[0]), int(fields[1]), seconds))
    return rows
if samples(): raise SystemExit('Stop the existing development AltTab before measuring')
for enabled in [False, True]:
    command = ['open', '-n']
    for key, value in {
        'ALTTAB_NATIVE_ICON_PROTOTYPE': str(int(enabled)),
        'ALTTAB_NATIVE_ICON_TEST_PAGES': '|'.join(sites['pages']),
        'ALTTAB_NATIVE_ICON_TEST_ASSETS': '|'.join(sites['assets']),
        'ALTTAB_BENCHMARK_SHOW_MS': '5000',
    }.items(): command += ['--env', key + '=' + value]
    command += ['--stdout', '/tmp/alttab-process-measure.log', '--stderr', '/tmp/alttab-process-measure.log',
                '-a', str(app), '--args', '--logs=debug', '--benchmark', 'showUi', '5', '-localSafariSiteIcons', 'NO']
    subprocess.run(command, check=True)
    start = time.monotonic()
    seen = False
    peak_rss = 0
    last_cpu = 0
    while time.monotonic() - start < 60:
        rows = samples()
        if not rows and seen: break
        for pid, rss, cpu in rows:
            seen = True
            peak_rss = max(peak_rss, rss)
            last_cpu = max(last_cpu, cpu)
        time.sleep(.25)
    else: raise SystemExit('Benchmark did not finish; inspect the running process')
    if not seen: raise SystemExit('Benchmark process was not observed')
    print(json.dumps({'native': enabled, 'cycles': 5, 'shown_ms_per_cycle': 5000,
                      'elapsed_seconds': round(time.monotonic() - start, 2),
                      'sampled_peak_rss_kib': peak_rss, 'last_sampled_cpu_seconds': last_cpu}), flush=True)
