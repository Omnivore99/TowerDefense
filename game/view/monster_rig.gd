class_name MonsterRig
extends Node3D
## A rigged monster model from assets/monsters/<arch>.glb (built by tools/blender/build_monsters.py).
## The model is unit sized (r = 1, forward +X) with three animations:
##   move  one gait cycle; seeked from the simulation's gait phase so the feet match the sim
##   hit   short recoil, layered over move with a one-shot
##   death played once when the monster is killed
## Everything is advanced by hand from EnemyView.sync so the pose is final before we read bones.

const DIR := "res://assets/monsters/%s.glb"
const ATTACH_BONES := ["top", "body", "shell", "cube", "balloon", "ring0", "face"]
const HIT_COOLDOWN := 0.35

static var _scenes := {}

var player: AnimationPlayer
var tree: AnimationTree
var skel: Skeleton3D
var mesh: MeshInstance3D
var move_len := 1.0
var hit_cd := 0.0
var dying := false
var _ball := -1


static func has_model(arch: String) -> bool:
	if not _scenes.has(arch):
		var p := DIR % arch
		_scenes[arch] = load(p) if ResourceLoader.exists(p) else null
	return _scenes[arch] != null


static func make(arch: String, mats: Dictionary) -> MonsterRig:
	if not has_model(arch):
		return null
	var rig := MonsterRig.new()
	var inst: Node3D = (_scenes[arch] as PackedScene).instantiate()
	rig.add_child(inst)
	rig.player = inst.find_child("AnimationPlayer", true, false)
	rig.skel = inst.find_child("Skeleton3D", true, false)
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		rig.mesh = n
	rig._apply_mats(mats)
	rig._build_tree()
	if rig.skel != null:
		rig._ball = rig.skel.find_bone("ball")
	return rig


func _apply_mats(mats: Dictionary) -> void:
	if mesh == null or mesh.mesh == null:
		return
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for i in mesh.mesh.get_surface_count():
		var m := mesh.mesh.surface_get_material(i)
		var nm := m.resource_name if m != null else "body"
		if mats.has(nm):
			mesh.set_surface_override_material(i, mats[nm])


func _build_tree() -> void:
	if player == null:
		return
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if player.has_animation("move"):
		move_len = player.get_animation("move").length
	var bt := AnimationNodeBlendTree.new()
	var mv := AnimationNodeAnimation.new()
	mv.animation = "move"
	var seek := AnimationNodeTimeSeek.new()
	var ht := AnimationNodeAnimation.new()
	ht.animation = "hit"
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.04
	shot.fadeout_time = 0.1
	bt.add_node("move", mv, Vector2(0, 0))
	bt.add_node("seek", seek, Vector2(200, 0))
	bt.add_node("hit", ht, Vector2(200, 150))
	bt.add_node("shot", shot, Vector2(400, 0))
	bt.connect_node("seek", 0, "move")
	bt.connect_node("shot", 0, "seek")
	bt.connect_node("shot", 1, "hit")
	bt.connect_node("output", 0, "shot")
	tree = AnimationTree.new()
	tree.tree_root = bt
	add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true


## phase: 0..1 position in the gait cycle. roll: extra spin for the roller's ball (radians).
func pose(phase: float, delta: float, roll: float = 0.0) -> void:
	if dying:
		player.advance(delta)
		return
	if tree == null:
		return
	hit_cd = maxf(0.0, hit_cd - delta)
	tree.set("parameters/seek/seek_request", fposmod(phase, 1.0) * move_len)
	tree.advance(delta)
	if _ball >= 0:
		skel.set_bone_pose_rotation(_ball, Quaternion(Vector3(0, 1, 0), -roll))


func hit() -> void:
	if tree == null or dying or hit_cd > 0.0:
		return
	hit_cd = HIT_COOLDOWN
	tree.set("parameters/shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Plays the death animation; returns its length in seconds.
func die() -> float:
	if player == null or not player.has_animation("death"):
		return 0.0
	dying = true
	if tree != null:
		tree.active = false
	player.play("death")
	player.advance(0.0)
	return player.get_animation("death").length


## A node that follows the main body bone; children placed in the monster's unscaled
## body space (units of the view, not of the model) ride along with the animation.
func attach_point(r: float) -> Node3D:
	if skel == null:
		return self
	var bi := -1
	for b in ATTACH_BONES:
		bi = skel.find_bone(b)
		if bi >= 0:
			break
	if bi < 0:
		return self
	var ba := BoneAttachment3D.new()
	skel.add_child(ba)
	ba.bone_idx = bi
	var holder := Node3D.new()
	ba.add_child(holder)
	holder.transform = skel.get_bone_global_rest(bi).affine_inverse() * Transform3D(Basis.from_scale(Vector3.ONE / r), Vector3.ZERO)
	return holder
