"""Cuts the gold frame out of its white backdrop and builds the bubble frame assets.

frame.jpg -> VoidGramBubbleFrame@3x.png  (9-slice: corners + 1 px stretch strips)
          -> VoidGramBubbleFrameTop@3x.png / VoidGramBubbleFrameBottom@3x.png (centre ornaments)
"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

src, out = sys.argv[1], sys.argv[2]
rgb = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
h, w, _ = rgb.shape

# Whiteness: bright and unsaturated. Gold is saturated, so it never qualifies.
mx, mn = rgb.max(axis=2), rgb.min(axis=2)
whiteness = np.clip((mn - 200.0) / 40.0, 0, 1) * np.clip(1.0 - (mx - mn - 12.0) / 30.0, 0, 1)
white = whiteness > 0.35

# Only white that is connected to the outside or to the picture opening is background.
labels, _ = ndimage.label(white)
seeds = set(labels[0, :]) | set(labels[-1, :]) | set(labels[:, 0]) | set(labels[:, -1]) | {labels[h // 2, w // 2]}
seeds.discard(0)
background = np.isin(labels, list(seeds))
# Soft edge: one-pixel ring keeps partial alpha from its whiteness.
ring = ndimage.binary_dilation(background, iterations=2) & ~background
alpha = np.where(background, 0.0, 1.0)
alpha = np.where(ring, 1.0 - whiteness, alpha)
alpha = ndimage.gaussian_filter(alpha, 0.6)

# Un-premultiply the white halo out of edge pixels.
a = np.clip(alpha, 1e-3, 1)[..., None]
colour = np.clip((rgb - 255.0 * (1 - a)) / a, 0, 255)
rgba = np.dstack([colour, alpha[..., None] * 255]).astype(np.uint8)

# Frame bounds.
ys, xs = np.where(alpha > 0.5)
x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
frame = Image.fromarray(rgba[y0:y1, x0:x1], "RGBA")
fw, fh = frame.size
frame.save(f"{out}/frame-cutout.png")

# The photo's rails differ (top ~68 px, sides ~81 px). Measure them from the opening and
# resample the top and bottom bands to the side's thickness, so the frame is even all round.
fa = np.asarray(frame)
opening = fa[..., 3] < 128
olab, _ = ndimage.label(opening)
inner = olab == olab[fh // 2, fw // 2]
iys, ixs = np.where(inner)
top_t, bottom_t, left_t = iys.min(), fh - 1 - iys.max(), ixs.min()
border = float(left_t)
def remap_rows(img, top, bottom, target):
    rows = []
    def band(y0, y1, n):
        part = img.crop((0, y0, img.width, y1))
        return part.resize((img.width, n), Image.LANCZOS)
    middle = img.crop((0, top, img.width, img.height - bottom))
    out = Image.new("RGBA", (img.width, target * 2 + middle.height), (0, 0, 0, 0))
    out.paste(band(0, top, target), (0, 0))
    out.paste(middle, (0, target))
    out.paste(band(img.height - bottom, img.height, target), (0, target + middle.height))
    return out
frame = remap_rows(frame, top_t, bottom_t, left_t)
fw, fh = frame.size
frame.save(f"{out}/frame-cutout.png")

point_thickness = 6.0
scale = point_thickness * 3.0 / border  # source px -> @3x px

corner_w, corner_h = 160, 160          # corner ornaments, source px
top_strip_x = 420                       # plain moulding column on top/bottom
side = np.asarray(frame)[:, :90, :3].astype(np.float32)
# Plainest row of the left side between the corner ornaments: least change to the next row.
rows = range(corner_h, fh - corner_h)
diffs = [np.abs(side[y] - side[y + 1]).mean() for y in rows]
side_strip_y = list(rows)[int(np.argmin(diffs))]

def crop(box):
    return frame.crop(box)

parts = {
    "tl": crop((0, 0, corner_w, corner_h)),
    # The right rail of the photo has a retouch seam; the right side mirrors the left.
    "tr": crop((0, 0, corner_w, corner_h)).transpose(Image.FLIP_LEFT_RIGHT),
    "bl": crop((0, fh - corner_h, corner_w, fh)),
    "br": crop((0, fh - corner_h, corner_w, fh)).transpose(Image.FLIP_LEFT_RIGHT),
    "t": crop((top_strip_x, 0, top_strip_x + 4, corner_h)),
    "b": crop((top_strip_x, fh - corner_h, top_strip_x + 4, fh)),
    "l": crop((0, side_strip_y, corner_w, side_strip_y + 4)),
    "r": crop((0, side_strip_y, corner_w, side_strip_y + 4)).transpose(Image.FLIP_LEFT_RIGHT),
}
# Compact source: corners with a 4 px plain strip between them; the centre stays clear.
compact = Image.new("RGBA", (corner_w * 2 + 4, corner_h * 2 + 4), (0, 0, 0, 0))
compact.paste(parts["tl"], (0, 0))
compact.paste(parts["t"], (corner_w, 0))
compact.paste(parts["tr"], (corner_w + 4, 0))
compact.paste(parts["l"], (0, corner_h))
compact.paste(parts["r"], (corner_w + 4, corner_h))
compact.paste(parts["bl"], (0, corner_h + 4))
compact.paste(parts["b"], (corner_w, corner_h + 4))
compact.paste(parts["br"], (corner_w + 4, corner_h + 4))

def scaled(img):
    return img.resize((max(1, round(img.width * scale)), max(1, round(img.height * scale))), Image.LANCZOS)

nine = scaled(compact)
nine.save(f"{out}/VoidGramBubbleFrame@3x.png", optimize=True)

# Centre ornaments of the top and bottom rails.
cx = fw // 2
orn_w = 240
top = crop((cx - orn_w // 2, 0, cx + orn_w // 2, corner_h))
bottom = crop((cx - orn_w // 2, fh - corner_h, cx + orn_w // 2, fh))
def feather(img, fraction=0.3):
    """Fades an ornament's sides into the rail it sits on."""
    img = img.copy()
    alpha = np.asarray(img.split()[3]).astype(np.float32)
    ramp = np.ones(img.width, np.float32)
    n = int(img.width * fraction)
    ramp[:n] = np.linspace(0, 1, n)
    ramp[-n:] = np.linspace(1, 0, n)
    img.putalpha(Image.fromarray((alpha * ramp[None, :]).astype(np.uint8)))
    return img

top, bottom = feather(top), feather(bottom)
scaled(top).save(f"{out}/VoidGramBubbleFrameTop@3x.png", optimize=True)
scaled(bottom).save(f"{out}/VoidGramBubbleFrameBottom@3x.png", optimize=True)

print("bands", top_t, bottom_t, left_t, "frame", fw, fh, "side strip", side_strip_y, "nine", nine.size, "cap px", round(corner_w * scale), round(corner_h * scale), "orn", scaled(top).size)
