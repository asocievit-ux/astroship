#!/usr/bin/env python3
import re, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from strings_table import LANGS, BODIES, UI

ATT = [
    "Your choice lets AstroShip show ads that are more relevant to you. The app works the same either way.",
    "許可すると、あなたに合った広告が表示されやすくなります。どちらを選んでもアプリの機能は変わりません。",
    "允许后，AstroShip 可以向你显示更相关的广告。无论如何选择，App 的功能都不变。",
    "Si lo permites, AstroShip podrá mostrarte anuncios más relevantes. La app funciona igual en ambos casos.",
    "Se permitir, o AstroShip poderá mostrar anúncios mais relevantes para você. O app funciona igual em qualquer caso.",
    "Si vous autorisez, AstroShip pourra afficher des publicités plus pertinentes. L’app fonctionne de la même façon dans les deux cas.",
    "Wenn du zustimmst, kann AstroShip dir relevantere Werbung zeigen. Die App funktioniert in beiden Fällen gleich.",
    "Kapag pinayagan mo, makakapagpakita ang AstroShip ng mas angkop na mga ad. Pareho pa rin ang gamit ng app anuman ang piliin mo.",
    "Если разрешить, AstroShip сможет показывать более подходящую рекламу. Приложение работает одинаково в обоих случаях.",
    "Om du tillåter det kan AstroShip visa annonser som är mer relevanta för dig. Appen fungerar likadant oavsett val.",
    "אם תאשר/י, AstroShip תוכל להציג מודעות רלוונטיות יותר. האפליקציה פועלת אותו דבר בכל מקרה.",
]
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
        (d / "InfoPlist.strings").write_text('"CFBundleDisplayName" = "AstroShip";\n"CFBundleName" = "AstroShip";\n'
            + f'"NSUserTrackingUsageDescription" = "{esc(ATT[i])}";\n', encoding="utf-8")
    # every key used in Swift must exist
    used = set()
    for f in (OUT.parent.parent / "Sources" / "App").glob("*.swift"):
        used |= set(re.findall(r'L\("([a-zA-Z.]+)"', f.read_text()))
    missing = sorted(k for k in used if k not in entries)
    assert not missing, missing
    print(f"{len(entries)} keys x {len(LANGS)} languages")

main()
