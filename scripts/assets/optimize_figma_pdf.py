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

Usage:
    python3 scripts/assets/optimize_figma_pdf.py path1.pdf path2.pdf ...

The script edits each PDF in place. Run after exporting from Figma. For the
final 1-2% squeeze, follow with:

    mutool clean -ggg -z in.pdf out.pdf
    qpdf --object-streams=generate --recompress-flate --compression-level=9 out.pdf final.pdf

Requires: pip3 install --user --break-system-packages pikepdf
"""
import sys

try:
    import pikepdf
    from pikepdf import Name
except ImportError:
    sys.stderr.write("pikepdf not installed. Run: pip3 install --user --break-system-packages pikepdf\n")
    sys.exit(1)


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
