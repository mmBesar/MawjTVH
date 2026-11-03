#!/usr/bin/env python3
"""Draws the MawjTVH icon (a wave on teal that turns from white to amber, over a broadcast signal) and writes
the SVG plus every PNG size the Android and Linux builds need.

Needs Pillow only:  pip install pillow
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
BRANDING = ROOT / "assets" / "branding"

ABYSS = (8, 22, 50)
SWELL = (31, 94, 170)
FOAM = (242, 247, 253)
CREST = (242, 140, 40)
SIGNAL_CX, SIGNAL_CY = 512, 800

SIZE = 1024  # design grid


def wave_points(steps: int = 220):
    """Points of one and a half sine periods across the tile."""
    left, right = 170, 854
    mid = 430
    points = []
    for i in range(steps + 1):
        t = i / steps
        x = left + (right - left) * t
        amp = 150 * (0.55 + 0.45 * math.sin(math.pi * t))
        y = mid - amp * math.sin(t * math.pi * 3.0)
        points.append((x, y))
    return points


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def render(size: int) -> Image.Image:
    scale = 4  # supersample
    s = size * scale
    k = s / SIZE
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    # Rounded tile with a vertical deep-blue gradient.
    tile = Image.new("RGBA", (s, s))
    px = tile.load()
    for y in range(s):
        c = lerp(SWELL, ABYSS, y / s)
        for x in range(s):
            px[x, y] = c + (255,)
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, s - 1, s - 1), radius=int(230 * k), fill=255
    )
    img.paste(tile, (0, 0), mask)

    draw = ImageDraw.Draw(img)
    points = wave_points()
    width = int(70 * k)
    n = len(points)
    for i in range(n - 1):
        t = i / (n - 1)
        # White for the first half, then a quick blend to orange.
        blend = min(1.0, max(0.0, (t - 0.45) / 0.3))
        color = lerp(FOAM, CREST, blend) + (255,)
        p0 = (points[i][0] * k, points[i][1] * k)
        p1 = (points[i + 1][0] * k, points[i + 1][1] * k)
        draw.line((p0, p1), fill=color, width=width)
        r = width / 2
        draw.ellipse((p1[0] - r, p1[1] - r, p1[0] + r, p1[1] + r), fill=color)

    # Broadcast signal under the wave: a dot and two arcs.
    cx, cy, r = SIGNAL_CX * k, SIGNAL_CY * k, 36 * k
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=CREST + (255,))
    for radius in (95, 160):
        rr = radius * k
        draw.arc(
            (cx - rr, cy - rr, cx + rr, cy + rr),
            start=225,
            end=315,
            fill=FOAM + (255,),
            width=int(26 * k),
        )

    return img.resize((size, size), Image.LANCZOS)


def write_svg(path: Path) -> None:
    points = wave_points()
    n = len(points)
    first = " ".join(f"{x:.1f},{y:.1f}" for x, y in points[: int(n * 0.55)])
    second = " ".join(f"{x:.1f},{y:.1f}" for x, y in points[int(n * 0.55) - 1 :])
    arcs = "\n".join(
        f'  <path d="M {SIGNAL_CX - r * math.sin(math.pi / 4):.1f} {SIGNAL_CY - r * math.cos(math.pi / 4):.1f} '
        f'A {r} {r} 0 0 1 {SIGNAL_CX + r * math.sin(math.pi / 4):.1f} {SIGNAL_CY - r * math.cos(math.pi / 4):.1f}" '
        f'fill="none" stroke="rgb{FOAM}" stroke-width="26" stroke-linecap="butt"/>'
        for r in (95, 160)
    )
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}" width="512" height="512">
  <defs>
    <linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="rgb{SWELL}"/>
      <stop offset="1" stop-color="rgb{ABYSS}"/>
    </linearGradient>
  </defs>
  <rect width="{SIZE}" height="{SIZE}" rx="230" fill="url(#tile)"/>
  <polyline points="{first}" fill="none" stroke="rgb{FOAM}" stroke-width="70" stroke-linecap="round" stroke-linejoin="round"/>
  <polyline points="{second}" fill="none" stroke="rgb{CREST}" stroke-width="70" stroke-linecap="round" stroke-linejoin="round"/>
  <circle cx="{SIGNAL_CX}" cy="{SIGNAL_CY}" r="36" fill="rgb{CREST}"/>
{arcs}
</svg>
"""
    path.write_text(svg, encoding="utf-8")


def main() -> None:
    BRANDING.mkdir(parents=True, exist_ok=True)
    (BRANDING / "linux").mkdir(exist_ok=True)
    write_svg(BRANDING / "mawjtvh.svg")
    big = render(512)
    big.save(BRANDING / "mawjtvh_icon.png")
    big.save(BRANDING / "linux" / "mawjtvh.png")
    for density, size in (
        ("mdpi", 48),
        ("hdpi", 72),
        ("xhdpi", 96),
        ("xxhdpi", 144),
        ("xxxhdpi", 192),
    ):
        folder = BRANDING / "android" / f"mipmap-{density}"
        folder.mkdir(parents=True, exist_ok=True)
        render(size).save(folder / "ic_launcher.png")
    print("Icons written under assets/branding/.")


if __name__ == "__main__":
    main()
