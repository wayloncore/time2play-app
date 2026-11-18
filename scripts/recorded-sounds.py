#!/usr/bin/env python3
"""Recorded sound effects for the app (App/Sounds), taken from free packs (.github/workflows/sounds.yml runs this on a
GitHub runner, since a cloud session can't reach the packs' site).

  packs LIST PACKDIR        downloads the OpenGameArt pages in LIST (scripts/sound-packs.txt) and prints each page's
                            license, author and attribution (also saved in PACKDIR/_licenses.json)
  survey PACKDIR            lists every sound in the downloaded packs: its length, peak and loudness, how bright it
                            is, and how many hits it has, so the picks can be chosen without listening
  pick PACKDIR PICKS OUTDIR trims, levels and fades the files scripts/sound-picks.json names, and writes each as a
                            small .caf (mono, 44.1 kHz, IMA4: about 23 KB a second) in place of the synthesized .wav

Needs numpy and ffmpeg. The packs themselves are never kept, only the few files picked from them.
"""
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request
import zipfile

import numpy as np

RATE = 44100
AUDIO = (".ogg", ".wav", ".mp3", ".flac", ".aiff", ".aif")
# The synthesized set's peaks (dBFS), so a recording sits about as loud as the sound it replaces.
PEAKS = {"card-play": -4, "draw": -6, "your-turn": -4, "dice-roll": -5, "dice-land": -4, "farkle": -5, "win": -3,
         "bolt": -5}
MAX_BYTES = 100 * 1024


def decode(path, filters=""):
    """Any audio file as mono float samples at 44.1 kHz (ffmpeg does the decoding and the resampling), with any
    ffmpeg audio filters (a pick's "filter", say "lowpass=f=1500" to make a thud duller)."""
    af = ["-af", filters] if filters else []
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(RATE), *af, "-f", "f32le", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype="<f4").astype(np.float64)


def encode_caf(path, x):
    pcm = np.clip(x, -1, 1).astype("<f4").tobytes()
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-",
                    "-c:a", "adpcm_ima_qt", "-f", "caf", path], input=pcm, check=True)


def db(v):
    return 20 * np.log10(max(v, 1e-9))


def stats(x):
    if len(x) == 0:
        return {"len": 0}
    peak = float(np.max(np.abs(x)))
    rms = float(np.sqrt(np.mean(x ** 2)))
    # the loud part: from the first to the last 10 ms window within 40 dB of the peak
    win = 441
    n = len(x) // win
    env = np.sqrt(np.mean(x[: n * win].reshape(n, win) ** 2, axis=1)) if n else np.array([rms])
    loud = np.where(env > peak * 0.01)[0]
    body = (loud[-1] - loud[0] + 1) * win / RATE if len(loud) else 0
    # hits: windows that jump 12 dB over the one before (a card slap is 1, a dice roll is many)
    hits = int(np.sum((env[1:] > env[:-1] * 4) & (env[1:] > peak * 0.05))) if n > 1 else 0
    # brightness: the spectral centroid of the whole sound, in Hz
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    freqs = np.fft.rfftfreq(len(x), 1 / RATE)
    centroid = float(np.sum(freqs * spec) / max(np.sum(spec), 1e-9))
    return {"len": len(x) / RATE, "body": body, "peak": db(peak), "rms": db(rms), "hits": hits, "hz": centroid}


def audio_files(packdir):
    out = []
    for root, _, files in os.walk(packdir):
        for f in files:
            if f.lower().endswith(AUDIO) and not f.startswith("._"):
                out.append(os.path.relpath(os.path.join(root, f), packdir))
    return sorted(out)


NOTES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
# Melodic sounds whose notes the survey prints, so a rising (happy) one can be told from a falling one
MELODIC = re.compile(r"jingles_(HIT|PIZZA|STEEL|SAX)\d+|confirmation_|question_|maximize_00[6-9]|zap|twoTone|threeTone")


def contour(x):
    """The strongest pitch in each 60 ms stretch that's loud, as note names (repeats merged)."""
    n, out = 2646, []
    peak = np.max(np.abs(x)) or 1
    freqs = np.fft.rfftfreq(n, 1 / RATE)
    band = (freqs > 150) & (freqs < 2500)
    for k in range(0, len(x) - n, n):
        w = x[k:k + n]
        if np.sqrt(np.mean(w ** 2)) < peak * 0.05:
            continue
        spec = np.abs(np.fft.rfft(w * np.hanning(n)))
        f = freqs[band][np.argmax(spec[band])]
        m = int(round(69 + 12 * np.log2(f / 440)))
        name = f"{NOTES[m % 12]}{m // 12 - 1}"
        if not out or out[-1] != name:
            out.append(name)
    return " ".join(out)


def survey(packdir):
    files = [f for f in audio_files(packdir) if "preview" not in f.lower()]
    melodic = []
    print(f"{len(files)} sounds")
    print(f"{'file':70} {'len s':>6} {'body s':>6} {'peak':>6} {'rms':>6} {'hits':>4} {'bright Hz':>9}")
    for rel in files:
        try:
            s = stats(decode(os.path.join(packdir, rel)))
        except subprocess.CalledProcessError:
            print(f"{rel:70} (couldn't decode)")
            continue
        print(f"{rel:70} {s['len']:6.2f} {s['body']:6.2f} {s['peak']:6.1f} {s['rms']:6.1f} {s['hits']:4d} {s['hz']:9.0f}")
        if MELODIC.search(rel):
            melodic.append(rel)
    print("\nNotes (the strongest pitch every 60 ms while it's loud):")
    for rel in melodic:
        print(f"{rel:70} {contour(decode(os.path.join(packdir, rel)))}")


def shape(x, pick, name):
    """Trim the silence in front, cut to length, fade, and level the peak."""
    if pick.get("start"):
        x = x[int(pick["start"] * RATE):]
    peak = np.max(np.abs(x)) or 1
    lead = np.argmax(np.abs(x) > peak * 0.003)   # about -50 dB under the peak
    x = x[max(0, lead - int(0.002 * RATE)):]
    if pick.get("length"):
        x = x[: int(pick["length"] * RATE)]
    # trailing silence goes too
    tail = len(x) - np.argmax(np.abs(x[::-1]) > np.max(np.abs(x)) * 0.002)
    x = x[: min(len(x), tail + int(0.01 * RATE))].copy()
    fin = int(0.003 * RATE)
    fout = min(len(x), int(pick.get("fade", 0.06) * RATE))
    x[:fin] *= np.linspace(0, 1, fin)
    x[len(x) - fout:] *= np.linspace(1, 0, fout) ** 2
    target = pick.get("peak", PEAKS.get(name, -4)) + pick.get("gain", 0)
    return x * (10 ** (target / 20) / (np.max(np.abs(x)) or 1))


def field(html, name):
    """The text of one field on an OpenGameArt page (License(s), Author, Attribution...), tags stripped."""
    i = html.find(f"field-name-{name}")
    if i < 0:
        return ""
    j = html.find("field-name-", i + 20)
    if j < 0:
        j = i + 3000
    j = html.rfind("<", i, j)   # the next field's opening tag isn't part of this one
    text = re.sub(r"<[^>]+>", " ", html[i:j])
    text = re.sub(r"\s+", " ", text.split(">", 1)[-1]).replace("&nbsp;", " ").replace("&quot;", '"').strip()
    return text


def packs(listfile, packdir):
    """Downloads each OpenGameArt page's files (name and page URL, one per line in listfile) into packdir/<name>, and
    records each page's license, author and attribution in packdir/_licenses.json. A page that can't be reached is
    skipped; at least one has to come down."""
    os.makedirs(packdir, exist_ok=True)
    info = {}
    for line in open(listfile):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        name, page = line.split()
        try:
            html = urllib.request.urlopen(page, timeout=60).read().decode("utf-8", "replace")
        except Exception as e:   # noqa: BLE001 (a missing page is skipped, not fatal)
            print(f"::warning::{name}: {page}: {e}")
            continue
        title = re.search(r"<title>([^<]*)</title>", html)
        lic = field(html, "field-art-licenses")
        rec = {"page": page, "title": title.group(1).strip() if title else "", "license": lic,
               "author": field(html, "author-submitter") or field(html, "field-art-author"),
               "attribution": field(html, "field-art-attribution"), "files": []}
        links = sorted(set(re.findall(r'https?://opengameart\.org/sites/default/files/[^"\'<> ]+', html)))
        links = [u for u in links if u.lower().rsplit(".", 1)[-1] in ("zip", "ogg", "wav", "mp3", "flac")]
        dest = os.path.join(packdir, name)
        os.makedirs(dest, exist_ok=True)
        for u in links:
            fn = os.path.join(dest, os.path.basename(urllib.parse.unquote(u)))
            try:
                with urllib.request.urlopen(u, timeout=120) as r, open(fn, "wb") as f:
                    f.write(r.read())
            except Exception as e:   # noqa: BLE001
                print(f"::warning::{name}: {u}: {e}")
                continue
            rec["files"].append(os.path.basename(fn))
            if fn.lower().endswith(".zip"):
                with zipfile.ZipFile(fn) as z:
                    for m in z.namelist():   # never outside the pack's folder
                        if m.startswith("/") or ".." in m.split("/"):
                            continue
                        z.extract(m, dest)
                os.remove(fn)
        info[name] = rec
        print(f"== {name}: {rec['title']}\n   page: {page}\n   license: {lic or '(none found)'}\n"
              f"   author: {rec['author']}\n   attribution: {rec['attribution']}\n   files: {rec['files']}")
    json.dump(info, open(os.path.join(packdir, "_licenses.json"), "w"), indent=1)
    if not any(r["files"] for r in info.values()):
        print("::error::No pack came down")
        sys.exit(1)


def allowed(license_text):
    """CC0, or plain CC-BY (credit given). A page with several licenses lets you choose any one of them."""
    words = re.findall(r"CC0|CC-BY[-A-Z]*", license_text.upper())
    return any(w == "CC0" or w == "CC-BY" for w in words)


def pick(packdir, picks_path, outdir):
    picks = json.load(open(picks_path))
    licenses = json.load(open(os.path.join(packdir, "_licenses.json")))
    bad = []
    for name, p in picks.items():
        if name.startswith("_"):
            continue
        pack = p["file"].split("/", 1)[0]
        lic = licenses.get(pack, {}).get("license", "")
        if not allowed(lic):
            bad.append(f"{name}: pack {pack}'s license isn't CC0 or CC-BY: {lic!r}")
            continue
        src = os.path.join(packdir, p["file"])
        x = shape(decode(src, p.get("filter", "")), p, name)
        path = os.path.join(outdir, f"{name}.caf")
        encode_caf(path, x)
        size = os.path.getsize(path)
        s = stats(decode(path))
        print(f"{name}.caf  <- {p['file']} ({lic})  {s['len']:.2f} s, peak {s['peak']:.1f} dB, rms {s['rms']:.1f} dB, {size} bytes")
        if size > MAX_BYTES:
            bad.append(f"{name}.caf is {size} bytes (over {MAX_BYTES})")
        old = os.path.join(outdir, f"{name}.wav")
        if os.path.exists(old):
            os.remove(old)   # the app plays the .caf when there is one; the synthesized .wav goes
    if bad:
        print("\n".join(bad))
        sys.exit(1)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "packs" and len(sys.argv) == 4:
        packs(sys.argv[2], sys.argv[3])
    elif mode == "survey" and len(sys.argv) == 3:
        survey(sys.argv[2])
    elif mode == "pick" and len(sys.argv) == 5:
        pick(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        print(__doc__)
        sys.exit(2)
