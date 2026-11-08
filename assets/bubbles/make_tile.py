"""The VoidGram mark pattern of the grey bubble skin, as one seamless tile.

The skin itself is a gradient drawn in code; only this small white-on-clear tile ships, so a
bubble of any size repeats it instead of stretching a screenshot.
"""
import subprocess
import sys
from PIL import Image

mark_svg, out = sys.argv[1], sys.argv[2]
SCALE = 3
TILE = 64 * SCALE  # 64 pt

subprocess.run(["rsvg-convert", "-w", "512", "-h", "512", mark_svg, "-o", "/tmp/mark.png"], check=True)
mark = Image.open("/tmp/mark.png").convert("RGBA")
# The whole mark in white: both wings at full strength, the inner triangle at its grey's
# strength (#BBBBBB), so the tile tints to any colour and keeps the logo's two tones.
r, g, b, a = mark.split()
alpha = Image.fromarray((__import__("numpy").asarray(r, dtype="float32") * __import__("numpy").asarray(a, dtype="float32") / 255.0).astype("uint8"))
glyph = Image.merge("RGBA", (Image.new("L", mark.size, 255),) * 3 + (alpha,))
glyph = glyph.crop(glyph.getbbox())

tile = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))

def safe_place(size_pt, angle, cx, cy):
    g = glyph.resize((size_pt * SCALE, round(size_pt * SCALE * glyph.height / glyph.width)), Image.LANCZOS)
    g = g.rotate(angle, resample=Image.BICUBIC, expand=True)
    layer = Image.new("RGBA", (TILE * 3, TILE * 3), (0, 0, 0, 0))
    layer.alpha_composite(g, (round((cx + 64) * SCALE - g.width / 2), round((cy + 64) * SCALE - g.height / 2)))
    for dx in range(3):
        for dy in range(3):
            tile.alpha_composite(layer.crop((dx * TILE, dy * TILE, dx * TILE + TILE, dy * TILE + TILE)))

# Two marks per tile, tilted like the reference, different sizes.
safe_place(26, 18, 20, 20)
safe_place(18, 18, 50, 50)
tile.save(f"{out}/VoidGramBubblePattern@3x.png", optimize=True)
print(tile.size)
