#!/usr/bin/env python3
"""Refresh app marks in the six shipped settings illustrations without taking over the desktop."""
from pathlib import Path
import subprocess
import tempfile

from PIL import Image

root = Path(__file__).resolve().parents[2]
capture_revision = '0d9d710779333b1b2279f04b53d919fb35557120'
master = Image.open(root / 'resources/icons/app/app.png').convert('RGBA')
variants = ['hide_colored_circles', 'hide_space_number_labels', 'hide_status_icons',
            'show_colored_circles', 'show_space_number_labels', 'show_status_icons']


def replace_mark(image, box, position, size):
    left, top, right, bottom = box
    for y in range(top, bottom):
        a, b = image.getpixel((left - 1, y)), image.getpixel((right, y))
        for x in range(left, right):
            fraction = (x - left + 1) / (right - left + 1)
            image.putpixel((x, y), tuple(round(a[c] * (1 - fraction) + b[c] * fraction) for c in range(4)))
    image.alpha_composite(master.resize((size, size), Image.Resampling.LANCZOS), position)


with tempfile.TemporaryDirectory() as directory:
    temp = Path(directory)
    for variant in variants:
        relative = f'resources/illustrations/thumbnails_{variant}_light@2x.heic'
        source, decoded = temp / 'source.heic', temp / 'decoded.png'
        source.write_bytes(subprocess.check_output(['git', 'show', f'{capture_revision}:{relative}'], cwd=root))
        subprocess.run(['sips', '-s', 'format', 'png', str(source), '--out', str(decoded)],
                       check=True, stdout=subprocess.DEVNULL)
        image = Image.open(decoded).convert('RGBA')
        replace_mark(image, (454, 207, 484, 236), (452, 205), 34)
        replace_mark(image, (498, 293, 507, 303), (496, 291), 14)
        image.save(decoded)
        subprocess.run(['sips', '-s', 'format', 'heic', '-s', 'formatOptions', '85',
                        str(decoded), '--out', str(root / relative)], check=True, stdout=subprocess.DEVNULL)
        print(relative)
