extends SceneTree
## Loads every script so parse and type errors show up: godot --headless --path game -s res://tools/check.gd

func _init() -> void:
	var bad := 0
	for f in _scan("res://"):
		var s: Variant = load(f)
		if s == null or (s is GDScript and not (s as GDScript).can_instantiate() and not f.ends_with("check.gd")):
			printerr("FAILED: ", f)
			bad += 1
	print("checked scripts, %d failed" % bad)
	quit(1 if bad > 0 else 0)


func _scan(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for sub in d.get_directories():
		if sub.begins_with(".") or sub == "build":
			continue
		out.append_array(_scan(dir.path_join(sub)))
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	return out
