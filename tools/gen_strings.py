#!/usr/bin/env python3
import re, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from strings_table import LANGS, BODIES, UI

OUT = Path(__file__).resolve().parent.parent / "Resources" / "Localization"

def esc(s): return s.replace("\\", "\\\\").replace('"', '\\"')

def main():
    entries = {f"body.{k}": v for k, v in BODIES.items()}
    entries.update(UI)
    for k, v in entries.items():
        assert len(v) == len(LANGS), (k, len(v))
        n = v[0].count("%@")
        for lang, s in zip(LANGS, v):
            assert s.count("%@") == n, (k, lang, s)
    for i, lang in enumerate(LANGS):
        d = OUT / f"{lang}.lproj"
        d.mkdir(parents=True, exist_ok=True)
        lines = [f'"{esc(k)}" = "{esc(v[i])}";' for k, v in sorted(entries.items())]
        (d / "Localizable.strings").write_text("\n".join(lines) + "\n", encoding="utf-8")
        (d / "InfoPlist.strings").write_text('"CFBundleDisplayName" = "AstroShip";\n"CFBundleName" = "AstroShip";\n', encoding="utf-8")
    # every key used in Swift must exist
    used = set()
    for f in (OUT.parent.parent / "Sources" / "App").glob("*.swift"):
        used |= set(re.findall(r'L\("([a-zA-Z.]+)"', f.read_text()))
    missing = sorted(k for k in used if k not in entries)
    assert not missing, missing
    print(f"{len(entries)} keys x {len(LANGS)} languages")

main()
