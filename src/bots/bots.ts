// Headless bot players for the balance harness.
import { BASE_SQUARES, BUILDINGS, TOWERS, type BuildingId } from '../balance';
import { canBuild } from '../sim/base';
import { type Game, type Preview, type Source } from '../sim/game';
import { cellIdx, inGrid, routeAt } from '../sim/map';
import { type Orient, type Piece, isCap, placedCells } from '../sim/pieces';
import { Rng } from '../sim/rng';
import { type Tower } from '../sim/towers';
import { type Suit } from '../sim/waves';

export type Skill = 'novice' | 'average' | 'expert';
export const SKILLS: Record<Skill, { waste: number; colour: number; stack: number; spot: 'random' | 'decent' | 'spiral'; maxMass: number; holes: boolean }> = {
  novice: { waste: 0.25, colour: 0, stack: 0, spot: 'random', maxMass: 4, holes: true },
  average: { waste: 0.1, colour: 0.45, stack: 0.1, spot: 'decent', maxMass: 6, holes: false },
  expert: { waste: 0, colour: 0.7, stack: 0.3, spot: 'spiral', maxMass: 8, holes: false },
};
const ORIENTS: Orient[] = [0, 1, 2, 3].flatMap((rot) => [{ rot, mirror: false }, { rot, mirror: true }]);
const WEAK: Record<Suit, string> = { hearts: 'green', clubs: 'red', diamonds: 'blue', spades: 'gold' };
const BUILD_PRIORITY: BuildingId[] = ['blastDoor', 'beacon', 'powerStation', 'harvesterHub', 'missileBattery', 'research', 'recycler', 'factory', 'smite', 'shapeFactory'];

interface Spot { x: number; y: number; score: number }

export class Bot {
  game: Game;
  skill: Skill;
  rng: Rng;
  private spots: Spot[] = [];
  private spotsFor = -1;
  private cooldown = 0;

  constructor(game: Game, skill: Skill, seed: number) {
    this.game = game;
    this.skill = skill;
    this.rng = new Rng(seed);
  }

  /** Call once per sim step. */
  act() {
    const g = this.game;
    if (g.phase === 'reveal') { if (g.revealPaused) g.continueReveal(); return; }
    if (g.phase === 'cleared') { g.enterBase(); return; }
    if (g.phase === 'base') { this.shop(); g.nextBoard(); return; }
    if (g.phase !== 'calm' && g.phase !== 'wave') return;
    if (this.spotsFor !== g.boardNo * 1000 + g.attempt) this.findSpots();
    if (--this.cooldown > 0) return;
    this.cooldown = this.skill === 'novice' ? 30 : 12; // novices are slower to act
    if (g.canSmite()) this.smite();
    const src = this.nextSource();
    if (src) { this.placeOne(src); return; }
    if (g.phase === 'calm') g.ready();
  }

  private nextSource(): Source | null {
    const g = this.game;
    if (g.must.length) return { zone: 'must', index: 0 };
    const i = g.may.findIndex((p) => p);
    if (i >= 0) return { zone: 'may', index: i };
    if (g.hold) return { zone: 'hold', index: 0 };
    return null;
  }

  // ------------------------------------------------------------ spot finding
  private findSpots() {
    const g = this.game;
    this.spotsFor = g.boardNo * 1000 + g.attempt;
    const samples: { x: number; y: number; w: number }[] = [];
    for (const r of g.board.routes)
      for (let d = 0; d < r.length; d += 2) {
        const p = routeAt(r, d);
        const late = d / r.length;
        samples.push({ x: p.x, y: p.y, w: this.skill === 'expert' ? 0.6 + late : 1 });
      }
    const spots: Spot[] = [];
    for (let y = 2; y < 62; y += 3)
      for (let x = 2; x < 102; x += 3) {
        if (g.board.isRoad(x, y) || g.board.isCoreCell(x, y) || g.board.ore[cellIdx(x, y)]) continue;
        let near = false;
        for (let dy = -2; dy <= 2 && !near; dy++) for (let dx = -2; dx <= 2; dx++) if (inGrid(x + dx, y + dy) && g.board.isRoad(x + dx, y + dy)) { near = true; break; }
        if (near) continue;
        let score = 0;
        for (const s of samples) if (Math.hypot(s.x - x, s.y - y) < 14) score += s.w;
        score += Math.max(0, g.board.h(x, y)) * 2;
        if (score > 0) spots.push({ x, y, score });
      }
    spots.sort((a, b) => b.score - a.score);
    this.spots = spots;
  }

  private pickSpot(): Spot | null {
    const g = this.game;
    const free = this.spots.filter((s) => !g.towers.some((t) => Math.hypot(t.cx - s.x, t.cy - s.y) < 6) && !g.objAt[cellIdx(s.x, s.y)]);
    if (!free.length) return null;
    if (this.skill === 'novice') return this.rng.pick(free);
    if (this.skill === 'average') return this.rng.pick(free.slice(0, Math.max(1, Math.ceil(free.length * 0.25))));
    return free[Math.min(free.length - 1, this.rng.int(0, 2))];
  }

  // ------------------------------------------------------------ placement
  private placeOne(src: Source) {
    const g = this.game;
    const piece = g.getPiece(src)!;
    const cfg = SKILLS[this.skill];
    if (this.rng.chance(cfg.waste)) { this.discard(src); return; }
    const towers = g.towers.filter((t) => !t.baseTower);
    // 1. stories
    if (this.rng.chance(cfg.stack) || (isCap(piece.kind) && cfg.stack > 0)) {
      const ts = towers.filter((t) => t.active).sort((a, b) => (b.stats?.dps ?? 0) - (a.stats?.dps ?? 0));
      for (const t of ts) {
        const pv = this.bestOn(t, piece, 'story');
        if (pv && this.commit(src, pv)) return;
      }
    }
    // 2. finish an unfinished pile
    const piles = towers.filter((t) => !t.type);
    if (piles.length) {
      for (const t of piles) {
        const pv = this.bestOn(t, piece, 'tower');
        if (pv && this.commit(src, pv)) return;
      }
    }
    // 3. caps: harvest or mass
    if (isCap(piece.kind) && this.harvest(src, piece)) return;
    // 4. mass on an existing tower (colour-aware for skilled bots)
    const massTargets = towers.filter((t) => t.active && t.pieces.filter((p) => p.layer === 0).length < cfg.maxMass);
    const wantColour = this.rng.chance(cfg.colour) && piece.color === WEAK[g.dominant];
    if (massTargets.length && (this.rng.chance(0.45) || wantColour)) {
      const sorted = massTargets.sort((a, b) => {
        const ca = wantColour && a.stats?.color === piece.color ? -10 : 0;
        const cb = wantColour && b.stats?.color === piece.color ? -10 : 0;
        return ca - cb || (b.stats?.dps ?? 0) - (a.stats?.dps ?? 0);
      });
      for (const t of sorted.slice(0, 4)) {
        const pv = this.bestOn(t, piece, 'tower');
        if (pv && this.commit(src, pv)) return;
      }
    }
    // 5. new tower
    for (let tries = 0; tries < 6; tries++) {
      const spot = this.pickSpot();
      if (!spot) break;
      for (const o of ORIENTS) {
        const pv = g.preview(piece, o, spot.x, spot.y);
        if (pv.ok && pv.kind === 'tower' && pv.towerId === undefined) { if (this.commitAt(src, o, spot.x, spot.y)) return; }
      }
      this.spots = this.spots.filter((s) => s !== spot);
    }
    // 6. anything legal: harvester, mass, or a mine on the road
    if (this.harvest(src, piece)) return;
    for (const t of massTargets) {
      const pv = this.bestOn(t, piece, 'tower');
      if (pv && this.commit(src, pv)) return;
    }
    this.discard(src);
  }

  private harvest(src: Source, piece: Piece): boolean {
    const g = this.game;
    for (const v of g.board.veins)
      for (const o of ORIENTS)
        for (let dy = 0; dy < 3; dy++)
          for (let dx = 0; dx < 3; dx++) {
            const pv = g.preview(piece, o, v.x + dx, v.y + dy);
            if (pv.ok && pv.kind === 'harvester' && this.commitAt(src, o, v.x + dx, v.y + dy)) return true;
          }
    return false;
  }

  /** Best legal placement of a piece onto/next to a tower. */
  private bestOn(t: Tower, piece: Piece, kind: 'story' | 'tower'): (Preview & { o: Orient; cx: number; cy: number }) | null {
    const g = this.game;
    const cfg = SKILLS[this.skill];
    const ground = t.layers[0];
    const xs = ground.map((c) => c[0]), ys = ground.map((c) => c[1]);
    const x0 = Math.min(...xs) - 4, x1 = Math.max(...xs) + 4, y0 = Math.min(...ys) - 4, y1 = Math.max(...ys) + 4;
    let best: (Preview & { o: Orient; cx: number; cy: number }) | null = null;
    let bestScore = -Infinity;
    const top = t.layers[t.layers.length - 1];
    const own = new Set(ground.map(([x, y]) => cellIdx(x, y)));
    const topSet = new Set(top.map(([x, y]) => cellIdx(x, y)));
    for (const o of ORIENTS) {
      if (piece.kind === 'O' && o.rot + (o.mirror ? 1 : 0) > 0) continue;
      for (let cy = y0; cy <= y1; cy++)
        for (let cx = x0; cx <= x1; cx++) {
          // cheap pre-check before the full preview
          const cells = placedCells(piece.kind, o, cx, cy);
          if (kind === 'story') {
            if (!cells.every(([x, y]) => own.has(cellIdx(x, y)))) continue;
            if (!cells.some(([x, y]) => topSet.has(cellIdx(x, y)))) continue;
          } else {
            if (cells.some(([x, y]) => !inGrid(x, y) || own.has(cellIdx(x, y)))) continue;
            if (!cells.some(([x, y]) => own.has(cellIdx(x + 1, y)) || own.has(cellIdx(x - 1, y)) || own.has(cellIdx(x, y + 1)) || own.has(cellIdx(x, y - 1)))) continue;
          }
          const pv = g.preview(piece, o, cx, cy);
          if (!pv.ok || pv.kind !== kind || pv.towerId !== t.id || pv.mergeIds) continue;
          if (!cfg.holes && pv.holes.length) continue;
          let score = (pv.dps ?? 0) + pv.gained.length * 3 - pv.lost.length * 3;
          if (this.skill === 'novice') score = this.rng.next();
          if (score > bestScore) { bestScore = score; best = { ...pv, o, cx, cy }; }
        }
    }
    return best;
  }

  private commit(src: Source, pv: Preview & { o: Orient; cx: number; cy: number }) {
    return this.commitAt(src, pv.o, pv.cx, pv.cy);
  }
  private commitAt(src: Source, o: Orient, cx: number, cy: number): boolean {
    return this.game.place(src, o, cx, cy).ok;
  }

  private discard(src: Source) {
    const g = this.game;
    if (g.canRecycle()) { g.recycle(src); return; }
    if (src.zone === 'must') g.must.splice(src.index, 1);
    else if (src.zone === 'may') g.may[src.index] = null;
    else g.hold = null;
  }

  private smite() {
    const g = this.game;
    let best = null as null | { x: number; y: number; n: number };
    for (const e of g.enemies) {
      const n = g.enemies.filter((o) => Math.hypot(o.x - e.x, o.y - e.y) < 6).length;
      if (!best || n > best.n) best = { x: e.x, y: e.y, n };
    }
    if (best && best.n >= 5) g.smite(best.x, best.y);
  }

  private shop() {
    const g = this.game;
    g.convertOre();
    for (;;) {
      let bought = false;
      for (const id of BUILD_PRIORITY) {
        const sq = BASE_SQUARES.map((s, i) => ({ s, i }))
          .filter(({ i }) => !canBuild(g.base, i, id))
          .sort((a, b) => Math.abs(a.s.size - BUILDINGS[id].size) - Math.abs(b.s.size - BUILDINGS[id].size))[0];
        // skilled bots wait for an exact fit when the square is much too big
        if (!sq) continue;
        if (this.skill !== 'novice' && sq.s.size > BUILDINGS[id].size * 2 && g.boardNo < 5) continue;
        if (!g.build(sq.i, id)) { bought = true; break; }
      }
      if (!bought) break;
    }
  }
}

export { TOWERS };
