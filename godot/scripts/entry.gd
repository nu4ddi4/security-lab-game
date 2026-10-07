extends Node

func _ready():
	var legacy = Array(OS.get_cmdline_user_args()).any(func(a): return a == "--legacy" or a.begins_with("--qa"))
	var path = "res://scenes/main.tscn" if legacy else "res://prototype/main.tscn"
	get_tree().change_scene_to_file.call_deferred(path)
