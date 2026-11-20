"""Original ambient loop around 528 Hz, synthesised from scratch (no samples, no third-party music).
Every partial and every modulation completes a whole number of cycles in T seconds, so the loop is seamless.
Output: Resources/Audio/ambient528.m4a (AAC). Requires numpy and ffmpeg."""
import numpy as np, subprocess, pathlib, wave
SR = 44100
T = 64.0                      # loop length (s); frequency grid = 1/64 Hz
N = int(SR * T)
t = np.arange(N) / SR
rng = np.random.default_rng(528)

def q(f):                      # snap a frequency to the loop grid
    return round(f * T) / T

def lfo(cycles, phase=0.0):    # 0..1, whole cycles per loop
    return 0.5 - 0.5 * np.cos(2 * np.pi * cycles * t / T + phase)

L = np.zeros(N); R = np.zeros(N)
# (frequency, level, swell cycles per loop, stereo pan)
voices = [
    (132.0, 0.30, 1, 0.0),     # 528 / 4 : warm root
    (198.0, 0.16, 2, -0.3),    # fifth above root
    (264.0, 0.20, 1, 0.25),    # 528 / 2
    (396.0, 0.10, 3, -0.4),    # 3/2 of 264
    (528.0, 0.13, 2, 0.35),    # the 528 Hz tone itself, kept soft
    (660.0, 0.035, 4, -0.2),   # major third, very quiet shimmer
    (792.0, 0.03, 3, 0.4),
]
for i, (f, a, sw, pan) in enumerate(voices):
    env = 0.35 + 0.65 * lfo(sw, phase=i * 1.3)
    sig = np.zeros(N)
    for d in (-2, 0, 2):       # three slightly detuned copies -> slow chorus beating
        fq = q(f) + d / T
        ph = rng.uniform(0, 2 * np.pi)
        sig += np.sin(2 * np.pi * fq * t + ph) * (1.0 if d == 0 else 0.55)
        sig += 0.12 * np.sin(2 * np.pi * 2 * fq * t + ph)   # gentle 2nd harmonic
    sig *= a * env / 2.2
    L += sig * np.sqrt(0.5 * (1 - pan)); R += sig * np.sqrt(0.5 * (1 + pan))

# soft "space wind": periodic noise shaped in the frequency domain (periodic by construction)
for ch in (L, R):
    spec = np.fft.rfft(rng.standard_normal(N))
    fr = np.fft.rfftfreq(N, 1 / SR)
    shape = 1 / np.maximum(fr, 20) ** 0.5 * np.exp(-((fr - 400) / 500) ** 2)
    noise = np.fft.irfft(spec * shape, N)
    noise /= np.abs(noise).max()
    ch += 0.035 * noise * (0.4 + 0.6 * lfo(2, phase=1.0))

mix = np.stack([L, R], 1)
mix /= np.abs(mix).max()
mix *= 0.7                     # headroom; the app plays it at a modest volume as well
out = pathlib.Path(__file__).resolve().parent.parent / "Resources/Audio"
out.mkdir(parents=True, exist_ok=True)
wav = "/tmp/ambient528.wav"
with wave.open(wav, "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((mix * 32767).astype("<i2").tobytes())
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "aac", "-b:a", "128k",
                str(out / "ambient528.m4a")], check=True)
print("wrote", out / "ambient528.m4a")
