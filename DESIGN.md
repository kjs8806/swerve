# Swerve — Design Notes

## GAME_VISION
Player fantasy: weaving through dense traffic at speed, the tension of a
close call, the rush of a chained dodge. A 5-lane, top-down/perspective
arcade racer built to replicate a specific reference game (see prompt
video/screenshot): reach the finish line within a 60-second timer while
dodging traffic, chaining near-misses for speed boosts, and banking coins
to trigger an invincible turbo burst.

Target player: casual mobile arcade racer fans (Traffic Racer / Racing
Fever lineage). As a 1:1 replica this has no differentiation of its own —
it exists to nail the *feel* of the reference before any original spin is
layered on.

## CORE_LOOP
Swerve (avoid/graze traffic) → speed changes (penalty or boost) → bank
coins → fill turbo gauge → turbo burst (fast + invincible) → repeat →
cross finish line before the 60s clock runs out.

- **10s**: react to the first few obstacles, learn lane-swerve input.
- **1 min**: a full race — dodge, chain near-misses, trigger turbo, win
  or lose against the clock.
- Session length is intentionally ~1 race; this MVP has no meta-game yet
  (see LATER below).

## Fun Hypothesis
We believe players will enjoy this because avoiding traffic at
increasing speed under a hard timer is inherently tense, and the
near-miss-boost mechanic rewards *skillful* dodging (staying close,
not overcautious) rather than just lane-camping in a safe lane.

## MVP Scope (what's built)
**CORE** — implemented in `web/`:
- 5-lane perspective road, player fixed near the bottom, traffic
  scrolling toward the player.
- Swerve left/right (on-screen buttons + arrow keys), one lane per
  input, clamped to the 5 lanes.
- Collision with an obstacle → hard speed penalty that recovers over
  ~1.7s (tuned so repeated crashes can cost you the race).
- Near-miss: swerving out of a lane while an obstacle is in the "danger
  zone" right behind you grants a temporary speed boost and increments
  a combo counter (resets on collision).
- Coins on the road fill a turbo gauge; full gauge auto-triggers Turbo
  Mode (~1.9x speed, invincible to collisions) that drains over ~4
  seconds.
- 60-second countdown; a fixed finish distance must be covered before
  time runs out. Difficulty (obstacle density/frequency, base speed)
  ramps up over the run.
- Progress bar shows the full race at a glance: a START label, a car
  icon marking the player's own position by distance traveled, and a
  checkered FINISH icon at the end.
- A checkered finish-line tape renders in the 3D scene itself as the
  player closes in on the finish distance, and again as they cross it.
- Turbo Mode is unmistakable when active: a persistent pulsing "TURBO!"
  banner, radiating speed-line streaks, a screen-edge vignette pulse,
  and a flame trail behind the player's car — on top of the color
  change and gauge fill it already had.
- Win/lose screen with run stats, restart.

**REJECTED for this MVP** (present in the reference footage but not in
the user's mechanic description — flagged rather than silently added):
- Manual "Turbo x4" consumable item separate from the gauge-triggered
  turbo.
- A "Jump" mechanic/button.
Both are cheap to add later once the core swerve/turbo loop is proven
fun; adding them now would be scope creep beyond what was asked for.

**LATER** (meta-game, not needed to test the core hypothesis):
- Persistent currency/garage, car unlocks, cosmetics.
- Multiple race courses/finish distances, career/level progression.
- Real art (this build uses placeholder canvas-drawn shapes, not
  sprites) and audio.
- Analytics wiring, soft-launch gates.

## Tech Decision
Built first as an HTML5 Canvas + vanilla JS prototype
(`web/index.html`, `web/style.css`, `web/game.js`) rather than Godot,
specifically to validate the core loop cheaply and interactively before
committing to the target engine. Godot (the intended shipping engine)
is the next step once the loop is confirmed fun — see ROADMAP.

## Balance Notes (tunable constants live at the top of `game.js`)
Validated via scripted playthroughs (not just eyeballing):
- Skilled reactive play: finishes around ~49s (comfortable margin).
- Never touching the controls: **loses**.
- Deliberately steering into every obstacle: **loses**.
Only genuinely competent dodging wins — doing nothing and doing badly
both fail, which is a sharper skill curve than the first pass (see
DECISION_LOG: an earlier reading of "bad play barely survives" turned
out to be an artifact of the stuck-obstacle bug, not real balance).
Initial tuning only — needs real playtesters, not just scripted bots.

## ROADMAP
1. **Prototype** — HTML5 Canvas core loop, validated by scripted play
   (done).
2. **Playtest** — real people played the web build and confirmed the
   core loop is fun (done — this is the gate that greenlit step 3).
3. **Godot rebuild (this)** — ported the validated loop into Godot (the
   intended shipping engine) under `godot/`. Same constants, same
   logic, verified headlessly (Xvfb + `--rendering-driver opengl3`) via
   a scripted test harness exercising collision, near-miss boost, coin
   → turbo, keyboard input, on-screen button input, and win → restart —
   the same rigor as the web prototype's Playwright tests, not just
   "it opened without errors." Still needs an actual device pass (real
   touch input feel, portrait/landscape, performance on a normal
   phone) — the engine swap doesn't validate those on its own.
4. **Vertical slice** — real art pass, SFX, one polished course.
5. **MVP** — minimum meta-game (currency from races, one car unlock) to
   test D1 return motivation.
6. **Soft launch gates** — tutorial completion, D1 retention, average
   time-to-finish distribution.

## DECISION_LOG
- Chose HTML5 Canvas over Godot for the first prototype: this sandbox
  has no Godot editor/runtime, and validating the actual gameplay feel
  now outweighs building in the final engine before we know the loop
  works. Godot remains the target for the real build.
- Cut the manual turbo-item and jump mechanics from MVP scope: not
  part of the user's mechanic description, and the core swerve/turbo
  loop can be validated without them.
- Retuned collision penalty (from a mild 0.45x/1.1s slowdown to a
  harsher 0.22x/1.7s) after scripted playtests showed even
  deliberately-bad play won with 7+ seconds to spare — the timer needs
  to feel like a real constraint, not a formality.
- Fixed a real bug (user-reported: obstacle cars appeared stuck at the
  bottom of the screen after being passed): once an obstacle was
  marked `resolved` (hit or safely passed), the update loop's
  `if (o.resolved) continue` skipped its position update on every
  later frame too, not just its collision/dodge logic — so it froze in
  place forever and never crossed the removal threshold. Fixed by
  always advancing position first, and only skipping the *logic* once
  resolved. Also extended how far a passed car travels before removal
  (off the bottom of the screen, not just past the player's row) and
  folded the player into the same depth-sorted draw pass as traffic,
  so a just-passed car correctly renders in front of the player as it
  exits instead of being hidden behind it.
  Side effect worth noting: re-running the balance scripts after this
  fix changed the "deliberately bad play" outcome from a narrow win
  (~59.6s) to a loss — the earlier number was measured while stuck
  obstacles were quietly cluttering the road, which isn't the real
  game. The corrected balance (above) is the one to trust.
- Removed the rival marker/pace entirely — not needed.
- Briefly tried auto-starting the race on page load instead of
  requiring a "TAP TO START" tap, then reverted at the user's request:
  the manual start screen is back. Bound both `pointerdown` and
  `click` on the start/restart button either way, since
  `pointerdown`-only handling can be unreliable in some mobile
  browsers/webviews — that hardening stays regardless of which start
  flow is active.
- Ported the validated loop into Godot (`godot/`) once real playtesters
  confirmed the web build was fun. Kept the same architecture as the
  web version on purpose: one script (`Race.gd`) owns state, update,
  and rendering via a single `_draw()` pass, mirroring the Canvas
  approach rather than switching to per-object Sprite2D nodes — lower
  risk for a straight port, revisit when real art replaces the
  procedural shapes. Caught and fixed three real bugs during headless
  verification (Xvfb + `--rendering-driver opengl3`, no GPU/Vulkan
  available in this sandbox), not just visual guesses:
  - `Control.modulate` multiplies with a node's existing theme color
    rather than replacing it, so recoloring the combo popup via
    `modulate` turned "HIT!" (meant to be red) into a muddy olive
    green, since it was multiplying with the scene's default green.
    Fixed by using `add_theme_color_override("font_color", ...)`
    instead, and reserving `modulate` for brightness/alpha pulsing only.
  - The "TURBO!" banner was functionally showing but unreadable: white
    text (well, orange) is invisible against a similarly-colored
    background. Same failure mode as the earlier web turbo-visibility
    fix, in a new engine — added a black outline (`font_outline_color`
    + `outline_size`) the same way the finish-tape "FINISH" text needed
    one once I noticed it disappeared against the tape's white squares
    (`draw_string_outline` before `draw_string`, mirroring the
    Canvas version's stroke-then-fill).
  - Godot `Label`s don't clip overflowing text by default, so a
    plain-text player-position marker on the progress bar rendered
    wider than its box and overlapped the "FINISH" label. Replaced the
    text marker with a small colored `ColorRect` instead of fighting
    text sizing.
