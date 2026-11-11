class_name Sfx
extends Node
## Plays the generated sound bank (tools/sfx/make_sfx.py). Each sound is an
## AudioStreamRandomizer over its variations with pitch and volume jitter. Voice limits per
## sound keep busy moments clean. World sounds are positional (3D); UI sounds are not.
## Music: a calm pad that is always on, and percussion that fades in during waves.

const VARIANTS := {
	"place": 4, "activate": 3, "gun": 4, "mg": 4, "rifle": 3, "mortar": 3, "boom": 4, "missile": 3,
	"laser": 3, "pulsar": 3, "lightning": 4, "efield": 3, "freeze": 3, "flame": 3, "splat": 4, "spore": 3,
	"casing": 5, "kill": 5, "kill_big": 3, "combo": 5, "leak": 3, "wave": 3, "click": 3, "thunder": 4,
	"chime": 3, "reject": 3, "undo": 3, "pop_ripe": 5, "pop_dull": 4, "tap": 3, "chop": 3,
	"card_flip": 3, "card_shuffle": 3, "tick": 5, "whistle": 3, "jet": 3, "orbital": 3, "bell": 3,
}
## Max simultaneous voices per sound (section 15.2: casings 8, ticks 6).
const LIMITS := {"casing": 8, "tick": 6, "mg": 6, "gun": 6, "kill": 6, "laser": 4, "flame": 3, "efield": 3, "splat": 5}
const VOL_DB := {"mg": -10.0, "gun": -6.0, "laser": -10.0, "casing": -12.0, "flame": -9.0, "efield": -12.0, "kill": -4.0, "click": -8.0}
const TOWER_SOUND := {
	"Gun": "gun", "Machine Gun": "mg", "Rifle": "rifle", "Bomb": "mortar", "Missile": "missile", "Laser": "laser",
	"Pulsar": "pulsar", "Lightning": "lightning", "E-Field": "efield", "Freezer": "freeze", "Flamer": "flame",
	"Acid": "splat", "Virus": "spore",
}
const POOL_3D := 28
const POOL_UI := 8

var streams := {}  ## name -> AudioStreamRandomizer
var single := {}  ## "name_v" -> AudioStream (for picking one variation, e.g. combo tiers)
var players3d: Array[AudioStreamPlayer3D] = []
var players_ui: Array[AudioStreamPlayer] = []
var busy := {}  ## name -> Array of players currently playing it
var volume := 0.7
var music_volume := 0.5
var pad_player: AudioStreamPlayer
var drum_player: AudioStreamPlayer
var drums_target := 0.0
var drums_level := 0.0


func _ready() -> void:
	for n in VARIANTS:
		var rnd := AudioStreamRandomizer.new()
		rnd.random_pitch = 1.08
		rnd.random_volume_offset_db = 2.0
		for v in VARIANTS[n]:
			var st: AudioStream = load("res://assets/sfx/%s_%d.ogg" % [n, v])
			if st != null:
				rnd.add_stream(-1, st)
				single["%s_%d" % [n, v]] = st
		streams[n] = rnd
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 18.0
		p.max_distance = 160.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.panning_strength = 0.6
		add_child(p)
		players3d.append(p)
	for i in POOL_UI:
		var q := AudioStreamPlayer.new()
		add_child(q)
		players_ui.append(q)
	pad_player = _music("res://assets/music/calm_pad.ogg")
	drum_player = _music("res://assets/music/wave_drums.ogg")
	drum_player.volume_db = -60.0


func _music(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var st: Variant = load(path)
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	p.stream = st
	add_child(p)
	if st != null and not OS.has_feature("headless") and DisplayServer.get_name() != "headless":
		p.play()
	return p


func set_volumes(sfx: float, music: float) -> void:
	volume = sfx
	music_volume = music


func set_wave(on: bool) -> void:
	drums_target = 1.0 if on else 0.0


func _process(delta: float) -> void:
	drums_level = move_toward(drums_level, drums_target, delta * 0.5)
	var mv := maxf(0.0001, music_volume)
	pad_player.volume_db = linear_to_db(mv * (0.8 - 0.3 * drums_level))
	drum_player.volume_db = linear_to_db(maxf(0.0001, mv * drums_level * 0.8))


func _can_play(name_id: String) -> bool:
	var lim: int = LIMITS.get(name_id, 10)
	var list: Array = busy.get(name_id, [])
	var alive: Array = []
	for p in list:
		if is_instance_valid(p) and p.playing and p.get_meta("sfx", "") == name_id:
			alive.append(p)
	busy[name_id] = alive
	return alive.size() < lim


func _free_player(pool: Array) -> Node:
	for p in pool:
		if not p.playing:
			return p
	return null


## Positional world sound.
func play_at(name_id: String, pos: Vector3, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if volume <= 0.0 or not streams.has(name_id) or not _can_play(name_id):
		return
	var p := _free_player(players3d) as AudioStreamPlayer3D
	if p == null:
		return
	p.stream = streams[name_id]
	p.global_position = pos
	p.volume_db = vol_db + VOL_DB.get(name_id, 0.0) + linear_to_db(volume)
	p.pitch_scale = pitch
	p.set_meta("sfx", name_id)
	p.play()
	busy[name_id].append(p)


## Non-positional sound (UI, stingers). variant >= 0 picks one variation.
func play(name_id: String, vol_db: float = 0.0, variant: int = -1, pitch: float = 1.0) -> void:
	if volume <= 0.0 or not streams.has(name_id) or not _can_play(name_id):
		return
	var p := _free_player(players_ui) as AudioStreamPlayer
	if p == null:
		return
	var key := "%s_%d" % [name_id, variant]
	p.stream = single[key] if variant >= 0 and single.has(key) else streams[name_id]
	p.volume_db = vol_db + VOL_DB.get(name_id, 0.0) + linear_to_db(volume)
	p.pitch_scale = pitch
	p.set_meta("sfx", name_id)
	p.play()
	busy[name_id].append(p)
