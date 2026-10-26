import type { PieceColor } from '../sim/pieces';
import type { Suit } from '../sim/waves';
import type { Size } from '../balance';

export const PAL = {
  bg: 0x0d1220,
  board: 0x18203a,
  grid: 0x1f2846,
  macro: 0x2a3560,
  road: 0x5b4a3c,
  roadEdge: 0x7a6450,
  roadGlow: 0xf6d59a,
  ore: 0x6ff3ff,
  core: 0xffd36b,
  coreDeep: 0xc98b2a,
  rise: [0x1c2543, 0x212b4d, 0x263157],
  valley: [0x141a2f, 0x111628],
  good: 0x7dffb0,
  bad: 0xff5d6c,
  white: 0xffffff,
  seal: 0xff9a5c,
};

export const PIECE_HEX: Record<PieceColor, number> = { red: 0xff6b6b, gold: 0xffc94a, green: 0x4fe0a0, blue: 0x5aa8ff };
export const PIECE_CSS: Record<PieceColor, string> = { red: '#ff6b6b', gold: '#ffc94a', green: '#4fe0a0', blue: '#5aa8ff' };

const SUIT_RANGE: Record<Suit, [number, number]> = {
  hearts: [0xffa184, 0xe8432f],
  diamonds: [0xf2f27a, 0xa7c92b],
  clubs: [0x7cf0c0, 0x15a58f],
  spades: [0xa6b4ff, 0x7a3fe0],
};
const TIER: Record<Size, number> = { small: 0, medium: 0.4, large: 0.75, giant: 0.9, boss: 1 };

export function mix(a: number, b: number, t: number): number {
  const ar = (a >> 16) & 255, ag = (a >> 8) & 255, ab = a & 255;
  const br = (b >> 16) & 255, bg = (b >> 8) & 255, bb = b & 255;
  return (Math.round(ar + (br - ar) * t) << 16) | (Math.round(ag + (bg - ag) * t) << 8) | Math.round(ab + (bb - ab) * t);
}
export function suitColor(s: Suit, size: Size): number {
  const [l, d] = SUIT_RANGE[s];
  return mix(l, d, TIER[size]);
}
export function shade(c: number, k: number): number {
  return k >= 0 ? mix(c, 0xffffff, k) : mix(c, 0x000000, -k);
}
export const hexCss = (c: number) => '#' + c.toString(16).padStart(6, '0');
