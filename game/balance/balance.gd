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
## v2.0 economy (sections 5.1, 6). [Tune]
const FOREST := {"perNewRoad": 2, "side": [4, 6], "trees": [13, 34], "perCell": 1.0, "timberPerTree": 3.0, "regrowEvery": 2}
const LAKE := {"perNewRoad": 1, "side": [5, 8], "units": [34, 89], "perShoreCell": 2, "refill": 0.34}
## Pimples: one sprouts every `every` waves per structure, `cap` alive at once; V = valueMult x per-wave output (min minValue).
const PIMPLE := {"every": 2, "cap": 2, "pearlChance": 0.3333, "minValue": 8.0, "valueMult": 3.0, "craterCool": 3}
## Resource Lance (D2): charges per wave by level, upgrade costs to level 2, 3, 4.
const LANCE := {"charges": [2, 3, 4, 5], "upgrade": [8, 13, 21]}
## Ore converts to Essence at a poor rate (section 6.1; the Market district in M5).
const ORE_TO_ESSENCE := 3.0

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

const BUILDING_IDS: Array[String] = ["lance", "armory", "blastDoor", "beacon", "powerStation", "recycler", "research", "shapeFactory", "harvesterHub", "factory", "missileBattery"]
const BUILDINGS := {
	"lance":          {"name": "Resource Lance", "size": 1, "cost": 5, "effect": "Pops pimples anywhere on the map: 2 charges per wave"},
	"blastDoor":      {"name": "Blast Door", "size": 1, "cost": 5, "effect": "+5 base buffer per board"},
	"beacon":         {"name": "Beacon", "size": 1, "cost": 5, "effect": "+1 MAY USE slot"},
	"armory":         {"name": "Armory", "size": 2, "cost": 8, "effect": "Unlocks every kit in the Armory (K)"},
	"powerStation":   {"name": "Power Station", "size": 2, "cost": 8, "effect": "+10% damage for Laser, Pulsar, Lightning, E-Field"},
	"recycler":       {"name": "Recycler", "size": 2, "cost": 8, "effect": "Turn any piece into 2 Essence"},
	"research":       {"name": "Research Tower", "size": 3, "cost": 13, "effect": "+1 tech point per board; every 3rd board, a rare-glyph piece"},
	"shapeFactory":   {"name": "Shape Factory", "size": 3, "cost": 21, "effect": "Once per wave, choose the next piece family"},
	"harvesterHub":   {"name": "Harvester Hub", "size": 3, "cost": 13, "effect": "+50% ore from Harvesters"},
	"factory":        {"name": "Factory", "size": 5, "cost": 34, "effect": "Sends a small tank down the road every 13 s"},
	"missileBattery": {"name": "Missile Battery", "size": 5, "cost": 34, "effect": "Base Missile tower, 40-cell range from the core"},
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

# ================================================================ v2.0 milestone 4
# ---------------------------------------------------------------- targeting (section 9.1)
const PRIORITIES: Array[String] = ["first", "last", "most", "least", "fastest", "slowest", "strongest", "weakest", "specials", "air", "closest"]
const PRIORITY_LABEL := {
	"first": "First", "last": "Last", "most": "Most powerful", "least": "Least powerful", "fastest": "Fastest",
	"slowest": "Slowest", "strongest": "Strongest", "weakest": "Weakest", "specials": "Specials first", "air": "Air first", "closest": "Closest",
}
const PRIORITY_DEFAULT := {
	"Gun": "first", "Machine Gun": "first", "Rifle": "most", "Bomb": "first", "Missile": "air", "Laser": "strongest",
	"Pulsar": "first", "Lightning": "first", "E-Field": "first", "Freezer": "fastest", "Flamer": "first", "Acid": "first", "Virus": "least",
}
## Turret turn rates (rad/s); a shot fires only when aligned within AIM_TOLERANCE.
const TURN_RATE := {
	"Gun": 7.0, "Machine Gun": 11.0, "Rifle": 2.6, "Bomb": 4.0, "Missile": 6.0, "Laser": 5.0, "Pulsar": 4.0,
	"Lightning": 99.0, "E-Field": 99.0, "Freezer": 99.0, "Flamer": 6.0, "Acid": 4.0, "Virus": 6.0,
}
const AIM_TOLERANCE := 0.22
const TARGET_HYSTERESIS := 1.15

# ---------------------------------------------------------------- evolutions (section 9.5) [Tune]
const TECHS: Array[String] = ["steam", "aether", "alchemy"]
const TECH_NAME := {"steam": "Steamworks", "aether": "Aether", "alchemy": "Alchemy"}
## Resources each technology leans on (Mk III / Mk IV costs are split 13:8 and 34:21 across them).
const TECH_RES := {"steam": ["ore", "timber"], "aether": ["ore", "water"], "alchemy": ["water", "timber"]}
## Points needed for each next tech level (Fibonacci): level 1 at 1 point, 2 at 3, 3 at 6, 4 at 11, 5 at 19.
const TECH_LEVEL_POINTS: Array[int] = [1, 2, 3, 5, 8]
const TECH_OPEN_COST := 13.0
const EVO := {
	"mk2": {"ore": 8.0, "timber": 5.0, "dmg": 1.3, "range": 1.1},
	"mk3": {"split": [13.0, 8.0], "techLevel": 1, "dmg": 1.6, "range": 1.1},
	"mk4": {"split": [34.0, 21.0], "pearls": 2, "techLevel": 3, "dmg": 1.6, "range": 1.1},
	"sizeFactorPerPiece": 0.1,
}
## Tech perks: level 2 = +10% damage for that technology's towers; level 5 ultimates.
const TECH_PERK_DMG := 0.1
const LIGHTHOUSE_GRID := 0.15
## Branches: two per tower. m3 / m4 are the Mk III signature and Mk IV capstone effects.
## Keys: dmg range rate (multipliers); pierce chain salvo multi (counts); splash (radius); dot (fraction
## of hit damage per second, 3 s); slow [mult, s]; stun (s); knock (cells); vuln (+x taken, 3 s);
## buff (+x damage to towers within 6 cells); armor (ignore shields and armour); spread (dots spread on
## kill); puddle (leaves a damaging puddle, radius); fire (s the puddle burns).
const BRANCHES := {
	"Gun": [
		{"tech": "steam", "name": "Bastion Gun", "m3": {"rate": 1.6, "dmg": 1.1}, "m4": {"rate": 2.2, "dmg": 1.3, "splash": 1.2}, "tags": "Belt-fed · Sustained"},
		{"tech": "aether", "name": "Lens Cannon", "m3": {"pierce": 1, "dmg": 1.3}, "m4": {"pierce": 3, "dmg": 1.6}, "tags": "Light bolts · Pierce"},
	],
	"Machine Gun": [
		{"tech": "steam", "name": "Gatling Keep", "m3": {"rate": 1.5}, "m4": {"rate": 2.4}, "tags": "Spin-up · Casings"},
		{"tech": "alchemy", "name": "Nanite Spitter", "m3": {"dot": 0.35}, "m4": {"dot": 0.5, "spread": 1}, "tags": "Infects · Stacks"},
	],
	"Rifle": [
		{"tech": "steam", "name": "Siege Rifle", "m3": {"armor": 1, "dmg": 1.3}, "m4": {"armor": 1, "dmg": 1.7, "knock": 1.0}, "tags": "Armour piercing · Knockback"},
		{"tech": "aether", "name": "Lighthouse Lance", "m3": {"pierce": 3, "dmg": 1.2}, "m4": {"pierce": 12, "dmg": 1.5}, "tags": "Rail beam · Line"},
	],
	"Bomb": [
		{"tech": "steam", "name": "Steam Mortar", "m3": {"salvo": 2}, "m4": {"salvo": 4, "dmg": 1.2}, "tags": "Cluster bomblets · Area"},
		{"tech": "alchemy", "name": "Plague Mortar", "m3": {"puddle": 2.0}, "m4": {"puddle": 2.6, "slow": [0.7, 1.0], "vuln": 0.15}, "tags": "Gas clouds · Corrode"},
	],
	"Missile": [
		{"tech": "steam", "name": "Rocket Spire", "m3": {"salvo": 3}, "m4": {"salvo": 7}, "tags": "Salvos · Smoke"},
		{"tech": "aether", "name": "Seeker Array", "m3": {"dmg": 1.3, "rate": 1.3}, "m4": {"dmg": 1.6, "rate": 1.5, "chain": 2}, "tags": "Homing · Anti-air"},
	],
	"Laser": [
		{"tech": "aether", "name": "Amber Dome Emitter", "m3": {"dmg": 1.4}, "m4": {"dmg": 1.6, "multi": 2}, "tags": "Ramping beam · Split"},
		{"tech": "steam", "name": "Furnace Lance", "m3": {"fire": 2.0}, "m4": {"fire": 5.0, "dmg": 1.3}, "tags": "Heat beam · Fire lines"},
	],
	"Pulsar": [
		{"tech": "aether", "name": "Resonance Spire", "m3": {"dmg": 1.3, "range": 1.15}, "m4": {"dmg": 1.6, "stun": 0.2}, "tags": "Wide rings · Stun"},
		{"tech": "alchemy", "name": "Spore Pulsar", "m3": {"dot": 0.3}, "m4": {"dot": 0.4, "puddle": 1.6}, "tags": "Spores · Clouds"},
	],
	"Lightning": [
		{"tech": "aether", "name": "Plasma Spire", "m3": {"chain": 2}, "m4": {"chain": 4, "dmg": 1.4}, "tags": "Chain lightning · Multi-target"},
		{"tech": "steam", "name": "Dynamo Coil", "m3": {"stun": 0.15}, "m4": {"stun": 0.3, "dmg": 1.4}, "tags": "Stun · Arcs"},
	],
	"E-Field": [
		{"tech": "aether", "name": "Crystal Ward", "m3": {"buff": 0.1}, "m4": {"buff": 0.2, "dmg": 1.3}, "tags": "Support · Rune amplifier"},
		{"tech": "alchemy", "name": "Miasma Dome", "m3": {"dot": 0.3}, "m4": {"dot": 0.4, "vuln": 0.15}, "tags": "Poison aura · Weaken"},
	],
	"Freezer": [
		{"tech": "aether", "name": "Frost Lens", "m3": {"stun": 0.5}, "m4": {"stun": 0.8, "dmg": 1.3}, "tags": "Freeze · Control"},
		{"tech": "alchemy", "name": "Cryo Cauldron", "m3": {"puddle": 1.8}, "m4": {"puddle": 2.4, "splash": 1.5}, "tags": "Slush · Shatter"},
	],
	"Flamer": [
		{"tech": "steam", "name": "Boiler Furnace", "m3": {"range": 1.3, "knock": 0.3}, "m4": {"range": 1.5, "knock": 0.5, "dmg": 1.4}, "tags": "Long jet · Knockback"},
		{"tech": "alchemy", "name": "Napalm Alembic", "m3": {"dot": 0.4}, "m4": {"dot": 0.6, "spread": 1}, "tags": "Sticky fire · Spreads"},
	],
	"Acid": [
		{"tech": "alchemy", "name": "Nanite Cauldron", "m3": {"puddle": 2.6}, "m4": {"puddle": 3.2, "vuln": 0.2}, "tags": "Wide puddles · Eat armour"},
		{"tech": "steam", "name": "Pressure Sprayer", "m3": {"range": 1.35}, "m4": {"range": 1.5, "pierce": 4}, "tags": "Pressurised jet · Line"},
	],
	"Virus": [
		{"tech": "alchemy", "name": "Hive Spire", "m3": {"dot": 0.2, "spread": 1}, "m4": {"dot": 0.3, "spread": 2, "dmg": 1.4}, "tags": "Fast spread · Swarm"},
		{"tech": "aether", "name": "Phage Beacon", "m3": {"vuln": 0.1}, "m4": {"vuln": 0.2}, "tags": "Marks · Team damage"},
	],
}

# ---------------------------------------------------------------- kits (section 10) [Tune]
const KIT_BELT := 6
const KITS := {
	"landmine": {"name": "Landmine", "cost": {"ore": 3.0}, "where": "road", "size": Vector2i(1, 1), "note": "3 x 3 blast, 55 x unit HP, one use"},
	"spike": {"name": "Spike trap", "cost": {"timber": 5.0, "ore": 2.0}, "where": "road", "size": Vector2i(2, 2), "note": "0.5 x unit HP per crossing + bleed, 21 hits"},
	"betty": {"name": "Bouncing Betty", "cost": {"ore": 5.0, "essence": 1.0}, "where": "road", "size": Vector2i(1, 1), "note": "hits airborne too, 2-cell burst"},
	"claymore": {"name": "Tripwire claymore", "cost": {"ore": 5.0, "timber": 2.0}, "where": "road", "size": Vector2i(1, 1), "note": "shrapnel cone along the road, catches leapers"},
	"tar": {"name": "Tar pit", "cost": {"timber": 5.0, "water": 5.0}, "where": "road", "size": Vector2i(2, 3), "note": "slows to 50% for the board"},
	"metronome_decay": {"name": "Decay metronome", "cost": {"timber": 8.0, "ore": 5.0}, "where": "off", "size": Vector2i(2, 2), "note": "stacking rot per tick"},
	"metronome_thunder": {"name": "Thunder metronome", "cost": {"timber": 8.0, "ore": 5.0}, "where": "off", "size": Vector2i(2, 2), "note": "area burst per tick"},
	"metronome_molasses": {"name": "Molasses metronome", "cost": {"timber": 8.0, "ore": 5.0}, "where": "off", "size": Vector2i(2, 2), "note": "slows 25% per tick"},
	"metronome_unmaking": {"name": "Unmaking metronome", "cost": {"timber": 8.0, "ore": 5.0}, "where": "off", "size": Vector2i(2, 2), "note": "strips shields and armour"},
	"ram_impact": {"name": "Torpedo Ram (impact)", "cost": {"ore": 13.0, "timber": 8.0}, "where": "roadside", "size": Vector2i(3, 3), "note": "rolling rocket up the road, 21 x unit HP"},
	"ram_grinder": {"name": "Torpedo Ram (grinder)", "cost": {"ore": 13.0, "timber": 8.0}, "where": "roadside", "size": Vector2i(3, 3), "note": "slithering drill through everything"},
	"howitzer": {"name": "Howitzer", "cost": {"ore": 21.0, "essence": 13.0}, "where": "ring", "size": Vector2i(2, 2), "note": "55-cell artillery, 34 x unit HP"},
	"airstrike": {"name": "Air-strike antenna", "cost": {"ore": 34.0, "essence": 21.0}, "where": "ring", "size": Vector2i(2, 2), "note": "A: a 3 x 13 cascade every 21 s"},
	"orbital": {"name": "Orbital uplink", "cost": {"ore": 55.0, "essence": 34.0, "pearls": 3.0}, "where": "ring", "size": Vector2i(2, 2), "note": "O: one huge beam"},
}
const KIT_ORDER: Array[String] = ["landmine", "spike", "betty", "claymore", "tar", "metronome_decay", "metronome_thunder", "metronome_molasses", "metronome_unmaking", "ram_impact", "ram_grinder", "howitzer", "airstrike", "orbital"]
const ROAD_KITS_PER_SQUARE := 2
const TRAP := {
	"landmineUnits": 55.0, "landmineR": 1.6, "spikeUnits": 0.5, "spikeHits": 21, "bettyUnits": 21.0, "bettyR": 2.0,
	"claymoreUnits": 21.0, "claymoreLen": 5.0, "tarSlow": 0.5,
}
const METRONOME := {"tick": 0.618, "decay": 0.928, "stop": 0.1, "shove": 0.4, "timedShove": 0.7, "window": 0.146, "max": 1.272, "radius": 5.0,
	"rotFrac": 0.02, "rotT": 3.0, "rotStacks": 5, "thunderUnits": 0.6, "molasses": 0.75, "molassesT": 1.236, "unmakeShield": 0.25}
const RAM := {"speed": 9.0, "impactUnits": 21.0, "impactR": 3.0, "impactReload": 8.0, "grinderUnits": 3.0, "grinderReload": 10.0, "reach": 34.0}
const HOWITZER := {"range": 55.0, "minRange": 8.0, "reload": 6.5, "units": 34.0, "radius": 3.0, "flight": 2.5, "max": 3}
const AIRSTRIKE := {"every": 21.0, "radius": 40.0, "len": 13, "width": 3, "units": 5.0}
const ORBITAL := {"recharge": 55.0, "units": 55.0, "ringUnits": 21.0, "r0": 2.0, "r1": 8.0, "delay": 0.618}
## Base ring: kit pads in a ring around the core (section 13).
const RING := {"inner": 4.5, "outer": 9.5}
