#!/usr/bin/env python3
"""The app's sound effects and its background music, made here from scratch (synthesized: sine tones, filtered noise,
plucked strings). Nothing is sampled or copied, and nothing is from a TV show. Run it to make them again:

    python3 scripts/sounds.py            # writes App/Sounds/*.wav and App/Sounds/music.m4a (needs numpy and ffmpeg)

Since Nov 17 the effects are recorded (App/Sounds/*.caf, scripts/recorded-sounds.py), and the app plays an effect's
.caf when there is one, so this skips any effect that has a .caf (--all makes them all). The music is still made here.

The same seed makes the same files, so a run with no changes leaves git clean (except the m4a's encoder stamp)."""
import os, subprocess, sys, wave
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "App", "Sounds")
rng = np.random.default_rng(2026_11_17)


def t_(sec, sr=SR):
    return np.arange(int(sec * sr)) / sr


def env(n, attack=0.004, decay=8.0, sr=SR):
    """A fast rise, then an exponential fall (decay: how many e-folds per second)."""
    t = np.arange(n) / sr
    a = np.clip(t / max(attack, 1e-6), 0, 1)
    return a * np.exp(-decay * t)


def bell(freq, sec, decay=5.0, bright=0.35, sr=SR):
    """A soft bell: a sine with two quieter, inharmonic partials that die faster."""
    t = t_(sec, sr)
    s = np.sin(2 * np.pi * freq * t) * env(len(t), 0.003, decay, sr)
    s += bright * np.sin(2 * np.pi * freq * 2.76 * t) * env(len(t), 0.002, decay * 2.2, sr)
    s += bright * 0.4 * np.sin(2 * np.pi * freq * 5.40 * t) * env(len(t), 0.001, decay * 3.5, sr)
    return s


def bandpass(x, lo, hi, sr=SR):
    """A brick-wall band in the frequency domain (fine for short one-shot noises)."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / sr)
    X[(f < lo) | (f > hi)] = 0
    return np.fft.irfft(X, len(x))


def lowpass_1pole(x, cutoff, sr=SR):
    a = np.exp(-2 * np.pi * cutoff / sr)
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def place(buf, sound, at_sec, gain=1.0, sr=SR):
    i = int(at_sec * sr)
    j = min(len(buf), i + len(sound))
    if i < len(buf):
        buf[i:j] += gain * sound[: j - i]


def finish(x, peak_db=-3.0, fade=0.01):
    x = x - np.mean(x)
    n = int(fade * SR)
    if n and len(x) > 2 * n:
        x[-n:] *= np.linspace(1, 0, n)
    m = np.max(np.abs(x)) or 1
    return x / m * (10 ** (peak_db / 20))


def write_wav(name, x, sr=SR):
    path = os.path.join(OUT, name)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes(pcm.tobytes())
    print(f"{name}: {len(x) / sr:.2f}s, {os.path.getsize(path) // 1024} KB")


# ---------- the effects ----------

def card_play():
    """A card landing on the pile: a papery slap and a soft low thump."""
    n = int(0.16 * SR)
    noise = bandpass(rng.standard_normal(n), 900, 6500) * env(n, 0.001, 38)
    thump = np.sin(2 * np.pi * 140 * t_(0.16)) * env(n, 0.002, 30) * 0.6
    return finish(noise + thump, -4)


def draw():
    """A card sliding off the deck: a short swish rising in pitch."""
    sec = 0.22
    n = int(sec * SR)
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    # sweep a band from low to high in slices
    slices = 11
    for k in range(slices):
        a, b = k * n // slices, (k + 1) * n // slices
        lo = 700 + 3800 * k / slices
        seg = bandpass(noise[a:b] if b - a > 64 else np.zeros(b - a), lo, lo * 1.9)
        out[a:b] = seg
    shape = np.sin(np.pi * np.linspace(0, 1, n)) ** 1.5
    return finish(out * shape, -6)


def your_turn():
    """Your turn: two bright, friendly notes going up (E5, then B5)."""
    buf = np.zeros(int(0.75 * SR))
    place(buf, bell(659.25, 0.6, 6, 0.25), 0.0, 0.8)
    place(buf, bell(987.77, 0.6, 5, 0.25), 0.11, 1.0)
    return finish(buf, -4)


def die_click(pitch=1.0):
    """One die knocking the table: a short, woody click."""
    n = int(0.05 * SR)
    c = bandpass(rng.standard_normal(n), 1800 * pitch, 5200 * pitch) * env(n, 0.0005, 120)
    knock = np.sin(2 * np.pi * 420 * pitch * t_(0.05)) * env(n, 0.0005, 90) * 0.5
    return c + knock


def dice_roll():
    """Dice shaken and thrown: a rattle of clicks that thins out."""
    sec = 0.7
    buf = np.zeros(int(sec * SR))
    t = 0.0
    while t < sec - 0.06:
        place(buf, die_click(rng.uniform(0.8, 1.25)), t, rng.uniform(0.35, 1.0))
        t += rng.uniform(0.015, 0.04) + (t / sec) * 0.06   # quick at first, then slower
    shake = bandpass(rng.standard_normal(len(buf)), 2500, 7000) * env(len(buf), 0.01, 6) * 0.15
    return finish(buf + shake, -5)


def dice_land():
    """Dice coming to rest: three clacks, the last one softest."""
    buf = np.zeros(int(0.28 * SR))
    for i, (at, g) in enumerate([(0.0, 1.0), (0.07, 0.6), (0.15, 0.3)]):
        place(buf, die_click(0.9 + 0.08 * i), at, g)
    thud = np.sin(2 * np.pi * 110 * t_(0.28)) * env(len(buf), 0.002, 22) * 0.35
    return finish(buf + thud, -4)


def soft_tone(freq, sec, vib=0.0):
    """A round, muted tone (a sine with a little second harmonic), with optional vibrato."""
    t = t_(sec)
    ph = 2 * np.pi * freq * t + (vib * np.sin(2 * np.pi * 5.5 * t) if vib else 0)
    s = np.sin(ph) + 0.25 * np.sin(2 * ph) + 0.08 * np.sin(3 * ph)
    a = np.clip(t / 0.02, 0, 1) * np.clip((sec - t) / 0.12, 0, 1)
    return s * a


def farkle():
    """A Farkle: two muted notes stepping down, and a soft low bump. Disappointed, not mean."""
    buf = np.zeros(int(0.95 * SR))
    place(buf, soft_tone(392.0, 0.28), 0.0, 0.8)           # G4
    place(buf, soft_tone(311.13, 0.55, vib=0.6), 0.26, 0.9)  # E-flat 4, wobbling a little
    bump = np.sin(2 * np.pi * 70 * t_(0.3)) * env(int(0.3 * SR), 0.004, 14)
    place(buf, bump, 0.26, 0.5)
    return finish(lowpass_1pole(buf, 2400), -5)


def win():
    """A win: a rising arpeggio (C, E, G, C) and a shimmer that hangs on."""
    buf = np.zeros(int(1.6 * SR))
    for i, f in enumerate([523.25, 659.25, 783.99, 1046.5]):
        place(buf, bell(f, 1.1, 3.2, 0.3), i * 0.09, 0.7 + 0.1 * i)
    for f in [1567.98, 2093.0, 2637.0]:
        place(buf, bell(f, 1.0, 4.5, 0.1), 0.36 + rng.uniform(0, 0.08), 0.18)
    return finish(buf, -3)


def bolt():
    """A Bolt (+2 or +4) aimed at you: a quick electric zap falling in pitch."""
    sec = 0.38
    t = t_(sec)
    f = 1400 * np.exp(-7 * t) + 90
    ph = 2 * np.pi * np.cumsum(f) / SR
    buzz = np.sign(np.sin(ph)) * 0.5 + np.sin(ph * 2.01) * 0.3
    crackle = bandpass(rng.standard_normal(len(t)), 3000, 9000) * (rng.random(len(t)) < 0.08) * 0.8
    s = (buzz + crackle) * env(len(t), 0.002, 9)
    return finish(lowpass_1pole(s, 5000), -5)


# ---------- the music: a quiet, original loop ----------

MSR = 22050
BPM = 84


def note(n):
    """MIDI note number to Hz."""
    return 440.0 * 2 ** ((n - 69) / 12)


def pad(freqs, sec):
    """A soft chord: a few slightly detuned sines per note, slow in and out."""
    t = t_(sec, MSR)
    s = np.zeros(len(t))
    for f in freqs:
        for d in (-0.6, 0.0, 0.7):
            s += np.sin(2 * np.pi * (f + d) * t + rng.uniform(0, 6.28))
    a = np.clip(t / 0.9, 0, 1) * np.clip((sec - t) / 1.1, 0, 1)
    return s * a / (3 * len(freqs))


def pluck(freq, sec=1.2):
    """A plucked string (Karplus-Strong), soft and short."""
    n = int(sec * MSR)
    period = max(2, int(MSR / freq))
    buf = rng.uniform(-1, 1, period)
    out = np.zeros(n)
    for i in range(n):
        v = buf[i % period]
        out[i] = v
        buf[i % period] = 0.497 * (v + buf[(i + 1) % period])
    return out * np.clip(np.arange(n) / 30, 0, 1)


def music():
    beat = 60 / BPM
    bar = 4 * beat
    # Fmaj9, Am7, Dm9, G7sus (then a second pass a little different), all voiced around middle C
    chords = [[53, 57, 60, 64, 67], [57, 60, 64, 67], [50, 57, 60, 64, 65], [55, 60, 62, 65]]
    bass = [41, 45, 38, 43]
    length = bar * 2 * len(chords) * 2          # two passes of the four chords, two bars each
    n = int(length * MSR)
    buf = np.zeros(n + int(4 * MSR))            # room for the tails; they wrap round to the start below
    for p in range(2):
        for i, ch in enumerate(chords):
            start = (p * len(chords) + i) * 2 * bar
            place(buf, pad([note(m) for m in ch], 2 * bar + 0.8), start, 0.55, MSR)
            place(buf, np.sin(2 * np.pi * note(bass[i]) * t_(2 * bar, MSR)) * env(int(2 * bar * MSR), 0.05, 0.9, MSR),
                  start, 0.22, MSR)
            # a gentle arpeggio: eighths, skipping some, an octave up on the second pass
            up = 12 if p == 1 else 0
            pattern = [0, 2, 1, 3, 2, 4, 3, 1] if p == 0 else [4, 2, 3, 1, 2, 0, 1, 3]
            for k in range(16):
                if (k in (5, 13)) or (p == 0 and k in (7, 15)):
                    continue
                m = ch[pattern[k % 8] % len(ch)] + 12 + up
                place(buf, pluck(note(m)), start + k * beat / 2, 0.16 if k % 4 else 0.22, MSR)
    tail = buf[n:]
    loop = buf[:n].copy()
    loop[: len(tail)] += tail                    # the end rings into the start: no click where it loops
    loop = lowpass_1pole(loop, 3200, MSR)
    return finish(loop, -14, fade=0)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in [("card-play", card_play), ("draw", draw), ("your-turn", your_turn), ("dice-roll", dice_roll),
                     ("dice-land", dice_land), ("farkle", farkle), ("win", win), ("bolt", bolt)]:
        # a recorded effect (App/Sounds/<name>.caf, scripts/recorded-sounds.py) wins: its synthesized .wav is only
        # made when there's no .caf, or with --all
        if os.path.exists(os.path.join(OUT, f"{name}.caf")) and "--all" not in sys.argv:
            continue
        write_wav(f"{name}.wav", fn())
    m = music()
    tmp = os.path.join(OUT, "music-tmp.wav")
    write_wav("music-tmp.wav", m, MSR)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "aac", "-b:a", "64k",
                    "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact",
                    os.path.join(OUT, "music.m4a")], check=True)
    os.remove(tmp)
    print(f"music.m4a: {os.path.getsize(os.path.join(OUT, 'music.m4a')) // 1024} KB")


if __name__ == "__main__":
    sys.exit(main())
