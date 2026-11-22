#!/usr/bin/env python3
"""Synthesise the Satisfying TD v2.0 sound bank (section 15.2).

Every tonal sound uses the C major pentatonic palette so overlapping sounds never clash.
Writes mono OGG files (3-5 variations each) into game/assets/sfx/ and two music loops into
game/assets/music/. Needs numpy and ffmpeg with libvorbis.

    python3 game/tools/sfx/make_sfx.py
"""
import os
import subprocess
import sys
import tempfile
import wave
import zlib

import numpy as np

SR = 22050
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SFX_DIR = os.path.join(ROOT, "assets", "sfx")
MUSIC_DIR = os.path.join(ROOT, "assets", "music")
PENTA = [0, 2, 4, 7, 9]  # C D E G A


def note(n):
    """Frequency of the n-th pentatonic step above C3 (n may be negative)."""
    octave, step = divmod(n, 5)
    semis = 12 * octave + PENTA[step]
    return 130.81 * 2 ** (semis / 12)


def t(dur):
    return np.arange(int(SR * dur)) / SR


def env(dur, a=0.005, d=0.2, curve=4.0):
    x = t(dur)
    e = np.minimum(1.0, x / max(a, 1e-4)) * np.exp(-np.maximum(0, x - a) * curve / max(d, 1e-4))
    return e


def sine(f, dur, f_end=None):
    x = t(dur)
    if f_end is None:
        return np.sin(2 * np.pi * f * x)
    fr = np.geomspace(f, f_end, len(x))
    return np.sin(2 * np.pi * np.cumsum(fr) / SR)


def noise(dur, rng):
    return rng.uniform(-1, 1, int(SR * dur))


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def pad(x, before=0.0):
    return np.concatenate([np.zeros(int(SR * before)), x])


def finish(x, gain=0.8):
    peak = np.max(np.abs(x)) or 1.0
    x = x / peak * gain
    fade = min(len(x), int(SR * 0.01))
    x[-fade:] *= np.linspace(1, 0, fade)
    return x


def write(path, x):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wpath = tmp.name
    with wave.open(wpath, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", wpath, "-c:a", "libvorbis", "-q:a", "3", path], check=True)
    os.remove(wpath)


# ----------------------------------------------------------------------------- sounds
def s_place(rng, v):  # lock click + thud
    thud = sine(90 + 10 * v, 0.18, 45) * env(0.18, 0.002, 0.08)
    click = sine(note(10 + v % 3), 0.08) * env(0.08, 0.001, 0.03) * 0.5
    dust = lowpass(noise(0.15, rng), 900) * env(0.15, 0.005, 0.06) * 0.6
    return mix(thud, click, dust)


def s_activate(rng, v):  # two-note chord, rising
    a = sine(note(7 + v), 0.6) * env(0.6, 0.01, 0.35)
    b = pad(sine(note(9 + v), 0.6) * env(0.6, 0.01, 0.35), 0.09)
    sh = highpass(noise(0.3, rng), 3000) * env(0.3, 0.05, 0.1) * 0.15
    return mix(a, b * 0.8, sh)


def s_gun(rng, v):
    crack = highpass(noise(0.12, rng), 1500) * env(0.12, 0.001, 0.025)
    body = sine(180 - 15 * v, 0.12, 70) * env(0.12, 0.001, 0.04)
    return mix(crack * 0.7, body)


def s_mg(rng, v):
    crack = highpass(noise(0.06, rng), 2500) * env(0.06, 0.001, 0.012)
    body = sine(240 + 20 * v, 0.06, 120) * env(0.06, 0.001, 0.02)
    return mix(crack * 0.6, body * 0.7)


def s_rifle(rng, v):
    crack = highpass(noise(0.4, rng), 900) * env(0.4, 0.001, 0.05)
    boom = sine(110, 0.4, 40) * env(0.4, 0.001, 0.15)
    tail = lowpass(noise(0.4, rng), 600) * env(0.4, 0.02, 0.25) * 0.3
    return mix(crack, boom, tail)


def s_mortar(rng, v):
    thump = sine(70 + 8 * v, 0.3, 35) * env(0.3, 0.002, 0.12)
    puff = lowpass(noise(0.3, rng), 1200) * env(0.3, 0.003, 0.1) * 0.6
    return mix(thump, puff)


def s_boom(rng, v):
    low = sine(60 - 5 * v, 0.9, 25) * env(0.9, 0.003, 0.35)
    rumble = lowpass(noise(0.9, rng), 300 + 60 * v) * env(0.9, 0.01, 0.4)
    crack = highpass(noise(0.15, rng), 2000) * env(0.15, 0.001, 0.04) * 0.4
    return mix(low, rumble * 1.4, crack)


def s_missile(rng, v):
    x = t(0.6)
    sweep = highpass(noise(0.6, rng), 800) * np.sin(np.pi * x / 0.6) ** 2 * 0.6
    tone = sine(500 + 50 * v, 0.6, 250) * env(0.6, 0.05, 0.3) * 0.2
    return mix(sweep, tone)


def s_laser(rng, v):
    x = t(0.25)
    f = note(12 + v)
    zap = np.sin(2 * np.pi * f * x + 3 * np.sin(2 * np.pi * 37 * x)) * env(0.25, 0.005, 0.1)
    return zap


def s_pulsar(rng, v):
    thr = sine(note(3 + v), 0.4, note(1 + v)) * env(0.4, 0.01, 0.2)
    ring = sine(note(13 + v), 0.4) * env(0.4, 0.01, 0.15) * 0.3
    return mix(thr, ring)


def s_lightning(rng, v):
    crackle = highpass(noise(0.35, rng), 2500) * (rng.uniform(0, 1, int(SR * 0.35)) > 0.7) * env(0.35, 0.001, 0.12)
    buzz = np.sign(sine(110 + 30 * v, 0.35)) * env(0.35, 0.002, 0.1) * 0.25
    return mix(crackle, buzz)


def s_efield(rng, v):
    x = t(0.5)
    hum = sine(note(-2 + v), 0.5) * (0.5 + 0.5 * np.sin(2 * np.pi * 12 * x)) * env(0.5, 0.05, 0.25)
    return hum


def s_freeze(rng, v):
    hiss = highpass(noise(0.5, rng), 4000) * env(0.5, 0.03, 0.25)
    chime = sine(note(15 + v), 0.5) * env(0.5, 0.005, 0.2) * 0.2
    return mix(hiss * 0.7, chime)


def s_flame(rng, v):
    roar = lowpass(noise(0.5, rng), 700 + 100 * v) * env(0.5, 0.04, 0.3)
    crackle = highpass(noise(0.5, rng), 3000) * (rng.uniform(0, 1, int(SR * 0.5)) > 0.95) * 0.5
    return mix(roar, crackle)


def s_splat(rng, v):  # acid / goo landing
    blob = sine(220 + 30 * v, 0.25, 90) * env(0.25, 0.002, 0.07)
    wet = lowpass(noise(0.25, rng), 1600) * env(0.25, 0.002, 0.08) * 0.7
    return mix(blob, wet)


def s_spore(rng, v):
    puff = lowpass(noise(0.35, rng), 1000) * env(0.35, 0.03, 0.15)
    plip = sine(note(8 + v), 0.15) * env(0.15, 0.002, 0.05) * 0.3
    return mix(puff, plip)


def s_casing(rng, v):  # brass tinkle
    f = 2600 + 300 * v
    a = sine(f, 0.18) * env(0.18, 0.001, 0.05)
    b = pad(sine(f * 1.37, 0.12) * env(0.12, 0.001, 0.04) * 0.6, 0.05 + 0.02 * v)
    return mix(a, b)


def s_kill(rng, v):  # gummy splat with a pentatonic blip
    splat = lowpass(noise(0.3, rng), 1400) * env(0.3, 0.002, 0.08)
    pop = sine(note(9 + v), 0.2, note(5 + v)) * env(0.2, 0.002, 0.07) * 0.6
    return mix(splat, pop)


def s_kill_big(rng, v):
    splat = lowpass(noise(0.6, rng), 900) * env(0.6, 0.003, 0.2)
    thud = sine(80, 0.6, 40) * env(0.6, 0.003, 0.2)
    drops = mix(*(pad(sine(note(10 + k), 0.08) * env(0.08, 0.001, 0.03) * 0.25, 0.15 + 0.08 * k) for k in range(3)))
    return mix(splat, thud, drops)


def s_combo(rng, v):  # rising arpeggio, v = combo tier 0..4
    parts = []
    for k in range(3 + v):
        parts.append(pad(sine(note(7 + k), 0.25) * env(0.25, 0.003, 0.12) * 0.6, 0.06 * k))
    return mix(*parts)


def s_leak(rng, v):  # alarm thud
    thud = sine(55, 0.5, 35) * env(0.5, 0.002, 0.2)
    bell = mix(sine(note(2), 0.6), sine(note(2) * 2.01, 0.6) * 0.5) * env(0.6, 0.002, 0.25) * 0.4
    return mix(thud, bell)


def s_wave(rng, v):  # horn
    x = t(1.2)
    f = note(0)
    horn = (np.sin(2 * np.pi * f * x) + 0.5 * np.sin(4 * np.pi * f * x) + 0.25 * np.sin(6 * np.pi * f * x))
    return lowpass(horn * env(1.2, 0.15, 0.7), 1800)


def s_click(rng, v):
    return sine(note(12 + v), 0.05) * env(0.05, 0.001, 0.015)


def s_thunder(rng, v):  # road strike
    crack = highpass(noise(0.2, rng), 1500) * env(0.2, 0.001, 0.05)
    roll = lowpass(noise(1.4, rng), 250) * env(1.4, 0.05, 0.6) * 1.5
    return mix(crack, roll)


def s_chime(rng, v):  # ore / essence gain
    return mix(*(pad(sine(note(10 + k + v), 0.4) * env(0.4, 0.002, 0.2) * 0.5, 0.05 * k) for k in range(2)))


def s_reject(rng, v):
    return mix(sine(note(-1), 0.15), sine(note(-1) * 1.06, 0.15)) * env(0.15, 0.002, 0.06) * 0.5


def s_undo(rng, v):
    return sine(note(9), 0.2, note(4)) * env(0.2, 0.005, 0.08) * 0.6


# pre-built for later milestones (economy, cards, metronomes, artillery)
def s_pop_ripe(rng, v):
    thump = sine(90, 0.35, 50) * env(0.35, 0.002, 0.1)
    pop = sine(note(12 + v), 0.08, note(7 + v)) * env(0.08, 0.001, 0.03)
    drops = mix(*(pad(sine(note(11 + k + v), 0.06) * env(0.06, 0.001, 0.02) * 0.4, 0.1 + 0.07 * k) for k in range(4)))
    wet = lowpass(noise(0.3, rng), 2000) * env(0.3, 0.002, 0.06) * 0.6
    return mix(thump, pop, drops, wet)


def s_pop_dull(rng, v):
    return mix(sine(note(8 + v), 0.1, note(5 + v)) * env(0.1, 0.001, 0.03), lowpass(noise(0.1, rng), 1000) * env(0.1, 0.001, 0.03) * 0.5)


def s_tap(rng, v):
    return mix(highpass(noise(0.06, rng), 2000) * env(0.06, 0.001, 0.01), sine(400, 0.06) * env(0.06, 0.001, 0.015) * 0.5)


def s_chop(rng, v):
    return mix(lowpass(noise(0.15, rng), 1500 + 300 * v) * env(0.15, 0.001, 0.04), sine(150, 0.15, 80) * env(0.15, 0.001, 0.05))


def s_card_flip(rng, v):
    return highpass(noise(0.08, rng), 2500) * env(0.08, 0.001, 0.02)


def s_card_shuffle(rng, v):
    parts = [pad(highpass(noise(0.03, rng), 3000) * env(0.03, 0.001, 0.008) * 0.6, 0.025 * k) for k in range(24)]
    return mix(*parts)


def s_tick(rng, v):  # metronome woodblock, v raises pitch
    return mix(sine(note(10 + v), 0.08) * env(0.08, 0.0005, 0.015), highpass(noise(0.03, rng), 2000) * env(0.03, 0.0005, 0.005) * 0.3)


def s_whistle(rng, v):  # howitzer shell descending
    return sine(1800 - 100 * v, 1.0, 500) * env(1.0, 0.3, 0.9) * 0.4


def s_jet(rng, v):
    x = t(1.5)
    return highpass(noise(1.5, rng), 600) * np.sin(np.pi * x / 1.5) ** 3


def s_orbital(rng, v):
    x = t(2.0)
    charge = sine(80, 2.0, 600) * (x / 2.0) ** 2 * 0.4
    roar = pad(lowpass(noise(1.2, rng), 500) * env(1.2, 0.01, 0.6), 1.2)
    return mix(charge, roar)


def s_bell(rng, v):
    f = note(5 + v)
    return mix(sine(f, 1.5), sine(f * 2.76, 1.5) * 0.4, sine(f * 5.4, 1.5) * 0.2) * env(1.5, 0.002, 0.8)


SOUNDS = {
    "place": (s_place, 4), "activate": (s_activate, 3), "gun": (s_gun, 4), "mg": (s_mg, 4),
    "rifle": (s_rifle, 3), "mortar": (s_mortar, 3), "boom": (s_boom, 4), "missile": (s_missile, 3),
    "laser": (s_laser, 3), "pulsar": (s_pulsar, 3), "lightning": (s_lightning, 4), "efield": (s_efield, 3),
    "freeze": (s_freeze, 3), "flame": (s_flame, 3), "splat": (s_splat, 4), "spore": (s_spore, 3),
    "casing": (s_casing, 5), "kill": (s_kill, 5), "kill_big": (s_kill_big, 3), "combo": (s_combo, 5),
    "leak": (s_leak, 3), "wave": (s_wave, 3), "click": (s_click, 3), "thunder": (s_thunder, 4),
    "chime": (s_chime, 3), "reject": (s_reject, 3), "undo": (s_undo, 3),
    "pop_ripe": (s_pop_ripe, 5), "pop_dull": (s_pop_dull, 4), "tap": (s_tap, 3), "chop": (s_chop, 3),
    "card_flip": (s_card_flip, 3), "card_shuffle": (s_card_shuffle, 3), "tick": (s_tick, 5),
    "whistle": (s_whistle, 3), "jet": (s_jet, 3), "orbital": (s_orbital, 3), "bell": (s_bell, 3),
}


def music_pad(rng):
    """Calm ambient pad: a slow 4-chord pentatonic loop (16 s)."""
    dur = 16.0
    x = t(dur)
    out = np.zeros(len(x))
    chords = [[0, 2, 4], [-1, 1, 3], [-2, 0, 2], [-1, 1, 4]]
    for i, ch in enumerate(chords):
        seg = (x >= i * 4) & (x < (i + 1) * 4 + 0.6)
        local = x - i * 4
        e = np.clip(local / 1.2, 0, 1) * np.clip((4.6 - local) / 1.2, 0, 1)
        for n in ch:
            f = note(n + 5)
            out += seg * e * (np.sin(2 * np.pi * f * x) + 0.3 * np.sin(2 * np.pi * f * 2.003 * x)) * 0.2
    return lowpass(out, 1400)


def music_drums(rng):
    """Wave percussion loop at 96 bpm (8 beats = 5 s)."""
    beat = 60 / 96
    dur = beat * 8
    out = np.zeros(int(SR * dur))
    for k in range(8):
        at = int(SR * k * beat)
        kick = sine(70, 0.3, 40) * env(0.3, 0.002, 0.1)
        if k % 2 == 0:
            out[at: at + len(kick)] += kick
        else:
            sn = lowpass(noise(0.2, rng), 3000) * env(0.2, 0.001, 0.05) * 0.5
            out[at: at + len(sn)] += sn
        hh = highpass(noise(0.05, rng), 6000) * env(0.05, 0.001, 0.01) * 0.25
        h2 = at + int(SR * beat / 2)
        out[h2: h2 + len(hh)] += hh[: max(0, len(out) - h2)]
    return out


def main():
    only = set(sys.argv[1:])
    for name, (fn, n) in SOUNDS.items():
        if only and name not in only:
            continue
        for v in range(n):
            rng = np.random.default_rng(zlib.crc32(f"{name}{v}".encode()))
            write(os.path.join(SFX_DIR, f"{name}_{v}.ogg"), finish(fn(rng, v)))
        print(f"{name}: {n}")
    if not only or "music" in only:
        rng = np.random.default_rng(7)
        write(os.path.join(MUSIC_DIR, "calm_pad.ogg"), finish(music_pad(rng), 0.6))
        write(os.path.join(MUSIC_DIR, "wave_drums.ogg"), finish(music_drums(rng), 0.6))
        print("music: 2")


if __name__ == "__main__":
    main()
