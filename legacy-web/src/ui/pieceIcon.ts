// Small canvas drawings of pieces for the queues.
import { PIECE_CSS } from '../render/palette';
import { type Piece, familyOf, isCap, orientCells } from '../sim/pieces';

const GLYPH_SYM: Record<string, string> = {
  range: '◎', damage: '✦', rate: '»', pierce: '➶', chain: '⚡', crit: '✸', slow: '❄', essence: '◆',
};
const FAMILY_SYM: Record<string, string> = { Hook: 'J', Block: 'O', Bar: 'I', Tee: 'T', Skew: 'S' };

export function drawPieceIcon(cv: HTMLCanvasElement, p: Piece | null, locked = false) {
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  const size = cv.clientWidth || 56;
  if (cv.width !== size * dpr) { cv.width = size * dpr; cv.height = size * dpr; }
  const ctx = cv.getContext('2d')!;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, size, size);
  if (!p) return;
  const cells = orientCells(p.kind, { rot: 0, mirror: false });
  const w = Math.max(...cells.map((c) => c[0])) + 1, h = Math.max(...cells.map((c) => c[1])) + 1;
  const u = Math.min((size - 14) / 4, (size - 14) / Math.max(w, h));
  const ox = (size - w * u) / 2, oy = (size - h * u) / 2 + 2;
  const col = p.golden ? '#ffe08a' : PIECE_CSS[p.color];
  ctx.globalAlpha = locked ? 0.35 : 1;
  for (const [x, y] of cells) {
    ctx.fillStyle = shadeCss(col, -0.45);
    ctx.fillRect(ox + x * u, oy + y * u + u * 0.18, u, u);
  }
  for (const [x, y] of cells) {
    ctx.fillStyle = col;
    ctx.fillRect(ox + x * u, oy + y * u, u, u);
    ctx.fillStyle = 'rgba(255,255,255,0.28)';
    ctx.fillRect(ox + x * u + u * 0.12, oy + y * u + u * 0.1, u * 0.76, u * 0.14);
    ctx.strokeStyle = shadeCss(col, -0.55);
    ctx.lineWidth = 1;
    ctx.strokeRect(ox + x * u + 0.5, oy + y * u + 0.5, u - 1, u - 1);
  }
  ctx.font = '700 10px Nunito, system-ui, sans-serif';
  ctx.textBaseline = 'top';
  ctx.fillStyle = 'rgba(220,228,255,0.75)';
  const fam = familyOf(p);
  ctx.fillText(p.golden ? '★' : isCap(p.kind) ? 'cap' : `${p.kind}`, 4, 3);
  if (p.glyph) {
    ctx.font = '700 13px system-ui, sans-serif';
    ctx.fillStyle = '#fff';
    ctx.textAlign = 'right';
    ctx.fillText(GLYPH_SYM[p.glyph], size - 4, 2);
    ctx.textAlign = 'left';
  }
  ctx.globalAlpha = 1;
}

export function shadeCss(hex: string, k: number): string {
  const n = parseInt(hex.slice(1), 16);
  let r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255;
  const t = k >= 0 ? 255 : 0, a = Math.abs(k);
  r = Math.round(r + (t - r) * a); g = Math.round(g + (t - g) * a); b = Math.round(b + (t - b) * a);
  return `rgb(${r},${g},${b})`;
}
export { GLYPH_SYM };
