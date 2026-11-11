// Monster art: detailed vector bodies with layered shading, pre-rendered to cached textures.
// Every form has walk frames; tiers add armour plates, glowing seams, horns and a crown.
// Textures are made on first use, so only the combinations a run meets are ever drawn.
import { Container, Graphics, type Renderer as PixiRenderer, Text, Texture } from 'pixi.js';
import { GROUPS, type Archetype, type Group } from '../balance';
import { mix, shade } from './palette';

const S = 44; // texture pixels per body unit (body radius is 1 unit)
export const ART_SCALE = 1 / S;

type G = Graphics;

/** Fill a closed shape three times to fake a lit 3D volume: shadow side, body, highlight. */
function volume(g: G, path: (g: G, k: number) => void, c: number, cx = 0, cy = 0, r = 1) {
  const dark = shade(c, -0.5), lt = shade(c, 0.45);
  path(g, 1.0); g.fill(dark);
  path(g, 0.94); g.fill(c);
  // soft core light, up-left of the part's centre
  g.ellipse(cx - 0.25 * r, cy - 0.32 * r, 0.55 * r, 0.4 * r).fill({ color: lt, alpha: 0.35 });
  g.ellipse(cx - 0.32 * r, cy - 0.42 * r, 0.22 * r, 0.13 * r).fill({ color: 0xffffff, alpha: 0.55 });
  path(g, 1.0); g.stroke({ width: 0.07, color: shade(c, -0.7), alpha: 0.9 });
}

function eyes(g: G, x: number, y: number, sp: number, r: number, glow = false, col = 0x1a1a2a) {
  for (const s of [-1, 1]) {
    const ex = x, ey = y + s * sp;
    if (glow) g.circle(ex, ey, r * 1.9).fill({ color: 0xff5040, alpha: 0.35 });
    g.circle(ex, ey, r).fill(glow ? 0xffe9a0 : 0xffffff);
    g.circle(ex + r * 0.3, ey, r * 0.55).fill(glow ? 0xff3020 : col);
    g.circle(ex + r * 0.1, ey - r * 0.35, r * 0.25).fill({ color: 0xffffff, alpha: 0.9 });
  }
}

function legs(g: G, n: number, frame: number, len: number, col: number, spread = 0.9, y0 = 0.55) {
  for (let i = 0; i < n; i++) {
    const t = n === 1 ? 0 : i / (n - 1) - 0.5;
    const x = t * spread * 2;
    const ph = (frame + i * 2) % 4;
    const swing = [0.35, 0.1, -0.35, -0.1][ph];
    for (const s of [-1, 1]) {
      const bx = x, by = s * y0;
      const kx = bx + swing * 0.5, ky = s * (y0 + len * 0.55);
      const fx = bx + swing, fy = s * (y0 + len);
      g.moveTo(bx, by).lineTo(kx, ky).lineTo(fx, fy);
    }
  }
  g.stroke({ width: 0.13, color: col, cap: 'round', join: 'round' });
}

// ---------------------------------------------------------------- forms
// Forms face +x (right). Coordinates are body units; radius about 1.
type FormDraw = (g: G, c: number, frame: number, variant: number) => void;

const FORMS: Record<Archetype, FormDraw> = {
  hopper(g, c) {
    const body = (g: G, k: number) => g.roundRect(-0.9 * k, -0.85 * k, 1.8 * k, 1.7 * k, 0.6 * k);
    volume(g, body, c);
    g.roundRect(-0.45, 0.55, 0.9, 0.18, 0.09).fill({ color: shade(c, -0.6), alpha: 0.5 });
    eyes(g, 0.35, -0.05, 0.3, 0.2);
  },
  crawler(g, c, frame) {
    legs(g, 3, frame, 0.55, shade(c, -0.55), 0.55, 0.38);
    const body = (g: G, k: number) => g.ellipse(-0.15, 0, 0.75 * k, 0.55 * k);
    volume(g, body, c, -0.15, 0, 0.7);
    const head = (g: G, k: number) => g.circle(0.62, 0, 0.36 * k);
    volume(g, head, shade(c, -0.15), 0.62, 0, 0.36);
    g.circle(0.8, -0.12, 0.07).fill(0xff4a4a); g.circle(0.8, 0.12, 0.07).fill(0xff4a4a); g.circle(0.88, 0, 0.05).fill(0xff4a4a);
    g.moveTo(-0.5, -0.3).lineTo(0.15, -0.35).moveTo(-0.55, 0).lineTo(0.2, 0).moveTo(-0.5, 0.3).lineTo(0.15, 0.35)
      .stroke({ width: 0.05, color: shade(c, -0.55), alpha: 0.6 });
  },
  blob(g, c) {
    const body = (g: G, k: number) => {
      g.moveTo(-0.95 * k, 0.4 * k)
        .bezierCurveTo(-1.0 * k, -0.6 * k, -0.2 * k, -1.0 * k, 0.35 * k, -0.8 * k)
        .bezierCurveTo(1.05 * k, -0.55 * k, 1.05 * k, 0.55 * k, 0.5 * k, 0.75 * k)
        .bezierCurveTo(0.0, 0.95 * k, -0.85 * k, 0.95 * k, -0.95 * k, 0.4 * k)
        .closePath();
    };
    volume(g, body, c);
    g.circle(-0.15, 0.1, 0.32).fill({ color: shade(c, -0.35), alpha: 0.6 }); // nucleus
    g.circle(-0.22, 0.03, 0.12).fill({ color: shade(c, 0.4), alpha: 0.5 });
    for (const [x, y, r] of [[0.35, 0.35, 0.08], [-0.55, -0.2, 0.06], [0.1, -0.45, 0.05]] as const) g.circle(x, y, r).stroke({ width: 0.03, color: 0xffffff, alpha: 0.6 });
    eyes(g, 0.45, -0.15, 0.22, 0.15);
  },
  slinky(g, c, _frame, variant) {
    const st = variant === 1 ? 1.45 : 1.0;
    for (let k = 3; k >= 0; k--) {
      const x = (-0.9 + k * 0.42) * st;
      const seg = (g: G, kk: number) => g.circle(x, 0, 0.45 * kk);
      volume(g, seg, k % 2 ? shade(c, -0.15) : c, x, 0, 0.45);
    }
    const head = (g: G, k: number) => g.circle(0.75 * st + 0.1, 0, 0.5 * k);
    volume(g, head, shade(c, 0.1), 0.75 * st + 0.1, 0, 0.5);
    g.moveTo(0.95 * st, -0.3).quadraticCurveTo(1.15 * st, -0.75, 1.35 * st, -0.7).moveTo(0.95 * st, 0.3).quadraticCurveTo(1.15 * st, 0.75, 1.35 * st, 0.7)
      .stroke({ width: 0.06, color: shade(c, -0.6) });
    g.circle(1.35 * st, -0.7, 0.08).fill(shade(c, 0.5)); g.circle(1.35 * st, 0.7, 0.08).fill(shade(c, 0.5));
    eyes(g, 0.95 * st, 0, 0.18, 0.13);
  },
  roller(g, c) {
    const body = (g: G, k: number) => g.circle(0, 0, 0.95 * k);
    volume(g, body, c);
    for (const a of [-0.55, 0, 0.55]) {
      g.moveTo(a * 1.4, -0.85).quadraticCurveTo(a * 1.4 + 0.25, 0, a * 1.4, 0.85).stroke({ width: 0.1, color: shade(c, -0.55), alpha: 0.8 });
      g.moveTo(a * 1.4 + 0.08, -0.75).quadraticCurveTo(a * 1.4 + 0.3, 0, a * 1.4 + 0.08, 0.75).stroke({ width: 0.04, color: shade(c, 0.5), alpha: 0.6 });
    }
  },
  swinger(g, c, frame) {
    const sw = [0.9, 0.3, -0.9, -0.3][frame];
    const arm = shade(c, -0.35);
    for (const s of [-1, 1]) {
      const sx = 0.0, sy = s * 0.55;
      const hx = 0.2 + Math.cos(sw * s) * 0.9, hy = s * (0.6 + Math.abs(Math.sin(sw)) * 0.6);
      g.moveTo(sx, sy).quadraticCurveTo((sx + hx) / 2 + 0.2, sy + s * 0.5, hx, hy).stroke({ width: 0.26, color: arm, cap: 'round' });
      g.circle(hx, hy, 0.18).fill(shade(c, -0.5));
    }
    const body = (g: G, k: number) => g.roundRect(-0.6 * k, -0.62 * k, 1.2 * k, 1.24 * k, 0.45 * k);
    volume(g, body, c, 0, 0, 0.62);
    g.ellipse(0.3, 0, 0.3, 0.42).fill({ color: shade(c, 0.35), alpha: 0.5 }); // face
    eyes(g, 0.38, 0, 0.17, 0.13);
  },
  tumbler(g, c) {
    // bevelled cube seen from above-ish: top face, two side faces
    g.poly([-0.85, -0.6, 0.35, -0.95, 0.95, -0.35, -0.25, 0.0]).fill(shade(c, 0.3));
    g.poly([-0.85, -0.6, -0.25, 0.0, -0.25, 0.95, -0.85, 0.35]).fill(shade(c, -0.35));
    g.poly([-0.25, 0.0, 0.95, -0.35, 0.95, 0.6, -0.25, 0.95]).fill(c);
    g.poly([-0.85, -0.6, 0.35, -0.95, 0.95, -0.35, 0.95, 0.6, -0.25, 0.95, -0.85, 0.35]).stroke({ width: 0.07, color: shade(c, -0.7) });
    g.poly([-0.55, -0.55, 0.3, -0.78, 0.65, -0.4, -0.2, -0.18]).stroke({ width: 0.05, color: 0xffffff, alpha: 0.4 });
    eyes(g, 0.35, 0.3, 0.2, 0.12);
  },
  nautilus(g, c) {
    // tentacles
    for (const s of [-1, 0, 1]) g.moveTo(0.6, s * 0.2).quadraticCurveTo(1.0, s * 0.45, 1.25, s * 0.35 + 0.1).stroke({ width: 0.12, color: shade(c, -0.25), cap: 'round' });
    const shell = (g: G, k: number) => g.circle(-0.15, 0, 0.85 * k);
    volume(g, shell, c, -0.15, 0, 0.85);
    let r = 0.08, a = 0;
    g.moveTo(-0.15, 0);
    for (let i = 0; i < 70; i++) { a += 0.17; r *= 1.045; g.lineTo(-0.15 + Math.cos(a) * r, Math.sin(a) * r); if (r > 0.78) break; }
    g.stroke({ width: 0.08, color: shade(c, -0.55) });
    for (let k = 0; k < 6; k++) { const aa = k * 1.05; g.moveTo(-0.15 + Math.cos(aa) * 0.3, Math.sin(aa) * 0.3).lineTo(-0.15 + Math.cos(aa) * 0.8, Math.sin(aa) * 0.8); }
    g.stroke({ width: 0.03, color: shade(c, 0.45), alpha: 0.5 });
    const head = (g: G, k: number) => g.ellipse(0.65, 0, 0.32 * k, 0.4 * k);
    volume(g, head, shade(c, 0.2), 0.65, 0, 0.36);
    eyes(g, 0.72, 0, 0.17, 0.1);
  },
  beetle(g, c, frame) {
    legs(g, 3, frame, 0.5, shade(c, -0.6), 0.5, 0.55);
    const shell = (g: G, k: number) => g.ellipse(-0.1, 0, 0.85 * k, 0.72 * k);
    volume(g, shell, c);
    g.moveTo(-0.95, 0).lineTo(0.6, 0).stroke({ width: 0.06, color: shade(c, -0.7) });
    g.ellipse(-0.3, -0.35, 0.35, 0.18).fill({ color: 0xffffff, alpha: 0.18 });
    g.ellipse(-0.3, 0.35, 0.35, 0.18).fill({ color: 0xffffff, alpha: 0.1 });
    const head = (g: G, k: number) => g.ellipse(0.78, 0, 0.28 * k, 0.34 * k);
    volume(g, head, shade(c, -0.3), 0.78, 0, 0.3);
    g.moveTo(0.95, -0.15).quadraticCurveTo(1.25, -0.25, 1.25, -0.05).moveTo(0.95, 0.15).quadraticCurveTo(1.25, 0.25, 1.25, 0.05).stroke({ width: 0.07, color: shade(c, -0.7) });
    g.circle(0.88, -0.14, 0.06).fill(0xffffff); g.circle(0.88, 0.14, 0.06).fill(0xffffff);
  },
  balloon(g, c) {
    g.moveTo(-0.9, 0).lineTo(-1.5, 0.1).stroke({ width: 0.05, color: 0xffffff, alpha: 0.6 });
    const body = (g: G, k: number) => g.ellipse(0, 0, 0.92 * k, 0.85 * k);
    volume(g, body, c);
    for (const a of [-0.45, 0, 0.45]) g.moveTo(-0.85, a * 0.6).quadraticCurveTo(0, a * 1.9, 0.85, a * 0.6).stroke({ width: 0.04, color: shade(c, -0.4), alpha: 0.5 });
    g.poly([-0.95, -0.12, -0.95, 0.12, -1.12, 0]).fill(shade(c, -0.5));
    eyes(g, 0.4, 0, 0.25, 0.16);
  },
  walker(g, c, frame) {
    legs(g, 2, frame, 0.7, shade(c, -0.6), 0.45, 0.55);
    const body = (g: G, k: number) => g.roundRect(-0.85 * k, -0.75 * k, 1.7 * k, 1.5 * k, 0.35 * k);
    volume(g, body, c);
    g.roundRect(0.25, -0.5, 0.45, 1.0, 0.12).fill(0x1a1a2a); // visor
    g.circle(0.48, -0.22, 0.09).fill(0xff5555); g.circle(0.48, 0.22, 0.09).fill(0xff5555);
    g.circle(0.48, -0.22, 0.18).fill({ color: 0xff5555, alpha: 0.25 }); g.circle(0.48, 0.22, 0.18).fill({ color: 0xff5555, alpha: 0.25 });
    g.rect(-0.6, -0.95, 0.5, 0.25).fill(shade(c, -0.4)); g.rect(-0.6, 0.7, 0.5, 0.25).fill(shade(c, -0.4));
  },
};

// ---------------------------------------------------------------- tiers
function tierDecor(g: G, c: number, tier: number, champion: boolean) {
  if (tier >= 2) {
    // armour plates with rivets on the back
    const plate = 0x8d97b5, plateLt = 0xd8deef;
    for (const [x, y, w, h] of [[-0.75, -0.42, 0.42, 0.84], [-0.3, -0.5, 0.36, 1.0]] as const) {
      g.roundRect(x, y, w, h, 0.1).fill(plate);
      g.roundRect(x + 0.04, y + 0.04, w - 0.08, h * 0.35, 0.08).fill({ color: plateLt, alpha: 0.7 });
      g.roundRect(x, y, w, h, 0.1).stroke({ width: 0.04, color: 0x3a4058 });
      g.circle(x + w / 2, y + 0.12, 0.04).fill(0x3a4058);
      g.circle(x + w / 2, y + h - 0.12, 0.04).fill(0x3a4058);
    }
  }
  if (tier >= 3) {
    // glowing seams and horns
    const glow = mix(shade(c, 0.6), 0xfff2a0, 0.5);
    g.moveTo(-0.8, -0.1).lineTo(-0.2, 0.05).lineTo(0.3, -0.15).stroke({ width: 0.2, color: glow, alpha: 0.3, cap: 'round' });
    g.moveTo(-0.8, -0.1).lineTo(-0.2, 0.05).lineTo(0.3, -0.15).stroke({ width: 0.07, color: 0xffffff, alpha: 0.9, cap: 'round' });
    for (const s of [-1, 1]) {
      g.poly([0.15, s * 0.55, 0.45, s * 0.6, 0.55, s * 1.1]).fill(0xf2ead2);
      g.poly([0.15, s * 0.55, 0.45, s * 0.6, 0.55, s * 1.1]).stroke({ width: 0.04, color: 0x5a4a30 });
    }
  }
  if (tier >= 4) {
    // crown on top of the head (drawn on the back, facing up the screen in top-down view)
    const cx = -0.05, cy = 0;
    g.poly([cx - 0.42, cy + 0.3, cx - 0.42, cy - 0.3, cx - 0.12, cy - 0.12, cx + 0.05, cy - 0.42, cx + 0.22, cy - 0.12, cx + 0.42, cy - 0.3, cx + 0.42, cy + 0.3]).fill(0xffc94a);
    g.poly([cx - 0.42, cy + 0.3, cx - 0.42, cy - 0.3, cx - 0.12, cy - 0.12, cx + 0.05, cy - 0.42, cx + 0.22, cy - 0.12, cx + 0.42, cy - 0.3, cx + 0.42, cy + 0.3]).stroke({ width: 0.05, color: 0x7a5410 });
    g.rect(cx - 0.42, cy + 0.12, 0.84, 0.12).fill({ color: 0xfff1b0, alpha: 0.7 });
    g.circle(cx + 0.05, cy + 0.0, 0.08).fill(0xff4a6a);
  }
  if (champion) {
    // spikes around the body
    for (let k = 0; k < 9; k++) {
      const a = Math.PI * 0.6 + (k / 8) * Math.PI * 0.8;
      for (const s of [-1, 1]) {
        const aa = s > 0 ? a : -a;
        const x0 = Math.cos(aa) * 0.88, y0 = Math.sin(aa) * 0.88;
        g.poly([x0 + Math.cos(aa + 1.4) * 0.12, y0 + Math.sin(aa + 1.4) * 0.12, x0 + Math.cos(aa) * 0.38, y0 + Math.sin(aa) * 0.38, x0 + Math.cos(aa - 1.4) * 0.12, y0 + Math.sin(aa - 1.4) * 0.12]).fill(0xe8e2d0);
      }
    }
  }
}

// ---------------------------------------------------------------- cache
export class MonsterArt {
  private cache = new Map<string, Texture>();
  private badges = new Map<string, Texture>();
  shadow: Texture;
  shield: Texture;
  ring: Texture;

  constructor(private renderer: PixiRenderer) {
    const sh = new Graphics();
    sh.ellipse(0, 0, 1, 0.45).fill({ color: 0x000000, alpha: 0.28 });
    sh.ellipse(0, 0, 0.7, 0.3).fill({ color: 0x000000, alpha: 0.18 });
    this.shadow = this.bake(sh);
    const bub = new Graphics();
    bub.circle(0, 0, 1.2).fill({ color: 0x9fd8ff, alpha: 0.12 });
    bub.circle(0, 0, 1.2).stroke({ width: 0.08, color: 0xcfeeff, alpha: 0.8 });
    bub.circle(0, 0, 1.05).stroke({ width: 0.04, color: 0x9fd8ff, alpha: 0.4 });
    bub.ellipse(-0.45, -0.55, 0.35, 0.18).fill({ color: 0xffffff, alpha: 0.5 });
    this.shield = this.bake(bub);
    const ring = new Graphics();
    ring.circle(0, 0, 1).stroke({ width: 0.12, color: 0xffffff, alpha: 0.9 });
    this.ring = this.bake(ring);
  }

  private bake(g: Graphics, pad = 1.7): Texture {
    // generateTexture ignores the target's own transform, so scale an inner container
    const c = new Container();
    const inner = new Container();
    const box = new Graphics();
    box.rect(-pad, -pad, pad * 2, pad * 2).fill({ color: 0x000000, alpha: 0.001 });
    inner.addChild(box, g);
    inner.scale.set(S);
    c.addChild(inner);
    const t = this.renderer.generateTexture({ target: c, resolution: 1, antialias: true });
    c.destroy({ children: true });
    return t;
  }

  /** Number of walk frames for a form. */
  frames(arch: Archetype): number {
    return arch === 'crawler' || arch === 'beetle' || arch === 'walker' || arch === 'swinger' ? 4 : 1;
  }

  body(arch: Archetype, color: number, tier: number, frame: number, variant: number, champion: boolean): Texture {
    const key = `${arch}|${color}|${tier}|${frame}|${variant}|${champion ? 1 : 0}`;
    let t = this.cache.get(key);
    if (t) return t;
    const g = new Graphics();
    FORMS[arch](g, color, frame % 4, variant);
    if (arch !== 'balloon') tierDecor(g, color, tier, champion);
    else if (tier >= 4) tierDecor(g, color, 4, champion);
    t = this.bake(g, arch === 'slinky' ? 2.2 : 1.7);
    this.cache.set(key, t);
    return t;
  }

  /** Element badge: the group colour with the chemical symbol. */
  badge(element: string, group: Group): Texture {
    let t = this.badges.get(element);
    if (t) return t;
    const col = GROUPS[group].color;
    const c = new Container();
    const g = new Graphics();
    g.roundRect(-0.62, -0.5, 1.24, 1.0, 0.18).fill(0x10131f);
    g.roundRect(-0.55, -0.43, 1.1, 0.86, 0.14).fill(col);
    g.roundRect(-0.55, -0.43, 1.1, 0.3, 0.12).fill({ color: 0xffffff, alpha: 0.3 });
    g.scale.set(S);
    const txt = new Text({ text: element, style: { fontFamily: 'Nunito, system-ui, sans-serif', fontSize: S * 0.62, fontWeight: '900', fill: 0x10131f } });
    txt.anchor.set(0.5);
    txt.position.set(0, S * 0.02);
    c.addChild(g, txt);
    t = this.renderer.generateTexture({ target: c, resolution: 1, antialias: true });
    c.destroy({ children: true });
    this.badges.set(element, t);
    return t;
  }
}
