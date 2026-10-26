// PixiJS renderer: board, road reveal, towers (2.5D), enemies, effects, ghost and camera.
import { Application, Container, Graphics, Text } from 'pixi.js';
import { COMBO, GRID_H, GRID_W, MACRO, MACRO_H, MACRO_W, PHI, SIZES, TOWERS, T } from '../balance';
import type { Enemy, Game, GameEvent, Preview } from '../sim/game';
import { CORE_PT, mxy, type Board } from '../sim/map';
import type { Cell, Piece } from '../sim/pieces';
import type { Tower } from '../sim/towers';
import { PAL, PIECE_HEX, mix, shade, suitColor } from './palette';

interface Particle {
  x: number; y: number; vx: number; vy: number; life: number; max: number; size: number; color: number;
  kind: 'dot' | 'square' | 'ring' | 'spark' | 'spiral'; g: number; spin: number; ang: number; r0?: number; cx?: number; cy?: number;
}
interface FloatText { t: Text; x: number; y: number; life: number; max: number; vy: number; world: boolean }
interface Drop { pieceId: number; cells: Cell[]; color: number; t: number; dur: number; height: number; towerId?: number; size: number }
interface Flash { kind: string; x1: number; y1: number; x2: number; y2: number; life: number; max: number; color: number; seed: number }
interface TowerView { c: Container; base: Graphics; turret: Graphics; version: string }
interface EnemyView { c: Container; body: Graphics; suit: string; arch: string }

const LAYER_LIFT = 0.42; // cells of lift per story
const ENEMY_VIS = 1.7; // enemies draw larger than their hit radius so they read at 10 px cells
const TURRET_VIS = 1.45;

export class Renderer {
  app: Application;
  world = new Container();
  private terrain = new Graphics();
  private roadG = new Graphics();
  private oreG = new Graphics();
  private coreC = new Container();
  private coreG = new Graphics();
  private objG = new Graphics();
  private towerLayer = new Container();
  private enemyLayer = new Container();
  private fx = new Graphics();
  private particlesG = new Graphics();
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
  reducedMotion = false;
  showRanges = false;
  selectedTower = 0;

  private towers = new Map<number, TowerView>();
  private enemies = new Map<number, EnemyView>();
  private particles: Particle[] = [];
  private texts: FloatText[] = [];
  private drops: Drop[] = [];
  private flashes: Flash[] = [];
  private hiddenPieces = new Set<number>();
  private shake = { x: 0, y: 0, t: 0, mag: 0 };
  private nudge = { x: 0, y: 0 };
  private boardRef: Board | null = null;
  private roadDrawnFinal = false;
  private time = 0;
  private cascade = 0;
  private perfectFlash = 0;
  private sealFlash: { a: number; b: number; t: number; ok: boolean }[] = [];
  hoverEdge: [number, number] | null = null;
  ghost: { piece: Piece; pv: Preview; range: number } | null = null;
  smiteAim: { x: number; y: number; r: number } | null = null;

  constructor(app: Application) {
    this.app = app;
    this.world.addChild(this.terrain, this.oreG, this.roadG, this.coreC, this.objG, this.towerLayer, this.enemyLayer, this.fx, this.particlesG, this.ghostG);
    this.coreC.addChild(this.coreG);
    this.fx.blendMode = 'normal';
    app.stage.addChild(this.world, this.screen, this.edgeGlow);
  }

  // ================================================================ camera
  layout() {
    const W = this.app.screen.width, H = this.app.screen.height;
    const v = this.viewport;
    const availW = W - v.left - v.right, availH = H - v.top - v.bottom;
    const base = Math.max(4, Math.min(availW / GRID_W, availH / GRID_H));
    this.cell = base * this.zoom * this.camZoom;
    const bw = GRID_W * this.cell, bh = GRID_H * this.cell;
    const cx = v.left + availW / 2, cy = v.top + availH / 2;
    this.offX = cx - bw / 2 + this.pan.x;
    this.offY = cy - bh / 2 + this.pan.y;
    if (this.zoom <= 1.001) { this.pan.x = 0; this.pan.y = 0; }
  }
  toWorld(sx: number, sy: number) {
    return { x: (sx - this.offX) / this.cell, y: (sy - this.offY) / this.cell };
  }
  toScreen(x: number, y: number) {
    return { x: this.offX + x * this.cell, y: this.offY + y * this.cell };
  }
  addShake(mag: number) {
    if (this.reducedMotion) return;
    this.shake.mag = Math.max(this.shake.mag, mag);
    this.shake.t = 0.236;
  }

  // ================================================================ board
  setBoard(b: Board) {
    this.boardRef = b;
    this.roadDrawnFinal = false;
    for (const v of this.towers.values()) v.c.destroy({ children: true });
    for (const v of this.enemies.values()) v.c.destroy({ children: true });
    this.towers.clear();
    this.enemies.clear();
    this.particles = [];
    this.drops = [];
    this.flashes = [];
    this.hiddenPieces.clear();
    this.drawTerrain(b);
    this.drawCore();
  }

  private drawTerrain(b: Board) {
    const g = this.terrain;
    g.clear();
    g.rect(-0.6, -0.6, GRID_W + 1.2, GRID_H + 1.2).fill({ color: 0x000000, alpha: 0.35 });
    g.rect(0, 0, GRID_W, GRID_H).fill(PAL.board);
    // subtle macro checker for depth
    for (let my = 0; my < MACRO_H; my++)
      for (let mx = 0; mx < MACRO_W; mx++)
        if ((mx + my) % 2 === 0) g.rect(mx * MACRO, my * MACRO, MACRO, MACRO).fill({ color: 0xffffff, alpha: 0.012 });
    for (let y = 0; y < GRID_H; y++)
      for (let x = 0; x < GRID_W; x++) {
        const h = b.height[y * GRID_W + x];
        if (h > 0) g.rect(x, y, 1, 1).fill(PAL.rise[Math.min(2, h - 1)]);
        else if (h < 0) g.rect(x, y, 1, 1).fill(PAL.valley[Math.min(1, -h - 1)]);
      }
    // cliff edges: light on top-left of rises, shadow under them
    for (let y = 0; y < GRID_H; y++)
      for (let x = 0; x < GRID_W; x++) {
        const h = b.height[y * GRID_W + x];
        const hd = y + 1 < GRID_H ? b.height[(y + 1) * GRID_W + x] : 0;
        const hr = x + 1 < GRID_W ? b.height[y * GRID_W + x + 1] : 0;
        const hu = y > 0 ? b.height[(y - 1) * GRID_W + x] : 0;
        if (h > hd) g.rect(x, y + 1, 1, 0.22 * (h - hd)).fill({ color: 0x000000, alpha: 0.35 });
        if (h > hr) g.rect(x + 1, y, 0.12 * (h - hr), 1).fill({ color: 0x000000, alpha: 0.25 });
        if (h > hu) g.rect(x, y, 1, 0.12).fill({ color: 0xffffff, alpha: 0.06 * (h - hu) });
      }
    for (let x = 0; x <= GRID_W; x++) g.moveTo(x, 0).lineTo(x, GRID_H);
    for (let y = 0; y <= GRID_H; y++) g.moveTo(0, y).lineTo(GRID_W, y);
    g.stroke({ width: 0.04, color: PAL.grid, alpha: 0.9 });
    for (let x = 0; x <= GRID_W; x += MACRO) g.moveTo(x, 0).lineTo(x, GRID_H);
    for (let y = 0; y <= GRID_H; y += MACRO) g.moveTo(0, y).lineTo(GRID_W, y);
    g.stroke({ width: 0.07, color: PAL.macro, alpha: 0.8 });
  }

  private drawCore() {
    const g = this.coreG;
    g.clear();
    // Fibonacci squares + golden spiral, scaled to fit around the core
    const s = 0.5;
    const sq: [number, number, number][] = [[0, 0, 8], [8, 0, 5], [10, 5, 3], [8, 6, 2], [8, 5, 1], [9, 5, 1]];
    const ox = -8.5 * s, oy = -5.5 * s;
    g.circle(0, 0, 4.2).fill({ color: PAL.core, alpha: 0.07 });
    g.circle(0, 0, 3.1).fill({ color: 0x251d10, alpha: 0.95 });
    for (const [x, y, n] of sq) g.rect(ox + x * s, oy + y * s, n * s, n * s).stroke({ width: 0.06, color: PAL.core, alpha: 0.35 });
    // spiral arcs through the squares (drawn outward from the core)
    const arcs: [number, number, number, number, number][] = [
      [9, 6, 1, Math.PI, Math.PI * 1.5], [9, 5, 1, Math.PI * 1.5, Math.PI * 2], [8, 6, 2, 0, Math.PI * 0.5],
      [10, 5, 3, Math.PI * 0.5, Math.PI], [13, 5, 5, Math.PI, Math.PI * 1.5], [8, 8, 8, Math.PI * 1.5, Math.PI * 2],
    ];
    void arcs;
    let r = 0.12, a = 0;
    g.moveTo(0, 0);
    for (let i = 0; i < 160; i++) {
      a += 0.08;
      r *= Math.pow(PHI, 0.08 / (Math.PI / 2));
      if (r > 2.9) break;
      g.lineTo(Math.cos(a) * r, Math.sin(a) * r);
    }
    g.stroke({ width: 0.16, color: PAL.core, alpha: 0.95, cap: 'round' });
    g.circle(0, 0, 0.35).fill(PAL.core);
    g.circle(0, 0, 3.1).stroke({ width: 0.12, color: PAL.core, alpha: 0.6 });
    this.coreC.position.set(CORE_PT.x, CORE_PT.y);
  }

  private drawRoadReveal(game: Game) {
    const b = game.board;
    const g = this.roadG;
    g.clear();
    const c = (m: number) => ({ x: mxy(m).x * MACRO + 4, y: mxy(m).y * MACRO + 4 });
    const frac = game.revealStep - Math.floor(game.revealStep);
    for (const p of b.paths) {
      const pts = [p.start, ...p.path.slice(0, p.revealed).map(c)];
      // head position between the last revealed macro and the next
      let head = pts[pts.length - 1];
      if (p.revealed < p.path.length && !game.revealPaused) {
        const nx = c(p.path[p.revealed]);
        head = { x: head.x + (nx.x - head.x) * frac, y: head.y + (nx.y - head.y) * frac };
        pts.push(head);
      }
      this.polyline(g, pts, 2.2, PAL.road, 1);
      this.polyline(g, pts, 0.18, PAL.roadGlow, 0.35);
      // crackling lightning head
      if (p.revealed < p.path.length) {
        const flick = Math.sin(this.time * 40) * 0.5 + 0.5;
        g.circle(head.x, head.y, 1.4 + flick * 0.6).fill({ color: 0xbfe8ff, alpha: 0.25 });
        for (let k = 0; k < 3; k++) {
          const ang = this.time * 7 + k * 2.1 + Math.sin(this.time * 31 + k) * 0.8;
          this.jagged(g, head.x, head.y, head.x + Math.cos(ang) * 4, head.y + Math.sin(ang) * 4, 0xd9f2ff, 0.12, 0.7);
        }
        g.circle(head.x, head.y, 0.6).fill(0xffffff);
      }
    }
    this.drawSeals(g, b);
  }

  private drawSeals(g: Graphics, b: Board) {
    const edgeLine = (a: number, bb: number) => {
      const p = mxy(a), q = mxy(bb);
      if (p.y === q.y) { const x = Math.max(p.x, q.x) * MACRO; return [x, p.y * MACRO + 1, x, p.y * MACRO + MACRO - 1]; }
      const y = Math.max(p.y, q.y) * MACRO;
      return [p.x * MACRO + 1, y, p.x * MACRO + MACRO - 1, y];
    };
    for (const k of b.seals) {
      const a = Math.floor(k / 1000), bb = k % 1000;
      const [x1, y1, x2, y2] = edgeLine(a, bb);
      g.moveTo(x1, y1).lineTo(x2, y2).stroke({ width: 0.9, color: PAL.seal, cap: 'round' });
      g.moveTo(x1, y1).lineTo(x2, y2).stroke({ width: 0.3, color: 0xffffff, alpha: 0.7, cap: 'round' });
    }
    if (this.hoverEdge) {
      const [x1, y1, x2, y2] = edgeLine(this.hoverEdge[0], this.hoverEdge[1]);
      g.moveTo(x1, y1).lineTo(x2, y2).stroke({ width: 0.7, color: PAL.seal, alpha: 0.45, cap: 'round' });
    }
    for (const f of this.sealFlash) {
      const [x1, y1, x2, y2] = edgeLine(f.a, f.b);
      const sh = f.ok ? 0 : Math.sin(f.t * 60) * 0.4;
      g.moveTo(x1 + sh, y1 + sh).lineTo(x2 + sh, y2 + sh).stroke({ width: 1.1, color: f.ok ? 0xffffff : PAL.bad, alpha: Math.min(1, f.t * 3), cap: 'round' });
    }
  }

  private drawRoadFinal(b: Board) {
    const g = this.roadG;
    g.clear();
    for (let y = 0; y < GRID_H; y++)
      for (let x = 0; x < GRID_W; x++) if (b.road[y * GRID_W + x]) g.rect(x, y, 1, 1).fill(PAL.road);
    for (let y = 0; y < GRID_H; y++)
      for (let x = 0; x < GRID_W; x++) {
        if (!b.road[y * GRID_W + x]) continue;
        const edge = (dx: number, dy: number) => { const nx = x + dx, ny = y + dy; return nx < 0 || ny < 0 || nx >= GRID_W || ny >= GRID_H || !b.road[ny * GRID_W + nx]; };
        if (edge(0, -1)) g.rect(x, y, 1, 0.12).fill({ color: PAL.roadEdge, alpha: 0.9 });
        if (edge(0, 1)) g.rect(x, y + 0.88, 1, 0.12).fill({ color: 0x000000, alpha: 0.3 });
        if (edge(-1, 0)) g.rect(x, y, 0.12, 1).fill({ color: PAL.roadEdge, alpha: 0.7 });
        if (edge(1, 0)) g.rect(x + 0.88, y, 0.12, 1).fill({ color: 0x000000, alpha: 0.25 });
      }
    for (const r of b.routes) this.polyline(g, r.pts, 0.14, PAL.roadGlow, 0.18);
    // ingress arrows
    for (const p of b.paths) {
      g.circle(p.start.x, p.start.y, 1.6).fill({ color: PAL.bad, alpha: 0.25 });
      g.circle(p.start.x, p.start.y, 0.8).fill({ color: PAL.bad, alpha: 0.6 });
    }
    this.roadDrawnFinal = true;
  }

  private polyline(g: Graphics, pts: { x: number; y: number }[], w: number, color: number, alpha: number) {
    if (pts.length < 2) return;
    g.moveTo(pts[0].x, pts[0].y);
    for (let i = 1; i < pts.length; i++) g.lineTo(pts[i].x, pts[i].y);
    g.stroke({ width: w, color, alpha, cap: 'round', join: 'round' });
  }

  private jagged(g: Graphics, x1: number, y1: number, x2: number, y2: number, color: number, w: number, alpha: number, seed = Math.random() * 1000) {
    const n = 7;
    g.moveTo(x1, y1);
    const dx = x2 - x1, dy = y2 - y1, len = Math.hypot(dx, dy) || 1;
    const nx = -dy / len, ny = dx / len;
    for (let i = 1; i < n; i++) {
      const t = i / n;
      const off = (Math.sin(seed * 12.9898 + i * 78.233 + this.time * 30) * 43758.5453 % 1) * len * 0.12;
      g.lineTo(x1 + dx * t + nx * off, y1 + dy * t + ny * off);
    }
    g.lineTo(x2, y2);
    g.stroke({ width: w, color, alpha, cap: 'round', join: 'round' });
  }

  // ================================================================ objects (ore, harvesters, road pieces)
  private drawObjects(game: Game) {
    const g = this.objG;
    g.clear();
    const b = game.board;
    const pulse = 0.55 + 0.45 * Math.sin(this.time * 2.2);
    if (this.roadDrawnFinal) {
      const og = this.oreG;
      og.clear();
      for (const v of b.veins) {
        og.roundRect(v.x - 0.3, v.y - 0.3, 3.6, 3.6, 0.6).fill({ color: PAL.ore, alpha: 0.08 + 0.08 * pulse });
        for (let dy = 0; dy < 3; dy++)
          for (let dx = 0; dx < 3; dx++) {
            const x = v.x + dx, y = v.y + dy;
            og.rect(x + 0.08, y + 0.08, 0.84, 0.84).fill({ color: 0x1c4652, alpha: 1 });
            og.poly([x + 0.5, y + 0.15, x + 0.82, y + 0.5, x + 0.5, y + 0.85, x + 0.18, y + 0.5]).fill({ color: PAL.ore, alpha: 0.45 + 0.35 * pulse });
          }
      }
    }
    for (const h of game.harvesters) {
      if (this.hiddenPieces.has(h.piece.id)) continue;
      this.cellsBlock(g, h.cells, PIECE_HEX[h.piece.color], 0, 0.85);
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
        g.roundRect(bb.x0 + 0.05, bb.y0 + 0.05, bb.w - 0.1, bb.h - 0.1, 0.3).fill(0x8d8fa8);
        g.roundRect(bb.x0 + 0.05, bb.y0 + 0.05, bb.w - 0.1, bb.h - 0.4, 0.3).fill(0xb9bcd4);
        for (let i = 1; i < bb.w; i++) g.moveTo(bb.x0 + i, bb.y0 + 0.2).lineTo(bb.x0 + i, bb.y1 + 0.8);
        g.stroke({ width: 0.06, color: 0x5c5e75 });
        if (rp.maxHp > 0) {
          const f = Math.max(0, rp.hp / rp.maxHp);
          g.rect(bb.x0, bb.y0 - 0.5, bb.w, 0.22).fill({ color: 0x000000, alpha: 0.5 });
          g.rect(bb.x0, bb.y0 - 0.5, bb.w * f, 0.22).fill(0xd0d4ff);
        }
      } else {
        rp.cells.forEach(([x, y], i) => {
          if (!rp.mines[i]) return;
          g.circle(x + 0.5, y + 0.5, 0.34).fill(0x30333f);
          g.circle(x + 0.5, y + 0.5, 0.34).stroke({ width: 0.06, color: PIECE_HEX[rp.piece.color] });
          const blink = Math.sin(this.time * 5 + i) > 0.6;
          g.circle(x + 0.5, y + 0.45, 0.1).fill(blink ? 0xff4a4a : 0x5a1a1a);
        });
      }
    }
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
    // side faces where nothing is below
    for (const [x, y] of cells) if (!has(x, y + 1)) g.rect(x, y + 1 - lift, 1, lift + 0.001 + 0.18).fill({ color: side, alpha });
    for (const [x, y] of cells) {
      g.rect(x, y - lift, 1, 1).fill({ color, alpha });
      g.rect(x + 0.1, y - lift + 0.1, 0.8, 0.14).fill({ color: 0xffffff, alpha: 0.22 * alpha });
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
        v = { c, base, turret, version: '' };
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
      v.turret.position.set(t.cx, t.cy - lift - 0.25);
      if (t.active) {
        const k = Math.min(1, t.activateT / T.l);
        const s = (k < 1 ? this.elastic(k) : 1 + (t.fireFlash > 0 ? 0.08 : 0)) * TURRET_VIS * Math.min(1.25, 0.8 + t.layers[0].length / 40);
        v.turret.scale.set(s);
        v.turret.rotation = t.angle + Math.PI / 2;
        v.turret.visible = true;
      } else v.turret.visible = false;
      v.c.zIndex = t.cy;
    }
    for (const [id, v] of this.towers) if (!live.has(id)) { v.c.destroy({ children: true }); this.towers.delete(id); }
    this.towerLayer.sortableChildren = true;
  }

  private elastic(k: number) {
    // ease-out-back: overshoots then settles, like a weapon snapping open
    const c1 = 1.70158, c3 = c1 + 1;
    return 1 + c3 * Math.pow(k - 1, 3) + c1 * Math.pow(k - 1, 2);
  }

  private drawTowerBase(g: Graphics, t: Tower) {
    g.clear();
    const ground = t.layers[0];
    // drop shadow
    for (const [x, y] of ground) g.rect(x + 0.25, y + 0.3, 1, 1).fill({ color: 0x000000, alpha: 0.28 });
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
      // stacked offset shadow under the next layer
      if (l + 1 < layers) for (const [x, y] of t.layers[l + 1]) g.rect(x + 0.12, y - lift + 0.12, 1, 1).fill({ color: 0x000000, alpha: 0.18 });
    }
    // hole cracks
    if (t.stats) for (const [x, y] of t.stats.shape.holes) {
      g.moveTo(x + 0.2, y + 0.2).lineTo(x + 0.5, y + 0.55).lineTo(x + 0.4, y + 0.8).moveTo(x + 0.5, y + 0.55).lineTo(x + 0.85, y + 0.4);
      g.stroke({ width: 0.08, color: PAL.bad, alpha: 0.8 });
    }
  }

  private drawTurret(g: Graphics, t: Tower) {
    g.clear();
    if (!t.type) return;
    const col = t.stats?.color ? PIECE_HEX[t.stats.color] : 0xdfe6ff;
    const dark = 0x1a2036;
    const ring = (r: number, c = col, w = 0.14) => g.circle(0, 0, r).stroke({ width: w, color: c });
    g.circle(0, 0.15, 1.05).fill({ color: 0x000000, alpha: 0.3 });
    g.circle(0, 0, 0.95).fill(dark);
    ring(0.95, col, 0.12);
    switch (t.type) {
      case 'Gun': g.roundRect(-0.18, -1.6, 0.36, 1.4, 0.1).fill(0xd8deef); break;
      case 'Machine Gun':
        g.roundRect(-0.36, -1.5, 0.22, 1.3, 0.08).fill(0xd8deef);
        g.roundRect(0.14, -1.5, 0.22, 1.3, 0.08).fill(0xd8deef);
        break;
      case 'Rifle': g.roundRect(-0.12, -2.2, 0.24, 2.0, 0.08).fill(0xeef2ff); g.rect(-0.25, -0.6, 0.5, 0.3).fill(col); break;
      case 'Bomb': g.circle(0, -0.4, 0.62).fill(0x9aa3c0); g.circle(0, -0.4, 0.32).fill(dark); break;
      case 'Missile':
        for (const dx of [-0.38, 0, 0.38]) g.poly([dx - 0.13, -0.1, dx + 0.13, -0.1, dx, -1.1]).fill(0xeef2ff);
        break;
      case 'Laser': g.poly([-0.5, -0.3, 0.5, -0.3, 0.16, -1.4, -0.16, -1.4]).fill(0xbfd7ff); g.circle(0, -1.4, 0.18).fill(col); break;
      case 'Pulsar': ring(0.55, col, 0.18); g.rect(-0.1, -1.7, 0.2, 1.3).fill(col); break;
      case 'Lightning': g.rect(-0.08, -1.7, 0.16, 1.6).fill(0xdfe6ff); g.circle(0, -1.75, 0.3).fill(0xbfe8ff); break;
      case 'E-Field': ring(0.5, 0xbfe8ff, 0.12); ring(0.25, 0xbfe8ff, 0.1); break;
      case 'Freezer': for (let k = 0; k < 6; k++) { const a = (k * Math.PI) / 3; g.moveTo(0, 0).lineTo(Math.cos(a) * 0.75, Math.sin(a) * 0.75); } g.stroke({ width: 0.14, color: 0xcff6ff, cap: 'round' }); break;
      case 'Flamer': g.poly([-0.3, -0.2, 0.3, -0.2, 0.45, -1.3, -0.45, -1.3]).fill(0xffb06b); break;
      case 'Acid': g.circle(0, -0.3, 0.5).fill(0x8cff7a); g.rect(-0.15, -1.3, 0.3, 0.9).fill(0x6fd860); break;
      case 'Virus': for (let k = 0; k < 8; k++) { const a = (k * Math.PI) / 4; g.circle(Math.cos(a) * 0.6, Math.sin(a) * 0.6, 0.12).fill(0xd88cff); } g.circle(0, 0, 0.4).fill(0xb05ce0); break;
    }
    if (t.stats?.pure) g.circle(0, 0, 0.2).fill(0xffe08a);
  }

  // ================================================================ enemies
  private syncEnemies(game: Game, alpha: number) {
    const live = new Set<number>();
    for (const e of game.enemies) {
      live.add(e.id);
      let v = this.enemies.get(e.id);
      if (!v) {
        const c = new Container();
        const body = new Graphics();
        c.addChild(body);
        this.enemyLayer.addChild(c);
        v = { c, body, suit: '', arch: '' };
        this.enemies.set(e.id, v);
        c.scale.set(0.01);
      }
      const x = e.px + (e.x - e.px) * alpha, y = e.py + (e.y - e.py) * alpha;
      if (v.suit !== e.suit || e.arch === 'swinger' || e.arch === 'slinky' || e.arch === 'roller') {
        v.suit = e.suit;
        this.drawEnemy(v.body, e);
      }
      const r = SIZES[e.size].radius * e.scale * ENEMY_VIS;
      let sx = 1, sy = 1, oy = 0;
      if (e.arch === 'hopper') {
        const ph = (e.animT % 0.618) / 0.618;
        if (ph < 0.45) { oy = -Math.sin((ph / 0.45) * Math.PI) * 0.9; sx = 0.9; sy = 1.12; } else { const k = Math.sin(((ph - 0.45) / 0.55) * Math.PI); sx = 1 + 0.25 * k; sy = 1 - 0.22 * k; }
      }
      if (e.arch === 'balloon') oy = -1.6 + Math.sin(e.animT * 2) * 0.2;
      const grow = Math.min(1, v.c.scale.x / Math.max(0.01, r) + 0.15);
      const pop = e.hitFlash > 0 ? 1.12 : 1;
      v.c.position.set(x, y + oy);
      v.c.scale.set(r * sx * pop * grow, r * sy * pop * grow);
      v.c.zIndex = y;
      v.c.alpha = e.immune ? 0.4 : 1;
      if (e.arch === 'roller') v.body.rotation = e.d * 1.4;
      else if (e.arch === 'tumbler') v.body.rotation = Math.floor(e.animT / 1.2) * (Math.PI / 2) + Math.min(1, (e.animT % 1.2) / 0.236) * (Math.PI / 2);
      else if (e.arch === 'nautilus' || e.arch === 'walker' || e.arch === 'slinky') v.body.rotation = e.dir;
      else v.body.rotation = 0;
    }
    for (const [id, v] of this.enemies) if (!live.has(id)) { v.c.destroy({ children: true }); this.enemies.delete(id); }
    this.enemyLayer.sortableChildren = true;
  }

  /** Enemy body in unit space (radius 1). */
  private drawEnemy(g: Graphics, e: Enemy) {
    g.clear();
    const c = suitColor(e.suit, e.size);
    const dk = shade(c, -0.45), lt = shade(c, 0.35);
    const eyes = (y = -0.15, sp = 0.32) => {
      g.circle(-sp, y, 0.2).fill(0xffffff); g.circle(sp, y, 0.2).fill(0xffffff);
      g.circle(-sp + 0.04, y + 0.03, 0.1).fill(0x1a1a2a); g.circle(sp + 0.04, y + 0.03, 0.1).fill(0x1a1a2a);
    };
    g.ellipse(0, 0.85, 0.85, 0.25).fill({ color: 0x000000, alpha: 0.25 });
    switch (e.arch) {
      case 'hopper':
        g.roundRect(-0.9, -0.85, 1.8, 1.7, 0.7).fill(c);
        g.roundRect(-0.7, -0.75, 1.0, 0.4, 0.2).fill({ color: 0xffffff, alpha: 0.35 });
        eyes();
        break;
      case 'slinky': {
        const st = e.stretched ? 1.9 : 1.0;
        for (let k = 0; k < 4; k++) g.roundRect(-0.7 * st + k * 0.45 * st - 0.1, -0.7, 0.75, 1.4, 0.35).fill(k % 2 ? dk : c);
        g.circle(0.9 * st, 0, 0.55).fill(lt);
        break;
      }
      case 'roller':
        g.circle(0, 0, 0.95).fill(c);
        g.moveTo(-0.95, 0).lineTo(0.95, 0).stroke({ width: 0.18, color: dk });
        g.arc(0, 0, 0.6, -0.8, 0.8).stroke({ width: 0.14, color: lt });
        break;
      case 'swinger': {
        const sw = Math.sin(e.animT * 7) * 0.9;
        g.moveTo(-0.5, -0.1).lineTo(-0.5 - Math.cos(sw) * 0.8, -0.1 + Math.sin(sw) * 0.8);
        g.moveTo(0.5, -0.1).lineTo(0.5 + Math.cos(-sw) * 0.8, -0.1 + Math.sin(-sw) * 0.8);
        g.stroke({ width: 0.25, color: dk, cap: 'round' });
        g.roundRect(-0.6, -0.9, 1.2, 1.7, 0.4).fill(c);
        eyes(-0.35, 0.24);
        break;
      }
      case 'tumbler':
        g.roundRect(-0.85, -0.85, 1.7, 1.7, 0.18).fill(c);
        g.roundRect(-0.6, -0.6, 1.2, 1.2, 0.1).stroke({ width: 0.12, color: lt });
        break;
      case 'nautilus': {
        g.ellipse(0.1, 0.35, 1.0, 0.45).fill(dk);
        g.circle(-0.15, -0.1, 0.8).fill(c);
        let r = 0.08, a = 0;
        g.moveTo(-0.15, -0.1);
        for (let i = 0; i < 60; i++) { a += 0.18; r *= 1.045; g.lineTo(-0.15 + Math.cos(a) * r, -0.1 + Math.sin(a) * r); if (r > 0.75) break; }
        g.stroke({ width: 0.1, color: lt });
        g.circle(0.95, 0.15, 0.22).fill(lt);
        break;
      }
      case 'balloon':
        g.moveTo(0, 0.9).lineTo(0.1, 2.2).stroke({ width: 0.06, color: 0xffffff, alpha: 0.6 });
        g.ellipse(0, 0, 0.85, 1.0).fill(c);
        g.ellipse(-0.3, -0.35, 0.22, 0.32).fill({ color: 0xffffff, alpha: 0.45 });
        g.poly([-0.15, 0.95, 0.15, 0.95, 0, 0.75]).fill(dk);
        break;
      case 'walker':
        for (const s of [-1, 1]) g.roundRect(-0.25 + s * 0.45 - 0.2, 0.2, 0.4, 0.9, 0.15).fill(dk);
        g.roundRect(-0.95, -1.0, 1.9, 1.5, 0.45).fill(c);
        g.roundRect(-0.6, -0.65, 1.2, 0.35, 0.15).fill(0x1a1a2a);
        g.circle(-0.25, -0.48, 0.1).fill(0xff5555); g.circle(0.25, -0.48, 0.1).fill(0xff5555);
        break;
    }
    if (e.golden) g.circle(0, 0, 1.15).stroke({ width: 0.14, color: 0xffe08a });
    if (e.boss) g.circle(0, 0, 1.25).stroke({ width: 0.1, color: 0xffffff, alpha: 0.7 });
    if (e.ability) this.abilityMark(g, e.ability);
  }

  private abilityMark(g: Graphics, a: string) {
    const col: Record<string, number> = {
      shielded: 0x9fd8ff, swift: 0xffffff, blink: 0xd59fff, splitter: 0xfff07a, bearer: 0x7ac8ff, grower: 0xff8a5c,
      regen: 0x7aff9a, phase: 0xc0c0ff, herald: 0xffd36b, hoarder: 0xffe08a,
    };
    g.circle(0.75, -0.75, 0.3).fill(0x10131f);
    g.circle(0.75, -0.75, 0.2).fill(col[a] ?? 0xffffff);
  }

  // ================================================================ events → effects
  handleEvents(events: GameEvent[], game: Game) {
    const rm = this.reducedMotion;
    for (const ev of events) {
      switch (ev.t) {
        case 'place': {
          const dur = T.s;
          this.drops.push({ pieceId: ev.pieceId, cells: ev.cells, color: PIECE_HEX[ev.color], t: 0, dur, height: 7, towerId: ev.towerId, size: ev.size });
          this.hiddenPieces.add(ev.pieceId);
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
        case 'shot': {
          const kind = ev.kind;
          if (kind === 'hitscan' || kind === 'ricochet' || kind === 'tank')
            this.flashes.push({ kind, x1: ev.x1, y1: ev.y1, x2: ev.x2, y2: ev.y2, life: kind === 'hitscan' ? 0.18 : 0.12, max: 0.18, color: ev.color ? PIECE_HEX[ev.color] : 0xffffff, seed: Math.random() });
          else if (kind === 'pierce')
            this.flashes.push({ kind, x1: ev.x1, y1: ev.y1, x2: ev.x2, y2: ev.y2, life: 0.236, max: 0.236, color: ev.color ? PIECE_HEX[ev.color] : 0xbfe0ff, seed: 0 });
          else if (kind === 'cone' && !rm) {
            const a = Math.atan2(ev.y2 - ev.y1, ev.x2 - ev.x1);
            for (let k = 0; k < 3; k++) {
              const aa = a + (Math.random() - 0.5) * 1.1, sp = 8 + Math.random() * 6;
              this.particles.push({ x: ev.x1, y: ev.y1, vx: Math.cos(aa) * sp, vy: Math.sin(aa) * sp, life: 0.5, max: 0.5, size: 0.35, color: Math.random() < 0.5 ? 0xffb347 : 0xff6b3d, kind: 'dot', g: -2, spin: 0, ang: 0 });
            }
          } else if (kind === 'virus')
            this.flashes.push({ kind, x1: ev.x1, y1: ev.y1, x2: ev.x2, y2: ev.y2, life: 0.3, max: 0.3, color: 0xd88cff, seed: Math.random() });
          else if (kind === 'bullet' && !rm) this.particles.push({ x: ev.x1, y: ev.y1, vx: 0, vy: 0, life: 0.08, max: 0.08, size: 0.6, color: 0xffffff, kind: 'dot', g: 0, spin: 0, ang: 0 });
          break;
        }
        case 'bolt':
          this.flashes.push({ kind: 'bolt', x1: ev.x1, y1: ev.y1, x2: ev.x2, y2: ev.y2, life: 0.18, max: 0.18, color: 0xd9f2ff, seed: Math.random() * 100 });
          if (!ev.miss) this.ring(ev.x2, ev.y2, 0.2, 1.5, 0xd9f2ff, 0.2);
          break;
        case 'explode':
          this.ring(ev.x, ev.y, 0.2, ev.r + 0.6, ev.color ? PIECE_HEX[ev.color] : 0xffc46b, T.s);
          for (let k = 0; k < (rm ? 3 : 10); k++) this.spark(ev.x, ev.y, k % 2 ? 0xffd28a : 0xff7a4a, 7);
          this.addShake(0.12);
          break;
        case 'mine':
          this.ring(ev.x, ev.y, 0.2, 2.2, 0xff6b3d, T.m);
          for (let k = 0; k < (rm ? 4 : 14); k++) this.spark(ev.x, ev.y, 0xffb347, 9);
          this.addShake(0.35);
          break;
        case 'kill': {
          const col = suitColor(ev.suit, ev.size);
          const n = rm ? 4 : ev.size === 'small' ? 10 : ev.size === 'medium' ? 14 : 22;
          if (ev.split) this.splitBurst(ev.x, ev.y, col);
          for (let k = 0; k < n; k++) {
            const a = Math.random() * Math.PI * 2, sp = 3 + Math.random() * 6;
            this.particles.push({ x: ev.x, y: ev.y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp - 3, life: 0.6 + Math.random() * 0.4, max: 1, size: 0.25 + Math.random() * 0.3, color: k % 3 ? col : 0xffffff, kind: k % 2 ? 'square' : 'dot', g: 14, spin: (Math.random() - 0.5) * 12, ang: 0 });
          }
          this.ring(ev.x, ev.y, 0.3, 1.6 + SIZES[ev.size].radius, col, T.s);
          if (ev.essence >= 1) this.text(`+${Math.round(ev.essence)}`, ev.x, ev.y - 1, 0xb8f3ff, 11);
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
        case 'seal': this.sealFlash.push({ a: ev.a, b: ev.b, t: 0.4, ok: true }); break;
        case 'sealReject': this.sealFlash.push({ a: ev.a, b: ev.b, t: 0.5, ok: false }); break;
        case 'smite':
          this.ring(ev.x, ev.y, 0.5, ev.r, 0xfff3c0, T.l);
          this.ring(ev.x, ev.y, 0.5, ev.r * 0.6, 0xffffff, T.m);
          this.flashes.push({ kind: 'smite', x1: ev.x, y1: -10, x2: ev.x, y2: ev.y, life: 0.382, max: 0.382, color: 0xfff3c0, seed: 0 });
          this.addShake(0.8);
          break;
        case 'barrierBreak':
          for (let k = 0; k < 12; k++) this.spark(ev.x, ev.y, 0xb9bcd4, 6);
          break;
        case 'revealDone':
          this.drawRoadFinal(game.board);
          break;
      }
    }
  }

  private ring(x: number, y: number, r0: number, r1: number, color: number, life: number) {
    this.particles.push({ x, y, vx: 0, vy: 0, life, max: life, size: r1, r0, color, kind: 'ring', g: 0, spin: 0, ang: 0 });
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
    // calm phases ease the camera out by 5%
    const targetZoom = game.phase === 'calm' || game.phase === 'reveal' ? 0.95 : 1;
    this.camZoom += (targetZoom - this.camZoom) * Math.min(1, dt * 1.5);
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
    if (game.phase === 'reveal') this.drawRoadReveal(game);
    else if (!this.roadDrawnFinal) this.drawRoadFinal(game.board);
    this.coreC.rotation = this.time * 0.15;
    this.coreC.scale.set(1 + Math.sin(this.time * 2) * 0.02);

    this.stepDrops(dt);
    this.drawObjects(game);
    this.syncTowers(game);
    this.syncEnemies(game, alpha);
    this.drawFx(game, alpha, dt);
    this.drawParticles(dt);
    this.drawGhost();
    this.drawTexts(dt);
    this.drawEdgeGlow(dt);
    this.sealFlash = this.sealFlash.filter((f) => (f.t -= dt) > 0);
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

  private drawFx(game: Game, alpha: number, dt: number) {
    const g = this.fx;
    g.clear();
    // drops (falling pieces with squash)
    for (const d of this.drops) {
      const k = d.t / d.dur;
      const fall = (1 - k * k) * d.height;
      const t = d.towerId ? game.towerById(d.towerId) : null;
      const layer = t ? Math.max(0, ...t.pieces.filter((p) => p.piece.id === d.pieceId).map((p) => p.layer)) : 0;
      for (const [x, y] of d.cells) g.rect(x + 0.2, y + 0.25, 1, 1).fill({ color: 0x000000, alpha: 0.25 * k });
      this.cellsBlock(g, d.cells, d.color, layer * LAYER_LIFT + fall, 0.95);
    }
    // puddles
    for (const p of game.puddles) {
      g.circle(p.x, p.y, p.r).fill({ color: 0x8cff7a, alpha: 0.16 * Math.min(1, p.t) });
      g.circle(p.x, p.y, p.r * 0.6).fill({ color: 0xbaff9a, alpha: 0.12 * Math.min(1, p.t) });
    }
    // auras and beams
    for (const t of game.towers) {
      if (!t.active || !t.stats || !t.type) continue;
      const lift = (t.layers.length - 1) * LAYER_LIFT + 0.45;
      const def = TOWERS[t.type];
      if (def.kind === 'aura') {
        const col = t.type === 'Freezer' ? 0xbff4ff : 0x9fd8ff;
        const pulse = (this.time * 0.8) % 1;
        g.circle(t.cx, t.cy, t.stats.range * pulse).stroke({ width: 0.12, color: col, alpha: 0.18 * (1 - pulse) });
        if (t.fireFlash > 0 && t.type === 'E-Field')
          for (const e of game.enemies)
            if (Math.hypot(e.x - t.cx, e.y - t.cy) <= t.stats.range && e.arch !== 'balloon')
              this.jagged(g, t.cx, t.cy - lift, e.x, e.y, 0xcfeaff, 0.08, 0.6, e.id);
      }
      if (def.kind === 'beam' && t.targetId) {
        const e = game.enemies.find((x) => x.id === t.targetId);
        if (e) {
          const ex = e.px + (e.x - e.px) * alpha, ey = e.py + (e.y - e.py) * alpha;
          const ramp = Math.min(1, t.rampT / 3);
          const col = t.stats.color ? PIECE_HEX[t.stats.color] : 0xbfd7ff;
          g.moveTo(t.cx, t.cy - lift).lineTo(ex, ey).stroke({ width: 0.25 + ramp * 0.45, color: col, alpha: 0.35, cap: 'round' });
          g.moveTo(t.cx, t.cy - lift).lineTo(ex, ey).stroke({ width: 0.08 + ramp * 0.15, color: 0xffffff, alpha: 0.9, cap: 'round' });
          g.circle(ex, ey, 0.4 + ramp * 0.4 + Math.random() * 0.15).fill({ color: 0xffffff, alpha: 0.6 });
        }
      }
      if (t.stats.spire) {
        g.ellipse(t.cx, t.cy - lift - 1.2, 1.2, 0.4).stroke({ width: 0.12, color: 0xffe08a, alpha: 0.6 + 0.3 * Math.sin(this.time * 3) });
      }
      if (this.showRanges || this.selectedTower === t.id) {
        g.circle(t.cx, t.cy, t.stats.range).fill({ color: 0xffffff, alpha: this.selectedTower === t.id ? 0.05 : 0.02 });
        g.circle(t.cx, t.cy, t.stats.range).stroke({ width: 0.1, color: 0xffffff, alpha: this.selectedTower === t.id ? 0.5 : 0.15 });
      }
      if (!t.type && t.layers[0]) {
        // unfinished pile marker
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
      const col = p.color ? PIECE_HEX[p.color] : 0xffffff;
      if (p.kind === 'bullet') {
        const dx = p.x - p.px, dy = p.y - p.py;
        g.moveTo(x - dx * 2, y - dy * 2).lineTo(x, y).stroke({ width: 0.3, color: col, alpha: 0.7, cap: 'round' });
        g.circle(x, y, 0.24).fill(0xffffff);
      } else if (p.kind === 'lob' || p.kind === 'acid') {
        const k = Math.min(1, p.t / p.dur);
        const hgt = Math.sin(k * Math.PI) * 3;
        g.circle(x, y, 0.3).fill({ color: 0x000000, alpha: 0.25 });
        g.circle(x, y - hgt, 0.4).fill(p.kind === 'acid' ? 0x8cff7a : 0x2b2f45);
        g.circle(x - 0.1, y - hgt - 0.1, 0.14).fill({ color: 0xffffff, alpha: 0.5 });
      } else if (p.kind === 'homing') {
        const a = Math.atan2(p.y - p.py, p.x - p.px);
        g.poly([x + Math.cos(a) * 0.6, y + Math.sin(a) * 0.6, x + Math.cos(a + 2.5) * 0.35, y + Math.sin(a + 2.5) * 0.35, x + Math.cos(a - 2.5) * 0.35, y + Math.sin(a - 2.5) * 0.35]).fill(0xeef2ff);
        if (!this.reducedMotion && Math.random() < 0.6)
          this.particles.push({ x: x - Math.cos(a) * 0.4, y: y - Math.sin(a) * 0.4, vx: 0, vy: 0, life: 0.4, max: 0.4, size: 0.25, color: 0x9aa3c0, kind: 'dot', g: -1, spin: 0, ang: 0 });
      }
    }
    // tanks
    for (const k of game.tanks) {
      const x = k.px + (k.x - k.px) * alpha, y = k.py + (k.y - k.py) * alpha;
      g.roundRect(x - 0.7, y - 0.5, 1.4, 1.0, 0.25).fill(0xffd36b);
      g.circle(x, y, 0.35).fill(0x8a6a2a);
    }
    // flashes
    for (const f of this.flashes) {
      const a = f.life / f.max;
      if (f.kind === 'bolt') { this.jagged(g, f.x1, f.y1, f.x2, f.y2, f.color, 0.18, a, f.seed); this.jagged(g, f.x1, f.y1, f.x2, f.y2, 0xffffff, 0.06, a, f.seed + 1); }
      else if (f.kind === 'smite') { g.moveTo(f.x1, f.y1).lineTo(f.x2, f.y2).stroke({ width: 2.5 * a, color: f.color, alpha: a }); }
      else if (f.kind === 'virus') { g.moveTo(f.x1, f.y1).quadraticCurveTo((f.x1 + f.x2) / 2 + 1, (f.y1 + f.y2) / 2 - 2, f.x2, f.y2).stroke({ width: 0.12, color: f.color, alpha: a * 0.7 }); }
      else {
        g.moveTo(f.x1, f.y1).lineTo(f.x2, f.y2).stroke({ width: f.kind === 'pierce' ? 0.5 * a + 0.1 : 0.12, color: f.color, alpha: a, cap: 'round' });
        if (f.kind === 'pierce') g.moveTo(f.x1, f.y1).lineTo(f.x2, f.y2).stroke({ width: 0.1, color: 0xffffff, alpha: a });
      }
      f.life -= dt;
    }
    this.flashes = this.flashes.filter((f) => f.life > 0);
    // enemy hp bars and status
    for (const e of game.enemies) {
      const x = e.px + (e.x - e.px) * alpha, y = e.py + (e.y - e.py) * alpha;
      const r = SIZES[e.size].radius * e.scale * ENEMY_VIS;
      const oy = e.arch === 'balloon' ? -1.6 : 0;
      if (e.hp < e.maxHp || e.shield > 0) {
        const w = Math.max(1.2, r * 2.2);
        g.rect(x - w / 2, y + oy - r - 0.6, w, 0.22).fill({ color: 0x000000, alpha: 0.55 });
        g.rect(x - w / 2, y + oy - r - 0.6, w * Math.max(0, e.hp / e.maxHp), 0.22).fill(e.hp / e.maxHp > 0.4 ? 0x7dffb0 : 0xffb35c);
        if (e.shield > 0) g.rect(x - w / 2, y + oy - r - 0.85, w * Math.min(1, e.shield / (e.maxHp * 0.38)), 0.16).fill(0x9fd8ff);
      }
      if (e.slowMult < 1) g.circle(x, y + oy, r + 0.15).stroke({ width: 0.08, color: 0xbff4ff, alpha: 0.6 });
      if (e.dots.length) {
        const d = e.dots[0];
        const c = d.kind === 'virus' ? 0xd88cff : d.kind === 'poison' ? 0x8cff7a : 0xff8a3d;
        if (!this.reducedMotion && Math.random() < 0.25)
          this.particles.push({ x: x + (Math.random() - 0.5) * r, y: y + oy, vx: 0, vy: -2, life: 0.5, max: 0.5, size: 0.18, color: c, kind: 'dot', g: 0, spin: 0, ang: 0 });
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
    g.clear();
    if (this.particles.length > 1400) this.particles.splice(0, this.particles.length - 1400);
    for (const p of this.particles) {
      p.life -= dt;
      const k = Math.max(0, p.life / p.max);
      if (p.kind === 'ring') {
        const r = p.r0! + (p.size - p.r0!) * (1 - k * k);
        g.circle(p.x, p.y, r).stroke({ width: 0.15 + 0.25 * k, color: p.color, alpha: k });
        continue;
      }
      if (p.kind === 'spiral') {
        // particles sweeping out along a golden spiral
        const tt = 1 - k;
        const dir = p.r0 === -1 ? 1 : -1;
        const r = 0.3 * Math.pow(PHI, tt * 5);
        const a = p.ang + dir * tt * 4;
        p.x = p.cx! + Math.cos(a) * r;
        p.y = p.cy! + Math.sin(a) * r + (p.r0 === -1 ? tt * tt * 6 : 0);
        g.circle(p.x, p.y, p.size * (0.5 + k)).fill({ color: p.color, alpha: k });
        continue;
      }
      p.vy += p.g * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= 0.97;
      p.ang += p.spin * dt;
      if (p.kind === 'square') {
        const s = p.size;
        const c = Math.cos(p.ang) * s, sn = Math.sin(p.ang) * s;
        g.poly([p.x - c + sn, p.y - sn - c, p.x + c + sn, p.y + sn - c, p.x + c - sn, p.y + sn + c, p.x - c - sn, p.y - sn + c]).fill({ color: p.color, alpha: k });
      } else if (p.kind === 'spark') {
        g.moveTo(p.x, p.y).lineTo(p.x - p.vx * 0.04, p.y - p.vy * 0.04).stroke({ width: p.size, color: p.color, alpha: k, cap: 'round' });
      } else g.circle(p.x, p.y, p.size * (0.4 + 0.6 * k)).fill({ color: p.color, alpha: k });
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
    // drop shadow at landing + ghost above
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
  }
}

export { shade };
