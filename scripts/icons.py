#!/usr/bin/env python3
"""The alternate app icons you pick in You: the Time2Play mark (the gold 2 in its ring) lifted off the usual icon and
set on other backgrounds, plus small previews for the picker. Run it to make them again (needs Pillow and numpy):

    python3 scripts/icons.py

Writes App/Assets.xcassets/AppIcon-<Name>.appiconset (1024 x 1024, no transparency) and icon-<name>.imageset."""
import json, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "App", "Assets.xcassets")
SIZE = 1024


def mark():
    """The mark as colors plus a coverage mask, from the navy icon: how far each pixel is from the background."""
    src = np.asarray(Image.open(os.path.join(ROOT, "AppIcon.appiconset", "AppIcon.png")).convert("RGB")).astype(float)
    # the background, smoothed: a heavy blur of the icon with the mark's pixels left out
    r, g, b = src[..., 0], src[..., 1], src[..., 2]
    rough = np.clip((r - 40) / 60, 0, 1)                                 # gold and its brown edge have red; navy has little
    bg_only = src * (1 - rough[..., None])
    weight = Image.fromarray(((1 - rough) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(40))
    blur = np.stack([np.asarray(Image.fromarray(bg_only[..., c].astype(np.uint8)).filter(ImageFilter.GaussianBlur(40))).astype(float)
                     for c in range(3)], -1)
    w = np.asarray(weight).astype(float)[..., None] / 255
    bg = blur / np.maximum(w, 1e-3)
    # coverage: how much brighter in red than the background, scaled so the darkest part of the mark (its brown
    # shadow, about 0x6B in red) counts as solid
    alpha = np.clip((r - bg[..., 0]) / 70, 0, 1)
    alpha = np.where(alpha > 0.97, 1, alpha)
    color = (src - (1 - alpha[..., None]) * bg) / np.maximum(alpha[..., None], 1e-3)
    color = np.clip(color, 0, 255)
    return color, alpha


def radial(top, bottom, glow=None):
    """A soft vertical gradient with a faint glow behind the mark, like the usual icon's."""
    y = np.linspace(0, 1, SIZE)[:, None, None]
    img = np.array(top, float) * (1 - y) + np.array(bottom, float) * y
    img = np.broadcast_to(img, (SIZE, SIZE, 3)).copy()
    if glow:
        yy, xx = np.mgrid[0:SIZE, 0:SIZE]
        d = np.sqrt((xx - SIZE * 0.5) ** 2 + (yy - SIZE * 0.42) ** 2) / (SIZE * 0.55)
        k = np.clip(1 - d, 0, 1) ** 2
        img += (np.array(glow, float) - img) * k[..., None] * 0.5
    return img


def compose(bg, color, alpha):
    a = alpha[..., None]
    return np.clip(bg * (1 - a) + color * a, 0, 255).astype(np.uint8)


def gold_variant(color, alpha):
    """The mark in deep navy on a gold field: the colors swapped, the 2's shading kept as light and dark."""
    lum = color.mean(-1, keepdims=True) / 255
    navy_dark, navy_light = np.array([8, 13, 30], float), np.array([40, 52, 92], float)
    ink = navy_dark + (navy_light - navy_dark) * np.clip((lum - 0.35) / 0.6, 0, 1)
    bg = radial((246, 206, 120), (214, 150, 52), glow=(255, 228, 160))
    return compose(bg, ink, alpha)


def write_icon(name, pixels):
    d = os.path.join(ROOT, f"{name}.appiconset")
    os.makedirs(d, exist_ok=True)
    Image.fromarray(pixels, "RGB").save(os.path.join(d, "AppIcon.png"), optimize=True)
    json.dump({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
               "info": {"author": "xcode", "version": 1}}, open(os.path.join(d, "Contents.json"), "w"), indent=2)


def write_preview(name, pixels):
    d = os.path.join(ROOT, f"{name}.imageset")
    os.makedirs(d, exist_ok=True)
    Image.fromarray(pixels, "RGB").resize((180, 180), Image.LANCZOS).save(os.path.join(d, f"{name}.png"), optimize=True)
    json.dump({"images": [{"filename": f"{name}.png", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}},
              open(os.path.join(d, "Contents.json"), "w"), indent=2)


def main():
    color, alpha = mark()
    navy = np.asarray(Image.open(os.path.join(ROOT, "AppIcon.appiconset", "AppIcon.png")).convert("RGB"))
    variants = {
        "Midnight": compose(radial((22, 22, 24), (2, 2, 3), glow=(38, 36, 34)), color, alpha),
        "Felt": compose(radial((36, 92, 70), (14, 46, 34), glow=(52, 118, 90)), color, alpha),
        "Plum": compose(radial((70, 34, 72), (26, 12, 30), glow=(98, 50, 96)), color, alpha),
        "Gold": gold_variant(color, alpha),
    }
    write_preview("icon-navy", navy)
    for name, px in variants.items():
        write_icon(f"AppIcon-{name}", px)
        write_preview(f"icon-{name.lower()}", px)
        print(f"AppIcon-{name}")


if __name__ == "__main__":
    main()
