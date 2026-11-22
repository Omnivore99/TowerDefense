class_name Rng
extends RefCounted
## Deterministic seeded RNG (mulberry32), bit-identical to the v1.1 TypeScript version.

const M32 := 0xFFFFFFFF
var s: int = 0


func _init(seed_value: int = 0) -> void:
	s = seed_value & M32


static func imul(a: int, b: int) -> int:
	a &= M32
	b &= M32
	var lo: int = (a * (b & 0xFFFF)) & M32
	var hi: int = ((a * (b >> 16)) & 0xFFFF) << 16
	return (lo + hi) & M32


func next() -> float:
	s = (s + 0x6D2B79F5) & M32
	var t: int = s
	t = imul(t ^ (t >> 15), t | 1)
	t = t ^ ((t + imul(t ^ (t >> 7), t | 61)) & M32)
	return float((t ^ (t >> 14)) & M32) / 4294967296.0


func range_f(a: float, b: float) -> float:
	return a + (b - a) * next()


## Inclusive integer range.
func int_range(a: int, b: int) -> int:
	return a + int(floor(next() * float(b - a + 1)))


func chance(p: float) -> bool:
	return next() < p


func pick(arr: Array) -> Variant:
	return arr[int(floor(next() * arr.size()))]


func weighted(w: Dictionary) -> Variant:
	var total := 0.0
	for k in w:
		total += float(w[k])
	var r := next() * total
	var last: Variant = null
	for k in w:
		r -= float(w[k])
		last = k
		if r <= 0.0:
			return k
	return last


func shuffle(arr: Array) -> Array:
	var i := arr.size() - 1
	while i > 0:
		var j := int(floor(next() * float(i + 1)))
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
		i -= 1
	return arr


## Mix a seed with stream labels so map, pieces and waves are independent streams.
static func sub_seed(seed_value: int, parts: Array) -> int:
	var h: int = (seed_value & M32) ^ 0x9E3779B9
	for p in parts:
		h = imul(h ^ ((int(p) + 0x7F4A7C15) & M32), 0x85EBCA6B)
		h = h ^ (h >> 13)
		h = imul(h, 0xC2B2AE35)
		h = h ^ (h >> 16)
	return h & M32


static func random_seed() -> int:
	return randi() & M32
