#!/usr/bin/env python3
"""Draws Sugerly's app icons (one per accent colour) at 1024 x 1024.

A big glossy polka-dot "S" (the curly S from the logo) on a bright
gradient with soft dots and sparkles. Run from the repo root:
    python3 scripts/make-app-icons.py [out_dir]
"""
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 1024

ACCENTS = {
    "rose": (0xD9577F, 0xEE8FAE),
    "lavender": (0x7C5CF0, 0xB19CFF),
    "mint": (0x16A37F, 0x5FD3B0),
    "peach": (0xEE6E40, 0xFFAA80),
    "sky": (0x2F80E0, 0x7CBEFF),
}


def rgb(h):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255)


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def fast_gradient(size, c0, c1):
    """Diagonal gradient from c0 (top-left) to c1 (bottom-right)."""
    n = 256
    g = Image.new("RGB", (n, n))
    px = g.load()
    for y in range(n):
        for x in range(n):
            t = (x + y) / (2 * (n - 1))
            t = t * t * (3 - 2 * t)  # ease
            px[x, y] = mix(c0, c1, t)
    return g.resize(size, Image.BICUBIC)


def dots(size, spacing, radius, color, alpha, offset=0):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    w, h = size
    row = 0
    y = -spacing
    while y < h + spacing:
        x = -spacing + (spacing / 2 if row % 2 else 0) + offset
        while x < w + spacing:
            d.ellipse((x - radius, y - radius, x + radius, y + radius), fill=color + (alpha,))
            x += spacing
        y += spacing * 0.87
        row += 1
    return layer


def sparkle(draw, cx, cy, r, color):
    # A soft four-point star.
    pts = []
    for i in range(8):
        ang = math.pi / 4 * i - math.pi / 2
        rr = r if i % 2 == 0 else r * 0.28
        pts.append((cx + rr * math.cos(ang), cy + rr * math.sin(ang)))
    draw.polygon(pts, fill=color)


def bezier(p0, p1, p2, p3, steps=90):
    out = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        out.append((
            u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
            u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1],
        ))
    return out


# A round, bubbly "S" like the logo's: a top that starts on the right,
# a bowl on each side and a tail that curls up at the bottom left.
def _squash(points, k=0.86):
    return [(x, 520 + (y - 512) * k) for x, y in points]


S_PATH = _squash(
    bezier((738, 262), (690, 186), (604, 160), (512, 164))
    + bezier((512, 164), (378, 168), (290, 238), (298, 334))
    + bezier((298, 334), (308, 440), (430, 470), (520, 500))
    + bezier((520, 500), (640, 540), (734, 600), (726, 702))
    + bezier((726, 702), (716, 812), (610, 862), (505, 862))
    + bezier((505, 862), (400, 862), (318, 820), (286, 756))
)


def stroke_mask(radius, path=None):
    m = Image.new("L", (SIZE * 2, SIZE * 2), 0)
    d = ImageDraw.Draw(m)
    r = radius * 2
    for x, y in path or S_PATH:
        d.ellipse((x * 2 - r, y * 2 - r, x * 2 + r, y * 2 + r), fill=255)
    return m.resize((SIZE, SIZE), Image.LANCZOS)


MIMI = os.path.join(os.path.dirname(__file__), "..", "native", "Sugerly", "Assets.xcassets", "Mimi{0}.imageset", "mimi-{1}.png")


def icon(main_hex, light_hex, mimi=None, sparkles=True):
    main, light = rgb(main_hex), rgb(light_hex)
    deep = mix(main, (40, 10, 30), 0.45)          # outline colour
    pale = mix(light, (255, 255, 255), 0.72)      # letter fill
    top = mix(light, (255, 255, 255), 0.25)

    # With Mimi, the S sits a little lower so her head can peek over its top.
    k, dx, dy = (0.88, 0, 74) if mimi else (1.0, 0, 0)
    path = [(512 + (x - 512) * k + dx, 512 + (y - 512) * k + dy) for x, y in S_PATH]
    r = 66 * k

    # Background: bright gradient, soft glow, faint polka dots.
    bg = fast_gradient((SIZE, SIZE), top, main).convert("RGBA")
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((-320, -320, 820, 720), fill=(255, 255, 255, 90))
    glow = glow.filter(ImageFilter.GaussianBlur(190))
    bg = Image.alpha_composite(bg, glow)
    bg = Image.alpha_composite(bg, dots((SIZE, SIZE), 96, 8, (255, 255, 255), 30))

    fill = stroke_mask(r, path)
    outline = stroke_mask(r + 22 * k, path)
    halo = stroke_mask(r + 52 * k, path)

    # Mimi's head peeking over the top of the S (the S hides her chin).
    if mimi:
        art = Image.open(mimi).convert("RGBA")
        head = art.crop((0, 0, art.width, round(art.height * 0.62)))
        w = 232
        f = w / art.width
        head = head.resize((w, round(head.height * f)), Image.LANCZOS)
        pad = 30
        canvas = Image.new("RGBA", (head.width + pad * 2, head.height + pad * 2), (0, 0, 0, 0))
        canvas.paste(head, (pad, pad), head)
        edge = canvas.split()[3].filter(ImageFilter.MaxFilter(25)).filter(ImageFilter.GaussianBlur(1.2))
        cx = 540
        # Her chin rests on the S: everything down to her cheeks shows.
        column = [halo.getpixel((cx, yy)) for yy in range(SIZE)]
        s_top = next(yy for yy, v in enumerate(column) if v > 128)
        x = cx - canvas.width // 2
        y = round(s_top - 240 * f) - pad
        drop = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        shade = Image.new("RGBA", canvas.size, deep + (0,))
        shade.putalpha(edge.filter(ImageFilter.GaussianBlur(16)).point(lambda v: int(v * 0.35)))
        drop.paste(shade, (x, y + 12), shade)
        bg = Image.alpha_composite(bg, drop)
        layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        rim = Image.new("RGBA", canvas.size, (255, 255, 255, 0))
        rim.putalpha(edge)
        layer.paste(rim, (x, y), rim)
        layer.paste(canvas, (x, y), canvas)
        bg = Image.alpha_composite(bg, layer)

    # Soft shadow under the letter.
    shadow = Image.new("RGBA", (SIZE, SIZE), deep + (0,))
    shadow.putalpha(halo.filter(ImageFilter.GaussianBlur(26)).point(lambda v: int(v * 0.45)))
    bg = Image.alpha_composite(bg, ImageChops.offset(shadow, 0, 22))

    # White halo, then the dark outline.
    white = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    white.putalpha(halo)
    bg = Image.alpha_composite(bg, white)
    line = Image.new("RGBA", (SIZE, SIZE), deep + (0,))
    line.putalpha(outline)
    bg = Image.alpha_composite(bg, line)

    # Letter: pale gradient with polka dots, like the logo.
    body = fast_gradient((SIZE, SIZE), (255, 255, 255), pale).convert("RGBA")
    body = Image.alpha_composite(body, dots((SIZE, SIZE), 46, 8, light, 150, offset=12))
    body.putalpha(fill)
    bg = Image.alpha_composite(bg, body)

    # Gloss: a soft white shine across the top of the letter.
    shine = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(shine).ellipse((160 + dx, 90 + dy, 860 + dx, 430 + dy), fill=170)
    shine = shine.filter(ImageFilter.GaussianBlur(40))
    gloss = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    gloss.putalpha(ImageChops.multiply(shine, stroke_mask(40 * k, path)))
    bg = Image.alpha_composite(bg, gloss)

    # Little sparkles (in the app they twinkle on their own layer instead).
    if sparkles:
        sp = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        d = ImageDraw.Draw(sp)
        for cx, cy, rr, a in SPARKLES:
            sparkle(d, cx, cy, rr, (255, 255, 255, a))
        bg = Image.alpha_composite(bg, sp)
    return bg.convert("RGB")


# Where the sparkles sit (x, y, size, opacity) — the app's twinkling logo uses
# the same spots.
SPARKLES = [(846, 170, 62, 240), (930, 296, 26, 210), (130, 250, 38, 215)]


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    only = sys.argv[2:] or list(ACCENTS)
    for name in only:
        mimi = MIMI.format(name.capitalize(), name)
        icon(*ACCENTS[name], mimi=mimi).save(os.path.join(out, f"icon-{name}.png"))
        # Same art without sparkles, for the twinkling logo inside the app.
        icon(*ACCENTS[name], mimi=mimi, sparkles=False).resize((512, 512), Image.LANCZOS).save(os.path.join(out, f"badge-{name}.png"))
        print("made", name)
