// Board generation: terrain, ore veins and the spiral-guided Roadway.
import {
  CORE_MACRO, CORE_RADIUS, GRID_H, GRID_W, INGRESS_BY_BOARD, MACRO, MACRO_H, MACRO_W,
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
  revealed: number; // number of macro cells revealed
  joinsAt: number | null; // macro id where this road joins another road
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
    for (let th = -6; th < 14; th += 0.05) {
      const r = ROAD.spiralA * Math.exp(b * th);
      if (r > 20) break;
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

export interface RoadParams {
  cost: Float32Array;
  seals: Set<number>;
  forbidden: Set<number>;
  joinable: Set<number>;
  avoid: Set<number>; // cells near other roads (penalised)
}

/** Dijkstra on the macro grid. Stops at the core or at any joinable road cell. */
export function routeMacro(from: number, p: RoadParams, target: number | null = null): number[] | null {
  const N = MACRO_W * MACRO_H;
  const dist = new Float32Array(N).fill(Infinity);
  const prev = new Int32Array(N).fill(-1);
  const done = new Uint8Array(N);
  dist[from] = 0;
  for (;;) {
    let u = -1;
    let best = Infinity;
    for (let i = 0; i < N; i++) if (!done[i] && dist[i] < best) { best = dist[i]; u = i; }
    if (u < 0) return null;
    done[u] = 1;
    const reached = target !== null ? u === target : u === CORE_ID || (u !== from && p.joinable.has(u));
    if (reached) {
      const out: number[] = [];
      for (let c = u; c >= 0; c = prev[c]) out.push(c);
      return out.reverse();
    }
    for (const v of neighbours(u)) {
      if (done[v] || p.forbidden.has(v) || p.seals.has(edgeKey(u, v))) continue;
      const nd = dist[u] + p.cost[v] + (p.avoid.has(v) && coreDist(v) > 2 ? 2.5 : 0);
      if (nd < dist[v]) { dist[v] = nd; prev[v] = u; }
    }
  }
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

function edgeStart(m: number): Pt {
  const { x, y } = mxy(m);
  const cx = x * MACRO + MACRO / 2;
  const cy = y * MACRO + MACRO / 2;
  // pick the board edge this macro touches, furthest from the core
  const opts: Pt[] = [];
  if (x === 0) opts.push({ x: 0, y: cy });
  if (x === MACRO_W - 1) opts.push({ x: GRID_W, y: cy });
  if (y === 0) opts.push({ x: cx, y: 0 });
  if (y === MACRO_H - 1) opts.push({ x: cx, y: GRID_H });
  opts.sort((a, b) => Math.hypot(b.x - CORE_PT.x, b.y - CORE_PT.y) - Math.hypot(a.x - CORE_PT.x, a.y - CORE_PT.y));
  return opts[0];
}

export class Board {
  readonly b: number;
  readonly seed: number;
  height = new Int8Array(GRID_W * GRID_H);
  road = new Uint8Array(GRID_W * GRID_H);
  ore = new Uint8Array(GRID_W * GRID_H); // vein index + 1
  veins: Pt[] = [];
  paths: PathState[] = [];
  branches: number[][] = [];
  seals = new Set<number>();
  routes: Route[] = [];
  minLength: number;
  private cost: Float32Array;
  private rng: Rng;

  constructor(seed: number, b: number) {
    this.seed = seed;
    this.b = b;
    this.rng = new Rng(subSeed(seed, 101, b));
    this.minLength = ROAD.minLenBase - ROAD.minLenPerBoard * b + this.rng.int(-ROAD.minLenJitter, ROAD.minLenJitter);
    this.cost = new Float32Array(MACRO_W * MACRO_H);
    this.planRoads();
    this.makeTerrain();
  }

  // ------------------------------------------------------------- roads
  private planRoads() {
    const n = INGRESS_BY_BOARD[this.b - 1];
    let best: { paths: PathState[]; cost: Float32Array; score: number } | null = null;
    for (let attempt = 0; attempt < ROAD.attempts; attempt++) {
      const rng = new Rng(subSeed(this.seed, 202, this.b, attempt));
      const field = spiralField(rng);
      const cost = new Float32Array(field.length);
      for (let m = 0; m < cost.length; m++) cost[m] = 1 + ROAD.spiralK * field[m] + rng.range(0, ROAD.noise);
      const edgeCells: number[] = [];
      for (let m = 0; m < cost.length; m++) {
        const p = mxy(m);
        if ((p.x === 0 || p.y === 0 || p.x === MACRO_W - 1 || p.y === MACRO_H - 1) && coreDist(m) >= 3) edgeCells.push(m);
      }
      rng.shuffle(edgeCells);
      const chosen: number[] = [];
      for (const m of edgeCells) {
        if (chosen.length >= n) break;
        const p = mxy(m);
        if (chosen.every((c) => { const q = mxy(c); return Math.abs(q.x - p.x) + Math.abs(q.y - p.y) >= 5; })) chosen.push(m);
      }
      if (chosen.length < n) continue;
      const paths: PathState[] = [];
      const used = new Set<number>();
      let ok = true;
      for (const ing of chosen) {
        const avoid = new Set<number>();
        for (const u of used) for (const v of neighbours(u)) avoid.add(v);
        // walk via a waypoint on the far side of the core so the road curls around it
        const path = this.curlRoute(ing, cost, used, avoid, rng);
        if (!path || hasHairpin(path)) { ok = false; break; }
        const join = path[path.length - 1] !== CORE_ID ? path[path.length - 1] : null;
        paths.push({ ingressMacro: ing, start: edgeStart(ing), path, revealed: 1, joinsAt: join });
        for (const c of path) if (c !== CORE_ID) used.add(c);
      }
      if (!ok) continue;
      const lens = paths.map((p) => this.pathLength(p, paths));
      const shortest = Math.min(...lens);
      const score = shortest >= this.minLength ? 1000 - Math.abs(shortest - this.minLength - 15) : shortest;
      if (!best || score > best.score) best = { paths, cost, score };
      if (shortest >= this.minLength && shortest <= this.minLength + 40) break;
    }
    if (!best) throw new Error('road generation failed');
    this.paths = best.paths;
    this.cost = best.cost;
  }

  private curlRoute(ing: number, cost: Float32Array, used: Set<number>, avoid: Set<number>, rng: Rng): number[] | null {
    const base: RoadParams = { cost, seals: this.seals, forbidden: new Set(), joinable: used, avoid };
    const direct = routeMacro(ing, base);
    if (!direct) return null;
    if (direct.length * MACRO >= this.minLength || used.size > 0) return direct;
    // pick a waypoint around the core on the opposite side from the ingress
    const ip = mxy(ing);
    const ang = Math.atan2(ip.y - CORE_MACRO.y, ip.x - CORE_MACRO.x) + Math.PI + rng.range(-0.9, 0.9);
    const r = rng.range(2, 3.2);
    const wx = Math.max(0, Math.min(MACRO_W - 1, Math.round(CORE_MACRO.x + r * Math.cos(ang))));
    const wy = Math.max(0, Math.min(MACRO_H - 1, Math.round(CORE_MACRO.y + r * Math.sin(ang))));
    const way = mid(wx, wy);
    if (way === CORE_ID || coreDist(way) < 2) return direct;
    const first = routeMacro(ing, { ...base, forbidden: new Set([CORE_ID]) }, way);
    if (!first) return direct;
    const forb = new Set(first.slice(0, -1));
    const second = routeMacro(way, { ...base, forbidden: forb });
    if (!second) return direct;
    return first.concat(second.slice(1));
  }

  /** Road length in cells for a path, following joins to the core. */
  pathLength(p: PathState, all: PathState[] = this.paths): number {
    let len = Math.hypot(p.start.x - (mxy(p.path[0]).x * MACRO + 4), p.start.y - (mxy(p.path[0]).y * MACRO + 4));
    len += (p.path.length - 1) * MACRO;
    if (p.joinsAt !== null) {
      const host = all.find((q) => q !== p && q.path.includes(p.joinsAt!));
      if (host) len += (host.path.length - 1 - host.path.indexOf(p.joinsAt)) * MACRO;
    }
    return len;
  }

  /** Total reveal length (macro steps) used to drive the lightning animation. */
  revealTotal(): number {
    return Math.max(...this.paths.map((p) => p.path.length));
  }

  /** BFS check: every head can still reach the core with these seals. */
  sealsValid(seals: Set<number>): boolean {
    for (const p of this.paths) {
      const head = p.path[Math.min(p.revealed, p.path.length) - 1];
      const blocked = new Set(p.path.slice(0, Math.max(0, p.revealed - 1)));
      const seen = new Set<number>([head]);
      const q = [head];
      let ok = false;
      while (q.length) {
        const u = q.shift()!;
        if (u === CORE_ID) { ok = true; break; }
        for (const v of neighbours(u)) {
          if (seen.has(v) || blocked.has(v) || seals.has(edgeKey(u, v))) continue;
          seen.add(v);
          q.push(v);
        }
      }
      if (!ok) return false;
    }
    return true;
  }

  /** May this edge take a seal? (not on the already revealed road) */
  sealAllowed(a: number, b: number): boolean {
    if (a === CORE_ID || b === CORE_ID) return false;
    for (const p of this.paths) {
      const rev = p.path.slice(0, p.revealed);
      for (let i = 0; i + 1 < rev.length; i++) if (edgeKey(rev[i], rev[i + 1]) === edgeKey(a, b)) return false;
    }
    const s = new Set(this.seals);
    s.add(edgeKey(a, b));
    return this.sealsValid(s);
  }

  /** After seals: detour around each sealed edge on the planned road, keeping the rest of its curl. */
  reroute() {
    for (let i = 0; i < this.paths.length; i++) {
      const p = this.paths[i];
      for (let guard = 0; guard < 8; guard++) {
        const k = p.path.findIndex((c, j) => j + 1 < p.path.length && this.seals.has(edgeKey(c, p.path[j + 1])));
        if (k < 0) break;
        const forbidden = new Set<number>([CORE_ID]);
        for (const q of this.paths) for (const c of q.path) forbidden.add(c);
        for (const br of this.branches) for (const c of br) forbidden.add(c);
        forbidden.delete(p.path[k]);
        forbidden.delete(p.path[k + 1]);
        const det = routeMacro(p.path[k], { cost: this.cost, seals: this.seals, forbidden, joinable: new Set(), avoid: new Set() }, p.path[k + 1]);
        if (!det) { this.rerouteFromHeads(); return; }
        p.path = p.path.slice(0, k).concat(det, p.path.slice(k + 2));
      }
    }
  }

  private rerouteFromHeads() {
    const fixed = new Set<number>();
    for (const p of this.paths) for (const c of p.path.slice(0, p.revealed)) if (c !== CORE_ID) fixed.add(c);
    const used = new Set<number>();
    for (let i = 0; i < this.paths.length; i++) {
      const p = this.paths[i];
      if (p.revealed >= p.path.length) { for (const c of p.path) if (c !== CORE_ID) used.add(c); continue; }
      const head = p.path[p.revealed - 1];
      const prefix = p.path.slice(0, p.revealed);
      const forbidden = new Set<number>([...prefix.slice(0, -1)]);
      for (const c of fixed) if (!prefix.includes(c)) forbidden.add(c);
      const avoid = new Set<number>();
      for (const u of used) for (const v of neighbours(u)) avoid.add(v);
      const joinable = new Set([...used].filter((c) => !prefix.includes(c)));
      const rest = routeMacro(head, { cost: this.cost, seals: this.seals, forbidden, joinable, avoid });
      if (rest) {
        p.path = prefix.concat(rest.slice(1));
        p.joinsAt = p.path[p.path.length - 1] !== CORE_ID ? p.path[p.path.length - 1] : null;
      }
      for (const c of p.path) if (c !== CORE_ID) used.add(c);
    }
  }

  /** Finish the board after the reveal: forks, road cells, routes, ore. */
  finalize() {
    const rng = new Rng(subSeed(this.seed, 303, this.b));
    if (this.b >= ROAD.forkFromBoard) this.makeForks(rng);
    this.road.fill(0);
    const segs: [Pt, Pt][] = [];
    const centre = (m: number): Pt => ({ x: mxy(m).x * MACRO + 4, y: mxy(m).y * MACRO + 4 });
    for (const p of this.paths) {
      segs.push([p.start, centre(p.path[0])]);
      for (let i = 0; i + 1 < p.path.length; i++) segs.push([centre(p.path[i]), centre(p.path[i + 1])]);
    }
    for (const br of this.branches) for (let i = 0; i + 1 < br.length; i++) segs.push([centre(br[i]), centre(br[i + 1])]);
    for (const [a, b] of segs) {
      const x0 = Math.min(a.x, b.x), x1 = Math.max(a.x, b.x), y0 = Math.min(a.y, b.y), y1 = Math.max(a.y, b.y);
      for (let y = Math.floor(y0) - 1; y < Math.max(Math.ceil(y1), Math.floor(y0) + 1); y++)
        for (let x = Math.floor(x0) - 1; x < Math.max(Math.ceil(x1), Math.floor(x0) + 1); x++)
          if (inGrid(x, y)) this.road[cellIdx(x, y)] = 1;
    }
    // flatten terrain on and next to the road and around the core
    for (let y = 0; y < GRID_H; y++)
      for (let x = 0; x < GRID_W; x++) {
        let near = false;
        for (let dy = -1; dy <= 1 && !near; dy++)
          for (let dx = -1; dx <= 1; dx++) if (inGrid(x + dx, y + dy) && this.road[cellIdx(x + dx, y + dy)]) { near = true; break; }
        if (near || Math.hypot(x + 0.5 - CORE_PT.x, y + 0.5 - CORE_PT.y) < CORE_RADIUS + 2) this.height[cellIdx(x, y)] = 0;
      }
    this.buildRoutes();
    this.makeOre(rng);
  }

  private makeForks(rng: Rng) {
    const roadCells = new Set<number>();
    for (const p of this.paths) for (const c of p.path) roadCells.add(c);
    for (const p of this.paths) {
      let forks = 0;
      for (let i = 1; i < p.path.length - 4 && forks < 2; i++) {
        if (!rng.chance(ROAD.forkP * 2.5)) continue; // per-step chance boosted: most steps cannot fork
        const j = Math.min(p.path.length - 2, i + rng.int(3, 5));
        if (j - i < 3) continue;
        const forbidden = new Set<number>([...roadCells, CORE_ID]);
        forbidden.delete(p.path[i]);
        forbidden.delete(p.path[j]);
        for (const br of this.branches) for (const c of br) forbidden.add(c);
        const br = routeMacro(p.path[i], { cost: this.cost, seals: this.seals, forbidden, joinable: new Set(), avoid: new Set() }, p.path[j]);
        if (!br || br.length - 1 > (j - i) * 2 + 3 || br.length - 1 < j - i + 2) continue;
        if (br.some((c) => coreDist(c) < 1)) continue;
        this.branches.push(br);
        for (const c of br) roadCells.add(c);
        forks++;
        i = j;
      }
    }
  }

  private buildRoutes() {
    const next = new Map<number, number[]>();
    const add = (a: number, b: number) => {
      const l = next.get(a) ?? [];
      if (!l.includes(b)) l.push(b);
      next.set(a, l);
    };
    for (const p of this.paths) for (let i = 0; i + 1 < p.path.length; i++) add(p.path[i], p.path[i + 1]);
    for (const br of this.branches) for (let i = 0; i + 1 < br.length; i++) add(br[i], br[i + 1]);
    this.routes = [];
    this.paths.forEach((p, ingress) => {
      const found: number[][] = [];
      const dfs = (c: number, acc: number[], seen: Set<number>) => {
        if (found.length >= 16) return;
        if (c === CORE_ID) { found.push(acc.slice()); return; }
        for (const n of next.get(c) ?? []) {
          if (seen.has(n)) continue;
          seen.add(n); acc.push(n);
          dfs(n, acc, seen);
          acc.pop(); seen.delete(n);
        }
      };
      dfs(p.path[0], [p.path[0]], new Set([p.path[0]]));
      for (const macros of found) {
        const pts: Pt[] = [p.start, ...macros.map((m) => ({ x: mxy(m).x * MACRO + 4, y: mxy(m).y * MACRO + 4 }))];
        this.routes.push(makeRoute(ingress, pts));
      }
    });
  }

  // ------------------------------------------------------------- terrain & ore
  private makeTerrain() {
    const rng = new Rng(subSeed(this.seed, 404, this.b));
    const planned = new Set<number>();
    for (const p of this.paths) for (const c of p.path) { planned.add(c); }
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

  private makeOre(rng: Rng) {
    const n = rng.int(ORE.min, ORE.max);
    this.veins = [];
    this.ore.fill(0);
    for (let tries = 0; tries < 400 && this.veins.length < n; tries++) {
      const x = rng.int(1, GRID_W - ORE.size - 1);
      const y = rng.int(1, GRID_H - ORE.size - 1);
      let ok = Math.hypot(x - CORE_PT.x, y - CORE_PT.y) > 10;
      for (let dy = -2; dy < ORE.size + 2 && ok; dy++)
        for (let dx = -2; dx < ORE.size + 2; dx++) {
          const cx = x + dx, cy = y + dy;
          if (!inGrid(cx, cy)) continue;
          if (this.road[cellIdx(cx, cy)] || this.ore[cellIdx(cx, cy)]) { ok = false; break; }
        }
      // keep veins within reach of the road so harvesters sit in the action
      let nearRoad = false;
      for (let dy = -10; dy < 13 && ok && !nearRoad; dy++)
        for (let dx = -10; dx < 13; dx++) if (inGrid(x + dx, y + dy) && this.road[cellIdx(x + dx, y + dy)]) { nearRoad = true; break; }
      if (!ok || !nearRoad) continue;
      this.veins.push({ x, y });
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
  let i = 1;
  // binary search segment
  let lo = 1, hi = r.cum.length - 1;
  while (lo < hi) {
    const m = (lo + hi) >> 1;
    if (r.cum[m] < d) lo = m + 1; else hi = m;
  }
  i = lo;
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
