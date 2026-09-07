#!/usr/bin/env python3
"""Generate an original arcade-racing sound pack for Swerve."""

from pathlib import Path
import math
import wave

import numpy as np

SR = 44100
OUT = Path(__file__).resolve().parent
RNG = np.random.default_rng(8806)


def tone(freq, duration, phase=0.0):
    t = np.arange(round(duration * SR)) / SR
    return np.sin(2 * np.pi * freq * t + phase)


def sweep(start, end, duration, phase=0.0):
    n = round(duration * SR)
    t = np.arange(n) / SR
    k = (end - start) / duration
    return np.sin(2 * np.pi * (start * t + 0.5 * k * t * t) + phase)


def noise(duration):
    return RNG.uniform(-1.0, 1.0, round(duration * SR))


def periodic_noise(duration, base_hz=10, count=40):
    """Periodic noise-like signal whose harmonics close exactly at loop edge."""
    n = round(duration * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    fundamental = 1.0 / duration
    first = max(1, round(base_hz / fundamental))
    for h in range(first, first + count):
        out += RNG.uniform(0.2, 1.0) * np.sin(
            2 * np.pi * h * fundamental * t + RNG.uniform(0, 2 * np.pi)
        ) / math.sqrt(h)
    return out


def adsr(x, attack=0.01, release=0.08):
    env = np.ones(len(x))
    a = min(len(x), round(attack * SR))
    r = min(len(x), round(release * SR))
    if a:
        env[:a] = np.linspace(0, 1, a, endpoint=False)
    if r:
        env[-r:] = np.linspace(1, 0, r)
    return x * env


def echo(x, delay=0.07, decay=0.3, repeats=2):
    out = np.zeros(len(x) + round(delay * SR) * repeats)
    out[:len(x)] += x
    step = round(delay * SR)
    for i in range(1, repeats + 1):
        out[i * step:i * step + len(x)] += x * decay ** i
    return out


def lowpass(x, cutoff=2500):
    # Stable one-pole filter; enough to keep synthesized transients mobile-friendly.
    alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff / SR)
    out = np.empty_like(x)
    value = 0.0
    for i, sample in enumerate(x):
        value += alpha * (sample - value)
        out[i] = value
    return out


def normalize(x, peak=0.89):
    x = np.nan_to_num(x)
    maximum = np.max(np.abs(x)) or 1.0
    return x * (peak / maximum)


def write_wav(name, x, peak=0.89):
    x = normalize(x, peak)
    pcm = np.round(x * 32767).astype('<i2')
    with wave.open(str(OUT / name), 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(pcm.tobytes())


def engine_loop(name, fundamental, duration, brightness):
    # Frequencies are integer multiples of the one-second loop fundamental.
    t = np.arange(round(duration * SR)) / SR
    pulse = (
        0.62 * np.sin(2 * np.pi * fundamental * t)
        + 0.29 * np.sin(2 * np.pi * fundamental * 2 * t + 0.4)
        + 0.16 * np.sin(2 * np.pi * fundamental * 3 * t + 0.9)
        + 0.08 * np.sin(2 * np.pi * fundamental * 5 * t)
    )
    body = np.tanh(pulse * 1.55)
    texture = periodic_noise(duration, base_hz=fundamental * 2, count=55)
    flutter = 0.93 + 0.07 * np.sin(2 * np.pi * 6 * t)
    write_wav(name, lowpass((body * 0.88 + texture * brightness) * flutter, 3800))


def main():
    OUT.mkdir(parents=True, exist_ok=True)

    # Seamless source loops (converted to OGG by the build command).
    engine_loop('_engine_idle_source.wav', 46, 1.0, 0.28)
    engine_loop('_engine_drive_source.wav', 78, 1.0, 0.34)

    t = np.arange(SR) / SR
    turbo_loop = (
        0.48 * periodic_noise(1.0, 90, 90)
        + 0.30 * np.sin(2 * np.pi * 320 * t)
        + 0.16 * np.sin(2 * np.pi * 640 * t + 0.5)
    ) * (0.94 + 0.06 * np.sin(2 * np.pi * 8 * t))
    write_wav('_turbo_sustain_source.wav', lowpass(turbo_loop, 7000), 0.82)

    # One-shot effects.
    x = adsr(0.65 * sweep(700, 150, 0.24) + 0.25 * noise(0.24), 0.003, 0.09)
    write_wav('lane-change-whoosh.wav', lowpass(x, 5200), 0.82)

    d = 0.34
    x = adsr(0.70 * tone(1046.5, d) + 0.42 * tone(1568, d), 0.004, 0.20)
    write_wav('coin-pickup.wav', echo(x, 0.055, 0.25, 2), 0.88)

    d = 0.42
    x = np.zeros(round(d * SR))
    for start, freq in [(0.00, 659.25), (0.09, 830.61), (0.18, 1046.5)]:
        note = adsr(tone(freq, 0.17), 0.004, 0.12)
        i = round(start * SR)
        x[i:i + len(note)] += note
    write_wav('combo-increment.wav', x, 0.88)

    d = 0.52
    impact = adsr(0.72 * noise(d) + 0.70 * sweep(135, 42, d), 0.001, 0.31)
    write_wav('collision-impact.wav', lowpass(np.tanh(impact * 1.8), 2800), 0.92)

    d = 0.44
    road = adsr(0.72 * lowpass(noise(d), 1500) + 0.46 * sweep(105, 58, d), 0.001, 0.25)
    write_wav('road-hit.wav', road, 0.88)

    d = 1.18
    charge = adsr(0.52 * sweep(180, 1450, d) + 0.23 * sweep(360, 2900, d) + 0.12 * noise(d), 0.015, 0.07)
    write_wav('turbo-charge.wav', lowpass(charge, 7000), 0.88)

    d = 0.82
    activation = adsr(0.65 * sweep(220, 1120, d) + 0.38 * sweep(700, 2400, d) + 0.20 * noise(d), 0.004, 0.22)
    write_wav('turbo-activation.wav', lowpass(np.tanh(activation * 1.3), 8000), 0.91)

    d = 0.30
    warning = adsr(0.77 * tone(880, d) + 0.26 * tone(1760, d), 0.003, 0.14)
    write_wav('countdown-warning.wav', warning, 0.84)

    d = 0.13
    tap = adsr(0.75 * sweep(1300, 620, d) + 0.14 * noise(d), 0.002, 0.065)
    write_wav('ui-tap.wav', lowpass(tap, 6000), 0.78)

    d = 1.20
    race = np.zeros(round(d * SR))
    for start, freq, length in [(0.0, 440, 0.15), (0.25, 554.37, 0.15), (0.50, 659.25, 0.60)]:
        note = adsr(tone(freq, length) + 0.30 * tone(freq * 2, length), 0.004, min(0.25, length * 0.45))
        i = round(start * SR)
        race[i:i + len(note)] += note
    write_wav('race-start.wav', race, 0.90)

    d = 1.75
    finish = np.zeros(round(d * SR))
    for start, freq, length in [(0.0, 523.25, 0.42), (0.18, 659.25, 0.42), (0.36, 783.99, 0.42), (0.58, 1046.5, 0.92)]:
        note = adsr(tone(freq, length) + 0.22 * tone(freq * 2, length), 0.008, min(0.42, length * 0.55))
        i = round(start * SR)
        finish[i:i + len(note)] += note
    write_wav('finish-win.wav', echo(finish, 0.09, 0.16, 2), 0.90)

    d = 1.35
    fail = adsr(0.67 * sweep(440, 110, d) + 0.25 * sweep(330, 82.5, d), 0.01, 0.48)
    write_wav('time-up-failure.wav', fail, 0.87)


if __name__ == '__main__':
    main()
