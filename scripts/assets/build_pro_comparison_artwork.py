#!/usr/bin/env python3
"""Export the website desktop and shortcut scenes as standalone English PDFs.

Usage: python3 scripts/assets/build_pro_comparison_artwork.py /path/to/alt-tab-website
Requires macOS 14+ for build-time SVG decoding. Runtime assets support macOS 12+.
"""
import copy
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from xml.etree import ElementTree as ET

ET.register_namespace('', 'http://www.w3.org/2000/svg')
source = Path(sys.argv[1]) / 'frontend/public/illustrations/shortcuts.en.full.svg'
target = Path(__file__).resolve().parents[2] / 'resources/pro-illustrations'
original = ET.parse(source).getroot()
namespace = '{http://www.w3.org/2000/svg}'
converter = '''import AppKit
let image = NSImage(contentsOfFile: CommandLine.arguments[1])!
var box = CGRect(origin: .zero, size: image.size)
let context = CGContext(URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL,
    mediaBox: &box, [kCGPDFContextCreator as String: ""] as CFDictionary)!
context.beginPDFPage(nil)
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
if CommandLine.arguments[2].hasSuffix("desktop.en.pdf") {
    let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(srgbRed: 27/255, green: 37/255, blue: 80/255, alpha: 1).cgColor,
        NSColor(srgbRed: 58/255, green: 63/255, blue: 118/255, alpha: 1).cgColor,
        NSColor(srgbRed: 93/255, green: 86/255, blue: 135/255, alpha: 1).cgColor
    ] as CFArray, locations: [0, 0.55, 1])!
    context.drawLinearGradient(sky, start: CGPoint(x: 0, y: box.height), end: .zero, options: [])

}
image.draw(in: box)
NSGraphicsContext.current = nil
context.endPDFPage()
context.closePDF()
'''
with tempfile.TemporaryDirectory() as temporary:
    work = Path(temporary)
    (work / 'export.swift').write_text(converter)
    scenes = [c for c in original if c.tag == namespace + 'g' and c[0].get('width') in ['1128', '760']]
    search = ET.parse(source.parent / 'search.en.full.svg').getroot()
    results = copy.deepcopy([c for c in search if c.tag == namespace + 'g'][0])
    for child in list(results)[1:7]:
        results.remove(child)
    results[0].set('height', '464.671')
    for child in list(results)[1:]:
        child.set('transform', child.get('transform').replace('142)', '18)'))
    all_windows = ET.parse(source.parent / 'autosize.en.full.svg').getroot()
    all_scene = copy.deepcopy([c for c in all_windows if c.tag == namespace + 'g'][1])
    for child in all_scene.iter():
        if child.text == 'Trip checklist':
            child.text = 'Japan checklist'
    for feature, scene, document in [('desktop', original[2], original),
            ('shortcuts-all', scenes[0], original), ('shortcuts-safari', scenes[1], original),
            ('search-results', results, search), ('search-all', all_scene, all_windows)]:
        scene = copy.deepcopy(scene)
        scene.attrib.pop('transform', None)
        if feature == 'desktop':
            root = scene
            root.attrib.pop('x', None)
            root.attrib.pop('y', None)
            # CoreSVG/PDF drops the radial glow's stop opacity. Keep the blue sky
            # and original vector hills; Quartz exports the sky gradient reliably.
            for child in list(root):
                if child.tag == namespace + 'defs' or child.get('fill') in ['url(#sky)', 'url(#glow)']:
                    root.remove(child)
        else:
            width, height = scene[0].get('width'), scene[0].get('height')
            root = ET.Element(namespace + 'svg', {'width': width, 'height': height, 'viewBox': f'0 0 {width} {height}'})
            root.extend(copy.deepcopy(c) for c in document if c.tag.endswith(('}style', '}defs')))
            root.append(scene)
            definitions = root.find(namespace + 'defs')
            by_id = {node.get('id'): node for node in definitions}
            used, pending = set(), [scene]
            while pending:
                node = pending.pop()
                for value in (v for child in node.iter() for v in child.attrib.values()):
                    refs = re.findall(r'url\(#([^)]*)\)', value)
                    if value.startswith('#') and value[1:] in by_id:
                        refs.append(value[1:])
                    for ref in refs:
                        if ref not in used and ref in by_id:
                            used.add(ref)
                            pending.append(by_id[ref])
            for node in list(definitions):
                if node.get('id') not in used:
                    definitions.remove(node)
        for node in root.iter():
            node.attrib.pop('filter', None)
            for key, value in list(node.attrib.items()):
                if re.fullmatch(r'#[0-9a-fA-F]{8}', value):
                    node.set(key, value[:7])
                    node.set(key + '-opacity', str(int(value[7:], 16) / 255))
        svg = work / (feature + '.svg')
        ET.ElementTree(root).write(svg, encoding='utf-8', xml_declaration=True)
        subprocess.run(['swift', str(work / 'export.swift'), str(svg), str(target / (feature + '.en.pdf'))], check=True)
