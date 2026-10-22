#!/usr/bin/env python3
"""Generates the City of Shadows procedural texture pack (PIL only).

All textures are original, drawn from noise/lines/rects at runtime in CI —
the same pattern as generate_icon.py. Output: CityOfShadows/Textures/*.jpg
"""
import os
import random
from PIL import Image, ImageDraw, ImageFont

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "CityOfShadows", "Textures")


def save(img, name, quality=86):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    img.save(path, "JPEG", quality=quality)
    print("texture:", name, img.size, os.path.getsize(path), "bytes")


def noise_layer(size, base, spread, seed):
    rng = random.Random(seed)
    img = Image.new("RGB", (size // 4, size // 4))
    px = img.load()
    for y in range(size // 4):
        for x in range(size // 4):
            px[x, y] = tuple(max(0, min(255, base[i] + rng.randint(-spread, spread)))
                             for i in range(3))
    return img.resize((size, size), Image.BILINEAR)


def speckle(img, count, colors, seed, rmin=1, rmax=3):
    rng = random.Random(seed)
    d = ImageDraw.Draw(img)
    w, h = img.size
    for _ in range(count):
        x = rng.randint(0, w - 1)
        y = rng.randint(0, h - 1)
        r = rng.randint(rmin, rmax)
        d.ellipse([x - r, y - r, x + r, y + r], fill=rng.choice(colors))
    return img


def asphalt():
    size = 2048
    img = noise_layer(size, (40, 40, 45), 14, 101)
    d = ImageDraw.Draw(img)
    rng = random.Random(7)
    # Worn patches
    for _ in range(26):
        x, y = rng.randint(0, size - 200), rng.randint(0, size - 200)
        w, h = rng.randint(120, 440), rng.randint(80, 320)
        tone = rng.randint(30, 62)
        d.ellipse([x, y, x + w, y + h], fill=(tone, tone, tone + 4))
    # Cracks
    for _ in range(15):
        x, y = rng.randint(0, size - 1), rng.randint(0, size - 1)
        for _ in range(rng.randint(4, 9)):
            nx = x + rng.randint(-92, 92)
            ny = y + rng.randint(-92, 92)
            d.line([x, y, nx, ny], fill=(18, 18, 20), width=3)
            x, y = nx, ny
    speckle(img, 20000, [(52, 52, 58), (30, 30, 34), (66, 66, 72)], 55)
    save(img, "asphalt.jpg")


def concrete():
    img = noise_layer(1024, (118, 118, 122), 12, 202)
    d = ImageDraw.Draw(img)
    # Slab grid
    for i in range(0, 1025, 256):
        d.line([i, 0, i, 1024], fill=(88, 88, 92), width=4)
        d.line([0, i, 1024, i], fill=(88, 88, 92), width=4)
    rng = random.Random(3)
    for _ in range(18):  # stains
        x, y = rng.randint(0, 900), rng.randint(0, 900)
        w = rng.randint(40, 150)
        d.ellipse([x, y, x + w, y + w // 2], fill=(102, 102, 106))
    speckle(img, 3500, [(132, 132, 136), (104, 104, 108)], 21)
    save(img, "concrete.jpg")


def facade(name, base, frame, cols, rows, lit_ratio, seed, door=False, size=2048):
    img = noise_layer(size, base, 8, seed)
    d = ImageDraw.Draw(img)
    rng = random.Random(seed + 1)
    cw = size // cols
    ch = size // rows
    for cx in range(cols):
        for cy in range(rows):
            x0 = cx * cw + cw // 5
            y0 = cy * ch + ch // 5
            x1 = (cx + 1) * cw - cw // 5
            y1 = (cy + 1) * ch - ch // 6
            if rng.random() < lit_ratio:
                col = rng.choice([(255, 199, 105), (255, 220, 150), (190, 215, 255)])
            else:
                col = (28 + rng.randint(0, 18), 38 + rng.randint(0, 16), 54 + rng.randint(0, 20))
            d.rectangle([x0, y0, x1, y1], fill=col, outline=frame, width=4)
            d.line([x0, (y0 + y1) // 2, x1, (y0 + y1) // 2], fill=frame, width=3)
    if door:
        d.rectangle([size * 44 // 100, size * 88 // 100,
                     size * 56 // 100, size - 1], fill=(40, 32, 26), outline=frame, width=5)
    save(img, name)


def brick():
    img = noise_layer(1024, (122, 74, 58), 16, 303)
    d = ImageDraw.Draw(img)
    rng = random.Random(9)
    bh, bw = 32, 128
    for row in range(1024 // bh):
        offset = (row % 2) * (bw // 2)
        for col in range(-1, 1024 // bw + 1):
            x = col * bw + offset
            y = row * bh
            tone = rng.randint(-14, 14)
            d.rectangle([x + 3, y + 3, x + bw - 3, y + bh - 3],
                        fill=(122 + tone, 74 + tone // 2, 58 + tone // 2))
    save(img, "brick.jpg")


def warehouse():
    img = noise_layer(1024, (96, 104, 100), 10, 404)
    d = ImageDraw.Draw(img)
    for x in range(0, 1025, 42):  # corrugation
        d.line([x, 0, x, 1024], fill=(74, 82, 78), width=5)
        d.line([x + 18, 0, x + 18, 1024], fill=(116, 124, 118), width=3)
    rng = random.Random(4)
    for _ in range(12):  # rust streaks
        x = rng.randint(0, 1000)
        y = rng.randint(0, 600)
        d.line([x, y, x + rng.randint(-6, 6), y + rng.randint(80, 260)],
               fill=(110, 72, 44), width=rng.randint(3, 8))
    d.rectangle([312, 560, 712, 1023], fill=(70, 76, 72), outline=(52, 56, 52), width=6)
    for y in range(600, 1024, 84):
        d.line([312, y, 712, y], fill=(52, 56, 52), width=4)
    save(img, "warehouse.jpg")


def shopfront():
    img = noise_layer(1024, (52, 54, 66), 8, 505)
    d = ImageDraw.Draw(img)
    # Abstract coloured sign panels (no text, no brands).
    panels = [(214, 84, 70), (66, 150, 190), (240, 178, 66), (112, 186, 128), (168, 110, 190)]
    rng = random.Random(6)
    x = 24
    i = 0
    while x < 940:
        w = rng.randint(120, 220)
        d.rectangle([x, 60, x + w, 240], fill=panels[i % len(panels)])
        d.rectangle([x + 14, 84, x + w - 14, 150], fill=(240, 240, 235))
        x += w + 26
        i += 1
    # Glass storefront below.
    for gx in range(4):
        x0 = 24 + gx * 248
        d.rectangle([x0, 420, x0 + 224, 980], fill=(24, 44, 62), outline=(150, 155, 165), width=5)
        d.polygon([(x0 + 20, 980), (x0 + 110, 420), (x0 + 170, 420), (x0 + 60, 980)],
                  fill=(40, 66, 88))
    d.rectangle([0, 980, 1024, 1024], fill=(30, 30, 34))
    save(img, "shopfront.jpg")


def sand():
    img = noise_layer(1024, (196, 172, 128), 13, 606)
    speckle(img, 7000, [(214, 192, 150), (178, 152, 108), (226, 206, 168)], 61, 1, 2)
    save(img, "sand.jpg")


def grass():
    img = noise_layer(1024, (52, 96, 44), 14, 707)
    d = ImageDraw.Draw(img)
    rng = random.Random(71)
    greens = [(66, 118, 52), (44, 84, 38), (84, 138, 62), (58, 104, 48)]
    for _ in range(5200):
        x = rng.randint(0, 1023)
        y = rng.randint(0, 1023)
        d.line([x, y, x + rng.randint(-2, 2), y - rng.randint(4, 9)],
               fill=rng.choice(greens), width=1)
    save(img, "grass.jpg")


def water():
    img = noise_layer(1024, (16, 58, 96), 12, 808)
    d = ImageDraw.Draw(img)
    rng = random.Random(81)
    for _ in range(240):
        x = rng.randint(0, 980)
        y = rng.randint(0, 1023)
        w = rng.randint(24, 90)
        tone = rng.choice([(30, 84, 128), (42, 104, 148), (24, 70, 110)])
        d.line([x, y, x + w, y], fill=tone, width=rng.randint(2, 4))
    save(img, "water.jpg")


def sky():
    img = Image.new("RGB", (1024, 512))
    px = img.load()
    top = (26, 52, 108)
    mid = (96, 140, 196)
    low = (238, 196, 138)
    for y in range(512):
        t = y / 511.0
        if t < 0.7:
            k = t / 0.7
            col = tuple(int(top[i] + (mid[i] - top[i]) * k) for i in range(3))
        else:
            k = (t - 0.7) / 0.3
            col = tuple(int(mid[i] + (low[i] - mid[i]) * k) for i in range(3))
        for x in range(1024):
            px[x, y] = col
    save(img, "sky_gradient.jpg", quality=88)


def sky_env():
    """Equirect-style environment map for SceneKit IBL (lightingEnvironment).

    2048x1024: sky-blue gradient up top, warm horizon glow band, dark ground
    below the horizon line. Built small and upscaled for smoothness.
    """
    w, h = 512, 256
    img = Image.new("RGB", (w, h))
    px = img.load()
    sky_top = (52, 102, 178)
    sky_low = (148, 182, 222)
    glow = (246, 205, 152)
    ground_hi = (52, 47, 44)
    ground_lo = (16, 15, 16)
    horizon = 0.56
    for y in range(h):
        t = y / float(h - 1)
        if t < horizon - 0.06:
            k = t / (horizon - 0.06)
            col = tuple(int(sky_top[i] + (sky_low[i] - sky_top[i]) * k) for i in range(3))
        elif t < horizon + 0.06:
            k = (t - (horizon - 0.06)) / 0.12
            col = tuple(int(sky_low[i] + (glow[i] - sky_low[i]) * k) for i in range(3))
        else:
            k = (t - (horizon + 0.06)) / (1.0 - horizon - 0.06)
            col = tuple(int(ground_hi[i] + (ground_lo[i] - ground_hi[i]) * k) for i in range(3))
        for x in range(w):
            px[x, y] = col
    img = img.resize((2048, 1024), Image.BILINEAR)
    save(img, "sky_env.jpg", quality=90)


def billboard():
    """Fictional night-race ad artwork for the 3D city billboards.

    1024x512, original art: neon headline "SHADOW GRAND PRIX" over a
    city skyline silhouette, plus a fictional "VEGA MOTORS" tagline.
    No real brands, no real-world references.
    """
    w, h = 1024, 512
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    # Night-sky gradient backdrop.
    for y in range(h):
        t = y / float(h - 1)
        col = (int(8 + 30 * t), int(6 + 26 * t), int(26 + 84 * t))
        d.line([0, y, w, y], fill=col)
    # Distant glow band.
    for y in range(300, 380):
        k = 1 - abs(y - 340) / 40.0
        d.line([0, y, w, y], fill=(int(90 * k) + 8, int(40 * k) + 6, int(120 * k) + 26))
    # Skyline silhouette with lit windows.
    rng = random.Random(99)
    x = 0
    while x < w:
        bw = rng.randint(46, 110)
        bh = rng.randint(120, 290)
        d.rectangle([x, h - bh, x + bw, h], fill=(7, 7, 16))
        d.rectangle([x, h - bh, x + bw, h - bh + 4], fill=(16, 14, 30))
        for _ in range(rng.randint(10, 24)):
            wx = rng.randint(x + 6, x + bw - 14)
            wy = rng.randint(h - bh + 12, h - 24)
            win = rng.choice([(255, 200, 110), (150, 220, 255), (255, 140, 200)])
            d.rectangle([wx, wy, wx + 8, wy + 10], fill=win)
        x += bw + rng.randint(4, 18)
    # Light streaks of a night race track at the bottom.
    for _ in range(26):
        sx = rng.randint(0, w - 160)
        sy = rng.randint(h - 70, h - 14)
        streak = rng.choice([(255, 90, 120), (90, 200, 255), (255, 214, 90)])
        d.line([sx, sy, sx + rng.randint(60, 160), sy], fill=streak, width=3)
    # Headline + tagline.
    try:
        big = ImageFont.load_default(size=96)
        small = ImageFont.load_default(size=44)
    except Exception:  # noqa: BLE001 - very old Pillow without sized bitmap font
        big = ImageFont.load_default()
        small = ImageFont.load_default()
    d.text((w // 2, 120), "SHADOW GRAND PRIX", font=big, anchor="mm",
           fill=(255, 214, 90), stroke_width=3, stroke_fill=(24, 12, 0))
    d.text((w // 2, 210), "VEGA MOTORS  -  SEASON 07", font=small, anchor="mm",
           fill=(150, 225, 255), stroke_width=2, stroke_fill=(8, 20, 30))
    d.text((w // 2, 268), "NIGHT RACING LEAGUE", font=small, anchor="mm",
           fill=(255, 150, 200), stroke_width=2, stroke_fill=(20, 6, 14))
    save(img, "billboard.jpg", quality=88)


def main():
    asphalt()
    concrete()
    facade("facade_high.jpg", (56, 60, 72), (24, 26, 32), 10, 16, 0.22, 111)
    facade("facade_mid.jpg", (96, 88, 78), (40, 38, 34), 8, 12, 0.18, 222)
    facade("facade_house.jpg", (168, 148, 122), (70, 58, 44), 4, 3, 0.30, 333, door=True)
    facade("facade_glass.jpg", (38, 74, 92), (18, 34, 44), 9, 14, 0.26, 444)
    brick()
    warehouse()
    shopfront()
    sand()
    grass()
    water()
    sky()
    sky_env()
    billboard()
    print("texture pack done")


if __name__ == "__main__":
    main()
