#!/usr/bin/env python3
"""Builds the bundled sky, star and galaxy assets from the source files in ../astroship-assets.

Frames: ecliptic J2000 (x = vernal equinox, z = ecliptic north). The sky texture is an
equirectangular map in ecliptic longitude/latitude: column 0 = lon -180, row 0 = lat +90.
The app maps the same lon/lat onto its own sphere mesh, so no mirroring conventions apply.
"""
import json, math, re, struct, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

SRC = Path(sys.argv[1] if len(sys.argv) > 1 else "/workspace/astroship-assets")
OUT = Path(__file__).resolve().parent.parent / "Resources"
EPS = math.radians(23.4392911)
# ICRS equatorial -> galactic (Hipparcos / Liu et al. 2011)
T_EQ_GAL = np.array([
    [-0.0548755604162154, -0.8734370902348850, -0.4838350155487132],
    [ 0.4941094278755837, -0.4448296299600112,  0.7469822444972189],
    [-0.8676661490190047, -0.1980763734312015,  0.4559837761750669]])
c, s = math.cos(EPS), math.sin(EPS)
ECL_TO_EQ = np.array([[1, 0, 0], [0, c, -s], [0, s, c]])  # eq = M @ ecl
EQ_TO_ECL = ECL_TO_EQ.T


def sky_texture(w=4096, h=2048):
    # Remove point stars (grey opening) so only the diffuse Milky Way glow remains; the
    # catalogue stars are drawn separately at their exact positions.
    src = Image.open(SRC / "eso_mw.jpg").convert("RGB")
    src = src.filter(ImageFilter.MinFilter(7)).filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(2))
    pano = np.asarray(src, dtype=np.float32) / 255.0
    ph, pw, _ = pano.shape
    xs = (np.arange(w) + 0.5) / w * 2 * np.pi - np.pi
    ys = np.pi / 2 - (np.arange(h) + 0.5) / h * np.pi
    lon, lat = np.meshgrid(xs, ys)
    d = np.stack([np.cos(lat) * np.cos(lon), np.cos(lat) * np.sin(lon), np.sin(lat)], -1)
    g = d @ (T_EQ_GAL @ ECL_TO_EQ).T
    l = np.degrees(np.arctan2(g[..., 1], g[..., 0]))
    b = np.degrees(np.arcsin(np.clip(g[..., 2], -1, 1)))
    # ESO eso0932a: galactic centre in the middle, longitude increasing to the left.
    px = ((0.5 - l / 360.0) % 1.0) * pw
    py = (0.5 - b / 180.0) * ph
    x0 = np.floor(px).astype(int) % pw; y0 = np.clip(np.floor(py).astype(int), 0, ph - 1)
    x1 = (x0 + 1) % pw; y1 = np.clip(y0 + 1, 0, ph - 1)
    fx = (px - np.floor(px))[..., None]; fy = (py - np.floor(py))[..., None]
    img = (pano[y0, x0] * (1 - fx) * (1 - fy) + pano[y0, x1] * fx * (1 - fy) +
           pano[y1, x0] * (1 - fx) * fy + pano[y1, x1] * fx * fy)
    img *= np.clip((88.5 - np.abs(b)) / 3.0, 0, 1)[..., None]
    # Dim and lift the black point so stars from the catalogue carry the sharp points.
    img = np.clip((img - 0.02) * 0.8, 0, 1) ** 1.05
    # v3: lift the faint band (~2x in the midtones) so the Milky Way reads clearly behind the opening view
    k = 2.6
    img = np.clip((1 - np.exp(-k * img)) / (1 - np.exp(-k)), 0, 1)
    Image.fromarray((img * 255).astype(np.uint8)).save(OUT / "Textures/sky_milkyway.jpg", quality=86)
    return pano


def kelvin_rgb(k):
    t = k / 100.0
    if t <= 66: r = 255
    else: r = 329.698727446 * ((t - 60) ** -0.1332047592)
    if t <= 66: g = 99.4708025861 * math.log(t) - 161.1195681661
    else: g = 288.1221695283 * ((t - 60) ** -0.0755148492)
    if t >= 66: b = 255
    elif t <= 19: b = 0
    else: b = 138.5177312231 * math.log(t - 10) - 305.0447927307
    rgb = [max(0, min(255, v)) for v in (r, g, b)]
    # soften toward white: the eye sees stars as only mildly coloured
    return [int(0.55 * v + 0.45 * 255) for v in rgb]


def parse_ra(s):
    m = re.match(r"(\d+)h (\d+)m ([\d.]+)s", s)
    return (int(m[1]) + int(m[2]) / 60 + float(m[3]) / 3600) * 15


def parse_dec(s):
    m = re.match(r"([+-])(\d+)° (\d+)′ (\d+)″", s)
    v = int(m[2]) + int(m[3]) / 60 + int(m[4]) / 3600
    return -v if m[1] == "-" else v


def stars():
    data = json.loads((SRC / "bsc5-short.json").read_text())
    out = bytearray()
    n = 0
    for st in data:
        if "RA" not in st or "V" not in st:
            continue
        ra, de = math.radians(parse_ra(st["RA"])), math.radians(parse_dec(st["Dec"]))
        eq = np.array([math.cos(de) * math.cos(ra), math.cos(de) * math.sin(ra), math.sin(de)])
        x, y, z = EQ_TO_ECL @ eq
        mag = float(st["V"])
        k = float(st.get("K", 6000) or 6000)
        r, g, b = kelvin_rgb(k)
        out += struct.pack("<ffffBBBB", x, y, z, mag, r, g, b, 255)
        n += 1
    (OUT / "Data/stars.bin").write_bytes(bytes(out))
    print("stars", n)


def star_sprite(size=64):
    y, x = np.mgrid[0:size, 0:size]
    r = np.hypot(x - size / 2 + 0.5, y - size / 2 + 0.5) / (size / 2)
    a = np.exp(-(r ** 2) * 9) + 0.25 * np.exp(-(r ** 2) * 2.2)
    a = np.clip(a / a.max(), 0, 1) * (r < 1)
    v = (a * 255).astype(np.uint8)
    Image.fromarray(np.stack([v, v, v], -1)).save(OUT / "Textures/star_sprite.png")


def glow(size=256, name="sun_glow.png", tint=(1.0, 0.86, 0.62)):
    y, x = np.mgrid[0:size, 0:size]
    r = np.hypot(x - size / 2 + 0.5, y - size / 2 + 0.5) / (size / 2)
    a = 1 / (1 + (r * 7) ** 2) * np.clip(1 - r, 0, 1) ** 1.5
    a = a / a.max()
    rgb = np.stack([a * tint[0], a * tint[1], a * tint[2]], -1)
    Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)).save(OUT / f"Textures/{name}")


def galaxy(size=2048, seed=7):
    """Procedural top-down Milky Way. Image right = +X, image down = +Z in the galaxy scene;
    seen from the north galactic pole the disc turns clockwise, so arms trail counter-clockwise."""
    rng = np.random.default_rng(seed)
    R = 16.0  # kpc at the image edge
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    X = (x + 0.5) / size * 2 * R - R
    Y = -((y + 0.5) / size * 2 * R - R)  # visual up
    r = np.hypot(X, Y) + 1e-6
    th = np.arctan2(Y, X)  # counter-clockwise as seen
    img = np.zeros((size, size, 3), np.float32)
    disc = np.exp(-r / 3.6)
    img += disc[..., None] * np.array([0.55, 0.5, 0.45]) * 1.3
    # bar, about 27 deg from the Sun-centre line (Sun is straight down).
    bar_ang = math.radians(-90 + 27)
    bx = X * math.cos(bar_ang) + Y * math.sin(bar_ang)
    by = -X * math.sin(bar_ang) + Y * math.cos(bar_ang)
    bar = np.exp(-(bx / 4.2) ** 2 - (by / 1.3) ** 2)
    img += bar[..., None] * np.array([1.0, 0.85, 0.6]) * 1.1
    bulge = np.exp(-(r / 1.4) ** 2)
    img += bulge[..., None] * np.array([1.0, 0.9, 0.7]) * 1.6
    pitch = math.radians(16)
    k = 1 / math.tan(pitch)
    def arm(theta0, width, strength, rmin, rmax, color):
        # trailing arm: theta grows with ln r (counter-clockwise outward)
        phase = (th - (theta0 + k * np.log(r / rmin)))
        d = np.angle(np.exp(1j * phase))  # wrap to -pi..pi
        dist = np.abs(d) * r  # kpc along circle
        prof = np.exp(-(dist / (width * (0.6 + 0.12 * r))) ** 2) * (r > rmin * 0.8) * np.exp(-np.clip(r - rmax, 0, None) / 1.5)
        prof *= np.clip((r - rmin * 0.8) / 1.5, 0, 1)
        return prof[..., None] * np.array(color) * strength
    sun_th = -math.pi / 2  # straight down
    def theta0_through(rr, th_at):
        return th_at - k * math.log(rr / 3.5)
    blue = [0.55, 0.7, 1.0]
    img += arm(theta0_through(10.5, sun_th), 0.75, 1.0, 3.5, 15.5, blue)        # Perseus (outside Sun)
    img += arm(theta0_through(10.5, sun_th) + math.pi, 0.75, 1.0, 3.5, 15.5, blue)  # Scutum-Centaurus
    img += arm(theta0_through(6.6, sun_th), 0.55, 0.65, 3.5, 13.0, blue)        # Sagittarius-Carina
    img += arm(theta0_through(6.6, sun_th) + math.pi, 0.55, 0.65, 3.5, 13.0, blue)  # Norma-Outer
    # Orion spur: short segment through the Sun
    spur = arm(theta0_through(8.2, sun_th), 0.35, 0.55, 3.5, 20, [0.7, 0.8, 1.0])
    spur *= np.exp(-((th - sun_th + 0.0) / 0.45) ** 2)[..., None] * (np.abs(r - 8.2) < 2.5)[..., None]
    img += spur
    # star clusters / HII regions on the arms
    arms_mask = img[..., 2] - img[..., 0] * 0.6
    pts = (rng.random((90000, 2)) * size).astype(int)
    m = arms_mask[pts[:, 1], pts[:, 0]]
    keep = pts[(m > 0.08) & (rng.random(len(pts)) < np.clip(m, 0, 1))]
    for (px, py) in keep:
        col = np.array([1.0, 0.5, 0.7]) if rng.random() < 0.1 else np.array([0.8, 0.88, 1.0])
        rr = 1 if rng.random() < 0.8 else 2
        img[max(0,py-rr+1):py+rr, max(0,px-rr+1):px+rr] += col * (0.4 + 0.8 * rng.random())
    field = (rng.random((140000, 2)) * size).astype(int)
    dens = (disc + bulge * 0.5)[field[:, 1], field[:, 0]]
    sel = field[rng.random(len(field)) < dens * 1.4]
    img[sel[:, 1], sel[:, 0]] += np.array([1.0, 0.92, 0.8]) * 0.5
    # dust lanes inside arms
    dust = arm(theta0_through(10.0, sun_th), 0.25, 1, 3.5, 15, [1, 1, 1])[..., 0] + \
           arm(theta0_through(10.0, sun_th) + math.pi, 0.25, 1, 3.5, 15, [1, 1, 1])[..., 0]
    img *= (1 - 0.45 * np.clip(dust, 0, 1))[..., None]
    noise = rng.random((size // 16, size // 16)).astype(np.float32)
    noise = np.asarray(Image.fromarray((noise * 255).astype(np.uint8)).resize((size, size), Image.BICUBIC), np.float32) / 255
    img *= (0.75 + 0.5 * noise)[..., None]
    img *= np.clip(1.2 - r / R, 0, 1)[..., None]
    out = Image.fromarray((np.clip(img, 0, 1) ** 0.85 * 255).astype(np.uint8))
    out = out.filter(ImageFilter.GaussianBlur(1.2))
    out.save(OUT / "Textures/galaxy_top.jpg", quality=88)


def planets():
    names = {"2k_sun": "sun", "2k_mercury": "mercury", "2k_venus_atmosphere": "venus", "2k_earth_daymap": "earth",
             "2k_earth_clouds": "earth_clouds", "2k_moon": "moon", "2k_mars": "mars", "2k_jupiter": "jupiter",
             "2k_saturn": "saturn", "2k_uranus": "uranus", "2k_neptune": "neptune", "2k_ceres_fictional": "ceres",
             "2k_eris_fictional": "eris", "2k_haumea_fictional": "haumea", "2k_makemake_fictional": "makemake"}
    for src, dst in names.items():
        im = Image.open(SRC / f"{src}.jpg").convert("RGB")
        im.save(OUT / f"Textures/{dst}.jpg", quality=88)
    ring = Image.open(SRC / "2k_saturn_ring_alpha.png").convert("RGBA")
    ring.save(OUT / "Textures/saturn_ring.png")


if __name__ == "__main__":
    (OUT / "Textures").mkdir(parents=True, exist_ok=True); (OUT / "Data").mkdir(parents=True, exist_ok=True)
    planets(); sky_texture(); stars(); star_sprite(); glow(); glow(128, "marker_glow.png", (1, 1, 1)); galaxy()
    print("done")
