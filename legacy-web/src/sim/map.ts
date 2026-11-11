// The persistent map: terrain, ore veins and the road network.
// Board 1 lays the first spiral-guided road. Every later board strikes in one new road
// that joins the network as close to the core as it can, going around towers when it must.
import {
  BLOCKED_EDGE_COST, CORE_MACRO, CORE_RADIUS, GRID_H, GRID_W, JOIN_K, MACRO, MACRO_H, MACRO_W,
  ORE, PHI, REVEAL, ROAD, TERRAIN,
} from '../balance';
import { Rng, subSeed } from './rng';

export type Pt = { x: number; y: number };
export const mid = (mx: number, my: number) => my * MACRO_W + mx;
export const mxy = (m: number): Pt => ({ x: m % MACRO_W, y: Math.floor(m / MACRO_W) });
export const edgeKey = (a: number, b: number) => (a < b ? a * 1000 + b : b * 1000 + a);
export const cellIdx = (x: number, y: number) => y * GRID_W + x;
export const inGrid = (x: number, y: number) => x >= 0 && y >= 0 && x < GRID_W && y < GRID_H;
export const CORE_ID = mid(CORE_MACRO.x, CORE_MACRO.y);
export const CORE_PT: Pt = { x: CORE_MACRO.x * MACRO + MACRO / 2, y: CORE_MACRO.y * MACRO + MACRO / 2 };
export const macroCentre = (m: number): Pt => ({ x: mxy(m).x * MACRO + MACRO / 2, y: mxy(m).y * MACRO + MACRO / 2 });

export interface Route {
  ingress: number; // ingress index
  pts: Pt[]; // polyline in cell coordinates
  cum: number[]; // cumulative length at each point
  length: number;
  corners: number[]; // distances along the route where the road turns
}

export interface PathState {
  ingressMacro: number;
  start: Pt; // edge point
  path: number[]; // macro ids from ingress to core (or to a join cell)
  revealed: number; // number of macro cells revealed (drives the strike animation)
  joinsAt: number | null; // macro id where this road joins another road
  board: number; // board that added it
}

/** Serialisable board state for saves, retries and undo. */
export interface BoardData {
  seed: number;
  height: number[];
  ore: number[];
  veins: Pt[];
  paths: PathState[];
  cost: number[];
}

function neighbours(m: number): number[] {
  const { x, y } = mxy(m);
  const out: number[] = [];
  if (x > 0) out.push(m - 1);
  if (x < MACRO_W - 1) out.push(m + 1);
  if (y > 0) out.push(m - MACRO_W);
  if (y < MACRO_H - 1) out.push(m + MACRO_W);
  return out;
}

const coreDist = (m: number) => {
  const p = mxy(m);
  return Math.max(Math.abs(p.x - CORE_MACRO.x), Math.abs(p.y - CORE_MACRO.y));
};

/** Distance (macro units) from each macro centre to the nearest arm of the guide spiral. */
function spiralField(rng: Rng): Float32Array {
  const arms = rng.int(2, 3);
  const theta0 = rng.range(0, Math.PI * 2);
  const pts: Pt[] = [];
  const b = (2 * Math.log(PHI)) / Math.PI; // r = a e^(b theta) == a phi^(2 theta / pi)
  for (let k = 0; k < arms; k++) {
    const off = theta0 + (k * Math.PI * 2) / arms;
    for (let th = -6; th < 16; th += 0.05) {
      const r = ROAD.spiralA * Math.exp(b * th);
      if (r > 30) break;
      pts.push({ x: CORE_MACRO.x + 0.5 + r * Math.cos(th + off), y: CORE_MACRO.y + 0.5 + r * Math.sin(th + off) });
    }
  }
  const f = new Float32Array(MACRO_W * MACRO_H);
  for (let m = 0; m < f.length; m++) {
    const c = mxy(m);
    let best = 1e9;
    for (const p of pts) {
      const d = Math.hypot(c.x + 0.5 - p.x, c.y + 0.5 - p.y);
      if (d < best) best = d;
    }
    f[m] = best;
  }
  return f;
}

function costField(rng: Rng): Float32Array {
  const field = spiralField(rng);
  const cost = new Float32Array(field.length);
  for (let m = 0; m < cost.length; m++) cost[m] = 1 + ROAD.spiralK * Math.min(4, field[m]) + rng.range(0, ROAD.noise);
  return cost;
}

/** Cells covered by the road segment between two points (3 cells wide). */
export function segCells(a: Pt, b: Pt): number[] {
  const out: number[] = [];
  const x0 = Math.min(a.x, b.x), x1 = Math.max(a.x, b.x), y0 = Math.min(a.y, b.y), y1 = Math.max(a.y, b.y);
  for (let y = Math.floor(y0) - 1; y < Math.max(Math.ceil(y1), Math.floor(y0) + 1); y++)
    for (let x = Math.floor(x0) - 1; x < Math.max(Math.ceil(x1), Math.floor(x0) + 1); x++)
      if (inGrid(x, y)) out.push(cellIdx(x, y));
  return out;
}

function edgeStart(m: number): Pt {
  const { x, y } = mxy(m);
  const c = macroCentre(m);
  const opts: Pt[] = [];
  if (x === 0) opts.push({ x: 0, y: c.y });
  if (x === MACRO_W - 1) opts.push({ x: GRID_W, y: c.y });
  if (y === 0) opts.push({ x: c.x, y: 0 });
  if (y === MACRO_H - 1) opts.push({ x: c.x, y: GRID_H });
  opts.sort((a, b) => Math.hypot(b.x - CORE_PT.x, b.y - CORE_PT.y) - Math.hypot(a.x - CORE_PT.x, a.y - CORE_PT.y));
  return opts[0];
}

interface RouteParams {
  cost: Float32Array;
  forbidden: Set<number>;
  terminal: (m: number) => number | null; // extra cost when this macro ends the road, or null if it cannot end here
  avoid: Set<number>;
  edgeCost?: (a: number, b: number) => number;
}

/** Dijkstra on the macro grid with terminal costs. */
function routeMacro(from: number, p: RouteParams): number[] | null {
  const N = MACRO_W * MACRO_H;
  const dist = new Float64Array(N).fill(Infinity);
  const prev = new Int32Array(N).fill(-1);
  const done = new Uint8Array(N);
  const isTerm = new Uint8Array(N);
  dist[from] = 0;
  let bestEnd = -1, bestTotal = Infinity;
  for (;;) {
    let u = -1;
    let best = Infinity;
    for (let i = 0; i < N; i++) if (!done[i] && dist[i] < best) { best = dist[i]; u = i; }
    if (u < 0 || best >= bestTotal) break;
    done[u] = 1;
    if (u !== from) {
      const tc = p.terminal(u);
      if (tc !== null) {
        isTerm[u] = 1;
        if (dist[u] + tc < bestTotal) { bestTotal = dist[u] + tc; bestEnd = u; }
        continue; // a road stops where it meets the network
      }
    }
    for (const v of neighbours(u)) {
      if (done[v] || p.forbidden.has(v)) continue;
      const nd = dist[u] + p.cost[v] + (p.avoid.has(v) && coreDist(v) > 2 ? 2.5 : 0) + (p.edgeCost ? p.edgeCost(u, v) : 0);
      if (nd < dist[v]) { dist[v] = nd; prev[v] = u; }
    }
  }
  if (bestEnd < 0) return null;
  const out: number[] = [];
  for (let c = bestEnd; c >= 0; c = prev[c]) out.push(c);
  return out.reverse();
}

/** True if the path doubles back next to itself away from the core (parallel roads too close). */
function hasHairpin(path: number[]): boolean {
  for (let i = 0; i < path.length; i++) {
    for (let j = i + 3; j < path.length; j++) {
      const a = mxy(path[i]);
      const b = mxy(path[j]);
      if (Math.abs(a.x - b.x) + Math.abs(a.y - b.y) === 1 && coreDist(path[i]) > 2 && coreDist(path[j]) > 2) return true;
    }
  }
  return false;
}

export class Board {
  readonly seed: number;
  height = new Int8Array(GRID_W * GRID_H);
  road = new Uint8Array(GRID_W * GRID_H);
  ore = new Uint8Array(GRID_W * GRID_H); // vein index + 1
  veins: Pt[] = [];
  paths: PathState[] = [];
  routes: Route[] = [];
  /** The road being struck in this board (shown by the reveal), or null. */
  pending: PathState | null = null;
  /** Cells the pending road will cover. */
  pendingCells: number[] = [];
  /** Bumped whenever road cells change, so the renderer can redraw. */
  version = 0;
  minLength: number;
  private cost: Float32Array;

  constructor(seed: number, data?: BoardData) {
    this.seed = seed;
    const rng = new Rng(subSeed(seed, 101, 1));
    this.minLength = ROAD.minLenBase + rng.int(-ROAD.minLenJitter, ROAD.minLenJitter);
    this.cost = new Float32Array(MACRO_W * MACRO_H);
    if (data) {
      this.height = Int8Array.from(data.height);
      this.ore = Uint8Array.from(data.ore);
      this.veins = data.veins.map((v) => ({ ...v }));
      this.paths = data.paths.map((p) => ({ ...p, path: p.path.slice(), start: { ...p.start } }));
      this.cost = Float32Array.from(data.cost);
      this.rebuildRoad();
      return;
    }
    this.pending = this.planFirstRoad();
    this.pendingCells = this.cellsOf(this.pending);
    this.makeTerrain();
  }

  serialize(): BoardData {
    return {
      seed: this.seed, height: Array.from(this.height), ore: Array.from(this.ore), veins: this.veins.map((v) => ({ ...v })),
      paths: this.paths.map((p) => ({ ...p, path: p.path.slice(), start: { ...p.start } })), cost: Array.from(this.cost),
    };
  }

  // ------------------------------------------------------------- roads
  private roadMacros(): Set<number> {
    const s = new Set<number>();
    for (const p of this.paths) for (const c of p.path) if (c !== CORE_ID) s.add(c);
    return s;
  }

  private planFirstRoad(): PathState {
    let best: { path: PathState; cost: Float32Array; score: number } | null = null;
    for (let attempt = 0; attempt < ROAD.attempts; attempt++) {
      const rng = new Rng(subSeed(this.seed, 202, 1, attempt));
      const cost = costField(rng);
      const edgeCells: number[] = [];
      for (let m = 0; m < cost.length; m++) {
        const p = mxy(m);
        if ((p.x === 0 || p.y === 0 || p.x === MACRO_W - 1 || p.y === MACRO_H - 1) && coreDist(m) >= 4) edgeCells.push(m);
      }
      const ing = rng.pick(edgeCells);
      const path = this.curlRoute(ing, cost, rng);
      if (!path || hasHairpin(path)) continue;
      const ps: PathState = { ingressMacro: ing, start: edgeStart(ing), path, revealed: 1, joinsAt: null, board: 1 };
      const len = this.pathLength(ps, [ps]);
      const score = len >= this.minLength ? 1000 - Math.abs(len - this.minLength - 20) : len;
      if (!best || score > best.score) best = { path: ps, cost, score };
      if (len >= this.minLength && len <= this.minLength + 50) break;
    }
    if (!best) throw new Error('road generation failed');
    this.cost = best.cost;
    return best.path;
  }

  private curlRoute(ing: number, cost: Float32Array, rng: Rng): number[] | null {
    const toCore = (m: number) => (m === CORE_ID ? 0 : null);
    const base: RouteParams = { cost, forbidden: new Set(), terminal: toCore, avoid: new Set() };
    const direct = routeMacro(ing, base);
    if (!direct) return null;
    if (direct.length * MACRO >= this.minLength) return direct;
    // pick a waypoint around the core on the opposite side from the ingress so the road curls
    const ip = mxy(ing);
    const ang = Math.atan2(ip.y - CORE_MACRO.y, ip.x - CORE_MACRO.x) + Math.PI + rng.range(-0.9, 0.9);
    const r = rng.range(2.2, 3.6);
    const wx = Math.max(0, Math.min(MACRO_W - 1, Math.round(CORE_MACRO.x + r * Math.cos(ang))));
    const wy = Math.max(0, Math.min(MACRO_H - 1, Math.round(CORE_MACRO.y + r * Math.sin(ang))));
    const way = mid(wx, wy);
    if (way === CORE_ID || coreDist(way) < 2) return direct;
    const first = routeMacro(ing, { ...base, forbidden: new Set([CORE_ID]), terminal: (m) => (m === way ? 0 : null) });
    if (!first) return direct;
    const second = routeMacro(way, { ...base, forbidden: new Set(first.slice(0, -1)) });
    if (!second) return direct;
    return first.concat(second.slice(1));
  }

  /** Road distance (macro steps) from every road macro to the core. */
  private roadDistance(): Map<number, number> {
    const next = new Map<number, number>();
    for (const p of this.paths) for (let i = 0; i + 1 < p.path.length; i++) next.set(p.path[i], p.path[i + 1]);
    const out = new Map<number, number>();
    const walk = (m: number): number => {
      if (m === CORE_ID) return 0;
      const known = out.get(m);
      if (known !== undefined) return known;
      out.set(m, 999); // cycle guard
      const n = next.get(m);
      const d = n === undefined ? 999 : walk(n) + 1;
      out.set(m, d);
      return d;
    };
    for (const p of this.paths) for (const c of p.path) walk(c);
    return out;
  }

  /**
   * Plan the road a new board strikes in. It starts on an unused edge far from the other spawns,
   * prefers to join the network close to the core, and routes around cells where blocked() is true.
   * Returns the cells of objects the strike will have to clear (empty unless every route is blocked).
   */
  planRoad(b: number, blocked: (cell: number) => boolean): { path: PathState; destroys: number[] } {
    const rng = new Rng(subSeed(this.seed, 202, b));
    const cost = costField(rng);
    const used = this.roadMacros();
    const starts = this.paths.map((p) => mxy(p.ingressMacro));
    const cands: { m: number; score: number }[] = [];
    for (let m = 0; m < cost.length; m++) {
      const p = mxy(m);
      if (!(p.x === 0 || p.y === 0 || p.x === MACRO_W - 1 || p.y === MACRO_H - 1)) continue;
      if (used.has(m) || coreDist(m) < 5) continue;
      if (neighbours(m).some((n) => used.has(n))) continue;
      const far = starts.length ? Math.min(...starts.map((q) => Math.abs(q.x - p.x) + Math.abs(q.y - p.y))) : 99;
      cands.push({ m, score: Math.min(far, 12) + coreDist(m) * 0.8 + rng.range(0, 4) });
    }
    cands.sort((a, b2) => b2.score - a.score);
    const rd = this.roadDistance();
    const avoid = new Set<number>();
    for (const u of used) for (const v of neighbours(u)) avoid.add(v);
    const centres = (a: number, c: number) => segCells(macroCentre(a), macroCentre(c));
    const edgeBlocked = new Map<number, boolean>();
    const isBlocked = (a: number, c: number) => {
      const k = edgeKey(a, c);
      let v = edgeBlocked.get(k);
      if (v === undefined) { v = centres(a, c).some(blocked); edgeBlocked.set(k, v); }
      return v;
    };
    let fallback: { path: PathState; destroys: number[] } | null = null;
    for (const cand of cands.slice(0, 6)) {
      const ing = cand.m;
      const startPt = edgeStart(ing);
      const startCells = segCells(startPt, macroCentre(ing));
      const startBlocked = startCells.some(blocked);
      const path = routeMacro(ing, {
        cost,
        forbidden: new Set(),
        terminal: (m) => (m === CORE_ID ? 0 : used.has(m) ? JOIN_K * (rd.get(m) ?? 50) : null),
        avoid,
        edgeCost: (a, c) => (isBlocked(a, c) ? BLOCKED_EDGE_COST : 0),
      });
      if (!path || path.length < 2) continue;
      const end = path[path.length - 1];
      const ps: PathState = { ingressMacro: ing, start: startPt, path, revealed: 1, joinsAt: end === CORE_ID ? null : end, board: b };
      const destroys = new Set<number>();
      if (startBlocked) for (const c of startCells) if (blocked(c)) destroys.add(c);
      for (let i = 0; i + 1 < path.length; i++) if (isBlocked(path[i], path[i + 1])) for (const c of centres(path[i], path[i + 1])) if (blocked(c)) destroys.add(c);
      const res = { path: ps, destroys: [...destroys] };
      if (!destroys.size) return res;
      if (!fallback || res.destroys.length < fallback.destroys.length) fallback = res;
    }
    if (fallback) return fallback;
    throw new Error('no road could be planned');
  }

  /** Cells covered by a path. */
  cellsOf(p: PathState): number[] {
    const out = new Set<number>();
    for (const c of segCells(p.start, macroCentre(p.path[0]))) out.add(c);
    for (let i = 0; i + 1 < p.path.length; i++) for (const c of segCells(macroCentre(p.path[i]), macroCentre(p.path[i + 1]))) out.add(c);
    return [...out];
  }

  setPending(p: PathState) {
    this.pending = p;
    this.pendingCells = this.cellsOf(p);
  }

  /** Road length in cells for a path, following joins to the core. */
  pathLength(p: PathState, all: PathState[] = this.paths): number {
    let len = Math.hypot(p.start.x - macroCentre(p.path[0]).x, p.start.y - macroCentre(p.path[0]).y);
    len += (p.path.length - 1) * MACRO;
    let j = p.joinsAt;
    let guard = 0;
    while (j !== null && guard++ < 10) {
      const host = all.find((q) => q !== p && q.path.includes(j!) && q.path[q.path.length - 1] !== j);
      if (!host) break;
      len += (host.path.length - 1 - host.path.indexOf(j)) * MACRO;
      j = host.joinsAt;
    }
    return len;
  }

  /** Macro steps the strike animation covers. */
  revealTotal(): number {
    return this.pending ? this.pending.path.length : 1;
  }

  /**
   * Commit the pending road: lay its cells, flatten the ground around it (never under objects),
   * rebuild routes and add ore veins near it.
   */
  commitPending(occupied: (cell: number) => boolean) {
    const p = this.pending;
    if (!p) return;
    p.revealed = p.path.length;
    this.paths.push(p);
    this.pending = null;
    this.pendingCells = [];
    this.rebuildRoad(occupied);
    const rng = new Rng(subSeed(this.seed, 303, p.board));
    const count = p.board === 1 ? rng.int(ORE.min, ORE.max) : ORE.perNewRoad;
    this.makeOre(rng, count, new Set(this.cellsOf(p)), occupied);
  }

  /** Lay road cells for every committed path, flatten around them and rebuild routes. */
  rebuildRoad(occupied: (cell: number) => boolean = () => false) {
    this.road.fill(0);
    for (const p of this.paths) for (const c of this.cellsOf(p)) this.road[c] = 1;
    for (let y = 0; y < GRID_H; y++)
      for (let x = 0; x < GRID_W; x++) {
        const i = cellIdx(x, y);
        if (this.height[i] === 0 || occupied(i)) continue;
        let near = false;
        for (let dy = -1; dy <= 1 && !near; dy++)
          for (let dx = -1; dx <= 1; dx++) if (inGrid(x + dx, y + dy) && this.road[cellIdx(x + dx, y + dy)]) { near = true; break; }
        if (near || Math.hypot(x + 0.5 - CORE_PT.x, y + 0.5 - CORE_PT.y) < CORE_RADIUS + 2) this.height[i] = 0;
      }
    for (let i = 0; i < this.road.length; i++) if (this.road[i]) this.ore[i] = 0;
    this.buildRoutes();
    this.version++;
  }

  private buildRoutes() {
    const next = new Map<number, number[]>();
    const add = (a: number, b: number) => {
      const l = next.get(a) ?? [];
      if (!l.includes(b)) l.push(b);
      next.set(a, l);
    };
    for (const p of this.paths) for (let i = 0; i + 1 < p.path.length; i++) add(p.path[i], p.path[i + 1]);
    this.routes = [];
    this.paths.forEach((p, ingress) => {
      const found: number[][] = [];
      const dfs = (c: number, acc: number[], seen: Set<number>) => {
        if (found.length >= 4) return;
        if (c === CORE_ID) { found.push(acc.slice()); return; }
        for (const n of next.get(c) ?? []) {
          if (seen.has(n)) continue;
          seen.add(n); acc.push(n);
          dfs(n, acc, seen);
          acc.pop(); seen.delete(n);
        }
      };
      dfs(p.path[0], [p.path[0]], new Set([p.path[0]]));
      for (const macros of found) this.routes.push(makeRoute(ingress, [p.start, ...macros.map(macroCentre)]));
    });
  }

  // ------------------------------------------------------------- terrain & ore
  private makeTerrain() {
    const rng = new Rng(subSeed(this.seed, 404, 1));
    const planned = new Set<number>(this.pending ? this.pending.path : []);
    for (let m = 0; m < MACRO_W * MACRO_H; m++) {
      if (planned.has(m) || coreDist(m) < 1) continue;
      const nf = rng.pick(TERRAIN.featuresPerMacro);
      const { x: mx, y: my } = mxy(m);
      for (let f = 0; f < nf; f++) {
        const s = rng.pick(TERRAIN.blobSizes);
        const h = rng.chance(0.6) ? rng.int(TERRAIN.rise[0], TERRAIN.rise[1]) : rng.int(TERRAIN.valley[0], TERRAIN.valley[1]);
        const ox = mx * MACRO + rng.int(0, MACRO - s);
        const oy = my * MACRO + rng.int(0, MACRO - s);
        for (let y = 0; y < s; y++)
          for (let x = 0; x < s; x++) {
            if (s >= 5 && (x === 0 || x === s - 1) && (y === 0 || y === s - 1)) continue; // round the big blobs
            this.height[cellIdx(ox + x, oy + y)] = h;
          }
      }
    }
  }

  private makeOre(rng: Rng, n: number, near: Set<number>, occupied: (cell: number) => boolean) {
    let added = 0;
    for (let tries = 0; tries < 600 && added < n; tries++) {
      const x = rng.int(1, GRID_W - ORE.size - 1);
      const y = rng.int(1, GRID_H - ORE.size - 1);
      let ok = Math.hypot(x - CORE_PT.x, y - CORE_PT.y) > 10;
      for (let dy = -2; dy < ORE.size + 2 && ok; dy++)
        for (let dx = -2; dx < ORE.size + 2; dx++) {
          const cx = x + dx, cy = y + dy;
          if (!inGrid(cx, cy)) continue;
          const i = cellIdx(cx, cy);
          if (this.road[i] || this.ore[i] || occupied(i)) { ok = false; break; }
        }
      // keep veins within reach of the new road so harvesters sit in the action
      let nearRoad = false;
      for (let dy = -10; dy < 13 && ok && !nearRoad; dy++)
        for (let dx = -10; dx < 13; dx++) if (inGrid(x + dx, y + dy) && near.has(cellIdx(x + dx, y + dy))) { nearRoad = true; break; }
      if (!ok || !nearRoad) continue;
      this.veins.push({ x, y });
      added++;
      for (let dy = 0; dy < ORE.size; dy++)
        for (let dx = 0; dx < ORE.size; dx++) {
          this.ore[cellIdx(x + dx, y + dy)] = this.veins.length;
          this.height[cellIdx(x + dx, y + dy)] = 0;
        }
    }
  }

  isCoreCell(x: number, y: number): boolean {
    return Math.abs(x + 0.5 - CORE_PT.x) < CORE_RADIUS && Math.abs(y + 0.5 - CORE_PT.y) < CORE_RADIUS;
  }
  h(x: number, y: number): number {
    return this.height[cellIdx(x, y)];
  }
  isRoad(x: number, y: number): boolean {
    return this.road[cellIdx(x, y)] === 1;
  }
}

export function makeRoute(ingress: number, pts: Pt[]): Route {
  const cum = [0];
  const corners: number[] = [];
  for (let i = 1; i < pts.length; i++) cum.push(cum[i - 1] + Math.hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y));
  for (let i = 1; i + 1 < pts.length; i++) {
    const a = Math.atan2(pts[i].y - pts[i - 1].y, pts[i].x - pts[i - 1].x);
    const b = Math.atan2(pts[i + 1].y - pts[i].y, pts[i + 1].x - pts[i].x);
    if (Math.abs(a - b) > 0.1) corners.push(cum[i]);
  }
  return { ingress, pts, cum, length: cum[cum.length - 1], corners };
}

/** Position and heading at distance d along a route. */
export function routeAt(r: Route, d: number): { x: number; y: number; dir: number } {
  if (d <= 0) {
    const a = r.pts[0], b = r.pts[1];
    return { x: a.x, y: a.y, dir: Math.atan2(b.y - a.y, b.x - a.x) };
  }
  let lo = 1, hi = r.cum.length - 1;
  while (lo < hi) {
    const m = (lo + hi) >> 1;
    if (r.cum[m] < d) lo = m + 1; else hi = m;
  }
  const i = lo;
  if (d >= r.length) {
    const a = r.pts[r.pts.length - 2], b = r.pts[r.pts.length - 1];
    return { x: b.x, y: b.y, dir: Math.atan2(b.y - a.y, b.x - a.x) };
  }
  const a = r.pts[i - 1], b = r.pts[i];
  const seg = r.cum[i] - r.cum[i - 1];
  const t = seg > 0 ? (d - r.cum[i - 1]) / seg : 0;
  return { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, dir: Math.atan2(b.y - a.y, b.x - a.x) };
}

export { REVEAL };
