#!/usr/bin/env python3
"""Thunder for #708's option B, the storm (wayloncore/tyleralocke#717): Time2Play's own, made in code (no recording,
no real-world audio). Writes App/Sounds/thunder.caf (mono, 44.1 kHz, 16-bit) with ffmpeg.

How a near strike sounds, and so how this is built (docs/app/cinematic.md, "How real lightning lights a scene"):
a sharp crack from the return stroke (a short broadband burst), then, a beat later because sound is slower than
light, a low rumble that swells, rolls (the sound arriving from different parts of the channel) and dies away.
The crack is at 0 s and the rumble starts at about 0.3 s, which is where thunder.ahap puts its haptic events.

  python3 scripts/thunder.py            # needs numpy and ffmpeg
"""
import os
import subprocess
import tempfile
import wave

import numpy as np

SR = 44100
DUR = 2.6
rng = np.random.default_rng(717)
n = int(SR * DUR)
t = np.arange(n) / SR


def lowpass(x, cutoff):
    """A gentle one-pole low-pass, run twice (12 dB an octave)."""
    a = np.exp(-2 * np.pi * cutoff / SR)
    for _ in range(2):
        y = np.empty_like(x)
        acc = 0.0
        for i, v in enumerate(x):
            acc = (1 - a) * v + a * acc
            y[i] = acc
        x = y
    return x


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


# the crack: 40 ms of bright noise with a hard attack and a fast fall, a little body under it
crack = rng.standard_normal(n) * np.exp(-t / 0.018) * (t < 0.12)
crack = highpass(crack, 900) * 0.9 + lowpass(crack, 300) * 0.6

# the rumble: brown-ish noise kept low, rolling (slow, irregular swells), rising then dying away
noise = np.cumsum(rng.standard_normal(n))
noise -= lowpass(noise, 18)                 # no drift
body = lowpass(noise, 140)
start = 0.3
env = np.clip((t - start) / 0.22, 0, 1) ** 1.5 * np.exp(-np.clip(t - start - 0.25, 0, None) / 0.75)
roll = 0.55 + 0.45 * np.abs(lowpass(rng.standard_normal(n), 3.5)) / 0.35
roll = np.clip(roll, 0.3, 1.6)
rumble = body * env * roll

x = crack / (np.max(np.abs(crack)) + 1e-9) * 0.85 + rumble / (np.max(np.abs(rumble)) + 1e-9) * 0.95
fade = np.clip((DUR - t) / 0.25, 0, 1)
x = x * fade
x = x / np.max(np.abs(x)) * 0.89
pcm = (x * 32767).astype(np.int16)

out = os.path.join(os.path.dirname(__file__), "..", "App", "Sounds", "thunder.caf")
with tempfile.TemporaryDirectory() as d:
    w = os.path.join(d, "thunder.wav")
    with wave.open(w, "wb") as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR); f.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", w, "-c:a", "pcm_s16le", "-f", "caf", out], check=True)
print("wrote", os.path.normpath(out), f"{DUR} s")
