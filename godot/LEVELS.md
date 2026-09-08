# Swerve level progression

Levels unlock sequentially. This gives the difficulty curve a predictable
learning order while keeping replayed cities selectable. Unlock state is saved
in `user://progress.cfg`.

| Level | City | Lighting | Speed start / ramp / max | Time | Finish | Obstacles | Wave interval | Playtest note |
| ---: | --- | --- | --- | ---: | ---: | --- | --- | --- |
| 1 | Sydney | Bright morning | 120 / 1.8 / 220 | 65s | 8,000 | 1 → 1 | 2.10 → 1.45s | Tutorial-like: single blockers, abundant pickups, large time margin. |
| 2 | Rio | Golden afternoon | 130 / 2.0 / 240 | 64s | 9,000 | 1 → 2 | 1.85 → 1.20s | Introduces occasional two-wide reads without sustained pressure. |
| 3 | Paris | Lavender dusk | 140 / 2.2 / 260 | 63s | 10,000 | 1 → 2 | 1.65 → 1.05s | Comfortable, with a clearer need to choose the open side early. |
| 4 | London | Rainy blue hour | 150 / 2.4 / 280 | 62s | 11,000 | 1 → 2 | 1.50 → 0.92s | Moderate rhythm; wet-night contrast makes silhouettes easy to read. |
| 5 | Singapore | Tropical twilight | 160 / 2.6 / 300 | 61s | 12,000 | 1 → 2 | 1.36 → 0.80s | Midpoint test: consistent inputs matter, but recovery remains generous. |
| 6 | New York | Dense night | 170 / 2.8 / 320 | 60s | 13,200 | 1 → 3 | 1.24 → 0.72s | First late-race three-wide waves; open lane remains obvious and reachable. |
| 7 | Dubai | Golden dusk | 180 / 3.0 / 340 | 60s | 14,400 | 1 → 3 | 1.14 → 0.65s | Faster decisions and fewer pickups, with enough race-time margin to recover. |
| 8 | Mumbai | Monsoon night | 190 / 3.2 / 360 | 59s | 15,300 | 2 → 3 | 1.02 → 0.58s | Starts under real pressure; deliberate early lane choice is rewarded. |
| 9 | Hong Kong | Neon night | 200 / 3.5 / 380 | 58s | 16,200 | 2 → 3 | 0.92 → 0.52s | High-speed consistency test with frequent overlapping wave reads. |
| 10 | Tokyo | Intense neon night | 215 / 3.8 / 405 | 58s | 17,600 | 2 → 3 | 0.82 → 0.48s | Skill check: rapid two/three-wide waves, smallest clean-run margin, still passable. |

## Fairness contract

- A wave is capped to the currently available lane count minus one, preserving
  at least one completely unoccupied lane even when waves overlap.
- Runtime wave spacing is clamped to 0.48s. Two lane-change animations plus
  their 90ms input locks require 0.46s, leaving a small additional buffer.
- Obstacles stop spawning when the finish comes into view.
- Every level is finishable without turbo or collision slowdown. Pickup rates
  are extra help, not a hidden completion requirement.

`tools/validate_levels.gd` checks all ten resources and HD textures, integrates
the no-hit finish distance, and simulates 10,000 overlapping waves per level.
The notes above are the intended manual-playtest targets; final touch-device
sign-off should confirm steering feel and visual readability on target hardware.
