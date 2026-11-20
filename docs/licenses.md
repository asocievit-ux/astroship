# Data, images and licences

| Asset | Source | Licence / terms |
|---|---|---|
| Planet, Sun, Moon, Ceres/Eris/Haumea/Makemake textures, Saturn ring, Earth clouds | Solar System Scope, https://www.solarsystemscope.com/textures/ | CC BY 4.0 — attribution in app (Settings › Data and image credits). The dwarf-planet maps are artistic ("fictional") renderings. |
| Milky Way background | ESO/S. Brunier, "The Milky Way panorama" (eso0932a) | CC BY 4.0 — stars removed by grey opening, reprojected to ecliptic coordinates, dimmed |
| Star positions / magnitudes / colours | Yale Bright Star Catalogue 5th ed. (Hoffleit & Warren 1991), via the JSON conversion by brettonw/YaleBrightStarCatalog | Catalogue data (NASA ADC / CDS V/50), free scientific use |
| Planet orbits | JPL "Approximate Positions of the Planets", E. M. Standish | Public (NASA/JPL) |
| Moon | ELP-2000/82 main terms as tabulated in J. Meeus, Astronomical Algorithms | Formulas (not copyrightable data) |
| Moons | JPL Horizons state vectors (2026-11-20) + JPL satellite mean elements | Public (NASA/JPL) |
| Dwarf planets, Vesta, comets | JPL Small-Body Database osculating elements | Public (NASA/JPL) |
| Sun's galactic motion | Θ0 = 230 km/s; (U,V,W) = (11.1, 12.24, 7.25) km/s, Schönrich, Binney & Dehnen 2010; R0 = 8.2 kpc | Published values |
| Galaxy top view, sun glow, star sprite, app icon | Generated procedurally by `tools/build_assets.py` / icon script | Own work |

## Background music
Played in this order as a looping playlist (re-encoded to AAC 144 kbps stereo; files `Resources/Audio/bgm1-4.m4a`).
All four are used under the **Pixabay Content License** — summary: https://pixabay.com/service/license-summary/

| # | File | Title | Creator (Pixabay) | Pixabay page | Length |
|---|------|-------|-------------------|--------------|--------|
| 1 | bgm1.m4a | Meditation Binaural 8 Hz 528 Hz | siarhei_korbut | https://pixabay.com/music/meditation-binaural-8-hz-528-hz-396680/ | 9:55 |
| 2 | bgm2.m4a | Activate Feminine Energy | soul_frequencies | https://pixabay.com/music/activate-feminine-energy-492002/ | 1:00 |
| 3 | bgm3.m4a | 528hz Frequency Ambient Music (Meditation, Calming, Zen, Spiritual Music) | ribhavagrawal | https://pixabay.com/music/528hz-frequency-ambient-music-meditationcalmingzenspiritual-music-237574/ | 5:34 |
| 4 | bgm4.m4a | Revelation of the Misty Planet (396Hz & 528 Hz Meditation) | Siarhei_Korbut | https://pixabay.com/ja/music/瞑想-精神的な-revelation-of-the-misty-planet-396hz-amp-528-hz-meditation-471813/ | 9:55 |

Notes:
- Tracks 1 and 4 are registered with YouTube Content ID by their creator (a claim can appear on videos that contain it; this does not affect use inside the app).
- Page URLs are built from the Pixabay track IDs in the original file names (Pixabay resolves `/music/<slug>-<id>/`); verify in a browser before publishing.
- Pixabay tracks must not be redistributed as standalone audio files; here they are only embedded in the app.
