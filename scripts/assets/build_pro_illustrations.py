#!/usr/bin/env python3
"""Extract English feature artwork from the website's SVG illustrations.

Usage: python3 scripts/assets/build_pro_illustrations.py /path/to/alt-tab-website
Keeps the original vector windows and embedded photos; omits desktop/menu context.
CoreSVG doesn't implement SVG filters, so native AppKit supplies the surrounding card.
"""
import copy
from pathlib import Path
import re
import sys
from xml.etree import ElementTree as ET

ET.register_namespace('', 'http://www.w3.org/2000/svg')
source = Path(sys.argv[1]) / 'frontend/public/illustrations'
target = Path(__file__).resolve().parents[2] / 'resources/pro-illustrations'
target.mkdir(exist_ok=True)
for locale in ['en']:
    for feature in ['search', 'autosize', 'thumbnails', 'app-icons', 'titles']:
        source_feature = 'styles' if feature in ['thumbnails', 'app-icons', 'titles'] else feature
        original = ET.parse(source / f'{source_feature}.{locale}.full.svg').getroot()
        index = {'thumbnails': 0, 'app-icons': 1, 'titles': 2}.get(feature, 0)
        scene = copy.deepcopy([c for c in original if c.tag.endswith('}g')][index])
        scene.attrib.pop('transform', None)
        width, height = scene[0].get('width'), scene[0].get('height')
        root = ET.Element('{http://www.w3.org/2000/svg}svg', {
            'width': width, 'height': height, 'viewBox': f'0 0 {width} {height}'})
        root.extend(copy.deepcopy(c) for c in original if c.tag.endswith(('}style', '}defs')))
        root.append(scene)
        for node in root.iter():
            node.attrib.pop('filter', None)
            for key, value in list(node.attrib.items()):
                if re.fullmatch(r'#[0-9a-fA-F]{8}', value):
                    node.set(key, value[:7])
                    node.set(key + '-opacity', str(int(value[7:], 16) / 255))
        definitions = root.find('{http://www.w3.org/2000/svg}defs')
        by_id = {node.get('id'): node for node in definitions}
        used = set()
        pending = [scene]
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
        ET.ElementTree(root).write(target / f'{feature}.{locale}.svg', encoding='utf-8', xml_declaration=True)
