class_name World
extends Node3D
## The playable world: owns the Game (sim), steps it at a fixed 60 Hz scaled by the speed
## setting, turns sim events into feedback, and keeps the 3D views in sync with the sim.
## Input: left click places / selects, right-drag pans, wheel zooms, R rotate, F mirror,
## H hold, Space or Enter Ready, Esc undo (2 s) / cancel, Q E turn the camera, Home recentre,
## P pause, 1 2 3 pick MUST USE pieces, 4 5 6 pick MAY USE.

const SPEEDS := [0.5, 1.0, 2.0, 3.0]
const MAX_STEPS_PER_FRAME := 12
## Cell grid that fades in around the cursor while placing (section 4.3).
const GRID_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
varying vec3 wp;
void vertex(){ wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment(){
	vec2 f = abs(fract(wp.xz) - 0.5);
	float line = smoothstep(0.47, 0.5, max(f.x, f.y));
	float fade = 1.0 - smoothstep(1.5, 4.4, length(UV - 0.5) * 9.0);
	ALBEDO = vec3(1.0, 0.75, 0.4);
	ALPHA = line * fade * 0.35;
}
"""

var g: Game
var settings: Dictionary
var meta: Dictionary
var terrain: TerrainView
var cam_rig: CamRig
var fx: Fx
var hud: Hud
var sfx: Sfx
var shot_sound_t := {}  ## tower id -> last firing sound time (ms)
var env: Environment
var sun: DirectionalLight3D
var core: Node3D
var core_glow: OmniLight3D
var core_ring: MeshInstance3D
var tower_root: Node3D
var enemy_root: Node3D
var proj_root: Node3D
var misc_root: Node3D
var tower_views := {}  ## tower id -> TowerView
var enemy_views := {}  ## enemy id -> EnemyView
var proj_views := {}  ## projectile id -> MeshInstance3D
var road_views := {}  ## road piece id -> Node3D
var harv_views := {}  ## harvester id -> Node3D
var tank_views := {}  ## tank id -> Node3D
var puddle_views: Array[MeshInstance3D] = []

var speed := 1.0
var paused := false
var acc := 0.0
var alpha := 1.0
var selected: Dictionary = {}
var rot := 0
var mirror := false
var hover := Vector2i(-999, -999)
var ghost: Node3D
var ghost_sig := ""
var range_ring: MeshInstance3D
var selected_tower := 0
var last_revealed := 0
var last_road_version := -1
var playing := false
var pan_drag := false
var pan_moved := 0.0
var mouse_pos := Vector2.ZERO
var bolt_t := 0.0
var sky_mat: ProceduralSkyMaterial
var grid: MeshInstance3D
var eco_view: EcoView
var last_ground_version := -1
var arsenal_view: ArsenalView
## Kit placement: belt slot in hand (-1 = none) and its rotation.
var kit_slot := -1
var kit_rot := 0
## Strike targeting: "" | "orbital" | "airstrike"; air strikes are aimed by dragging.
var strike_mode := ""
var strike_press: Variant = null
## Demo / screenshot mode (user args): --demo [--warp B,W,S] [--cam x,z,dist,yaw] [--shot path.png]
var demo_bot: Bot
var shot_path := ""
var shot_wait := 2.0


func _ready() -> void:
	settings = SaveIO.load_settings()
	meta = SaveIO.load_meta()
	speed = float(settings.speed)
	_build_environment()
	terrain = TerrainView.new()
	terrain.name = "Terrain"
	add_child(terrain)
	tower_root = _root("Towers")
	enemy_root = _root("Enemies")
	proj_root = _root("Projectiles")
	misc_root = _root("Misc")
	cam_rig = CamRig.new()
	cam_rig.name = "CamRig"
	cam_rig.reduced_motion = settings.reducedMotion
	cam_rig.sensitivity = float(settings.camSensitivity)
	add_child(cam_rig)
	fx = Fx.new()
	fx.name = "Fx"
	fx.reduced_motion = settings.reducedMotion
	fx.quality = 0.5 if OS.has_feature("web") or settings.quality == "low" else 1.0
	add_child(fx)
	fx.cam = cam_rig.cam
	fx.ground_y = func(x: float, z: float) -> float: return _ground_y(x, z)
	sfx = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	sfx.set_volumes(float(settings.volume), float(settings.music))
	fx.casing_landed.connect(func(pos: Vector3): sfx.play_at("casing", pos))
	ghost = Node3D.new()
	ghost.name = "Ghost"
	add_child(ghost)
	range_ring = MeshInstance3D.new()
	range_ring.mesh = Kit.torus(0.96, 1.0, 64)
	range_ring.material_override = Kit.unshaded(Color(1.0, 0.75, 0.35, 0.55), true)
	range_ring.visible = false
	add_child(range_ring)
	grid = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(9, 9)
	grid.mesh = pm
	var gm := ShaderMaterial.new()
	var gs := Shader.new()
	gs.code = GRID_SHADER
	gm.shader = gs
	grid.material_override = gm
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grid.visible = false
	add_child(grid)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.w = self
	layer.add_child(hud)
	# a quiet board behind the title screen
	_new_game(int(Time.get_unix_time_from_system()) & 0x7FFFFFFF, "normal", {}, false)
	cam_rig.frame_all()
	var args := OS.get_cmdline_user_args()
	if args.has("--demo"):
		_start_demo(args)
	else:
		_title_screen()


func _arg(args: PackedStringArray, key: String, def: String) -> String:
	var i := args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else def


func _start_demo(args: PackedStringArray) -> void:
	_new_game(int(_arg(args, "--seed", "7")), _arg(args, "--mode", "normal"), {}, false)
	playing = true
	demo_bot = Bot.new(g, _arg(args, "--skill", "expert"), 99)
	var warp := _arg(args, "--warp", "")
	if warp != "":
		var w := warp.split(",")
		var wb := int(w[0])
		var ww := int(w[1])
		var ws := float(w[2]) if w.size() > 2 else 8.0
		var guard := 0
		while guard < 400000:
			guard += 1
			demo_bot.act()
			g.step()
			if g.phase == "reveal" or g.events.size() > 4000:
				g.events.clear()
			if g.phase == "lost":
				g.retry_board()
			if g.board_no == wb and g.wave_index == ww and g.phase == "wave" and g.wave_t >= ws:
				break
			if g.board_no > wb:
				break
		g.events.clear()
		terrain.rebuild()
		last_road_version = g.board.version
		_build_core()
		_resync_all()
	if args.has("--rich"):
		_showcase()
	if args.has("--select"):
		var best: SimTower = null
		for t in g.towers:
			if t.type != "" and (best == null or t.mark * 100 + t.ground_count() > best.mark * 100 + best.ground_count()):
				best = t
		if best != null:
			selected_tower = best.id
	var cam := _arg(args, "--cam", "")
	if cam == "kit" and not g.arsenal.metronomes.is_empty():
		var m0: Dictionary = g.arsenal.metronomes[0]
		cam_rig.target = Vector3(m0.x, 0, m0.y)
		cam_rig.dist_goal = float(_arg(args, "--dist", "18"))
		cam_rig.dist = cam_rig.dist_goal
	elif cam == "tower" and selected_tower != 0:
		var st := g.tower_by_id(selected_tower)
		cam_rig.target = Vector3(st.cx, 0, st.cy)
		cam_rig.dist_goal = float(_arg(args, "--dist", "16"))
		cam_rig.dist = cam_rig.dist_goal
	elif cam.begins_with("enemy") and not g.enemies.is_empty():
		var e0: SimEnemy = g.enemies[0]
		cam_rig.target = Vector3(e0.x, 0, e0.y)
		cam_rig.dist_goal = float(cam.split(",")[1]) if cam.contains(",") else 24.0
		cam_rig.dist = cam_rig.dist_goal
	elif cam != "" and cam != "tower" and cam != "kit" and not cam.begins_with("enemy"):
		var c := cam.split(",")
		cam_rig.target = Vector3(float(c[0]), 0, float(c[1]))
		cam_rig.dist_goal = float(c[2])
		cam_rig.dist = cam_rig.dist_goal
		if c.size() > 3:
			cam_rig.yaw_goal = deg_to_rad(float(c[3]))
			cam_rig.yaw = cam_rig.yaw_goal
	else:
		cam_rig.recentre()
	shot_path = _arg(args, "--shot", "")
	shot_wait = float(_arg(args, "--wait", "2.0"))


## Demo only: fill the base and show off evolutions and kits for screenshots.
func _showcase() -> void:
	g.base.ore = 999.0
	g.base.timber = 999.0
	g.base.water = 999.0
	g.base.essence = 999.0
	g.base.pearls = 20
	g.base.unlocked = Bal.BASE_SQUARES.size()
	for k in Bal.TECHS:
		g.base.tech[k] = 6
	if not g.has_building("armory"):
		for i in Bal.BASE_SQUARES.size():
			if g.base.buildings[i] == "" and Bal.BASE_SQUARES[i].size >= 2:
				g.base.buildings[i] = "armory"
				break
	var ts: Array = g.towers.filter(func(t): return t.type != "")
	ts.sort_custom(func(a, b): return a.ground_count() > b.ground_count())
	for i in mini(ts.size(), 6):
		var t: SimTower = ts[i]
		var target := 4 - (i % 3)
		while t.mark < target:
			if g.evolve(t.id, i % 2) != "":
				break
	for id in ["howitzer", "howitzer", "airstrike", "orbital"]:
		g.buy_kit(id)
	for id in ["metronome_thunder", "ram_impact", "landmine", "spike", "tar"]:
		g.buy_kit(id)
	var r: Route = g.board.routes[0]
	for slot in g.arsenal.belt.size():
		var id: String = g.arsenal.belt[slot]
		if id == "":
			continue
		var done := false
		for k in 400:
			var d := r.length * (0.2 + 0.002 * k)
			var p := r.at(d)
			var side := 1.0 if k % 2 == 0 else -1.0
			var off := Vector2(-sin(p.z), cos(p.z)) * (0.0 if Bal.KITS[id].where == "road" else 3.0 * side)
			if g.place_kit(slot, 0, floori(p.x + off.x), floori(p.y + off.y)).get("ok", false):
				done = true
				break
		if not done:
			continue
	for e in g.drain_events():
		pass
	for t in g.towers:
		if tower_views.has(t.id):
			tower_views[t.id].rebuild()


func _root(n: String) -> Node3D:
	var r := Node3D.new()
	r.name = n
	add_child(r)
	return r


# ------------------------------------------------------------------ environment ("dusk fortress")
func _build_environment() -> void:
	env = Environment.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.13, 0.17, 0.27)
	sky_mat.sky_horizon_color = Color(0.72, 0.52, 0.42)
	sky_mat.ground_horizon_color = Color(0.32, 0.3, 0.33)
	sky_mat.ground_bottom_color = Color(0.1, 0.11, 0.14)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.68)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.fog_enabled = true
	env.fog_light_color = Color(0.42, 0.42, 0.55)
	env.fog_density = 0.0018
	env.fog_sky_affect = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.05
	if not OS.has_feature("web"):
		env.ssao_enabled = true
		env.ssao_radius = 1.2
		env.ssao_intensity = 1.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.82, 0.66)
	sun.light_energy = 1.15
	sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-142.0), 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	sun.shadow_blur = 1.5
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.45, 0.55, 0.85)
	fill.light_energy = 0.3
	fill.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(40.0), 0)
	add_child(fill)


# ------------------------------------------------------------------ the core keep
## The light moves from dusk on board 1 to night by board 7, so glowing towers matter more.
func _apply_time_of_day() -> void:
	var k := clampf((g.board_no - 1) / 6.0, 0.0, 1.0)
	sun.light_energy = lerpf(1.15, 0.45, k)
	sun.light_color = Color(1.0, 0.82, 0.66).lerp(Color(0.6, 0.68, 1.0), k)
	sky_mat.sky_top_color = Color(0.13, 0.17, 0.27).lerp(Color(0.03, 0.04, 0.09), k)
	sky_mat.sky_horizon_color = Color(0.72, 0.52, 0.42).lerp(Color(0.2, 0.2, 0.32), k)
	env.ambient_light_energy = lerpf(0.75, 0.45, k)
	env.ambient_light_color = Color(0.5, 0.55, 0.68).lerp(Color(0.35, 0.4, 0.6), k)


func _build_core() -> void:
	if core != null:
		core.queue_free()
	core = Node3D.new()
	core.name = "Core"
	add_child(core)
	var c := Board.CORE_PT
	var y0 := terrain.cell_pos(c.x, c.y).y
	core.position = Vector3(c.x, y0, c.y)
	var r := Bal.CORE_RADIUS
	# plinth, keep, four corner towers, roof spire, amber heart
	Kit.add(core, Kit.bevel_box(Vector3(r * 2.0, 0.5, r * 2.0), 0.12), Kit.stone(Color(0.19, 0.21, 0.26)), Vector3(0, 0.25, 0))
	Kit.drum(core, r * 0.62, 2.6, 0.5, Color(0.22, 0.25, 0.31))
	Kit.crenellations(core, r * 0.64, 3.1, 12)
	Kit.windows(core, r * 0.63, 1.6, 8, Kit.amber(4.0))
	for i in 4:
		var a := PI / 4.0 + i * PI / 2.0
		var p := Vector3(cos(a), 0, sin(a)) * r * 0.85
		var t := Node3D.new()
		t.position = p
		core.add_child(t)
		Kit.drum(t, 0.55, 2.0, 0.5)
		Kit.add(t, Kit.cone(0.7, 1.1, 8), Kit.roof(), Vector3(0, 3.05, 0))
		Kit.lantern(t, Vector3(0, 2.5, 0.6))
	Kit.add(core, Kit.cone(r * 0.5, 2.2, 12), Kit.roof(), Vector3(0, 4.2, 0))
	var heart := Kit.add(core, Kit.sphere(0.45, 16), Kit.amber(2.5), Vector3(0, 5.6, 0))
	heart.name = "Heart"
	core_ring = Kit.add(core, Kit.torus(0.62, 0.7, 32), Kit.glow(Color(1, 0.65, 0.25), 4.0), Vector3(0, 5.6, 0), Vector3(PI / 2.0, 0, 0))
	core_glow = OmniLight3D.new()
	core_glow.light_color = Color(1.0, 0.66, 0.3)
	core_glow.light_energy = 2.5
	core_glow.omni_range = 14.0
	core_glow.position = Vector3(0, 5.6, 0)
	core.add_child(core_glow)
	cam_rig.home = Vector3(c.x, 0, c.y)
	_apply_time_of_day()


# ------------------------------------------------------------------ game lifecycle
func _new_game(seed_value: int, mode: String, snapshot: Dictionary, tutorial: bool) -> void:
	var opts := {"tutorial": tutorial}
	if not snapshot.is_empty():
		opts["snapshot"] = snapshot
	g = Game.new(seed_value, mode, opts)
	for k in meta.get("discovered", []):
		g.discovered[k] = true
	for k in meta.get("elements", []):
		g.discovered_elements[k] = true
	g.undo_enabled = true
	terrain.extra_kind = g.eco.ground_kind
	terrain.setup(g.board)
	last_road_version = g.board.version
	last_ground_version = g.eco.ground_version
	if eco_view == null:
		eco_view = EcoView.new()
		eco_view.name = "Economy"
		add_child(eco_view)
	eco_view.setup(self, g.eco)
	if arsenal_view == null:
		arsenal_view = ArsenalView.new()
		arsenal_view.name = "Arsenal"
		add_child(arsenal_view)
		arsenal_view.setup(self)
	arsenal_view.clear_all()
	kit_slot = -1
	strike_mode = ""
	last_revealed = 0
	_build_core()
	_resync_all()
	selected = {}
	selected_tower = 0
	acc = 0.0


func start_run(mode: String, tutorial: bool) -> void:
	hud.close_modal()
	_new_game(int(Time.get_unix_time_from_system() * 1000.0) & 0x7FFFFFFF, mode, {}, tutorial)
	playing = true
	paused = false
	cam_rig.recentre()
	SaveIO.save_run(g)


func continue_run() -> void:
	var d := SaveIO.load_run()
	if d.is_empty():
		hud.toast("No saved run found", Color(1, 0.6, 0.5))
		return
	hud.close_modal()
	_new_game(int(d.seed), String(d.mode), d.snapshot, false)
	playing = true
	paused = false
	cam_rig.recentre()


func _resync_all() -> void:
	for d in [tower_views, enemy_views, proj_views, road_views, harv_views, tank_views]:
		for k in d:
			if is_instance_valid(d[k]):
				d[k].queue_free()
		d.clear()
	for p in puddle_views:
		p.queue_free()
	puddle_views.clear()
	if arsenal_view != null:
		arsenal_view.clear_all()
	for t in g.towers:
		_tower_view(t)


func _ground_y(x: float, z: float) -> float:
	if g == null:
		return 0.0
	var cx := clampi(floori(x), 0, Bal.GRID_W - 1)
	var cy := clampi(floori(z), 0, Bal.GRID_H - 1)
	return g.board.h(cx, cy) * Kit.LH


# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	if g == null:
		return
	if playing and not paused and not hud.has_modal():
		acc += delta * speed
		var n := 0
		while acc >= Bal.DT and n < MAX_STEPS_PER_FRAME:
			if demo_bot != null:
				demo_bot.act()
			g.step()
			acc -= Bal.DT
			n += 1
			_handle_events(g.drain_events())
		if n == MAX_STEPS_PER_FRAME:
			acc = 0.0
		alpha = clampf(acc / Bal.DT, 0.0, 1.0)
	else:
		_handle_events(g.drain_events())
	if g.board.version != last_road_version or g.eco.ground_version != last_ground_version:
		last_road_version = g.board.version
		last_ground_version = g.eco.ground_version
		terrain.rebuild()
		_build_core()
		eco_view.setup(self, g.eco)
	_sync_reveal(delta)
	_sync_towers()
	_sync_enemies(delta)
	_sync_projectiles()
	_sync_misc(delta)
	eco_view.sync(delta)
	arsenal_view.sync(delta)
	if core != null:
		core.get_node("Heart").scale = Vector3.ONE * (1.0 + 0.06 * sin(Time.get_ticks_msec() * 0.003))
		core_ring.rotation.z += delta * 0.6
		core_glow.light_energy = 2.0 + 1.5 * float(g.integrity) / Bal.BASE_INTEGRITY
	var pan := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if not hud.has_modal():
		var wasd := Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)), float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
		cam_rig.pan_keys(wasd if wasd != Vector2.ZERO else pan, delta)
	if cam_rig.spectator:
		cam_rig.spec_focus = _densest_fight()
	_update_ghost()
	hud.refresh(g)
	_update_selected_card()
	if shot_path != "":
		shot_wait -= delta
		if shot_wait <= 0.0:
			var img := get_viewport().get_texture().get_image()
			img.save_png(shot_path)
			print("hud ", hud.size, " card ", hud.card.position, " ", hud.card.visible, " toasts ", hud.toasts.position, " sel ", selected_tower)
			print("saved ", shot_path)
			get_tree().quit()


# ------------------------------------------------------------------ events -> feedback
func _w(x: float, y: float, lift: float = 0.5) -> Vector3:
	return Vector3(x, _ground_y(x, y) + lift, y)


func _glow_of(color: String) -> Color:
	return Bal.PIECE_GLOW.get(color, Color(1.0, 0.7, 0.35))


func _handle_events(evs: Array) -> void:
	for e in evs:
		match e.t:
			"shot":
				_on_shot(e)
			"bolt":
				var a := _muzzle(e.towerId, e.x1, e.y1) if e.x1 == _tower_x(e.towerId) else _w(e.x1, e.y1, 0.6)
				var b := _w(e.x2, e.y2, 0.6)
				fx.ribbon(a, b, 0.09, Color(0.7, 0.85, 1.0), 0.16, true, 7)
				fx.ribbon(a, b, 0.035, Color(1, 1, 1), 0.12, true, 5)
				fx.burst(b, 5, 3.0, Color(0.7, 0.85, 1.0), 0.06, 0.25)
				_tower_sound(tower_views.get(e.towerId), "bolt", a)
			"aura":
				var tv: TowerView = tower_views.get(e.towerId)
				if tv != null:
					var t := tv.tower
					fx.ring(_w(t.cx, t.cy, 0.15), 0.5, t.stats.range * 0.95, 0.5, Color(0.55, 0.85, 1.0, 0.45))
			"explode":
				var r: float = e.get("r", 1.5)
				fx.explosion(_w(e.x, e.y, 0.3), r, _glow_of(e.get("color", "red")))
				fx.decal(_w(e.x, e.y, 0.03), r * 0.8, Color(0.05, 0.04, 0.04, 0.55), 7.0)
				cam_rig.add_shake(0.12 if not e.get("big", false) else 0.4)
				sfx.play_at("boom", _w(e.x, e.y, 0.5), -4.0 if r < 2.0 else 0.0)
			"impact":
				fx.burst(_w(e.x, e.y, 0.5), 6, 3.5, _glow_of(e.get("color", "gold")), 0.06, 0.3)
			"puddle":
				if e.get("kind", "acid") == "fire":
					fx.burst(_w(e.x, e.y, 0.3), 4, 2.0, Color(1.0, 0.55, 0.15), 0.08, 0.5)
				else:
					fx.burst(_w(e.x, e.y, 0.3), 10, 2.5, Color(0.6, 1.0, 0.3), 0.1, 0.5, "glob")
					sfx.play_at("splat", _w(e.x, e.y, 0.3))
			"hit":
				if e.get("crit", false):
					fx.burst(_w(e.x, e.y, 0.8), 8, 4.0, Color(1, 0.95, 0.6), 0.08, 0.35)
			"spawn":
				pass
			"kill":
				_on_kill(e)
			"combo":
				if e.n >= 3:
					hud.combo(e.n)
				if e.n in [3, 5, 8, 13, 21]:
					sfx.play("combo", 0.0, [3, 5, 8, 13, 21].find(e.n))
			"leak":
				fx.explosion(_w(e.x, e.y, 0.6), 1.6, Color(1, 0.4, 0.3))
				cam_rig.add_shake(0.35)
				sfx.play("leak")
				hud.toast("The base was hit! −%d" % e.dmg, Color(1, 0.55, 0.45), 1.6)
			"place":
				_on_place(e)
			"merged":
				var tv2: TowerView = tower_views.get(e.from)
				if tv2 != null:
					tv2.queue_free()
					tower_views.erase(e.from)
			"activate":
				var tv3: TowerView = tower_views.get(e.towerId)
				if tv3 != null:
					tv3.rebuild()
					tv3.play_activate()
					var t3 := tv3.tower
					fx.ring(_w(t3.cx, t3.cy, 0.1), 0.3, 3.2, 0.6, Color(1, 0.75, 0.35, 0.8))
					fx.burst(_w(t3.cx, t3.cy, 1.2), 24, 5.0, Color(1, 0.8, 0.4), 0.08, 0.6)
				hud.toast("%s online" % e.type, Color(1, 0.82, 0.45))
				sfx.play("activate")
			"bonus":
				hud.toast(e.label, Color(0.55, 1.0, 0.7), 2.0)
			"undo":
				for id in tower_views.keys():
					if g.tower_by_id(id) == null:
						tower_views[id].queue_free()
						tower_views.erase(id)
				for t in g.towers:
					if not tower_views.has(t.id):
						_tower_view(t)
					elif tower_views[t.id].needs_rebuild():
						tower_views[t.id].rebuild()
				_sync_road_pieces(true)
				hud.toast("Undone", Color(0.8, 0.85, 1.0), 1.0)
				sfx.play("undo")
			"reject":
				hud.toast(e.reason, Color(1, 0.6, 0.5), 1.4)
				sfx.play("reject")
			"evolve":
				_on_evolve(e)
			"techUp":
				hud.toast("%s level %d%s" % [Bal.TECH_NAME[e.tech], e.level, _tech_perk_text(e.tech, e.level)], Color(1, 0.85, 0.45), 2.6)
				sfx.play("bell")
			"kitBought":
				hud.toast("%s on the Kit belt" % Bal.KITS[e.kind].name, Color(0.9, 0.85, 0.7), 1.4)
				sfx.play("click")
			"kitBuilt":
				hud.toast("%s built on the base ring" % Bal.KITS[e.kind].name, Color(1, 0.82, 0.45), 1.8)
				sfx.play("bell")
			"kitPlaced":
				var kp := _w(e.x, e.y, 0.1)
				fx.smoke(kp, 6, Color(0.5, 0.45, 0.38, 0.6), 0.25, 0.9, 0.3)
				sfx.play_at("place", kp, -2.0, 1.2)
				sfx.play_at("click", kp, 0.0, 0.8)
			"trap":
				_on_trap(e)
			"shove":
				var sp := _w(e.x, e.y, 1.0)
				if e.timed:
					fx.ring(_w(e.x, e.y, 0.2), 0.4, 3.0, 0.5, Color(1, 0.85, 0.35, 0.9))
					sfx.play_at("chime", sp, 0.0, 1.0 + 0.1 * e.amp)
				else:
					fx.ring(_w(e.x, e.y, 0.2), 0.3, 1.8, 0.35, Color(0.9, 0.9, 1.0, 0.5))
					sfx.play_at("tap", sp)
			"tick":
				var tp2 := _w(e.x, e.y, 1.6)
				var steps := [0, 2, 4, 5, 7, 9]
				var st: int = steps[clampi(int(e.amp * 5.0), 0, 5)]
				sfx.play_at("tick", tp2, -6.0 + 4.0 * minf(1.0, e.amp), pow(2.0, (st + (0 if e.side > 0 else -5)) / 12.0))
				var mc: Color = ArsenalView.KIND_COLOR.get(e.kind, Color.WHITE)
				fx.ring(_w(e.x, e.y, 0.15), 0.6, Bal.METRONOME.radius * minf(1.0, e.amp + 0.3), 0.45, Color(mc.r, mc.g, mc.b, 0.35 + 0.3 * minf(1.0, e.amp)))
				if e.kind == "thunder":
					cam_rig.add_shake(0.05 * e.amp)
			"howitzer":
				var mz := arsenal_view.fire_howitzer(e.pad)
				if mz != Vector3.ZERO:
					fx.burst(mz, 16, 7.0, Color(1, 0.75, 0.35), 0.12, 0.3)
					fx.smoke(mz, 8, Color(0.55, 0.52, 0.5, 0.6), 0.4, 1.6, 0.6)
				fx.ring(_w(e.x, e.y, 0.1), 0.5, 4.5, 0.6, Color(0.7, 0.62, 0.5, 0.5))
				cam_rig.add_shake(0.2)
				sfx.play_at("boom", _w(e.x, e.y, 0.5), 2.0, 0.6)
				get_tree().create_timer(maxf(0.1, e.dur / speed - 0.9)).timeout.connect(func(): sfx.play_at("whistle", _w(e.tx, e.ty, 6.0)))
			"shellHit":
				fx.mushroom(_w(e.x, e.y, 0.1), e.r)
				cam_rig.add_shake(0.5)
				sfx.play_at("boom", _w(e.x, e.y, 0.5), 4.0, 0.7)
				get_tree().create_timer(0.35).timeout.connect(func(): sfx.play_at("thunder", _w(e.x, e.y, 0.5), -6.0, 0.6))
			"blast":
				var bp := _w(e.x, e.y, 0.2)
				if e.kind == "orbital":
					fx.beam(bp, 1.0)
					fx.explosion(bp, e.r * 1.4, Color(0.7, 0.85, 1.0))
					fx.ring(bp, e.r, Bal.ORBITAL.r1, Bal.ORBITAL.delay, Color(0.75, 0.9, 1.0, 0.9))
					cam_rig.add_shake(1.0)
					sfx.play_at("orbital", bp, 4.0)
				else:
					fx.explosion(bp, e.r, Color(1, 0.6, 0.3))
					sfx.play_at("boom", bp, -3.0, randf_range(0.9, 1.2))
					cam_rig.add_shake(0.12)
			"airstrike":
				_on_airstrike(e)
			"orbital":
				var op := _w(e.x, e.y, 0.15)
				fx.ring(op, Bal.ORBITAL.r1 * 1.2, Bal.ORBITAL.r0 * 0.5, e.delay, Color(0.6, 0.85, 1.0, 0.95))
				fx.ribbon(op + Vector3(0, 70, 0), op, 0.15, Color(0.7, 0.9, 1.0, 0.8), e.delay)
				strike_mode = ""
			"strikeReady":
				hud.toast(("Orbital strike ready (O)" if e.kind == "orbital" else "Air strike ready (X)"), Color(0.7, 0.9, 1.0), 1.8)
				sfx.play("bell", -4.0)
			"ramFire":
				var rp2 := _w(e.x, e.y, 1.1)
				fx.smoke(rp2, 8, Color(0.6, 0.6, 0.62, 0.6), 0.3, 1.2, 0.5)
				sfx.play_at("missile", rp2, 0.0, 0.8 if e.variant == "impact" else 1.2)
			"ramHit":
				if e.get("fizzle", false):
					fx.smoke(_w(e.x, e.y, 0.3), 6)
				else:
					fx.explosion(_w(e.x, e.y, 0.3), e.r, Color(1, 0.6, 0.25))
					cam_rig.add_shake(0.3)
					sfx.play_at("boom", _w(e.x, e.y, 0.5), 2.0)
			"stun":
				fx.ring(_w(e.x, e.y, 0.9), 0.2, 0.7, 0.3, Color(0.75, 0.9, 1.0, 0.8), false)
			"mine":
				fx.explosion(_w(e.x, e.y, 0.2), 1.3, Color(1, 0.55, 0.3))
				sfx.play_at("boom", _w(e.x, e.y, 0.2), -3.0)
				cam_rig.add_shake(0.15)
			"barrierBreak":
				fx.burst(_w(e.x, e.y, 0.6), 18, 4.0, Color(0.55, 0.55, 0.6), 0.12, 0.7, "debris", 10.0)
				_sync_road_pieces(true)
			"destroyed":
				fx.burst(_w(e.x, e.y, 0.6), 30, 6.0, Color(0.5, 0.5, 0.55), 0.14, 0.9, "debris", 10.0)
				fx.smoke(_w(e.x, e.y, 0.4), 10)
				_resync_all()
			"strike":
				cam_rig.add_shake(0.3)
			"phase":
				_on_phase(e.phase)
			"waveStart":
				hud.toast("Wave %d" % e.index, Color(1, 0.8, 0.45), 1.6)
				sfx.play("wave", -4.0)
				sfx.set_wave(true)
			"early":
				hud.toast("Early call: +%d ◆" % int(Bal.EARLY_CALL_BONUS), Color(1, 0.85, 0.45), 1.6)
				sfx.play("chime")
			"harvest":
				var parts: PackedStringArray = []
				for k in ["ore", "timber", "water"]:
					if e[k] > 0.0:
						parts.append("+%d %s" % [int(e[k]), k])
				hud.toast(", ".join(parts), Color(0.85, 0.75, 0.55), 1.8)
				sfx.play("chime")
			"pop":
				_on_pop(e)
			"treeFell":
				var tp := eco_view._cell_xyz(e.cell, 0.8)
				fx.burst(tp, 14, 2.5, Color(0.3, 0.45, 0.25), 0.08, 0.9, "debris", 4.0)
				sfx.play_at("chop", tp, 0.0, 0.7)
			"pimpleSprout":
				fx.burst(eco_view._cell_xyz(e.cell, 0.1), 6, 1.5, Color(0.4, 0.33, 0.25), 0.06, 0.5, "debris", 8.0)
			"pimpleWither":
				fx.smoke(eco_view._cell_xyz(e.cell, 0.1), 4, Color(0.15, 0.14, 0.13, 0.6), 0.2, 1.0, 0.4)
			"lanceUp":
				hud.toast("Lance level %d: %d charges per wave" % [e.level, g.eco.lance_charges_max()], Color(1, 0.85, 0.45))
				sfx.play("bell")
			"discover":
				hud.toast("New element: %s" % e.element, Color(0.7, 0.9, 1.0), 2.0)
			"loot":
				fx.burst(_w(e.x, e.y, 0.8), 30, 5.0, Color(1, 0.85, 0.3), 0.1, 0.9)
				sfx.play("chime", 0.0, 2)
				hud.toast("Loot: +%d ◆ +%d ore" % [int(e.essence), int(e.ore)], Color(1, 0.85, 0.4))
			"champion":
				hud.toast("A champion approaches", Color(1, 0.6, 0.4), 2.0)
			"build":
				hud.toast("%s built" % Bal.BUILDINGS[e.id].name, Color(1, 0.82, 0.45))
				sfx.play("bell")
			"recycle":
				hud.toast("+%d ◆" % int(e.essence), Color(1, 0.85, 0.45), 1.0)


func _tech_perk_text(tech: String, lv: int) -> String:
	if lv == 2:
		return {"steam": ": casings and shells +10%", "aether": ": beams ramp 20% faster", "alchemy": ": puddles last +1 s"}[tech]
	if lv == 5:
		return {"steam": ": Iron Rain (cluster shells)", "aether": ": Lighthouse Grid (linked towers +15%)", "alchemy": ": Bloom (kills leave puddles)"}[tech]
	return ""


func _on_evolve(e: Dictionary) -> void:
	var tv: TowerView = tower_views.get(e.towerId)
	if tv != null:
		tv.hammer_cb = func(v: TowerView):
			var hp := v.global_position + Vector3(v.tower.cx + randf_range(-0.5, 0.5), v.top_y + randf_range(0.3, 1.2), v.tower.cy + randf_range(-0.5, 0.5))
			fx.burst(hp, 5, 3.0, Color(1, 0.8, 0.45), 0.05, 0.25)
			sfx.play_at("tap", hp, -4.0, randf_range(0.8, 1.1))
		tv.rebuild()
	var p := _w(e.x, e.y, 0.2)
	get_tree().create_timer(Bal.PHI / maxf(0.5, speed)).timeout.connect(func():
		fx.ring(p, 0.4, 4.0, 0.6, Color(1, 0.8, 0.4, 0.9))
		fx.burst(p + Vector3(0, 1.5, 0), 36, 6.0, Color(1, 0.85, 0.45), 0.09, 0.7)
		sfx.play_at("activate", p, 0.0, 1.0 + 0.1 * e.mark))
	var t := g.tower_by_id(e.towerId)
	if t != null:
		var bd := Evolve.branch_def(t)
		hud.toast("%s Mk %s%s" % [t.type, ["I", "II", "III", "IV"][e.mark - 1], (": " + bd.name) if not bd.is_empty() else ""], Color(1, 0.85, 0.45), 2.0)


func _on_trap(e: Dictionary) -> void:
	var p := _w(e.x, e.y, 0.2)
	match e.kind:
		"landmine":
			fx.explosion(p, e.r, Color(1, 0.55, 0.3))
			cam_rig.add_shake(0.35)
			sfx.play_at("boom", p, 2.0, 0.9)
		"betty":
			var up := p + Vector3(0, 1.5, 0)
			fx.burst(p, 6, 3.0, Color(0.5, 0.45, 0.4), 0.08, 0.4, "debris", 10.0)
			fx.explosion(up, e.r, Color(1, 0.7, 0.35))
			cam_rig.add_shake(0.25)
			sfx.play_at("boom", up, 0.0, 1.2)
		"claymore":
			for i in 24:
				var a: float = e.dir + randf_range(-0.6, 0.6)
				fx.emit("spark", p + Vector3(0, 0.3, 0), Vector3(cos(a), 0.05, sin(a)) * randf_range(10.0, 16.0), 0.35, 0.05, Color(1, 0.85, 0.5), 2.0)
			fx.smoke(p, 6)
			cam_rig.add_shake(0.2)
			sfx.play_at("boom", p, 0.0, 1.4)
		"spike":
			arsenal_view.spike_punch(e.id)
			fx.burst(_w(e.x, e.y, 0.5), 6, 2.5, Color(0.8, 0.15, 0.15), 0.06, 0.4, "glob", 8.0)
			sfx.play_at("tap", p, -2.0, 1.3)
		"tarFire":
			fx.explosion(p, 2.0, Color(1, 0.5, 0.15))
			sfx.play_at("jet", p, 4.0, 0.6)


func _on_airstrike(e: Dictionary) -> void:
	var dir: float = e.dir
	var d := Vector3(cos(dir), 0, sin(dir))
	var mid := _w(e.x, e.y, 6.0)
	var wing := Node3D.new()
	misc_root.add_child(wing)
	Kit.add(wing, Kit.box(Vector3(1.6, 0.12, 3.2)), Kit.dark_iron())
	Kit.add(wing, Kit.box(Vector3(0.3, 0.1, 3.4)), Kit.glow(Color(1, 0.4, 0.2), 3.0), Vector3(-0.7, 0, 0))
	wing.rotation.y = -dir
	wing.position = mid - d * 40.0
	var tw := wing.create_tween()
	tw.tween_property(wing, "position", mid + d * 40.0, 0.8 / maxf(0.5, speed))
	tw.tween_callback(wing.queue_free)
	sfx.play_at("jet", mid, 4.0)
	strike_mode = ""


## The Lance on the base fires a needle across the map (0.382 s), then the pimple bursts.
func _on_pop(e: Dictionary) -> void:
	var target := eco_view.pimple_world(e.cell)
	var from := core.global_position + Vector3(0, 6.0, 0) if core != null else target + Vector3(0, 10, 0)
	var mid := (from + target) / 2.0 + Vector3(0, from.distance_to(target) * 0.12, 0)
	fx.ribbon(from, mid, 0.06, Color(1, 0.95, 0.8), Bal.T_M)
	fx.ribbon(mid, target, 0.06, Color(1, 0.95, 0.8), Bal.T_M)
	sfx.play("click", -6.0, 1)
	var tw := create_tween()
	tw.tween_interval(Bal.T_M)
	tw.tween_callback(func(): _pop_burst(e, target))


func _pop_burst(e: Dictionary, at: Vector3) -> void:
	var res: String = e.res
	var col: Color = EcoView.RES_COLOR[res]
	if e.black:
		fx.smoke(at, 8, Color(0.12, 0.11, 0.1, 0.7), 0.22, 1.2, 0.6)
		sfx.play_at("tap", at)
	else:
		var big: bool = e.stage == "ripe"
		fx.burst(at, 30 if big else 12, 5.0 if big else 3.0, col, 0.1, 0.8, "glob", 10.0)
		fx.ring(at - Vector3(0, 0.25, 0), 0.2, 1.4 if big else 0.8, 0.4, Color(col.r, col.g, col.b, 0.7))
		fx.smoke(at, 3, Color(0.8, 0.8, 0.82, 0.4), 0.18, 0.6, 0.6)
		sfx.play_at("pop_ripe" if big else "pop_dull", at)
		cam_rig.add_nudge(Vector3(0, -0.12 if big else -0.05, 0))
	var txt := "+%d %s" % [int(e.amount), res] if e.amount > 0 else "nothing left"
	if e.pearl:
		txt += "  and a PEARL!"
		sfx.play("chime", 2.0, 2)
	hud.toast(txt, col.lightened(0.3) if not e.black else Color(0.7, 0.7, 0.72), 1.8)


func _tower_x(id: int) -> float:
	var t := g.tower_by_id(id)
	return t.cx if t != null else -1.0


func _muzzle(tower_id: int, x: float, y: float) -> Vector3:
	var tv: TowerView = tower_views.get(tower_id)
	if tv != null:
		return tv.muzzle_world()
	return _w(x, y, 1.0)


func _on_shot(e: Dictionary) -> void:
	var tv: TowerView = tower_views.get(e.towerId)
	if tv != null:
		tv.on_fire()
	var a := _muzzle(e.towerId, e.x1, e.y1)
	_tower_sound(tv, e.kind, a)
	var b := _w(e.x2, e.y2, 0.6)
	var c := _glow_of(e.color)
	match e.kind:
		"bullet":
			fx.burst(a, 3, 2.0, Color(1, 0.8, 0.45), 0.05, 0.08)
			if tv != null and tv.tower.type in ["Machine Gun", "Gun"]:
				var side := Vector3(randf_range(-1, 1), 2.5, randf_range(-1, 1))
				fx.emit("casing", a - Vector3(0, 0.2, 0), side, 2.5, 1.0, Color.WHITE, 12.0)
		"hitscan":
			fx.emit("casing", a - Vector3(0, 0.2, 0), Vector3(randf_range(-1, 1), 3.0, randf_range(-1, 1)), 3.0, 1.6, Color.WHITE, 12.0)
			fx.ribbon(a, b, 0.05, Color(1, 0.95, 0.75), 0.12)
			fx.burst(a, 6, 3.0, Color(1, 0.85, 0.5), 0.06, 0.12)
			fx.burst(b, 6, 3.0, Color(1, 0.85, 0.5), 0.06, 0.25)
		"beam":
			fx.ribbon(a, b, 0.12, c.lerp(Color(1, 0.3, 0.25), 0.5), 0.07)
			fx.ribbon(a, b, 0.04, Color(1, 0.95, 0.9), 0.06)
			if randf() < 0.3:
				fx.burst(b, 2, 1.5, c, 0.05, 0.2)
		"pierce":
			fx.ribbon(a, b, 0.22, Color(0.75, 0.55, 1.0), 0.25)
			fx.ribbon(a, b, 0.07, Color(1, 1, 1), 0.18)
		"cone":
			var dir := (b - a)
			for i in 6:
				var v := dir.normalized() * randf_range(5.0, 9.0) + Vector3(randf_range(-1, 1), randf_range(0.0, 1.2), randf_range(-1, 1)) * 1.6
				fx.emit("spark", a, v, randf_range(0.25, 0.45), randf_range(0.12, 0.22), Color(1.0, randf_range(0.35, 0.6), 0.15), -1.5, 1.5, 1.2)
			if randf() < 0.3:
				fx.smoke(a + (b - a) * 0.6, 1, Color(0.3, 0.3, 0.32, 0.4), 0.3, 1.0, 1.2)
		"lob", "puddle":
			fx.smoke(a, 3, Color(0.6, 0.6, 0.62, 0.5), 0.18, 0.7, 0.6)
			fx.burst(a, 4, 2.0, Color(1, 0.7, 0.35), 0.07, 0.12)
		"homing":
			fx.smoke(a, 2, Color(0.7, 0.7, 0.72, 0.5), 0.15, 0.6, 0.3)
		"virus":
			fx.ribbon(a, b, 0.06, Color(0.6, 1.0, 0.4), 0.2, true, 3)
			fx.burst(b, 6, 1.5, Color(0.6, 1.0, 0.4), 0.07, 0.4, "glob", 1.0)
		"ricochet", "tank":
			fx.ribbon(a if e.kind == "tank" else _w(e.x1, e.y1, 0.6), b, 0.05, Color(1, 0.85, 0.4), 0.1)
		_:
			fx.burst(a, 3, 2.0, c, 0.05, 0.1)


func _tower_sound(tv: TowerView, kind: String, at: Vector3) -> void:
	var type := tv.tower.type if tv != null else ("Gun" if kind == "tank" else "")
	var snd: String = Sfx.TOWER_SOUND.get(type, "")
	if snd == "":
		return
	var id := tv.tower.id if tv != null else -1
	var now := Time.get_ticks_msec()
	var gap := 70 if snd in ["mg", "laser", "flame", "efield"] else 30
	if now - int(shot_sound_t.get(id, 0)) < gap:
		return
	shot_sound_t[id] = now
	sfx.play_at(snd, at)


func _on_kill(e: Dictionary) -> void:
	var p := _w(e.x, e.y, 0.5)
	var col := EnemyView.suit_color(e.suit, e.size)
	var big: bool = e.size in ["large", "giant", "champion", "boss"]
	var n := 26 if big else 12
	fx.burst(p, n, 4.5 if big else 3.5, col, 0.14 if big else 0.1, 0.7, "glob", 9.0)
	fx.burst(p + Vector3(0, 0.3, 0), 6, 3.0, Color(1, 0.9, 0.6), 0.05, 0.3)
	fx.decal(_w(e.x, e.y, 0.02), 0.5 if not big else 1.2, Color(col.r * 0.5, col.g * 0.5, col.b * 0.5, 0.55), 5.0)
	sfx.play_at("kill_big" if big else "kill", p)
	if big:
		cam_rig.add_shake(0.25)
	var ev: EnemyView = enemy_views.get(e.id)
	if ev != null:
		ev.queue_free()
		enemy_views.erase(e.id)


func _on_place(e: Dictionary) -> void:
	var col := _glow_of(e.color)
	var sum := Vector2.ZERO
	for c in e.cells:
		sum += Vector2(c.x + 0.5, c.y + 0.5)
	var ctr: Vector2 = sum / float(e.cells.size())
	var p := _w(ctr.x, ctr.y, 0.3)
	fx.burst(p, 10, 2.5, col, 0.07, 0.4)
	fx.smoke(p, 4, Color(0.6, 0.58, 0.55, 0.45), 0.2, 0.8, 0.4)
	cam_rig.add_nudge(Vector3(0, -0.15, 0))
	sfx.play_at("place", p, 0.0, 1.0 + 0.1 * (4 - mini(4, e.size)) * 0.5)
	match e.kind:
		"tower", "story":
			var t := g.tower_by_id(e.towerId)
			if t != null:
				if tower_views.has(t.id):
					tower_views[t.id].rebuild()
				else:
					_tower_view(t)
		"barrier", "mine":
			_sync_road_pieces(true)
		"harvester":
			sfx.play_at("chime", p, -6.0)


func _on_phase(p: String) -> void:
	if p != "wave":
		sfx.set_wave(false)
	if demo_bot != null:
		if p == "reveal":
			last_revealed = 0
			_resync_all()
		return
	match p:
		"calm":
			if g.wave_index == 0:
				hud.toast("Board %d" % g.board_no, Color(1, 0.82, 0.45), 2.0)
				if g.base.freeTech and playing:
					open_tech()
		"cleared":
			_sync_road_pieces(true)
			SaveIO.log_metrics(g.metrics)
			_cleared_screen()
		"base":
			_base_screen()
		"reveal":
			last_revealed = 0
			_resync_all()
			_build_core()
			if playing:
				SaveIO.save_run(g)
				meta.discovered = g.discovered.keys()
				meta.elements = g.discovered_elements.keys()
				SaveIO.save_meta(meta)
		"lost":
			SaveIO.log_metrics(g.metrics)
			_lost_screen()
		"victory":
			SaveIO.log_metrics(g.metrics)
			SaveIO.clear_run()
			_victory_screen()


# ------------------------------------------------------------------ road reveal: lightning
func _macro_centre(m: int) -> Vector2:
	var v := Board.mxy(m)
	return Vector2(v.x * Bal.MACRO + Bal.MACRO / 2.0, v.y * Bal.MACRO + Bal.MACRO / 2.0)


func _sync_reveal(delta: float) -> void:
	if g.phase != "reveal" or g.board.pending.is_empty():
		return
	var pend: Dictionary = g.board.pending
	var rv: int = pend.revealed
	bolt_t -= delta
	if rv > last_revealed:
		for i in range(maxi(1, last_revealed), rv):
			var a: Vector2 = pend.start if i == 1 else _macro_centre(pend.path[i - 2])
			if i - 1 < pend.path.size():
				var b := _macro_centre(pend.path[i - 1])
				_strike(a, b)
		last_revealed = rv
	if bolt_t <= 0.0 and rv >= 1:
		bolt_t = 0.12
		var k := randi_range(0, rv - 1)
		var a2: Vector2 = pend.start if k == 0 else _macro_centre(pend.path[k - 1])
		var b2 := _macro_centre(pend.path[mini(k, pend.path.size() - 1)])
		fx.ribbon(_w(a2.x, a2.y, 0.3), _w(b2.x, b2.y, 0.3), 0.08, Color(0.75, 0.85, 1.0, 0.7), 0.1, true, 9)


func _strike(a: Vector2, b: Vector2) -> void:
	var pa := _w(a.x, a.y, 0.2)
	var pb := _w(b.x, b.y, 0.2)
	fx.ribbon(pb + Vector3(0, 40, 0), pb, 0.5, Color(0.8, 0.9, 1.0), 0.25, true, 12)
	fx.ribbon(pa, pb, 0.25, Color(0.7, 0.85, 1.0), 0.35, true, 14)
	fx.burst(pb, 30, 7.0, Color(0.8, 0.9, 1.0), 0.08, 0.5)
	fx.smoke(pb, 8, Color(0.4, 0.42, 0.48, 0.5), 0.5, 1.6, 0.7)
	fx.decal(pb, 1.4, Color(0.05, 0.05, 0.07, 0.6), 3.0)
	cam_rig.add_shake(0.25)
	sfx.play_at("thunder", pb)


# ------------------------------------------------------------------ view sync
func _tower_view(t: SimTower) -> TowerView:
	var tv := TowerView.new()
	tower_root.add_child(tv)
	tv.setup(t, terrain)
	tower_views[t.id] = tv
	return tv


func _sync_towers() -> void:
	for t in g.towers:
		var tv: TowerView = tower_views.get(t.id)
		if tv == null:
			_tower_view(t)
		elif tv.needs_rebuild():
			tv.rebuild()
	if tower_views.size() > g.towers.size():
		for id in tower_views.keys():
			if g.tower_by_id(id) == null:
				tower_views[id].queue_free()
				tower_views.erase(id)


func _sync_enemies(delta: float) -> void:
	var seen := {}
	for e in g.enemies:
		seen[e.id] = true
		var ev: EnemyView = enemy_views.get(e.id)
		if ev == null:
			ev = EnemyView.new()
			enemy_root.add_child(ev)
			ev.setup(e, terrain)
			enemy_views[e.id] = ev
		ev.sync(alpha, delta)
	if enemy_views.size() > seen.size():
		for id in enemy_views.keys():
			if not seen.has(id):
				var ev2: EnemyView = enemy_views[id]
				if ev2.e != null and ev2.e.leaked:
					pass
				ev2.queue_free()
				enemy_views.erase(id)


func _proj_mesh(p: SimProjectile) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	match p.kind:
		"bullet":
			m.mesh = Kit.sphere(0.07, 6)
			m.material_override = Kit.glow(Color(1, 0.8, 0.45), 4.0)
		"homing":
			m.mesh = Kit.cylinder(0.06, 0.08, 0.45, 6)
			m.material_override = Kit.iron()
			var flame := Kit.add(m, Kit.sphere(0.09, 6), Kit.glow(Color(1, 0.6, 0.2), 6.0), Vector3(0, -0.28, 0))
			flame.name = "Flame"
		"lob":
			m.mesh = Kit.sphere(0.18, 10)
			m.material_override = Kit.dark_iron()
			Kit.add(m, Kit.sphere(0.05, 6), Kit.glow(Color(1, 0.6, 0.25), 6.0), Vector3(0, 0.17, 0))
		"acid":
			m.mesh = Kit.sphere(0.16, 10)
			m.material_override = Kit.glow(Color(0.55, 1.0, 0.3), 2.5)
		_:
			m.mesh = Kit.sphere(0.08, 6)
			m.material_override = Kit.glow(_glow_of(p.color), 3.0)
	proj_root.add_child(m)
	return m


func _sync_projectiles() -> void:
	var seen := {}
	for p in g.projectiles:
		seen[p.id] = true
		var m: MeshInstance3D = proj_views.get(p.id)
		if m == null:
			m = _proj_mesh(p)
			proj_views[p.id] = m
		var x := lerpf(p.px, p.x, alpha)
		var y := lerpf(p.py, p.y, alpha)
		var lift := 0.7
		if p.kind == "lob" or p.kind == "acid":
			var k := clampf(p.t / maxf(p.dur, 0.001), 0.0, 1.0)
			lift = 0.7 + sin(k * PI) * (2.0 + p.dur * 2.0)
		var pos := _w(x, y, lift)
		var prev: Vector3 = m.position
		m.position = pos
		if p.kind == "homing" and prev.distance_squared_to(pos) > 1e-6:
			m.look_at(pos + (pos - prev), Vector3.UP)
			m.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
			if randf() < 0.5:
				fx.emit("puff", pos, Vector3(0, 0.4, 0), 0.6, 0.12, Color(0.75, 0.75, 0.78, 0.45), 0.0, 1.0, 1.5)
		elif p.kind == "bullet" and randf() < 0.25:
			fx.ribbon(prev, pos, 0.03, Color(1, 0.8, 0.45, 0.6), 0.05)
	if proj_views.size() > seen.size():
		for id in proj_views.keys():
			if not seen.has(id):
				proj_views[id].queue_free()
				proj_views.erase(id)


func _sync_road_pieces(force: bool = false) -> void:
	var seen := {}
	for rp in g.road_pieces:
		seen[rp.id] = true
		if road_views.has(rp.id) and not force:
			continue
		if road_views.has(rp.id):
			continue
		var n := Node3D.new()
		misc_root.add_child(n)
		road_views[rp.id] = n
		for c in rp.cells:
			var base := _w(c.x + 0.5, c.y + 0.5, 0.0)
			if rp.kind == "barrier":
				Kit.add(n, Kit.bevel_box(Vector3(0.92, 0.7, 0.92), 0.08), Kit.stone(Color(0.26, 0.27, 0.3)), base + Vector3(0, 0.35, 0))
				Kit.add(n, Kit.box(Vector3(0.94, 0.06, 0.94)), Kit.dark_iron(), base + Vector3(0, 0.55, 0))
			else:
				var mine := Kit.add(n, Kit.cylinder(0.22, 0.26, 0.12, 10), Kit.dark_iron(), base + Vector3(0, 0.06, 0))
				Kit.add(mine, Kit.sphere(0.05, 6), Kit.glow(Color(1, 0.35, 0.2), 4.0), Vector3(0, 0.08, 0))
	for id in road_views.keys():
		if not seen.has(id):
			road_views[id].queue_free()
			road_views.erase(id)
	# spent mines disappear
	for rp in g.road_pieces:
		if rp.kind == "mine" and road_views.has(rp.id):
			var n2: Node3D = road_views[rp.id]
			for i in mini(n2.get_child_count(), rp.mines.size()):
				(n2.get_child(i) as Node3D).visible = rp.mines[i]


func _sync_harvesters() -> void:
	var seen := {}
	for h in g.harvesters:
		seen[h.id] = true
		if harv_views.has(h.id):
			continue
		var n := Node3D.new()
		misc_root.add_child(n)
		harv_views[h.id] = n
		var mat := Kit.piece_block(h.piece.color, h.piece.golden)
		for c in h.cells:
			var base := _w(c.x + 0.5, c.y + 0.5, 0.0)
			Kit.add(n, Kit.bevel_box(Vector3(0.9, 0.3, 0.9), 0.06), mat, base + Vector3(0, 0.15, 0))
			var drill := Kit.add(n, Kit.cone(0.18, 0.5, 8), Kit.brass(), base + Vector3(0, 0.55, 0), Vector3(PI, 0, 0))
			drill.name = "Drill"
	for id in harv_views.keys():
		if not seen.has(id):
			harv_views[id].queue_free()
			harv_views.erase(id)


func _sync_misc(delta: float) -> void:
	_sync_road_pieces()
	# tanks
	var seen := {}
	for k in g.tanks:
		seen[k.id] = true
		var n: Node3D = tank_views.get(k.id)
		if n == null:
			n = Node3D.new()
			misc_root.add_child(n)
			Kit.add(n, Kit.bevel_box(Vector3(0.9, 0.35, 0.6), 0.06), Kit.dark_iron(), Vector3(0, 0.25, 0))
			Kit.add(n, Kit.cylinder(0.2, 0.22, 0.2, 10), Kit.iron(), Vector3(0, 0.5, 0))
			Kit.add(n, Kit.cylinder(0.04, 0.04, 0.5, 6), Kit.iron(), Vector3(0.3, 0.52, 0), Vector3(0, 0, PI / 2.0))
			tank_views[k.id] = n
		n.position = _w(lerpf(k.px, k.x, alpha), lerpf(k.py, k.y, alpha), 0.0)
		n.rotation.y = -k.dir
	for id in tank_views.keys():
		if not seen.has(id):
			tank_views[id].queue_free()
			tank_views.erase(id)
	# acid puddles
	while puddle_views.size() < g.puddles.size():
		var m := MeshInstance3D.new()
		m.mesh = Kit.cylinder(1.0, 1.0, 0.04, 24)
		m.material_override = Kit.glow(Color(0.45, 0.9, 0.2, 0.6), 1.2)
		misc_root.add_child(m)
		puddle_views.append(m)
	for i in puddle_views.size():
		var m2 := puddle_views[i]
		m2.visible = i < g.puddles.size()
		if m2.visible:
			var pd: Dictionary = g.puddles[i]
			m2.position = _w(pd.x, pd.y, 0.04)
			var fire: bool = pd.get("kind", "acid") == "fire"
			if m2.get_meta("fire", false) != fire:
				m2.set_meta("fire", fire)
				m2.material_override = Kit.glow(Color(1.0, 0.45, 0.12, 0.7), 2.5) if fire else Kit.glow(Color(0.45, 0.9, 0.2, 0.6), 1.2)
			var s: float = pd.r * clampf(pd.t / 0.5, 0.2, 1.0)
			m2.scale = Vector3(s, 1, s)


## The point of the densest fight: the enemy with the most others within 6 cells,
## leaning toward the ones closest to the core.
func _densest_fight() -> Vector3:
	if g.enemies.is_empty():
		return cam_rig.home
	var best := g.enemies[0]
	var best_score := -1.0
	var step := maxi(1, g.enemies.size() / 24)
	for i in range(0, g.enemies.size(), step):
		var e := g.enemies[i]
		var n := 0.0
		for j in range(0, g.enemies.size(), step):
			var o := g.enemies[j]
			if absf(o.x - e.x) < 6.0 and absf(o.y - e.y) < 6.0:
				n += 1.0
		var score := n + 3.0 * e.progress()
		if score > best_score:
			best_score = score
			best = e
	return Vector3(best.x, 0, best.y)


# ------------------------------------------------------------------ placement ghost
func _cur_piece() -> Variant:
	if selected.is_empty():
		return null
	return g.get_piece(selected)


func _update_ghost() -> void:
	if kit_slot >= 0 or strike_mode != "":
		_update_kit_ghost()
		return
	var p: Variant = _cur_piece()
	if p == null and not selected.is_empty():
		selected = {}
	var cell := _cell_under(mouse_pos)
	hover = cell
	grid.visible = p != null and playing and cell.x > -100
	if grid.visible:
		grid.position = Vector3(cell.x + 0.5, _ground_y(cell.x + 0.5, cell.y + 0.5) + 0.03, cell.y + 0.5)
	if p == null or not playing or hud.has_modal() or cell.x < -100:
		ghost.visible = false
		var hint_txt := "" if p == null else "[color=#8a93a6]Point at the ground to place[/color]"
		if p == null and Board.in_grid(cell.x, cell.y):
			var pm := g.eco.pimple_at(Board.cell_idx(cell.x, cell.y))
			if not pm.is_empty():
				hint_txt = eco_view.pimple_hint(pm)
		hud.set_hint(hint_txt)
		_update_range_preview(null)
		return
	var sig := "%d|%d|%s|%d,%d|%d" % [p.id, rot, str(mirror), cell.x, cell.y, g.towers.size() + g.board.version * 1000]
	ghost.visible = true
	if sig == ghost_sig:
		return
	ghost_sig = sig
	for c in ghost.get_children():
		c.queue_free()
	var pv := g.preview(p, rot, mirror, cell.x, cell.y)
	var ok: bool = pv.get("ok", false)
	var mat := Kit.ghost_mat(ok)
	var body := Kit.piece_block(p.color, p.golden) if ok else mat
	for c in pv.get("cells", []):
		var top := 0.0
		if Board.in_grid(c.x, c.y):
			top = g.board.h(c.x, c.y) * Kit.LH
			var tid := g.tower_at[Board.cell_idx(c.x, c.y)]
			if tid != 0 and pv.get("kind", "") == "story":
				var t := g.tower_by_id(tid)
				if t != null:
					top += g.level_at(t, c.x, c.y) * Kit.BLOCK_H
		Kit.add(ghost, Kit.bevel_box(Vector3(0.94, Kit.BLOCK_H, 0.94), 0.05), mat if not ok else body, Vector3(c.x + 0.5, top + Kit.BLOCK_H * 0.5 + 0.02, c.y + 0.5))
		if ok:
			var gm := Kit.add(ghost, Kit.box(Vector3(0.98, 0.03, 0.98)), Kit.unshaded(Color(1, 0.8, 0.4, 0.35), true), Vector3(c.x + 0.5, top + 0.02, c.y + 0.5))
			gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in ghost.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).transparency = 0.35 if ok else 0.45
	# hint text: what this placement will do
	var txt := ""
	if not ok:
		txt = "[color=#ff8a7a]%s[/color]" % pv.get("reason", "Can't place here")
	else:
		match pv.get("kind", ""):
			"tower":
				if pv.resultType != "":
					txt = "[b]%s[/b]  [color=#8a93a6]%s · DPS %.0f · range %.1f[/color]" % [pv.resultType, pv.hint, pv.dps, pv.range]
				else:
					txt = "Pile: %d more core piece%s to make a tower" % [pv.needs, "" if pv.needs == 1 else "s"]
			"story":
				txt = "[b]Story %d[/b] on %s  [color=#8a93a6]DPS %.0f · range %.1f[/color]" % [pv.get("layer", 1) + 1, pv.get("resultType", ""), pv.get("dps", 0.0), pv.get("range", 0.0)]
			_:
				txt = ", ".join(pv.get("gained", []))
		var extra: PackedStringArray = []
		for s in pv.get("gained", []):
			if pv.get("kind", "") in ["tower", "story"]:
				extra.append("[color=#7dffb0]+ %s[/color]" % s)
		for s in pv.get("lost", []):
			extra.append("[color=#ff8a7a]− %s[/color]" % s)
		if not extra.is_empty():
			txt += "\n" + "   ".join(extra)
	hud.set_hint(txt + "\n[color=#8a93a6]R rotate · F mirror · H hold · right-click a slot to hold[/color]")
	_update_range_preview(pv if ok else null)


func _update_kit_ghost() -> void:
	var cell := _cell_under(mouse_pos)
	grid.visible = false
	if strike_mode != "":
		ghost.visible = false
		if strike_mode == "orbital":
			hud.set_hint("[b]Orbital strike[/b]: click a target  [color=#8a93a6]55 × unit HP at the centre, a ring out to 8 cells · right-click cancels[/color]")
			var hit: Variant = cam_rig.ground_at(mouse_pos, 0.0)
			if hit != null:
				_show_ring(Vector2(hit.x, hit.z), Bal.ORBITAL.r1)
		else:
			hud.set_hint("[b]Air strike[/b]: press on a point and drag to set the direction  [color=#8a93a6]13 blasts in a 3 × 13 line · right-click cancels[/color]")
			_show_ring(Vector2(Board.CORE_PT.x, Board.CORE_PT.y), g.arsenal.airstrike_radius())
		return
	if kit_slot >= g.arsenal.belt.size() or g.arsenal.belt[kit_slot] == "":
		kit_slot = -1
		return
	var id: String = g.arsenal.belt[kit_slot]
	var sig := "kit|%s|%d|%d,%d|%d" % [id, kit_rot, cell.x, cell.y, g.board.version]
	ghost.visible = playing and cell.x > -100
	if sig == ghost_sig:
		return
	ghost_sig = sig
	for c in ghost.get_children():
		c.queue_free()
	var pv := g.arsenal.preview(g, id, kit_rot, cell.x, cell.y)
	var mat := Kit.ghost_mat(pv.ok)
	for c in pv.cells:
		var top: float = g.board.h(c.x, c.y) * Kit.LH if Board.in_grid(c.x, c.y) else 0.0
		Kit.add(ghost, Kit.box(Vector3(0.94, 0.12, 0.94)), mat, Vector3(c.x + 0.5, top + 0.08, c.y + 0.5))
	var k: Dictionary = Bal.KITS[id]
	var txt := "[b]%s[/b]  [color=#8a93a6]%s[/color]" % [k.name, k.note]
	if not pv.ok:
		txt = "[color=#ff8a7a]%s[/color]  " % pv.reason + txt
	hud.set_hint(txt + "\n[color=#8a93a6]R rotate · right-click cancels[/color]")
	if id.begins_with("metronome"):
		var c0: Vector2i = pv.cells[0]
		_show_ring(Vector2(c0.x + 1.0, c0.y + 1.0), Bal.METRONOME.radius)
	else:
		range_ring.visible = false


func select_kit(i: int) -> void:
	if i < 0 or i >= g.arsenal.belt.size() or g.arsenal.belt[i] == "":
		return
	selected = {}
	strike_mode = ""
	kit_slot = i if kit_slot != i else -1
	ghost_sig = ""
	sfx.play("click")


func begin_strike(kind: String) -> void:
	var ok: bool = g.can_orbital() if kind == "orbital" else g.can_airstrike()
	if not ok:
		var pad: Dictionary = g.arsenal.orbital_pad() if kind == "orbital" else g.arsenal.airstrike_pad()
		hud.toast(("Build the %s in the Armory first" % Bal.KITS[kind].name) if pad.is_empty() else ("Recharging: %d s" % ceili(pad.cd if kind == "orbital" else Bal.AIRSTRIKE.every - pad.charge)), Color(1, 0.6, 0.5), 1.4)
		return
	selected = {}
	kit_slot = -1
	strike_mode = kind
	sfx.play("click")


func cycle_priority() -> void:
	if selected_tower == 0:
		return
	var pr := g.cycle_priority(selected_tower)
	hud.toast("Target: %s" % Bal.PRIORITY_LABEL.get(pr, pr), Color(0.9, 0.9, 1.0), 1.0)
	sfx.play("click")


func set_all_priority() -> void:
	var t := g.tower_by_id(selected_tower)
	if t == null:
		return
	g.set_priority(t.id, t.priority, true)
	hud.toast("Every %s: %s" % [t.type, Bal.PRIORITY_LABEL.get(t.priority, t.priority)], Color(0.9, 0.9, 1.0), 1.2)


func _effects_text(m: Dictionary) -> String:
	var out: PackedStringArray = []
	for k in m:
		var v: Variant = m[k]
		match k:
			"dmg": out.append("damage ×%.1f" % v)
			"range": out.append("range ×%.2f" % v)
			"rate": out.append("fire rate ×%.1f" % v)
			"pierce": out.append("pierces %d" % v)
			"chain": out.append("chains +%d" % v)
			"salvo": out.append("+%d per salvo" % v)
			"splash": out.append("splash %.1f cells" % v)
			"dot": out.append("damage over time %d%%/s" % roundi(v * 100))
			"slow": out.append("slows to %d%%" % roundi(v[0] * 100))
			"stun": out.append("stuns %.1f s" % v)
			"knock": out.append("knockback %.1f" % v)
			"vuln": out.append("marked: +%d%% damage taken" % roundi(v * 100))
			"buff": out.append("nearby towers +%d%%" % roundi(v * 100))
			"armor": out.append("ignores armour and shields")
			"spread": out.append("spreads on kill")
			"multi": out.append("+%d beams" % v)
			"puddle": out.append("leaves puddles (%.1f)" % v)
			"fire": out.append("sets the road on fire %.0f s" % v)
	return ", ".join(out)


func open_evolve() -> void:
	var t := g.tower_by_id(selected_tower)
	if t == null or t.type == "" or t.mark >= 4:
		return
	var back := func():
		hud.close_modal()
	if t.mark == 1:
		var c := Evolve.cost(t, -1)
		var err := g.evolve_blocked(t.id)
		hud.open_modal("Evolve %s to Mk II" % t.type, "[b]+30%% damage, +10%% range[/b], lanterns and crenellations.\nCost: %s%s" % [Evolve.cost_text(c), ("\n[color=#ff8a7a]%s[/color]" % err) if err != "" else ""], [
			["Evolve", func():
				if g.evolve(t.id) == "":
					hud.close_modal()],
			["Close", back]], 520)
		return
	if t.mark == 3:
		var bd := Evolve.branch_def(t)
		var c3 := Evolve.cost(t, t.branch)
		var err3 := g.evolve_blocked(t.id, t.branch)
		hud.open_modal("Capstone: %s Mk IV" % bd.name, "[color=#ffd9a0]%s[/color]\n%s\nA bigger model ringed with light.\nCost: %s  [color=#8a93a6]needs %s level %d[/color]%s" % [bd.tags, _effects_text(bd.m4), Evolve.cost_text(c3), Bal.TECH_NAME[bd.tech], Bal.EVO.mk4.techLevel, ("\n[color=#ff8a7a]%s[/color]" % err3) if err3 != "" else ""], [
			["Evolve", func():
				if g.evolve(t.id, t.branch) == "":
					hud.close_modal()],
			["Close", back]], 560)
		return
	var vb: VBoxContainer = hud.open_modal("Choose a branch for %s" % t.type, "[color=#8a93a6]The choice is permanent for this tower. Mk III gives 1 tech point; Mk IV gives 2.[/color]", [["Close", back]], 760)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	vb.add_child(hb)
	vb.move_child(hb, 2)
	var bs := Evolve.branches(t.type)
	for i in bs.size():
		var b: Dictionary = bs[i]
		var pc := PanelContainer.new()
		pc.custom_minimum_size = Vector2(360, 0)
		hb.add_child(pc)
		var col := VBoxContainer.new()
		pc.add_child(col)
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		rt.custom_minimum_size = Vector2(340, 0)
		var err2 := g.evolve_blocked(t.id, i)
		rt.text = "[font_size=18][color=%s]%s %s[/color][/font_size]\n[b]%s[/b]\n[color=#ffd9a0]%s[/color]\nMk III: %s\nMk IV: %s\nCost: %s%s" % [Hud.TECH_COLOR[b.tech], Hud.TECH_ICON[b.tech], Bal.TECH_NAME[b.tech], b.name, b.tags, _effects_text(b.m3), _effects_text(b.m4), Evolve.cost_text(Evolve.cost(t, i)), ("\n[color=#ff8a7a]%s[/color]" % err2) if err2 != "" else ""]
		col.add_child(rt)
		var btn := Button.new()
		btn.text = "Evolve to %s" % b.name
		btn.disabled = err2 != ""
		btn.pressed.connect(func():
			if g.evolve(t.id, i) == "":
				hud.close_modal())
		col.add_child(btn)
	hud.call_deferred("_recentre")


func open_tech() -> void:
	var lines: PackedStringArray = []
	for k in Bal.TECHS:
		var pts: int = g.base.tech[k]
		var lv := g.tech_level(k)
		lines.append("[color=%s]%s %s[/color]  level [b]%d[/b]  [color=#8a93a6](%d points%s)[/color]" % [Hud.TECH_COLOR[k], Hud.TECH_ICON[k], Bal.TECH_NAME[k], lv, pts, (", %d to next" % Evolve.points_to_next(pts)) if lv < 5 else ""])
	var body := "\n".join(lines) + "\n\n[color=#8a93a6]Mk III evolutions give 1 point, Mk IV give 2. Levels need 1, 2, 3, 5, 8 points. Level 2 perks, level 5 ultimates.[/color]"
	if g.base.freeTech:
		body = "[color=#ffcf6b]Pick your first technology: it opens at level 1 for free.[/color]\n\n" + body
	var btns: Array = []
	for k in Bal.TECHS:
		var c := g.tech_open_cost(k)
		if c >= 0.0:
			btns.append(["Open %s%s" % [Bal.TECH_NAME[k], "" if c == 0.0 else " (%d ◆)" % int(c)], func():
				var err := g.open_tech(k)
				if err != "":
					hud.toast(err, Color(1, 0.6, 0.5), 1.4)
				else:
					open_tech()])
	btns.append(["Close", func(): hud.close_modal()])
	hud.open_modal("Technologies", body, btns, 640)


func open_armory() -> void:
	var vb: VBoxContainer = hud.open_modal("Armory", "[color=#8a93a6]Road kits go on the Kit belt (Shift+1–6); base-ring kits are built on a pad around the core. %s[/color]" % ("" if g.has_building("armory") else "Build the Armory at the base to unlock everything but Landmines and Spike traps."), [["Close", func(): hud.close_modal()]], 720)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	vb.add_child(grid)
	vb.move_child(grid, 2)
	for id in Bal.KIT_ORDER:
		var k: Dictionary = Bal.KITS[id]
		var l := RichTextLabel.new()
		l.bbcode_enabled = true
		l.fit_content = true
		l.custom_minimum_size = Vector2(420, 0)
		l.text = "[b]%s[/b]  [color=#8a93a6]%s[/color]" % [k.name, k.note]
		grid.add_child(l)
		var cl := Label.new()
		cl.text = Evolve.cost_text(k.cost)
		grid.add_child(cl)
		var b := Button.new()
		var err: String = g.arsenal.kit_blocked(g, id)
		b.text = "Buy" if err == "" else err
		b.disabled = err != ""
		b.pressed.connect(func():
			var e2 := g.buy_kit(id)
			if e2 != "":
				hud.toast(e2, Color(1, 0.6, 0.5), 1.4)
			open_armory())
		grid.add_child(b)
	for i in 6:
		var pd: Dictionary = g.arsenal.pads[i]
		if pd.get("kind", "") != "howitzer":
			continue
		var hb := HBoxContainer.new()
		vb.add_child(hb)
		vb.move_child(hb, vb.get_child_count() - 2)
		var hl := Label.new()
		hl.text = "Howitzer %d:" % (i + 1)
		hb.add_child(hl)
		for u in Arsenal.PAD_UPGRADES:
			var ub := Button.new()
			var info: Dictionary = Arsenal.PAD_UPGRADES[u]
			ub.text = "%s %s" % [info.name, "✓" if pd.get(u, 0) > 0 else "(%d ⬢)" % int(info.cost)]
			ub.tooltip_text = info.note
			ub.disabled = pd.get(u, 0) > 0
			ub.pressed.connect(func():
				var e3: String = g.arsenal.upgrade_pad(g, i, u)
				if e3 != "":
					hud.toast(e3, Color(1, 0.6, 0.5), 1.4)
				open_armory())
			hb.add_child(ub)
	hud.call_deferred("_recentre")


func _update_range_preview(pv: Variant) -> void:
	if pv != null and pv.get("range", 0.0) > 0.0:
		var c := Vector2.ZERO
		for cc in pv.cells:
			c += Vector2(cc.x + 0.5, cc.y + 0.5)
		c /= float(pv.cells.size())
		_show_ring(c, pv.range)
	elif selected_tower != 0:
		var t := g.tower_by_id(selected_tower)
		if t != null and not t.stats.is_empty():
			_show_ring(Vector2(t.cx, t.cy), t.stats.range)
		else:
			range_ring.visible = false
	else:
		range_ring.visible = false


func _show_ring(c: Vector2, r: float) -> void:
	range_ring.visible = true
	range_ring.position = _w(c.x, c.y, 0.08)
	range_ring.scale = Vector3(r, 1.0, r)


func _cell_under(screen: Vector2) -> Vector2i:
	# march down terrain levels from the top so raised terraces are hit first
	for lvl in range(4, -1, -1):
		var hit: Variant = cam_rig.ground_at(screen, lvl * Kit.LH)
		if hit == null:
			continue
		var x := floori(hit.x)
		var y := floori(hit.z)
		if Board.in_grid(x, y) and g.board.h(x, y) == lvl:
			return Vector2i(x, y)
	var h0: Variant = cam_rig.ground_at(screen, 0.0)
	if h0 == null:
		return Vector2i(-999, -999)
	return Vector2i(floori(h0.x), floori(h0.z))


# ------------------------------------------------------------------ HUD callbacks
func select_source(s: Dictionary) -> void:
	if g.get_piece(s) == null:
		return
	sfx.play("click")
	if s.zone == "may" and g.may_locked():
		hud.toast("Place your MUST USE pieces first", Color(1, 0.7, 0.5), 1.4)
		return
	if selected == s:
		selected = {}
	else:
		selected = s
		selected_tower = 0
		hud.hide_card()
	ghost_sig = ""


func hold_swap(s: Dictionary) -> void:
	if g.hold_swap(s):
		selected = {}
		ghost_sig = ""


func discard_selected() -> void:
	if selected.is_empty():
		return
	var ok := g.recycle(selected) if g.can_recycle() else g.discard(selected)
	if ok:
		selected = {}
		ghost_sig = ""


func call_ready() -> void:
	if g.phase == "calm":
		sfx.play("click", 0.0, 2)
		g.ready()


func set_speed(s: float) -> void:
	speed = s
	settings.speed = s
	SaveIO.save_settings(settings)


func toggle_pause() -> void:
	if hud.has_modal():
		return
	paused = true
	_pause_screen()


func _update_selected_card() -> void:
	if selected_tower != 0:
		var t := g.tower_by_id(selected_tower)
		if t == null:
			selected_tower = 0
			hud.hide_card()
		else:
			hud.show_tower(t, g)


# ------------------------------------------------------------------ input
func _unhandled_input(ev: InputEvent) -> void:
	if g == null:
		return
	if ev is InputEventMouseMotion:
		mouse_pos = ev.position
		if pan_drag:
			cam_rig.pan(ev.relative)
			pan_moved += ev.relative.length()
		return
	if ev is InputEventMouseButton and cam_rig.spectator and ev.pressed:
		cam_rig.spectator = false
	if ev is InputEventMouseButton:
		mouse_pos = ev.position
		match ev.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if ev.pressed:
					cam_rig.zoom_at(0.88, ev.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if ev.pressed:
					cam_rig.zoom_at(1.0 / 0.88, ev.position)
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				if ev.pressed:
					pan_drag = true
					pan_moved = 0.0
				else:
					pan_drag = false
					if pan_moved < 6.0 and ev.button_index == MOUSE_BUTTON_RIGHT:
						_cancel()
			MOUSE_BUTTON_LEFT:
				if ev.pressed and playing and not hud.has_modal():
					_click(ev.position)
				elif not ev.pressed and strike_mode == "airstrike" and strike_press != null:
					var hit: Variant = cam_rig.ground_at(ev.position, 0.0)
					var a: Vector2 = strike_press
					var dir := 0.0
					if hit != null and Vector2(hit.x, hit.z).distance_to(a) > 1.5:
						dir = (Vector2(hit.x, hit.z) - a).angle()
					else:
						dir = g.arsenal._road_dir(g, a.x, a.y)
					strike_press = null
					if not g.airstrike(a.x, a.y, dir):
						hud.toast("Out of air-strike range" if g.can_airstrike() else "Air strike not ready", Color(1, 0.6, 0.5), 1.2)
						strike_mode = ""
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		_key(ev.keycode)


func _click(pos: Vector2) -> void:
	var cell := _cell_under(pos)
	if strike_mode != "":
		var hit: Variant = cam_rig.ground_at(pos, 0.0)
		if hit == null:
			return
		if strike_mode == "orbital":
			if not g.orbital(hit.x, hit.z):
				hud.toast("Orbital strike not ready", Color(1, 0.6, 0.5), 1.2)
				strike_mode = ""
		else:
			strike_press = Vector2(hit.x, hit.z)
		return
	if kit_slot >= 0:
		var res0 := g.place_kit(kit_slot, kit_rot, cell.x, cell.y)
		if res0.get("ok", false):
			kit_slot = -1
			ghost_sig = ""
		return
	# shove a metronome
	if Board.in_grid(cell.x, cell.y):
		var k := g.arsenal.kit_at_cell(Board.cell_idx(cell.x, cell.y))
		if not k.is_empty() and k.has("amp"):
			g.arsenal.shove(g, k.id)
			return
		if not k.is_empty() and k.has("variant"):
			g.arsenal.retool_ram(k.id)
			hud.toast("Ram retooled: %s" % ("impact" if k.variant == "impact" else "grinder"), Color(0.9, 0.85, 0.7), 1.2)
			return
	var p: Variant = _cur_piece()
	if p != null:
		var res := g.place(selected, rot, mirror, cell.x, cell.y)
		if res.get("ok", false):
			ghost_sig = ""
			if g.get_piece(selected) == null:
				selected = _auto_next()
		return
	# pop a pimple with the Lance
	if Board.in_grid(cell.x, cell.y):
		var pm := g.eco.pimple_at(Board.cell_idx(cell.x, cell.y))
		if not pm.is_empty():
			if g.eco.lance_level() == 0:
				hud.toast("Build the Resource Lance at the base to pop pimples", Color(1, 0.7, 0.5), 2.0)
			elif g.eco.charges() <= 0:
				hud.toast("The Lance is out of charges until the next wave", Color(1, 0.7, 0.5), 1.6)
			else:
				g.pop_pimple(pm.id)
			return
	# select a tower
	if Board.in_grid(cell.x, cell.y):
		var tid := g.tower_at[Board.cell_idx(cell.x, cell.y)]
		selected_tower = tid
		if tid == 0:
			hud.hide_card()


## After placing, keep the next MUST USE piece in hand so the flow stays fast.
func _auto_next() -> Dictionary:
	if not g.must.is_empty():
		return {"zone": "must", "index": 0}
	return {}


func _cancel() -> void:
	if strike_mode != "":
		strike_mode = ""
		strike_press = null
		return
	if kit_slot >= 0:
		kit_slot = -1
		ghost_sig = ""
		return
	if not selected.is_empty():
		selected = {}
		ghost_sig = ""
	elif selected_tower != 0:
		selected_tower = 0
		hud.hide_card()


func _key(k: Key) -> void:
	if hud.has_modal():
		if k == KEY_ESCAPE and paused:
			_resume()
		return
	if cam_rig.spectator and k != KEY_V:
		cam_rig.spectator = false
	match k:
		KEY_R:
			rot = (rot + 1) % 4
			kit_rot = (kit_rot + 1) % 2
			ghost_sig = ""
		KEY_T:
			cycle_priority()
		KEY_K:
			open_armory()
		KEY_Y:
			open_tech()
		KEY_U:
			open_evolve()
		KEY_O:
			begin_strike("orbital")
		KEY_X:
			begin_strike("airstrike")
		KEY_G:
			var hit: Variant = cam_rig.ground_at(mouse_pos, 0.0)
			if hit != null:
				var mid: int = g.arsenal.nearest_metronome(hit.x, hit.z)
				if mid != 0:
					g.arsenal.shove(g, mid)
		KEY_F:
			mirror = not mirror
			ghost_sig = ""
		KEY_H:
			if not selected.is_empty():
				hold_swap(selected)
			elif g.hold != null:
				select_source({"zone": "hold", "index": 0})
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			call_ready()
		KEY_ESCAPE:
			if g.undo_left() > 0.0:
				g.undo()
			elif not selected.is_empty() or selected_tower != 0:
				_cancel()
			else:
				toggle_pause()
		KEY_P:
			toggle_pause()
		KEY_Q:
			cam_rig.rotate_step(-1)
		KEY_E:
			cam_rig.rotate_step(1)
		KEY_HOME:
			cam_rig.recentre()
		KEY_V:
			cam_rig.spectator = not cam_rig.spectator
			hud.toast("Spectator camera " + ("on" if cam_rig.spectator else "off"), Color(0.8, 0.85, 1.0), 1.2)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6 when Input.is_key_pressed(KEY_SHIFT):
			select_kit(k - KEY_1)
		KEY_1, KEY_2, KEY_3:
			select_source({"zone": "must", "index": k - KEY_1})
		KEY_4, KEY_5, KEY_6, KEY_7:
			select_source({"zone": "may", "index": k - KEY_4})
		KEY_BRACKETLEFT:
			set_speed(SPEEDS[maxi(0, SPEEDS.find(speed) - 1)])
		KEY_BRACKETRIGHT:
			set_speed(SPEEDS[mini(SPEEDS.size() - 1, SPEEDS.find(speed) + 1)])


# ------------------------------------------------------------------ screens
func _title_screen() -> void:
	playing = false
	var has_save := not SaveIO.load_run().is_empty()
	var body := "[color=#c9cfdc]Build towers from falling pieces. Every shape matters.[/color]\n\n[color=#8a93a6]Relaxed: monsters ×0.618 HP · Normal · Golden: ×1.618 HP[/color]"
	var buttons: Array = []
	if has_save:
		buttons.append(["Continue", continue_run])
	buttons.append(["Relaxed", func(): start_run("relaxed", not meta.tutorialDone)])
	buttons.append(["Normal", func(): start_run("normal", not meta.tutorialDone)])
	buttons.append(["Golden", func(): start_run("golden", false)])
	var vb: VBoxContainer = hud.open_modal("Satisfying TD", body, buttons, 560)
	var hb2 := HBoxContainer.new()
	var st := Button.new()
	st.text = "Settings"
	st.pressed.connect(_settings_screen.bind(true))
	hb2.add_child(st)
	var v1 := Button.new()
	v1.text = "Play v1.1 (web)"
	v1.tooltip_text = "The original 2D version"
	v1.pressed.connect(func(): OS.shell_open("https://omnivore99.github.io/TowerDefense/v1/"))
	hb2.add_child(v1)
	vb.add_child(hb2)


func _pause_screen() -> void:
	hud.open_modal("Paused", "[color=#8a93a6]Board %d · wave %d[/color]" % [g.board_no, g.wave_index], [
		["Resume", _resume],
		["Settings", _settings_screen.bind(false)],
		["Restart board", func():
			hud.close_modal()
			paused = false
			g.retry_board()
			_resync_all()],
		["Main menu", func():
			SaveIO.save_run(g)
			_title_screen()],
	])


func _resume() -> void:
	paused = false
	hud.close_modal()


func _settings_screen(from_title: bool) -> void:
	var vb: VBoxContainer = hud.open_modal("Settings", "", [["Done", func():
		SaveIO.save_settings(settings)
		sfx.set_volumes(float(settings.volume), float(settings.music))
		cam_rig.reduced_motion = settings.reducedMotion
		fx.reduced_motion = settings.reducedMotion
		cam_rig.sensitivity = float(settings.camSensitivity)
		if from_title:
			_title_screen()
		else:
			_pause_screen()]], 460)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	vb.add_child(grid)
	vb.move_child(grid, 1)
	for key in ["volume", "music", "camSensitivity"]:
		var l := Label.new()
		l.text = {"volume": "Sound volume", "music": "Music volume", "camSensitivity": "Camera speed"}[key]
		grid.add_child(l)
		var s := HSlider.new()
		s.min_value = 0.0 if key != "camSensitivity" else 0.3
		s.max_value = 1.0 if key != "camSensitivity" else 2.5
		s.step = 0.05
		s.value = float(settings[key])
		s.custom_minimum_size = Vector2(200, 24)
		s.value_changed.connect(func(v: float): settings[key] = v)
		grid.add_child(s)
	for key in ["reducedMotion", "showRanges", "colourBlind"]:
		var l2 := Label.new()
		l2.text = {"reducedMotion": "Reduced motion (no shake)", "showRanges": "Always show ranges", "colourBlind": "Colour-blind glyph marks"}[key]
		grid.add_child(l2)
		var c := CheckBox.new()
		c.button_pressed = bool(settings[key])
		c.toggled.connect(func(v: bool): settings[key] = v)
		grid.add_child(c)


func _cleared_screen() -> void:
	var lost := Bal.BASE_INTEGRITY - g.integrity
	var body := "Base integrity %d / %d%s\nEssence [color=#ffcf6b]%d ◆[/color] · Ore %d\n\n[color=#8a93a6]The next square of your base unlocks.[/color]" % [g.integrity, Bal.BASE_INTEGRITY, "  (−%d)" % lost if lost > 0 else "  flawless!", int(g.base.essence), int(g.base.ore)]
	hud.open_modal("Board %d cleared" % g.board_no, body, [["To the base", func():
		hud.close_modal()
		g.enter_base()]])


func _base_screen() -> void:
	var lv := g.eco.lance_level()
	var lance_txt := ""
	if lv > 0 and lv < Bal.LANCE.charges.size():
		lance_txt = "Upgrade Lance (%d ◆)" % Bal.LANCE.upgrade[lv - 1]
	var vb: VBoxContainer = hud.open_modal("Your base", "Essence [color=#ffcf6b]%d ◆[/color] · Ore %d · Timber %d · Water %d · Pearls %d\n[color=#8a93a6]Ore converts to Essence at %d : 1.[/color]" % [int(g.base.essence), int(g.base.ore), int(g.base.timber), int(g.base.water), int(g.base.pearls), int(Bal.ORE_TO_ESSENCE)], [
		["Convert ore → ◆", func():
			g.convert_ore()
			_base_screen()],
		[lance_txt if lance_txt != "" else "Lance: max level" if lv > 0 else "No Lance yet", func():
			var err := g.upgrade_lance()
			if err != "":
				hud.toast(err, Color(1, 0.6, 0.5), 1.4)
			_base_screen()],
		["Next board ▶", func():
			hud.close_modal()
			g.next_board()],
	], 720)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(grid)
	vb.move_child(grid, 2)
	for i in Bal.BASE_SQUARES.size():
		var sq: Dictionary = Bal.BASE_SQUARES[i]
		var l := Label.new()
		var b: String = g.base.buildings[i]
		if i >= g.base.unlocked:
			l.text = "Square %d (size %d): locked" % [i + 1, sq.size]
			l.add_theme_color_override("font_color", Color(0.5, 0.52, 0.58))
			grid.add_child(l)
			grid.add_child(Control.new())
			continue
		l.text = "Square %d (size %d)%s: %s" % [i + 1, sq.size, " ★" if g.is_harmony(i) else "", Bal.BUILDINGS[b].name if b != "" else "empty"]
		grid.add_child(l)
		if b != "":
			grid.add_child(Control.new())
			continue
		var ob := OptionButton.new()
		ob.add_item("Build…")
		var ids: Array = []
		for id in Bal.BUILDINGS:
			if g.can_build(i, id) == "":
				ob.add_item("%s (%d ◆): %s" % [Bal.BUILDINGS[id].name, Bal.BUILDINGS[id].cost, Bal.BUILDINGS[id].effect])
				ids.append(id)
		ob.disabled = ids.is_empty()
		ob.item_selected.connect(func(idx: int):
			if idx > 0:
				g.build(i, ids[idx - 1])
				_base_screen())
		grid.add_child(ob)


func _lost_screen() -> void:
	hud.open_modal("The base fell", "[color=#8a93a6]Board %d, wave %d. Try the board again from its start: your towers and base come back as they were.[/color]" % [g.board_no, g.wave_index], [
		["Retry board", func():
			hud.close_modal()
			g.retry_board()
			_resync_all()],
		["Main menu", _title_screen],
	])


func _victory_screen() -> void:
	meta.tutorialDone = true
	SaveIO.save_meta(meta)
	hud.open_modal("Victory!", "All %d boards held. [color=#ffcf6b]%d ◆[/color] left in the vault." % [Bal.BOARDS, int(g.base.essence)], [
		["Main menu", _title_screen],
	])
