"""Losslessly compress PNG data for generated brand assets."""
import oxipng


def optimize(data):
    result = oxipng.optimize_from_memory(
        data, level=6, strip=oxipng.StripChunks.safe(),
        deflate=oxipng.Deflaters.zopfli(15),
    )
    return result if len(result) < len(data) else data
