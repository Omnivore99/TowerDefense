// The persistent golden-spiral base.
import { BASE_SQUARES, BASE_START_SQUARES, BUILDINGS, HARMONY, type BuildingId } from '../balance';

export interface BaseState {
  unlocked: number; // number of squares unlocked, in spiral order
  buildings: (BuildingId | null)[]; // per square
  essence: number;
  ore: number;
  smiteCharge: number; // waves since last smite
}

export function newBase(): BaseState {
  return { unlocked: BASE_START_SQUARES, buildings: BASE_SQUARES.map(() => null), essence: 0, ore: 0, smiteCharge: 99 };
}

export function hasBuilding(b: BaseState, id: BuildingId): boolean {
  return b.buildings.includes(id);
}

/** Effect multiplier for a building: 0 if absent, 1 normally, 1.236 with Harmony (exact fit). */
export function buildingMult(b: BaseState, id: BuildingId): number {
  const i = b.buildings.indexOf(id);
  if (i < 0) return 0;
  return BASE_SQUARES[i].size === BUILDINGS[id].size ? 1 + HARMONY : 1;
}

export function isHarmony(b: BaseState, square: number): boolean {
  const id = b.buildings[square];
  return !!id && BASE_SQUARES[square].size === BUILDINGS[id].size;
}

export function goldenBase(b: BaseState): boolean {
  return b.buildings.every((x) => x !== null);
}

export function canBuild(b: BaseState, square: number, id: BuildingId): string | null {
  if (square >= b.unlocked) return 'Square locked';
  if (b.buildings[square]) return 'Square taken';
  if (hasBuilding(b, id)) return 'Already built';
  if (BASE_SQUARES[square].size < BUILDINGS[id].size) return 'Square too small';
  if (b.essence < BUILDINGS[id].cost) return 'Not enough Essence';
  return null;
}
