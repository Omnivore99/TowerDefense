// Wave composition: Fibonacci counts, splits, bursts and the HP budget.
import {
  ABILITIES, ABILITY_LIST, ARCH, ARCHETYPES_BY_BOARD, BOARD_START_PIECES, BURSTS, DOMINANT_SHARE,
  H_B, HP_ALPHA, MODES, PIECES_PER_WAVE_CYCLE, SIZES, TENSION, WAVES_PER_BOARD, WAVE_LADDER, FIB,
  type Ability, type Archetype, type ModeId, type Size,
} from '../balance';
import { Rng, subSeed } from './rng';

export type Suit = 'hearts' | 'diamonds' | 'clubs' | 'spades';
export const SUITS: Suit[] = ['hearts', 'diamonds', 'clubs', 'spades'];
export const SUIT_SYMBOL: Record<Suit, string> = { hearts: '♥', diamonds: '♦', clubs: '♣', spades: '♠' };

export interface EnemySpec {
  size: Size;
  suit: Suit;
  arch: Archetype;
  ability: Ability | null;
  golden: boolean;
  boss?: boolean;
}

export interface WaveSpec {
  board: number;
  index: number; // 1-based
  count: number;
  split: [number, number, number];
  enemies: EnemySpec[];
  bursts: number[];
  budget: number;
  unitHp: number;
  dominant: Suit;
}

export function dominantSuit(seed: number, b: number): Suit {
  return new Rng(subSeed(seed, 606, b)).pick(SUITS);
}

export function tension(b: number, i: number): number {
  const W = WAVES_PER_BOARD[b - 1];
  if (W === 1) return TENSION.single[b - 1] ?? 0.9;
  let t = TENSION.start + ((TENSION.end - TENSION.start) * (i - 1)) / (W - 1);
  if (i !== W && TENSION.spikes.includes(i)) t *= TENSION.spike;
  else if (i !== W && TENSION.spikes.includes(i - 1)) t *= TENSION.exhale;
  return t;
}

export function waveCount(b: number, i: number): { count: number; split: [number, number, number] } {
  const rung = Math.min(WAVE_LADDER.length - 1, Math.floor(b / 2) + Math.floor((i - 1) / 3));
  const count = WAVE_LADDER[rung];
  const k = FIB.indexOf(count, 2);
  return { count, split: [FIB[k - 1], FIB[k - 3], FIB[k - 4]] };
}

export function hpBudget(b: number, i: number, mode: ModeId): number {
  const S = BOARD_START_PIECES[b - 1];
  return (H_B[b - 1] * Math.pow(S + (i - 1) * PIECES_PER_WAVE_CYCLE, HP_ALPHA)) / Math.pow(5, HP_ALPHA - 1) * tension(b, i) * MODES[mode].hp;
}

export function makeWave(seed: number, b: number, i: number, mode: ModeId): WaveSpec {
  const rng = new Rng(subSeed(seed, 505, b, i));
  const { count, split } = waveCount(b, i);
  const dominant = dominantSuit(seed, b);
  const sizes: Size[] = [];
  for (let k = 0; k < split[0]; k++) sizes.push('small');
  for (let k = 0; k < split[1]; k++) sizes.push('medium');
  for (let k = 0; k < split[2]; k++) sizes.push('large');
  const archs = ARCHETYPES_BY_BOARD[b - 1];
  const abilityChance = b >= ABILITIES.fromBoard ? Math.min(ABILITIES.max, ABILITIES.perBoard * (b - 2)) : 0;
  const enemies: EnemySpec[] = sizes.map((size) => {
    const suit = rng.chance(DOMINANT_SHARE) ? dominant : rng.pick(SUITS);
    const arch = rng.pick(archs);
    const ability = rng.chance(abilityChance) ? rng.pick(ABILITY_LIST) : null;
    const golden = rng.chance(ABILITIES.goldenChance);
    return { size, suit, arch, ability, golden };
  });
  // Balloons replace some smalls, Giant Walkers replace some larges
  if (b >= ARCH.balloonFromBoard) {
    let n = Math.floor(count / ARCH.balloonEvery);
    for (const e of enemies) if (n > 0 && e.size === 'small' && e.arch !== 'balloon') { e.arch = 'balloon'; n--; }
  }
  if (b >= ARCH.walkerFromBoard) {
    let n = Math.floor(count / ARCH.walkerEvery);
    for (const e of enemies) if (n > 0 && e.size === 'large') { e.size = 'giant'; e.arch = 'walker'; n--; }
  }
  rng.shuffle(enemies);
  // gentle ordering: larger enemies drift toward later bursts
  enemies.sort((a, b2) => SIZES[a.size].hp - SIZES[b2.size].hp + (rng.next() - 0.5) * 1.6);
  if (b === 7 && i === WAVES_PER_BOARD[6]) enemies.push({ size: 'boss', suit: dominant, arch: 'nautilus', ability: null, golden: false, boss: true });
  const bursts: number[] = [];
  let left = enemies.length;
  for (let k = 0; left > 0; k++) {
    const n = Math.min(left, BURSTS[Math.min(k, BURSTS.length - 1)]);
    bursts.push(n);
    left -= n;
  }
  const budget = hpBudget(b, i, mode);
  const sumHp = enemies.reduce((s, e) => s + SIZES[e.size].hp, 0);
  return { board: b, index: i, count, split, enemies, bursts, budget, unitHp: budget / sumHp, dominant };
}
