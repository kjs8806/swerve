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
grid, spawning, collision logic, and rendering. `scenes/Main.tscn` holds
the HUD and wires up the swerve/restart buttons. Approved production art
is stored under `assets/` and is drawn on the existing depth-sorted road.

All five lanes are equal width (20% each). Traffic and hazards are always
spawned on the corresponding mathematical lane centers.
