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
Played as an endless playlist in shuffled order (reshuffled every cycle, no back-to-back repeats). Re-encoded to AAC 128 kbps, 44.1 kHz stereo; files `Resources/Audio/bgm1-8.m4a`. Every audio file in `Resources/Audio` is picked up automatically — add one with `tools/add_bgm.sh` and list it here.
All eight are used under the **Pixabay Content License** — summary: https://pixabay.com/service/license-summary/

| # | File | Title | Creator (Pixabay) | Pixabay page | Length |
|---|------|-------|-------------------|--------------|--------|
| 1 | bgm1.m4a | Meditation Binaural 8 Hz 528 Hz | siarhei_korbut | https://pixabay.com/music/meditation-binaural-8-hz-528-hz-396680/ | 9:55 |
| 2 | bgm2.m4a | Activate Feminine Energy | soul_frequencies | https://pixabay.com/music/activate-feminine-energy-492002/ | 1:00 |
| 3 | bgm3.m4a | 528hz Frequency Ambient Music (Meditation, Calming, Zen, Spiritual Music) | ribhavagrawal | https://pixabay.com/music/528hz-frequency-ambient-music-meditationcalmingzenspiritual-music-237574/ | 5:34 |
| 4 | bgm4.m4a | Revelation of the Misty Planet (396Hz & 528 Hz Meditation) | Siarhei_Korbut | https://pixabay.com/ja/music/瞑想-精神的な-revelation-of-the-misty-planet-396hz-amp-528-hz-meditation-471813/ | 9:55 |
| 5 | bgm5.m4a | Sunset Glow (Relaxation Dreamy) | Siarhei_Korbut | https://pixabay.com/ja/music/モダンクラシック-sunset-glow-relaxation-dreamy-583603/ | 10:00 |
| 6 | bgm6.m4a | Sweet Dreams 528 Hz Short | Siarhei_Korbut | https://pixabay.com/ja/music/瞑想-精神的な-sweet-dreams-528-hz-short-377543/ | 3:45 |
| 7 | bgm7.m4a | Angels Lullaby 528 Hz (Short) | Siarhei_Korbut | https://pixabay.com/ja/music/瞑想-精神的な-angels-lullaby-528-hz-short-391382/ | 3:25 |
| 8 | bgm8.m4a | 528 Hz Solar Plexus Chakra Healing | Roman_Sol | https://pixabay.com/ja/music/瞑想-精神的な-528-hz-solar-plexus-chakra-healing-553028/ | 3:15 |

Notes:
- Tracks 1, 4, 5, 6, 7 and 8 are registered with YouTube Content ID by their creators (a claim can appear on videos that contain it; this does not affect use inside the app).
- Page URLs are built from the Pixabay track IDs in the original file names (Pixabay resolves `/music/<slug>-<id>/`); verify in a browser before publishing.
- Pixabay tracks must not be redistributed as standalone audio files; here they are only embedded in the app.
