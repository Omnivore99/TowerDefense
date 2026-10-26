// Every tunable number in Satisfying TD lives here.
// Values come from the design balance simulation (see tower-defense/sim/) and the
// bot harness (npm run bots). Change numbers here, never in game code.

export const PHI = (1 + Math.sqrt(5)) / 2; // 1.618
export const SQRT_PHI = Math.sqrt(PHI); // 1.272
export const INV_PHI = 1 / PHI; // 0.618
export const FIB = [1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144];
/** Animation timings on the phi ladder (seconds). */
export const T = { xs: 0.146, s: 0.236, m: 0.382, l: 0.618, xl: 1.0, xxl: 1.618 };

export const SIM_HZ = 60;

// ---------------------------------------------------------------- run structure
export const BOARDS = 7;
export const WAVES_PER_BOARD = [1, 1, 2, 3, 5, 8, 13];
export const BASE_INTEGRITY = 21;
export const BOARD_START_PIECES = [5, 5, 8, 8, 13, 13, 13];
export const CALM_PIECES = 2;
export const WAVE_PIECE_INTERVAL = 4; // seconds per piece during waves
export const EARLY_CALL_WINDOW = 10; // seconds
export const EARLY_CALL_BONUS = 3; // essence
export const MODES = {
  relaxed: { name: 'Relaxed', hp: INV_PHI },
  normal: { name: 'Normal', hp: 1 },
  golden: { name: 'Golden', hp: PHI },
} as const;
export type ModeId = keyof typeof MODES;

// ---------------------------------------------------------------- map
export const MACRO_W = 13;
export const MACRO_H = 8;
export const MACRO = 8; // cells per macro square
export const GRID_W = MACRO_W * MACRO; // 104
export const GRID_H = MACRO_H * MACRO; // 64
export const CORE_MACRO = { x: 8, y: 5 };
export const CORE_RADIUS = 3; // cells blocked around the core centre
export const INGRESS_BY_BOARD = [1, 1, 1, 2, 2, 3, 3];
export const ROAD = {
  spiralK: 1.6, // weight of distance to the guide spiral
  noise: 0.9,
  spiralA: 0.42, // r(theta) = a * phi^(2 theta / pi), macro units
  forkP: 0.12,
  forkFromBoard: 3,
  minLenBase: 125, // L_min = 125 - 6 b (+-10)
  minLenPerBoard: 6,
  minLenJitter: 10,
  attempts: 60,
};
export const REVEAL = { seconds: 4, pauses: 2, sealsPerPause: 2 };
export const TERRAIN = { featuresPerMacro: [0, 0, 0, 1, 1, 2], blobSizes: [2, 3, 5], rise: [1, 3], valley: [-2, -1] };
export const ORE = { min: 3, max: 5, size: 3 };

// ---------------------------------------------------------------- pieces
export const PIECE_WEIGHTS: Record<string, number> = { I: 1.0, O: 1.0, T: 1.1, S: 0.55, Z: 0.55, J: 0.55, L: 0.55 };
export const CAP_CHANCE = 1 / 5;
export const GLYPH_ODDS = { golden: 1 / 89, rare: 1 / 21, common: 1 / 8 };
export const MAY_SLOTS = 3;
export const MUST_VISIBLE = 3;
export const MAX_GROUND_PIECES = 8;
export const MAX_STORIES = 5;
export const ROAD_PIECES_PER_MACRO = 1;

// ---------------------------------------------------------------- towers
export type TowerType =
  | 'Gun' | 'Machine Gun' | 'Rifle' | 'Bomb' | 'Missile' | 'Laser' | 'Pulsar'
  | 'Lightning' | 'E-Field' | 'Freezer' | 'Flamer' | 'Acid' | 'Virus';

export interface TowerDef {
  dps: number; range: number; interval: number;
  area: number; // splash/aura radius in cells (0 = single)
  maxTargets: number;
  kind: 'bullet' | 'hitscan' | 'lob' | 'homing' | 'beam' | 'pierce' | 'bolt' | 'aura' | 'cone' | 'puddle' | 'virus';
  air: boolean; // can hit Balloons
  energy: boolean; // boosted by Power Station
  single: boolean; // single-target shot (Swingers can parry)
  note: string;
}

export const TOWERS: Record<TowerType, TowerDef> = {
  'Gun':         { dps: 10,  range: 16, interval: 0.5,  area: 0,   maxTargets: 1, kind: 'bullet',  air: false, energy: false, single: true,  note: 'generalist' },
  'Machine Gun': { dps: 12,  range: 15, interval: 0.146, area: 0,  maxTargets: 1, kind: 'bullet',  air: false, energy: false, single: true,  note: 'fast small bullets' },
  'Rifle':       { dps: 14,  range: 26, interval: 1.272, area: 0,  maxTargets: 1, kind: 'hitscan', air: true,  energy: false, single: true,  note: 'slow, ignores shields' },
  'Bomb':        { dps: 8,   range: 22, interval: 1.618, area: 1.5, maxTargets: 5, kind: 'lob',    air: false, energy: false, single: false, note: 'lobbed 3-cell splash' },
  'Missile':     { dps: 7,   range: 32, interval: 2.0,  area: 1.5, maxTargets: 5, kind: 'homing',  air: true,  energy: false, single: false, note: 'homing, hunts Balloons and Giants' },
  'Laser':       { dps: 15,  range: 16, interval: 0.1,  area: 0,   maxTargets: 1, kind: 'beam',    air: false, energy: true,  single: false, note: 'beam ramps up on one target' },
  'Pulsar':      { dps: 10,  range: 24, interval: 0.786, area: 0,  maxTargets: 99, kind: 'pierce', air: true,  energy: true,  single: false, note: 'pierces in a line' },
  'Lightning':   { dps: 6.5, range: 20, interval: 0.618, area: 2,  maxTargets: 3, kind: 'bolt',    air: true,  energy: true,  single: false, note: 'random bolts, can miss' },
  'E-Field':     { dps: 4.5, range: 11, interval: 0.25, area: 11,  maxTargets: 8, kind: 'aura',    air: false, energy: true,  single: false, note: 'constant aura' },
  'Freezer':     { dps: 3,   range: 11, interval: 0.25, area: 11,  maxTargets: 8, kind: 'aura',    air: false, energy: false, single: false, note: 'slows to 60% speed' },
  'Flamer':      { dps: 11,  range: 10, interval: 0.1,  area: 0,   maxTargets: 4, kind: 'cone',    air: false, energy: false, single: false, note: 'cone, burn over time' },
  'Acid':        { dps: 7,   range: 10, interval: 1.0,  area: 2,   maxTargets: 5, kind: 'puddle',  air: false, energy: false, single: false, note: 'puddles linger 3 s' },
  'Virus':       { dps: 7.5, range: 12, interval: 1.0,  area: 0,   maxTargets: 4, kind: 'virus',   air: false, energy: false, single: false, note: 'DoT that spreads on death' },
};
export const TOWER_TYPES = Object.keys(TOWERS) as TowerType[];

export const COMBAT = {
  bulletSpeed: 34, // cells/s
  missileSpeed: 18,
  lobTime: 0.618,
  laserRamp: [0.6, 1.6, 3], // min mult, max mult, seconds to max
  freezerSlow: 0.6,
  flamerCone: 0.7, // radians half-angle
  flamerBurn: 0.35, // share of flamer damage dealt as burn over 2 s
  acidLinger: 3,
  virusDuration: 4,
  lightningMiss: 0.2,
  mineBurst: 34, // minimum mine damage
  mineBurstUnit: 0.34, // or this share of unit HP if larger
  mineRadius: 1,
  barrierUnits: 21, // barrier HP in units of enemy HP
  barrierChew: 1.0, // units of barrier HP chewed per second by a small enemy
  activateTime: T.l,
};

export const MASS_EXP = 0.9;
export const TRAITS = { Hook: 0.08, Block: 0.08, Bar: 0.08, Tee: 0.05, Skew: 0.08 };
export const STORY = { damage: SQRT_PHI, range: 0.15 };
export const RISE_RANGE = 1; // +cells per terrain level
export const SHAPE = {
  hole: -0.1,
  goldenMin: 1.55, goldenMax: 1.7, golden: 0.1,
  mirror: 0.15,
  rotational: 0.15,
  perfect: 0.25,
  surfaceMax: 0.1,
  spireCritEvery: 13,
  spireCrit: PHI * PHI,
};
export const GLYPHS = {
  range: 0.1, damage: 0.15, rate: 0.15, pierce: 1,
  critChance: 0.1, critMult: 2, slowOnHit: 0.8, slowTime: 1, chain: 1,
};
export const RESONANCE = { burnSplash: 0.3, ricochet: 2, blueSplash: 1.5, poisonSpread: 0.5 };

// ---------------------------------------------------------------- enemies
export type Size = 'small' | 'medium' | 'large' | 'giant' | 'boss';
export const SIZES: Record<Size, { hp: number; speed: number; leak: number; essence: number; radius: number }> = {
  small:  { hp: 1,          speed: 3.2,               leak: 1, essence: 1, radius: 0.55 },
  medium: { hp: PHI,        speed: 3.2 / SQRT_PHI,    leak: 2, essence: 2, radius: 0.7 },
  large:  { hp: PHI ** 2,   speed: 3.2 / PHI,         leak: 3, essence: 3, radius: 0.85 },
  giant:  { hp: PHI ** 4,   speed: 1.2,               leak: 5, essence: 5, radius: 1.3 },
  boss:   { hp: PHI ** 5,   speed: 1.0,               leak: 8, essence: 13, radius: 1.6 },
};
export const SUIT_MULT = { strong: SQRT_PHI, weak: 1 / SQRT_PHI };

export type Archetype = 'hopper' | 'slinky' | 'roller' | 'swinger' | 'tumbler' | 'nautilus' | 'balloon' | 'walker';
/** Road archetypes unlocked per board (cumulative). */
export const ARCHETYPES_BY_BOARD: Archetype[][] = [
  ['hopper'],
  ['hopper', 'slinky', 'roller'],
  ['hopper', 'slinky', 'roller', 'swinger', 'tumbler'],
  ['hopper', 'slinky', 'roller', 'swinger', 'tumbler', 'nautilus'],
  ['hopper', 'slinky', 'roller', 'swinger', 'tumbler', 'nautilus'],
  ['hopper', 'slinky', 'roller', 'swinger', 'tumbler', 'nautilus'],
  ['hopper', 'slinky', 'roller', 'swinger', 'tumbler', 'nautilus'],
];
export const ARCH = {
  hopperCycle: 0.618, hopperAir: 0.45,
  slinkyCycle: 1.0, slinkySplash: 1.5,
  rollerSpeed: 1.38, rollerBrake: 0.5,
  swingerParry: 1 / 5, swingerWeak: 1.2,
  tumblerFlip: 1.2,
  nautilusSpeed: 0.8, nautilusFront: 0.5,
  balloonSpeed: 0.7, balloonFromBoard: 4, balloonEvery: 13,
  walkerFromBoard: 5, walkerEvery: 21,
};

export type Ability =
  | 'shielded' | 'swift' | 'blink' | 'splitter' | 'bearer' | 'grower'
  | 'regen' | 'phase' | 'herald' | 'hoarder';
export const ABILITY_LIST: Ability[] = ['shielded', 'swift', 'blink', 'splitter', 'bearer', 'grower', 'regen', 'phase', 'herald', 'hoarder'];
export const ABILITIES = {
  fromBoard: 3, perBoard: 0.08, max: 0.4, goldenChance: 1 / 89,
  shield: 0.38, swift: SQRT_PHI, blinkCells: 8, blinkEvery: 5,
  splitHp: 1 / (PHI * PHI), splitGenerations: 4,
  bearerShield: 0.2, bearerEvery: 3, bearerRadius: 3,
  growerHp: PHI * PHI, growerLeak: 2,
  regen: 0.02, phaseEvery: 3, phaseTime: T.l,
  heraldSpeed: 1.2, heraldRadius: 3,
  hoarderSpeed: 1.3, hoarderEssence: 8,
};

// ---------------------------------------------------------------- waves
export const WAVE_LADDER = [5, 8, 13, 21, 34, 55];
export const BURSTS = [1, 1, 2, 3, 5, 8, 13, 21, 34];
export const BURST_GAP = 2.5;
export const PIECES_PER_WAVE_CYCLE = 9.5;
export const HP_ALPHA = 1.3;
/** H_b per board on Normal. Recalibrated with the bot harness (see README). */
export const H_B = [246, 500, 260, 225, 235, 140, 142];
export const TENSION = { start: 0.72, end: 1.0, spike: 1.12, exhale: 0.9, spikes: [2, 3, 5, 8], single: [0.75, 0.9] };
export const DOMINANT_SHARE = 0.5;
export const BOSS_SHED = [1, 1, 2, 3, 5];
export const TUTORIAL_SAFE_SECONDS = 20;

// ---------------------------------------------------------------- base
export const BASE_SQUARES = [
  // Fibonacci squares tiling the 13 x 8 golden rectangle, in spiral unlock order (core in the 1x1s).
  { id: 0, size: 1, x: 8, y: 5 },
  { id: 1, size: 1, x: 9, y: 5 },
  { id: 2, size: 2, x: 8, y: 6 },
  { id: 3, size: 3, x: 10, y: 5 },
  { id: 4, size: 5, x: 8, y: 0 },
  { id: 5, size: 8, x: 0, y: 0 },
];
/** Squares unlocked at the start, then one more after clearing boards 1..5. */
export const BASE_START_SQUARES = 2;
export const HARMONY = 1 / PHI ** 3; // +23.6%
export const GOLDEN_BASE_DAMAGE = 0.08;

export type BuildingId =
  | 'blastDoor' | 'beacon' | 'powerStation' | 'recycler' | 'research'
  | 'shapeFactory' | 'harvesterHub' | 'factory' | 'missileBattery' | 'smite';
export const BUILDINGS: Record<BuildingId, { name: string; size: number; cost: number; effect: string }> = {
  blastDoor:      { name: 'Blast Door',      size: 1, cost: 5,  effect: '+5 base buffer per board' },
  beacon:         { name: 'Beacon',          size: 1, cost: 5,  effect: '+1 MAY USE slot' },
  powerStation:   { name: 'Power Station',   size: 2, cost: 8,  effect: '+10% damage for Laser, Pulsar, Lightning, E-Field' },
  recycler:       { name: 'Recycler',        size: 2, cost: 8,  effect: 'Turn any piece into 2 Essence' },
  research:       { name: 'Research Tower',  size: 3, cost: 13, effect: 'Every 3rd board, a rare-glyph piece' },
  shapeFactory:   { name: 'Shape Factory',   size: 3, cost: 21, effect: 'Once per wave, choose the next piece family' },
  harvesterHub:   { name: 'Harvester Hub',   size: 3, cost: 13, effect: '+50% ore from Harvesters' },
  factory:        { name: 'Factory',         size: 5, cost: 34, effect: 'Sends a small tank down the road every 13 s' },
  missileBattery: { name: 'Missile Battery', size: 5, cost: 34, effect: 'Base Missile tower, 40-cell range from the core' },
  smite:          { name: 'Smite Tower',     size: 8, cost: 55, effect: 'Orbital strike, recharges over 3 waves' },
};
export const BUILDING_FX = {
  blastDoor: 5, powerStation: 0.1, recycler: 2, harvesterHub: 0.5,
  factoryEvery: 13, tankDps: 12, tankRange: 6, tankHpUnits: 8, tankSpeed: 2.5,
  batteryRange: 40, smiteWaves: 3, smiteRadius: 6, smiteUnits: 8,
};
export const ESSENCE = { oreRate: 1 };

// ---------------------------------------------------------------- feedback
export const COMBO = { window: T.xxl, steps: [3, 5, 8, 13, 21] };
