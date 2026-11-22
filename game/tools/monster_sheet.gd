extends SceneTree
## Contact sheet of the rigged monsters: one column per archetype, rows are move phases,
## then hit and death. Run with a display (xvfb):
##   godot --path game --rendering-driver opengl3 --resolution 1800x1000 -s res://tools/monster_sheet.gd -- out.png

const ARCHS := ["hopper", "crawler", "blob", "slinky", "roller", "tumbler", "swinger", "walker", "beetle", "nautilus", "balloon"]
const ROWS := [["move", 0.0], ["move", 0.2], ["move", 0.45], ["move", 0.7], ["hit", 0.06], ["death", 0.25], ["death", 0.7]]


func _initialize() -> void:
	var out := "monster_sheet.png"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out = args[0]
	var root3 := Node3D.new()
	root.add_child(root3)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.17, 0.22)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.7)
	env.environment.ambient_light_energy = 0.6
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.light_color = Color(1.0, 0.85, 0.65)
	root3.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ROWS.size() * 4.0 + 1.0
	root3.add_child(cam)
	var w := ARCHS.size() * 4.0
	var h := ROWS.size() * 4.0
	cam.look_at_from_position(Vector3(w * 0.5 - 2.0, h * 0.5 + 6.0, 14.0), Vector3(w * 0.5 - 2.0, h * 0.5 - 1.0, 0))
	for ci in ARCHS.size():
		for ri in ROWS.size():
			var arch: String = ARCHS[ci]
			var mats := {"body": Kit.jelly_material(Color("ffa184"), Color("e8432f")), "dark": Kit.dark_iron(),
				"eye": Kit.std("eye_white", Color(0.95, 0.95, 0.92), 0.0, 0.2), "pupil": Kit.std("eye_pupil", Color(0.03, 0.03, 0.05), 0.0, 0.1)}
			var rig := MonsterRig.make(arch, mats)
			if rig == null:
				print("missing ", arch)
				continue
			root3.add_child(rig)
			var s := 0.6 if arch in ["walker", "balloon"] else 1.0
			rig.scale = Vector3.ONE * s
			rig.position = Vector3(ci * 4.0, h - ri * 4.0 - 3.0, 0)
			rig.rotation.y = -0.5
			rig.set_meta("row", ROWS[ri])
	await process_frame
	for rig in root3.get_children():
		if rig is MonsterRig:
			var row: Array = rig.get_meta("row")
			if row[0] == "move":
				rig.pose(row[1], 0.0)
			elif row[0] == "hit":
				rig.pose(0.0, 0.0)
				rig.hit()
				rig.pose(0.0, row[1])
			else:
				rig.die()
				rig.pose(0.0, row[1])
	for i in 6:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out)
	print("saved ", out)
	quit()
