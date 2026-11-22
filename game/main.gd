extends Node
## Entry point. With user args (after --) it runs headless tools instead of the game:
##   godot --headless --path game -- --bots --seeds 8 --mode normal
##   godot --headless --path game -- --tests

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--bots"):
		Harness.run_cli(args)
		get_tree().quit()
		return
	if args.has("--tests"):
		var code := TestRunner.run_all()
		get_tree().quit(code)
		return
	var scene: PackedScene = load("res://view/world.tscn")
	add_child(scene.instantiate())
