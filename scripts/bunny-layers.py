# Cuts the flat bunny picture into recolourable layers for the bunny maker
# (native/Sugerly/Views/Bunny). The parts are found by colour and by the
# dark outlines between them: fur, outfit (dress and navy cape), collar, bow,
# eyes (with fur painted in underneath so faces can be swapped) and the
# outlines. Needs numpy, pillow and scipy.
#
#   python3 scripts/bunny-layers.py bunny.png out/
#
# Then copy out/Bunny*.png into the matching Bunny*.imageset folders.
import sys, json
from PIL import Image
import numpy as np
from scipy import ndimage as nd

src, out = sys.argv[1], sys.argv[2]
img = Image.open(src).convert("RGBA")
a = np.array(img).astype(float) / 255
rgb, al = a[..., :3], a[..., 3]
H, W = al.shape
mx, mn = rgb.max(-1), rgb.min(-1)
v = mx
s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
# hue in degrees
r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
d = np.maximum(mx - mn, 1e-6)
h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
lum = 0.299 * r + 0.587 * g + 0.114 * b
op = al > 0.01
dark = op & (lum < 0.30)
light = op & ~dark

lab, n = nd.label(light)
sizes = nd.sum(light, lab, range(1, n + 1))
boxes = nd.find_objects(lab)

def comp_mask(pred):
    m = np.zeros_like(op)
    for k in range(1, n + 1):
        sl = boxes[k - 1]
        if sl is None: continue
        y0, y1, x0, x1 = sl[0].start, sl[0].stop, sl[1].start, sl[1].stop
        sub = lab[sl] == k
        mean = rgb[sl][sub].mean(0)
        if pred(k, x0, x1, y0, y1, int(sizes[k - 1]), mean):
            m[sl] |= sub
    return m

head = lab == (np.argmax(sizes) + 1)
pinkish = ((h > 300) | (h < 15)) & (s > 0.2) & (v > 0.6)
# The bow: everything light in the top-right corner except the head.
bow = comp_mask(lambda k, x0, x1, y0, y1, sz, m: x0 > 460 and y1 < 360) & ~head
# Collar: the magenta pieces at the neck.
collar = comp_mask(lambda k, x0, x1, y0, y1, sz, m: y0 > 650 and y1 < 770 and m[0] > 0.6 and m[1] < 0.45 and m[2] > 0.45)
# Outfit: light parts below the neck (dress, sleeves, skirt) that aren't legs or the brown petticoat.
below = comp_mask(lambda k, x0, x1, y0, y1, sz, m: y0 > 660) & ~collar
legs = below & pinkish & (np.mgrid[0:H, 0:W][0] > 960)
brownish = below & (h > 5) & (h < 45) & (v < 0.75)
outfit_light = below & ~legs & ~brownish
# Navy cape / skirt bands: dark but clearly blue.
navy = dark & (h > 195) & (h < 250) & (s > 0.45) & (np.mgrid[0:H, 0:W][0] > 640)
outfit = outfit_light | navy
body = head | legs

# Eyes: the two big dark ovals in the face, holes filled.
dlab, dn = nd.label(dark)
eyes = np.zeros_like(op)
for (x, y) in [(315, 458), (562, 458)]:
    ids = np.unique(dlab[y - 40:y + 40, x - 60:x + 60]); ids = ids[ids > 0]
    best = max(ids, key=lambda k: (dlab == k).sum())
    eyes |= nd.binary_fill_holes(dlab == best)
eyes = nd.binary_dilation(eyes, iterations=2) & op
eye_boxes = []
el, en = nd.label(eyes)
for sl in nd.find_objects(el):
    eye_boxes.append([sl[1].start / W, sl[0].start / H, (sl[1].stop - sl[1].start) / W, (sl[0].stop - sl[0].start) / H])

lines = op & ~(body | outfit | collar | bow) & ~eyes
body = body & ~eyes

# Under the eyes, the body continues: a smooth fur colour fitted to the ring
# around each eye (ignoring the blush), with a little of the fur's grain.
filled = rgb.copy()
face_fill = np.zeros_like(op)
rng = np.random.default_rng(7)
yy, xx = np.mgrid[0:H, 0:W]
for k in range(1, en + 1):
    eye = el == k
    hole = nd.binary_dilation(eye, iterations=3)
    ring = nd.binary_dilation(eye, iterations=18) & ~nd.binary_dilation(eye, iterations=5) & body
    pts = np.stack([np.ones(ring.sum()), xx[ring] / W, yy[ring] / H], 1)
    cols = rgb[ring]
    keep = np.ones(len(cols), bool)
    for _ in range(3):
        coef, *_ = np.linalg.lstsq(pts[keep], cols[keep], rcond=None)
        err = np.abs(cols - pts @ coef).sum(1)
        keep = err < np.median(err) * 2.2
    noise = (cols[keep] - pts[keep] @ coef).std(0)
    hp = np.stack([np.ones(hole.sum()), xx[hole] / W, yy[hole] / H], 1)
    filled[hole] = np.clip(hp @ coef + rng.normal(0, 1, (hole.sum(), 3)) * noise * 0.8, 0, 1)
    face_fill |= hole & ~body
def save(name, mask, colour=None, alpha=None):
    o = np.zeros((H, W, 4))
    o[..., :3] = rgb if colour is None else colour
    o[..., 3] = (al if alpha is None else alpha) * mask
    o[..., :3] *= (o[..., 3:] > 0)
    Image.fromarray((o * 255).round().astype(np.uint8)).save(f"{out}/{name}.png", optimize=True)

body_rgb = np.where(body[..., None], rgb, filled)
save("BunnyBody", body | face_fill, body_rgb, np.where(body, al, 1.0))
save("BunnyOutfit", outfit)
save("BunnyCollar", collar)
save("BunnyBow", bow)
save("BunnyEyes", eyes)
save("BunnyLines", lines)
print(json.dumps({"size": [W, H], "eyes": eye_boxes,
                  "coverage": {k: int(m.sum()) for k, m in [("body", body), ("outfit", outfit), ("collar", collar), ("bow", bow), ("eyes", eyes), ("lines", lines)]},
                  "unassigned": int((op & ~(body | outfit | collar | bow | eyes | lines)).sum())}))
