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
`scenes/LevelSelect.tscn` presents a racing-lobby city carousel, five-slot
active-parts loadout, and rotating three-offer parts market. The player keeps
the standard gray car while purchasable gameplay
parts in `PartCatalog.gd` provide the run-changing abilities.

Progression is sequential: completing level N unlocks level N+1. The highest
unlocked level is stored in `user://progress.cfg`; deleting that file resets
progress without affecting other settings. A fresh save owns only the Default
car and starts with zero gold. Comet and Apex unlock through campaign progress.
Gold collected during a race is added to the persistent wallet when the race
ends. Part purchases, half-price sales, the five-part inventory, visible shop
offers, escalating refresh cost, and selected car persist in the same file.

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

Validate the parts catalog and rotating-shop invariants with
an isolated user-data directory:

```
XDG_DATA_HOME=/tmp/swerve-test godot4 --headless --path godot --script res://tools/validate_parts_shop.gd
```
