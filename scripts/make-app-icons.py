#!/usr/bin/env python3
"""Draws Sugerly's app icons (one per accent colour) at 1024 x 1024.

Mimi the bunny's head (the real drawing) peeking up from the bottom edge
on a soft gradient with polka dots and sparkles. Run from the repo root:
    python3 scripts/make-app-icons.py [out_dir] [accent ...]
Writes icon-<accent>.png (1024, for the home screen) and badge-<accent>.png
(512, without sparkles: the app draws its own twinkling ones on top).
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
S = 2  # drawn at 2x for smooth edges

ACCENTS = {
    "rose": (0xD9577F, 0xEE8FAE),
    "lavender": (0x7C5CF0, 0xB19CFF),
    "mint": (0x16A37F, 0x5FD3B0),
    "peach": (0xEE6E40, 0xFFAA80),
    "sky": (0x2F80E0, 0x7CBEFF),
}

# Where the sparkles sit (x, y, size, opacity) out of 1024 — the app's
# twinkling badge uses the same spots.
SPARKLES = [(206, 214, 92, 255), (820, 168, 64, 235), (884, 330, 34, 220), (120, 402, 30, 200)]


def rgb(h):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255)


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def vertical(size, c0, c1):
    g = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        g.putpixel((0, y), mix(c0, c1, t * t * (3 - 2 * t)))
    return g.resize(size, Image.BICUBIC)


def star(draw, cx, cy, r, color):
    pts = []
    for i in range(16):
        ang = math.pi / 8 * i - math.pi / 2
        # A soft four-point star: long points, pinched waist.
        k = i % 4
        rr = r if k == 0 else r * 0.18 if k == 2 else r * 0.26
        pts.append((cx + rr * math.cos(ang), cy + rr * math.sin(ang)))
    draw.polygon(pts, fill=color)


def ellipse(d, cx, cy, rx, ry, **kw):
    d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), **kw)


def icon(main_hex, light_hex, mimi, sparkles=True):
    main, light = rgb(main_hex), rgb(light_hex)
    deep = mix(main, (48, 12, 34), 0.62)            # outline and eyes
    top = mix(light, (255, 255, 255), 0.86)
    bottom = mix(light, (255, 255, 255), 0.5)

    bg = vertical((SIZE, SIZE), top, bottom).convert("RGBA")

    # Faint polka dots in the background.
    dots = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dots)
    step = 84
    for row, y in enumerate(range(-step, SIZE + step, step)):
        for x in range(-step, SIZE + step, step):
            ox = step / 2 if row % 2 else 0
            ellipse(dd, x + ox, y, 8, 8, fill=(255, 255, 255, 170))
    bg = Image.alpha_composite(bg, dots)

    # Mimi (the real drawing): just her head, peeking up from the bottom edge.
    art = Image.open(mimi).convert("RGBA")
    head = art.crop((0, 0, art.width, round(art.height * 0.575)))
    w = 740
    head = head.resize((w, round(head.height * w / head.width)), Image.LANCZOS)
    head = head.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))
    x, y = (SIZE - w) // 2, SIZE - head.height + 30
    shade = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    soft = Image.new("RGBA", head.size, deep + (0,))
    soft.putalpha(head.split()[3].filter(ImageFilter.GaussianBlur(18)).point(lambda v: int(v * 0.22)))
    shade.paste(soft, (x, y + 10), soft)
    bg = Image.alpha_composite(bg, shade)
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    layer.paste(head, (x, y), head)
    bg = Image.alpha_composite(bg, layer)

    if sparkles:
        sp = Image.new("RGBA", (SIZE * S, SIZE * S), (0, 0, 0, 0))
        d = ImageDraw.Draw(sp)
        for cx, cy, r, a in SPARKLES:
            star(d, cx * S, cy * S, r * S, mix(main, (255, 255, 255), 0.15) + (a,))
        bg = Image.alpha_composite(bg, sp.resize((SIZE, SIZE), Image.LANCZOS))
    return bg.convert("RGB")


MIMI = os.path.join(os.path.dirname(__file__), "..", "native", "Sugerly", "Assets.xcassets", "Mimi{0}.imageset", "mimi-{1}.png")

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    for name in sys.argv[2:] or list(ACCENTS):
        mimi = MIMI.format(name.capitalize(), name)
        icon(*ACCENTS[name], mimi).save(os.path.join(out, f"icon-{name}.png"))
        icon(*ACCENTS[name], mimi, sparkles=False).resize((512, 512), Image.LANCZOS).save(os.path.join(out, f"badge-{name}.png"))
        print("made", name)
