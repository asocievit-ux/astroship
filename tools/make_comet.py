"""Comet tail / coma sprites (additive, black = transparent). Bottom of a tail image = the nucleus.
Run from repo root: python3 tools/make_comet.py"""
import numpy as np
from PIL import Image
W, H = 128, 512
y, x = np.mgrid[0:H, 0:W].astype(np.float32)
t = 1 - (y + 0.5) / H              # 0 at the nucleus (bottom) -> 1 at the tail end (top)
xc = (x + 0.5) / W * 2 - 1         # -1..1 across
def tail(sig0, sig1, fall, color, gain, streaks=0.0, seed=0):
    sig = sig0 + (sig1 - sig0) * t
    across = np.exp(-(xc / sig) ** 2)
    along = np.exp(-t / fall) * np.clip(t / 0.02, 0, 1) * (1 - t) ** 1.5
    a = across * along
    if streaks:
        rng = np.random.default_rng(seed)
        s = rng.random(W).astype(np.float32)
        s = np.convolve(s, np.ones(5) / 5, mode="same")
        a *= (1 - streaks) + streaks * s[None, :] * 1.6
    img = np.clip(a[..., None] * np.array(color) * gain, 0, 1)
    return Image.fromarray((img * 255).astype(np.uint8))
tail(0.05, 0.22, 0.45, (0.45, 0.68, 1.0), 0.75, streaks=0.5, seed=3).save("Resources/Textures/comet_ion.png")
tail(0.12, 0.65, 0.30, (1.0, 0.92, 0.78), 0.55).save("Resources/Textures/comet_dust.png")
n = 128
yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
r = np.hypot(xx - n / 2 + 0.5, yy - n / 2 + 0.5) / (n / 2)
a = np.exp(-(r / 0.22) ** 2) * 0.9 + np.exp(-r / 0.25) * 0.35
img = np.clip(a[..., None] * np.array([0.85, 0.95, 1.0]), 0, 1) * (r < 1)[..., None]
Image.fromarray((img * 255).astype(np.uint8)).save("Resources/Textures/comet_coma.png")
print("ok")
