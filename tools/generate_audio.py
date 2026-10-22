#!/usr/bin/env python3
"""Generates the City of Shadows audio pack — Python stdlib ONLY
(wave, math, random, array). All sounds are original synthesized tones/noise.
Output: CityOfShadows/Audio/*.wav (legitimately tens of MB in total).
"""
import math
import os
import random
import wave
from array import array

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "CityOfShadows", "Audio")


def clamp16(v):
    if v > 32767:
        return 32767
    if v < -32768:
        return -32768
    return int(v)


def save_wav(name, mono, rate):
    """mono: list of floats -1..1 -> stereo WAV (right = tiny delay echo)."""
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    delay = int(rate * 0.011)
    frames = array("h")
    n = len(mono)
    for i in range(n):
        left = mono[i]
        right = mono[i - delay] * 0.82 if i >= delay else mono[i] * 0.82
        frames.append(clamp16(left * 32767))
        frames.append(clamp16(right * 32767))
    with wave.open(path, "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(rate)
        wf.writeframes(frames.tobytes())
    print("audio:", name, rate, "Hz", round(n / rate, 2), "s",
          os.path.getsize(path), "bytes")


def normalize(buf, peak=0.72):
    m = max(0.0001, max(abs(v) for v in buf))
    k = peak / m
    return [v * k for v in buf]


def lowpass(buf, alpha):
    out = []
    y = 0.0
    for v in buf:
        y += alpha * (v - y)
        out.append(y)
    return out


def menu_music():
    rate = 44100
    dur = 60.0
    n = int(rate * dur)
    # Am - F - C - G, 15 s each; frequencies complete whole cycles per chord
    # segment approximately; a slow swell per chord avoids clicks.
    chords = [
        (110.00, 164.81, 261.63),   # A2 E3 C4
        (87.31, 130.81, 220.00),    # F2 C3 A3
        (130.81, 196.00, 329.63),   # C3 G3 E4
        (98.00, 146.83, 246.94),    # G2 D3 B3
    ]
    buf = [0.0] * n
    seg = n // 4
    for i in range(n):
        t = i / rate
        ci = min(3, i // seg)
        f1, f2, f3 = chords[ci]
        local = (i - ci * seg) / seg
        swell = 0.55 + 0.45 * math.sin(math.pi * min(1.0, local * 1.15))
        v = (math.sin(2 * math.pi * f1 * t) * 0.50 +
             math.sin(2 * math.pi * f2 * t) * 0.32 +
             math.sin(2 * math.pi * f3 * t) * 0.24 +
             math.sin(2 * math.pi * f3 * 2 * t) * 0.06)
        buf[i] = v * swell * 0.6
    buf = lowpass(buf, 0.25)
    buf = lowpass(buf, 0.25)
    save_wav("menu_music.wav", normalize(buf, 0.66), rate)


def engine_loop():
    rate = 22050
    dur = 4.0
    n = int(rate * dur)
    buf = [0.0] * n
    rng = random.Random(5)
    for i in range(n):
        t = i / rate
        trem = 0.9 + 0.1 * math.sin(2 * math.pi * 0.5 * t)  # 2 whole cycles
        v = (math.sin(2 * math.pi * 50 * t) * 0.55 +
             math.sin(2 * math.pi * 100 * t) * 0.30 +
             math.sin(2 * math.pi * 150 * t) * 0.14 +
             (rng.random() * 2 - 1) * 0.05)
        buf[i] = v * trem
    save_wav("engine_loop.wav", normalize(lowpass(buf, 0.5), 0.7), rate)


def siren_loop():
    rate = 22050
    dur = 4.0
    n = int(rate * dur)
    buf = [0.0] * n
    for i in range(n):
        t = i / rate
        seg = int(t / 0.5) % 2
        freq = 720.0 if seg == 0 else 960.0
        # Smooth the switch: blend freq near segment borders.
        frac = (t % 0.5) / 0.5
        if frac > 0.92:
            freq = freq + ((960.0 if seg == 0 else 720.0) - freq) * (frac - 0.92) / 0.08
        buf[i] = math.sin(2 * math.pi * freq * t) * 0.5
    save_wav("siren_loop.wav", normalize(buf, 0.55), rate)


def rain_loop():
    rate = 22050
    dur = 6.0
    n = int(rate * dur)
    rng = random.Random(9)
    raw = [(rng.random() * 2 - 1) for _ in range(n)]
    buf = lowpass(raw, 0.16)
    buf = lowpass(buf, 0.30)
    # Loop crossfade: fold the tail into the head.
    fade = int(rate * 0.3)
    for i in range(fade):
        k = i / fade
        buf[i] = buf[i] * k + buf[n - fade + i] * (1 - k)
    save_wav("rain_loop.wav", normalize(buf, 0.5), rate)


def city_ambience():
    rate = 22050
    dur = 20.0
    n = int(rate * dur)
    rng = random.Random(12)
    raw = [(rng.random() * 2 - 1) for _ in range(n)]
    buf = lowpass(raw, 0.05)
    buf = [v * 0.5 for v in buf]
    # Distant soft tones (pentatonic), sparse.
    notes = [220.0, 261.63, 293.66, 329.63, 392.0]
    for start_s in (2.0, 6.5, 11.0, 15.5):
        f = notes[rng.randint(0, len(notes) - 1)]
        start = int(start_s * rate)
        length = int(rate * 1.6)
        for j in range(length):
            idx = start + j
            if idx >= n:
                break
            env = math.sin(math.pi * j / length)
            buf[idx] += math.sin(2 * math.pi * f * (j / rate)) * 0.10 * env
    # Faint city hum.
    for i in range(n):
        buf[i] += math.sin(2 * math.pi * 60 * (i / rate)) * 0.03
    save_wav("city_ambience.wav", normalize(buf, 0.5), rate)


def tone(freq, dur, rate=22050, decay=6.0, glide_to=None):
    n = int(rate * dur)
    buf = []
    for i in range(n):
        t = i / rate
        f = freq if glide_to is None else freq + (glide_to - freq) * (i / n)
        env = math.exp(-decay * t)
        buf.append(math.sin(2 * math.pi * f * t) * env)
    return buf


def ui_click():
    save_wav("ui_click.wav", normalize(tone(1400, 0.08, decay=42), 0.5), 22050)


def cash():
    rate = 22050
    a = tone(988, 0.10, rate=rate, decay=16)
    b = tone(1319, 0.30, rate=rate, decay=9)
    buf = a + [0.0] * (int(rate * 0.4) - len(a))
    for i, v in enumerate(b):
        buf[len(a) + i] += v if len(a) + i < len(buf) else 0
    save_wav("cash.wav", normalize(buf, 0.6), rate)


def success():
    rate = 22050
    freqs = [523.25, 659.25, 783.99, 1046.50]
    total = int(rate * 0.8)
    buf = [0.0] * total
    step = int(rate * 0.13)
    for k, f in enumerate(freqs):
        note = tone(f, 0.45, rate=rate, decay=5.0)
        start = k * step
        for i, v in enumerate(note):
            if start + i < total:
                buf[start + i] += v * 0.7
    save_wav("success.wav", normalize(buf, 0.62), rate)


def fail():
    save_wav("fail.wav", normalize(tone(280, 0.5, decay=4.5, glide_to=150), 0.55), 22050)


def punch():
    rate = 22050
    n = int(rate * 0.15)
    rng = random.Random(3)
    raw = [(rng.random() * 2 - 1) for _ in range(n)]
    body = lowpass(raw, 0.35)
    buf = []
    for i in range(n):
        t = i / rate
        env = math.exp(-26 * t)
        thump = math.sin(2 * math.pi * 90 * t) * 0.8
        buf.append((body[i] * 0.7 + thump) * env)
    save_wav("punch.wav", normalize(buf, 0.8), rate)


def step():
    rate = 22050
    n = int(rate * 0.07)
    rng = random.Random(4)
    raw = [(rng.random() * 2 - 1) for _ in range(n)]
    body = lowpass(raw, 0.5)
    buf = [body[i] * math.exp(-40 * (i / rate)) for i in range(n)]
    save_wav("step.wav", normalize(buf, 0.4), rate)


def main():
    menu_music()
    engine_loop()
    siren_loop()
    rain_loop()
    city_ambience()
    ui_click()
    cash()
    success()
    fail()
    punch()
    step()
    total = 0
    for f in sorted(os.listdir(OUT_DIR)):
        total += os.path.getsize(os.path.join(OUT_DIR, f))
    print("audio pack total bytes:", total)


if __name__ == "__main__":
    main()
