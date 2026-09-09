# Swerve (Godot)

The real-engine port of the validated web prototype (see the repo root
`DESIGN.md` for the design rationale and tuned balance constants, and
`web/` for the original HTML5 Canvas prototype it was ported from).

Requires Godot 4.3+. Open `project.godot` in the Godot editor, or run
headlessly:

```
godot4 --path godot/
```

`scripts/Race.gd` holds the game state, update loop, five-lane perspective
grid, spawning, collision logic, and rendering. The ten-city campaign and the
always-unlocked Impossible space bonus level use data-driven race profiles in
`levels/` as `LevelConfig` resources, exposed by `scripts/LevelCatalog.gd`.
`scenes/LevelSelect.tscn` presents the level grid.

Progression is sequential: completing level N unlocks level N+1. The highest
unlocked level is stored in `user://progress.cfg`; deleting that file resets
progress without affecting other settings. Gold pickups accumulate across
levels in the same save file under `economy/total_gold`, ready to be spent by
the future car-unlock system. Restarting a race resets only its per-run total.

`scenes/Main.tscn` holds the HUD and wires up the swerve/restart buttons.
Approved production art is stored under `assets/` and is drawn on the existing
depth-sorted road.

All five lanes are equal width (20% each). Traffic and hazards are always
spawned on the corresponding mathematical lane centers.

Run the level balance invariant check with:

```
godot4 --headless --path godot --script res://tools/validate_levels.gd
```

Traffic and hazards reserve their lanes until they leave the screen, and each
candidate is projected down the road before spawning to reject any future
visual overlap. Turbo pickup intervals are level-configured at 8–16 seconds,
making boosts meaningfully less frequent than the original 4.5–9.5-second
range. Validate object separation with:

```
godot4 --headless --path godot --script res://tools/validate_obstacle_spacing.gd
```
