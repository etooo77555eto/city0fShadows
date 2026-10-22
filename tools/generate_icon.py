#!/usr/bin/env python3
"""Draws the City of Shadows app icon (1024x1024) — run in CI before xcodebuild.

Design: night-city gradient (deep navy -> violet), a crescent moon, dark
building silhouettes with warm lit windows, and a wet-street reflection band.
The PNG is generated, never committed (push tooling is text-only).
"""
import os
import random
from PIL import Image, ImageDraw

SIZE = 1024
OUT = os.path.join(os.path.dirname(__file__), "..",
                   "CityOfShadows", "Assets.xcassets", "AppIcon.appiconset",
                   "icon-1024.png")

TOP = (10, 12, 34)       # deep night navy
MID = (38, 24, 74)       # violet
LOW = (86, 38, 92)       # dusk magenta near horizon

# Vertical gradient via a small strip, upscaled for smoothness.
small = Image.new("RGB", (1, 256))
px = small.load()
for y in range(256):
    t = y / 255.0
    if t < 0.55:
        k = t / 0.55
        px[0, y] = tuple(int(TOP[i] + (MID[i] - TOP[i]) * k) for i in range(3))
    else:
        k = (t - 0.55) / 0.45
        px[0, y] = tuple(int(MID[i] + (LOW[i] - MID[i]) * k) for i in range(3))
img = small.resize((SIZE, SIZE), Image.BICUBIC)
d = ImageDraw.Draw(img, "RGBA")

# Stars.
random.seed(11)
for _ in range(110):
    x = random.randint(0, SIZE - 1)
    y = random.randint(0, int(SIZE * 0.45))
    r = random.choice([1, 1, 2])
    a = random.randint(90, 200)
    d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, a))

# Crescent moon (two overlapping circles).
mx, my, mr = int(SIZE * 0.76), int(SIZE * 0.20), int(SIZE * 0.085)
d.ellipse([mx - mr, my - mr, mx + mr, my + mr], fill=(245, 240, 205, 255))
d.ellipse([mx - mr + int(mr * 0.55), my - mr - int(mr * 0.18),
           mx + mr + int(mr * 0.55), my + mr - int(mr * 0.18)],
          fill=(24, 18, 52, 255))

# Building silhouettes (two depth layers).
def skyline(base_y, color, seed, hmin, hmax):
    rng = random.Random(seed)
    x = -20
    buildings = []
    while x < SIZE + 20:
        w = rng.randint(70, 150)
        h = rng.randint(hmin, hmax)
        buildings.append((x, base_y - h, w, h))
        x += w + rng.randint(4, 26)
    for (bx, by, bw, bh) in buildings:
        d.rectangle([bx, by, bx + bw, base_y], fill=color)
        # Lit windows.
        cols = max(1, bw // 22)
        rows = max(1, bh // 30)
        for cx in range(cols):
            for cy in range(rows):
                if rng.random() < 0.34:
                    wx = bx + 8 + cx * 22
                    wy = by + 10 + cy * 30
                    warm = rng.choice([(255, 196, 92), (255, 220, 150), (170, 205, 255)])
                    d.rectangle([wx, wy, wx + 9, wy + 13], fill=warm + (235,))
    return buildings

horizon = int(SIZE * 0.88)
skyline(horizon, (16, 14, 34, 255), seed=5, hmin=260, hmax=430)
skyline(horizon, (7, 6, 16, 255), seed=9, hmin=150, hmax=300)

# Wet street: dark band + reflection streaks.
d.rectangle([0, horizon, SIZE, SIZE], fill=(5, 5, 12, 255))
for _ in range(46):
    x = random.randint(0, SIZE - 60)
    y = random.randint(horizon + 8, SIZE - 14)
    w = random.randint(22, 70)
    col = random.choice([(255, 196, 92), (150, 120, 255), (120, 180, 255)])
    d.rectangle([x, y, x + w, y + 3], fill=col + (120,))

os.makedirs(os.path.dirname(OUT), exist_ok=True)
img.save(OUT, "PNG")
print("icon written:", OUT, img.size)
