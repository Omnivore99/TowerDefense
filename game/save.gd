class_name SaveIO
extends RefCounted
## user:// JSON saves, versioned. Every file access is wrapped: a corrupt or missing save
## offers "start new run", never a crash. Snapshots are taken at the start of each board.

const VERSION := 2
const RUN_PATH := "user://run.json"
const SETTINGS_PATH := "user://settings.json"
const META_PATH := "user://meta.json"
const METRICS_PATH := "user://metrics.json"


## Convert engine types (Vector2i, Vector2, packed arrays) to plain JSON values, tagged.
static func encode(v: Variant) -> Variant:
	match typeof(v):
		TYPE_VECTOR2I:
			return {"$v2i": [v.x, v.y]}
		TYPE_VECTOR2:
			return {"$v2": [v.x, v.y]}
		TYPE_VECTOR3:
			return {"$v3": [v.x, v.y, v.z]}
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[str(k)] = encode(v[k])
			return d
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_VECTOR2_ARRAY:
			var a := []
			for x in v:
				a.append(encode(x))
			return a
		TYPE_OBJECT:
			return null
	return v


static func decode(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			if v.has("$v2i"):
				return Vector2i(int(v["$v2i"][0]), int(v["$v2i"][1]))
			if v.has("$v2"):
				return Vector2(v["$v2"][0], v["$v2"][1])
			if v.has("$v3"):
				return Vector3(v["$v3"][0], v["$v3"][1], v["$v3"][2])
			var d := {}
			for k in v:
				d[k] = decode(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(decode(x))
			return a
		TYPE_FLOAT:
			# JSON has no ints: restore whole numbers so ids and counts stay ints
			if v == floorf(v) and absf(v) < 9.0e15:
				return int(v)
	return v


static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	var data: Variant = JSON.parse_string(txt)
	return data


static func _write(path: String, data: Variant) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	return true


static func save_run(game: Game) -> void:
	if game == null or game.phase == "victory":
		clear_run()
		return
	var data := {
		"v": VERSION, "seed": game.seed, "mode": game.mode, "board": game.board_snapshot.boardNo,
		"snapshot": encode(game.board_snapshot), "discovered": game.discovered.keys(), "elements": game.discovered_elements.keys(),
		"savedAt": Time.get_unix_time_from_system(),
	}
	_write(RUN_PATH, data)


## Returns {} when there is no usable save.
static func load_run() -> Dictionary:
	var d: Variant = _read(RUN_PATH)
	if not (d is Dictionary) or int(d.get("v", 0)) != VERSION or not d.has("snapshot"):
		return {}
	var out: Dictionary = decode(d)
	return out


static func clear_run() -> void:
	if FileAccess.file_exists(RUN_PATH):
		DirAccess.remove_absolute(RUN_PATH)


static func default_settings() -> Dictionary:
	return {
		"volume": 0.7, "music": 0.5, "reducedMotion": false, "showRanges": false, "speed": 1.0,
		"colourBlind": false, "metronomeAssist": false, "camSensitivity": 1.0, "quality": "high",
	}


static func load_settings() -> Dictionary:
	var s := default_settings()
	var d: Variant = _read(SETTINGS_PATH)
	if d is Dictionary:
		for k in d:
			s[k] = d[k]
	return s


static func save_settings(s: Dictionary) -> void:
	_write(SETTINGS_PATH, s)


static func load_meta() -> Dictionary:
	var m := {"tutorialDone": false, "discovered": [], "elements": []}
	var d: Variant = _read(META_PATH)
	if d is Dictionary:
		for k in d:
			m[k] = d[k]
	return m


static func save_meta(m: Dictionary) -> void:
	_write(META_PATH, m)


static func log_metrics(m: Dictionary) -> void:
	var all: Variant = _read(METRICS_PATH)
	if not (all is Array):
		all = []
	var row: Dictionary = encode(m)
	row["at"] = Time.get_datetime_string_from_system()
	all.append(row)
	if all.size() > 500:
		all = all.slice(all.size() - 500)
	_write(METRICS_PATH, all)


## Export playtest metrics next to the executable / into the user folder; returns the path.
static func export_metrics() -> String:
	var all: Variant = _read(METRICS_PATH)
	var path := OS.get_user_data_dir() + "/playtest-metrics-%d.json" % int(Time.get_unix_time_from_system())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(all if all is Array else [], "  "))
	return path
