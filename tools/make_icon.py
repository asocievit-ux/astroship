"""App icon (1024x1024, no alpha): the opening view in miniature - warm Sun above centre, a faint
edge-on asteroid belt, and thin coloured helix trails streaming down from the Sun. Run from repo root."""
import math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 2048                      # supersampled, downscaled to 1024
random.seed(7)
cx, cy = S * 0.5, S * 0.40

def layer():
    return Image.new("RGB", (S, S), (0, 0, 0))

# background: near-black with a faint blue lift around the Sun
yy, xx = np.mgrid[0:S, 0:S]
r = np.hypot(xx - cx, (yy - cy) * 1.2) / S
bg = np.zeros((S, S, 3))
bg[..., 0] = 4 + 10 * np.exp(-r * 4); bg[..., 1] = 6 + 12 * np.exp(-r * 4); bg[..., 2] = 14 + 22 * np.exp(-r * 3)
img = Image.fromarray(bg.clip(0, 255).astype(np.uint8))

stars = layer(); d = ImageDraw.Draw(stars)
for _ in range(170):
    x, y = random.uniform(0, S), random.uniform(0, S)
    b = random.random() ** 2.5
    rad = 1.5 + 4 * b
    c = int(90 + 165 * b)
    tint = random.choice([(1, 1, 1), (1, .9, .8), (.85, .9, 1)])
    d.ellipse([x - rad, y - rad, x + rad, y + rad], fill=tuple(int(c * t) for t in tint))

# asteroid belt: dotted, nearly edge-on ellipse (brighter at the front)
belt = layer(); d = ImageDraw.Draw(belt)
for _ in range(2600):
    a = random.uniform(0, 2 * math.pi)
    k = random.gauss(1, 0.07)
    x = cx + 880 * k * math.cos(a); y = cy + 150 * k * math.sin(a) + random.gauss(0, 6)
    front = 0.55 + 0.45 * math.sin(a)
    c = int(random.uniform(70, 150) * front)
    rr = random.uniform(1.8, 3.6)
    d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=(c, int(c * .92), int(c * .82)))
belt = Image.blend(belt, belt.filter(ImageFilter.GaussianBlur(3)), 0.4)

# helix trails streaming down from the Sun
trails = layer(); d = ImageDraw.Draw(trails)
specs = [  # (end x offset at the bottom, helix amplitude, turns, colour, width)
    (-560, 40, 1.4, (255, 120, 80), 12),
    (-330, 70, 1.0, (140, 200, 255), 13),
    (-60, 150, 0.8, (255, 235, 170), 14),
    (150, 110, 1.2, (255, 215, 140), 12),
    (420, 60, 1.6, (120, 235, 255), 12),
]
for dx, amp, turns, col, w in specs:
    pts = []
    for i in range(400):
        t = i / 399
        y = cy + t * (S - cy + 40)
        grow = min(1, t * 4)
        x = cx + dx * t ** 1.1 + amp * grow * math.sin(2 * math.pi * turns * t)
        pts.append((x, y))
    d.line(pts, fill=col, width=w, joint="curve")
glow = trails.filter(ImageFilter.GaussianBlur(14))

# Sun: smooth radial glow (hot white core, warm halo)
rs = np.hypot(xx - cx, yy - cy)
sun_i = 255 * (1.2 * np.exp(-(rs / 75) ** 2) + 0.9 * np.exp(-rs / 120) + 0.45 * np.exp(-rs / 330))
sun_rgb = np.stack([sun_i * 1.0, sun_i * 0.78, sun_i * 0.48], -1)
sun_rgb += np.stack([255 * np.exp(-(rs / 70) ** 2)] * 3, -1) * np.array([0, 0.2, 0.45])
acc = np.asarray(img, float)
for L, g in [(stars, 1), (belt, 1), (glow, 1.3), (trails, 0.95)]:
    acc = acc + np.asarray(L, float) * g
acc = acc + sun_rgb
acc = 255 * (1 - np.exp(-acc / 255 * 1.1))     # soft tone map keeps highlights from clipping hard
out = Image.fromarray(acc.clip(0, 255).astype(np.uint8)).resize((1024, 1024), Image.LANCZOS).convert("RGB")
out.save("Resources/Assets.xcassets/AppIcon.appiconset/icon.png", optimize=True)
out.resize((180, 180), Image.LANCZOS).save("/workspace/icon/icon_180_preview.png")
out.resize((60, 60), Image.LANCZOS).save("/workspace/icon/icon_60_preview.png")
out.save("/workspace/icon/astroship_icon_1024.png")
print("ok")
