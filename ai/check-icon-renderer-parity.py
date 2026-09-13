#!/usr/bin/env python3
"""Check the vendored renderer and regression tests against a companion checkout."""
import argparse
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("companion", type=Path, help="Path to macos/alt-tab-site-icons")
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
for local, upstream in [
    ("src/switcher/main-window/IconRenderer.swift", "Extension/IconRenderer.swift"),
    ("ai/IconRendererTests.swift", "test_renderer.swift"),
]:
    if (root / local).read_bytes() != (args.companion / upstream).read_bytes():
        raise SystemExit(f"Renderer parity failed: {local}")
print("Renderer source and regression tests match the companion")
