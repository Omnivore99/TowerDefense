class_name CamRig
extends Node3D
## Three-quarter perspective camera (about 50° pitch). Wheel zooms toward the cursor,
## right-drag or WASD pans, Q / E rotate in 45° steps with an eased turn, Home recentres.
## Also: screen shake, nudges, and the auto-directed spectator mode.

const PITCH := deg_to_rad(52.0)
const MIN_DIST := 9.0
const MAX_DIST := 150.0

var cam: Camera3D
var target := Vector3(84, 0, 52)
var dist := 120.0
var dist_goal := 120.0
var yaw := 0.0
var yaw_goal := 0.0
var home := Vector3(84, 0, 52)
var shake := 0.0
var nudge := Vector3.ZERO
var reduced_motion := false
var sensitivity := 1.0
var dragging := false
var drag_last := Vector2.ZERO
## Spectator: the world sets a focus point each frame while active.
var spectator := false
var spec_focus := Vector3.ZERO
var bounds := Rect2(0, 0, Bal.GRID_W, Bal.GRID_H)


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.3
	cam.far = 600.0
	add_child(cam)
	_apply(0.0)


func frame_all() -> void:
	target = Vector3(Bal.GRID_W / 2.0, 0, Bal.GRID_H / 2.0 + 4.0)
	dist_goal = 128.0
	dist = dist_goal


func recentre() -> void:
	target = home
	dist_goal = 46.0


func rotate_step(dir: int) -> void:
	yaw_goal += dir * PI / 4.0


func zoom_at(factor: float, screen_pos: Vector2) -> void:
	var before: Variant = ground_at(screen_pos)
	dist_goal = clampf(dist_goal * factor, MIN_DIST, MAX_DIST)
	# move toward the cursor so the point under it stays put (approximately)
	if before != null:
		var k := 1.0 - factor
		target += (Vector3(before.x, 0, before.z) - Vector3(target.x, 0, target.z)) * k * 0.9
		_clamp()


func pan(screen_delta: Vector2) -> void:
	var s := dist * 0.0016 * sensitivity
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	target -= right * screen_delta.x * s
	target -= fwd * screen_delta.y * s
	_clamp()


func pan_keys(v: Vector2, delta: float) -> void:
	if v == Vector2.ZERO:
		return
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var speed := dist * 0.9 * sensitivity
	target += (right * v.x + fwd * v.y) * speed * delta
	_clamp()


func _clamp() -> void:
	target.x = clampf(target.x, bounds.position.x - 10, bounds.end.x + 10)
	target.z = clampf(target.z, bounds.position.y - 10, bounds.end.y + 14)


func add_shake(amount: float) -> void:
	if reduced_motion:
		return
	shake = minf(1.0, shake + amount)


func add_nudge(v: Vector3) -> void:
	if reduced_motion:
		return
	nudge += v


func _process(delta: float) -> void:
	_apply(delta)


func _apply(delta: float) -> void:
	var k := 1.0 - pow(0.0005, delta) if delta > 0.0 else 1.0
	if spectator:
		target = target.lerp(spec_focus, 1.0 - pow(0.08, delta))
		dist_goal = lerpf(dist_goal, 30.0, 1.0 - pow(0.3, delta))
	dist = lerpf(dist, dist_goal, k)
	yaw = lerp_angle(yaw, yaw_goal, 1.0 - pow(0.002, delta) if delta > 0.0 else 1.0)
	var off := Vector3(sin(yaw) * cos(PITCH), sin(PITCH), cos(yaw) * cos(PITCH)) * dist
	var shake_off := Vector3.ZERO
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 2.2)
		var s := shake * shake * 0.6
		shake_off = Vector3(randf_range(-s, s), randf_range(-s, s), randf_range(-s, s))
	nudge = nudge.lerp(Vector3.ZERO, 1.0 - pow(0.0001, delta) if delta > 0.0 else 1.0)
	position = target + off + shake_off + nudge
	if cam != null:
		cam.global_position = position
		cam.look_at(target + shake_off * 0.5 + nudge, Vector3.UP)


## Point on the ground plane (y = 0) under a screen position, or null.
func ground_at(screen_pos: Vector2, plane_y: float = 0.0) -> Variant:
	if cam == null:
		return null
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 1e-5:
		return null
	var t := (plane_y - from.y) / dir.y
	if t < 0.0:
		return null
	return from + dir * t
