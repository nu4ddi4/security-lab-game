extends Node

func run(game: InvestigationPrototype):
	await get_tree().physics_frame
	var failures = []
	if game.player.enabled or not game.ui.modal_open: failures.append("UI freezes movement")
	var initial = game.state.known.duplicate()
	game._use("server_console","device",false)
	if game.state.known != initial: failures.append("E never awards evidence")
	game._use("server_console","device",true)
	if game.context != "server_console" or game.player.enabled: failures.append("F captures context and freezes movement")
	game.command("inspect account")
	if "E02" not in game.state.evidence: failures.append("Terminal query awards actual record")
	game._use("project_pc","device",true)
	var bad = game.dispatch(game.engine.parse("logs access --task T-17",game.context,game.state))
	if bad.code != "WRONG_DEVICE": failures.append("Device guard")
	game.ui.close()
	if not game.player.enabled: failures.append("Close restores movement")
	var start = game.player.global_position
	Input.action_press("forward")
	await get_tree().create_timer(.3).timeout
	Input.action_release("forward")
	if game.player.global_position.distance_to(start) < .2: failures.append("Dummy scene movement")
	game.player.global_position = Vector3(0,.01,-2)
	game.player.camera.look_at(Vector3(0,1.2,-3.85))
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not game.player.target is InvestigationTarget or game.player.target.logical_id != "server_console": failures.append("Actual device raycast")
	else:
		game.player.tool_requested.emit(game.player.target)
		if game.context != "server_console": failures.append("Raycast F context captured")
	game.ui.open_tablet()
	if game.player.enabled: failures.append("Tablet freezes movement")
	game.save_now()
	if not game.store.load_state(game.content).has("state"): failures.append("Separate save loads")
	var path = game.store.directory.path_join("save.json")
	var broken = "{broken-prototype-save"
	var file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(broken)
	file.close()
	if not game.store.load_state(game.content).has("error"): failures.append("Broken save detected")
	if not game.store.preserve(): failures.append("Broken save preserved")
	if FileAccess.get_file_as_string(path) != broken: failures.append("Preservation leaves original intact")
	var copies = Array(DirAccess.get_files_at(game.store.directory))
	if not copies.any(func(name): return name.begins_with("save.preserved.") and FileAccess.get_file_as_string(game.store.directory.path_join(name)) == broken): failures.append("Preserved copy has original bytes")
	game.save_now()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--prototype-capture=") and DisplayServer.get_name() != "headless":
			game.ui.close()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--prototype-capture="))
	print("INVESTIGATION_SMOKE ",JSON.stringify({"passed":failures.is_empty(),"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
