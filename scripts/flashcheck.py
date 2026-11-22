#!/usr/bin/env python3
"""The photosensitivity check for #708's cinematic options (WCAG 2.2, 2.3.1 Three Flashes or Below Threshold).

Reads a recording (any video ffmpeg can open), samples it at a steady frame rate, and counts general flashes and red
flashes in every one-second window, for the whole screen and for each quarter of it (a flash in one corner of the
screen is still a flash).

  python3 scripts/flashcheck.py recording.mp4 [--fps 60] [--limit 2] [--name overdraft-director]

A general flash is a pair of opposing changes in relative luminance of 10% or more of the maximum, where the darker
state is below 0.80 (WCAG's definition). A red flash is the same pair of changes in the share of saturated red
(R / (R + G + B) >= 0.8) in that area. #708's own bar is stricter than WCAG's three: at most 2 general flashes in
any second, and no red flashes at all. Prints one line per area and a verdict line:
  FLASHCHECK <name> PASS general=<most in a second> red=<most in a second> limit=<limit>
and exits 1 on a failure. Needs ffmpeg; no other packages.
"""
import argparse
import subprocess
import sys

W, H = 72, 156   # the frames are scaled to this before measuring: plenty for screen-sized flashes


def srgb_to_linear(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


LIN = [srgb_to_linear(i) for i in range(256)]


def frames(path, fps):
    cmd = ["ffmpeg", "-v", "error", "-i", path, "-vf", f"fps={fps},scale={W}:{H}:flags=area", "-f", "rawvideo",
           "-pix_fmt", "rgb24", "-"]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    size = W * H * 3
    while True:
        b = p.stdout.read(size)
        if len(b) < size:
            break
        yield b
    p.wait()


def areas():
    """The whole screen and its four quarters, as (name, x0, y0, x1, y1)."""
    hw, hh = W // 2, H // 2
    return [("screen", 0, 0, W, H), ("top-left", 0, 0, hw, hh), ("top-right", hw, 0, W, hh),
            ("bottom-left", 0, hh, hw, H), ("bottom-right", hw, hh, W, H)]


def measure(b, a):
    _, x0, y0, x1, y1 = a
    lum = red = 0.0
    n = 0
    for y in range(y0, y1):
        row = y * W * 3
        for x in range(x0, x1):
            i = row + x * 3
            r, g, bl = b[i], b[i + 1], b[i + 2]
            lum += 0.2126 * LIN[r] + 0.7152 * LIN[g] + 0.0722 * LIN[bl]
            s = r + g + bl
            if s > 0 and r / s >= 0.8:
                red += 1
            n += 1
    return lum / n, red / n


def transitions(series, general=True):
    """Frame indexes where a change of 10% or more from the last turning point completes (WCAG's transitions).
    A rise or fall goes on being the same transition until it turns. For general flashes the darker state must be
    below 0.80."""
    out = []
    if not series:
        return out
    lo = hi = series[0]
    direction = 0   # +1 rising (hi is the peak so far), -1 falling (lo is the trough so far), 0 not known yet
    for i, v in enumerate(series[1:], 1):
        if direction == 0:
            lo, hi = min(lo, v), max(hi, v)
            if v - lo >= 0.1 and (not general or lo < 0.8):
                out.append(i); direction = 1; hi = v
            elif hi - v >= 0.1 and (not general or v < 0.8):
                out.append(i); direction = -1; lo = v
        elif direction == 1:
            if v > hi:
                hi = v
            elif hi - v >= 0.1 and (not general or v < 0.8):
                out.append(i); direction = -1; lo = v
        else:
            if v < lo:
                lo = v
            elif v - lo >= 0.1 and (not general or lo < 0.8):
                out.append(i); direction = 1; hi = v
    return out


def most_in_a_second(trans, fps):
    """The most flashes (pairs of opposing transitions) in any one-second window."""
    best = 0
    j = 0
    for i in range(len(trans)):
        while trans[i] - trans[j] >= fps:
            j += 1
        best = max(best, (i - j + 1) // 2)
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--fps", type=int, default=60)
    ap.add_argument("--limit", type=int, default=2)
    ap.add_argument("--name", default="")
    o = ap.parse_args()
    ars = areas()
    lum = {a[0]: [] for a in ars}
    red = {a[0]: [] for a in ars}
    count = 0
    for b in frames(o.video, o.fps):
        count += 1
        for a in ars:
            l, r = measure(b, a)
            lum[a[0]].append(l); red[a[0]].append(r)
    if count < o.fps:
        print(f"FLASHCHECK {o.name or o.video} ERROR only {count} frames read")
        return 1
    worst_g = worst_r = 0
    for a in ars:
        k = a[0]
        g = most_in_a_second(transitions(lum[k]), o.fps)
        r = most_in_a_second(transitions(red[k], general=False), o.fps)
        worst_g = max(worst_g, g); worst_r = max(worst_r, r)
        print(f"  {k}: luminance {min(lum[k]):.3f} to {max(lum[k]):.3f}, most general flashes in a second {g}, "
              f"saturated red up to {max(red[k]) * 100:.1f}% of the area, most red flashes in a second {r}")
    ok = worst_g <= o.limit and worst_r == 0
    print(f"FLASHCHECK {o.name or o.video} {'PASS' if ok else 'FAIL'} general={worst_g} red={worst_r} "
          f"limit={o.limit} frames={count} seconds={count / o.fps:.1f}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
