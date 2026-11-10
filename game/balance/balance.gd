class_name Bal
extends RefCounted
## Every tunable number in Satisfying TD v2.0 lives here.
## Ported from v1.1 src/balance.ts. Gameplay code never holds magic numbers.
## [Default] = a design choice Marco may change. [Tune] = settled by the bot harness.

const PHI := 1.6180339887498949
const SQRT_PHI := 1.272019649514069
const INV_PHI := 0.6180339887498949
const FIB: Array[int] = [1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144]
## Animation timings on the phi ladder (seconds).
const T_XS := 0.146
const T_S := 0.236
const T_M := 0.382
const T_L := 0.618
const T_XL := 1.0
const T_XXL := 1.618

const SIM_HZ := 60
const DT := 1.0 / 60.0

# ---------------------------------------------------------------- run structure
const BOARDS := 7
const WAVES_PER_BOARD: Array[int] = [1, 1, 2, 3, 5, 8, 13]
const BASE_INTEGRITY := 21
const BOARD_START_PIECES: Array[int] = [5, 5, 8, 8, 13, 13, 13]
const CALM_PIECES := 2
const WAVE_PIECE_INTERVAL := 4.0
const EARLY_CALL_WINDOW := 10.0
const EARLY_CALL_BONUS := 3
const MODES := {
	"relaxed": {"name": "Relaxed", "hp": 0.6180339887498949},
	"normal": {"name": "Normal", "hp": 1.0},
	"golden": {"name": "Golden", "hp": 1.6180339887498949},
}

# ---------------------------------------------------------------- map
const MACRO_W := 21
const MACRO_H := 13
const MACRO := 8
const GRID_W := 168
const GRID_H := 104
const CORE_MACRO := Vector2i(13, 8)
const CORE_RADIUS := 3
const JOIN_K := 4.0
const BLOCKED_EDGE_COST := 400.0
const ROAD := {
	"spiralK": 1.6, "noise": 0.9, "spiralA": 0.42,
	"minLenBase": 150, "minLenJitter": 10, "attempts": 60,
}
const REVEAL_SECONDS := 3.0
const REVEAL_STRIKE_SECONDS := 1.8
const TERRAIN := {"featuresPerMacro": [0, 0, 0, 1, 1, 2], "blobSizes": [2, 3, 5], "rise": [1, 3], "valley": [-2, -1]}
const ORE := {"min": 4, "max": 5, "size": 3, "perNewRoad": 2}

# ---------------------------------------------------------------- pieces
const PIECE_WEIGHTS := {"I": 1.0, "O": 1.0, "T": 1.1, "S": 0.55, "Z": 0.55, "J": 0.55, "L": 0.55}
const CAP_CHANCE := 0.2
const GLYPH_GOLDEN := 1.0 / 89.0
const GLYPH_RARE := 1.0 / 21.0
const GLYPH_COMMON := 1.0 / 8.0
const MAY_SLOTS := 3
const MUST_VISIBLE := 3
const MAX_GROUND_PIECES := 8
const MAX_STORIES := 5

# ---------------------------------------------------------------- towers
const TOWER_TYPES: Array[String] = ["Gun", "Machine Gun", "Rifle", "Bomb", "Missile", "Laser", "Pulsar", "Lightning", "E-Field", "Freezer", "Flamer", "Acid", "Virus"]
const TOWERS := {
	"Gun":         {"dps": 10.0, "range": 16.0, "interval": 0.5,   "area": 0.0, "maxTargets": 1,  "kind": "bullet",  "air": false, "energy": false, "single": true,  "note": "generalist"},
	"Machine Gun": {"dps": 12.0, "range": 15.0, "interval": 0.146, "area": 0.0, "maxTargets": 1,  "kind": "bullet",  "air": false, "energy": false, "single": true,  "note": "fast small bullets"},
	"Rifle":       {"dps": 14.0, "range": 26.0, "interval": 1.272, "area": 0.0, "maxTargets": 1,  "kind": "hitscan", "air": true,  "energy": false, "single": true,  "note": "slow, ignores shields"},
	"Bomb":        {"dps": 8.0,  "range": 22.0, "interval": 1.618, "area": 1.5, "maxTargets": 5,  "kind": "lob",     "air": false, "energy": false, "single": false, "note": "lobbed 3-cell splash"},
	"Missile":     {"dps": 7.0,  "range": 32.0, "interval": 2.0,   "area": 1.5, "maxTargets": 5,  "kind": "homing",  "air": true,  "energy": false, "single": false, "note": "homing, hunts air"},
	"Laser":       {"dps": 15.0, "range": 16.0, "interval": 0.1,   "area": 0.0, "maxTargets": 1,  "kind": "beam",    "air": false, "energy": true,  "single": false, "note": "beam ramps up on one target"},
	"Pulsar":      {"dps": 10.0, "range": 24.0, "interval": 0.786, "area": 0.0, "maxTargets": 99, "kind": "pierce",  "air": true,  "energy": true,  "single": false, "note": "pierces in a line"},
	"Lightning":   {"dps": 6.5,  "range": 20.0, "interval": 0.618, "area": 2.0, "maxTargets": 3,  "kind": "bolt",    "air": true,  "energy": true,  "single": false, "note": "random bolts, can miss"},
	"E-Field":     {"dps": 4.5,  "range": 11.0, "interval": 0.25,  "area": 11.0, "maxTargets": 8, "kind": "aura",    "air": false, "energy": true,  "single": false, "note": "constant aura"},
	"Freezer":     {"dps": 3.0,  "range": 11.0, "interval": 0.25,  "area": 11.0, "maxTargets": 8, "kind": "aura",    "air": false, "energy": false, "single": false, "note": "slows to 60% speed"},
	"Flamer":      {"dps": 11.0, "range": 10.0, "interval": 0.1,   "area": 0.0, "maxTargets": 4,  "kind": "cone",    "air": false, "energy": false, "single": false, "note": "cone, burn over time"},
	"Acid":        {"dps": 7.0,  "range": 10.0, "interval": 1.0,   "area": 2.0, "maxTargets": 5,  "kind": "puddle",  "air": false, "energy": false, "single": false, "note": "puddles linger 3 s"},
	"Virus":       {"dps": 7.5,  "range": 12.0, "interval": 1.0,   "area": 0.0, "maxTargets": 4,  "kind": "virus",   "air": false, "energy": false, "single": false, "note": "DoT that spreads on death"},
}

const COMBAT := {
	"bulletSpeed": 34.0, "missileSpeed": 18.0, "lobTime": 0.618,
	"laserRampLo": 0.6, "laserRampHi": 1.6, "laserRampT": 3.0,
	"freezerSlow": 0.6, "flamerCone": 0.7, "flamerBurn": 0.35,
	"acidLinger": 3.0, "virusDuration": 4.0, "lightningMiss": 0.2,
	"mineBurst": 34.0, "mineBurstUnit": 0.34, "mineRadius": 1.0,
	"barrierUnits": 21.0, "barrierChew": 1.0, "activateTime": 0.618,
}

const MASS_EXP := 0.9
const TRAITS := {"Hook": 0.08, "Block": 0.08, "Bar": 0.08, "Tee": 0.05, "Skew": 0.08}
## v1.1 story: damage x1.272, range +15%. v2.0 section 9.3 raises damage to x1.5 (set in milestone 6).
const STORY_DAMAGE := 1.272019649514069
const STORY_RANGE := 0.15
const RISE_RANGE := 1.0
const SHAPE := {
	"hole": -0.1, "goldenMin": 1.55, "goldenMax": 1.7, "golden": 0.1,
	"mirror": 0.15, "rotational": 0.15, "perfect": 0.25, "surfaceMax": 0.1,
	"spireCritEvery": 13, "spireCrit": 2.618033988749895,
}
const GLYPHS := {
	"range": 0.1, "damage": 0.15, "rate": 0.15, "pierce": 1,
	"critChance": 0.1, "critMult": 2.0, "slowOnHit": 0.8, "slowTime": 1.0, "chain": 1,
}
const RESONANCE := {"burnSplash": 0.3, "ricochet": 2, "blueSplash": 1.5, "poisonSpread": 0.5}

# ---------------------------------------------------------------- enemies
const SIZES := {
	"mite":     {"hp": 0.3819660112501051, "speed": 3.7, "leak": 1, "essence": 0.5, "radius": 0.36},
	"small":    {"hp": 1.0, "speed": 3.2, "leak": 1, "essence": 1.0, "radius": 0.55},
	"medium":   {"hp": 1.6180339887498949, "speed": 2.5157, "leak": 2, "essence": 2.0, "radius": 0.7},
	"large":    {"hp": 2.618033988749895, "speed": 1.9777, "leak": 3, "essence": 3.0, "radius": 0.85},
	"giant":    {"hp": 6.854101966249685, "speed": 1.2, "leak": 5, "essence": 5.0, "radius": 1.3},
	"champion": {"hp": 11.090169943749475, "speed": 1.05, "leak": 8, "essence": 21.0, "radius": 1.5},
	"boss":     {"hp": 17.94427190999916, "speed": 0.95, "leak": 13, "essence": 34.0, "radius": 1.9},
}
const SUIT_STRONG := 1.272019649514069
const SUIT_WEAK_MULT := 0.7861513777574233

const ARCHETYPES_BY_BOARD := [
	["hopper", "crawler"],
	["hopper", "crawler", "slinky", "roller", "blob"],
	["hopper", "crawler", "slinky", "roller", "blob", "swinger", "tumbler", "beetle"],
	["hopper", "crawler", "slinky", "roller", "blob", "swinger", "tumbler", "beetle", "nautilus"],
	["hopper", "crawler", "slinky", "roller", "blob", "swinger", "tumbler", "beetle", "nautilus"],
	["hopper", "crawler", "slinky", "roller", "blob", "swinger", "tumbler", "beetle", "nautilus"],
	["hopper", "crawler", "slinky", "roller", "blob", "swinger", "tumbler", "beetle", "nautilus"],
]
const MITE_FORMS := ["crawler", "hopper", "blob"]
const MITE_SHARE: Array[float] = [0.25, 0.45, 0.5, 0.55, 0.6, 0.6, 0.65]
const MITES_PER_SMALL := 3
const LANE_SPREAD := 1.05
const ARCH := {
	"hopperCycle": 0.618, "hopperAir": 0.45,
	"slinkyCycle": 1.0, "slinkySplash": 1.5,
	"rollerSpeed": 1.38, "rollerBrake": 0.5,
	"swingerParry": 0.2, "swingerWeak": 1.2,
	"tumblerFlip": 1.2,
	"nautilusSpeed": 0.8, "nautilusFront": 0.5,
	"balloonSpeed": 0.7, "balloonFromBoard": 4, "balloonEvery": 13,
	"walkerFromBoard": 5, "walkerEvery": 21,
	"beetleBullet": 0.85, "blobSplash": 1.2,
}
## Soft bodies hop, stretch and jiggle; coils expand and contract (v2.0 section 8.1).
const SOFT_ARCHS := ["hopper", "crawler", "blob"]
const COIL_ARCHS := ["slinky"]

# ---------------------------------------------------------------- elements
const GROUPS := {
	"nonmetal":   {"name": "Nonmetal", "symbols": ["H", "C", "N", "P"], "color": Color("9fb4c8"), "ability": "No special ability", "counter": "Anything", "fromBoard": 1},
	"alkali":     {"name": "Alkali metal", "symbols": ["Li", "Na", "K", "Rb", "Cs"], "color": Color("ff8a5c"), "ability": "Speed bursts every few seconds", "counter": "Slows and chokepoints", "fromBoard": 2},
	"lanthanide": {"name": "Lanthanide", "symbols": ["La", "Ce", "Nd", "Eu", "Gd"], "color": Color("7aff9a"), "ability": "Regenerates health over time", "counter": "Burst damage and burn", "fromBoard": 2},
	"precious":   {"name": "Precious metal", "symbols": ["Au", "Ag", "Pt"], "color": Color("ffe08a"), "ability": "Fast, drops a pile of Essence", "counter": "Catch it for a jackpot", "fromBoard": 2},
	"transition": {"name": "Transition metal", "symbols": ["Ti", "Fe", "Co", "Ni", "Cu", "Zn"], "color": Color("c7cbd9"), "ability": "Armour cuts every hit by a flat amount", "counter": "Heavy single shots", "fromBoard": 3},
	"noble":      {"name": "Noble gas", "symbols": ["He", "Ne", "Ar", "Kr", "Xe"], "color": Color("9fd8ff"), "ability": "Force field that absorbs damage, then recharges", "counter": "Rapid fire to pop the shield", "fromBoard": 3},
	"actinide":   {"name": "Actinide", "symbols": ["Th", "U", "Np", "Pu"], "color": Color("fff07a"), "ability": "Splits into smaller monsters on death", "counter": "Splash damage", "fromBoard": 4},
	"chalcogen":  {"name": "Chalcogen", "symbols": ["O", "S", "Se", "Te"], "color": Color("ffd36b"), "ability": "Speeds up monsters around it", "counter": "Focus it first", "fromBoard": 4},
	"metalloid":  {"name": "Metalloid", "symbols": ["B", "Si", "Ge", "As", "Sb"], "color": Color("c0a8ff"), "ability": "Phases out briefly and cannot be hit", "counter": "Area damage and sprays", "fromBoard": 5},
	"alkaline":   {"name": "Alkaline earth", "symbols": ["Be", "Mg", "Ca", "Sr", "Ba"], "color": Color("7ac8ff"), "ability": "Shields the monsters around it", "counter": "Long range snipers", "fromBoard": 5},
	"halogen":    {"name": "Halogen", "symbols": ["F", "Cl", "Br", "I"], "color": Color("b6ff5c"), "ability": "Corrosive aura slows nearby towers", "counter": "Long range", "fromBoard": 6},
	"post":       {"name": "Post-transition metal", "symbols": ["Al", "Ga", "In", "Sn", "Pb"], "color": Color("ff9f7a"), "ability": "Dense: much more health, hits the core harder", "counter": "Sustained damage", "fromBoard": 6},
}
const ABILITIES := {
	"chanceByBoard": [0.0, 0.22, 0.32, 0.42, 0.5, 0.55, 0.6],
	"goldenChance": 1.0 / 89.0,
	"shield": 0.38, "shieldDelay": 2.5, "shieldRecharge": 0.2,
	"alkaliEvery": 4.0, "alkaliBurst": 1.1, "alkaliMult": 2.0,
	"armor": 0.05, "armorFloor": 0.35,
	"splitHp": 0.3819660112501051, "splitGenerations": 3,
	"bearerShield": 0.2, "bearerEvery": 3.0, "bearerRadius": 3.0,
	"growerHp": 2.618033988749895, "growerLeak": 2,
	"regen": 0.02, "phaseEvery": 3.0, "phaseTime": 0.618,
	"heraldSpeed": 1.2, "heraldRadius": 3.0,
	"hoarderSpeed": 1.3, "hoarderEssence": 8.0,
	"corrosiveRadius": 5.0, "corrosiveRate": 0.7,
}

# ---------------------------------------------------------------- tiers
const TIER_ODDS := [
	[1.0, 0.0, 0.0, 0.0], [0.8, 0.2, 0.0, 0.0], [0.6, 0.35, 0.05, 0.0], [0.45, 0.4, 0.15, 0.0],
	[0.3, 0.4, 0.25, 0.05], [0.2, 0.35, 0.3, 0.15], [0.1, 0.3, 0.35, 0.25],
]
const TIER_HP: Array[float] = [1.0, 1.6180339887498949, 2.618033988749895, 4.23606797749979]
const TIER_SCALE: Array[float] = [1.0, 1.1, 1.2, 1.32]
const TIER_ESSENCE: Array[float] = [1.0, 1.5, 2.0, 2.5]

# ---------------------------------------------------------------- champions
const CHAMPION := {
	"fromBoard": 3,
	"waves": [[], [], [0], [0], [3, 0], [4, 0], [5, 10]],
	"summonEvery": 3.5, "summonCount": 3,
	"lootEssence": 13.0, "lootOre": 8.0,
}
const UNDO_SECONDS := 2.0

# ---------------------------------------------------------------- waves
const WAVE_LADDER: Array[int] = [5, 8, 13, 21, 34, 55, 89]
const BURSTS: Array[int] = [1, 1, 2, 3, 5, 8, 13, 21, 34]
const BURST_GAP := 2.5
const PACK_SPACING := {"mite": 0.07, "small": 0.14, "medium": 0.2, "large": 0.26, "giant": 0.4, "champion": 0.5, "boss": 0.5}
const PIECES_PER_WAVE_CYCLE := 9.5
const HP_ALPHA := 1.3
## H_B per board on Normal. [Tune] Recalibrate with the harness for v2.0 (section 8.5).
const H_B: Array[float] = [420.0, 1300.0, 430.0, 560.0, 640.0, 600.0, 660.0]
const TENSION := {"start": 0.72, "end": 1.0, "spike": 1.12, "exhale": 0.9, "spikes": [2, 3, 5, 8], "single": [0.75, 0.9]}
const DOMINANT_SHARE := 0.5

# ---------------------------------------------------------------- base
const BASE_SQUARES := [
	{"id": 0, "size": 1, "x": 8, "y": 5},
	{"id": 1, "size": 1, "x": 9, "y": 5},
	{"id": 2, "size": 2, "x": 8, "y": 6},
	{"id": 3, "size": 3, "x": 10, "y": 5},
	{"id": 4, "size": 5, "x": 8, "y": 0},
	{"id": 5, "size": 8, "x": 0, "y": 0},
]
const BASE_START_SQUARES := 2
const HARMONY := 0.2360679774997897
const GOLDEN_BASE_DAMAGE := 0.08

const BUILDING_IDS: Array[String] = ["blastDoor", "beacon", "powerStation", "recycler", "research", "shapeFactory", "harvesterHub", "factory", "missileBattery", "smite"]
const BUILDINGS := {
	"blastDoor":      {"name": "Blast Door", "size": 1, "cost": 5, "effect": "+5 base buffer per board"},
	"beacon":         {"name": "Beacon", "size": 1, "cost": 5, "effect": "+1 MAY USE slot"},
	"powerStation":   {"name": "Power Station", "size": 2, "cost": 8, "effect": "+10% damage for Laser, Pulsar, Lightning, E-Field"},
	"recycler":       {"name": "Recycler", "size": 2, "cost": 8, "effect": "Turn any piece into 2 Essence"},
	"research":       {"name": "Research Tower", "size": 3, "cost": 13, "effect": "Every 3rd board, a rare-glyph piece"},
	"shapeFactory":   {"name": "Shape Factory", "size": 3, "cost": 21, "effect": "Once per wave, choose the next piece family"},
	"harvesterHub":   {"name": "Harvester Hub", "size": 3, "cost": 13, "effect": "+50% ore from Harvesters"},
	"factory":        {"name": "Factory", "size": 5, "cost": 34, "effect": "Sends a small tank down the road every 13 s"},
	"missileBattery": {"name": "Missile Battery", "size": 5, "cost": 34, "effect": "Base Missile tower, 40-cell range from the core"},
	"smite":          {"name": "Smite Tower", "size": 8, "cost": 55, "effect": "Orbital strike, recharges over 3 waves"},
}
const BUILDING_FX := {
	"blastDoor": 5, "powerStation": 0.1, "recycler": 2.0, "harvesterHub": 0.5,
	"factoryEvery": 13.0, "tankDps": 12.0, "tankRange": 6.0, "tankHpUnits": 8.0, "tankSpeed": 2.5,
	"batteryRange": 40.0, "smiteWaves": 3, "smiteRadius": 6.0, "smiteUnits": 8.0,
}

# ---------------------------------------------------------------- feedback
const COMBO_WINDOW := 1.618
const COMBO_STEPS: Array[int] = [3, 5, 8, 13, 21]

## Piece colour -> glow colour (ref 4: Gold = amber, Red = red, Blue = cyan-blue, Green = acid green).
const PIECE_GLOW := {
	"gold": Color(1.0, 0.68, 0.22),
	"red": Color(1.0, 0.25, 0.2),
	"blue": Color(0.25, 0.75, 1.0),
	"green": Color(0.55, 1.0, 0.2),
}
const PIECE_BODY := {
	"gold": Color(0.92, 0.66, 0.2),
	"red": Color(0.86, 0.22, 0.2),
	"blue": Color(0.2, 0.52, 0.92),
	"green": Color(0.36, 0.78, 0.26),
}
