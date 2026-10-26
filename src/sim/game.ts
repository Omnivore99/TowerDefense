// The whole game simulation: pure logic, fixed timestep, no rendering.
// Render, audio and UI read state and drain `events`; bots drive it headless.
import {
  ABILITIES, ARCH, BASE_INTEGRITY, BASE_SQUARES, BOARDS, BOARD_START_PIECES, BUILDINGS, BUILDING_FX,
  BURST_GAP, CALM_PIECES, COMBAT, COMBO, EARLY_CALL_BONUS, EARLY_CALL_WINDOW, GLYPHS, GRID_H, GRID_W,
  MACRO, MAX_GROUND_PIECES, MAX_STORIES, MAY_SLOTS, PHI, RESONANCE, REVEAL, ROAD_PIECES_PER_MACRO,
  SHAPE, SIM_HZ, SIZES, SUIT_MULT, TOWERS, WAVES_PER_BOARD, WAVE_PIECE_INTERVAL,
  type Ability, type Archetype, type BuildingId, type ModeId, type Size, type TowerType,
} from '../balance';
import { type BaseState, buildingMult, canBuild, goldenBase, hasBuilding, newBase } from './base';
import { Board, CORE_PT, cellIdx, edgeKey, inGrid, makeRoute, mid, routeAt, type Pt, type Route } from './map';
import {
  type Cell, type Family, type Orient, type Piece, type PieceColor, PieceStream, RARE_GLYPHS, COMMON_GLYPHS,
  isCap, placedCells,
} from './pieces';
import { Rng, subSeed } from './rng';
import { type PlacedPiece, type Tower, type TowerStats, analyseShape, bbox, computeStats, recipe, towerFamilies } from './towers';
import { type Suit, type WaveSpec, SUITS, dominantSuit, makeWave } from './waves';

export type Phase = 'reveal' | 'calm' | 'wave' | 'cleared' | 'base' | 'lost' | 'victory';

export interface Dot { kind: 'burn' | 'virus' | 'poison' | 'acid'; dps: number; t: number; tower: number }

export interface Enemy {
  id: number;
  size: Size;
  suit: Suit;
  arch: Archetype;
  ability: Ability | null;
  golden: boolean;
  boss: boolean;
  gen: number;
  hp: number; maxHp: number; shield: number;
  route: Route;
  overland: boolean;
  d: number;
  x: number; y: number; px: number; py: number; dir: number;
  speed: number;
  slowT: number; slowMult: number;
  dots: Dot[];
  animT: number;
  airborne: boolean; stretched: boolean; immune: boolean;
  abilityT: number;
  heraldBoost: boolean;
  chewing: number; // road piece id or 0
  lastTower: number;
  shed: number;
  alive: boolean;
  scale: number;
  hitFlash: number;
}

export interface Projectile {
  id: number;
  kind: 'bullet' | 'lob' | 'homing' | 'acid';
  x: number; y: number; px: number; py: number;
  sx: number; sy: number; // start (lobs)
  tx: number; ty: number;
  targetId: number;
  t: number; dur: number; // lob timing
  speed: number;
  damage: number;
  tower: number;
  color: PieceColor | null;
  alive: boolean;
}

export interface RoadPiece {
  id: number;
  kind: 'barrier' | 'mine';
  piece: Piece;
  cells: Cell[];
  macro: number;
  hp: number; maxHp: number; // barrier, in absolute HP
  mines: boolean[];
  entry: Map<Route, number>;
}
export interface Harvester { id: number; piece: Piece; cells: Cell[]; oreCells: number }
export interface Puddle { x: number; y: number; r: number; t: number; dps: number; tower: number; maxTargets: number }
export interface Tank { id: number; route: Route; d: number; x: number; y: number; px: number; py: number; dir: number; cd: number; alive: boolean }

export type GameEvent =
  | { t: 'place'; pieceId: number; cells: Cell[]; size: number; kind: Preview['kind']; towerId?: number; pieceCount?: number; color: PieceColor }
  | { t: 'activate'; towerId: number; type: TowerType }
  | { t: 'bonus'; towerId: number; label: string; key: string }
  | { t: 'shot'; towerId: number; kind: string; x1: number; y1: number; x2: number; y2: number; color: PieceColor | null }
  | { t: 'bolt'; x1: number; y1: number; x2: number; y2: number; miss: boolean }
  | { t: 'hit'; x: number; y: number; amount: number; crit: boolean }
  | { t: 'explode'; x: number; y: number; r: number; color: PieceColor | null }
  | { t: 'kill'; x: number; y: number; size: Size; suit: Suit; arch: Archetype; split: boolean; essence: number }
  | { t: 'combo'; n: number; x: number; y: number }
  | { t: 'leak'; dmg: number; x: number; y: number }
  | { t: 'mine'; x: number; y: number }
  | { t: 'parry'; x: number; y: number }
  | { t: 'immune'; x: number; y: number }
  | { t: 'piece'; zone: 'must' | 'may' }
  | { t: 'phase'; phase: Phase }
  | { t: 'waveStart'; index: number }
  | { t: 'waveEnd'; index: number }
  | { t: 'seal'; a: number; b: number }
  | { t: 'sealReject'; a: number; b: number }
  | { t: 'reject'; reason: string }
  | { t: 'smite'; x: number; y: number; r: number }
  | { t: 'early' }
  | { t: 'recycle'; essence: number }
  | { t: 'build'; square: number; id: BuildingId }
  | { t: 'barrierBreak'; x: number; y: number }
  | { t: 'revealPause' }
  | { t: 'revealDone' }
  | { t: 'ore'; amount: number };

export interface Source { zone: 'must' | 'may' | 'hold'; index: number }

export interface Preview {
  ok: boolean;
  reason?: string;
  cells: Cell[];
  kind: 'tower' | 'story' | 'harvester' | 'barrier' | 'mine' | 'invalid';
  towerId?: number;
  mergeIds?: number[];
  layer?: number;
  resultType?: TowerType | null;
  needs?: number;
  hint?: string;
  gained: string[];
  lost: string[];
  holes: Cell[];
  dps?: number;
  range?: number;
}

export interface BoardMetrics {
  board: number; attempt: number; cleared: boolean; baseLost: number; integrity: number;
  waveTime: number; dangerTime: number; maxBacklog: number; backlogOver2: number;
  combosPeak: number; kills: number; leaks: number; earlyCalls: number; piecesPlaced: number;
}

export interface Settings { volume: number; reducedMotion: boolean; showRanges: boolean; speed: number }

const DT = 1 / SIM_HZ;
const SUIT_WEAK: Record<Suit, PieceColor> = { hearts: 'green', clubs: 'red', diamonds: 'blue', spades: 'gold' };
const SUIT_RESIST: Record<Suit, PieceColor> = { hearts: 'red', clubs: 'green', diamonds: 'gold', spades: 'blue' };

export class Game {
  seed: number;
  mode: ModeId;
  boardNo = 1;
  attempt = 1;
  phase: Phase = 'reveal';
  base: BaseState;
  baseSnapshot: BaseState;
  board!: Board;
  time = 0;
  phaseT = 0;
  tutorial: { step: number; text: string } | null = null;
  tutorialEnabled: boolean;
  discovered = new Set<TowerType>();

  // pieces
  stream!: PieceStream;
  must: Piece[] = [];
  may: (Piece | null)[] = [];
  hold: Piece | null = null;
  holdLocked = false;
  pieceTimer = 0;
  shapeFactoryUsed = false;

  // reveal
  revealStep = 0;
  revealPauses: number[] = [];
  revealPaused = false;
  sealsLeft = 0;

  // entities
  towers: Tower[] = [];
  towerAt = new Int32Array(GRID_W * GRID_H);
  objAt = new Int32Array(GRID_W * GRID_H);
  roadPieces: RoadPiece[] = [];
  harvesters: Harvester[] = [];
  enemies: Enemy[] = [];
  projectiles: Projectile[] = [];
  puddles: Puddle[] = [];
  tanks: Tank[] = [];
  batteryTower: Tower | null = null;
  private nextId = 1;

  // waves
  waveIndex = 0;
  wave: WaveSpec | null = null;
  spawnQueue: { at: number; spec: WaveSpec['enemies'][number] }[] = [];
  waveT = 0;
  integrity = BASE_INTEGRITY;
  buffer = 0;
  factoryT = 0;

  combo = { n: 0, last: -99, peak: 0 };
  metrics!: BoardMetrics;
  allMetrics: BoardMetrics[] = [];
  events: GameEvent[] = [];
  combat: Rng;
  waveRng: Rng;

  constructor(seed: number, mode: ModeId = 'normal', opts: { tutorial?: boolean; base?: BaseState; board?: number } = {}) {
    this.seed = seed >>> 0;
    this.mode = mode;
    this.base = opts.base ?? newBase();
    this.baseSnapshot = structuredClone(this.base);
    this.tutorialEnabled = opts.tutorial ?? true;
    this.combat = new Rng(subSeed(seed, 909));
    this.waveRng = new Rng(subSeed(seed, 808));
    this.startBoard(opts.board ?? 1);
  }

  // ================================================================ board flow
  startBoard(b: number) {
    this.boardNo = b;
    this.board = new Board(this.seed, b);
    this.stream = new PieceStream(subSeed(this.seed, 707, b), b * 100000);
    this.combat = new Rng(subSeed(this.seed, 909, b, this.attempt));
    this.waveRng = new Rng(subSeed(this.seed, 808, b));
    this.towers = [];
    this.towerAt.fill(0);
    this.objAt.fill(0);
    this.roadPieces = [];
    this.harvesters = [];
    this.enemies = [];
    this.projectiles = [];
    this.puddles = [];
    this.tanks = [];
    this.must = [];
    this.may = new Array(MAY_SLOTS + (hasBuilding(this.base, 'beacon') ? 1 : 0)).fill(null);
    this.hold = null;
    this.holdLocked = false;
    this.waveIndex = 0;
    this.wave = null;
    this.spawnQueue = [];
    this.integrity = BASE_INTEGRITY;
    this.buffer = Math.round(BUILDING_FX.blastDoor * buildingMult(this.base, 'blastDoor'));
    this.combo = { n: 0, last: -99, peak: 0 };
    this.revealStep = 0;
    const total = this.board.revealTotal();
    this.revealPauses = [];
    for (let k = 1; k <= REVEAL.pauses; k++) this.revealPauses.push(Math.max(2, Math.floor((total * k) / (REVEAL.pauses + 1))));
    this.revealPaused = false;
    this.sealsLeft = 0;
    this.metrics = {
      board: b, attempt: this.attempt, cleared: false, baseLost: 0, integrity: BASE_INTEGRITY, waveTime: 0, dangerTime: 0,
      maxBacklog: 0, backlogOver2: 0, combosPeak: 0, kills: 0, leaks: 0, earlyCalls: 0, piecesPlaced: 0,
    };
    this.batteryTower = hasBuilding(this.base, 'missileBattery') ? this.makeBattery() : null;
    this.tutorial = null;
    this.setPhase('reveal');
  }

  get isTutorial() {
    return this.boardNo === 1 && this.tutorialEnabled;
  }

  private setPhase(p: Phase) {
    this.phase = p;
    this.phaseT = 0;
    this.events.push({ t: 'phase', phase: p });
  }

  continueReveal() {
    if (this.phase !== 'reveal' || !this.revealPaused) return;
    this.revealPaused = false;
    this.sealsLeft = 0;
    this.board.reroute();
  }

  placeSeal(a: number, b: number): boolean {
    if (this.phase !== 'reveal' || !this.revealPaused || this.sealsLeft <= 0) return false;
    const k = edgeKey(a, b);
    if (this.board.seals.has(k) || !this.board.sealAllowed(a, b)) {
      this.events.push({ t: 'sealReject', a, b });
      return false;
    }
    this.board.seals.add(k);
    this.sealsLeft--;
    this.events.push({ t: 'seal', a, b });
    return true;
  }

  private finishReveal() {
    this.board.finalize();
    this.events.push({ t: 'revealDone' });
    // board-start grant
    if (this.isTutorial) {
      this.tutorial = { step: 0, text: 'Drag a piece from the tray onto the board, near the road. Three touching pieces become a tower.' };
      this.addPiece(this.stream.make('J', 'red'), true);
      this.addPiece(this.stream.make('L', 'red'), true);
      this.addPiece(this.stream.make('O', 'gold'), true);
    } else {
      let n = BOARD_START_PIECES[this.boardNo - 1];
      if (buildingMult(this.base, 'beacon') > 1) n++;
      for (let i = 0; i < n; i++) this.addPiece(this.stream.next(), true);
      if (hasBuilding(this.base, 'research') && this.boardNo % 3 === 0) {
        const r = this.waveRng;
        this.addPiece(this.stream.make(r.pick(['T', 'I', 'O', 'L'] as const), r.pick(['red', 'gold', 'green', 'blue'] as const), r.pick(RARE_GLYPHS)), true);
        if (buildingMult(this.base, 'research') > 1)
          this.addPiece(this.stream.make(r.pick(['c1', 'c2', 'c3'] as const), 'gold', r.pick(COMMON_GLYPHS)), true);
      }
    }
    this.setPhase('calm');
  }

  ready() {
    if (this.phase !== 'calm') return;
    if (this.isTutorial && this.tutorial && this.tutorial.step < 3) {
      // let impatient players skip the script
      this.tutorial.step = 3;
    }
    if (this.phaseT <= EARLY_CALL_WINDOW && !(this.isTutorial && this.waveIndex === 0)) {
      this.base.essence += EARLY_CALL_BONUS;
      this.metrics.earlyCalls++;
      this.events.push({ t: 'early' });
    }
    this.startWave();
  }

  private startWave() {
    this.waveIndex++;
    this.wave = makeWave(this.seed, this.boardNo, this.waveIndex, this.mode);
    this.spawnQueue = [];
    let at = 0, k = 0;
    for (const n of this.wave.bursts) {
      for (let j = 0; j < n; j++) this.spawnQueue.push({ at: at + j * 0.236, spec: this.wave.enemies[k++] });
      at += BURST_GAP;
    }
    this.waveT = 0;
    this.pieceTimer = WAVE_PIECE_INTERVAL;
    this.factoryT = 3;
    this.shapeFactoryUsed = false;
    for (const rp of this.roadPieces) if (rp.kind === 'barrier' && rp.maxHp === 0) this.armBarrier(rp);
    if (this.tutorial) this.tutorial = { step: 4, text: 'Here they come. Pieces now arrive every 4 seconds: keep building!' };
    this.setPhase('wave');
    this.events.push({ t: 'waveStart', index: this.waveIndex });
  }

  private endWave() {
    this.events.push({ t: 'waveEnd', index: this.waveIndex });
    // ore payout
    let ore = 0;
    for (const h of this.harvesters) ore += h.oreCells;
    ore *= 1 + BUILDING_FX.harvesterHub * buildingMult(this.base, 'harvesterHub');
    if (ore > 0) { this.base.ore += ore; this.events.push({ t: 'ore', amount: ore }); }
    this.base.smiteCharge++;
    this.projectiles = [];
    this.puddles = [];
    this.tanks = [];
    if (this.tutorial) this.tutorial = null;
    if (this.waveIndex >= WAVES_PER_BOARD[this.boardNo - 1]) {
      this.metrics.cleared = true;
      this.finishMetrics();
      this.setPhase(this.boardNo >= BOARDS ? 'victory' : 'cleared');
    } else {
      for (let i = 0; i < CALM_PIECES; i++) this.addPiece(this.stream.next(), true);
      this.setPhase('calm');
    }
  }

  private finishMetrics() {
    this.metrics.integrity = this.integrity;
    this.metrics.baseLost = Math.max(0, BASE_INTEGRITY - this.integrity) / BASE_INTEGRITY;
    this.metrics.combosPeak = this.combo.peak;
    this.allMetrics.push({ ...this.metrics });
  }

  /** After a cleared board: open the base screen (unlocks the next spiral square). */
  enterBase() {
    if (this.phase !== 'cleared') return;
    this.base.unlocked = Math.min(BASE_SQUARES.length, Math.max(this.base.unlocked, 2 + this.boardNo));
    this.setPhase('base');
  }

  nextBoard() {
    if (this.phase !== 'base' || this.boardNo >= BOARDS) return;
    this.attempt = 1;
    this.baseSnapshot = structuredClone(this.base);
    this.startBoard(this.boardNo + 1);
  }

  retryBoard() {
    this.base = structuredClone(this.baseSnapshot);
    this.attempt++;
    this.startBoard(this.boardNo);
  }

  build(square: number, id: BuildingId): string | null {
    const err = canBuild(this.base, square, id);
    if (err) return err;
    this.base.essence -= BUILDINGS[id].cost;
    this.base.buildings[square] = id;
    this.events.push({ t: 'build', square, id });
    return null;
  }

  convertOre() {
    this.base.essence += Math.floor(this.base.ore);
    this.base.ore -= Math.floor(this.base.ore);
  }

  // ================================================================ pieces & queues
  addPiece(p: Piece, toMay: boolean) {
    if (toMay) {
      const i = this.may.indexOf(null);
      if (i >= 0) { this.may[i] = p; this.events.push({ t: 'piece', zone: 'may' }); return; }
    }
    this.must.push(p);
    this.events.push({ t: 'piece', zone: 'must' });
  }

  get mayLocked() {
    return this.must.length > 0;
  }

  getPiece(s: Source): Piece | null {
    if (s.zone === 'must') return this.must[s.index] ?? null;
    if (s.zone === 'may') return this.mayLocked ? null : this.may[s.index] ?? null;
    return this.mayLocked ? null : this.hold;
  }

  private takePiece(s: Source): Piece | null {
    const p = this.getPiece(s);
    if (!p) return null;
    if (s.zone === 'must') this.must.splice(s.index, 1);
    else if (s.zone === 'may') this.may[s.index] = null;
    else this.hold = null;
    return p;
  }

  /** Swap a piece with the Hold slot (once per placement, as in modern Tetris). */
  holdSwap(s: Source): boolean {
    if (this.holdLocked || s.zone === 'hold') return false;
    const p = s.zone === 'must' ? this.must[s.index] : this.mayLocked ? null : this.may[s.index];
    if (!p) return false;
    const prev = this.hold;
    this.hold = p;
    if (s.zone === 'must') {
      if (prev) this.must[s.index] = prev; else this.must.splice(s.index, 1);
    } else this.may[s.index] = prev;
    this.holdLocked = true;
    return true;
  }

  canRecycle() {
    return hasBuilding(this.base, 'recycler');
  }

  recycle(s: Source): boolean {
    if (!this.canRecycle() || this.phase === 'reveal') return false;
    const p = this.takePiece(s);
    if (!p) return false;
    const e = BUILDING_FX.recycler * buildingMult(this.base, 'recycler');
    this.base.essence += e;
    this.holdLocked = false;
    this.events.push({ t: 'recycle', essence: e });
    this.tutorialAdvance('placed');
    return true;
  }

  chooseFamily(f: Family): boolean {
    if (!hasBuilding(this.base, 'shapeFactory') || this.shapeFactoryUsed) return false;
    this.stream.forcedFamily = f;
    this.shapeFactoryUsed = true;
    return true;
  }

  canSmite() {
    return hasBuilding(this.base, 'smite') && this.base.smiteCharge >= BUILDING_FX.smiteWaves && this.phase === 'wave';
  }

  smite(x: number, y: number): boolean {
    if (!this.canSmite() || !this.wave) return false;
    const mult = buildingMult(this.base, 'smite');
    const r = BUILDING_FX.smiteRadius * (mult > 1 ? 1.236 : 1);
    const dmg = BUILDING_FX.smiteUnits * this.wave.unitHp * mult;
    for (const e of this.enemies) if (e.alive && Math.hypot(e.x - x, e.y - y) <= r) this.damage(e, dmg, null, { area: true, ignoreShield: true });
    this.base.smiteCharge = 0;
    this.events.push({ t: 'smite', x, y, r });
    return true;
  }

  // ================================================================ placement
  levelAt(t: Tower, x: number, y: number): number {
    for (let l = t.layers.length - 1; l >= 0; l--) if (t.layers[l].some((c) => c[0] === x && c[1] === y)) return l + 1;
    return 0;
  }

  towerById(id: number) {
    return this.towers.find((t) => t.id === id);
  }

  canPlacePieces() {
    return this.phase === 'calm' || this.phase === 'wave';
  }

  preview(piece: Piece, o: Orient, cx: number, cy: number): Preview {
    const cells = placedCells(piece.kind, o, cx, cy);
    const bad = (reason: string): Preview => ({ ok: false, reason, cells, kind: 'invalid', gained: [], lost: [], holes: [] });
    if (!this.canPlacePieces()) return bad('Wait for the road');
    for (const [x, y] of cells) {
      if (!inGrid(x, y)) return bad('Off the board');
      if (this.board.isCoreCell(x, y)) return bad('That is the core');
      if (this.objAt[cellIdx(x, y)]) return bad('Occupied');
    }
    const under = new Set(cells.map(([x, y]) => this.towerAt[cellIdx(x, y)]).filter((v) => v));
    if (under.size > 0) return this.previewStory(piece, cells, under, bad);

    const roadN = cells.filter(([x, y]) => this.board.isRoad(x, y)).length;
    if (roadN > 0) {
      if (roadN < cells.length) return bad('Road pieces must sit fully on the road');
      if (isCap(piece.kind)) return bad('Caps cannot go on the road');
      const macros = new Set(cells.map(([x, y]) => mid(Math.floor(x / MACRO), Math.floor(y / MACRO))));
      for (const rp of this.roadPieces) for (const m of macros) if (rp.macro === m) return bad('One road piece per square');
      void ROAD_PIECES_PER_MACRO;
      const kind = piece.kind === 'O' ? 'barrier' : 'mine';
      return { ok: true, cells, kind, gained: [kind === 'barrier' ? 'Barrier: blocks the road' : `Mine field: ${cells.length} mines`], lost: [], holes: [] };
    }
    const h0 = this.board.h(cells[0][0], cells[0][1]);
    if (cells.some(([x, y]) => this.board.h(x, y) !== h0)) return bad('A piece must sit on one height');
    const oreN = cells.filter(([x, y]) => this.board.ore[cellIdx(x, y)]).length;
    if (oreN > 0) return { ok: true, cells, kind: 'harvester', gained: [`Harvester: ${oreN} ore per wave`], lost: [], holes: [] };

    // adjacent towers on the same height
    const adj = new Set<number>();
    for (const [x, y] of cells)
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const nx = x + dx, ny = y + dy;
        if (!inGrid(nx, ny)) continue;
        const id = this.towerAt[cellIdx(nx, ny)];
        if (id && this.towerById(id)!.height === h0) adj.add(id);
      }
    const adjTowers = [...adj].map((id) => this.towerById(id)!);
    const groundCount = adjTowers.reduce((s, t) => s + t.pieces.filter((p) => p.layer === 0).length, 0) + 1;
    if (groundCount > MAX_GROUND_PIECES) return bad(`Towers hold at most ${MAX_GROUND_PIECES} ground pieces`);
    const ordered = this.mergeOrder(adjTowers);
    const virt = this.virtualTower(ordered, { piece, cells, layer: 0 }, h0);
    const before = ordered[0]?.stats ?? null;
    return this.describe(virt, before, cells, adjTowers.length > 1 ? adjTowers.map((t) => t.id) : undefined, ordered[0]?.id);
  }

  private previewStory(piece: Piece, cells: Cell[], under: Set<number>, bad: (r: string) => Preview): Preview {
    if (under.size > 1) return bad('A story must rest on one tower');
    const t = this.towerById([...under][0])!;
    if (cells.some(([x, y]) => this.towerAt[cellIdx(x, y)] !== t.id)) return bad('A story must rest fully on the tower');
    if (!t.active) return bad('Finish the tower first: 3 pieces');
    const levels = cells.map(([x, y]) => this.levelAt(t, x, y));
    const L = levels[0];
    if (levels.some((l) => l !== L)) return bad('Uneven support');
    if (L >= MAX_STORIES) return bad(`Max ${MAX_STORIES} stories`);
    const existing = L < t.layers.length ? t.layers[L] : [];
    if (existing.length) {
      const touches = cells.some(([x, y]) => existing.some(([ex, ey]) => Math.abs(ex - x) + Math.abs(ey - y) === 1));
      if (!touches) return bad('Must touch the story it extends');
    }
    const newLayer = existing.concat(cells);
    const below = t.layers[L - 1];
    if (newLayer.length >= below.length) return bad('Each story needs fewer cells than the one below');
    const nb = bbox(newLayer), bb = bbox(below);
    if (nb.x1 - nb.x0 > bb.x1 - bb.x0 || nb.y1 - nb.y0 > bb.y1 - bb.y0) return bad('A story must be smaller in all respects');
    const virt = this.virtualTower([t], { piece, cells, layer: L }, t.height);
    const p = this.describe(virt, t.stats, cells, undefined, t.id);
    p.kind = 'story';
    p.layer = L;
    return p;
  }

  private mergeOrder(ts: Tower[]): Tower[] {
    return [...ts].sort((a, b) => {
      if (!!a.type !== !!b.type) return a.type ? -1 : 1;
      const ga = a.pieces.filter((p) => p.layer === 0).length, gb = b.pieces.filter((p) => p.layer === 0).length;
      return gb - ga || a.id - b.id;
    });
  }

  private virtualTower(ordered: Tower[], add: PlacedPiece, height: number): Tower {
    const pieces: PlacedPiece[] = [];
    for (const t of ordered) pieces.push(...t.pieces);
    pieces.push(add);
    const t: Tower = {
      id: -1, pieces, layers: [], height, type: null, hint: '', active: false, activateT: 0, cx: 0, cy: 0, stats: null,
      cooldown: 0, targetId: 0, angle: 0, rampTarget: 0, rampT: 0, shots: 0, kills: 0, fireFlash: 0,
    };
    // keep a merged tower's type: the leading tower's first three core pieces stay first
    this.rebuildTower(t);
    return t;
  }

  private rebuildTower(t: Tower) {
    const maxL = Math.max(...t.pieces.map((p) => p.layer));
    t.layers = [];
    for (let l = 0; l <= maxL; l++) t.layers.push(t.pieces.filter((p) => p.layer === l).flatMap((p) => p.cells));
    const core = t.pieces.filter((p) => p.layer === 0 && !isCap(p.piece.kind));
    if (core.length >= 3) {
      const r = recipe(towerFamilies(t));
      t.type = r.type;
      t.hint = r.hint;
    } else t.type = null;
    const g = t.layers[0];
    t.cx = g.reduce((s, c) => s + c[0] + 0.5, 0) / g.length;
    t.cy = g.reduce((s, c) => s + c[1] + 0.5, 0) / g.length;
    t.stats = computeStats(t, this.statCtx());
  }

  private statCtx() {
    return { powerStation: BUILDING_FX.powerStation * buildingMult(this.base, 'powerStation'), goldenBase: goldenBase(this.base) };
  }

  private describe(virt: Tower, before: TowerStats | null, cells: Cell[], mergeIds: number[] | undefined, towerId?: number): Preview {
    const after = virt.stats;
    const shape = after?.shape ?? analyseShape(virt.layers[0]);
    const prevKeys = new Set((before?.bonuses ?? []).filter((b) => b.good).map((b) => b.key));
    const nextKeys = new Set((after?.bonuses ?? []).filter((b) => b.good).map((b) => b.key));
    const gained = (after?.bonuses ?? []).filter((b) => b.good && !prevKeys.has(b.key) && b.key !== 'surface' && b.key !== 'mass').map((b) => b.label);
    const lost = (before?.bonuses ?? []).filter((b) => b.good && !nextKeys.has(b.key) && b.key !== 'surface').map((b) => b.label);
    const core = virt.pieces.filter((p) => p.layer === 0 && !isCap(p.piece.kind)).length;
    if (shape.holes.length && after) lost.push(`${shape.holes.length} hole${shape.holes.length > 1 ? 's' : ''}: −${shape.holes.length * 10}% damage`);
    if (mergeIds) gained.unshift(`Merges ${mergeIds.length} towers: keeps ${virt.type ?? 'pile'}`);
    return {
      ok: true, cells, kind: 'tower', towerId, mergeIds, resultType: virt.type, needs: Math.max(0, 3 - core), hint: virt.hint,
      gained, lost, holes: shape.holes, dps: after?.dps, range: after?.range,
    };
  }

  place(s: Source, o: Orient, cx: number, cy: number): Preview {
    const piece = this.getPiece(s);
    if (!piece) return { ok: false, reason: this.mayLocked && s.zone !== 'must' ? 'Place MUST USE pieces first' : 'No piece', cells: [], kind: 'invalid', gained: [], lost: [], holes: [] };
    const pv = this.preview(piece, o, cx, cy);
    if (!pv.ok) {
      this.events.push({ t: 'reject', reason: pv.reason ?? 'Illegal' });
      return pv;
    }
    this.takePiece(s);
    this.holdLocked = false;
    this.metrics.piecesPlaced++;
    const cells = pv.cells;
    if (pv.kind === 'barrier' || pv.kind === 'mine') {
      const rp: RoadPiece = {
        id: this.nextId++, kind: pv.kind, piece, cells,
        macro: mid(Math.floor(cells[0][0] / MACRO), Math.floor(cells[0][1] / MACRO)),
        hp: 0, maxHp: 0, mines: cells.map(() => true), entry: new Map(),
      };
      for (const r of this.board.routes) {
        for (let d = 0; d < r.length; d += 0.25) {
          const p = routeAt(r, d);
          if (cells.some(([x, y]) => Math.floor(p.x) === x && Math.floor(p.y) === y)) { rp.entry.set(r, d); break; }
        }
      }
      if (rp.kind === 'barrier' && this.phase === 'wave') this.armBarrier(rp);
      this.roadPieces.push(rp);
      for (const [x, y] of cells) this.objAt[cellIdx(x, y)] = rp.id;
      this.events.push({ t: 'place', pieceId: piece.id, cells, size: cells.length, kind: pv.kind, color: piece.color });
    } else if (pv.kind === 'harvester') {
      const h: Harvester = { id: this.nextId++, piece, cells, oreCells: cells.filter(([x, y]) => this.board.ore[cellIdx(x, y)]).length };
      this.harvesters.push(h);
      for (const [x, y] of cells) this.objAt[cellIdx(x, y)] = h.id;
      this.events.push({ t: 'place', pieceId: piece.id, cells, size: cells.length, kind: 'harvester', color: piece.color });
    } else if (pv.kind === 'story') {
      const t = this.towerById(pv.towerId!)!;
      const before = t.stats;
      t.pieces.push({ piece, cells, layer: pv.layer! });
      this.rebuildTower(t);
      this.events.push({ t: 'place', pieceId: piece.id, cells, size: cells.length, kind: 'story', towerId: t.id, pieceCount: t.pieces.length, color: piece.color });
      this.bonusEvents(t, before);
      this.tutorialAdvance('story');
    } else {
      const h0 = this.board.h(cells[0][0], cells[0][1]);
      const adj = new Set<number>();
      for (const [x, y] of cells)
        for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
          const nx = x + dx, ny = y + dy;
          if (!inGrid(nx, ny)) continue;
          const id = this.towerAt[cellIdx(nx, ny)];
          if (id && this.towerById(id)!.height === h0) adj.add(id);
        }
      const ordered = this.mergeOrder([...adj].map((id) => this.towerById(id)!));
      let t: Tower;
      const before = ordered[0]?.stats ?? null;
      const wasActive = ordered[0]?.active ?? false;
      if (ordered.length === 0) {
        t = {
          id: this.nextId++, pieces: [], layers: [], height: h0, type: null, hint: '', active: false, activateT: 0, cx: 0, cy: 0,
          stats: null, cooldown: 0, targetId: 0, angle: -Math.PI / 2, rampTarget: 0, rampT: 0, shots: 0, kills: 0, fireFlash: 0,
        };
        this.towers.push(t);
      } else {
        t = ordered[0];
        for (const other of ordered.slice(1)) {
          t.pieces.push(...other.pieces);
          t.kills += other.kills;
          this.towers = this.towers.filter((x) => x !== other);
        }
      }
      t.pieces.push({ piece, cells, layer: 0 });
      this.rebuildTower(t);
      for (const c of t.layers[0]) this.towerAt[cellIdx(c[0], c[1])] = t.id;
      this.events.push({ t: 'place', pieceId: piece.id, cells, size: cells.length, kind: 'tower', towerId: t.id, pieceCount: t.pieces.length, color: piece.color });
      if (t.type && !wasActive) {
        t.active = true;
        t.activateT = 0;
        t.cooldown = 0;
        this.discovered.add(t.type);
        this.events.push({ t: 'activate', towerId: t.id, type: t.type });
        this.tutorialAdvance('activate');
      } else if (wasActive) this.tutorialAdvance('mass');
      this.bonusEvents(t, before);
    }
    this.tutorialAdvance('placed');
    return pv;
  }

  private bonusEvents(t: Tower, before: TowerStats | null) {
    if (!t.stats) return;
    const prev = new Set((before?.bonuses ?? []).map((b) => b.key));
    for (const b of t.stats.bonuses)
      if (b.good && !prev.has(b.key) && ['golden', 'mirror', 'rot', 'perfect', 'spire', 'res', 'pure'].includes(b.key))
        this.events.push({ t: 'bonus', towerId: t.id, label: b.label, key: b.key });
  }

  private tutorialAdvance(what: 'activate' | 'mass' | 'story' | 'placed') {
    const tu = this.tutorial;
    if (!tu) return;
    if (tu.step === 0 && what === 'activate') {
      this.tutorial = { step: 1, text: 'A Gun! Two Hooks and a Block make a Gun. This new piece is MUST USE: place it before the tray unlocks. Try adding it to your Gun for extra mass.' };
      this.addPiece(this.stream.make('T', 'red'), false);
    } else if (tu.step === 1 && (what === 'mass' || what === 'placed') && this.must.length === 0) {
      this.tutorial = { step: 2, text: 'Caps are small pieces. Drop this one on top of your tower to build a story: +27% damage, +15% range. (R rotates, F mirrors.)' };
      this.addPiece(this.stream.make('c2', 'red'), true);
    } else if (tu.step === 2 && (what === 'story' || what === 'placed')) {
      this.tutorial = { step: 3, text: what === 'story' ? 'Story 2! Press Ready when you are set.' : 'Press Ready when you are set.' };
    }
  }

  // ================================================================ simulation step
  step() {
    const dt = DT;
    this.time += dt;
    this.phaseT += dt;
    if (this.phase === 'reveal') return this.stepReveal(dt);
    if (this.phase !== 'wave' && this.phase !== 'calm') return;
    for (const t of this.towers) if (t.active) t.activateT += dt;
    if (this.phase === 'calm') return;

    this.waveT += dt;
    this.metrics.waveTime += dt;
    this.metrics.maxBacklog = Math.max(this.metrics.maxBacklog, this.must.length);
    if (this.must.length > 2) this.metrics.backlogOver2 += dt;
    // pieces
    this.pieceTimer -= dt;
    if (this.pieceTimer <= 0) {
      this.pieceTimer += WAVE_PIECE_INTERVAL;
      this.addPiece(this.stream.next(), false);
    }
    // spawns
    while (this.spawnQueue.length && this.spawnQueue[0].at <= this.waveT) this.spawn(this.spawnQueue.shift()!.spec);
    // factory tanks
    if (hasBuilding(this.base, 'factory')) {
      this.factoryT -= dt;
      if (this.factoryT <= 0 && this.board.routes.length) {
        this.factoryT += BUILDING_FX.factoryEvery;
        const r = this.combat.pick(this.board.routes);
        this.tanks.push({ id: this.nextId++, route: r, d: r.length - 2, x: CORE_PT.x, y: CORE_PT.y, px: CORE_PT.x, py: CORE_PT.y, dir: 0, cd: 0, alive: true });
      }
    }
    for (const e of this.enemies) { e.px = e.x; e.py = e.y; }
    for (const p of this.projectiles) { p.px = p.x; p.py = p.y; }
    for (const k of this.tanks) { k.px = k.x; k.py = k.y; }
    this.stepEnemies(dt);
    this.stepTowers(dt);
    if (this.batteryTower) this.fireTower(this.batteryTower, dt);
    this.stepProjectiles(dt);
    this.stepPuddles(dt);
    this.stepTanks(dt);
    this.stepMines();
    this.enemies = this.enemies.filter((e) => e.alive);
    this.projectiles = this.projectiles.filter((p) => p.alive);
    // danger: any enemy in the last 25% of its road
    if (this.enemies.some((e) => e.d / e.route.length > 0.75)) this.metrics.dangerTime += dt;
    if (this.integrity <= 0 && this.phase === 'wave') {
      this.finishMetrics();
      this.setPhase('lost');
      return;
    }
    if (!this.spawnQueue.length && !this.enemies.length) this.endWave();
  }

  private stepReveal(dt: number) {
    if (this.revealPaused) return;
    const total = this.board.revealTotal();
    const speed = total / REVEAL.seconds;
    const prev = this.revealStep;
    this.revealStep += speed * dt;
    const pause = this.revealPauses.find((p) => prev < p && this.revealStep >= p);
    if (pause !== undefined) {
      this.revealStep = pause;
      this.revealPaused = true;
      this.sealsLeft = REVEAL.sealsPerPause;
      this.events.push({ t: 'revealPause' });
    }
    for (const p of this.board.paths) p.revealed = Math.min(p.path.length, Math.floor(this.revealStep) + 1);
    if (this.revealStep >= this.board.revealTotal() + 0.5) this.finishReveal();
  }

  // ---------------------------------------------------------------- enemies
  private spawn(spec: WaveSpec['enemies'][number], at?: { route: Route; d: number }, hpOverride?: number, gen = 0): Enemy {
    const sz = SIZES[spec.size];
    let route: Route;
    let overland = false;
    if (at) route = at.route;
    else if (spec.arch === 'balloon') {
      const p = this.waveRng.pick(this.board.paths);
      route = makeRoute(-1, [p.start, CORE_PT]);
      overland = true;
    } else if (spec.arch === 'walker') {
      const side = this.waveRng.int(0, 3);
      const t = this.waveRng.range(0.1, 0.9);
      const start: Pt = side === 0 ? { x: 0, y: t * GRID_H } : side === 1 ? { x: GRID_W, y: t * GRID_H } : side === 2 ? { x: t * GRID_W, y: 0 } : { x: t * GRID_W, y: GRID_H };
      route = makeRoute(-1, [start, CORE_PT]);
      overland = true;
    } else {
      const ing = this.waveRng.int(0, this.board.paths.length - 1);
      const opts = this.board.routes.filter((r) => r.ingress === ing);
      route = this.waveRng.pick(opts.length ? opts : this.board.routes);
    }
    if (at && at.route.ingress < 0) overland = true;
    let maxHp = hpOverride ?? (this.wave!.unitHp * sz.hp);
    if (spec.ability === 'grower' && hpOverride === undefined) maxHp *= ABILITIES.growerHp;
    const p0 = routeAt(route, at?.d ?? 0);
    const e: Enemy = {
      id: this.nextId++, size: spec.size, suit: spec.suit, arch: spec.arch, ability: spec.ability, golden: spec.golden, boss: !!spec.boss,
      gen, hp: maxHp, maxHp, shield: spec.ability === 'shielded' ? maxHp * ABILITIES.shield : 0,
      route, overland, d: at?.d ?? 0, x: p0.x, y: p0.y, px: p0.x, py: p0.y, dir: p0.dir,
      speed: sz.speed, slowT: 0, slowMult: 1, dots: [], animT: this.waveRng.next() * 10,
      airborne: false, stretched: false, immune: false, abilityT: 0, heraldBoost: false, chewing: 0, lastTower: 0, shed: 0, alive: true,
      scale: (spec.ability === 'grower' ? 1.3 : 1) * (gen > 0 ? Math.pow(0.8, gen) : 1), hitFlash: 0,
    };
    if (e.arch === 'roller') e.speed *= ARCH.rollerSpeed;
    if (e.arch === 'nautilus') e.speed *= ARCH.nautilusSpeed;
    if (e.arch === 'balloon') e.speed *= ARCH.balloonSpeed;
    if (e.ability === 'swift') e.speed *= ABILITIES.swift;
    if (e.ability === 'hoarder') e.speed *= ABILITIES.hoarderSpeed;
    this.enemies.push(e);
    return e;
  }

  private stepEnemies(dt: number) {
    // heralds and shield bearers act on neighbours
    for (const e of this.enemies) e.heraldBoost = false;
    for (const e of this.enemies) {
      if (!e.alive) continue;
      if (e.ability === 'herald')
        for (const o of this.enemies) if (o !== e && Math.hypot(o.x - e.x, o.y - e.y) < ABILITIES.heraldRadius) o.heraldBoost = true;
    }
    for (const e of this.enemies) {
      if (!e.alive) continue;
      e.animT += dt;
      e.abilityT += dt;
      if (e.hitFlash > 0) e.hitFlash -= dt;
      // archetype state
      if (e.arch === 'hopper') e.airborne = (e.animT % ARCH.hopperCycle) / ARCH.hopperCycle < ARCH.hopperAir;
      if (e.arch === 'slinky') e.stretched = Math.sin((e.animT / ARCH.slinkyCycle) * Math.PI * 2) > 0;
      if (e.arch === 'tumbler' && e.animT % ARCH.tumblerFlip < dt) e.suit = SUITS[(SUITS.indexOf(e.suit) + 1) % 4];
      // abilities
      switch (e.ability) {
        case 'regen': e.hp = Math.min(e.maxHp, e.hp + e.maxHp * ABILITIES.regen * dt); break;
        case 'phase': e.immune = e.abilityT % ABILITIES.phaseEvery > ABILITIES.phaseEvery - ABILITIES.phaseTime; break;
        case 'blink':
          if (e.abilityT >= ABILITIES.blinkEvery) { e.abilityT = 0; e.d = Math.min(e.route.length - 3, e.d + ABILITIES.blinkCells); }
          break;
        case 'bearer':
          if (e.abilityT >= ABILITIES.bearerEvery) {
            e.abilityT = 0;
            for (const o of this.enemies)
              if (o !== e && o.alive && Math.hypot(o.x - e.x, o.y - e.y) < ABILITIES.bearerRadius)
                o.shield = Math.max(o.shield, o.maxHp * ABILITIES.bearerShield);
          }
          break;
      }
      // DoTs
      for (const d of e.dots) {
        d.t -= dt;
        this.damage(e, d.dps * dt, this.towerById(d.tower) ?? null, { dot: true });
        if (!e.alive) break;
      }
      if (!e.alive) continue;
      e.dots = e.dots.filter((d) => d.t > 0);
      // slows
      if (e.slowT > 0) { e.slowT -= dt; if (e.slowT <= 0) e.slowMult = 1; }
      let v = e.speed * e.slowMult * (e.heraldBoost ? ABILITIES.heraldSpeed : 1);
      if (e.arch === 'roller' && e.route.corners.some((c) => Math.abs(c - e.d) < 2.5)) v *= ARCH.rollerBrake;
      // barriers
      e.chewing = 0;
      if (!e.overland) {
        for (const rp of this.roadPieces) {
          if (rp.kind !== 'barrier' || rp.hp <= 0) continue;
          const entry = rp.entry.get(e.route);
          if (entry === undefined) continue;
          const stop = entry - 0.6;
          if (e.d <= stop + 0.01 && e.d + v * dt >= stop) {
            e.d = Math.max(e.d, stop);
            e.chewing = rp.id;
            rp.hp -= COMBAT.barrierChew * Math.sqrt(SIZES[e.size].hp) * (this.wave?.unitHp ?? 1) * dt;
            if (rp.hp <= 0) this.breakBarrier(rp);
            break;
          }
        }
      }
      if (!e.chewing) e.d += v * dt;
      const p = routeAt(e.route, e.d);
      e.x = p.x; e.y = p.y; e.dir = p.dir;
      if (e.d >= e.route.length) this.leak(e);
    }
  }

  private armBarrier(rp: RoadPiece) {
    const unit = this.wave?.unitHp ?? makeWave(this.seed, this.boardNo, this.waveIndex + 1, this.mode).unitHp;
    rp.maxHp = rp.hp = COMBAT.barrierUnits * unit;
  }

  private breakBarrier(rp: RoadPiece) {
    const c = rp.cells[0];
    this.events.push({ t: 'barrierBreak', x: c[0] + 1, y: c[1] + 1 });
    this.roadPieces = this.roadPieces.filter((r) => r !== rp);
    for (const [x, y] of rp.cells) this.objAt[cellIdx(x, y)] = 0;
  }

  private leak(e: Enemy) {
    e.alive = false;
    let dmg = SIZES[e.size].leak + (e.ability === 'grower' ? ABILITIES.growerLeak : 0);
    if (this.isTutorial && this.waveT < 20) dmg = 0;
    const fromBuffer = Math.min(this.buffer, dmg);
    this.buffer -= fromBuffer;
    this.integrity -= dmg - fromBuffer;
    this.metrics.leaks++;
    this.events.push({ t: 'leak', dmg, x: e.x, y: e.y });
  }

  /** Apply damage with suit, archetype and ability rules. Returns damage dealt. */
  damage(
    e: Enemy, amount: number, t: Tower | null,
    o: { single?: boolean; area?: boolean; beam?: boolean; dot?: boolean; splash?: boolean; ignoreShield?: boolean; fx?: number; fy?: number; crit?: boolean } = {},
  ): number {
    if (!e.alive) return 0;
    if (e.immune) { if (!o.dot && this.combat.chance(0.2)) this.events.push({ t: 'immune', x: e.x, y: e.y }); return 0; }
    let m = 1;
    const color = t?.stats?.color ?? null;
    if (color) {
      if (SUIT_WEAK[e.suit] === color) m *= SUIT_MULT.strong;
      else if (SUIT_RESIST[e.suit] === color) m *= SUIT_MULT.weak;
    }
    if (e.arch === 'swinger') {
      if (o.single && this.combat.chance(ARCH.swingerParry)) { this.events.push({ t: 'parry', x: e.x, y: e.y }); return 0; }
      if (o.beam || o.area) m *= ARCH.swingerWeak;
    }
    if (e.arch === 'slinky' && e.stretched && o.splash) m *= ARCH.slinkySplash;
    if (e.arch === 'nautilus' && o.fx !== undefined && o.fy !== undefined) {
      const a = Math.atan2(o.fy - e.y, o.fx - e.x);
      let diff = Math.abs(a - e.dir) % (Math.PI * 2);
      if (diff > Math.PI) diff = Math.PI * 2 - diff;
      if (diff < Math.PI / 3) m *= ARCH.nautilusFront;
    }
    let dmg = amount * m;
    if (t?.stats?.critChance && !o.dot && this.combat.chance(t.stats.critChance)) { dmg *= GLYPHS.critMult; o.crit = true; }
    if (e.shield > 0 && !o.ignoreShield) {
      const s = Math.min(e.shield, dmg);
      e.shield -= s;
      dmg -= s;
    }
    e.hp -= dmg;
    if (t) e.lastTower = t.id;
    if (!o.dot) e.hitFlash = 0.08;
    if (o.crit) this.events.push({ t: 'hit', x: e.x, y: e.y, amount: dmg, crit: true });
    // slows from Tee traits and glyphs
    if (t?.stats && !o.dot) {
      if (t.stats.slowTrait > 0) this.slow(e, 1 - t.stats.slowTrait, 0.5);
      if (t.stats.slowOnHit > 0) this.slow(e, GLYPHS.slowOnHit, GLYPHS.slowTime);
      if (t.stats.dotTrait > 0) this.addDot(e, { kind: 'burn', dps: (amount * t.stats.dotTrait) / 2, t: 2, tower: t.id });
    }
    if (e.boss) {
      const frac = e.hp / e.maxHp;
      while (e.shed < 4 && frac <= 0.8 - e.shed * 0.2) this.bossShed(e);
    }
    if (e.hp <= 0) this.kill(e, t);
    return dmg;
  }

  private slow(e: Enemy, mult: number, time: number) {
    if (e.size === 'boss') mult = 1 - (1 - mult) * 0.5;
    e.slowMult = Math.min(e.slowMult, mult);
    e.slowT = Math.max(e.slowT, time);
  }

  private addDot(e: Enemy, d: Dot) {
    const ex = e.dots.find((x) => x.kind === d.kind && x.tower === d.tower);
    if (ex) { ex.t = Math.max(ex.t, d.t); ex.dps = Math.max(ex.dps, d.dps); } else e.dots.push(d);
  }

  private bossShed(e: Enemy) {
    const n = [1, 1, 2, 3, 5][e.shed];
    e.shed++;
    for (let i = 0; i < n; i++)
      this.spawn({ size: 'small', suit: this.waveRng.pick(SUITS), arch: 'hopper', ability: null, golden: false }, { route: e.route, d: Math.max(0, e.d - 0.5 - i * 0.4) }, this.wave!.unitHp);
    this.events.push({ t: 'explode', x: e.x, y: e.y, r: 2, color: 'gold' });
  }

  private kill(e: Enemy, t: Tower | null) {
    e.alive = false;
    this.metrics.kills++;
    let essence = SIZES[e.size].essence * (t?.stats?.essenceMult ?? 1);
    if (e.gen > 0) essence = Math.max(0.5, essence / 2);
    if (e.ability === 'hoarder') essence += ABILITIES.hoarderEssence;
    this.base.essence += essence;
    if (t) t.kills++;
    if (e.golden) this.addPiece(this.stream.make(this.combat.pick(['T', 'L', 'I', 'O'] as const), 'gold', null, true), true);
    // boss final shed
    if (e.boss && e.shed < 5) { e.shed = 4; this.bossShed(e); }
    // splitter
    const split = e.ability === 'splitter' && e.gen < ABILITIES.splitGenerations - 1;
    if (split)
      for (let i = 0; i < 2; i++) {
        const c = this.spawn({ size: e.size, suit: e.suit, arch: e.arch, ability: 'splitter', golden: false }, { route: e.route, d: Math.max(0, e.d - 0.4 + i * 0.8) }, e.maxHp * ABILITIES.splitHp, e.gen + 1);
        c.x = e.x; c.y = e.y;
      }
    // spreading DoTs
    const virus = e.dots.find((d) => d.kind === 'virus');
    const poison = e.dots.find((d) => d.kind === 'poison');
    for (const d of [virus, poison]) {
      if (!d) continue;
      const near = this.enemies.filter((o) => o.alive && o !== e && Math.hypot(o.x - e.x, o.y - e.y) < 3).slice(0, 2);
      for (const o of near) this.addDot(o, { ...d, t: d.kind === 'virus' ? COMBAT.virusDuration : 3 });
    }
    this.events.push({ t: 'kill', x: e.x, y: e.y, size: e.size, suit: e.suit, arch: e.arch, split, essence });
    // combos
    if (this.time - this.combo.last <= COMBO.window) this.combo.n++; else this.combo.n = 1;
    this.combo.last = this.time;
    this.combo.peak = Math.max(this.combo.peak, this.combo.n);
    if (COMBO.steps.includes(this.combo.n) || (this.combo.n > 21 && this.combo.n % 13 === 0))
      this.events.push({ t: 'combo', n: this.combo.n, x: e.x, y: e.y });
  }

  // ---------------------------------------------------------------- towers
  private canHit(t: Tower, e: Enemy): boolean {
    if (!e.alive) return false;
    if (e.arch === 'balloon' && !TOWERS[t.type!].air) return false;
    return true;
  }

  private inRange(t: Tower, e: Enemy, range: number) {
    return Math.hypot(e.x - t.cx, e.y - t.cy) <= range + SIZES[e.size].radius;
  }

  private pickTarget(t: Tower, range: number): Enemy | null {
    let best: Enemy | null = null;
    let bestScore = -Infinity;
    const missile = t.type === 'Missile';
    for (const e of this.enemies) {
      if (!this.canHit(t, e) || !this.inRange(t, e, range)) continue;
      let score = e.d / e.route.length;
      if (e.arch === 'walker' || e.boss) score += 10;
      if (missile && (e.arch === 'balloon' || e.size === 'giant')) score += 5;
      if (e.immune) score -= 3;
      if (score > bestScore) { bestScore = score; best = e; }
    }
    return best;
  }

  private stepTowers(dt: number) {
    for (const t of this.towers) {
      if (!t.active || !t.stats || t.activateT < COMBAT.activateTime) continue;
      this.fireTower(t, dt);
    }
  }

  private fireTower(t: Tower, dt: number) {
    const s = t.stats!;
    const def = TOWERS[t.type!];
    t.cooldown -= dt;
    if (t.fireFlash > 0) t.fireFlash -= dt;
    if (def.kind === 'beam') {
      let tgt = this.enemies.find((e) => e.id === t.rampTarget && this.canHit(t, e) && this.inRange(t, e, s.range)) ?? null;
      if (!tgt) { tgt = this.pickTarget(t, s.range); t.rampT = 0; }
      t.rampTarget = tgt?.id ?? 0;
      t.targetId = t.rampTarget;
      if (!tgt) return;
      t.rampT += dt;
      const [lo, hi, T] = COMBAT.laserRamp;
      const mult = lo + (hi - lo) * Math.min(1, t.rampT / T);
      t.angle = Math.atan2(tgt.y - t.cy, tgt.x - t.cx);
      this.damage(tgt, s.dps * dt * mult, t, { beam: true, fx: t.cx, fy: t.cy });
      if (t.cooldown <= 0) { t.cooldown = s.interval * 3; t.shots++; this.onHitExtras(t, tgt, s.damage * 3 * mult); }
      return;
    }
    if (t.cooldown > 0) return;
    if (def.kind === 'aura') {
      const targets = this.enemies.filter((e) => this.canHit(t, e) && this.inRange(t, e, s.range)).slice(0, s.maxTargets);
      if (!targets.length) { t.targetId = 0; return; }
      t.cooldown = s.interval;
      t.targetId = targets[0].id;
      t.fireFlash = 0.1;
      for (const e of targets) {
        this.damage(e, s.damage, t, { area: true });
        if (t.type === 'Freezer') this.slow(e, COMBAT.freezerSlow, s.interval + 0.15);
      }
      return;
    }
    const tgt = this.pickTarget(t, s.range);
    t.targetId = tgt?.id ?? 0;
    if (!tgt) return;
    t.angle = Math.atan2(tgt.y - t.cy, tgt.x - t.cx);
    t.cooldown = Math.max(t.cooldown + s.interval, s.interval * 0.5);
    t.shots++;
    t.fireFlash = 0.08;
    let dmg = s.damage;
    if (s.spire && t.shots % SHAPE.spireCritEvery === 0) dmg *= SHAPE.spireCrit;
    const color = s.color;
    switch (def.kind) {
      case 'bullet':
        this.projectiles.push(this.proj('bullet', t, tgt, dmg, COMBAT.bulletSpeed));
        this.events.push({ t: 'shot', towerId: t.id, kind: def.kind, x1: t.cx, y1: t.cy, x2: tgt.x, y2: tgt.y, color });
        break;
      case 'homing':
        this.projectiles.push(this.proj('homing', t, tgt, dmg, COMBAT.missileSpeed));
        this.events.push({ t: 'shot', towerId: t.id, kind: def.kind, x1: t.cx, y1: t.cy, x2: tgt.x, y2: tgt.y, color });
        break;
      case 'lob':
      case 'puddle': {
        const lead = routeAt(tgt.route, tgt.d + tgt.speed * tgt.slowMult * COMBAT.lobTime * 0.8);
        const p = this.proj(def.kind === 'lob' ? 'lob' : 'acid', t, tgt, dmg, 0);
        p.tx = lead.x; p.ty = lead.y; p.dur = COMBAT.lobTime;
        this.projectiles.push(p);
        this.events.push({ t: 'shot', towerId: t.id, kind: def.kind, x1: t.cx, y1: t.cy, x2: lead.x, y2: lead.y, color });
        break;
      }
      case 'hitscan':
        this.events.push({ t: 'shot', towerId: t.id, kind: def.kind, x1: t.cx, y1: t.cy, x2: tgt.x, y2: tgt.y, color });
        this.damage(tgt, dmg, t, { single: true, ignoreShield: true, fx: t.cx, fy: t.cy });
        this.onHitExtras(t, tgt, dmg);
        break;
      case 'pierce': {
        const ang = t.angle;
        const x2 = t.cx + Math.cos(ang) * s.range, y2 = t.cy + Math.sin(ang) * s.range;
        this.events.push({ t: 'shot', towerId: t.id, kind: def.kind, x1: t.cx, y1: t.cy, x2, y2, color });
        for (const e of this.enemies) {
          if (!this.canHit(t, e)) continue;
          const dx = e.x - t.cx, dy = e.y - t.cy;
          const along = dx * Math.cos(ang) + dy * Math.sin(ang);
          const perp = Math.abs(-dx * Math.sin(ang) + dy * Math.cos(ang));
          if (along > 0 && along <= s.range && perp < 0.9 + SIZES[e.size].radius * 0.5) this.damage(e, dmg, t, { fx: t.cx, fy: t.cy });
        }
        this.onHitExtras(t, tgt, dmg);
        break;
      }
      case 'bolt': {
        const miss = this.combat.chance(COMBAT.lightningMiss);
        const a = this.combat.range(0, Math.PI * 2), r = this.combat.range(0, miss ? s.area * 1.5 : s.area * 0.6);
        const bx = tgt.x + Math.cos(a) * r, by = tgt.y + Math.sin(a) * r;
        this.events.push({ t: 'bolt', x1: t.cx, y1: t.cy - 1.5, x2: bx, y2: by, miss });
        let n = 0;
        for (const e of this.enemies) {
          if (n >= s.maxTargets || !this.canHit(t, e)) continue;
          if (Math.hypot(e.x - bx, e.y - by) <= 1.5 + SIZES[e.size].radius * 0.5) { this.damage(e, dmg, t, { area: true }); n++; }
        }
        if (n) this.onHitExtras(t, tgt, dmg);
        break;
      }
      case 'cone': {
        let n = 0;
        this.events.push({ t: 'shot', towerId: t.id, kind: def.kind, x1: t.cx, y1: t.cy, x2: tgt.x, y2: tgt.y, color });
        for (const e of this.enemies) {
          if (n >= s.maxTargets || !this.canHit(t, e) || !this.inRange(t, e, s.range)) continue;
          let diff = Math.abs(Math.atan2(e.y - t.cy, e.x - t.cx) - t.angle) % (Math.PI * 2);
          if (diff > Math.PI) diff = Math.PI * 2 - diff;
          if (diff > COMBAT.flamerCone) continue;
          this.damage(e, dmg * (1 - COMBAT.flamerBurn), t, { area: true, fx: t.cx, fy: t.cy });
          this.addDot(e, { kind: 'burn', dps: (dmg * COMBAT.flamerBurn) / s.interval / 2 * 0.5, t: 2, tower: t.id });
          n++;
        }
        break;
      }
      case 'virus': {
        const targets = this.enemies
          .filter((e) => this.canHit(t, e) && this.inRange(t, e, s.range) && !e.dots.some((d) => d.kind === 'virus'))
          .sort((a, b) => b.d / b.route.length - a.d / a.route.length)
          .slice(0, s.maxTargets);
        const pool = targets.length ? targets : [tgt];
        for (const e of pool) {
          this.events.push({ t: 'shot', towerId: t.id, kind: def.kind, x1: t.cx, y1: t.cy, x2: e.x, y2: e.y, color });
          this.addDot(e, { kind: 'virus', dps: s.dps, t: COMBAT.virusDuration, tower: t.id });
        }
        break;
      }
    }
  }

  private proj(kind: Projectile['kind'], t: Tower, tgt: Enemy, damage: number, speed: number): Projectile {
    return {
      id: this.nextId++, kind, x: t.cx, y: t.cy, px: t.cx, py: t.cy, sx: t.cx, sy: t.cy, tx: tgt.x, ty: tgt.y,
      targetId: tgt.id, t: 0, dur: 1, speed, damage, tower: t.id, color: t.stats?.color ?? null, alive: true,
    };
  }

  /** Glyph and resonance extras after a primary hit. */
  private onHitExtras(t: Tower, tgt: Enemy, dmg: number) {
    const s = t.stats!;
    const near = (n: number, r: number) =>
      this.enemies.filter((e) => e.alive && e !== tgt && this.canHit(t, e) && Math.hypot(e.x - tgt.x, e.y - tgt.y) < r)
        .sort((a, b) => Math.hypot(a.x - tgt.x, a.y - tgt.y) - Math.hypot(b.x - tgt.x, b.y - tgt.y)).slice(0, n);
    if (s.pierce) for (const e of near(s.pierce, 1.8)) this.damage(e, dmg * 0.7, t, {});
    if (s.chain) for (const e of near(s.chain, 4)) { this.events.push({ t: 'bolt', x1: tgt.x, y1: tgt.y, x2: e.x, y2: e.y, miss: false }); this.damage(e, dmg * 0.6, t, {}); }
    switch (s.resonance) {
      case 'red':
        for (const e of near(4, 1.5)) { this.damage(e, dmg * RESONANCE.burnSplash, t, { splash: true }); this.addDot(e, { kind: 'burn', dps: dmg * 0.1, t: 2, tower: t.id }); }
        break;
      case 'gold':
        for (const e of near(RESONANCE.ricochet, 5)) { this.events.push({ t: 'shot', towerId: t.id, kind: 'ricochet', x1: tgt.x, y1: tgt.y, x2: e.x, y2: e.y, color: 'gold' }); this.damage(e, dmg * 0.5, t, { single: true }); }
        break;
      case 'blue':
        this.events.push({ t: 'explode', x: tgt.x, y: tgt.y, r: RESONANCE.blueSplash, color: 'blue' });
        for (const e of near(5, RESONANCE.blueSplash)) this.damage(e, dmg * 0.5, t, { splash: true });
        break;
      case 'green':
        this.addDot(tgt, { kind: 'poison', dps: dmg * 0.15, t: 3, tower: t.id });
        break;
    }
  }

  private stepProjectiles(dt: number) {
    for (const p of this.projectiles) {
      if (!p.alive) continue;
      const tw = this.towerById(p.tower) ?? (this.batteryTower?.id === p.tower ? this.batteryTower : null);
      if (p.kind === 'lob' || p.kind === 'acid') {
        p.t += dt;
        const k = Math.min(1, p.t / p.dur);
        p.x = p.sx + (p.tx - p.sx) * k;
        p.y = p.sy + (p.ty - p.sy) * k;
        if (k >= 1) {
          p.alive = false;
          if (p.kind === 'acid') {
            this.puddles.push({ x: p.tx, y: p.ty, r: tw?.stats?.area ?? 2, t: COMBAT.acidLinger, dps: (tw?.stats?.dps ?? 5) * 0.5, tower: p.tower, maxTargets: 5 });
          } else this.explode(p, tw);
        }
        continue;
      }
      const tgt = this.enemies.find((e) => e.id === p.targetId && e.alive);
      if (tgt) { p.tx = tgt.x; p.ty = tgt.y; }
      const dx = p.tx - p.x, dy = p.ty - p.y;
      const dist = Math.hypot(dx, dy);
      const stepLen = p.speed * dt;
      if (dist <= stepLen + 0.3) {
        p.x = p.tx; p.y = p.ty;
        p.alive = false;
        if (p.kind === 'homing') this.explode(p, tw);
        else if (tgt && tw) {
          this.damage(tgt, p.damage, tw, { single: true, fx: p.sx, fy: p.sy });
          this.onHitExtras(tw, tgt, p.damage);
        }
      } else {
        p.x += (dx / dist) * stepLen;
        p.y += (dy / dist) * stepLen;
      }
    }
  }

  private explode(p: Projectile, tw: Tower | null) {
    const r = tw?.stats?.area ?? 1.5;
    this.events.push({ t: 'explode', x: p.x, y: p.y, r, color: p.color });
    let n = 0;
    const max = tw?.stats?.maxTargets ?? 5;
    const sorted = this.enemies.filter((e) => e.alive).sort((a, b) => Math.hypot(a.x - p.x, a.y - p.y) - Math.hypot(b.x - p.x, b.y - p.y));
    let first: Enemy | null = null;
    for (const e of sorted) {
      if (n >= max) break;
      if (tw && !this.canHit(tw, e)) continue;
      const reach = r + SIZES[e.size].radius + (e.arch === 'slinky' && e.stretched ? 0.6 : 0);
      if (Math.hypot(e.x - p.x, e.y - p.y) > reach) continue;
      if (e.airborne && p.kind === 'lob') continue;
      this.damage(e, p.damage, tw, { area: true, splash: true, fx: p.sx, fy: p.sy });
      first ??= e;
      n++;
    }
    if (first && tw) this.onHitExtras(tw, first, p.damage);
  }

  private stepPuddles(dt: number) {
    for (const pd of this.puddles) {
      pd.t -= dt;
      const tw = this.towerById(pd.tower) ?? null;
      let n = 0;
      for (const e of this.enemies) {
        if (n >= pd.maxTargets || !e.alive || e.airborne || e.overland) continue;
        if (Math.hypot(e.x - pd.x, e.y - pd.y) <= pd.r + 0.3) { this.damage(e, pd.dps * dt, tw, { dot: true, area: true }); n++; }
      }
    }
    this.puddles = this.puddles.filter((p) => p.t > 0);
  }

  private stepMines() {
    if (!this.wave) return;
    const burst = Math.max(COMBAT.mineBurst, COMBAT.mineBurstUnit * this.wave.unitHp);
    for (const rp of this.roadPieces) {
      if (rp.kind !== 'mine') continue;
      rp.cells.forEach(([x, y], i) => {
        if (!rp.mines[i]) return;
        const cx = x + 0.5, cy = y + 0.5;
        const trig = this.enemies.find((e) => e.alive && !e.overland && !e.airborne && Math.hypot(e.x - cx, e.y - cy) < 0.9);
        if (!trig) return;
        rp.mines[i] = false;
        this.events.push({ t: 'mine', x: cx, y: cy });
        for (const e of this.enemies) if (e.alive && !e.overland && !e.airborne && Math.hypot(e.x - cx, e.y - cy) <= COMBAT.mineRadius + SIZES[e.size].radius)
          this.damage(e, burst, null, { area: true, splash: true });
      });
      if (rp.mines.every((m) => !m)) {
        this.roadPieces = this.roadPieces.filter((r) => r !== rp);
        for (const [x, y] of rp.cells) this.objAt[cellIdx(x, y)] = 0;
      }
    }
  }

  private stepTanks(dt: number) {
    const mult = buildingMult(this.base, 'factory');
    for (const k of this.tanks) {
      k.d -= BUILDING_FX.tankSpeed * dt;
      const p = routeAt(k.route, k.d);
      k.x = p.x; k.y = p.y; k.dir = p.dir + Math.PI;
      if (k.d <= 0) { k.alive = false; continue; }
      k.cd -= dt;
      if (k.cd <= 0) {
        const tgt = this.enemies.find((e) => e.alive && !e.overland && Math.hypot(e.x - k.x, e.y - k.y) < BUILDING_FX.tankRange);
        if (tgt) {
          k.cd = 0.382;
          this.events.push({ t: 'shot', towerId: -1, kind: 'tank', x1: k.x, y1: k.y, x2: tgt.x, y2: tgt.y, color: 'gold' });
          this.damage(tgt, BUILDING_FX.tankDps * 0.382 * mult * (this.wave ? this.wave.unitHp / 100 : 1), null, { single: true });
        }
      }
    }
    this.tanks = this.tanks.filter((k) => k.alive);
  }

  private makeBattery(): Tower {
    const mult = buildingMult(this.base, 'missileBattery');
    const def = TOWERS['Missile'];
    const t: Tower = {
      id: this.nextId++, pieces: [], layers: [[[CORE_PT.x, CORE_PT.y]]], height: 0, type: 'Missile', hint: 'Base Missile Battery', active: true, activateT: 99,
      cx: CORE_PT.x, cy: CORE_PT.y, stats: null, cooldown: 0, targetId: 0, angle: 0, rampTarget: 0, rampT: 0, shots: 0, kills: 0, fireFlash: 0, baseTower: true,
    };
    const damage = def.dps * def.interval * 2 * mult;
    t.stats = {
      damage, interval: def.interval, range: BUILDING_FX.batteryRange, area: def.area, maxTargets: def.maxTargets, dps: damage / def.interval,
      pierce: 0, chain: 0, critChance: 0, slowOnHit: 0, essenceMult: 1, slowTrait: 0, dotTrait: 0, color: null, resonance: null,
      spire: false, pure: false, stories: 1, bonuses: [], shape: analyseShape([[0, 0]]), hint: '',
    };
    return t;
  }

  // ================================================================ helpers for UI and bots
  nextWavePreview(): WaveSpec | null {
    if (this.waveIndex >= WAVES_PER_BOARD[this.boardNo - 1]) return null;
    return makeWave(this.seed, this.boardNo, this.waveIndex + 1, this.mode);
  }
  get wavesInBoard() {
    return WAVES_PER_BOARD[this.boardNo - 1];
  }
  get dominant(): Suit {
    return dominantSuit(this.seed, this.boardNo);
  }
  drainEvents(): GameEvent[] {
    const e = this.events;
    this.events = [];
    return e;
  }
}

export { DT };
