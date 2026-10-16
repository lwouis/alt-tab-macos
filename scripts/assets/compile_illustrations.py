#!/usr/bin/env python3
"""Compile the supported illustration SVG subset to shared native drawing instructions."""
from pathlib import Path
import xml.etree.ElementTree as E
import argparse, base64, hashlib, json, math, plistlib, re, tempfile

def compile_assets(source, out):
    out.mkdir(parents=True, exist_ok=True)
    ns = '{http://www.w3.org/2000/svg}'
    xlink = '{http://www.w3.org/1999/xlink}href'
    pools = {k: [] for k in ['nodes', 'paths', 'gradients']}
    lookup = {k: {} for k in pools}

    def intern(pool, value):
        key = json.dumps(value, sort_keys=True, separators=(',', ':'))
        if key not in lookup[pool]:
            lookup[pool][key] = len(pools[pool])
            pools[pool].append(value)
        return lookup[pool][key]

    def numbers(v):
        return list(map(float, re.findall('[-+]?(?:\\d*\\.\\d+|\\d+\\.?)(?:[eE][-+]?\\d+)?', v)))

    def path(d):
        tokens = re.findall('[a-zA-Z]|[-+]?(?:\\d*\\.\\d+|\\d+\\.?)(?:[eE][-+]?\\d+)?', d)
        i = 0
        cmd = None
        point = [0, 0]
        start = point
        last = None
        result = []
        while i < len(tokens):
            if tokens[i].isalpha():
                cmd = tokens[i]
                i += 1
            c = cmd.upper()
            relative = cmd.islower()
            if c == 'Z':
                result.append([3])
                point = start
                last = None
                cmd = None
                continue
            count = {'M': 2, 'L': 2, 'H': 1, 'V': 1, 'C': 6, 'S': 4, 'A': 7}[c]
            v = list(map(float, tokens[i:i + count]))
            i += count

            def xy(x, y):
                return [x + point[0], y + point[1]] if relative else [x, y]
            if c in ['M', 'L']:
                p = xy(*v)
                result.append([0 if c == 'M' else 1, *p])
                point = p
                if c == 'M':
                    start = p
                    cmd = 'l' if relative else 'L'
                last = None
            elif c in ['H', 'V']:
                p = point.copy()
                axis = 0 if c == 'H' else 1
                p[axis] = v[0] + (point[axis] if relative else 0)
                result.append([1, *p])
                point = p
                last = None
            elif c in ['C', 'S']:
                if c == 'C':
                    a = xy(*v[:2])
                    b = xy(*v[2:4])
                    p = xy(*v[4:])
                else:
                    a = [2 * point[j] - last[j] for j in range(2)] if last else point
                    b = xy(*v[:2])
                    p = xy(*v[2:])
                result.append([2, *a, *b, *p])
                point = p
                last = b
            elif c == 'A':
                (rx, ry, rot, large, sweep, x, y) = v
                p = xy(x, y)
                if rx != ry or rot != 0:
                    raise ValueError('Only circular, unrotated arcs are supported')
                dx = (point[0] - p[0]) / 2
                dy = (point[1] - p[1]) / 2
                r = max(rx, math.hypot(dx, dy))
                factor = math.sqrt(max(0, (r * r - dx * dx - dy * dy) / (dx * dx + dy * dy))) * (1 if large != sweep else -1)
                center = [(point[0] + p[0]) / 2 + factor * dy, (point[1] + p[1]) / 2 - factor * dx]
                a = math.atan2(point[1] - center[1], point[0] - center[0])
                b = math.atan2(p[1] - center[1], p[0] - center[0])
                delta = (b - a) % (2 * math.pi)
                if not sweep:
                    delta -= 2 * math.pi
                for step in range(max(1, math.ceil(abs(delta) / (math.pi / 2)))):
                    n = max(1, math.ceil(abs(delta) / (math.pi / 2)))
                    aa = a + delta * step / n
                    bb = a + delta * (step + 1) / n
                    k = 4 / 3 * math.tan((bb - aa) / 4)
                    q = [center[0] + r * math.cos(aa), center[1] + r * math.sin(aa)]
                    end = [center[0] + r * math.cos(bb), center[1] + r * math.sin(bb)]
                    result.append([2, q[0] - k * r * math.sin(aa), q[1] + k * r * math.cos(aa), end[0] + k * r * math.sin(bb), end[1] - k * r * math.cos(bb), *end])
                point = p
                last = None
        return intern('paths', result)

    def color(v, alpha=1):
        if v == 'none':
            return []
        if v.startswith('#'):
            h = v[1:]
            h = ''.join((c * 2 for c in h)) if len(h) == 3 else h
            return [int(h[i:i + 2], 16) / 255 for i in [0, 2, 4]] + [alpha]
        if v.startswith('rgba'):
            a = numbers(v)
            return [x / 255 for x in a[:3]] + [a[3] * alpha]
        raise ValueError(v)

    def transforms(v):
        result = []
        for (kind, args) in re.findall('(\\w+)\\(([^)]*)\\)', v):
            n = numbers(args)
            if kind == 'translate':
                result.append([1, 0, 0, 1, n[0], n[1] if len(n) > 1 else 0])
            elif kind == 'scale':
                result.append([n[0], 0, 0, n[1] if len(n) > 1 else n[0], 0, 0])
            elif kind == 'matrix':
                result.append(n)
            else:
                raise ValueError(kind)
        return result

    def validate(root):
        allowed = {'svg': {'width', 'height', 'x', 'y', 'viewBox', 'preserveAspectRatio'}, 'defs': set(), 'title': set(), 'g': set(), 'clipPath': set(), 'path': {'d'}, 'rect': {'x', 'y', 'width', 'height', 'rx', 'ry'}, 'circle': {'cx', 'cy', 'r'}, 'use': {'href', xlink, 'x', 'y'}, 'image': {'href', xlink, 'x', 'y', 'width', 'height', 'preserveAspectRatio'}, 'text': {'x', 'y', 'font-family', 'font-size', 'font-weight', 'text-anchor'}, 'linearGradient': {'x1', 'x2', 'y1', 'y2'}, 'radialGradient': {'cx', 'cy', 'r'}, 'stop': {'offset', 'stop-color', 'stop-opacity'}}
        common = {'id', 'fill', 'stroke', 'stroke-width', 'fill-opacity', 'stroke-opacity', 'stroke-linecap', 'stroke-linejoin', 'transform', 'clip-path', 'opacity', '{http://www.w3.org/XML/1998/namespace}lang'}
        ids = [e.get('id') for e in root.iter() if e.get('id')]
        if len(ids) != len(set(ids)):
            raise ValueError('Duplicate SVG ID')
        for e in root.iter():
            tag = e.tag.removeprefix(ns)
            if tag not in allowed:
                raise ValueError('Unsupported element: ' + tag)
            for attr in e.attrib:
                if attr not in allowed[tag] | common and (not attr.startswith(('data-', 'aria-'))):
                    raise ValueError('Unsupported attribute: ' + attr)
            if e.get('preserveAspectRatio') not in [None, 'none']:
                raise ValueError('Unsupported viewport alignment')
            if tag == 'text' and (list(e) or e.get('font-family') != 'Helvetica Neue' or e.get('font-weight') not in ['400', '600']):
                raise ValueError('Unsupported text layout')
            if tag == 'clipPath':
                if len(e) != 1:
                    raise ValueError('Clip must contain one shape')
                if set(e.attrib) - {'id'} or e[0].get('transform') or (e[0].tag == ns + 'use' and (e[0].get('x') or e[0].get('y'))):
                    raise ValueError('Unsupported clip transform')
    scenes = {}
    for file in sorted(source.glob('*.svg')):
        root = E.fromstring(file.read_bytes())
        validate(root)
        ids = {e.get('id'): e for e in root.iter() if e.get('id')}

        def gradient(ref):
            e = ids[ref]
            stops = [[float(s.get('offset')), *color(s.get('stop-color'), float(s.get('stop-opacity', '1')))] for s in e]
            kind = e.tag.removeprefix(ns)
            v = {'stops': stops, 'radial': kind == 'radialGradient'}
            if v['radial']:
                v['points'] = [float(e.get('cx', '.5')), float(e.get('cy', '.5')), float(e.get('r', '.5'))]
            else:
                v['points'] = [float(e.get(k, default)) for (k, default) in [('x1', '0'), ('y1', '0'), ('x2', '1'), ('y2', '0')]]
            return intern('gradients', v)

        def shape(e):
            tag = e.tag.removeprefix(ns)
            f = lambda k, d=0: float(e.get(k, str(d)))
            if tag == 'path':
                return {'path': path(e.get('d'))}
            if tag == 'rect':
                return {'rect': [f('x'), f('y'), f('width'), f('height'), f('rx'), f('ry', f('rx'))]}
            if tag == 'circle':
                return {'ellipse': [f('cx') - f('r'), f('cy') - f('r'), 2 * f('r'), 2 * f('r')]}
            if tag == 'use':
                return shape(ids[e.get(xlink)[1:]])
            raise ValueError(tag)

        def node(e, style=None, ancestors=()):
            if id(e) in ancestors:
                raise ValueError('Cyclic SVG reference')
            ancestors = (*ancestors, id(e))
            tag = e.tag.removeprefix(ns)
            if tag in ['defs', 'title', 'clipPath'] or e.get('data-preview-only') == 'true':
                return None
            inherited = dict(style or {'fill': '#000', 'stroke': 'none', 'stroke-width': '1', 'fill-opacity': '1', 'stroke-opacity': '1'})
            for k in ['fill', 'stroke', 'stroke-width', 'fill-opacity', 'stroke-opacity', 'stroke-linecap', 'stroke-linejoin']:
                if k in e.attrib:
                    inherited[k] = e.get(k)
            n = {}
            ts = transforms(e.get('transform', ''))
            if ts:
                n['transforms'] = ts
            if e.get('data-rtl-transform'):
                n['rtlTransforms'] = transforms(e.get('data-rtl-transform'))
            if e.get('clip-path'):
                clip = ids[e.get('clip-path')[5:-1]]
                assert len(clip) == 1
                n['clip'] = shape(clip[0])
            if e.get('opacity'):
                n['opacity'] = float(e.get('opacity'))
            if tag == 'svg':
                (w, h) = (float(e.get('width')), float(e.get('height')))
                vb = numbers(e.get('viewBox', f'0 0 {w} {h}'))
                n['transforms'] = ts + [[1, 0, 0, 1, float(e.get('x', '0')), float(e.get('y', '0'))], [w / vb[2], 0, 0, h / vb[3], -vb[0] * w / vb[2], -vb[1] * h / vb[3]]]
            if tag in ['svg', 'g']:
                children = [node(c, inherited, ancestors) for c in e]
                n['children'] = [c for c in children if c is not None]
            elif tag == 'use':
                ref = e.get(xlink) or e.get('href')
                if not ref.startswith('#'):
                    raise ValueError('External SVG reference')
                n['transforms'] = ts + [[1, 0, 0, 1, float(e.get('x', '0')), float(e.get('y', '0'))]]
                n['children'] = [node(ids[ref[1:]], inherited, ancestors)]
            elif tag == 'image':
                href = e.get(xlink) or e.get('href')
                if not href.startswith('data:image/jpeg;base64,'):
                    raise ValueError('Only embedded JPEGs are supported')
                data = base64.b64decode(href.split(',')[1], validate=True)
                name = hashlib.sha256(data).hexdigest()[:20] + '.jpg'
                (out / name).write_bytes(data)
                n['image'] = name
                n['rect'] = [float(e.get(k, '0')) for k in ['x', 'y', 'width', 'height']]
            elif tag == 'text':
                n['text'] = ''.join(e.itertext())
                n['x'] = float(e.get('x', '0'))
                n['y'] = float(e.get('y', '0'))
                n['font'] = e.get('font-family')
                n['fontSize'] = float(e.get('font-size'))
                n['bold'] = float(e.get('font-weight', '400')) >= 500
                n['anchor'] = e.get('text-anchor', 'start')
                for (attr, key) in [('data-i18n', 'localization'), ('data-dark-fill', 'darkFill')]:
                    if e.get(attr):
                        n[key] = color(e.get(attr)) if key == 'darkFill' else e.get(attr)
                for (attr, key) in [('data-max-width', 'maxWidth'), ('data-min-font-size', 'minimumSize')]:
                    if e.get(attr):
                        n[key] = float(e.get(attr))
                if e.get('data-highlight-query'):
                    n['highlightQuery'] = e.get('data-highlight-query')
                    n['highlightLocalization'] = e.get('data-highlight-i18n')
                    n['highlightFill'] = color(e.get('data-highlight-fill'))
                    n['highlightTextFill'] = color(e.get('data-highlight-text-fill'))
                    n['highlightLayout'] = numbers(e.get('data-highlight-layout'))
                    if not n['highlightLocalization'] or len(n['highlightLayout']) != 4:
                        raise ValueError('Highlight requires localization and offset, height, padding, radius')
            else:
                n.update(shape(e))
            if tag not in ['svg', 'g', 'use', 'image']:
                fill = inherited['fill']
                if fill.startswith('url('):
                    n['gradient'] = gradient(fill[5:-1])
                    n['fillAlpha'] = float(inherited['fill-opacity'])
                else:
                    n['fill'] = color(fill, float(inherited['fill-opacity']))
                n['stroke'] = color(inherited['stroke'], float(inherited['stroke-opacity']))
                n['strokeWidth'] = float(inherited['stroke-width'])
                n['roundCap'] = inherited.get('stroke-linecap') == 'round'
                n['roundJoin'] = inherited.get('stroke-linejoin') == 'round'
            return intern('nodes', n)
        scenes[file.stem] = {'root': node(root), 'size': [float(root.get('width')), float(root.get('height'))]}
    archive = {'version': 1, **pools, 'scenes': scenes}
    (out / 'scenes.plist').write_bytes(plistlib.dumps(archive, fmt=plistlib.FMT_BINARY, sort_keys=True))
    return archive

def main():
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=root / 'resources/svg-illustrations')
    parser.add_argument('--output', type=Path, default=root / 'resources/native-illustrations')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as temporary:
        generated = Path(temporary)
        archive = compile_assets(args.source, generated)
        expected = {p.name: p.read_bytes() for p in generated.iterdir()}
        actual = {p.name: p.read_bytes() for p in args.output.iterdir()} if args.output.exists() else {}
        if args.check:
            if actual != expected:
                raise SystemExit('Native illustrations are stale; run scripts/assets/compile_illustrations.py')
        else:
            args.output.mkdir(parents=True, exist_ok=True)
            for (name, data) in expected.items():
                (args.output / name).write_bytes(data)
            for name in actual.keys() - expected.keys():
                (args.output / name).unlink()
        print(f"{len(archive['scenes'])} illustrations, {len(archive['nodes'])} shared nodes, {len(archive['paths'])} paths, {len(archive['gradients'])} gradients; {sum(map(len, expected.values())):,} bytes")
if __name__ == '__main__':
    main()
