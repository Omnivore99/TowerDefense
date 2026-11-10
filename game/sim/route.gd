class_name Route
extends RefCounted
## A walkable polyline in cell coordinates, from an ingress to the core (or a town gate).

var ingress: int = 0
var pts: PackedVector2Array = PackedVector2Array()
var cum: PackedFloat64Array = PackedFloat64Array()
var length: float = 0.0
## Distances along the route where the road turns.
var corners: PackedFloat64Array = PackedFloat64Array()
## Town spur routes end at a town gate instead of the core (section 12).
var town_id: int = 0


static func make(ingress_idx: int, points: PackedVector2Array) -> Route:
	var r := Route.new()
	r.ingress = ingress_idx
	r.pts = points
	r.cum.append(0.0)
	for i in range(1, points.size()):
		r.cum.append(r.cum[i - 1] + points[i].distance_to(points[i - 1]))
	for i in range(1, points.size() - 1):
		var a := atan2(points[i].y - points[i - 1].y, points[i].x - points[i - 1].x)
		var b := atan2(points[i + 1].y - points[i].y, points[i + 1].x - points[i].x)
		if absf(a - b) > 0.1:
			r.corners.append(r.cum[i])
	r.length = r.cum[r.cum.size() - 1]
	return r


## Position and heading at distance d along the route: Vector3(x, y, dir).
func at(d: float) -> Vector3:
	var n := pts.size()
	if d <= 0.0:
		var a := pts[0]
		var b := pts[1]
		return Vector3(a.x, a.y, atan2(b.y - a.y, b.x - a.x))
	if d >= length:
		var a2 := pts[n - 2]
		var b2 := pts[n - 1]
		return Vector3(b2.x, b2.y, atan2(b2.y - a2.y, b2.x - a2.x))
	var lo := 1
	var hi := cum.size() - 1
	while lo < hi:
		var m := (lo + hi) >> 1
		if cum[m] < d:
			lo = m + 1
		else:
			hi = m
	var i := lo
	var p0 := pts[i - 1]
	var p1 := pts[i]
	var seg := cum[i] - cum[i - 1]
	var t := (d - cum[i - 1]) / seg if seg > 0.0 else 0.0
	return Vector3(p0.x + (p1.x - p0.x) * t, p0.y + (p1.y - p0.y) * t, atan2(p1.y - p0.y, p1.x - p0.x))


func near_corner(d: float, within: float) -> bool:
	for c in corners:
		if absf(c - d) < within:
			return true
	return false
