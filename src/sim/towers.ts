// Tower recipes, shape analysis and stat computation.
import {
  FIB, MASS_EXP, MAX_STORIES, RESONANCE, RISE_RANGE, SHAPE, STORY, TOWERS, TRAITS, GLYPHS,
  type TowerType,
} from '../balance';
import { type Cell, type Family, type Piece, type PieceColor, FAMILIES, familyOf, isCap } from './pieces';

// ------------------------------------------------------------------ recipes
const PAIR: Record<Family, Partial<Record<Family, TowerType>>> = {
  Hook:  { Block: 'Gun', Bar: 'Rifle', Tee: 'Machine Gun', Skew: 'Machine Gun' },
  Block: { Hook: 'Missile', Bar: 'Missile', Tee: 'Bomb', Skew: 'Bomb' },
  Bar:   { Hook: 'Laser', Block: 'Laser', Tee: 'Lightning', Skew: 'Pulsar' },
  Tee:   { Hook: 'Freezer', Block: 'E-Field', Bar: 'E-Field', Skew: 'Freezer' },
  Skew:  { Hook: 'Flamer', Block: 'Acid', Bar: 'Flamer', Tee: 'Virus' },
};
const PURE: Record<Family, TowerType> = { Hook: 'Machine Gun', Block: 'Bomb', Bar: 'Pulsar', Tee: 'Freezer', Skew: 'Acid' };
const TRIPLE: Record<string, TowerType> = {
  'Hook+Block+Bar': 'Rifle', 'Hook+Block+Tee': 'Missile', 'Hook+Block+Skew': 'Virus',
  'Hook+Bar+Tee': 'Lightning', 'Hook+Bar+Skew': 'Pulsar', 'Hook+Tee+Skew': 'Gun',
  'Block+Bar+Tee': 'E-Field', 'Block+Bar+Skew': 'Bomb', 'Block+Tee+Skew': 'Acid', 'Bar+Tee+Skew': 'Laser',
};
const famIdx = (f: Family) => FAMILIES.indexOf(f);

/** Resolve golden wildcards: they take the most common real family among the others. */
export function resolveFamilies(pieces: Piece[]): Family[] {
  const real = pieces.filter((p) => !p.golden).map((p) => familyOf(p)!);
  let wild: Family = 'Hook';
  if (real.length) {
    const counts = new Map<Family, number>();
    for (const f of real) counts.set(f, (counts.get(f) ?? 0) + 1);
    wild = real.reduce((a, f) => ((counts.get(f)! > counts.get(a)!) ? f : a), real[0]);
  }
  return pieces.map((p) => (p.golden ? wild : familyOf(p)!));
}

export function recipe(fams: Family[]): { type: TowerType; pure: boolean; hint: string } {
  const [a, b, c] = fams;
  if (a === b && b === c) return { type: PURE[a], pure: true, hint: `3 ${a} = ${PURE[a]} ★` };
  if (a === b || a === c || b === c) {
    const pair = a === b || a === c ? a : b;
    const odd = fams.find((f) => f !== pair)!;
    const t = PAIR[pair][odd]!;
    return { type: t, pure: false, hint: `2 ${pair} + ${odd} = ${t}` };
  }
  const key = [...fams].sort((x, y) => famIdx(x) - famIdx(y)).join('+');
  return { type: TRIPLE[key], pure: false, hint: `${key.replace(/\+/g, ' + ')} = ${TRIPLE[key]}` };
}

/** Every recipe as [families, tower] for the recipe book. */
export function allRecipes(): { fams: Family[]; type: TowerType; pure: boolean; hint: string }[] {
  const out: { fams: Family[]; type: TowerType; pure: boolean; hint: string }[] = [];
  for (const f of FAMILIES) out.push({ fams: [f, f, f], ...recipe([f, f, f]) });
  for (const p of FAMILIES) for (const o of FAMILIES) if (p !== o) out.push({ fams: [p, p, o], ...recipe([p, p, o]) });
  for (let i = 0; i < 5; i++) for (let j = i + 1; j < 5; j++) for (let k = j + 1; k < 5; k++) {
    const fams = [FAMILIES[i], FAMILIES[j], FAMILIES[k]];
    out.push({ fams, ...recipe(fams) });
  }
  return out;
}

// ------------------------------------------------------------------ shapes
export interface ShapeInfo {
  w: number; h: number; cells: number;
  holes: Cell[];
  golden: boolean; mirror: boolean; rotational: boolean; perfect: boolean;
  surface: number; // rate-of-fire modifier
}

export function analyseShape(cells: Cell[]): ShapeInfo {
  const xs = cells.map((c) => c[0]), ys = cells.map((c) => c[1]);
  const x0 = Math.min(...xs), y0 = Math.min(...ys);
  const w = Math.max(...xs) - x0 + 1, h = Math.max(...ys) - y0 + 1;
  const set = new Set(cells.map(([x, y]) => (y - y0) * 64 + (x - x0)));
  const has = (x: number, y: number) => set.has(y * 64 + x);
  // holes: empty cells in the bbox not reachable from outside
  const outside = new Set<number>();
  const q: Cell[] = [];
  for (let x = -1; x <= w; x++) { q.push([x, -1]); q.push([x, h]); }
  for (let y = 0; y < h; y++) { q.push([-1, y]); q.push([w, y]); }
  const key = (x: number, y: number) => (y + 1) * 80 + (x + 1);
  for (const [x, y] of q) outside.add(key(x, y));
  while (q.length) {
    const [x, y] = q.pop()!;
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const nx = x + dx, ny = y + dy;
      if (nx < -1 || ny < -1 || nx > w || ny > h) continue;
      const k = key(nx, ny);
      if (outside.has(k) || has(nx, ny)) continue;
      outside.add(k);
      q.push([nx, ny]);
    }
  }
  const holes: Cell[] = [];
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (!has(x, y) && !outside.has(key(x, y))) holes.push([x + x0, y + y0]);
  let mx = true, my = true, rot = true;
  for (const c of set) {
    const x = c % 64, y = Math.floor(c / 64);
    if (!has(w - 1 - x, y)) mx = false;
    if (!has(x, h - 1 - y)) my = false;
    if (!has(w - 1 - x, h - 1 - y)) rot = false;
  }
  const ratio = Math.max(w, h) / Math.min(w, h);
  let perim = 0;
  for (const c of set) {
    const x = c % 64, y = Math.floor(c / 64);
    if (!has(x + 1, y)) perim++;
    if (!has(x - 1, y)) perim++;
    if (!has(x, y + 1)) perim++;
    if (!has(x, y - 1)) perim++;
  }
  const minPerim = 2 * Math.ceil(2 * Math.sqrt(cells.length));
  const surface = Math.max(-SHAPE.surfaceMax, Math.min(SHAPE.surfaceMax, (perim / minPerim - 1.2) * 0.35));
  return {
    w, h, cells: cells.length, holes,
    golden: ratio >= SHAPE.goldenMin && ratio <= SHAPE.goldenMax,
    mirror: mx || my, rotational: rot, perfect: set.size === w * h && cells.length >= 4,
    surface,
  };
}

const FIB_UNIQ = [...new Set(FIB)];
export function isFibSpire(counts: number[]): boolean {
  if (counts.length < 3) return false;
  for (let i = 0; i + 1 < counts.length; i++) {
    const a = FIB_UNIQ.indexOf(counts[i]), b = FIB_UNIQ.indexOf(counts[i + 1]);
    if (a < 0 || b < 0 || a !== b + 1) return false;
  }
  return true;
}

// ------------------------------------------------------------------ towers
export interface PlacedPiece { piece: Piece; cells: Cell[]; layer: number }

export interface TowerStats {
  damage: number; interval: number; range: number; area: number; maxTargets: number;
  dps: number;
  pierce: number; chain: number; critChance: number; slowOnHit: number; essenceMult: number;
  slowTrait: number; dotTrait: number;
  color: PieceColor | null; resonance: PieceColor | null;
  spire: boolean; pure: boolean;
  stories: number;
  bonuses: { key: string; label: string; good: boolean }[];
  shape: ShapeInfo;
  hint: string;
}

export interface Tower {
  id: number;
  pieces: PlacedPiece[];
  layers: Cell[][];
  height: number;
  type: TowerType | null;
  hint: string;
  active: boolean;
  activateT: number;
  cx: number; cy: number;
  stats: TowerStats | null;
  cooldown: number;
  targetId: number;
  angle: number;
  rampTarget: number; rampT: number;
  shots: number;
  kills: number;
  fireFlash: number;
  baseTower?: boolean;
}

export interface StatContext {
  powerStation: number; // energy damage bonus (0 if none)
  goldenBase: boolean;
}

export function towerFamilies(t: Tower): Family[] {
  const core = t.pieces.filter((p) => p.layer === 0 && !isCap(p.piece.kind));
  return resolveFamilies(core.slice(0, 3).map((p) => p.piece));
}

export function majorityColor(pieces: Piece[]): { color: PieceColor | null; resonance: PieceColor | null } {
  const counts: Record<PieceColor, number> = { red: 0, gold: 0, green: 0, blue: 0 };
  let wild = 0;
  for (const p of pieces) (p.golden ? wild++ : counts[p.color]++);
  const sorted = (Object.keys(counts) as PieceColor[]).sort((a, b) => counts[b] - counts[a]);
  const top = sorted[0];
  // golden pieces count as any colour, so they break ties toward the leader
  const color = counts[top] + wild > counts[sorted[1]] ? top : null;
  const nonZero = sorted.filter((c) => counts[c] > 0);
  const resonance = pieces.length >= 3 && nonZero.length === 1 ? nonZero[0] : null;
  return { color, resonance };
}

export function computeStats(t: Tower, ctx: StatContext): TowerStats | null {
  if (!t.type) return null;
  const def = TOWERS[t.type];
  const ground = t.pieces.filter((p) => p.layer === 0);
  const groundCore = ground.filter((p) => !isCap(p.piece.kind));
  const groundCaps = ground.length - groundCore.length;
  const fams = towerFamilies(t);
  const { pure, hint } = recipe(fams);
  const shape = analyseShape(t.layers[0]);
  const bonuses: TowerStats['bonuses'] = [];

  // mass and family traits from extra core pieces
  const n = Math.max(3, groundCore.length + 0.5 * groundCaps);
  let dmg = Math.pow(n / 3, MASS_EXP);
  let rate = 1, rangeMul = 1, slowTrait = 0, dotTrait = 0;
  const extra = resolveFamilies(groundCore.slice(3).map((p) => p.piece));
  for (const f of extra) {
    if (f === 'Hook') rate += TRAITS.Hook;
    if (f === 'Block') dmg *= 1 + TRAITS.Block;
    if (f === 'Bar') rangeMul += TRAITS.Bar;
    if (f === 'Tee') slowTrait += TRAITS.Tee;
    if (f === 'Skew') dotTrait += TRAITS.Skew;
  }
  if (n > 3) bonuses.push({ key: 'mass', label: `Mass ×${Math.pow(n / 3, MASS_EXP).toFixed(2)}`, good: true });

  if (shape.holes.length) {
    dmg *= Math.max(0.3, 1 + SHAPE.hole * shape.holes.length);
    bonuses.push({ key: 'holes', label: `${shape.holes.length} hole${shape.holes.length > 1 ? 's' : ''} −${shape.holes.length * 10}% damage`, good: false });
  }
  if (shape.golden) { rangeMul += SHAPE.golden; bonuses.push({ key: 'golden', label: 'Golden footprint +10% range', good: true }); }
  if (shape.mirror) { rate += SHAPE.mirror; bonuses.push({ key: 'mirror', label: 'Mirror symmetry +15% rate', good: true }); }
  if (shape.rotational) { dmg *= 1 + SHAPE.rotational; bonuses.push({ key: 'rot', label: 'Rotational symmetry +15% damage', good: true }); }
  if (shape.perfect) {
    dmg *= 1 + SHAPE.perfect; rate += SHAPE.perfect; rangeMul += SHAPE.perfect;
    bonuses.push({ key: 'perfect', label: 'Perfect Block +25% everything', good: true });
  }
  rate += shape.surface;
  if (Math.abs(shape.surface) > 0.01)
    bonuses.push({ key: 'surface', label: `Surface ${shape.surface > 0 ? '+' : '−'}${Math.round(Math.abs(shape.surface) * 100)}% rate`, good: shape.surface > 0 });

  // stories (pure towers get one free)
  const stories = Math.min(MAX_STORIES + 1, t.layers.length + (pure ? 1 : 0));
  dmg *= Math.pow(STORY.damage, stories - 1);
  rangeMul += STORY.range * (stories - 1);
  if (pure) bonuses.push({ key: 'pure', label: 'Pure tower: +1 free story', good: true });
  const spire = isFibSpire(t.layers.map((l) => l.length));
  if (spire) bonuses.push({ key: 'spire', label: 'Fibonacci Spire: every 13th shot ×φ²', good: true });

  // glyphs
  let pierce = 0, chain = 0, crit = 0, slowOnHit = 0, essenceMult = 1;
  for (const p of t.pieces) {
    switch (p.piece.glyph) {
      case 'range': rangeMul += GLYPHS.range; break;
      case 'damage': dmg *= 1 + GLYPHS.damage; break;
      case 'rate': rate += GLYPHS.rate; break;
      case 'pierce': pierce += GLYPHS.pierce; break;
      case 'chain': chain += GLYPHS.chain; break;
      case 'crit': crit += GLYPHS.critChance; break;
      case 'slow': slowOnHit = GLYPHS.slowOnHit; break;
      case 'essence': essenceMult = 2; break;
    }
  }
  if (def.energy && ctx.powerStation > 0) dmg *= 1 + ctx.powerStation;
  if (ctx.goldenBase) dmg *= 1.08;

  const { color, resonance } = majorityColor(t.pieces.map((p) => p.piece));
  if (resonance) {
    const txt = { red: 'burn splash', gold: `ricochet to ${RESONANCE.ricochet} more`, blue: '3-cell splash', green: 'poison spreads on kill' }[resonance];
    bonuses.push({ key: 'res', label: `Resonance: ${txt}`, good: true });
  }
  const range = def.range * rangeMul + (t.height > 0 ? t.height * RISE_RANGE : 0);
  const interval = def.interval / rate;
  const damage = def.dps * def.interval * dmg;
  return {
    damage, interval, range, area: def.area, maxTargets: def.maxTargets,
    dps: damage / interval,
    pierce, chain, critChance: crit, slowOnHit, essenceMult, slowTrait, dotTrait,
    color, resonance, spire, pure, stories, bonuses, shape, hint,
  };
}

export function bbox(cells: Cell[]) {
  const xs = cells.map((c) => c[0]), ys = cells.map((c) => c[1]);
  return { x0: Math.min(...xs), y0: Math.min(...ys), x1: Math.max(...xs), y1: Math.max(...ys) };
}
