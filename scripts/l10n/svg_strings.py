#!/usr/bin/env python3
"""Expose standalone SVG text to the existing genstrings translation workflow."""
import json
from pathlib import Path
import xml.etree.ElementTree as ET


def extract(folder):
    entries = {}
    for path in sorted(folder.glob('*.svg')):
        for element in ET.parse(path).iter():
            identifier = element.get('data-i18n')
            if identifier:
                text = ''.join(element.itertext())
                entries.setdefault(text, set()).add(identifier)
    return entries


def swift_string(value):
    # These files are input to genstrings, never compiled or shipped.
    return json.dumps(value, ensure_ascii=False)


def source(entries):
    return '\n'.join(
        f'NSLocalizedString({swift_string(text)}, comment: {swift_string("Illustration: " + ", ".join(sorted(ids)))})'
        for text, ids in sorted(entries.items())
    ) + '\n'


if __name__ == '__main__':
    folder = Path(__file__).resolve().parents[2] / 'resources/svg-illustrations'
    print(source(extract(folder)), end='')
