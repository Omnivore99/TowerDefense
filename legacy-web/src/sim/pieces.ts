// Piece set, orientations, families, colours, glyphs and the seeded piece stream.
import { CAP_CHANCE, GLYPH_ODDS, PIECE_WEIGHTS } from '../balance';
import { Rng } from './rng';

export type Cell = [number, number];
export type CoreKind = 'I' | 'O' | 'T' | 'S' | 'Z' | 'J' | 'L';
export type CapKind = 'c1' | 'c2' | 'c3' | 'cL';
export type PieceKind = CoreKind | CapKind;
export type Family = 'Hook' | 'Block' | 'Bar' | 'Tee' | 'Skew';
export const FAMILIES: Family[] = ['Hook', 'Block', 'Bar', 'Tee', 'Skew'];
export type PieceColor = 'red' | 'gold' | 'green' | 'blue';
export const COLORS: PieceColor[] = ['red', 'gold', 'green', 'blue'];
export type CommonGlyph = 'range' | 'damage' | 'rate' | 'pierce';
export type RareGlyph = 'chain' | 'crit' | 'slow' | 'essence';
export type Glyph = CommonGlyph | RareGlyph;
export const COMMON_GLYPHS: CommonGlyph[] = ['range', 'damage', 'rate', 'pierce'];
export const RARE_GLYPHS: RareGlyph[] = ['chain', 'crit', 'slow', 'essence'];
export const GLYPH_LABEL: Record<Glyph, string> = {
  range: '+Range', damage: '+Damage', rate: '+Rate', pierce: '+Pierce',
  chain: 'Chain', crit: 'Crit', slow: 'Slow on hit', essence: 'Double Essence',
};

export const SHAPES: Record<PieceKind, Cell[]> = {
  I: [[0, 0], [1, 0], [2, 0], [3, 0]],
  O: [[0, 0], [1, 0], [0, 1], [1, 1]],
  T: [[0, 0], [1, 0], [2, 0], [1, 1]],
  S: [[1, 0], [2, 0], [0, 1], [1, 1]],
  Z: [[0, 0], [1, 0], [1, 1], [2, 1]],
  J: [[0, 0], [0, 1], [1, 1], [2, 1]],
  L: [[2, 0], [0, 1], [1, 1], [2, 1]],
  c1: [[0, 0]],
  c2: [[0, 0], [1, 0]],
  c3: [[0, 0], [1, 0], [2, 0]],
  cL: [[0, 0], [0, 1], [1, 1]],
};

export const FAMILY_OF: Record<CoreKind, Family> = {
  I: 'Bar', O: 'Block', T: 'Tee', S: 'Skew', Z: 'Skew', J: 'Hook', L: 'Hook',
};
export const KINDS_OF_FAMILY: Record<Family, CoreKind[]> = {
  Hook: ['J', 'L'], Block: ['O'], Bar: ['I'], Tee: ['T'], Skew: ['S', 'Z'],
};
export const CAP_KINDS: CapKind[] = ['c1', 'c2', 'c3', 'cL'];

export interface Piece {
  id: number;
  kind: PieceKind;
  color: PieceColor;
  glyph: Glyph | null;
  golden: boolean;
}

export function isCap(k: PieceKind): k is CapKind {
  return k[0] === 'c';
}
export function familyOf(p: Piece): Family | null {
  if (isCap(p.kind)) return null;
  return FAMILY_OF[p.kind as CoreKind];
}

/** Orientation = rotation (0..3, clockwise quarter turns) and mirror flag. */
export interface Orient { rot: number; mirror: boolean }

export function orientCells(kind: PieceKind, o: Orient): Cell[] {
  let cells = SHAPES[kind].map(([x, y]) => [x, y] as Cell);
  if (o.mirror) cells = cells.map(([x, y]) => [-x, y]);
  for (let r = 0; r < ((o.rot % 4) + 4) % 4; r++) cells = cells.map(([x, y]) => [-y, x]);
  const mx = Math.min(...cells.map((c) => c[0]));
  const my = Math.min(...cells.map((c) => c[1]));
  return cells.map(([x, y]) => [x - mx, y - my]);
}

/** Cells of a piece placed so the cursor cell sits near the piece centre. */
export function placedCells(kind: PieceKind, o: Orient, cx: number, cy: number): Cell[] {
  const cells = orientCells(kind, o);
  const w = Math.max(...cells.map((c) => c[0])) + 1;
  const h = Math.max(...cells.map((c) => c[1])) + 1;
  const ox = cx - Math.floor((w - 1) / 2);
  const oy = cy - Math.floor((h - 1) / 2);
  return cells.map(([x, y]) => [x + ox, y + oy]);
}

/** Seeded piece stream. Each board gets its own stream so a seed reproduces the pieces. */
export class PieceStream {
  private rng: Rng;
  private nextId: number;
  /** Shape Factory: force the next core piece family. */
  forcedFamily: Family | null = null;
  constructor(seed: number, idBase = 1) {
    this.rng = new Rng(seed);
    this.nextId = idBase;
  }
  next(): Piece {
    const r = this.rng;
    // Roll every random value in a fixed order so forcing a family never shifts the stream.
    const capRoll = r.next();
    const kindW = r.weighted(PIECE_WEIGHTS) as CoreKind;
    const capKind = r.pick(CAP_KINDS);
    const color = r.pick(COLORS);
    const g = r.next();
    const common = r.pick(COMMON_GLYPHS);
    const rare = r.pick(RARE_GLYPHS);
    const famPick = r.next();
    let kind: PieceKind = capRoll < CAP_CHANCE ? capKind : kindW;
    if (this.forcedFamily) {
      const opts = KINDS_OF_FAMILY[this.forcedFamily];
      kind = opts[Math.floor(famPick * opts.length)];
      this.forcedFamily = null;
    }
    let glyph: Glyph | null = null;
    let golden = false;
    if (g < GLYPH_ODDS.golden && !isCap(kind)) golden = true;
    else if (g < GLYPH_ODDS.golden + GLYPH_ODDS.rare) glyph = rare;
    else if (g < GLYPH_ODDS.golden + GLYPH_ODDS.rare + GLYPH_ODDS.common) glyph = common;
    return { id: this.nextId++, kind, color, glyph, golden };
  }
  make(kind: PieceKind, color: PieceColor, glyph: Glyph | null = null, golden = false): Piece {
    return { id: this.nextId++, kind, color, glyph, golden };
  }
}
