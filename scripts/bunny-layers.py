# Prepares the bunny artist's layers for the bunny maker
# (native/Sugerly/Views/Bunny). Every layer is the same 878×1210 canvas.
#
#   python3 scripts/bunny-layers.py layers/ flat.png out/
#
# layers/ holds the exported layers named: fur, outline, skirt, pinafore,
# bloomers, sailor, and face-<name> for each face. flat.png is the finished
# picture (used to cut out the bow, which has no layer of its own).
#
# What it makes:
# - The sailor top split into the top and its collar (by colour), so the
#   collar can take its own colour.
# - Each face split into its eyes and the rest, so the bunny can blink.
# - The bow, with its outline: the part of the finished picture that the
#   body layers don't explain, in the top-right corner.
# - Every layer's average colour hue (for recolouring) printed as JSON.
# Needs numpy, pillow and scipy.
import sys, os, json, glob
from PIL import Image
import numpy as np
from scipy import ndimage as nd

src, flat, out = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)
W, H = 878, 1210

def load(name):
    return np.array(Image.open(os.path.join(src, name + ".png")).convert("RGBA")).astype(float) / 255

def save(name, a):
    a = a.copy()
    a[..., :3] *= (a[..., 3:] > 0)
    Image.fromarray((np.clip(a, 0, 1) * 255).round().astype(np.uint8)).save(os.path.join(out, name + ".png"), optimize=True)

def hsv(a):
    rgb = a[..., :3]
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = np.maximum(mx - mn, 1e-6)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    return h, s, mx

def mean_hue(a):
    h, s, v = hsv(a)
    m = (a[..., 3] > 0.5) & (s > 0.25) & (v > 0.35)
    if m.sum() == 0: return 0.0
    ang = np.radians(h[m])
    return float(np.degrees(np.arctan2(np.sin(ang).mean(), np.cos(ang).mean())) % 360)

hues = {}
for name in ["fur", "outline", "skirt", "pinafore", "bloomers"]:
    a = load(name)
    save("Bunny" + name.capitalize(), a)
    hues[name] = mean_hue(a)

# Sailor top → top + collar (the pinks and their dark outline).
sailor = load("sailor")
h, s, v = hsv(sailor)
yy, xx = np.mgrid[0:H, 0:W]
pinkish = ((h > 285) | (h < 20)) & (sailor[..., 3] > 0) & (yy < 780)
collar = nd.binary_closing(pinkish, iterations=2) & (sailor[..., 3] > 0) & (yy < 780)
c = sailor.copy(); c[..., 3] *= collar
t = sailor.copy(); t[..., 3] *= ~collar
save("BunnyCollar", c); save("BunnySailor", t)
hues["collar"] = mean_hue(c); hues["sailor"] = mean_hue(t)

# Faces → eyes + the rest. The eyes are the lowest dark blob on each side
# of the face (below any eyebrows, above the blush).
faces = {}
for path in sorted(glob.glob(os.path.join(src, "face-*.png"))):
    name = os.path.basename(path)[5:-4]
    a = load("face-" + name)
    lum = (a[..., :3] * [0.299, 0.587, 0.114]).sum(-1)
    def find_eyes(dark, grow):
        # Only the really dark ink (not the blush or a grey snout); the
        # biggest blobs on each side, the lowest of them (eyebrows sit above).
        ink = (a[..., 3] > 0.3) & (lum < dark)
        lab, n = nd.label(nd.binary_dilation(ink, iterations=grow) if grow else ink)
        found = np.zeros_like(ink)
        boxes = []
        for side in (-1, 1):
            best = None
            for k, sl in enumerate(nd.find_objects(lab), start=1):
                ys, xs = sl
                cx = (xs.start + xs.stop) / 2
                cy = (ys.start + ys.stop) / 2
                if side * (cx - W / 2) < 50 or cy > H * 0.47 or xs.stop - xs.start > 200 or (lab[sl] == k).sum() < 1200: continue
                if best is None or cy > best[1]: best = (k, cy, sl)
            if best:
                # The whole eye, with the shine inside it.
                found |= nd.binary_dilation(nd.binary_fill_holes(lab == best[0]), iterations=2)
                ys, xs = best[2]
                boxes.append([xs.start / W, ys.start / H, (xs.stop - xs.start) / W, (ys.stop - ys.start) / H])
        return found, boxes
    eyes, boxes = find_eyes(0.3, 3)
    if len(boxes) < 2:
        eyes, boxes = find_eyes(0.2, 0)
    e = a.copy(); e[..., 3] *= eyes
    r = a.copy(); r[..., 3] *= ~eyes
    title = name.capitalize()
    save(f"BunnyFace{title}", r); save(f"BunnyFace{title}Eyes", e)
    cy = float(np.mean([b[1] + b[3] / 2 for b in boxes])) if boxes else 0.4
    faces[name] = {"eyes": len(boxes), "eyeCenterY": round(cy, 4)}

# The bow: what the finished picture shows in the top-right corner that the
# fur and outline don't.
f = np.array(Image.open(flat).convert("RGBA")).astype(float) / 255
base = np.zeros((H, W, 4))
for layer in [load("fur"), load("outline")]:
    al = layer[..., 3:]
    base[..., :3] = layer[..., :3] * al + base[..., :3] * (1 - al)
    base[..., 3:] = al + base[..., 3:] * (1 - al)
diff = np.abs(f[..., :3] - base[..., :3]).sum(-1) + np.abs(f[..., 3] - base[..., 3])
region = (xx > 470) & (yy > 80) & (yy < 380)
bow = region & (diff > 0.18) & (f[..., 3] > 0.05)
# Just the bow itself (the biggest piece), not an eyebrow of the face
# that was in the finished picture.
lab, n = nd.label(nd.binary_closing(bow, iterations=3))
sizes = nd.sum(bow, lab, range(1, n + 1))
keep = lab == (int(np.argmax(sizes)) + 1)
fh, fs, fv = hsv(f)
bow = nd.binary_fill_holes(keep) & (f[..., 3] > 0.05) & ~((fs < 0.1) & (fv > 0.9))
b = f.copy(); b[..., 3] *= bow
save("BunnyBow", b)
hues["bow"] = mean_hue(b)

print(json.dumps({"hues": hues, "faces": faces}, indent=1))
