"""Procedural top-down Milky Way for the galaxy screen (Resources/Textures/galaxy_top.jpg).
Same geometry as before: image edge = 16 kpc, Sun straight below the centre at 8.2 kpc, disc turning
clockwise as seen (arms trail counter-clockwise outward), bar ~27 deg from the Sun-centre line.
Looks: warm bar/bulge with a soft core, blue-white arms made of feathery spiral-aligned noise with
star clusters and pink HII knots, dark dust lanes on the arms' inner edges, a faint diffuse disc and
field stars, plus a gentle bloom. Run from repo root: python3 tools/make_galaxy.py"""
import math
import numpy as np
from PIL import Image, ImageFilter

S = 2048; R = 16.0
rng = np.random.default_rng(11)
y, x = np.mgrid[0:S, 0:S].astype(np.float32)
X = (x + 0.5) / S * 2 * R - R
Y = -((y + 0.5) / S * 2 * R - R)
r = np.hypot(X, Y) + 1e-4
th = np.arctan2(Y, X)
pitch = math.radians(13.5); k = 1 / math.tan(pitch)
sun_th = -math.pi / 2

def periodic_fbm(h, w, beta, seed):
    g = np.random.default_rng(seed)
    f = np.fft.fft2(g.standard_normal((h, w)))
    ky = np.fft.fftfreq(h)[:, None]; kx = np.fft.fftfreq(w)[None, :]
    kk = np.sqrt(kx ** 2 + ky ** 2); kk[0, 0] = 1
    n = np.real(np.fft.ifft2(f / kk ** beta))
    n = (n - n.mean()) / n.std()
    return n.astype(np.float32)

# Spiral coordinates: u along the arms (angle relative to the log spiral), v = ln r.
lnr = np.log(np.clip(r, 0.25, R * 1.5))
u = np.mod(th - k * lnr, 2 * np.pi)
V0, V1 = math.log(0.25), math.log(R * 1.5)
def sample(tex, uu, vv, stretch=1.0):
    h, w = tex.shape
    iu = (uu / (2 * np.pi) * w * stretch).astype(np.int64) % w
    iv = ((vv - V0) / (V1 - V0) * (h - 1)).clip(0, h - 1).astype(np.int64)
    return tex[iv, iu]
feather = sample(periodic_fbm(512, 1280, 0.95, 1), u, lnr)
fine = sample(periodic_fbm(1024, 2560, 0.6, 2), u, lnr)
clump = periodic_fbm(1024, 1024, 0.8, 3)
cl = clump[(y.astype(int) // 2) % 1024, (x.astype(int) // 2) % 1024]

def arm_phase(theta_at, r_at):
    return theta_at - k * math.log(r_at)
def arm(theta0, width_kpc, rmin, rmax):
    d = np.angle(np.exp(1j * (u - np.mod(theta0, 2 * np.pi))))      # angular offset across the arm
    dist = d * r / k * 1.0                                               # signed, ~kpc across
    w = width_kpc * (0.55 + 0.09 * r)
    prof = np.exp(-(dist / w) ** 2)
    env = np.clip((r - rmin) / 1.2, 0, 1) * np.exp(-np.clip(r - rmax, 0, None) / 1.8)
    return prof * env, dist / w

# Major arms (Perseus, Scutum-Centaurus) and minor (Sagittarius-Carina, Norma-Outer), Orion spur.
majors = [arm_phase(sun_th, 10.4), arm_phase(sun_th, 10.4) + math.pi]
minors = [arm_phase(sun_th, 6.7), arm_phase(sun_th, 6.7) + math.pi]
A = np.zeros_like(r); lane = np.zeros_like(r)
for t0 in majors:
    p, s = arm(t0, 0.5, 3.2, 15.5); A += p
    lane += np.exp(-((s + 0.85) / 0.35) ** 2) * (p > 0.02) * np.clip((r - 3.2) / 1.2, 0, 1) * np.exp(-np.clip(r - 14, 0, None))
for t0 in minors:
    p, s = arm(t0, 0.36, 3.6, 13.5); A += 0.75 * p
    lane += 0.7 * np.exp(-((s + 0.85) / 0.35) ** 2) * (p > 0.02) * np.clip((r - 3.6) / 1.2, 0, 1) * np.exp(-np.clip(r - 12, 0, None))
spur, _ = arm(arm_phase(sun_th, 8.2), 0.4, 6.5, 10.0)
spur *= np.exp(-(np.angle(np.exp(1j * (th - sun_th))) / 0.5) ** 2)
A += 0.55 * spur
armlight = A * np.clip(0.55 + 0.22 * feather + 0.03 * fine + 0.35 * cl, 0, None) * 1.25
armlight = np.asarray(Image.fromarray((np.clip(armlight / 3, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.6)), np.float32) / 255 * 3

img = np.zeros((S, S, 3), np.float32)
# diffuse old disc: warm inside, neutral outside, with spiral-aligned faint structure
disc = np.exp(-r / 3.2) * (0.55 + 0.2 * cl) * 1.0
img += disc[..., None] * np.array([0.62, 0.52, 0.40])
img += (np.exp(-r / 6.0) * 0.12 * np.clip(0.6 + feather, 0, None))[..., None] * np.array([0.5, 0.55, 0.65])
# bar + bulge
ba = math.radians(-90 + 27)
bx = X * math.cos(ba) + Y * math.sin(ba); by = -X * math.sin(ba) + Y * math.cos(ba)
bar = np.exp(-(bx / 4.2) ** 2 - (by / 0.95) ** 2) * (0.9 + 0.15 * cl)
img += bar[..., None] * np.array([1.0, 0.78, 0.48]) * 1.35
bulge = np.exp(-(r / 1.1) ** 2)
img += bulge[..., None] * np.array([1.0, 0.88, 0.66]) * 1.0
img += np.exp(-(r / 0.35) ** 2)[..., None] * np.array([1.0, 0.96, 0.88]) * 1.2
# ring of gas/star formation at the bar ends
ring = np.exp(-((r - 4.2) / 0.5) ** 2) * np.clip(0.5 + feather, 0, None) * 0.35
img += ring[..., None] * np.array([0.65, 0.72, 1.0])
# arms: blue-white young stars
img += armlight[..., None] * np.array([0.52, 0.66, 1.0]) * 0.95

# dust lanes (absorption) on the inner edge of the arms + patchy dust in the inner disc
dust = np.clip(lane * (0.7 + 0.3 * cl + 0.15 * feather), 0, 1.2)
dust += np.clip(0.25 * np.exp(-r / 4.5) * np.clip(feather - 0.3, 0, 1), 0, 1) * np.clip(r - 1.6, 0, 1)
dust = np.asarray(Image.fromarray((np.clip(dust / 1.5, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.0)), np.float32) / 255 * 1.5
img *= np.exp(-2.4 * dust)[..., None] * np.array([1.0, 0.95, 0.9]) + (1 - np.exp(-2.4 * dust))[..., None] * np.array([0.10, 0.05, 0.02]) * 0.0 + 0

# star clusters and HII regions along the arms
pts = (rng.random((260000, 2)) * S).astype(int)
m = (armlight * (1 - np.clip(dust, 0, 1)))[pts[:, 1], pts[:, 0]]
keep = pts[rng.random(len(pts)) < np.clip(m * 0.7, 0, 1)]
stars = np.zeros((S, S, 3), np.float32)
pink = rng.random(len(keep)) < 0.2
col = np.where(pink[:, None], np.array([1.0, 0.35, 0.6]) * 1.6, np.array([0.78, 0.86, 1.0]))
bri = 0.25 + 0.9 * rng.random(len(keep)) ** 3
np.add.at(stars, (keep[:, 1], keep[:, 0]), col * bri[:, None])
# field stars (old, warm), following the disc + bulge
f = (rng.random((420000, 2)) * S).astype(int)
dens = (np.exp(-r / 3.6) + 0.6 * bulge)[f[:, 1], f[:, 0]]
fs = f[rng.random(len(f)) < dens * 0.9]
np.add.at(stars, (fs[:, 1], fs[:, 0]), np.array([1.0, 0.9, 0.78]) * (0.15 + 0.4 * rng.random(len(fs)))[:, None])
st_img = Image.fromarray((np.clip(stars, 0, 1) * 255).astype(np.uint8))
stars = (np.asarray(st_img.filter(ImageFilter.GaussianBlur(0.8)), np.float32) / 255) * 2.2
stars += np.asarray(st_img.filter(ImageFilter.GaussianBlur(3)), np.float32) / 255 * 3.0   # cluster glow
img += stars

# fade the edge, bloom, tone map
img *= np.clip(1.25 - r / R, 0, 1)[..., None] ** 1.2
base = Image.fromarray((np.clip(img / 2.5, 0, 1) * 255).astype(np.uint8))
bloom = np.asarray(base.filter(ImageFilter.GaussianBlur(28)), np.float32) / 255 * 2.5
img = img + 0.4 * bloom
img = 1 - np.exp(-img * 1.05)
img = np.clip(img, 0, 1) ** 0.95
# a touch more saturation
lum = img.mean(-1, keepdims=True)
img = np.clip(lum + (img - lum) * 1.18, 0, 1)
out = Image.fromarray((img * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))
out.save("Resources/Textures/galaxy_top.jpg", quality=90)
out.resize((1024, 1024), Image.LANCZOS).save("/workspace/solar_tools/galaxy_preview.png")
print("ok")

# Soft warm glow sprite for the bulge (billboard in the 3-D galaxy screen; black = transparent).
n = 256
gy, gx = np.mgrid[0:n, 0:n].astype(np.float32)
gr = np.hypot(gx - n / 2 + 0.5, gy - n / 2 + 0.5) / (n / 2)
ga = (np.exp(-(gr / 0.22) ** 2) * 0.55 + np.exp(-(gr / 0.5) ** 2) * 0.22) * np.clip((1 - gr) / 0.15, 0, 1)
gimg = np.clip(ga[..., None] * np.array([1.0, 0.86, 0.62]), 0, 1)
Image.fromarray((gimg * 255).astype(np.uint8)).save("Resources/Textures/galaxy_glow.png")
