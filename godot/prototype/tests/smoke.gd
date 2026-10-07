extends Node

var capture_directory = ""

func capture(game: InvestigationPrototype, name: String):
	if capture_directory.is_empty() or DisplayServer.get_name() == "headless": return
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result = get_viewport().get_texture().get_image().save_png(capture_directory.path_join(name+".png"))
	if result != OK: push_error("Cannot capture prototype UI: "+error_string(result))
	print("INVESTIGATION_CAPTURE ",name)

func run(game: InvestigationPrototype):
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--prototype-capture-dir="):
			capture_directory = argument.trim_prefix("--prototype-capture-dir=")
			DirAccess.make_dir_recursive_absolute(capture_directory)
	await get_tree().physics_frame
	var failures = []
	if game.player.enabled or game.ui.mode != "briefing": failures.append("New investigation starts with assignment briefing")
	if game.content.case.briefing.assignment.is_empty(): failures.append("Assignment explains the player's job")
	await capture(game,"01-briefing")
	game.ui.close()
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not game.player.target is InvestigationTarget or game.player.target.logical_id != "oh": failures.append("First NPC is reachable from spawn")
	game.ui._process(0)
	if not game.ui.prompt.text.ends_with("대화"): failures.append("NPC has a contextual interaction hint")
	if game.controls.touch_enabled != game.controls.mobile: failures.append("Mobile defaults to touch and desktop defaults to keyboard")
	if game.controls.mobile:
		await get_tree().process_frame
		await get_tree().process_frame
		var tap = InputEventScreenTouch.new()
		tap.index = 7
		tap.pressed = true
		# Input.parse_input_event takes window pixels; UI targets use stretched
		# viewport coordinates. Android and resized desktop windows differ here.
		tap.position = get_viewport().get_final_transform()*game.controls.button_rects.tool.get_center()
		Input.parse_input_event(tap)
		await get_tree().process_frame
		if game.ui.mode != "dialogue": failures.append("Actual touch event opens the contextual dialogue button")
		tap.pressed = false
		Input.parse_input_event(tap)
		game.ui.close()
	var camera_pose = game.player.camera.global_transform
	game._use("oh","npc",true)
	await game.dialogue_camera_tween.finished
	if game.ui.mode != "dialogue" or game.ui.modal.visible or game.ui.terminal_panel.visible: failures.append("Local dialogue is separate from tablet and terminal")
	if game.ui.dialogue_panel.size.y >= get_viewport().get_visible_rect().size.y*.5: failures.append("Dialogue leaves the scene visible")
	if game.player.enabled or not game.dialogue_camera_active: failures.append("Conversation locks movement and frames the speaker")
	if game.player.camera.global_position.distance_to(camera_pose.origin) > .001: failures.append("Conversation keeps the player's camera position")
	if not is_equal_approx(game.player.camera.fov,68.0): failures.append("Conversation gently adjusts the camera")
	game.ui.dialogue_questions.get_child(0).pressed.emit()
	if "oh_intro" not in game.state.statements or not game.ui.guide_info().title.begins_with("2 / 8"): failures.append("Actual conversation advances the tutorial")
	await capture(game,"02-dialogue")
	game.ui.close()
	if not game.player.camera.global_transform.is_equal_approx(camera_pose): failures.append("Closing dialogue restores the camera")
	game.dispatch({"type":"dialogue","payload":{"id":"park_intro"}})
	var initial = game.state.known.duplicate()
	game._use("server_console","device",false)
	if game.state.known != initial: failures.append("External inspection never awards evidence")
	game._use("server_console","device",true)
	if game.context != "server_console" or game.player.enabled or game.ui.mode != "terminal": failures.append("F opens only the current device terminal")
	game.ui.command_input.text = "status"
	game.ui.execute_command()
	var known_before_ls = game.state.known.duplicate()
	game.ui.command_input.text = "ls"
	game.ui.execute_command()
	if not game.ui.terminal.text.contains("account.txt") or game.state.known != known_before_ls: failures.append("Directory lists files without granting unread evidence")
	if game.engine.parse("cat /etc/passwd",game.context,game.state).type != "invalid": failures.append("Terminal cannot read arbitrary system paths")
	game.ui.command_input.text = "inspect acc"
	var key = InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_TAB
	game.ui._terminal_input(key)
	if game.ui.command_input.text != "inspect account": failures.append("Terminal completes a device command")
	game.ui.execute_command()
	if "E02" not in game.state.evidence: failures.append("Terminal query awards the actual record")
	key.keycode = KEY_UP
	game.ui._terminal_input(key)
	if game.ui.command_input.text != "inspect account": failures.append("Terminal recalls command history")
	game.ui.command_input.text = "logs tasks"
	game.ui.execute_command()
	if not game.ui.guide_info().title.begins_with("4 / 8"): failures.append("Server baseline advances the tutorial")
	var server_output = game.ui.terminal.text
	if not server_output.contains("sec.ops > status"): failures.append("Terminal shows the session transcript")
	await capture(game,"03-terminal")
	game._use("project_pc","device",true)
	var bad = game.dispatch(game.engine.parse("logs access --task T-17",game.context,game.state))
	if bad.code != "WRONG_DEVICE": failures.append("Device command guard remains enforced")
	game._use("server_console","device",true)
	if game.ui.terminal.text != server_output: failures.append("Returning to a device preserves its output")
	game.dispatch({"type":"dialogue","payload":{"id":"han_intro"}})
	game._use("project_pc","device",true)
	game.ui.command_input.text = "inspect files"
	game.ui.execute_command()
	game._use("seo","npc",true)
	for child in game.ui.dialogue_questions.get_children():
		if child is Button and child.text == "유지보수 채널의 이전 제출 보기": failures.append("Messenger-only questions do not appear in local dialogue")
	game.dispatch({"type":"dialogue","payload":{"id":"seo_intro"}})
	game.ui.open_tablet(1)
	game.ui.contact = "seo"
	game.ui.refresh_messenger()
	for child in game.ui.messenger.get_children():
		if child is Button and child.text == "유지보수 채널의 이전 제출 보기": child.pressed.emit(); break
	if "E11" not in game.state.evidence or "message" not in game.state.known: failures.append("Messenger attachment acquires its own source record")
	if game.ui.mode != "tablet" or game.ui.dialogue_panel.visible: failures.append("Messenger is a separate asynchronous screen")
	await capture(game,"04-messenger")
	game._use("approval_archive","device",true)
	game.ui.command_input.text = "cat scope.txt"
	game.ui.execute_command()
	if not game.ui.guide_info().title.begins_with("8 / 8") or not game.engine.missing_work(game.state).is_empty(): failures.append("First-day tutorial finishes only after required work")
	game.ui.open_tablet(0)
	await capture(game,"05-notes")
	game.ui.close()
	if not game.player.enabled: failures.append("Closing the UI restores movement")
	var original_touch = game.controls.touch_enabled
	game.ui.open_tablet(4)
	game.ui.touch_setting.button_pressed = true
	if not game.controls.touch_enabled: failures.append("Settings enable touch without disabling keyboard")
	await capture(game,"07-settings")
	game.ui.close()
	await get_tree().process_frame
	var dimensions = get_viewport().get_visible_rect().size
	var touch = InputEventScreenTouch.new()
	touch.index = 2
	touch.pressed = true
	touch.position = Vector2(150,dimensions.y-150)
	game.controls.handle_touch(touch)
	var drag = InputEventScreenDrag.new()
	drag.index = 2
	drag.position = touch.position+Vector2(0,-85)
	game.controls.handle_touch(drag)
	var moved_from = game.player.global_position
	Input.action_press("forward")
	await get_tree().create_timer(.2).timeout
	Input.action_release("forward")
	var moved = game.player.global_position.distance_to(moved_from)
	if moved < .2 or moved > .75: failures.append("Touch plus keyboard moves the player without doubling speed")
	touch.index = 3
	touch.position = Vector2(dimensions.x*.6,dimensions.y*.5)
	game.controls.handle_touch(touch)
	var yaw = game.player.rotation.y
	drag.index = 3
	drag.relative = Vector2(70,0)
	game.controls.handle_touch(drag)
	if is_equal_approx(yaw,game.player.rotation.y): failures.append("A second finger controls view while the joystick is held")
	touch.index = 2
	touch.pressed = false
	game.controls.handle_touch(touch)
	if not game.player.touch_axes.is_zero_approx() or game.controls.look_finger != 3: failures.append("Releasing movement leaves the other finger active")
	var keyboard = InputEventKey.new()
	keyboard.pressed = true
	keyboard.physical_keycode = KEY_W
	game.controls._input(keyboard)
	if not game.controls.keyboard_seen or not game.controls.touch_enabled: failures.append("Hardware keyboard is detected alongside touch")
	game.ui.open_tablet()
	if game.controls.look_finger != -1 or not game.player.touch_axes.is_zero_approx(): failures.append("Opening UI releases all touch state")
	game.ui.close()
	game.updates._completed(HTTPRequest.RESULT_CANT_CONNECT,0,PackedStringArray(),PackedByteArray())
	if game.updates.busy or not game.player.enabled or game.ui.update_download.visible: failures.append("Update failures leave gameplay available and hide stale downloads")
	game.controls.set_touch(original_touch)
	game.player.global_position = Vector3(0,.01,7)
	game.player.camera.rotation = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	game.ui._process(0)
	if game.ui.prompt.visible: failures.append("Empty field has no permanent control-key list")
	var start = game.player.global_position
	Input.action_press("forward")
	await get_tree().create_timer(.3).timeout
	Input.action_release("forward")
	if game.player.global_position.distance_to(start) < .2: failures.append("Dummy scene movement")
	await capture(game,"06-field")
	game.review_target("server_console") if game.detailed_world else _dummy_server_pose(game)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not game.player.target is InvestigationTarget or game.player.target.logical_id != "server_console": failures.append("Actual device raycast")
	else:
		game.player.tool_requested.emit(game.player.target)
		if game.context != "server_console" or game.ui.mode != "terminal": failures.append("Raycast F captures only its terminal")
	game.ui.open_tablet()
	if game.player.enabled: failures.append("Tablet freezes movement")
	if game.detailed_world:
		game.ui.close()
		if game.investigation_environment.displays.size()!=6: failures.append("All six authored devices have equipment feedback")
		if not game.find_children("*","Label3D",true,false).is_empty(): failures.append("Detailed office has no floating prototype labels")
		for id in game.targets:
			game.review_target(id)
			await get_tree().physics_frame
			await get_tree().physics_frame
			if not game.player.target is InvestigationTarget or game.player.target.logical_id != id:
				failures.append("Detailed office target is reachable: "+id)
		if game.world.doors.is_empty(): failures.append("Detailed office preserves interactive doors")
		else:
			game.player.target = game.world.doors.values()[0]
			game.controls.set_touch(true)
			game.controls._process(0)
			if game.controls.buttons.tool.visible: failures.append("Doors do not offer investigation commands")
			game.controls.set_touch(original_touch)
		# Reuse the completed first-day flow to check real state-driven visuals,
		# without advancing/saving the player's investigation during this review.
		var next = game.engine.step(game.state,{"type":"day.end","payload":{"expectedDay":1,"confirmed":true}}).state
		game.investigation_environment.sync(next)
		var display = game.investigation_environment.displays.server_console.canvas
		if not display.rows.has("자료 서비스 지연"): failures.append("Nightly operations change actual equipment feedback")
		var repaired = game.engine.step(next,game.engine.parse("backup disable B-05","server_console",next)).state
		game.investigation_environment.sync(repaired)
		if not display.rows.has("자료 서비스 정상"): failures.append("Recovery clears actual equipment warning")
		game.investigation_environment.sync(game.state)
		game.ui.open_tablet()
	game.save_now()
	if not game.store.load_state(game.content).has("state"): failures.append("Existing save format accepts the new UI flow")
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
	var summary = {"passed":failures.is_empty(),"failures":failures,"platform":OS.get_name(),"mobile":game.controls.mobile,"touchDefault":original_touch,"keyboardDetected":game.controls.keyboard_seen}
	var report = FileAccess.open("user://prototype-smoke-result.json",FileAccess.WRITE)
	if report != null: report.store_string(JSON.stringify(summary))
	print("INVESTIGATION_SMOKE ",JSON.stringify(summary))
	get_tree().quit(0 if failures.is_empty() else 1)

func _dummy_server_pose(game):
	game.player.global_position = Vector3(0,.01,-2)
	game.player.camera.look_at(Vector3(0,1.2,-3.85))
