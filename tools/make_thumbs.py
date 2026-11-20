"""Body thumbnails for the fly-to picker, rendered from the app's own textures (Solar System Scope,
CC BY 4.0): lit orthographic spheres on transparent backgrounds; Saturn with its ring.
Run from repo root: python3 tools/make_thumbs.py"""
import math
import numpy as np
from PIL import Image

T = "Resources/Textures/"; OUT = "Resources/Thumbs/"
N = 192; SS = 3; M = N * SS

def tex(name):
    return np.asarray(Image.open(T + name).convert("RGB"), float) / 255

def render(name, texname, radius=0.92, tilt=18, lit=True, clouds=None, ring=False, lon0=0.0):
    t = tex(texname)
    th, tw = t.shape[:2]
    c = np.linspace(-1, 1, M)
    u, v = np.meshgrid(c, -c)                       # v up
    rgb = np.zeros((M, M, 3)); a = np.zeros((M, M))
    # pole tilted towards the viewer a little and rolled
    e = math.radians(27 if ring else 12); roll = math.radians(-tilt)
    pole = np.array([math.sin(roll) * math.cos(e), math.cos(roll) * math.cos(e), math.sin(e)])
    e1 = np.cross(pole, [0, 0, 1.0]); e1 /= np.linalg.norm(e1)
    e2 = np.cross(pole, e1)
    x, y = u / radius, v / radius
    rr = x * x + y * y
    inside = rr <= 1
    z = np.sqrt(np.clip(1 - rr, 0, 1))
    n = np.stack([x, y, z], -1)
    lat = np.arcsin(np.clip(n @ pole, -1, 1))
    lon = np.arctan2(n @ e2, n @ e1) + lon0
    ti = ((lat / math.pi + 0.5) * (th - 1)).astype(int).clip(0, th - 1)
    tj = (((lon / (2 * math.pi)) % 1) * (tw - 1)).astype(int).clip(0, tw - 1)
    col = t[th - 1 - ti, tj]
    if clouds is not None:
        cl = tex(clouds)[th - 1 - ti, tj].mean(-1, keepdims=True)
        col = col * (1 - cl) + cl
    L = np.array([-0.55, 0.35, 0.76]); L /= np.linalg.norm(L)
    if lit:
        shade = 0.06 + 0.94 * np.clip(n @ L, 0, 1) ** 0.85
        col = col * shade[..., None]
    else:                                            # the Sun: limb darkening, slight warm glow
        col = np.clip(col * (0.55 + 0.6 * z[..., None] ** 0.5) * 1.15, 0, 1)
    rgb[inside] = col[inside]; a[inside] = 1
    if ring:
        rt = np.asarray(Image.open(T + "saturn_ring.png").convert("RGBA"), float) / 255
        rt = rt.mean(0)                              # radial profile (2048 x 4)
        inner, outer = 74_500 / 58_232, 140_220 / 58_232
        # ring plane: normal = pole; ray (x, y, z) orthographic along -z
        zr = -(pole[0] * x + pole[1] * y) / pole[2]
        p = np.stack([x, y, zr], -1)
        r = np.linalg.norm(p, axis=-1)
        on = (r >= inner) & (r <= outer)
        k = ((r - inner) / (outer - inner) * (len(rt) - 1)).clip(0, len(rt) - 1).astype(int)
        rc = rt[k, :3]; ra = rt[k, 3] * on
        behind = inside & (zr < z)                   # the planet hides the far ring
        ra = np.where(behind, 0, ra)
        # planet shadow on the near ring is skipped; light the ring flatly a bit dimmer
        rc = rc * 0.85
        rgb = rgb * (1 - ra[..., None]) + rc * ra[..., None]
        a = np.maximum(a, ra)
    img = np.concatenate([rgb, a[..., None]], -1)
    im = Image.fromarray((img * 255).clip(0, 255).astype(np.uint8), "RGBA").resize((N, N), Image.LANCZOS)
    im.save(OUT + name + ".png", optimize=True)

render("sun", "sun.jpg", lit=False, radius=0.94)
for b in ["mercury", "venus", "mars", "jupiter", "uranus", "neptune", "ceres", "eris", "makemake", "moon"]:
    render(b, b + ".jpg", tilt=8 if b != "uranus" else 82)
render("earth", "earth.jpg", clouds="earth_clouds.jpg", tilt=23, lon0=2.2)
render("haumea", "haumea.jpg")
render("saturn", "saturn.jpg", radius=0.41, tilt=14, ring=True)
print("ok")
