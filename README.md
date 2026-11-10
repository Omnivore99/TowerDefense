# Satisfying TD

A tower defense game where you build towers from falling Tetris-style pieces. Every shape,
colour and story you stack changes how a tower fights.

- **v2.0 (3D, Godot 4.7)** lives in [`game/`](game/). Play it in the browser at
  https://omnivore99.github.io/TowerDefense/ once `main` deploys.
- **v1.1 (2D, TypeScript + Canvas)** lives in [`legacy-web/`](legacy-web/) and stays playable at
  https://omnivore99.github.io/TowerDefense/v1/.

## Running v2.0

1. Install [Godot 4.7](https://godotengine.org/download) (standard build, not .NET).
2. Open `game/project.godot` in the editor and press F5, or run `godot --path game`.

Controls: left click places the piece in hand or selects a tower, right-drag or WASD pans,
the wheel zooms, Q / E turn the camera, Home recentres. R rotates the piece, F mirrors it,
H puts it on hold, Space or Enter calls the next wave, Esc undoes a placement within 2 seconds.
1 2 3 pick MUST USE pieces, 4 to 7 pick MAY USE pieces, [ and ] change speed, P pauses.

## Tools

All of these run without a window:

```sh
godot --headless --path game -- --tests                       # unit + determinism tests
godot --headless --path game -- --bots --seeds 8 --jobs 4     # balance bots (all skills)
godot --headless --path game -- --bots --skill average --seeds 4 --mode normal --json
```

Bot reports print a table per board (clear rate, base HP lost, time in danger) and with
`--json` write `reports/bots-<skill>-<mode>.json`.

Demo and screenshots (needs a display or `xvfb-run`):

```sh
godot --path game -- --demo --warp 2,3,8 --shot shot.png      # expert bot, board 2 wave 3
```

## Layout

| Path | What |
| --- | --- |
| `game/balance/balance.gd` | Every tunable number (class `Bal`) |
| `game/sim/` | Deterministic 60 Hz simulation, no rendering (pieces, board, waves, towers, game) |
| `game/bots/` | Bot players and the balance harness |
| `game/view/` | 3D world: procedural model kit, terrain, towers, monsters, FX, camera |
| `game/ui/` | HUD and screens |
| `game/tests/` | Tests, including bit-exact checks against v1.1's random streams |
| `legacy-web/` | v1.1 |
| `docs/references/` | Art direction pictures |
