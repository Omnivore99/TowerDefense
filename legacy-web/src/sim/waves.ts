// Wave composition: Fibonacci counts, packs of one form/element/tier, the HP budget and champions.
import {
  ABILITIES, ARCH, ARCHETYPES_BY_BOARD, BOARD_START_PIECES, BURSTS, CHAMPION, DOMINANT_SHARE, GROUPS,
  H_B, HP_ALPHA, MITES_PER_SMALL, MITE_FORMS, MITE_SHARE, MODES, PIECES_PER_WAVE_CYCLE, SIZES, TENSION,
  TIER_HP, TIER_ODDS, WAVES_PER_BOARD, WAVE_LADDER, FIB,
  type Ability, type Archetype, type Group, type ModeId, type Size,
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
  element: string; // chemical symbol
  group: Group;
  tier: number; // 1..4
  golden: boolean;
  boss?: boolean;
  champion?: boolean;
  pack: number;
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

/** Element groups a pack may carry on board b. */
export function groupsFor(b: number): Ability[] {
  return (Object.keys(GROUPS) as Group[]).filter((g) => g !== 'nonmetal' && GROUPS[g].fromBoard <= b) as Ability[];
}

/** Does this wave bring a champion? */
export function hasChampion(b: number, i: number): boolean {
  if (b < CHAMPION.fromBoard) return false;
  const W = WAVES_PER_BOARD[b - 1];
  return (CHAMPION.waves[b - 1] ?? []).some((w) => (w === 0 ? W : w) === i);
}

/** HP weight of one monster inside the wave budget. */
export function hpWeight(e: { size: Size; tier: number; ability: Ability | null }): number {
  return SIZES[e.size].hp * TIER_HP[e.tier - 1] * (e.ability === 'post' ? ABILITIES.growerHp : 1);
}

export function makeWave(seed: number, b: number, i: number, mode: ModeId): WaveSpec {
  const rng = new Rng(subSeed(seed, 505, b, i));
  const { count, split } = waveCount(b, i);
  const dominant = dominantSuit(seed, b);
  const sizes: Size[] = [];
  for (let k = 0; k < split[0]; k++) sizes.push('small');
  for (let k = 0; k < split[1]; k++) sizes.push('medium');
  for (let k = 0; k < split[2]; k++) sizes.push('large');
  // larger monsters drift toward later packs
  rng.shuffle(sizes);
  sizes.sort((a, c) => SIZES[a].hp - SIZES[c].hp + (rng.next() - 0.5) * 1.6);
  // split into packs on the Fibonacci burst ladder
  const packs: Size[][] = [];
  let left = sizes.length, at = 0;
  for (let k = 0; left > 0; k++) {
    const n = Math.min(left, BURSTS[Math.min(k, BURSTS.length - 1)]);
    packs.push(sizes.slice(at, at + n));
    at += n;
    left -= n;
  }
  const archs = ARCHETYPES_BY_BOARD[b - 1];
  const groups = groupsFor(b);
  const odds = TIER_ODDS[b - 1];
  const enemies: EnemySpec[] = [];
  packs.forEach((pack, pi) => {
    const allSmall = pack.every((s) => s === 'small');
    const mites = allSmall && pack.length >= 2 && rng.chance(MITE_SHARE[b - 1]);
    const forms = mites ? MITE_FORMS.filter((f) => archs.includes(f)) : archs;
    const arch = rng.pick(forms.length ? forms : archs);
    const ability = groups.length && rng.chance(ABILITIES.chanceByBoard[b - 1]) ? rng.pick(groups) : null;
    const group: Group = ability ?? 'nonmetal';
    const element = rng.pick(GROUPS[group].symbols);
    let r = rng.next(), tier = 1;
    for (let t = 0; t < 4; t++) { r -= odds[t]; if (r <= 0) { tier = t + 1; break; } }
    const suit = rng.chance(DOMINANT_SHARE) ? dominant : rng.pick(SUITS);
    for (const size of pack) {
      const n = mites ? MITES_PER_SMALL : 1;
      for (let k = 0; k < n; k++)
        enemies.push({ size: mites ? 'mite' : size, suit, arch, ability, element, group, tier, golden: rng.chance(ABILITIES.goldenChance), pack: pi });
    }
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
  const last = packs.length;
  if (hasChampion(b, i)) {
    const ability = groups.length ? rng.pick(groups) : null;
    const group: Group = ability ?? 'nonmetal';
    enemies.push({
      size: 'champion', suit: dominant, arch: rng.pick(archs.filter((a) => a !== 'crawler')), ability, element: rng.pick(GROUPS[group].symbols), group,
      tier: 4, golden: false, champion: true, pack: last,
    });
  }
  if (b === 7 && i === WAVES_PER_BOARD[6])
    enemies.push({ size: 'boss', suit: dominant, arch: 'nautilus', ability: null, element: 'Og', group: 'nonmetal', tier: 4, golden: false, boss: true, pack: last + 1 });
  const bursts: number[] = [];
  for (const e of enemies) {
    if (bursts.length <= e.pack) bursts.push(0);
    bursts[e.pack]++;
  }
  const budget = hpBudget(b, i, mode);
  const sumHp = enemies.reduce((s, e) => s + hpWeight(e), 0);
  return { board: b, index: i, count, split, enemies, bursts: bursts.filter((n) => n > 0), budget, unitHp: budget / sumHp, dominant };
}
