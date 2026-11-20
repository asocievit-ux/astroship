"""Original warm meditation/sleep ambient loop centred on 528 Hz, synthesised from scratch
(no samples, no third-party music, not modelled on any specific track).
- warm low drone (66 / 132 Hz = 528/8, 528/4)
- four slowly cross-fading pad chords in just intonation on 132 Hz (528/4), soft harmonics, chorus
- sparse soft bell tones on the 528 scale, placed pseudo-randomly
- long synthetic reverb applied by circular convolution, gentle low-pass
Every component is periodic over T, so the loop is seamless. Output: Resources/Audio/ambient528.m4a"""
import numpy as np, subprocess, pathlib, wave
SR = 32000
T = 240.0                           # 4-minute loop
N = int(SR * T)
t = (np.arange(N, dtype=np.float64) / SR)
rng = np.random.default_rng(528)
q = lambda f: round(f * T) / T      # snap to the loop's frequency grid

def osc(f, ph=0.0):
    return np.sin(2 * np.pi * q(f) * t + ph).astype(np.float32)

def lfo(cycles, ph=0.0):
    return (0.5 - 0.5 * np.cos(2 * np.pi * cycles * t / T + ph)).astype(np.float32)

L = np.zeros(N, np.float32); R = np.zeros(N, np.float32)
def add(sig, pan):
    global L, R
    L += sig * np.float32(np.sqrt(0.5 * (1 - pan))); R += sig * np.float32(np.sqrt(0.5 * (1 + pan)))

# 1) drone
for f, a, pan in [(66, 0.20, 0.0), (132, 0.22, -0.1), (198, 0.06, 0.15)]:
    s = np.zeros(N, np.float32)
    for d in (-1, 0, 1):
        s += osc(f + d / T, rng.uniform(0, 6.28)) * (1 if d == 0 else 0.6)
    add(s * a * (0.75 + 0.25 * lfo(3, rng.uniform(0, 6.28))) / 2.2, pan)

# 2) pads: chord k is centred on segment k (60 s each); cos^2 cross-fades sum to one.
root = 132.0
chords = [
    [264, 330, 396, 528],                 # I    (528 on top)
    [264, 352, 440, 528],                 # IV   (F-like, 4/3)
    [264, 330, 440, 528],                 # vi   (5/3)
    [264, 297, 396, 528],                 # Vsus (9/8, 3/2)
]
seg = T / len(chords)
pos = t / seg
for k, notes in enumerate(chords):
    d = (pos - (k + 0.5) + len(chords) / 2) % len(chords) - len(chords) / 2   # circular distance
    w = np.where(np.abs(d) < 1, np.cos(np.pi * d / 2) ** 2, 0).astype(np.float32)
    idx = np.nonzero(w)[0]
    for j, f in enumerate(notes):
        pan = [-0.45, 0.35, -0.2, 0.45][j]
        top = f >= 500
        s = np.zeros(N, np.float32)
        for n in range(1, 6):                       # warm harmonic roll-off
            amp = 1 / n ** 2.2 * (0.5 if top else 1.0)
            if f * n > 2600: break
            for dt in (-2, 0, 3):
                ph = rng.uniform(0, 6.28)
                s[idx] += (np.sin(2 * np.pi * q(f * n + dt / T) * t[idx] + ph) * amp * (1 if dt == 0 else 0.5)).astype(np.float32)
        breathe = 0.6 + 0.4 * lfo(rng.integers(5, 11), rng.uniform(0, 6.28))
        add(s * w * breathe * 0.075, pan)

# 3) sparse bells on the 528 scale (soft attack, inharmonic partials, long decay)
bell_notes = [528, 594, 660, 792, 880, 1056, 396]
bells_L = np.zeros(N, np.float32); bells_R = np.zeros(N, np.float32)
tt = np.arange(int(SR * 9)) / SR
time = 2.0
while time < T - 1:
    f = q(float(rng.choice(bell_notes)))
    env = (1 - np.exp(-tt / 0.012)) * np.exp(-tt / rng.uniform(2.5, 4.0))
    b = (np.sin(2 * np.pi * f * tt) + 0.25 * np.sin(2 * np.pi * f * 2.0 * tt) * np.exp(-tt / 1.2)
         + 0.08 * np.sin(2 * np.pi * f * 2.76 * tt) * np.exp(-tt / 0.6)) * env
    b = (b * rng.uniform(0.035, 0.06)).astype(np.float32)
    i0 = int(time * SR); ii = (i0 + np.arange(len(tt))) % N   # wrap the tail around the loop
    pan = rng.uniform(-0.7, 0.7)
    np.add.at(bells_L, ii, b * np.float32(np.sqrt(0.5 * (1 - pan))))
    np.add.at(bells_R, ii, b * np.float32(np.sqrt(0.5 * (1 + pan))))
    time += rng.uniform(7, 16)

# 4) circular reverb + gentle low-pass (FFT, periodic -> seamless)
fr = np.fft.rfftfreq(N, 1 / SR)
lp = (1 / np.sqrt(1 + (fr / 2200) ** 4)).astype(np.float32)
def reverb(x, seed):
    r = np.random.default_rng(seed)
    n = int(SR * 7)
    ir = np.zeros(N, np.float32)
    tail = r.standard_normal(n).astype(np.float32) * np.exp(-np.arange(n) / (SR * 1.9)).astype(np.float32)
    ir[:n] = tail
    IR = np.fft.rfft(ir) * lp * (1 / np.sqrt(1 + (fr / 1400) ** 2))   # darker tail
    y = np.fft.irfft(np.fft.rfft(x) * IR, N).astype(np.float32)
    return y / (np.abs(y).max() + 1e-9)
def lowpass(x):
    return np.fft.irfft(np.fft.rfft(x) * lp, N).astype(np.float32)

dryL, dryR = lowpass(L), lowpass(R)
srcL, srcR = dryL + bells_L, dryR + bells_R
wetL, wetR = reverb(srcL, 1), reverb(srcR, 2)
peak = max(np.abs(dryL).max(), np.abs(dryR).max())
outL = dryL / peak * 0.55 + wetL * 0.45 + lowpass(bells_L) / peak * 0.35
outR = dryR / peak * 0.55 + wetR * 0.45 + lowpass(bells_R) / peak * 0.35
mix = np.stack([outL, outR], 1)
mix = mix / np.abs(mix).max() * 0.7
out = pathlib.Path(__file__).resolve().parent.parent / "Resources/Audio"
out.mkdir(parents=True, exist_ok=True)
wav = "/tmp/ambient528.wav"
with wave.open(wav, "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((mix * 32767).astype("<i2").tobytes())
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-ar", "44100", "-c:a", "aac", "-b:a", "112k",
                str(out / "ambient528.m4a")], check=True)
print("wrote", out / "ambient528.m4a", "seam", float(np.abs(mix[0] - mix[-1]).max()))
