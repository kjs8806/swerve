# Swerve (Godot)

The real-engine port of the validated web prototype (see the repo root
`DESIGN.md` for the design rationale and tuned balance constants, and
`web/` for the original HTML5 Canvas prototype it was ported from).

Requires Godot 4.3+. Open `project.godot` in the Godot editor, or run
headlessly:

```
godot4 --path godot/
```

`scripts/Race.gd` holds the entire game: constants, state, update loop,
and rendering (a single `_draw()` pass mirroring the Canvas version's
approach - road, traffic, coins, the finish tape, and turbo effects are
all procedural shapes, not sprites). `scenes/Main.tscn` holds the HUD
(Control nodes) and wires up the swerve/restart buttons.

Known placeholder: all visuals are flat-color procedural shapes, same
as the web prototype - real art/sprites are a later step once the loop
is confirmed fun in this engine too (it already was in the web build).
