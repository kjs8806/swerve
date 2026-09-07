# Swerve Sound Design Pack

Original synthesized sound effects for the Godot 4.3 mobile arcade-racing project. All assets are mono, 44.1 kHz, copyright-safe, and designed to remain audible through phone speakers without clipping.

## Asset map

| File | Trigger | Loop | Suggested volume |
|---|---|---:|---:|
| `engine-idle-loop.ogg` | Gameplay begins while vehicle is stationary or at minimum speed | Yes | -16 dB |
| `engine-drive-loop.ogg` | Normal forward driving | Yes | -13 dB |
| `lane-change-whoosh.wav` | Each accepted left/right lane change | No | -8 dB |
| `coin-pickup.wav` | Coin is collected | No | -5 dB |
| `combo-increment.wav` | Combo multiplier increases | No | -7 dB |
| `collision-impact.wav` | Player collides with traffic or a major obstacle | No | -3 dB |
| `road-hit.wav` | Player hits a pothole, loose tire, or traffic cone | No | -6 dB |
| `turbo-charge.wav` | Gauge reaches its final charge threshold or during a short pre-activation wind-up | No | -8 dB |
| `turbo-activation.wav` | Turbo begins | No | -2 dB |
| `turbo-sustain-loop.ogg` | Turbo remains active | Yes | -12 dB |
| `countdown-warning.wav` | Each final countdown tick | No | -6 dB |
| `ui-tap.wav` | Menu and HUD button press | No | -10 dB |
| `race-start.wav` | Race begins after countdown | No | -3 dB |
| `finish-win.wav` | Goal reached successfully | No | -4 dB |
| `time-up-failure.wav` | Timer reaches zero without success | No | -5 dB |

Suggested levels are starting points relative to Godot's 0 dB master bus. Tune them on a physical Samsung device before release.

## Godot setup

1. Copy the approved files to `godot/assets/audio/`.
2. Use `AudioStreamPlayer` nodes for global UI and race-state sounds. Use `AudioStreamPlayer2D` only if traffic sounds need spatial positioning.
3. Enable looping for the three `*-loop.ogg` imports and disable looping for every WAV.
4. Use separate `Engine`, `SFX`, and `UI` audio buses. Add a limiter to `Master` with a ceiling around -1 dB.
5. Crossfade `engine-idle-loop.ogg` and `engine-drive-loop.ogg` over roughly 150–250 ms instead of stopping one abruptly.
6. When turbo starts, lower the engine bus by roughly 2 dB, play `turbo-activation.wav`, then fade in `turbo-sustain-loop.ogg` over about 100 ms.
7. When turbo ends, fade the sustain loop out over about 150 ms and restore the engine bus.
8. Pool frequently repeated players for coins and UI taps so fast events can overlap without cutting each other off.

## Import guidance

- Keep WAV effects uncompressed in Godot for low-latency playback.
- Keep OGG loops compressed for small APK size.
- Do not enable forced mono conversion; the files are already mono.
- Do not normalize again on import unless device testing demonstrates a consistent level problem.
- Avoid playing more than one collision sound for the same collision event.
- Apply a short cooldown to lane-change and road-hit sounds to prevent noisy repetition.

## Approval notes

These sounds are a first-pass cohesive pack. Final mix decisions require listening on the target Samsung device alongside the actual engine speed, HUD sounds, and turbo visuals. The generation source is included as `generate_sound_pack.py` for reproducible revisions.
