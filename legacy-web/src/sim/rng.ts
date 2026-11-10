// Deterministic seeded RNG (mulberry32) plus helpers.

export class Rng {
  private s: number;
  constructor(seed: number) {
    this.s = seed >>> 0;
  }
  next(): number {
    let t = (this.s = (this.s + 0x6d2b79f5) >>> 0);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }
  range(a: number, b: number): number {
    return a + (b - a) * this.next();
  }
  int(a: number, b: number): number {
    // inclusive
    return a + Math.floor(this.next() * (b - a + 1));
  }
  chance(p: number): boolean {
    return this.next() < p;
  }
  pick<T>(arr: readonly T[]): T {
    return arr[Math.floor(this.next() * arr.length)];
  }
  weighted<T extends string>(w: Record<T, number>): T {
    const keys = Object.keys(w) as T[];
    let total = 0;
    for (const k of keys) total += w[k];
    let r = this.next() * total;
    for (const k of keys) {
      r -= w[k];
      if (r <= 0) return k;
    }
    return keys[keys.length - 1];
  }
  shuffle<T>(arr: T[]): T[] {
    for (let i = arr.length - 1; i > 0; i--) {
      const j = Math.floor(this.next() * (i + 1));
      [arr[i], arr[j]] = [arr[j], arr[i]];
    }
    return arr;
  }
}

/** Mix a seed with stream labels so map, pieces and waves are independent streams. */
export function subSeed(seed: number, ...parts: number[]): number {
  let h = seed >>> 0 ^ 0x9e3779b9;
  for (const p of parts) {
    h = Math.imul(h ^ (p + 0x7f4a7c15), 0x85ebca6b) >>> 0;
    h ^= h >>> 13;
    h = Math.imul(h, 0xc2b2ae35) >>> 0;
    h ^= h >>> 16;
  }
  return h >>> 0;
}

export function randomSeed(): number {
  return (Math.random() * 0xffffffff) >>> 0;
}
