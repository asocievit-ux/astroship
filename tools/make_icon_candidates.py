"""Icon candidates B and C (1024x1024 RGB, no text). A is tools/make_icon.py.
B: Sun centred in a tilted asteroid-belt ellipse on a black starfield.
C: Sun centred in a rounder belt ring, faint Milky Way band upper left, soft bluish galaxy glow below.
Usage: python3 tools/make_icon_candidates.py OUTDIR"""
import math, random, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 2048
out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
yy, xx = np.mgrid[0:S, 0:S].astype(float)

def blank():
    return Image.new("RGB", (S, S), (0, 0, 0))

def arr(img):
    return np.asarray(img, float)

def stars(seed, n=190):
    random.seed(seed)
    im = blank(); d = ImageDraw.Draw(im)
    for _ in range(n):
        x, y = random.uniform(0, S), random.uniform(0, S)
        b = random.random() ** 2.5
        r = 1.5 + 4.5 * b
        c = 90 + 165 * b
        t = random.choice([(1, 1, 1), (1, .9, .8), (.85, .9, 1)])
        d.ellipse([x - r, y - r, x + r, y + r], fill=tuple(int(c * k) for k in t))
    return arr(im)

def belt(seed, cx, cy, rx, ry, tilt_deg, n=5200, width=0.09):
    random.seed(seed)
    im = blank(); d = ImageDraw.Draw(im)
    ct, st = math.cos(math.radians(tilt_deg)), math.sin(math.radians(tilt_deg))
    for _ in range(n):
        a = random.uniform(0, 2 * math.pi)
        k = random.gauss(1, width)
        ex, ey = rx * k * math.cos(a), ry * k * math.sin(a)
        x, y = cx + ex * ct - ey * st, cy + ex * st + ey * ct
        front = 0.6 + 0.4 * math.sin(a)
        c = random.uniform(95, 190) * front
        r = random.uniform(2.0, 4.2)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(int(c), int(c * .93), int(c * .84)))
    im = Image.blend(im, im.filter(ImageFilter.GaussianBlur(3)), 0.35)
    return arr(im)

def sun(cx, cy, scale=1.0):
    rs = np.hypot(xx - cx, yy - cy) / scale
    i = 255 * (1.25 * np.exp(-(rs / 62) ** 2) + 0.85 * np.exp(-rs / 105) + 0.35 * np.exp(-rs / 300))
    rgb = np.stack([i, i * 0.76, i * 0.45], -1)
    rgb += np.stack([255 * np.exp(-(rs / 60) ** 2)] * 3, -1) * np.array([0, 0.22, 0.5])
    return rgb

def noise(seed, scales):
    rng = np.random.default_rng(seed)
    acc = np.zeros((S, S))
    for sigma, w in scales:
        n = Image.fromarray((rng.random((S // 8, S // 8)) * 255).astype(np.uint8)).resize((S, S), Image.BICUBIC)
        n = arr(n.filter(ImageFilter.GaussianBlur(sigma / 2))) / 255
        acc += w * (n - 0.5)
    return acc

def finish(acc, name):
    acc = 255 * (1 - np.exp(-np.clip(acc, 0, None) / 255 * 1.1))
    im = Image.fromarray(acc.clip(0, 255).astype(np.uint8)).resize((1024, 1024), Image.LANCZOS).convert("RGB")
    im.save(f"{out_dir}/{name}.png", optimize=True)

c = S / 2
bg = np.zeros((S, S, 3)); bg[..., 0] = 3; bg[..., 1] = 4; bg[..., 2] = 9

# B
acc = bg + stars(11) + belt(12, c, c, 820, 360, -10) + sun(c, c)
finish(acc, "B")

# C: Milky Way band across the upper left (diagonal), bluish galaxy glow below
band_axis = (xx * 0.42 + yy * 0.91 - S * 0.33) / S           # distance from a line rising to the right
band = np.exp(-(band_axis / 0.11) ** 2)
mw = band * (0.55 + 0.9 * noise(21, [(60, 1.0), (20, 0.6), (8, 0.3)]))
mw = np.clip(mw, 0, None) * (1 - 0.6 * np.clip(noise(22, [(25, 1.0), (10, 0.5)]) * 3, 0, 1) * band)  # dust lanes
mw_rgb = np.stack([mw * 70, mw * 66, mw * 72], -1)
gx, gy = c - 30, S * 0.875
u = ((xx - gx) * math.cos(0.9) + (yy - gy) * math.sin(0.9)) / 230
v = (-(xx - gx) * math.sin(0.9) + (yy - gy) * math.cos(0.9)) / 95
glow = np.exp(-(u ** 2 + v ** 2)) * (0.8 + 0.5 * noise(23, [(30, 1.0), (10, 0.4)]))
halo = np.exp(-((xx - gx) ** 2 + (yy - gy) ** 2) / (2 * 300 ** 2))
glow_rgb = np.stack([glow * 120 + halo * 18, glow * 135 + halo * 22, glow * 200 + halo * 45], -1)
acc = bg + mw_rgb + glow_rgb + stars(31, 220) + belt(32, c, c * 0.93, 640, 560, 0, n=5200, width=0.075) + sun(c, c * 0.93)
finish(acc, "C")
print("ok")
