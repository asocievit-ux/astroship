"""visionOS layered app icon from icon B (Back: starfield, opaque; Middle: asteroid belt; Front: Sun).
Writes Resources/VisionAssets.xcassets/AppIcon.solidimagestack. Run from repo root."""
import json, sys, pathlib
import numpy as np
from PIL import Image
src = pathlib.Path("tools/make_icon_candidates.py").read_text().split("# B")[0]
sys.argv = ["x", "/tmp"]
exec(src)
def tone(a): return 255 * (1 - np.exp(-np.clip(a, 0, None) / 255 * 1.1))
def opaque(a):
    return Image.fromarray(tone(a).clip(0, 255).astype(np.uint8)).resize((1024, 1024), Image.LANCZOS).convert("RGB")
def layer(a):
    rgb = tone(a).clip(0, 255)
    alpha = rgb.max(-1)
    col = np.where(alpha[..., None] > 0, rgb / np.maximum(alpha[..., None], 1) * 255, 0)
    im = np.dstack([col, alpha]).clip(0, 255).astype(np.uint8)
    return Image.fromarray(im, "RGBA").resize((1024, 1024), Image.LANCZOS)
back = opaque(bg + stars(11) + 0.35 * sun(c, c, 2.2))
middle = layer(belt(12, c, c, 820, 360, -10))
front = layer(sun(c, c))
root = pathlib.Path("Resources/VisionAssets.xcassets")
info = {"info": {"author": "xcode", "version": 1}}
root.mkdir(parents=True, exist_ok=True)
(root / "Contents.json").write_text(json.dumps(info, indent=1))
st = root / "AppIcon.solidimagestack"
st.mkdir(exist_ok=True)
names = [("Front", front), ("Middle", middle), ("Back", back)]
(st / "Contents.json").write_text(json.dumps({**info, "layers": [{"filename": f"{n}.solidimagestacklayer"} for n, _ in names]}, indent=1))
for n, im in names:
    d = st / f"{n}.solidimagestacklayer"; (d / "Content.imageset").mkdir(parents=True, exist_ok=True)
    (d / "Contents.json").write_text(json.dumps(info, indent=1))
    im.save(d / "Content.imageset" / f"{n.lower()}.png", optimize=True)
    (d / "Content.imageset" / "Contents.json").write_text(json.dumps({**info, "images": [{"filename": f"{n.lower()}.png", "idiom": "vision", "scale": "2x"}]}, indent=1))
# composite preview
comp = back.convert("RGBA"); comp.alpha_composite(middle); comp.alpha_composite(front)
comp.convert("RGB").save("/workspace/astroship_icons/B_vision_preview.png")
print("ok")
