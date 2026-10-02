#!/usr/bin/env python3
"""Strip Figma-injected bloat from PDF assets while preserving rendering.

Drops the following without affecting how AppKit renders the PDF:
- /Info dict (Producer="Figma", Title=...) at both trailer and Catalog levels
- /Metadata XMP packet
- /StructTreeRoot, /ParentTree, /StructElem accessibility tags
- /Lang, /MarkInfo (page accessibility hints)
- Per-page /Annots, /StructParents, /Tabs, /Metadata
- /ProcSet [/PDF] (deprecated since PDF 1.4)
- Embedded ICC color profiles: every [/ICCBased N R] reference is replaced with
  /DeviceRGB or /DeviceGray, walking page Resources, Form XObject Resources,
  Image XObject /ColorSpace, and Pattern /Shading /ColorSpace dicts. This
  matters most for Figma's color icons (8+ patterns each referencing the same
  ICC profile object).
- Duplicate gradient functions: Figma emits a fresh /FunctionType stream per
  pattern even when several patterns share the same ramp. Identical ones are
  collapsed onto a single object.

Also shrinks the drawing itself, which is lossy but not visibly so at icon sizes:
- Path coordinates are rounded to PATH_DECIMALS. Figma writes 9 decimals, a
  millionth of a pixel on a 22pt icon. Zero-length segments left by the rounding
  are dropped (only in fill-only content, where they can't draw a cap).
- Sampled gradients (Figma's mesh-like fills) are resampled to at most
  SHADING_GRID x SHADING_GRID. Figma emits 25x25 even when the gradient covers
  ~16x10 device pixels.
At 3 decimals and a 13 grid, the menubar icons render within 3/255 of the
originals at @2x/@3x. Check with a before/after render when changing either.

Usage:
    python3 scripts/assets/optimize_figma_pdf.py path1.pdf path2.pdf ...

The script edits each PDF in place. Run after exporting from Figma. For the
final 1-2% squeeze, follow with:

    mutool clean -ggg -z in.pdf out.pdf
    qpdf --object-streams=generate --recompress-flate --compression-level=9 out.pdf final.pdf

Requires: pip3 install --user --break-system-packages pikepdf
"""
import sys
from decimal import Decimal

try:
    import pikepdf
    from pikepdf import Name
except ImportError:
    sys.stderr.write("pikepdf not installed. Run: pip3 install --user --break-system-packages pikepdf\n")
    sys.exit(1)

PATH_DECIMALS = 3
SHADING_GRID = 13

PATH_OPS = {'m', 'l', 'c', 'v', 'y', 're'}
STROKE_OPS = {'S', 's', 'B', 'B*', 'b', 'b*'}


def swap_icc_in_cs_dict(cs_dict):
    """Walk a ColorSpace dict; replace ICCBased entries with /DeviceRGB or /DeviceGray."""
    try:
        keys = list(cs_dict.keys())
    except Exception:
        return
    for key in keys:
        try:
            val = cs_dict[key]
            arr = list(val)  # auto-dereferences indirect refs
            if len(arr) >= 2 and str(arr[0]) == '/ICCBased':
                icc = arr[1]
                n = int(icc.get('/N', 1)) if hasattr(icc, 'get') else 1
                cs_dict[key] = Name('/DeviceGray' if n == 1 else ('/DeviceRGB' if n == 3 else '/DeviceCMYK'))
        except Exception:
            pass


def dedupe_functions(pdf):
    """Collapse byte-identical /Function streams onto one object.

    Figma writes a separate PostScript calculator stream for every gradient, even when
    several gradients share the same ramp. On menubar-2 that was the same function five
    times over, ~1 KB in a 3.5 KB file. Repointing is enough; the orphans disappear in
    remove_unreferenced_resources(). Keyed on the decoded program plus the dict fields
    that change how it's evaluated, so functions that merely look alike aren't merged.
    """
    canon = {}
    for obj in pdf.objects:
        try:
            if not isinstance(obj, pikepdf.Stream) or Name('/FunctionType') not in obj:
                continue
            key = (str(obj.get(Name('/FunctionType'))), str(obj.get(Name('/Domain'))),
                   str(obj.get(Name('/Range'))), bytes(obj.read_bytes()))
            canon.setdefault(key, obj)
        except Exception:
            pass
    if not canon:
        return

    # /Function lives on Shading dicts nested under page Resources → Pattern, which are
    # often direct (non-indirect) objects. Those all report objgen (0,0), so only memoize
    # indirect ones or the first direct dict would shadow every sibling.
    seen = set()

    def visit(node):
        objgen = node.objgen
        if objgen != (0, 0):
            if objgen in seen:
                return
            seen.add(objgen)
        try:
            items = [(k, node[k]) for k in node.keys()] if isinstance(node, pikepdf.Dictionary) \
                else [(None, v) for v in node]
        except Exception:
            return
        for key, val in items:
            try:
                if key == '/Function' and isinstance(val, pikepdf.Stream) and Name('/FunctionType') in val:
                    k = (str(val.get(Name('/FunctionType'))), str(val.get(Name('/Domain'))),
                         str(val.get(Name('/Range'))), bytes(val.read_bytes()))
                    target = canon.get(k)
                    if target is not None and val.objgen != target.objgen:
                        node[key] = target
                    continue
                if isinstance(val, (pikepdf.Dictionary, pikepdf.Array)):
                    visit(val)
            except Exception:
                pass

    for page in pdf.pages:
        visit(page.obj)


def round_number(x):
    d = Decimal(str(x)).quantize(Decimal(1).scaleb(-PATH_DECIMALS)).normalize()
    return Decimal(0) if d.is_zero() else d


def round_paths(stream):
    """Round path operands; drop segments that collapse onto the current point.

    Only path-construction operators are touched: `cm` scales, colors and alphas
    keep full precision (a 1% error on a gradient's `cm` moves it visibly).
    """
    ops = pikepdf.parse_content_stream(stream)
    can_drop = not any(str(op) in STROKE_OPS for _, op in ops)
    out = []
    cur = start = None
    for operands, op in ops:
        name = str(op)
        if name not in PATH_OPS:
            if name == 'h':
                cur = start
            out.append((operands, op))
            continue
        nums = [round_number(v) for v in operands]
        pts = [(nums[i], nums[i + 1]) for i in range(0, len(nums), 2)]
        if name in ('l', 'c', 'v', 'y') and can_drop and all(p == cur for p in pts):
            continue
        if name in ('m', 're'):
            cur = start = pts[0]
        else:
            cur = pts[-1]
        out.append((nums, op))
    stream.write(pikepdf.unparse_content_stream(out))


def resample_shading(fn):
    """Shrink a 2-input, 8-bit sampled function (/FunctionType 0) to SHADING_GRID per side.

    New samples are taken on the old lattice with bilinear interpolation, so the
    corners and edges stay exact. Anything else (1-input ramps, 16-bit, custom
    /Encode) is left alone.
    """
    try:
        size = [int(s) for s in fn.Size]
        if int(fn.FunctionType) != 0 or len(size) != 2 or int(fn.BitsPerSample) != 8:
            return
        if max(size) <= SHADING_GRID:
            return
        if Name('/Encode') in fn and [float(e) for e in fn.Encode] != [0, size[0] - 1, 0, size[1] - 1]:
            return
        w, h = size
        channels = len(fn.Range) // 2
        data = fn.read_bytes()
        if len(data) < w * h * channels:
            return
    except Exception:
        return
    nw, nh = min(w, SHADING_GRID), min(h, SHADING_GRID)

    def sample(x, y, c):
        return data[(y * w + x) * channels + c]

    out = bytearray()
    for j in range(nh):
        fy = j * (h - 1) / (nh - 1)
        y0 = int(fy); y1 = min(y0 + 1, h - 1); ty = fy - y0
        for i in range(nw):
            fx = i * (w - 1) / (nw - 1)
            x0 = int(fx); x1 = min(x0 + 1, w - 1); tx = fx - x0
            for c in range(channels):
                top = sample(x0, y0, c) * (1 - tx) + sample(x1, y0, c) * tx
                bot = sample(x0, y1, c) * (1 - tx) + sample(x1, y1, c) * tx
                out.append(round(top * (1 - ty) + bot * ty))
    fn.write(bytes(out))
    fn.Size = [nw, nh]
    fn.Encode = [0, nw - 1, 0, nh - 1]


def shrink_drawing(pdf):
    for page in pdf.pages:
        contents = page.obj.get(Name('/Contents'))
        streams = list(contents) if isinstance(contents, pikepdf.Array) else [contents]
        if len(streams) > 1:
            # Merge first: a path can span stream boundaries.
            page.contents_coalesce()
            streams = [page.obj.Contents]
        for s in streams:
            if s is not None:
                round_paths(s)
    for obj in pdf.objects:
        if isinstance(obj, pikepdf.Stream) and obj.get(Name('/Subtype')) == Name('/Form'):
            round_paths(obj)
        if isinstance(obj, pikepdf.Stream) and Name('/FunctionType') in obj:
            resample_shading(obj)


def optimize(path):
    before = open(path, 'rb').read()
    pdf = pikepdf.open(path, allow_overwriting_input=True)

    # Wipe document info dict — trailer level
    if pdf.docinfo is not None:
        for k in list(pdf.docinfo.keys()):
            del pdf.docinfo[k]

    # Strip catalog-level metadata + accessibility + inline /Info
    root = pdf.Root
    for k in ['/Metadata', '/StructTreeRoot', '/Lang', '/MarkInfo', '/Info',
              '/ViewerPreferences', '/PageLayout', '/PageMode', '/AcroForm',
              '/Outlines', '/Names', '/PageLabels', '/OpenAction']:
        if Name(k) in root:
            del root[Name(k)]

    # Walk every object — including Streams (Image and Form XObjects are streams,
    # not plain Dictionary). Patch every ColorSpace ref to swap ICC → Device*.
    for obj in pdf.objects:
        try:
            if not isinstance(obj, (pikepdf.Dictionary, pikepdf.Stream)):
                continue

            # Page-level cruft
            if obj.get(Name('/Type')) == Name('/Page'):
                for k in ['/Annots', '/StructParents', '/Tabs', '/Metadata']:
                    if Name(k) in obj:
                        del obj[Name(k)]

            subtype = obj.get(Name('/Subtype')) if Name('/Subtype') in obj else None

            # Image XObject: /ColorSpace may be a direct [/ICCBased ...] array or
            # an indirect ref to one. list(cs) auto-dereferences in pikepdf.
            if subtype == Name('/Image'):
                cs = obj.get(Name('/ColorSpace'))
                if cs is not None:
                    try:
                        arr = list(cs)
                        if len(arr) >= 2 and str(arr[0]) == '/ICCBased':
                            n = int(arr[1].get('/N', 3)) if hasattr(arr[1], 'get') else 3
                            obj[Name('/ColorSpace')] = Name('/DeviceGray' if n == 1 else '/DeviceRGB')
                    except Exception:
                        pass

            # Form XObject: has its own Resources
            if subtype == Name('/Form') and Name('/Resources') in obj:
                fres = obj[Name('/Resources')]
                if Name('/ColorSpace') in fres:
                    swap_icc_in_cs_dict(fres[Name('/ColorSpace')])
                if Name('/ProcSet') in fres:
                    del fres[Name('/ProcSet')]

            # Page Resources
            res = obj.get(Name('/Resources'))
            if res is not None and isinstance(res, pikepdf.Dictionary):
                if Name('/ColorSpace') in res:
                    swap_icc_in_cs_dict(res[Name('/ColorSpace')])
                if Name('/ProcSet') in res:
                    del res[Name('/ProcSet')]
                # Patterns may have Shading dicts whose /ColorSpace points at ICC.
                if Name('/Pattern') in res:
                    for pkey in list(res[Name('/Pattern')].keys()):
                        pat = res[Name('/Pattern')][pkey]
                        if not isinstance(pat, pikepdf.Dictionary):
                            continue
                        sh = pat.get(Name('/Shading'))
                        if sh is not None and isinstance(sh, pikepdf.Dictionary):
                            cs = sh.get(Name('/ColorSpace'))
                            if cs is not None:
                                try:
                                    arr = list(cs)
                                    if len(arr) >= 2 and str(arr[0]) == '/ICCBased':
                                        n = int(arr[1].get('/N', 3)) if hasattr(arr[1], 'get') else 3
                                        sh[Name('/ColorSpace')] = Name('/DeviceGray' if n == 1 else '/DeviceRGB')
                                except Exception:
                                    pass
                        if Name('/Resources') in pat:
                            patres = pat[Name('/Resources')]
                            if Name('/ColorSpace') in patres:
                                swap_icc_in_cs_dict(patres[Name('/ColorSpace')])
        except Exception:
            pass

    shrink_drawing(pdf)
    dedupe_functions(pdf)
    pdf.remove_unreferenced_resources()
    pdf.save(path,
             compress_streams=True,
             stream_decode_level=pikepdf.StreamDecodeLevel.specialized,
             object_stream_mode=pikepdf.ObjectStreamMode.generate,
             linearize=False,
             min_version='1.4')
    after = open(path, 'rb').read()
    pct = (len(before) - len(after)) * 100 // len(before) if len(before) else 0
    print(f"{path}: {len(before)} -> {len(after)} ({pct}% saved)")

    # Bitmap-leak alarm: every Image XObject left in the file means Figma rasterized
    # something it could have kept vector. Usually the source is a stroked path (fix:
    # ⌘⇧O Outline Stroke) or a layer effect (drop shadow, blur, blend mode). Hidden
    # layers can still produce bitmaps when referenced by a clipping/masking group —
    # delete them rather than just hiding. See .claude/skills/assets-optimization/SKILL.md.
    bitmaps = count_images(path)
    if bitmaps:
        print(f"  ⚠ WARNING: {bitmaps} embedded bitmap(s) found — Figma source needs cleanup,"
              f" optimizer can't fix this. Investigate the .fig file.", file=sys.stderr)
        return False
    return True


def count_images(path):
    """Return the number of Image XObjects inside the PDF."""
    pdf = pikepdf.open(path)
    count = 0
    for obj in pdf.objects:
        try:
            if isinstance(obj, (pikepdf.Dictionary, pikepdf.Stream)):
                if obj.get(Name('/Subtype')) == Name('/Image'):
                    count += 1
        except Exception:
            pass
    return count


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    any_bitmaps = False
    for path in sys.argv[1:]:
        if not optimize(path):
            any_bitmaps = True
    # Non-zero exit when any input still has a bitmap so CI/scripts can catch it.
    sys.exit(1 if any_bitmaps else 0)


if __name__ == '__main__':
    main()
