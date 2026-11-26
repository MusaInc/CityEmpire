#!/usr/bin/env python3
"""Neighbourhood and shop ambience for WorldState, synthesised from code (no
samples, no licences) like tools/audio/gen_audio.py. Seamless mono loops,
22.05 kHz, 16-bit WAV, into assets/audio/:

  amb_shop      inside a busy shop: low voices, footsteps, a till beep now
                and then, the door chime
  amb_chatter   a street of passers-by: overlapping voices at distance
  amb_harbour   water lapping, gulls, rigging clinks
  amb_park      birdsong over a soft breeze

  python3 tools/audio/gen_ambience.py
"""
import os, wave
import numpy as np

SR = 22050
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'assets/audio')
rng = np.random.default_rng(7)


def lp(x, cutoff):
    a = np.exp(-2.0 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def bp(x, lo, hi):
    return lp(x, hi) - lp(x, lo)


def env_ad(n, a, d):
    t = np.arange(n) / SR
    return np.minimum(t / max(a, 1e-4), 1.0) * np.exp(-np.maximum(t - a, 0) / max(d, 1e-4))


def voices(seconds, talkers, near=1.0):
    """Murmur: band-passed noise shaped like syllables, formant-ish bands."""
    n = int(seconds * SR)
    out = np.zeros(n)
    for _ in range(talkers):
        f0 = rng.uniform(95, 230)
        t = np.arange(n) / SR
        # syllable envelope ~4-6 Hz with pauses between phrases
        syl = np.clip(np.sin(2 * np.pi * rng.uniform(3.6, 5.8) * t + rng.uniform(0, 6)), 0, 1) ** 1.5
        phrase = (np.sin(2 * np.pi * rng.uniform(0.15, 0.35) * t + rng.uniform(0, 6)) > -0.3).astype(float)
        phrase = lp(phrase, 3.0)
        buzz = np.sign(np.sin(2 * np.pi * f0 * t * (1 + 0.04 * np.sin(2 * np.pi * 0.7 * t)))) * 0.3 + rng.normal(0, 1, n) * 0.7
        v = bp(buzz, 300, 1100) * 0.7 + bp(buzz, 1500, 2600) * 0.25
        out += v * syl * phrase * rng.uniform(0.5, 1.0)
    return lp(out, 2600 if near > 0.5 else 1400) / max(1, talkers ** 0.5)


def beep(freq, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    return np.sin(2 * np.pi * freq * t) * env_ad(n, 0.003, dur * 0.4)


def place(out, clip, at, gain):
    i = int(at * SR)
    j = min(len(out), i + len(clip))
    out[i:j] += clip[: j - i] * gain


def loopify(x, fade=1.0):
    """Crossfade the tail into the head so the loop is seamless."""
    f = int(fade * SR)
    head = x[:f].copy()
    tail = x[-f:]
    w = np.linspace(0, 1, f)
    x = x[:-f].copy()
    x[:f] = head * w + tail * (1 - w)
    return x


def write(name, x, gain=0.8):
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    path = os.path.join(OUT, name + '.wav')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print('AMB', path, '%.1fs' % (len(x) / SR))


def shop():
    s = 12.0
    x = voices(s + 1, 5, near=1.0) * 0.7
    x += lp(rng.normal(0, 1, len(x)), 400) * 0.08                   # room tone
    for _ in range(14):                                               # footsteps
        place(x, lp(rng.normal(0, 1, 800), 900) * env_ad(800, 0.002, 0.03), rng.uniform(0, s), 0.35)
    for at in rng.uniform(0.5, s - 1, 4):                             # till beeps
        place(x, beep(2950, 0.09), at, 0.35)
        place(x, beep(2950, 0.09), at + 0.16, 0.25)
    place(x, beep(1318.5, 0.35) + 0.6 * np.pad(beep(1046.5, 0.45), (int(0.18 * SR), 0))[: int(0.35 * SR)], rng.uniform(2, s - 2), 0.3)
    return loopify(x)


def chatter():
    s = 14.0
    x = voices(s + 1, 9, near=0.3) * 0.8
    x += lp(rng.normal(0, 1, len(x)), 250) * 0.12
    for _ in range(26):
        place(x, lp(rng.normal(0, 1, 700), 1100) * env_ad(700, 0.002, 0.025), rng.uniform(0, s), 0.22)
    return loopify(x)


def harbour():
    s = 16.0
    n = int((s + 1) * SR)
    t = np.arange(n) / SR
    water = lp(rng.normal(0, 1, n), 700) * (0.55 + 0.45 * np.sin(2 * np.pi * 0.22 * t) ** 2)
    x = water * 0.8
    for at in rng.uniform(0.5, s - 2, 5):                             # gulls: falling cries
        d = rng.uniform(0.35, 0.6)
        m = int(d * SR)
        tt = np.arange(m) / SR
        f = 1900 - 900 * tt / d + 120 * np.sin(2 * np.pi * 9 * tt)
        cry = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(m, 0.04, d * 0.5)
        place(x, cry, at, rng.uniform(0.15, 0.3))
    for at in rng.uniform(0, s, 7):                                   # rigging clinks
        place(x, beep(rng.uniform(1700, 2400), 0.25) * 0.6, at, 0.12)
    return loopify(x)


def park():
    s = 14.0
    n = int((s + 1) * SR)
    x = lp(rng.normal(0, 1, n), 500) * 0.25                           # breeze in leaves
    for _ in range(18):                                               # chirps / short trills
        notes = rng.integers(2, 6)
        at = rng.uniform(0, s - 1)
        base = rng.uniform(2600, 4200)
        for k in range(notes):
            d = rng.uniform(0.05, 0.12)
            m = int(d * SR)
            tt = np.arange(m) / SR
            f = base * (1 + rng.uniform(-0.15, 0.15)) + 600 * np.sin(2 * np.pi * rng.uniform(15, 30) * tt)
            ch = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(m, 0.005, d * 0.5)
            place(x, ch, at + k * d * 1.2, rng.uniform(0.15, 0.3))
    return loopify(x)


if __name__ == '__main__':
    write('amb_shop', shop(), 0.7)
    write('amb_chatter', chatter(), 0.7)
    write('amb_harbour', harbour(), 0.75)
    write('amb_park', park(), 0.6)
