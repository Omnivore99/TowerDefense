// Ground and road art: a dusk-lit meadow with hills, hollows, flowers, rocks and a worn dirt road.
// Everything is vector and static, drawn once per road change, so it stays sharp at any zoom.
import { Graphics } from 'pixi.js';
import { GRID_H, GRID_W, MACRO } from '../balance';
import { type Board, CORE_PT, cellIdx } from '../sim/map';

export const TERRAIN_PAL = {
  grass: [0x1f3b2c, 0x234230, 0x274934, 0x2b5038, 0x30573c, 0x355e40, 0x3a6544],
  rise: [0x456a46, 0x58724f, 0x6c7863],
  cliff: [0x3a3a31, 0x2d2c26],
  valley: [0x1b3227, 0x162b23],
  water: 0x2b5866,
  dirt: [0x6f553e, 0x7a5e44, 0x846649],
  dirtEdge: 0x4d3a2a,
  rut: 0x5a4532,
  tuft: 0x5a9a5e,
  flower: [0xffd36b, 0xff8fb0, 0xd0b8ff, 0xf4f1e6],
  pebble: 0x8d8a7c,
  rock: 0x878b82,
  rockLt: 0xc3c6bb,
};

function hash(x: number, y: number, s: number): number {
  let h = (x * 374761393 + y * 668265263 + s * 2147483647) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}

function smooth(x: number, y: number, scale: number, s: number): number {
  const fx = x / scale, fy = y / scale;
  const x0 = Math.floor(fx), y0 = Math.floor(fy);
  const tx = fx - x0, ty = fy - y0;
  const sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty);
  const a = hash(x0, y0, s), b = hash(x0 + 1, y0, s), c = hash(x0, y0 + 1, s), d = hash(x0 + 1, y0 + 1, s);
  return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy;
}

/** Ground, hills, hollows, decorations and grid. */
export function drawTerrain(g: Graphics, b: Board) {
  g.clear();
  const seed = b.seed % 9973;
  // world edge: a dark drop and a soft rim
  g.roundRect(-2.2, -1.6, GRID_W + 4.4, GRID_H + 4.6, 3).fill({ color: 0x000000, alpha: 0.35 });
  g.rect(-0.5, GRID_H, GRID_W + 1, 1.6).fill(0x1a1712);
  g.rect(-0.5, GRID_H, GRID_W + 1, 0.4).fill(0x2a241b);
  // ground colour by noise, run-length encoded per row
  const P = TERRAIN_PAL;
  const groundColor = (x: number, y: number) => {
    const h = b.height[cellIdx(x, y)];
    if (h > 0) return P.rise[Math.min(2, h - 1)];
    if (h < 0) return P.valley[Math.min(1, -h - 1)];
    const n = smooth(x, y, 7, seed) * 0.6 + smooth(x, y, 19, seed + 7) * 0.4;
    const core = Math.hypot(x - CORE_PT.x, y - CORE_PT.y);
    const warm = core < 14 ? (14 - core) / 14 * 0.15 : 0;
    const k = Math.max(0, Math.min(P.grass.length - 1, Math.floor((n + warm) * P.grass.length)));
    return P.grass[k];
  };
  for (let y = 0; y < GRID_H; y++) {
    let runStart = 0, runCol = groundColor(0, y);
    for (let x = 1; x <= GRID_W; x++) {
      const c = x < GRID_W ? groundColor(x, y) : -1;
      if (c !== runCol) {
        g.rect(runStart, y, x - runStart, 1.02).fill(runCol);
        runStart = x;
        runCol = c;
      }
    }
  }
  // hills: lit top edge, cliff faces below, side shadows
  for (let y = 0; y < GRID_H; y++)
    for (let x = 0; x < GRID_W; x++) {
      const h = b.height[cellIdx(x, y)];
      const hd = y + 1 < GRID_H ? b.height[cellIdx(x, y + 1)] : 0;
      const hr = x + 1 < GRID_W ? b.height[cellIdx(x + 1, y)] : 0;
      const hu = y > 0 ? b.height[cellIdx(x, y - 1)] : 0;
      const hl = x > 0 ? b.height[cellIdx(x - 1, y)] : 0;
      if (h > hd) {
        const fh = 0.28 * (h - hd);
        g.rect(x, y + 1, 1, fh).fill(P.cliff[0]);
        g.rect(x, y + 1 + fh * 0.55, 1, fh * 0.45).fill(P.cliff[1]);
        g.rect(x, y + 1, 1, 0.06).fill({ color: 0xffffff, alpha: 0.08 });
      }
      if (h > hr) g.rect(x + 1, y, 0.14 * (h - hr), 1).fill({ color: 0x000000, alpha: 0.22 });
      if (h > hu) g.rect(x, y, 1, 0.1).fill({ color: 0xfff5d0, alpha: 0.08 * (h - hu) });
      if (h > hl) g.rect(x, y, 0.07, 1).fill({ color: 0xfff5d0, alpha: 0.05 });
      if (h < 0 && hu >= 0) g.rect(x, y, 1, 0.25).fill({ color: 0x000000, alpha: 0.25 });
      if (h < 0 && hl >= 0) g.rect(x, y, 0.18, 1).fill({ color: 0x000000, alpha: 0.18 });
    }
  // decorations
  for (let y = 0; y < GRID_H; y++)
    for (let x = 0; x < GRID_W; x++) {
      const i = cellIdx(x, y);
      if (b.road[i] || b.ore[i] || b.isCoreCell(x, y) || Math.hypot(x + 0.5 - CORE_PT.x, y + 0.5 - CORE_PT.y) < 4.5) continue;
      const r = hash(x, y, seed + 31);
      const h = b.height[i];
      const ox = 0.2 + hash(x, y, seed + 5) * 0.6, oy = 0.2 + hash(x, y, seed + 6) * 0.6;
      if (h > 0) {
        if (r < 0.1) rock(g, x + ox, y + oy, 0.2 + hash(x, y, 9) * 0.22);
        else if (r < 0.16) tuft(g, x + ox, y + oy, P.tuft);
      } else if (h < 0) {
        if (r < 0.07 && h <= -2) g.ellipse(x + 0.5, y + 0.55, 0.42, 0.28).fill({ color: P.water, alpha: 0.85 }).ellipse(x + 0.4, y + 0.48, 0.15, 0.05).fill({ color: 0xffffff, alpha: 0.25 });
        else if (r < 0.14) tuft(g, x + ox, y + oy, 0x3f7a4c);
      } else {
        if (r < 0.035) flower(g, x + ox, y + oy, P.flower[Math.floor(hash(x, y, 77) * 4)]);
        else if (r < 0.11) tuft(g, x + ox, y + oy, P.tuft);
        else if (r < 0.125) g.ellipse(x + ox, y + oy, 0.13, 0.09).fill(P.pebble).ellipse(x + ox - 0.03, y + oy - 0.03, 0.06, 0.03).fill({ color: 0xffffff, alpha: 0.3 });
        else if (r < 0.128) rock(g, x + ox, y + oy, 0.28);
      }
    }
  // grid: faint cells, slightly stronger macro squares
  for (let x = 0; x <= GRID_W; x++) g.moveTo(x, 0).lineTo(x, GRID_H);
  for (let y = 0; y <= GRID_H; y++) g.moveTo(0, y).lineTo(GRID_W, y);
  g.stroke({ width: 0.03, color: 0xffffff, alpha: 0.045 });
  for (let x = 0; x <= GRID_W; x += MACRO) g.moveTo(x, 0).lineTo(x, GRID_H);
  for (let y = 0; y <= GRID_H; y += MACRO) g.moveTo(0, y).lineTo(GRID_W, y);
  g.stroke({ width: 0.05, color: 0xffffff, alpha: 0.07 });
}

function tuft(g: Graphics, x: number, y: number, c: number) {
  g.moveTo(x - 0.14, y + 0.12).lineTo(x - 0.2, y - 0.14).moveTo(x, y + 0.12).lineTo(x + 0.02, y - 0.22).moveTo(x + 0.13, y + 0.12).lineTo(x + 0.22, y - 0.1)
    .stroke({ width: 0.06, color: c, cap: 'round' });
}

function flower(g: Graphics, x: number, y: number, c: number) {
  for (let k = 0; k < 5; k++) { const a = (k / 5) * Math.PI * 2; g.circle(x + Math.cos(a) * 0.1, y + Math.sin(a) * 0.1, 0.065).fill(c); }
  g.circle(x, y, 0.05).fill(0xffe9a0);
}

function rock(g: Graphics, x: number, y: number, r: number) {
  const P = TERRAIN_PAL;
  g.ellipse(x + r * 0.15, y + r * 0.35, r * 1.05, r * 0.5).fill({ color: 0x000000, alpha: 0.25 });
  g.poly([x - r, y + r * 0.2, x - r * 0.6, y - r * 0.6, x + r * 0.2, y - r * 0.8, x + r, y - r * 0.1, x + r * 0.7, y + r * 0.45, x - r * 0.4, y + r * 0.5]).fill(P.rock);
  g.poly([x - r * 0.6, y - r * 0.6, x + r * 0.2, y - r * 0.8, x + r * 0.45, y - r * 0.35, x - r * 0.3, y - r * 0.15]).fill(P.rockLt);
}

/** The dirt road: worn edges, grass fringe, wheel ruts along every route and scattered stones. */
export function drawRoad(g: Graphics, b: Board) {
  g.clear();
  const P = TERRAIN_PAL;
  const seed = b.seed % 9973;
  const isRoad = (x: number, y: number) => x >= 0 && y >= 0 && x < GRID_W && y < GRID_H && b.road[cellIdx(x, y)] === 1;
  // soft shoulder under the road
  for (let y = 0; y < GRID_H; y++)
    for (let x = 0; x < GRID_W; x++) if (isRoad(x, y)) g.rect(x - 0.2, y - 0.1, 1.4, 1.3).fill({ color: P.dirtEdge, alpha: 0.35 });
  for (let y = 0; y < GRID_H; y++)
    for (let x = 0; x < GRID_W; x++) {
      if (!isRoad(x, y)) continue;
      const n = smooth(x, y, 4, seed + 3);
      g.rect(x, y, 1.02, 1.02).fill(P.dirt[Math.min(2, Math.floor(n * 3))]);
    }
  for (let y = 0; y < GRID_H; y++)
    for (let x = 0; x < GRID_W; x++) {
      if (!isRoad(x, y)) continue;
      if (!isRoad(x, y - 1)) { g.rect(x, y, 1, 0.16).fill({ color: P.dirtEdge, alpha: 0.75 }); if (hash(x, y, seed) < 0.5) tuft(g, x + 0.5, y - 0.05, P.tuft); }
      if (!isRoad(x, y + 1)) { g.rect(x, y + 0.84, 1, 0.16).fill({ color: 0x000000, alpha: 0.28 }); }
      if (!isRoad(x - 1, y)) g.rect(x, y, 0.14, 1).fill({ color: P.dirtEdge, alpha: 0.6 });
      if (!isRoad(x + 1, y)) g.rect(x + 0.86, y, 0.14, 1).fill({ color: 0x000000, alpha: 0.22 });
      const r = hash(x, y, seed + 91);
      if (r < 0.08) g.ellipse(x + 0.3 + r * 4, y + 0.6, 0.09, 0.06).fill(P.pebble);
    }
  // ruts follow the routes
  for (const route of b.routes) {
    for (const off of [-0.55, 0.55]) {
      const pts = route.pts;
      for (let i = 0; i + 1 < pts.length; i++) {
        const a = pts[i], c = pts[i + 1];
        const dx = c.x - a.x, dy = c.y - a.y, len = Math.hypot(dx, dy) || 1;
        const nx = -dy / len * off, ny = dx / len * off;
        g.moveTo(a.x + nx, a.y + ny).lineTo(c.x + nx, c.y + ny);
      }
      g.stroke({ width: 0.12, color: P.rut, alpha: 0.55, cap: 'round', join: 'round' });
    }
  }
}
