extends SceneTree

func _init(): start.call_deferred()

func start():
	root.add_child(load("res://prototype/tests/services.gd").new())
