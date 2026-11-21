#!/usr/bin/env python3
"""Captioned App Store screenshots (1.1): each raw screenshot from a Store listing run (the store-shots download), on
navy with a two-line caption from store/captions.json above it. Same pixel size as the raw one, no transparency, so
App Store Connect takes it as it is. Usage: caption-shots.py RAW_DIR OUT_DIR FONT_DIR (Nunito 800 and 900 as TTF)."""
import json, os, re, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

NAVY, NAVY2 = (11, 17, 33), (22, 32, 64)
GOLD, PAPER = (233, 180, 90), (244, 234, 213)

def background(w, h):
    bg = Image.new("RGB", (w, h), NAVY)
    glow = Image.new("RGB", (w, h), NAVY)
    d = ImageDraw.Draw(glow)
    r = int(w * 0.9)
    d.ellipse((w // 2 - r, -r // 2, w // 2 + r, int(r * 1.1)), fill=NAVY2)
    return Image.blend(bg, glow.filter(ImageFilter.GaussianBlur(w // 6)), 1.0)

def line_parts(text):
    """'Share the code. {Play.}' -> [('Share the code. ', paper), ('Play.', gold)]"""
    out = []
    for i, part in enumerate(re.split(r"[{}]", text)):
        if part:
            out.append((part, GOLD if i % 2 else PAPER))
    return out

def draw_line(d, text, font, cx, y):
    parts = line_parts(text)
    widths = [d.textlength(t, font=font) for t, _ in parts]
    x = cx - sum(widths) / 2
    for (t, c), wd in zip(parts, widths):
        d.text((x, y), t, font=font, fill=c)
        x += wd

def fit(d, lines, font_path, size, maxw):
    while size > 20:
        f = ImageFont.truetype(font_path, size)
        if all(d.textlength(re.sub(r"[{}]", "", l), font=f) <= maxw for l in lines):
            return f
        size -= 4
    return ImageFont.truetype(font_path, size)

def caption(raw_path, lines, out_path, fonts):
    shot = Image.open(raw_path).convert("RGB")
    w, h = shot.size
    pad = 1 if w < h * 0.85 else 0          # iPhone is tall; iPad is nearly square
    img = background(w, h)
    d = ImageDraw.Draw(img)
    top = int(h * (0.075 if pad else 0.06))
    big = fit(d, lines, fonts[900], int(w * (0.085 if pad else 0.06)), w * 0.86)
    lh = int(big.size * 1.18)
    for i, l in enumerate(lines):
        draw_line(d, l, big, w / 2, top + i * lh)
    cap_bottom = top + len(lines) * lh + int(h * 0.035)

    # the screenshot, scaled to fit under the caption, with rounded corners and a thin gold edge
    room_h = h - cap_bottom - int(h * 0.04)
    scale = min(room_h / h, (w * 0.86) / w)
    sw, sh = int(w * scale), int(h * scale)
    small = shot.resize((sw, sh), Image.LANCZOS)
    radius = int(sw * (0.085 if pad else 0.035))
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), radius, fill=255)
    x, y = (w - sw) // 2, cap_bottom
    shadow = Image.new("L", (w, h), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((x, y + 18, x + sw, y + sh + 18), radius, fill=150)
    img = Image.composite(Image.new("RGB", (w, h), (0, 0, 0)), img, shadow.filter(ImageFilter.GaussianBlur(28)))
    edge = max(4, w // 300)
    ImageDraw.Draw(img).rounded_rectangle((x - edge, y - edge, x + sw + edge, y + sh + edge), radius + edge, fill=GOLD)
    img.paste(small, (x, y), mask)
    img.save(out_path, "PNG")
    print(f"{os.path.basename(out_path)}: {w}x{h}")

def main(raw_dir, out_dir, font_dir):
    caps = json.load(open(os.path.join(os.path.dirname(__file__), "..", "store", "captions.json")))
    fonts = {900: os.path.join(font_dir, "nunito-900.ttf")}
    os.makedirs(out_dir, exist_ok=True)
    for f in sorted(os.listdir(raw_dir)):
        m = re.fullmatch(r"store-(iphone|ipad)-(.+)\.png", f)
        if not m or m.group(2) not in caps:
            continue
        caption(os.path.join(raw_dir, f), caps[m.group(2)], os.path.join(out_dir, f), fonts)

if __name__ == "__main__":
    main(*sys.argv[1:4])
