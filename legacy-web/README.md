# Satisfying TD v1.0

Browser tower defense: towers are built Tetris-style from falling pieces, the base grows along a golden spiral of Fibonacci squares.

## Run

```
npm install
npm run dev        # dev server
npm run build      # typecheck + single-file build to dist/index.html (runs from file:// or any static host)
npm run bots       # headless balance harness (options: --seeds 8 --mode normal --skill novice,average,expert --json)
```

Open `dist/index.html?bots=1` (optionally `&seeds=3&mode=golden`) to run the harness in a browser.

## Layout

- `src/balance.ts` – every tunable number (H_b, tower stats, odds, timings, costs).
- `src/sim/` – pure, deterministic logic at 60 Hz: `map.ts` (terrain, ore, spiral-guided roadway, seals), `pieces.ts`, `towers.ts` (recipes, shape bonuses, stats), `waves.ts`, `base.ts`, `game.ts` (state machine, placement, combat).
- `src/render/` – PixiJS v8 renderer (2.5D towers, enemies, effects, ghost, camera).
- `src/audio/` – procedural Web Audio, pentatonic.
- `src/ui/` – DOM HUD, menus, base screen, input (mouse, keyboard, touch).
- `src/bots/` – novice / average / expert bots and the harness.
- `src/save.ts` – localStorage run, settings, playtest metrics.

## Controls

Drag or click a piece, then click the board. R / wheel / right-click rotate, F mirror, Space drop, H hold, Esc cancel,
B recipe book, P pause, Enter ready, Ctrl+wheel or +/- zoom, WASD / arrows pan when zoomed. Touch: drag to place, two-finger tap rotates.

## Interpretation notes

Where the build prompt left room, these choices were made (all easy to change):

- Wave arrivals go to MUST USE; the board-start grant and calm pieces fill the MAY USE tray first and overflow to MUST USE (so a 5-piece grant is 2 MUST + 3 MAY).
- Hold swaps once per placement, as in Tetris. Recycling counts as a placement.
- A story layer can be several pieces (that is how 13/8/5/3 Fibonacci Spires are possible); each layer must have fewer cells than the one below.
- Archetypes unlock gradually: hoppers on board 1, slinky/roller from 2, swinger/tumbler from 3, nautilus and balloons from 4, giant walkers from 5.
- Losing a board restores the base to its state at the start of that board and lets you retry.
