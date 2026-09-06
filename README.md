# Swerve

A 5-lane arcade dodge-racer prototype: swerve between lanes to avoid
traffic, chain near-misses for speed boosts, bank coins to trigger an
invincible turbo burst, and reach the finish line before the 60-second
clock runs out.

See [`DESIGN.md`](./DESIGN.md) for the design rationale, scope
decisions, and roadmap.

## Run the prototype

This is a static HTML5 Canvas + vanilla JS build — no build step.

```
cd web
python3 -m http.server 8080
```

Then open `http://localhost:8080` in a browser. Use the on-screen
◁ / ▷ buttons (or Left/Right arrow keys) to swerve.
