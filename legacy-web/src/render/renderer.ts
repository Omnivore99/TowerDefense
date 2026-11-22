// PixiJS renderer: meadow terrain, road strikes, towers (2.5D), monsters, weapon effects, ghost and camera.
import { Application, Container, Graphics, Sprite, Text } from 'pixi.js';
import { COMBO, GRID_H, GRID_W, GROUPS, PHI, SIZES, TOWERS, T, type TowerType } from '../balance';
import type { Enemy, Game, GameEvent, Preview } from '../sim/game';
import { CORE_PT, type Board, cellIdx, macroCentre, type Pt } from '../sim/map';
import type { Cell, Piece } from '../sim/pieces';
import type { Tower } from '../sim/towers';
import { ART_SCALE, MonsterArt } from './monsterArt';
import { PAL, PIECE_HEX, mix, shade, suitColor } from './palette';
import { TERRAIN_PAL, drawRoad, drawTerrain } from './terrainArt';

type PKind = 'dot' | 'square' | 'ring' | 'spark' | 'spiral' | 'casing' | 'smoke' | 'flame' | 'snow' | 'coin' | 'gem' | 'debris' | 'pulse' | 'ember';
interface Particle {
  x: number; y: number; vx: number; vy: number; life: number; max: number; size: number; color: number;
  kind: PKind; g: number; spin: number; ang: number; r0?: number; cx?: number; cy?: number;
  z?: number; vz?: number; glow?: boolean; rest?: number;
}
interface FloatText { t: Text; x: number; y: number; life: number; max: number; vy: number; world: boolean }
interface Drop { pieceId: number; cells: Cell[]; color: number; t: number; dur: number; height: number; towerId?: number; size: number }
interface Flash { kind: string; x1: number; y1: number; x2: number; y2: number; life: number; max: number; color: number; seed: number; w?: number }
interface Decal { x: number; y: number; r: number; life: number; max: number; color: number; kind: 'scorch' | 'stain' }
interface TowerView { c: Container; base: Graphics; turret: Graphics; version: string; lastPulse: number }
interface EnemyView { c: Container; shadow: Sprite; body: Sprite; badge: Sprite | null; shield: Sprite; key: string; stepT: number }

const LAYER_LIFT = 0.42; // cells of lift per story
const ENEMY_VIS = 1.7; // enemies draw larger than their hit radius so they read at small cell sizes
const TURRET_VIS = 1.45;
const MAX_ZOOM = 4.5;
const FLIP_FORMS = new Set(['hopper', 'blob', 'swinger', 'tumbler', 'balloon', 'roller']);

export class Renderer {
  app: Application;
  art: MonsterArt;
  world = new Container();
  private terrain = new Graphics();
  private roadG = new Graphics();
  private decalG = new Graphics();
  private oreG = new Graphics();
  private coreC = new Container();
  private coreG = new Graphics();
  private objG = new Graphics();
  private towerLayer = new Container();
  private enemyLayer = new Container();
  private fx = new Graphics();
  private particlesG = new Graphics();
  private glow = new Graphics();
  private ghostG = new Graphics();
  private screen = new Container();
  private edgeGlow = new Graphics();

  cell = 10;
  zoom = 1;
  private camZoom = 1;
  offX = 0;
  offY = 0;
  pan = { x: 0, y: 0 };
  viewport = { left: 176, top: 60, right: 12, bottom: 64 };
  private camTarget: { zoom: number; x: number; y: number } | null = null;
  reducedMotion = false;
  showRanges = false;
  selectedTower = 0;
  undoMark: { cells: Cell[]; frac: number } | null = null;

  private towers = new Map<number, TowerView>();
  private enemies = new Map<number, EnemyView>();
  private particles: Particle[] = [];
  private texts: FloatText[] = [];
  private drops: Drop[] = [];
  private flashes: Flash[] = [];
  private decals: Decal[] = [];
  private embers: { cells: number[]; t: number; max: number } | null = null;
  private hiddenPieces = new Set<number>();
  private shake = { x: 0, y: 0, t: 0, mag: 0 };
  private nudge = { x: 0, y: 0 };
  private boardRef: Board | null = null;
  private boardVersion = -1;
  private time = 0;
  private cascade = 0;
  private perfectFlash = 0;
  private strikeFlash = 0;
  private strikeT = 0;
  ghost: { piece: Piece; pv: Preview; range: number } | null = null;
  smiteAim: { x: number; y: number; r: number } | null = null;
  hoverEdge: [number, number] | null = null;

  constructor(app: Application) {
    this.app = app;
    this.art = new MonsterArt(app.renderer);
    this.world.addChild(this.terrain, this.oreG, this.roadG, this.decalG, this.coreC, this.objG, this.towerLayer, this.enemyLayer, this.fx, this.particlesG, this.glow, this.ghostG);
    this.coreC.addChild(this.coreG);
    this.glow.blendMode = 'add';
    this.towerLayer.sortableChildren = true;
    this.enemyLayer.sortableChildren = true;
    app.stage.addChild(this.world, this.screen, this.edgeGlow);
  }

  // ================================================================ camera
  private baseCell() {
    const W = this.app.screen.width, H = this.app.screen.height;
    const v = this.viewport;
    return Math.max(2, Math.min((W - v.left - v.right) / GRID_W, (H - v.top - v.bottom) / GRID_H));
  }
  private viewCentre() {
    const W = this.app.screen.width, H = this.app.screen.height;
    const v = this.viewport;
    return { x: v.left + (W - v.left - v.right) / 2, y: v.top + (H - v.top - v.bottom) / 2, w: W - v.left - v.right, h: H - v.top - v.bottom };
  }
  layout() {
    const base = this.baseCell();
    this.cell = base * this.zoom * this.camZoom;
    const bw = GRID_W * this.cell, bh = GRID_H * this.cell;
    const c = this.viewCentre();
    this.offX = c.x - bw / 2 + this.pan.x;
    this.offY = c.y - bh / 2 + this.pan.y;
  }
  private clampPan() {
    const c = this.viewCentre();
    const cell = this.baseCell() * this.zoom * this.camZoom;
    const mx = Math.max(0, (GRID_W * cell - c.w) / 2 + 80), my = Math.max(0, (GRID_H * cell - c.h) / 2 + 80);
    this.pan.x = Math.max(-mx, Math.min(mx, this.pan.x));
    this.pan.y = Math.max(-my, Math.min(my, this.pan.y));
  }
  /** Zoom by k, keeping the world point under the screen point (sx, sy) fixed. */
  zoomAt(sx: number, sy: number, k: number) {
    this.camTarget = null;
    this.layout();
    const w = this.toWorld(sx, sy);
    this.zoom = Math.max(1, Math.min(MAX_ZOOM, this.zoom * k));
    this.layout();
    const s = this.toScreen(w.x, w.y);
    this.pan.x += sx - s.x;
    this.pan.y += sy - s.y;
    this.clampPan();
    this.layout();
  }
  panBy(dx: number, dy: number) {
    this.camTarget = null;
    this.pan.x += dx;
    this.pan.y += dy;
    this.clampPan();
  }
  /** Ease the camera to frame a world rectangle. */
  focus(x0: number, y0: number, x1: number, y1: number, maxZoom = 2.2) {
    const c = this.viewCentre();
    const base = this.baseCell();
    const zoom = Math.max(1, Math.min(maxZoom, Math.min(c.w / ((x1 - x0 + 16) * base), c.h / ((y1 - y0 + 16) * base))));
    const cell = base * zoom * this.camZoom;
    const wx = (x0 + x1) / 2, wy = (y0 + y1) / 2;
    const x = c.x - wx * cell - (c.x - (GRID_W * cell) / 2);
    const y = c.y - wy * cell - (c.y - (GRID_H * cell) / 2);
    this.camTarget = { zoom, x, y };
  }
  private stepCamera(dt: number) {
    const t = this.camTarget;
    if (!t) return;
    const k = Math.min(1, dt * 2.2);
    this.zoom += (t.zoom - this.zoom) * k;
    this.pan.x += (t.x - this.pan.x) * k;
    this.pan.y += (t.y - this.pan.y) * k;
    this.clampPan();
    if (Math.abs(t.zoom - this.zoom) < 0.002 && Math.abs(t.x - this.pan.x) < 0.5 && Math.abs(t.y - this.pan.y) < 0.5) this.camTarget = null;
  }
  toWorld(sx: number, sy: number) {
    return { x: (sx - this.offX) / this.cell, y: (sy - this.offY) / this.cell };
  }
  toScreen(x: number, y: number) {
    return { x: this.offX + x * this.cell, y: this.offY + y * this.cell };
  }
  addShake(mag: number) {
    if (this.reducedMotion) return;
    this.shake.mag = Math.min(1.2, Math.max(this.shake.mag, mag));
    this.shake.t = 0.236;
  }

  // ================================================================ board
  setBoard(b: Board) {
    this.boardRef = b;
    this.boardVersion = -1;
    for (const v of this.towers.values()) v.c.destroy({ children: true });
    for (const v of this.enemies.values()) v.c.destroy({ children: true });
    this.towers.clear();
    this.enemies.clear();
    this.particles = [];
    this.drops = [];
    this.flashes = [];
    this.decals = [];
    this.hiddenPieces.clear();
    this.zoom = 1;
    this.pan = { x: 0, y: 0 };
    this.camTarget = null;
    this.drawCore();
  }

  private redrawGround(b: Board) {
    drawTerrain(this.terrain, b);
    drawRoad(this.roadG, b);
    this.boardVersion = b.version;
  }

  private drawCore() {
    const g = this.coreG;
    g.clear();
    const s = 0.5;
    const sq: [number, number, number][] = [[0, 0, 8], [8, 0, 5], [10, 5, 3], [8, 6, 2], [8, 5, 1], [9, 5, 1]];
    const ox = -8.5 * s, oy = -5.5 * s;
    g.circle(0, 0.5, 4.4).fill({ color: 0x000000, alpha: 0.3 });
    g.circle(0, 0, 4.2).fill({ color: PAL.core, alpha: 0.08 });
    g.circle(0, 0, 3.15).fill(0x2a2114);
    g.circle(0, 0, 3.15).stroke({ width: 0.35, color: 0x5a4524 });
    g.circle(0, 0, 2.8).fill(0x221a10);
    for (const [x, y, n] of sq) g.rect(ox + x * s, oy + y * s, n * s, n * s).stroke({ width: 0.06, color: PAL.core, alpha: 0.35 });
    let r = 0.12, a = 0;
    g.moveTo(0, 0);
    for (let i = 0; i < 160; i++) {
      a += 0.08;
      r *= Math.pow(PHI, 0.08 / (Math.PI / 2));
      if (r > 2.9) break;
      g.lineTo(Math.cos(a) * r, Math.sin(a) * r);
    }
    g.stroke({ width: 0.16, color: PAL.core, alpha: 0.95, cap: 'round' });
    g.circle(0, 0, 0.45).fill(PAL.core);
    g.circle(-0.12, -0.12, 0.15).fill({ color: 0xffffff, alpha: 0.7 });
    g.circle(0, 0, 3.1).stroke({ width: 0.12, color: PAL.core, alpha: 0.6 });
    this.coreC.position.set(CORE_PT.x, CORE_PT.y);
  }

  // ================================================================ road strike
  private strikePts(game: Game): Pt[] | null {
    const p = game.board.pending;
    if (!p) return null;
    return [p.start, ...p.path.map(macroCentre)];
  }

  private drawStrike(game: Game, g: Graphics, gl: Graphics) {
    const pts = this.strikePts(game);
    if (!pts) return;
    const total = game.board.revealTotal();
    const prog = Math.max(0, Math.min(1, game.revealStep / total));
    // cumulative lengths
    const cum = [0];
    for (let i = 1; i < pts.length; i++) cum.push(cum[i - 1] + Math.hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y));
    const L = cum[cum.length - 1] * prog;
    const burned: Pt[] = [pts[0]];
    let head = pts[0];
    for (let i = 1; i < pts.length; i++) {
      if (cum[i] <= L) { burned.push(pts[i]); head = pts[i]; continue; }
      const t = (L - cum[i - 1]) / (cum[i] - cum[i - 1] || 1);
      head = { x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * t, y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * t };
      burned.push(head);
      break;
    }
    // first instant: the whole bolt flashes along the route
    const st = this.strikeT;
    if (st < 0.55) {
      const a = 1 - st / 0.55;
      for (let k = 0; k < 2; k++) {
        gl.moveTo(pts[0].x, pts[0].y);
        for (let i = 1; i < pts.length; i++) {
          const m = { x: (pts[i - 1].x + pts[i].x) / 2 + Math.sin(i * 12.9 + k * 3 + this.time * 40) * 1.6, y: (pts[i - 1].y + pts[i].y) / 2 + Math.cos(i * 7.3 + k * 5 + this.time * 37) * 1.6 };
          gl.lineTo(m.x, m.y).lineTo(pts[i].x, pts[i].y);
        }
        gl.stroke({ width: k ? 0.25 : 1.4, color: k ? 0xffffff : 0x9fd8ff, alpha: a * (k ? 1 : 0.5), cap: 'round', join: 'round' });
      }
      // sky bolt into the spawn point
      this.jagged(gl, pts[0].x + 6, pts[0].y - 40, pts[0].x, pts[0].y, 0xd9f2ff, 0.5 * a + 0.1, a, 3);
    }
    // the road burns in behind the head
    this.polyline(g, burned, 3.0, 0x2a1a10, 0.85);
    this.polyline(gl, burned, 1.3, 0xff8a3d, 0.55);
    this.polyline(gl, burned, 0.35, 0xffe0a0, 0.8);
    if (prog < 1) {
      const flick = Math.sin(this.time * 40) * 0.5 + 0.5;
      gl.circle(head.x, head.y, 1.8 + flick * 0.7).fill({ color: 0xbfe8ff, alpha: 0.35 });
      for (let k = 0; k < 4; k++) {
        const ang = this.time * 7 + k * 1.6 + Math.sin(this.time * 31 + k) * 0.8;
        this.jagged(gl, head.x, head.y, head.x + Math.cos(ang) * 4.5, head.y + Math.sin(ang) * 4.5, 0xd9f2ff, 0.14, 0.8, k * 13);
      }
      gl.circle(head.x, head.y, 0.7).fill(0xffffff);
      if (!this.reducedMotion && Math.random() < 0.7) this.spark(head.x, head.y, Math.random() < 0.5 ? 0xffd28a : 0xbfe8ff, 9);
    }
  }

  private polyline(g: Graphics, pts: { x: number; y: number }[], w: number, color: number, alpha: number) {
    if (pts.length < 2) return;
    g.moveTo(pts[0].x, pts[0].y);
    for (let i = 1; i < pts.length; i++) g.lineTo(pts[i].x, pts[i].y);
    g.stroke({ width: w, color, alpha, cap: 'round', join: 'round' });
  }

  private jagged(g: Graphics, x1: number, y1: number, x2: number, y2: number, color: number, w: number, alpha: number, seed = Math.random() * 1000) {
    const n = 8;
    g.moveTo(x1, y1);
    const dx = x2 - x1, dy = y2 - y1, len = Math.hypot(dx, dy) || 1;
    const nx = -dy / len, ny = dx / len;
    for (let i = 1; i < n; i++) {
      const t = i / n;
      const off = ((Math.sin(seed * 12.9898 + i * 78.233 + this.time * 30) * 43758.5453) % 1) * len * 0.12;
      g.lineTo(x1 + dx * t + nx * off, y1 + dy * t + ny * off);
    }
    g.lineTo(x2, y2);
    g.stroke({ width: w, color, alpha, cap: 'round', join: 'round' });
  }

  // ================================================================ objects (ore, harvesters, road pieces, spawns)
  private drawObjects(game: Game) {
    const g = this.objG;
    g.clear();
    const b = game.board;
    const pulse = 0.55 + 0.45 * Math.sin(this.time * 2.2);
    const og = this.oreG;
    og.clear();
    for (const v of b.veins) {
      og.roundRect(v.x - 0.4, v.y - 0.4, 3.8, 3.8, 0.8).fill({ color: PAL.ore, alpha: 0.06 + 0.07 * pulse });
      og.roundRect(v.x - 0.1, v.y - 0.1, 3.2, 3.2, 0.5).fill({ color: 0x14303a, alpha: 0.9 });
      for (let dy = 0; dy < 3; dy++)
        for (let dx = 0; dx < 3; dx++) {
          const x = v.x + dx, y = v.y + dy;
          const h = 0.55 + ((dx * 7 + dy * 3) % 5) * 0.08;
          og.poly([x + 0.5, y + 0.95 - h, x + 0.78, y + 0.6, x + 0.5, y + 0.92, x + 0.22, y + 0.6]).fill({ color: 0x3fb8c8, alpha: 1 });
          og.poly([x + 0.5, y + 0.95 - h, x + 0.78, y + 0.6, x + 0.5, y + 0.7]).fill({ color: PAL.ore, alpha: 0.55 + 0.4 * pulse });
          og.circle(x + 0.42, y + 0.98 - h, 0.05).fill({ color: 0xffffff, alpha: 0.8 * pulse });
        }
    }
    for (const h of game.harvesters) {
      if (this.hiddenPieces.has(h.piece.id)) continue;
      this.cellsBlock(g, h.cells, PIECE_HEX[h.piece.color], 0, 0.9);
      const c = this.centroid(h.cells);
      const a = this.time * 3;
      for (let k = 0; k < 4; k++) g.moveTo(c.x, c.y).lineTo(c.x + Math.cos(a + k * 1.57) * 0.6, c.y + Math.sin(a + k * 1.57) * 0.6);
      g.stroke({ width: 0.18, color: 0x10202a, cap: 'round' });
      g.circle(c.x, c.y, 0.22).fill(PAL.ore);
    }
    for (const rp of game.roadPieces) {
      if (this.hiddenPieces.has(rp.piece.id)) continue;
      if (rp.kind === 'barrier') {
        const bb = this.bboxOf(rp.cells);
        g.roundRect(bb.x0 + 0.05, bb.y0 + 0.25, bb.w - 0.1, bb.h - 0.1, 0.3).fill(0x4d4f63);
        g.roundRect(bb.x0 + 0.05, bb.y0 + 0.05, bb.w - 0.1, bb.h - 0.3, 0.3).fill(0xb9bcd4);
        for (let i = 1; i < bb.w; i++) g.moveTo(bb.x0 + i, bb.y0 + 0.2).lineTo(bb.x0 + i, bb.y1 + 0.7);
        g.stroke({ width: 0.06, color: 0x5c5e75 });
        for (let i = 0; i < bb.w * 2; i++) g.rect(bb.x0 + 0.1 + i * 0.5, bb.y0 + 0.12, 0.25, 0.12).fill(i % 2 ? 0x1a1a1a : 0xffd36b);
        if (rp.maxHp > 0) {
          const f = Math.max(0, rp.hp / rp.maxHp);
          g.rect(bb.x0, bb.y0 - 0.5, bb.w, 0.22).fill({ color: 0x000000, alpha: 0.5 });
          g.rect(bb.x0, bb.y0 - 0.5, bb.w * f, 0.22).fill(0xd0d4ff);
        }
      } else {
        rp.cells.forEach(([x, y], i) => {
          if (!rp.mines[i]) return;
          g.circle(x + 0.5, y + 0.55, 0.36).fill({ color: 0x000000, alpha: 0.3 });
          g.circle(x + 0.5, y + 0.5, 0.34).fill(0x30333f);
          g.circle(x + 0.5, y + 0.5, 0.34).stroke({ width: 0.06, color: PIECE_HEX[rp.piece.color] });
          const blink = Math.sin(this.time * 5 + i) > 0.6;
          g.circle(x + 0.5, y + 0.45, 0.1).fill(blink ? 0xff4a4a : 0x5a1a1a);
        });
      }
    }
    // spawn portals at every road start
    for (const p of b.paths) this.portal(g, p.start.x, p.start.y);
  }

  private portal(g: Graphics, x: number, y: number) {
    const cx = Math.max(1.5, Math.min(GRID_W - 1.5, x)), cy = Math.max(1.5, Math.min(GRID_H - 1.5, y));
    g.circle(cx, cy, 2.0).fill({ color: 0x2a0a18, alpha: 0.75 });
    for (let k = 0; k < 3; k++) {
      const a = this.time * (1.5 + k * 0.4) + k * 2.1;
      const rr = 1.2 + k * 0.3;
      g.moveTo(cx + Math.cos(a) * rr, cy + Math.sin(a) * rr).arc(cx, cy, rr, a, a + 2.2).stroke({ width: 0.14, color: k === 1 ? 0xff9ab0 : PAL.bad, alpha: 0.75 });
    }
    this.glow.circle(cx, cy, 1.0 + Math.sin(this.time * 3) * 0.15).fill({ color: PAL.bad, alpha: 0.18 });
  }

  private centroid(cells: Cell[]) {
    return { x: cells.reduce((s, c) => s + c[0] + 0.5, 0) / cells.length, y: cells.reduce((s, c) => s + c[1] + 0.5, 0) / cells.length };
  }
  private bboxOf(cells: Cell[]) {
    const xs = cells.map((c) => c[0]), ys = cells.map((c) => c[1]);
    const x0 = Math.min(...xs), y0 = Math.min(...ys), x1 = Math.max(...xs), y1 = Math.max(...ys);
    return { x0, y0, x1, y1, w: x1 - x0 + 1, h: y1 - y0 + 1 };
  }

  /** Bevelled cell blocks with a side face (lift in cells). */
  private cellsBlock(g: Graphics, cells: Cell[], color: number, lift: number, alpha = 1, outline = true) {
    const set = new Set(cells.map(([x, y]) => y * 1000 + x));
    const has = (x: number, y: number) => set.has(y * 1000 + x);
    const side = shade(color, -0.45);
    for (const [x, y] of cells) if (!has(x, y + 1)) g.rect(x, y + 1 - lift, 1, lift + 0.001 + 0.2).fill({ color: side, alpha });
    for (const [x, y] of cells) {
      g.rect(x, y - lift, 1, 1).fill({ color, alpha });
      g.rect(x + 0.1, y - lift + 0.1, 0.8, 0.14).fill({ color: 0xffffff, alpha: 0.24 * alpha });
      g.rect(x + 0.1, y - lift + 0.76, 0.8, 0.12).fill({ color: 0x000000, alpha: 0.1 * alpha });
    }
    if (outline) {
      for (const [x, y] of cells) {
        const yy = y - lift;
        if (!has(x, y - 1)) g.moveTo(x, yy).lineTo(x + 1, yy);
        if (!has(x, y + 1)) g.moveTo(x, yy + 1).lineTo(x + 1, yy + 1);
        if (!has(x - 1, y)) g.moveTo(x, yy).lineTo(x, yy + 1);
        if (!has(x + 1, y)) g.moveTo(x + 1, yy).lineTo(x + 1, yy + 1);
      }
      g.stroke({ width: 0.08, color: shade(color, -0.55), alpha });
    }
  }

  // ================================================================ towers
  private turretScale(t: Tower) {
    return TURRET_VIS * Math.min(1.25, 0.8 + t.layers[0].length / 40);
  }
  /** World position of a tower's muzzle. */
  private muzzle(t: Tower, len = 1.5) {
    const lift = (t.layers.length - 1) * LAYER_LIFT + 0.2;
    const s = this.turretScale(t);
    return { x: t.cx + Math.cos(t.angle) * len * s, y: t.cy - lift - 0.25 + Math.sin(t.angle) * len * s };
  }

  private syncTowers(game: Game) {
    const live = new Set<number>();
    for (const t of game.towers) {
      live.add(t.id);
      let v = this.towers.get(t.id);
      if (!v) {
        const c = new Container();
        const base = new Graphics();
        const turret = new Graphics();
        c.addChild(base, turret);
        this.towerLayer.addChild(c);
        v = { c, base, turret, version: '', lastPulse: 0 };
        this.towers.set(t.id, v);
      }
      const hidden = t.pieces.filter((p) => this.hiddenPieces.has(p.piece.id)).map((p) => p.piece.id).join(',');
      const ver = `${t.pieces.length}|${t.type}|${hidden}|${t.active}`;
      if (ver !== v.version) {
        v.version = ver;
        this.drawTowerBase(v.base, t);
        this.drawTurret(v.turret, t);
      }
      const lift = (t.layers.length - 1) * LAYER_LIFT + 0.2;
      const recoil = t.fireFlash > 0 ? (t.fireFlash / 0.08) * 0.35 : 0;
      v.turret.position.set(t.cx - Math.cos(t.angle) * recoil, t.cy - lift - 0.25 - Math.sin(t.angle) * recoil);
      if (t.active) {
        const k = Math.min(1, t.activateT / T.l);
        const s = (k < 1 ? this.elastic(k) : 1) * this.turretScale(t);
        v.turret.scale.set(s);
        v.turret.rotation = t.angle + Math.PI / 2;
        v.turret.visible = true;
      } else v.turret.visible = false;
      v.base.tint = t.corroded ? mix(0xffffff, 0xb6ff5c, 0.35 + 0.15 * Math.sin(this.time * 8)) : 0xffffff;
      v.c.zIndex = t.cy;
    }
    for (const [id, v] of this.towers) if (!live.has(id)) { v.c.destroy({ children: true }); this.towers.delete(id); }
  }

  private elastic(k: number) {
    const c1 = 1.70158, c3 = c1 + 1;
    return 1 + c3 * Math.pow(k - 1, 3) + c1 * Math.pow(k - 1, 2);
  }

  private drawTowerBase(g: Graphics, t: Tower) {
    g.clear();
    const ground = t.layers[0];
    for (const [x, y] of ground) g.rect(x + 0.25, y + 0.3, 1, 1).fill({ color: 0x000000, alpha: 0.3 });
    const layers = t.layers.length;
    for (let l = 0; l < layers; l++) {
      const lift = l * LAYER_LIFT;
      for (const p of t.pieces) {
        if (p.layer !== l || this.hiddenPieces.has(p.piece.id)) continue;
        let c = PIECE_HEX[p.piece.color];
        if (!t.active) c = mix(c, 0x55607a, 0.45);
        if (p.piece.golden) c = 0xffe08a;
        this.cellsBlock(g, p.cells, c, lift);
        if (p.piece.glyph) {
          const cc = this.centroid(p.cells);
          g.circle(cc.x, cc.y - lift, 0.22).fill({ color: 0xffffff, alpha: 0.85 });
          g.circle(cc.x, cc.y - lift, 0.12).fill(shade(c, -0.5));
        }
      }
      if (l + 1 < layers) for (const [x, y] of t.layers[l + 1]) g.rect(x + 0.12, y - lift + 0.12, 1, 1).fill({ color: 0x000000, alpha: 0.18 });
    }
    if (t.stats) for (const [x, y] of t.stats.shape.holes) {
      g.moveTo(x + 0.2, y + 0.2).lineTo(x + 0.5, y + 0.55).lineTo(x + 0.4, y + 0.8).moveTo(x + 0.5, y + 0.55).lineTo(x + 0.85, y + 0.4);
      g.stroke({ width: 0.08, color: PAL.bad, alpha: 0.8 });
    }
  }

  private drawTurret(g: Graphics, t: Tower) {
    g.clear();
    if (!t.type) return;
    const col = t.stats?.color ? PIECE_HEX[t.stats.color] : 0xdfe6ff;
    const dark = 0x1a2036, metal = 0xc9d0e3, metalLt = 0xf2f5ff, metalDk = 0x6b7390;
    const ring = (r: number, c = col, w = 0.14) => g.circle(0, 0, r).stroke({ width: w, color: c });
    const barrel = (x: number, w: number, len: number) => {
      g.roundRect(x - w / 2, -len, w, len - 0.1, w * 0.3).fill(metalDk);
      g.roundRect(x - w / 2 + 0.03, -len, w * 0.45, len - 0.1, w * 0.2).fill(metalLt);
      g.rect(x - w / 2 - 0.04, -len, w + 0.08, 0.16).fill(dark);
    };
    g.circle(0, 0.18, 1.05).fill({ color: 0x000000, alpha: 0.3 });
    g.circle(0, 0, 0.98).fill(dark);
    g.circle(0, 0, 0.82).fill(0x2a3150);
    g.circle(-0.2, -0.25, 0.4).fill({ color: 0xffffff, alpha: 0.08 });
    ring(0.95, col, 0.13);
    switch (t.type) {
      case 'Gun': barrel(0, 0.38, 1.7); g.roundRect(-0.35, -0.5, 0.7, 0.6, 0.1).fill(metal); break;
      case 'Machine Gun':
        barrel(-0.24, 0.22, 1.55); barrel(0.24, 0.22, 1.55);
        g.roundRect(-0.45, -0.45, 0.9, 0.55, 0.1).fill(metal);
        g.rect(-0.08, -0.4, 0.16, 0.45).fill(0x8a6a2a);
        break;
      case 'Rifle': barrel(0, 0.24, 2.3); g.rect(-0.28, -0.7, 0.56, 0.3).fill(col); g.circle(0, -1.1, 0.16).fill(0x9fd8ff); break;
      case 'Bomb': g.circle(0, -0.35, 0.65).fill(metalDk); g.circle(0, -0.35, 0.65).stroke({ width: 0.08, color: metal }); g.circle(0, -0.35, 0.34).fill(dark); g.circle(-0.18, -0.55, 0.12).fill({ color: 0xffffff, alpha: 0.35 }); break;
      case 'Missile':
        g.roundRect(-0.6, -0.6, 1.2, 0.85, 0.12).fill(metalDk);
        for (const dx of [-0.38, 0, 0.38]) { g.poly([dx - 0.13, -0.2, dx + 0.13, -0.2, dx, -1.2]).fill(metalLt); g.rect(dx - 0.13, -0.3, 0.26, 0.12).fill(0xff6b6b); }
        break;
      case 'Laser': g.poly([-0.5, -0.3, 0.5, -0.3, 0.16, -1.5, -0.16, -1.5]).fill(0xbfd7ff); g.poly([-0.5, -0.3, -0.1, -0.3, -0.05, -1.5, -0.16, -1.5]).fill({ color: 0xffffff, alpha: 0.4 }); g.circle(0, -1.5, 0.2).fill(col); g.circle(0, -1.5, 0.35).fill({ color: col, alpha: 0.3 }); break;
      case 'Pulsar': ring(0.55, col, 0.18); g.rect(-0.1, -1.75, 0.2, 1.35).fill(col); g.circle(0, -1.75, 0.18).fill(0xffffff); break;
      case 'Lightning':
        g.rect(-0.08, -1.7, 0.16, 1.6).fill(metal);
        for (let k = 0; k < 3; k++) g.ellipse(0, -0.6 - k * 0.38, 0.3 - k * 0.05, 0.08).stroke({ width: 0.06, color: 0xd9a050 });
        g.circle(0, -1.8, 0.32).fill(0xbfe8ff); g.circle(0, -1.8, 0.5).fill({ color: 0xbfe8ff, alpha: 0.25 });
        break;
      case 'E-Field': ring(0.5, 0xbfe8ff, 0.12); ring(0.25, 0xbfe8ff, 0.1); for (let k = 0; k < 4; k++) { const a = k * Math.PI / 2 + 0.78; g.circle(Math.cos(a) * 0.62, Math.sin(a) * 0.62, 0.1).fill(0xbfe8ff); } break;
      case 'Freezer': for (let k = 0; k < 6; k++) { const a = (k * Math.PI) / 3; g.moveTo(0, 0).lineTo(Math.cos(a) * 0.78, Math.sin(a) * 0.78); g.moveTo(Math.cos(a) * 0.45, Math.sin(a) * 0.45).lineTo(Math.cos(a + 0.4) * 0.6, Math.sin(a + 0.4) * 0.6); } g.stroke({ width: 0.12, color: 0xcff6ff, cap: 'round' }); g.circle(0, 0, 0.2).fill(0xffffff); break;
      case 'Flamer': g.poly([-0.32, -0.2, 0.32, -0.2, 0.48, -1.35, -0.48, -1.35]).fill(metalDk); g.poly([-0.32, -0.2, 0.0, -0.2, -0.1, -1.35, -0.48, -1.35]).fill({ color: 0xffffff, alpha: 0.2 }); g.rect(-0.5, -1.45, 1.0, 0.16).fill(0xffb06b); g.circle(0.45, 0.2, 0.28).fill(0xff6b3d); break;
      case 'Acid': g.circle(0, -0.3, 0.52).fill(0x8cff7a); g.circle(-0.15, -0.45, 0.16).fill({ color: 0xffffff, alpha: 0.45 }); g.rect(-0.15, -1.35, 0.3, 0.9).fill(0x6fd860); break;
      case 'Virus': for (let k = 0; k < 8; k++) { const a = (k * Math.PI) / 4; g.moveTo(Math.cos(a) * 0.4, Math.sin(a) * 0.4).lineTo(Math.cos(a) * 0.62, Math.sin(a) * 0.62).stroke({ width: 0.06, color: 0xd88cff }); g.circle(Math.cos(a) * 0.66, Math.sin(a) * 0.66, 0.12).fill(0xd88cff); } g.circle(0, 0, 0.42).fill(0xb05ce0); g.circle(-0.12, -0.12, 0.12).fill({ color: 0xffffff, alpha: 0.4 }); break;
    }
    if (t.stats?.pure) g.circle(0, 0, 0.2).fill(0xffe08a);
  }

  // ================================================================ enemies
  private syncEnemies(game: Game, alpha: number, dt: number) {
    const live = new Set<number>();
    for (const e of game.enemies) {
      live.add(e.id);
      let v = this.enemies.get(e.id);
      if (!v) {
        const c = new Container();
        const shadow = new Sprite(this.art.shadow);
        const body = new Sprite();
        const shield = new Sprite(this.art.shield);
        shadow.anchor.set(0.5); body.anchor.set(0.5); shield.anchor.set(0.5);
        c.addChild(shadow, body, shield);
        let badge: Sprite | null = null;
        if (e.size !== 'mite') {
          badge = new Sprite(this.art.badge(e.element, e.group));
          badge.anchor.set(0.5);
          c.addChild(badge);
        }
        this.enemyLayer.addChild(c);
        v = { c, shadow, body, badge, shield, key: '', stepT: 0 };
        this.enemies.set(e.id, v);
        c.scale.set(0.01);
      }
      const x = e.px + (e.x - e.px) * alpha, y = e.py + (e.y - e.py) * alpha;
      const r = SIZES[e.size].radius * e.scale * ENEMY_VIS;
      const color = suitColor(e.suit, e.size);
      const nf = this.art.frames(e.arch);
      const frame = nf > 1 ? Math.floor(e.animT * (e.size === 'mite' ? 14 : 9)) % 4 : 0;
      const variant = e.arch === 'slinky' && e.stretched ? 1 : 0;
      const key = `${e.arch}|${color}|${e.tier}|${frame}|${variant}|${e.champion || e.boss}`;
      if (key !== v.key) {
        v.key = key;
        v.body.texture = this.art.body(e.arch, color, e.tier, frame, variant, e.champion || e.boss);
      }
      let sx = 1, sy = 1, oy = 0;
      if (e.arch === 'hopper') {
        const ph = (e.animT % 0.618) / 0.618;
        if (ph < 0.45) { oy = -Math.sin((ph / 0.45) * Math.PI) * 0.9 * Math.max(0.6, r); sx = 0.9; sy = 1.12; } else { const k = Math.sin(((ph - 0.45) / 0.55) * Math.PI); sx = 1 + 0.25 * k; sy = 1 - 0.22 * k; }
      } else if (e.arch === 'blob') {
        sx = 1 + Math.sin(e.animT * 6) * 0.08; sy = 1 - Math.sin(e.animT * 6) * 0.08;
      }
      if (e.arch === 'balloon') oy = -1.6 + Math.sin(e.animT * 2) * 0.2;
      const grow = Math.min(1, v.c.scale.x + dt * 5);
      const pop = e.hitFlash > 0 ? 1.12 : 1;
      v.c.position.set(x, y);
      v.c.scale.set(grow);
      v.c.zIndex = y;
      const cosd = Math.cos(e.sdir);
      const flip = FLIP_FORMS.has(e.arch) ? (cosd < -0.15 ? -1 : 1) : 1;
      const bs = r * ART_SCALE * pop;
      v.body.position.set(0, oy);
      v.body.scale.set(bs * sx * flip, bs * sy);
      if (e.arch === 'roller') v.body.rotation = e.d * 1.4 * (cosd < 0 ? -1 : 1);
      else if (e.arch === 'tumbler') v.body.rotation = Math.floor(e.animT / 1.2) * (Math.PI / 2) + Math.min(1, (e.animT % 1.2) / 0.236) * (Math.PI / 2);
      else if (FLIP_FORMS.has(e.arch)) v.body.rotation = 0;
      else v.body.rotation = e.sdir;
      v.shadow.position.set(0, r * 0.7);
      const air = oy < 0 ? Math.max(0.55, 1 + oy * 0.25) : 1;
      v.shadow.scale.set(r * ART_SCALE * 1.05 * air);
      v.shadow.alpha = e.arch === 'balloon' ? 0.5 : 1;
      v.body.alpha = e.immune ? 0.35 : 1;
      v.body.tint = e.immune ? 0xc8b8ff : e.slowMult < 1 ? 0xbfefff : 0xffffff;
      v.shield.visible = e.shield > 0;
      if (e.shield > 0) {
        v.shield.position.set(0, oy);
        v.shield.scale.set(r * ART_SCALE * (1 + Math.sin(this.time * 4 + e.id) * 0.03));
        v.shield.alpha = 0.35 + 0.65 * Math.min(1, e.shield / Math.max(1, e.maxHp * 0.38));
      }
      if (v.badge) {
        const bsz = (e.champion || e.boss ? 1.0 : 0.55) * ART_SCALE;
        v.badge.scale.set(bsz);
        v.badge.position.set(r * 0.75, oy - r * 0.9);
      }
      // tier IV and champions trail sparks; champions shake the ground
      if (!this.reducedMotion && e.tier >= 4 && Math.random() < (e.champion ? 0.5 : 0.12))
        this.particles.push({ x: x + (Math.random() - 0.5) * r, y: y + oy + (Math.random() - 0.5) * r, vx: 0, vy: -1.5, life: 0.6, max: 0.6, size: 0.14, color: 0xffd36b, kind: 'dot', g: 0, spin: 0, ang: 0, glow: true });
      if (e.champion || e.boss) {
        v.stepT -= dt;
        if (v.stepT <= 0) {
          v.stepT = 0.7;
          this.addShake(0.05);
          this.particles.push({ x, y: y + r * 0.6, vx: 0, vy: 0, life: 0.5, max: 0.5, size: r * 1.4, r0: r * 0.5, color: 0xcfc6b0, kind: 'ring', g: 0, spin: 0, ang: 0 });
        }
      }
    }
    for (const [id, v] of this.enemies) if (!live.has(id)) { v.c.destroy({ children: true }); this.enemies.delete(id); }
  }

  // ================================================================ events → effects
  handleEvents(events: GameEvent[], game: Game) {
    const rm = this.reducedMotion;
    for (const ev of events) {
      switch (ev.t) {
        case 'place': {
          this.drops.push({ pieceId: ev.pieceId, cells: ev.cells, color: PIECE_HEX[ev.color], t: 0, dur: T.s, height: 7, towerId: ev.towerId, size: ev.size });
          this.hiddenPieces.add(ev.pieceId);
          break;
        }
        case 'undo': {
          this.drops = this.drops.filter((d) => d.pieceId !== ev.pieceId);
          this.hiddenPieces.delete(ev.pieceId);
          const c = this.centroid(ev.cells);
          this.ring(c.x, c.y, 1.8, 0.3, PIECE_HEX[ev.color], T.m);
          for (let k = 0; k < (rm ? 4 : 12); k++) this.spark(c.x, c.y, PIECE_HEX[ev.color], 5);
          break;
        }
        case 'activate': {
          const t = game.towerById(ev.towerId);
          if (!t) break;
          this.ring(t.cx, t.cy, 0.5, 5, 0xffffff, T.l);
          this.ring(t.cx, t.cy, 0.5, 3, PIECE_HEX[t.stats?.color ?? 'gold'], T.m);
          this.text(`${ev.type}!`, t.cx, t.cy - 2.5, 0xffffff, 18);
          for (let k = 0; k < (rm ? 6 : 20); k++) this.spark(t.cx, t.cy, 0xffffff, 6);
          break;
        }
        case 'bonus': {
          const t = game.towerById(ev.towerId);
          if (!t) break;
          this.text(ev.label, t.cx, t.cy - 3.6, 0xffe08a, 15);
          this.spiralSweep(t.cx, t.cy, 0xffe08a);
          if (ev.key === 'perfect') { this.perfectFlash = 0.382; this.addShake(0.3); }
          break;
        }
        case 'shot': this.shotFx(ev, game); break;
        case 'bolt':
          this.flashes.push({ kind: 'bolt', x1: ev.x1, y1: ev.y1, x2: ev.x2, y2: ev.y2, life: 0.2, max: 0.2, color: 0xd9f2ff, seed: Math.random() * 100 });
          if (!ev.miss) { this.ring(ev.x2, ev.y2, 0.2, 1.8, 0xd9f2ff, 0.22); for (let k = 0; k < (rm ? 2 : 6); k++) this.spark(ev.x2, ev.y2, 0xd9f2ff, 8); }
          this.particles.push({ x: ev.x1, y: ev.y1, vx: 0, vy: 0, life: 0.12, max: 0.12, size: 1.1, color: 0xbfe8ff, kind: 'dot', g: 0, spin: 0, ang: 0, glow: true });
          break;
        case 'explode': {
          const col = ev.color ? PIECE_HEX[ev.color] : 0xffc46b;
          this.ring(ev.x, ev.y, 0.2, ev.r + 0.8, col, T.s);
          this.ring(ev.x, ev.y, 0.2, ev.r * 0.6 + 0.5, 0xffffff, 0.15);
          for (let k = 0; k < (rm ? 2 : 4); k++) this.particles.push({ x: ev.x + (Math.random() - 0.5) * ev.r * 0.6, y: ev.y + (Math.random() - 0.5) * ev.r * 0.6, vx: 0, vy: -0.5, life: 0.35, max: 0.35, size: ev.r * (0.5 + Math.random() * 0.4), color: k % 2 ? 0xff8a3d : 0xffd28a, kind: 'dot', g: 0, spin: 0, ang: 0, glow: true });
          for (let k = 0; k < (rm ? 3 : 10); k++) this.debris(ev.x, ev.y, k % 2 ? 0x5a4a3a : 0x8a7a66);
          for (let k = 0; k < (rm ? 1 : 3); k++) this.smoke(ev.x, ev.y, ev.r * 0.6);
          this.decal(ev.x, ev.y, ev.r * 0.8, 0x14100a, 'scorch');
          this.addShake(ev.r > 2 ? 0.25 : 0.12);
          break;
        }
        case 'mine':
          this.ring(ev.x, ev.y, 0.2, 2.4, 0xff6b3d, T.m);
          this.particles.push({ x: ev.x, y: ev.y, vx: 0, vy: 0, life: 0.3, max: 0.3, size: 1.6, color: 0xffb347, kind: 'dot', g: 0, spin: 0, ang: 0, glow: true });
          for (let k = 0; k < (rm ? 4 : 14); k++) this.debris(ev.x, ev.y, 0x6a5a4a);
          this.decal(ev.x, ev.y, 1.0, 0x14100a, 'scorch');
          this.addShake(0.35);
          break;
        case 'kill': {
          const col = suitColor(ev.suit, ev.size);
          const gcol = GROUPS[ev.group].color;
          const big = ev.size === 'champion' || ev.size === 'boss';
          const n = rm ? 4 : ev.size === 'mite' ? 5 : ev.size === 'small' ? 9 : ev.size === 'medium' ? 13 : big ? 50 : 20;
          if (ev.split) this.splitBurst(ev.x, ev.y, col);
          for (let k = 0; k < n; k++) {
            const a = Math.random() * Math.PI * 2, sp = (big ? 6 : 3) + Math.random() * 6;
            this.particles.push({ x: ev.x, y: ev.y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp - 3, life: 0.6 + Math.random() * 0.4, max: 1, size: (ev.size === 'mite' ? 0.15 : 0.25) + Math.random() * 0.3, color: k % 3 ? col : k % 2 ? gcol : 0xffffff, kind: k % 2 ? 'square' : 'dot', g: 14, spin: (Math.random() - 0.5) * 12, ang: 0 });
          }
          this.ring(ev.x, ev.y, 0.3, (ev.size === 'mite' ? 0.9 : 1.6) + SIZES[ev.size].radius, ev.group === 'nonmetal' ? col : gcol, T.s);
          if (ev.tier >= 3 && !rm) this.spiralSweep(ev.x, ev.y, gcol);
          if (big) { this.ring(ev.x, ev.y, 0.5, 9, 0xffffff, T.l); this.addShake(0.8); this.strikeFlash = 0.25; }
          if (ev.essence >= 1) this.text(`+${Math.round(ev.essence)}`, ev.x, ev.y - 1, 0xb8f3ff, ev.essence >= 5 ? 14 : 11);
          break;
        }
        case 'combo': {
          const big = ev.n >= 21;
          this.text(big ? `Fibonacci Cascade ×${ev.n}` : `×${ev.n}`, ev.x, ev.y - 2, big ? 0xffe08a : 0xffffff, big ? 24 : 14 + COMBO.steps.indexOf(ev.n) * 2);
          if (big) this.cascade = 1.618;
          break;
        }
        case 'leak':
          this.ring(CORE_PT.x, CORE_PT.y, 1, 5, PAL.bad, T.m);
          this.addShake(0.5);
          this.text(`−${ev.dmg}`, CORE_PT.x, CORE_PT.y - 3, PAL.bad, 16);
          break;
        case 'parry': this.text('parry', ev.x, ev.y - 1.2, 0xcfd6ff, 10); break;
        case 'immune': this.text('phase', ev.x, ev.y - 1.2, 0xc0c0ff, 10); break;
        case 'hit': if (ev.crit) this.text(`${Math.round(ev.amount)}!`, ev.x, ev.y - 1.4, 0xffe08a, 12); break;
        case 'smite':
          this.ring(ev.x, ev.y, 0.5, ev.r, 0xfff3c0, T.l);
          this.ring(ev.x, ev.y, 0.5, ev.r * 0.6, 0xffffff, T.m);
          this.flashes.push({ kind: 'smite', x1: ev.x, y1: -10, x2: ev.x, y2: ev.y, life: 0.382, max: 0.382, color: 0xfff3c0, seed: 0 });
          this.decal(ev.x, ev.y, ev.r * 0.7, 0x14100a, 'scorch');
          this.addShake(0.8);
          break;
        case 'barrierBreak':
          for (let k = 0; k < 12; k++) this.debris(ev.x, ev.y, 0xb9bcd4);
          break;
        case 'strike': {
          this.strikeT = 0;
          this.strikeFlash = 0.35;
          this.addShake(0.7);
          const pts = [ev.path.start, ...ev.path.path.map(macroCentre)];
          const xs = pts.map((p) => p.x).concat([CORE_PT.x]), ys = pts.map((p) => p.y).concat([CORE_PT.y]);
          this.focus(Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys), 1.8);
          break;
        }
        case 'revealDone': {
          this.camTarget = { zoom: 1, x: 0, y: 0 };
          const b = game.board;
          const last = b.paths[b.paths.length - 1];
          if (last) this.embers = { cells: b.cellsOf(last), t: 3, max: 3 };
          this.redrawGround(b);
          break;
        }
        case 'destroyed': {
          for (const [x, y] of ev.cells) { this.debris(x + 0.5, y + 0.5, 0x8a8f9f); if (Math.random() < 0.5) this.smoke(x + 0.5, y + 0.5, 0.8); }
          this.ring(ev.x, ev.y, 0.5, 4, 0xbfe8ff, T.m);
          this.text('Struck!', ev.x, ev.y - 2, 0xbfe8ff, 14);
          break;
        }
        case 'summon':
          this.ring(ev.x, ev.y, 0.5, 3.2, 0xd88cff, T.m);
          for (let k = 0; k < (rm ? 3 : 10); k++) this.spark(ev.x, ev.y, 0xd88cff, 6);
          break;
        case 'champion':
          this.ring(ev.x, ev.y, 0.5, 8, ev.boss ? 0xff5d6c : 0xffd36b, T.l);
          this.addShake(0.4);
          break;
        case 'loot': {
          this.ring(ev.x, ev.y, 0.5, 6, 0xffe08a, T.l);
          this.particles.push({ x: ev.x, y: ev.y, vx: 0, vy: 0, life: 0.5, max: 0.5, size: 3, color: 0xffe08a, kind: 'dot', g: 0, spin: 0, ang: 0, glow: true });
          for (let k = 0; k < (rm ? 6 : 26); k++) {
            const a = -Math.PI / 2 + (Math.random() - 0.5) * 2.2, sp = 6 + Math.random() * 9;
            this.particles.push({ x: ev.x, y: ev.y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, life: 1.4, max: 1.4, size: 0.3, color: k % 3 === 0 ? PAL.ore : 0xffd36b, kind: k % 3 === 0 ? 'gem' : 'coin', g: 16, spin: 8, ang: 0 });
          }
          this.text(`Loot! +${ev.essence}◆ +${ev.ore}⬢${ev.golden ? ' + golden piece' : ''}`, ev.x, ev.y - 3, 0xffe08a, 18);
          break;
        }
      }
    }
  }

  private shotFx(ev: Extract<GameEvent, { t: 'shot' }>, game: Game) {
    const rm = this.reducedMotion;
    const t = ev.towerId > 0 ? game.towerById(ev.towerId) : null;
    const col = ev.color ? PIECE_HEX[ev.color] : 0xffffff;
    const type: TowerType | null = t?.type ?? null;
    const tip = t ? this.muzzle(t, type === 'Rifle' ? 2.2 : type === 'Missile' ? 1.1 : 1.6) : { x: ev.x1, y: ev.y1 };
    const ang = Math.atan2(ev.y2 - ev.y1, ev.x2 - ev.x1);
    switch (ev.kind) {
      case 'bullet': {
        const big = type === 'Gun';
        this.muzzleFlash(tip.x, tip.y, ang, big ? 1.0 : 0.75);
        if (!rm) this.casing(t ? t.cx : ev.x1, t ? t.cy - 0.6 : ev.y1, ang);
        break;
      }
      case 'hitscan':
        this.muzzleFlash(tip.x, tip.y, ang, 1.6);
        this.flashes.push({ kind: 'tracer', x1: tip.x, y1: tip.y, x2: ev.x2, y2: ev.y2, life: 0.2, max: 0.2, color: col, seed: 0, w: 0.35 });
        if (!rm) { this.casing(t ? t.cx : ev.x1, t ? t.cy - 0.6 : ev.y1, ang, 1.4); this.smoke(tip.x, tip.y, 0.5); }
        for (let k = 0; k < (rm ? 1 : 4); k++) this.spark(ev.x2, ev.y2, 0xffe9b0, 7);
        this.addShake(0.08);
        break;
      case 'ricochet': case 'tank':
        this.flashes.push({ kind: ev.kind, x1: ev.x1, y1: ev.y1, x2: ev.x2, y2: ev.y2, life: 0.12, max: 0.12, color: col, seed: 0 });
        if (ev.kind === 'tank') this.muzzleFlash(ev.x1, ev.y1, ang, 0.6);
        break;
      case 'pierce':
        this.flashes.push({ kind: 'pierce', x1: tip.x, y1: tip.y, x2: ev.x2, y2: ev.y2, life: 0.26, max: 0.26, color: ev.color ? col : 0xbfe0ff, seed: 0 });
        if (!rm) for (let k = 1; k <= 3; k++) { const f = k / 4; this.ring(tip.x + (ev.x2 - tip.x) * f, tip.y + (ev.y2 - tip.y) * f, 0.2, 1.0, ev.color ? col : 0xbfe0ff, 0.25); }
        this.muzzleFlash(tip.x, tip.y, ang, 0.8, 0xbfe0ff);
        break;
      case 'cone': {
        if (rm) break;
        for (let k = 0; k < 7; k++) {
          const aa = ang + (Math.random() - 0.5) * 1.2, sp = 9 + Math.random() * 7;
          this.particles.push({ x: tip.x, y: tip.y, vx: Math.cos(aa) * sp, vy: Math.sin(aa) * sp, life: 0.45, max: 0.45, size: 0.45 + Math.random() * 0.3, color: Math.random() < 0.5 ? 0xffb347 : 0xff6b3d, kind: 'flame', g: -2, spin: 0, ang: 0, glow: true });
        }
        if (Math.random() < 0.4) this.particles.push({ x: tip.x, y: tip.y, vx: Math.cos(ang) * 5, vy: Math.sin(ang) * 5 - 2, life: 0.9, max: 0.9, size: 0.1, color: 0xffd28a, kind: 'ember', g: -1, spin: 0, ang: 0, glow: true });
        if (Math.random() < 0.3) this.smoke(tip.x + Math.cos(ang) * 4, tip.y + Math.sin(ang) * 4, 0.5);
        break;
      }
      case 'virus':
        this.flashes.push({ kind: 'virus', x1: tip.x, y1: tip.y, x2: ev.x2, y2: ev.y2, life: 0.32, max: 0.32, color: 0xd88cff, seed: Math.random() });
        if (!rm) for (let k = 0; k < 3; k++) this.particles.push({ x: ev.x2, y: ev.y2, vx: (Math.random() - 0.5) * 3, vy: -1.5, life: 0.8, max: 0.8, size: 0.16, color: 0xd88cff, kind: 'dot', g: 0, spin: 0, ang: 0, glow: true });
        break;
      case 'lob': case 'puddle':
        this.muzzleFlash(tip.x, tip.y, ang, 0.8, ev.kind === 'puddle' ? 0x8cff7a : 0xffb347);
        if (!rm) this.smoke(tip.x, tip.y, 0.6);
        break;
      case 'homing':
        this.muzzleFlash(tip.x, tip.y, ang, 0.9, 0xffd28a);
        if (!rm) { this.smoke(tip.x, tip.y, 0.7); this.smoke(tip.x, tip.y, 0.5); }
        break;
    }
  }

  private muzzleFlash(x: number, y: number, ang: number, size: number, color = 0xffe9a0) {
    this.flashes.push({ kind: 'muzzle', x1: x, y1: y, x2: x + Math.cos(ang) * size, y2: y + Math.sin(ang) * size, life: 0.07, max: 0.07, color, seed: Math.random() * 6, w: size });
  }
  private casing(x: number, y: number, ang: number, scale = 1) {
    if (this.particles.length > 1800) return;
    const side = ang + Math.PI / 2 * (Math.random() < 0.5 ? 1 : -1);
    const sp = 3 + Math.random() * 2.5;
    this.particles.push({ x, y, vx: Math.cos(side) * sp, vy: Math.sin(side) * sp * 0.6, z: 0.4, vz: 5 + Math.random() * 3, life: 3.2, max: 3.2, size: 0.13 * scale, color: 0xd9a845, kind: 'casing', g: 22, spin: (Math.random() - 0.5) * 30, ang: Math.random() * 6, rest: 0 });
  }
  private smoke(x: number, y: number, size: number) {
    this.particles.push({ x: x + (Math.random() - 0.5) * 0.5, y: y + (Math.random() - 0.5) * 0.5, vx: (Math.random() - 0.5) * 0.8, vy: -1.2 - Math.random(), life: 1.2, max: 1.2, size, color: 0x9a9a9a, kind: 'smoke', g: 0, spin: 0, ang: 0 });
  }
  private debris(x: number, y: number, color: number) {
    const a = Math.random() * Math.PI * 2, sp = 2 + Math.random() * 5;
    this.particles.push({ x, y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp * 0.6, z: 0.2, vz: 4 + Math.random() * 5, life: 1.4, max: 1.4, size: 0.1 + Math.random() * 0.15, color, kind: 'debris', g: 20, spin: (Math.random() - 0.5) * 20, ang: Math.random() * 6, rest: 0 });
  }
  private decal(x: number, y: number, r: number, color: number, kind: Decal['kind']) {
    if (this.decals.length > 160) this.decals.shift();
    this.decals.push({ x, y, r, life: 4.5, max: 4.5, color, kind });
  }
  private ring(x: number, y: number, r0: number, r1: number, color: number, life: number) {
    this.particles.push({ x, y, vx: 0, vy: 0, life, max: life, size: r1, r0, color, kind: 'ring', g: 0, spin: 0, ang: 0 });
  }
  private pulse(x: number, y: number, r1: number, color: number, life: number) {
    this.particles.push({ x, y, vx: 0, vy: 0, life, max: life, size: r1, r0: 0.4, color, kind: 'pulse', g: 0, spin: 0, ang: 0 });
  }
  private spark(x: number, y: number, color: number, sp: number) {
    const a = Math.random() * Math.PI * 2, s = sp * (0.4 + Math.random() * 0.8);
    this.particles.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: 0.4 + Math.random() * 0.3, max: 0.7, size: 0.18, color, kind: 'spark', g: 6, spin: 0, ang: a });
  }
  private spiralSweep(x: number, y: number, color: number) {
    const n = this.reducedMotion ? 8 : 34;
    for (let k = 0; k < n; k++)
      this.particles.push({ x, y, vx: 0, vy: 0, life: 1.0, max: 1.0, size: 0.22, color, kind: 'spiral', g: 0, spin: 0, ang: (k / n) * Math.PI * 4, cx: x, cy: y });
  }
  private splitBurst(x: number, y: number, color: number) {
    for (let k = 0; k < 8; k++)
      this.particles.push({ x, y, vx: 0, vy: 0, life: 0.8, max: 0.8, size: 0.3, color, kind: 'spiral', g: 0, spin: 0, ang: (k / 8) * Math.PI * 2, cx: x, cy: y, r0: -1 });
  }

  text(s: string, x: number, y: number, color: number, size: number) {
    if (this.texts.length > 40) { const old = this.texts.shift()!; old.t.destroy(); }
    const t = new Text({ text: s, style: { fontFamily: 'Nunito, system-ui, sans-serif', fontSize: size, fontWeight: '800', fill: color, stroke: { color: 0x0b0f1a, width: 4 } } });
    t.anchor.set(0.5);
    this.screen.addChild(t);
    this.texts.push({ t, x, y, life: 1.2, max: 1.2, vy: -1.6, world: true });
  }

  // ================================================================ frame
  draw(game: Game, alpha: number, dt: number) {
    this.time += dt;
    this.strikeT += dt;
    const targetZoom = game.phase === 'calm' || game.phase === 'reveal' ? 0.97 : 1;
    this.camZoom += (targetZoom - this.camZoom) * Math.min(1, dt * 1.5);
    this.stepCamera(dt);
    this.layout();
    if (this.shake.t > 0) {
      this.shake.t -= dt;
      const m = this.shake.mag * (this.shake.t / 0.236);
      this.shake.x = (Math.random() - 0.5) * 2 * m;
      this.shake.y = (Math.random() - 0.5) * 2 * m;
    } else { this.shake.x = this.shake.y = 0; this.shake.mag = 0; }
    this.nudge.y *= 0.8;
    this.world.position.set(this.offX + (this.shake.x + this.nudge.x) * this.cell, this.offY + (this.shake.y + this.nudge.y) * this.cell);
    this.world.scale.set(this.cell);

    if (this.boardRef !== game.board) this.setBoard(game.board);
    if (this.boardVersion !== game.board.version) this.redrawGround(game.board);
    this.coreC.rotation = this.time * 0.15;
    this.coreC.scale.set(1 + Math.sin(this.time * 2) * 0.02);

    this.glow.clear();
    this.stepDrops(dt);
    this.drawObjects(game);
    this.syncTowers(game);
    this.syncEnemies(game, alpha, dt);
    this.drawDecals(dt);
    this.drawFx(game, alpha, dt);
    this.drawParticles(dt);
    this.drawGhost();
    this.drawTexts(dt);
    this.drawEdgeGlow(dt);
  }

  private stepDrops(dt: number) {
    for (const d of this.drops) {
      d.t += dt;
      if (d.t >= d.dur) {
        this.hiddenPieces.delete(d.pieceId);
        const c = this.centroid(d.cells);
        this.ring(c.x, c.y, 0.4, 1.5 + d.size * 0.4, 0xe9e3d0, T.m);
        if (!this.reducedMotion) {
          for (let k = 0; k < 8 + d.size * 2; k++) {
            const a = Math.random() * Math.PI * 2;
            this.particles.push({ x: c.x + Math.cos(a) * 1.2, y: c.y + Math.sin(a) * 0.8, vx: Math.cos(a) * 3, vy: Math.sin(a) * 1.5, life: 0.4, max: 0.4, size: 0.3, color: 0xcfc6b0, kind: 'dot', g: 0, spin: 0, ang: 0 });
          }
          this.nudge.y = 0.05 + d.size * 0.03;
        }
      }
    }
    this.drops = this.drops.filter((d) => d.t < d.dur);
  }

  private drawDecals(dt: number) {
    const g = this.decalG;
    g.clear();
    for (const d of this.decals) {
      d.life -= dt;
      const a = Math.min(1, d.life / 1.5) * 0.32;
      g.ellipse(d.x, d.y, d.r * 1.2, d.r * 0.85).fill({ color: d.color, alpha: a * 0.6 });
      g.ellipse(d.x, d.y, d.r * 0.7, d.r * 0.5).fill({ color: d.color, alpha: a });
    }
    this.decals = this.decals.filter((d) => d.life > 0);
    if (this.embers) {
      this.embers.t -= dt;
      const k = Math.max(0, this.embers.t / this.embers.max);
      const gl = this.glow;
      for (let i = 0; i < this.embers.cells.length; i += 3) {
        const c = this.embers.cells[i];
        const x = c % GRID_W, y = Math.floor(c / GRID_W);
        const fl = 0.5 + 0.5 * Math.sin(this.time * 9 + i);
        gl.circle(x + 0.5, y + 0.5, 0.18 + 0.1 * fl).fill({ color: 0xff8a3d, alpha: k * (0.25 + 0.35 * fl) });
      }
      if (this.embers.t <= 0) this.embers = null;
    }
  }

  private drawFx(game: Game, alpha: number, dt: number) {
    const g = this.fx;
    const gl = this.glow;
    g.clear();
    if (game.phase === 'reveal') this.drawStrike(game, g, gl);
    // drops (falling pieces with squash)
    for (const d of this.drops) {
      const k = d.t / d.dur;
      const fall = (1 - k * k) * d.height;
      const t = d.towerId ? game.towerById(d.towerId) : null;
      const layer = t ? Math.max(0, ...t.pieces.filter((p) => p.piece.id === d.pieceId).map((p) => p.layer)) : 0;
      for (const [x, y] of d.cells) g.rect(x + 0.2, y + 0.25, 1, 1).fill({ color: 0x000000, alpha: 0.25 * k });
      this.cellsBlock(g, d.cells, d.color, layer * LAYER_LIFT + fall, 0.95);
    }
    // undo window: a ring drains around the last piece
    if (this.undoMark && this.undoMark.frac > 0) {
      const c = this.centroid(this.undoMark.cells);
      const bb = this.bboxOf(this.undoMark.cells);
      const r = Math.max(bb.w, bb.h) * 0.75 + 0.6;
      g.circle(c.x, c.y, r).stroke({ width: 0.12, color: 0xffffff, alpha: 0.15 });
      g.moveTo(c.x, c.y - r).arc(c.x, c.y, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * this.undoMark.frac).stroke({ width: 0.22, color: 0xffe08a, alpha: 0.9, cap: 'round' });
      for (const [x, y] of this.undoMark.cells) g.rect(x + 0.05, y + 0.05, 0.9, 0.9).stroke({ width: 0.06, color: 0xffe08a, alpha: 0.4 + 0.3 * Math.sin(this.time * 10) });
    }
    // puddles
    for (const p of game.puddles) {
      const a = Math.min(1, p.t);
      g.circle(p.x, p.y, p.r).fill({ color: 0x5fd860, alpha: 0.2 * a });
      g.circle(p.x, p.y, p.r * 0.65).fill({ color: 0xbaff9a, alpha: 0.14 * a });
      for (let k = 0; k < 3; k++) {
        const ph = (this.time * 1.3 + k * 0.33 + p.x) % 1;
        const bx = p.x + Math.cos(k * 2.1 + p.y) * p.r * 0.5, by = p.y + Math.sin(k * 2.1 + p.x) * p.r * 0.4;
        g.circle(bx, by, 0.1 + ph * 0.18).stroke({ width: 0.05, color: 0xdcffc0, alpha: (1 - ph) * a * 0.8 });
      }
    }
    // auras, beams and pulses
    for (const t of game.towers) {
      if (!t.active || !t.stats || !t.type) continue;
      const lift = (t.layers.length - 1) * LAYER_LIFT + 0.45;
      const def = TOWERS[t.type];
      const v = this.towers.get(t.id);
      if (def.kind === 'aura') {
        const col = t.type === 'Freezer' ? 0xbff4ff : 0x9fd8ff;
        if (v && t.fireFlash > 0 && this.time - v.lastPulse > 0.6) {
          v.lastPulse = this.time;
          this.pulse(t.cx, t.cy, t.stats.range, col, 0.6);
          if (t.type === 'Freezer' && !this.reducedMotion)
            for (const e of game.enemies) if (Math.hypot(e.x - t.cx, e.y - t.cy) <= t.stats.range && Math.random() < 0.35)
              this.particles.push({ x: e.x + (Math.random() - 0.5), y: e.y - 0.5, vx: 0, vy: 0.6, life: 0.8, max: 0.8, size: 0.2, color: 0xe6fbff, kind: 'snow', g: 0, spin: 2, ang: Math.random() * 6 });
        }
        if (t.fireFlash > 0 && t.type === 'E-Field')
          for (const e of game.enemies)
            if (Math.hypot(e.x - t.cx, e.y - t.cy) <= t.stats.range && e.arch !== 'balloon')
              this.jagged(gl, t.cx, t.cy - lift, e.x, e.y, 0xcfeaff, 0.08, 0.7, e.id);
      }
      if (def.kind === 'beam' && t.targetId) {
        const e = game.enemies.find((x) => x.id === t.targetId);
        if (e) {
          const ex = e.px + (e.x - e.px) * alpha, ey = e.py + (e.y - e.py) * alpha;
          const ramp = Math.min(1, t.rampT / 3);
          const col = t.stats.color ? PIECE_HEX[t.stats.color] : 0xbfd7ff;
          const tip = this.muzzle(t, 1.5);
          gl.moveTo(tip.x, tip.y).lineTo(ex, ey).stroke({ width: 1.0 + ramp * 1.2, color: col, alpha: 0.12, cap: 'round' });
          gl.moveTo(tip.x, tip.y).lineTo(ex, ey).stroke({ width: 0.3 + ramp * 0.45, color: col, alpha: 0.45, cap: 'round' });
          gl.moveTo(tip.x, tip.y).lineTo(ex, ey).stroke({ width: 0.08 + ramp * 0.15, color: 0xffffff, alpha: 0.95, cap: 'round' });
          gl.circle(ex, ey, 0.45 + ramp * 0.45 + Math.random() * 0.15).fill({ color: 0xffffff, alpha: 0.5 });
          gl.circle(tip.x, tip.y, 0.3 + ramp * 0.25).fill({ color: col, alpha: 0.6 });
          if (!this.reducedMotion && Math.random() < 0.5) this.spark(ex, ey, col, 6);
        }
      }
      if (t.stats.spire) g.ellipse(t.cx, t.cy - lift - 1.2, 1.2, 0.4).stroke({ width: 0.12, color: 0xffe08a, alpha: 0.6 + 0.3 * Math.sin(this.time * 3) });
      if (this.showRanges || this.selectedTower === t.id) {
        g.circle(t.cx, t.cy, t.stats.range).fill({ color: 0xffffff, alpha: this.selectedTower === t.id ? 0.05 : 0.02 });
        g.circle(t.cx, t.cy, t.stats.range).stroke({ width: 0.1, color: 0xffffff, alpha: this.selectedTower === t.id ? 0.5 : 0.15 });
      }
    }
    if (game.batteryTower && (this.showRanges || this.selectedTower === game.batteryTower.id))
      g.circle(CORE_PT.x, CORE_PT.y, game.batteryTower.stats!.range).stroke({ width: 0.1, color: 0xffe08a, alpha: 0.2 });
    for (const t of game.towers) {
      if (t.type) continue;
      const need = 3 - t.pieces.filter((p) => p.layer === 0 && p.piece.kind[0] !== 'c').length;
      for (let k = 0; k < 3; k++) g.circle(t.cx - 0.7 + k * 0.7, t.cy - 1.6, 0.22).fill({ color: k < 3 - need ? 0xffffff : 0x55607a, alpha: 0.9 });
    }
    // projectiles
    for (const p of game.projectiles) {
      const x = p.px + (p.x - p.px) * alpha, y = p.py + (p.y - p.py) * alpha;
      const col = p.color ? PIECE_HEX[p.color] : 0xffe9a0;
      if (p.kind === 'bullet') {
        const dx = p.x - p.px, dy = p.y - p.py;
        gl.moveTo(x - dx * 3, y - dy * 3).lineTo(x, y).stroke({ width: 0.32, color: col, alpha: 0.6, cap: 'round' });
        g.circle(x, y, 0.2).fill(0xfff6d0);
      } else if (p.kind === 'lob' || p.kind === 'acid') {
        const k = Math.min(1, p.t / p.dur);
        const hgt = Math.sin(k * Math.PI) * 3;
        g.circle(x, y, 0.3 * (1 - hgt / 5)).fill({ color: 0x000000, alpha: 0.25 });
        g.circle(x, y - hgt, 0.42).fill(p.kind === 'acid' ? 0x8cff7a : 0x2b2f45);
        g.circle(x - 0.12, y - hgt - 0.12, 0.14).fill({ color: 0xffffff, alpha: 0.5 });
        if (p.kind === 'lob') gl.circle(x + 0.25, y - hgt - 0.3, 0.12 + Math.random() * 0.08).fill({ color: 0xffb347, alpha: 0.9 });
      } else if (p.kind === 'homing') {
        const a = Math.atan2(p.y - p.py, p.x - p.px);
        g.poly([x + Math.cos(a) * 0.65, y + Math.sin(a) * 0.65, x + Math.cos(a + 2.5) * 0.35, y + Math.sin(a + 2.5) * 0.35, x + Math.cos(a - 2.5) * 0.35, y + Math.sin(a - 2.5) * 0.35]).fill(0xeef2ff);
        gl.circle(x - Math.cos(a) * 0.45, y - Math.sin(a) * 0.45, 0.22 + Math.random() * 0.1).fill({ color: 0xffb347, alpha: 0.9 });
        if (!this.reducedMotion && Math.random() < 0.7)
          this.particles.push({ x: x - Math.cos(a) * 0.5, y: y - Math.sin(a) * 0.5, vx: 0, vy: 0, life: 0.6, max: 0.6, size: 0.3, color: 0xb0b4c0, kind: 'smoke', g: 0, spin: 0, ang: 0 });
      }
    }
    // tanks
    for (const k of game.tanks) {
      const x = k.px + (k.x - k.px) * alpha, y = k.py + (k.y - k.py) * alpha;
      g.roundRect(x - 0.75, y - 0.45, 1.5, 1.0, 0.25).fill(0x6a5a2a);
      g.roundRect(x - 0.7, y - 0.55, 1.4, 0.9, 0.25).fill(0xffd36b);
      g.circle(x, y - 0.1, 0.35).fill(0x8a6a2a);
    }
    // flashes
    for (const f of this.flashes) {
      const a = f.life / f.max;
      if (f.kind === 'bolt') { this.jagged(gl, f.x1, f.y1, f.x2, f.y2, f.color, 0.4, a * 0.5, f.seed); this.jagged(gl, f.x1, f.y1, f.x2, f.y2, 0xffffff, 0.08, a, f.seed); this.jagged(gl, f.x2, f.y2, f.x2 + Math.cos(f.seed) * 2, f.y2 + Math.sin(f.seed) * 2, f.color, 0.06, a * 0.7, f.seed + 2); }
      else if (f.kind === 'smite') { gl.moveTo(f.x1, f.y1).lineTo(f.x2, f.y2).stroke({ width: 2.5 * a, color: f.color, alpha: a }); }
      else if (f.kind === 'virus') { g.moveTo(f.x1, f.y1).quadraticCurveTo((f.x1 + f.x2) / 2 + 1, (f.y1 + f.y2) / 2 - 2, f.x2, f.y2).stroke({ width: 0.12, color: f.color, alpha: a * 0.7 }); }
      else if (f.kind === 'muzzle') {
        const ang = Math.atan2(f.y2 - f.y1, f.x2 - f.x1), s = f.w ?? 1;
        const pts: number[] = [];
        for (let k = 0; k < 10; k++) {
          const aa = ang + (k / 10) * Math.PI * 2;
          const rr = (k % 2 ? 0.25 : 0.55) * s * (k === 0 ? 1.8 : 1);
          pts.push(f.x1 + Math.cos(aa) * rr, f.y1 + Math.sin(aa) * rr);
        }
        gl.poly(pts).fill({ color: f.color, alpha: a });
        gl.circle(f.x1, f.y1, 0.9 * s).fill({ color: f.color, alpha: 0.25 * a });
        gl.circle(f.x1, f.y1, 0.22 * s).fill({ color: 0xffffff, alpha: a });
      } else {
        const w = f.kind === 'pierce' ? 0.5 * a + 0.1 : f.w ?? 0.12;
        gl.moveTo(f.x1, f.y1).lineTo(f.x2, f.y2).stroke({ width: w * 2.2, color: f.color, alpha: a * 0.35, cap: 'round' });
        gl.moveTo(f.x1, f.y1).lineTo(f.x2, f.y2).stroke({ width: w * 0.5, color: 0xffffff, alpha: a, cap: 'round' });
      }
      f.life -= dt;
    }
    this.flashes = this.flashes.filter((f) => f.life > 0);
    // enemy hp bars and status
    for (const e of game.enemies) {
      const x = e.px + (e.x - e.px) * alpha, y = e.py + (e.y - e.py) * alpha;
      const r = SIZES[e.size].radius * e.scale * ENEMY_VIS;
      const oy = e.arch === 'balloon' ? -1.6 : 0;
      const big = e.champion || e.boss;
      if (e.hp < e.maxHp || e.shield > 0 || big) {
        const w = big ? r * 2.6 : Math.max(e.size === 'mite' ? 0.8 : 1.2, r * 2.2);
        const h = big ? 0.36 : e.size === 'mite' ? 0.14 : 0.22;
        const yy = y + oy - r - (big ? 1.0 : 0.55);
        g.rect(x - w / 2 - 0.05, yy - 0.05, w + 0.1, h + 0.1).fill({ color: 0x000000, alpha: 0.6 });
        g.rect(x - w / 2, yy, w * Math.max(0, e.hp / e.maxHp), h).fill(big ? 0xff5d6c : e.hp / e.maxHp > 0.4 ? 0x7dffb0 : 0xffb35c);
        if (e.shield > 0) g.rect(x - w / 2, yy - h * 0.8, w * Math.min(1, e.shield / (e.maxHp * 0.38)), h * 0.7).fill(0x9fd8ff);
      }
      if (e.dots.length && !this.reducedMotion && Math.random() < 0.2) {
        const d = e.dots[0];
        const c = d.kind === 'virus' ? 0xd88cff : d.kind === 'poison' ? 0x8cff7a : 0xff8a3d;
        this.particles.push({ x: x + (Math.random() - 0.5) * r, y: y + oy, vx: 0, vy: -2, life: 0.5, max: 0.5, size: 0.16, color: c, kind: 'dot', g: 0, spin: 0, ang: 0, glow: d.kind === 'burn' });
      }
    }
    // smite aim
    if (this.smiteAim) {
      g.circle(this.smiteAim.x, this.smiteAim.y, this.smiteAim.r).fill({ color: 0xfff3c0, alpha: 0.1 });
      g.circle(this.smiteAim.x, this.smiteAim.y, this.smiteAim.r).stroke({ width: 0.15, color: 0xfff3c0, alpha: 0.7 });
    }
  }

  private drawParticles(dt: number) {
    const g = this.particlesG;
    const gl = this.glow;
    g.clear();
    if (this.particles.length > 2400) this.particles.splice(0, this.particles.length - 2400);
    for (const p of this.particles) {
      p.life -= dt;
      const k = Math.max(0, p.life / p.max);
      const out = p.glow ? gl : g;
      switch (p.kind) {
        case 'ring': {
          const r = p.r0! + (p.size - p.r0!) * (1 - k * k);
          g.circle(p.x, p.y, r).stroke({ width: 0.15 + 0.25 * k, color: p.color, alpha: k });
          continue;
        }
        case 'pulse': {
          const e = 1 - k;
          const r = p.r0! + (p.size - p.r0!) * (1 - (1 - e) * (1 - e));
          g.circle(p.x, p.y, r).fill({ color: p.color, alpha: 0.1 * k });
          g.circle(p.x, p.y, r).stroke({ width: 0.25, color: p.color, alpha: 0.55 * k });
          gl.circle(p.x, p.y, r).stroke({ width: 0.6, color: p.color, alpha: 0.12 * k });
          continue;
        }
        case 'spiral': {
          const tt = 1 - k;
          const dir = p.r0 === -1 ? 1 : -1;
          const r = 0.3 * Math.pow(PHI, tt * 5);
          const a = p.ang + dir * tt * 4;
          p.x = p.cx! + Math.cos(a) * r;
          p.y = p.cy! + Math.sin(a) * r + (p.r0 === -1 ? tt * tt * 6 : 0);
          g.circle(p.x, p.y, p.size * (0.5 + k)).fill({ color: p.color, alpha: k });
          continue;
        }
        case 'casing': case 'debris': {
          if (p.rest === 0) {
            p.vz! -= p.g * dt;
            p.z! += p.vz! * dt;
            p.x += p.vx * dt;
            p.y += p.vy * dt;
            p.ang += p.spin * dt;
            if (p.z! <= 0) {
              p.z = 0;
              if (Math.abs(p.vz!) > 2) { p.vz = -p.vz! * 0.38; p.vx *= 0.55; p.vy *= 0.55; p.spin *= 0.5; }
              else { p.rest = 1; p.vz = 0; }
            }
          }
          const fade = Math.min(1, p.life / 0.6);
          const yy = p.y - (p.z ?? 0);
          if ((p.z ?? 0) > 0.05) g.ellipse(p.x, p.y + 0.05, p.size, p.size * 0.4).fill({ color: 0x000000, alpha: 0.2 * fade });
          const c = Math.cos(p.ang), sn = Math.sin(p.ang);
          const L = p.kind === 'casing' ? p.size * 1.8 : p.size, W = p.size;
          g.poly([p.x - c * L + sn * W, yy - sn * L - c * W, p.x + c * L + sn * W, yy + sn * L - c * W, p.x + c * L - sn * W, yy + sn * L + c * W, p.x - c * L - sn * W, yy - sn * L + c * W]).fill({ color: p.color, alpha: fade });
          if (p.kind === 'casing') g.circle(p.x - c * L * 0.6, yy - sn * L * 0.6, W * 0.5).fill({ color: 0xfff1b0, alpha: 0.7 * fade });
          continue;
        }
        case 'smoke': {
          p.x += p.vx * dt; p.y += p.vy * dt;
          const r = p.size * (0.6 + (1 - k) * 1.6);
          g.circle(p.x, p.y, r).fill({ color: p.color, alpha: 0.28 * k });
          continue;
        }
        case 'flame': {
          p.x += p.vx * dt; p.y += p.vy * dt; p.vx *= 0.9; p.vy *= 0.9; p.vy += p.g * dt;
          const col = k > 0.6 ? 0xffe9a0 : k > 0.3 ? p.color : 0xb03a1a;
          gl.circle(p.x, p.y, p.size * (1.4 - k * 0.6)).fill({ color: col, alpha: k * 0.8 });
          continue;
        }
        case 'snow': {
          p.y += p.vy * dt; p.ang += p.spin * dt;
          for (let a = 0; a < 3; a++) { const aa = p.ang + (a * Math.PI) / 3; g.moveTo(p.x - Math.cos(aa) * p.size, p.y - Math.sin(aa) * p.size).lineTo(p.x + Math.cos(aa) * p.size, p.y + Math.sin(aa) * p.size); }
          g.stroke({ width: 0.05, color: p.color, alpha: k });
          continue;
        }
        case 'coin': case 'gem': {
          p.vy += p.g * dt; p.x += p.vx * dt; p.y += p.vy * dt; p.vx *= 0.98; p.ang += p.spin * dt;
          const w = Math.abs(Math.cos(p.ang)) * p.size + 0.04;
          if (p.kind === 'coin') { g.ellipse(p.x, p.y, w, p.size).fill({ color: p.color, alpha: k }); g.ellipse(p.x, p.y, w * 0.6, p.size * 0.6).fill({ color: 0xfff1b0, alpha: k * 0.8 }); }
          else g.poly([p.x, p.y - p.size, p.x + w, p.y, p.x, p.y + p.size, p.x - w, p.y]).fill({ color: p.color, alpha: k });
          continue;
        }
      }
      p.vy += p.g * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= 0.97;
      p.ang += p.spin * dt;
      if (p.kind === 'square') {
        const s = p.size;
        const c = Math.cos(p.ang) * s, sn = Math.sin(p.ang) * s;
        out.poly([p.x - c + sn, p.y - sn - c, p.x + c + sn, p.y + sn - c, p.x + c - sn, p.y + sn + c, p.x - c - sn, p.y - sn + c]).fill({ color: p.color, alpha: k });
      } else if (p.kind === 'spark') {
        gl.moveTo(p.x, p.y).lineTo(p.x - p.vx * 0.045, p.y - p.vy * 0.045).stroke({ width: p.size, color: p.color, alpha: k, cap: 'round' });
      } else out.circle(p.x, p.y, p.size * (0.4 + 0.6 * k)).fill({ color: p.color, alpha: k });
    }
    this.particles = this.particles.filter((p) => p.life > 0);
  }

  private drawGhost() {
    const g = this.ghostG;
    g.clear();
    if (!this.ghost) return;
    const { piece, pv, range } = this.ghost;
    const ok = pv.ok;
    const col = ok ? PIECE_HEX[piece.color] : PAL.bad;
    const lift = pv.kind === 'story' ? (pv.layer ?? 1) * LAYER_LIFT : 0;
    // a brighter local grid helps line pieces up when zoomed out
    const c0 = this.centroid(pv.cells.length ? pv.cells : [[0, 0]]);
    const R = 5;
    for (let x = Math.floor(c0.x) - R; x <= Math.floor(c0.x) + R; x++) g.moveTo(x, c0.y - R).lineTo(x, c0.y + R);
    for (let y = Math.floor(c0.y) - R; y <= Math.floor(c0.y) + R; y++) g.moveTo(c0.x - R, y).lineTo(c0.x + R, y);
    g.stroke({ width: 0.04, color: 0xffffff, alpha: 0.12 });
    for (const [x, y] of pv.cells) g.rect(x, y - lift, 1, 1).fill({ color: col, alpha: 0.18 });
    for (const [x, y] of pv.cells) g.rect(x + 0.05, y - lift - 1.2 + 0.05, 0.9, 0.9).fill({ color: col, alpha: 0.55 });
    for (const [x, y] of pv.cells) g.rect(x, y - lift, 1, 1).stroke({ width: 0.08, color: ok ? 0xffffff : PAL.bad, alpha: 0.7 });
    for (const [x, y] of pv.holes) {
      g.moveTo(x + 0.2, y + 0.2).lineTo(x + 0.8, y + 0.8).moveTo(x + 0.8, y + 0.2).lineTo(x + 0.2, y + 0.8);
      g.stroke({ width: 0.12, color: PAL.bad, alpha: 0.9 });
    }
    if (ok && range > 0) {
      const c = this.centroid(pv.cells);
      g.circle(c.x, c.y, range).stroke({ width: 0.08, color: 0xffffff, alpha: 0.25 });
    }
  }

  private drawTexts(dt: number) {
    for (const t of this.texts) {
      t.life -= dt;
      t.y += t.vy * dt;
      const s = this.toScreen(t.x, t.y);
      t.t.position.set(s.x + this.shake.x * this.cell, s.y);
      const k = t.life / t.max;
      t.t.alpha = Math.min(1, k * 3);
      t.t.scale.set(k > 0.85 ? 1 + (k - 0.85) * 2 : 1);
    }
    for (const t of this.texts) if (t.life <= 0) t.t.destroy();
    this.texts = this.texts.filter((t) => t.life > 0);
  }

  private drawEdgeGlow(dt: number) {
    const g = this.edgeGlow;
    g.clear();
    const W = this.app.screen.width, H = this.app.screen.height;
    if (this.cascade > 0) {
      this.cascade -= dt;
      const a = Math.min(1, this.cascade) * 0.5;
      for (let i = 0; i < 6; i++) g.rect(i * 4, i * 4, W - i * 8, H - i * 8).stroke({ width: 4, color: 0xffd36b, alpha: a * (1 - i / 6) });
    }
    if (this.perfectFlash > 0) {
      this.perfectFlash -= dt;
      g.rect(0, 0, W, H).fill({ color: 0xffffff, alpha: this.perfectFlash * 0.5 });
    }
    if (this.strikeFlash > 0) {
      this.strikeFlash -= dt;
      if (!this.reducedMotion) g.rect(0, 0, W, H).fill({ color: 0xdff4ff, alpha: Math.max(0, this.strikeFlash) * 1.2 });
    }
  }
}

export { shade, TERRAIN_PAL, cellIdx };
