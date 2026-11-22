#!/usr/bin/env python3
"""The side-by-side for Tyler (#718): today and the three cinematic options, the same moments, from the stills each
option's Mac run committed (docs/app/cinematic/<option>/). Writes docs/app/cinematic/compare-overdraft.jpg and
compare-dice.jpg: one column each, labeled, the recent iPhone simulator's stills at half size.

  python3 scripts/cinema-compare.py        # needs Pillow
"""
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(__file__), "..", "docs", "app", "cinematic")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
SMALL = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


def sheet(name, cols, title):
    shots = []
    for label, sub, rel in cols:
        p = os.path.join(ROOT, rel)
        if os.path.exists(p):
            shots.append((label, sub, Image.open(p).convert("RGB")))
    if not shots:
        print("no stills for", name)
        return
    w = shots[0][2].width // 2
    h = shots[0][2].height // 2
    pad, head, top = 24, 110, 90
    out = Image.new("RGB", (pad + len(shots) * (w + pad), top + head + h + pad), (14, 12, 22))
    d = ImageDraw.Draw(out)
    d.text((pad, 26), title, fill=(240, 236, 250), font=font(FONT, 40))
    for i, (label, sub, im) in enumerate(shots):
        x = pad + i * (w + pad)
        d.text((x, top + 8), label, fill=(255, 214, 120), font=font(FONT, 34))
        d.text((x, top + 56), sub, fill=(200, 196, 214), font=font(SMALL, 22))
        out.paste(im.resize((w, h), Image.LANCZOS), (x, top + head))
    path = os.path.join(ROOT, name)
    out.save(path, quality=86)
    print("wrote", os.path.normpath(path), out.size)


sheet("compare-overdraft.jpg", [
    ("Today", "the storm as it is", "director/recent-overdraft-strike-today.jpg"),
    ("A: the director", "the camera: push-in, hit stop, shake", "director/recent-overdraft-strike.jpg"),
    ("B: the storm", "the world: HDR, bloom, staged strike", "storm/recent-overdraft-strike.jpg"),
    ("C: big moments", "a slow-motion sequence for your Bolt", "moments/recent-overdraft-strike.jpg"),
], "Overdraft, a Bolt's strike (0.08 s after it lands), iPhone 17 Pro simulator")

sheet("compare-dice.jpg", [
    ("Today", "your roll", "director/recent-dice-mid-roll-today.jpg"),
    ("A: the director", "a Farkle: the knock", "director/recent-dice-farkle.jpg"),
    ("B: the storm", "a Farkle: the light's swell", "storm/recent-dice-farkle.jpg"),
    ("C: big moments", "a Farkle: in slow motion", "moments/recent-dice-farkle.jpg"),
], "10000, your roll landing, iPhone 17 Pro simulator")
