extends Node

var capture_directory = ""
var failures = []

func check(value: bool, message: String):
	if not value: failures.append(message)

func capture(game, name: String):
	if capture_directory.is_empty() or DisplayServer.get_name() == "headless": return
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(capture_directory.path_join(name+".png"))
	print("STAGE_CAPTURE ",name)

func enter(game, command: String):
	if game.ui.mode == "field": game.ui.open_terminal()
	game.ui.command_input.text = command
	game.ui.command_input.text_submitted.emit(command)

func run(game: InvestigationPrototype):
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--prototype-capture-dir="):
			capture_directory = argument.trim_prefix("--prototype-capture-dir=")
			DirAccess.make_dir_recursive_absolute(capture_directory)
	await get_tree().process_frame
	var ui = game.ui as TerminalStagesUI
	check(ui != null and ui.mode == "main_menu" and not game.player.enabled,"Fresh game opens the stage-game main menu")
	await capture(game,"00-main-menu")
	var touch_default = game.controls.touch_enabled
	ui.entry.new_game.pressed.emit()
	check(ui.mode == "intro","New game has one short introduction")
	await capture(game,"01-intro")
	ui.entry.finish_intro()
	check(ui.mode == "field" and game.player.enabled and game.state.stage.index == 1,"Introduction opens the explorable office")
	check(game.player.third_person and game.stage_world.avatar.get_child_count() > 4,"The employee character and third-person camera are present")
	await capture(game,"office-character")
	ui.open_stage_picker()
	check("???" in ui.picks.get_child(1).text,"Unentered stage names are hidden")
	ui.begin_stage()
	enter(game,"sttatus")
	check(game.state.stage.phase == "playing" and ui.burst_count == 0,"First practice stage allows mistakes")
	await capture(game,"02-practice")
	enter(game,"help")
	await get_tree().process_frame
	check(ui.command_input.has_focus(),"Enter preserves terminal focus for the next command")
	check(ui.terminal.get_parsed_text().contains("status"),"Help is terminal output")
	ui.command_input.text = "status"
	ui.command_input.grab_focus()
	await get_tree().process_frame
	var key = InputEventKey.new()
	key.keycode = KEY_ENTER
	key.physical_keycode = KEY_ENTER
	key.pressed = true
	Input.parse_input_event(key.duplicate())
	Input.flush_buffered_events()
	await get_tree().process_frame
	key.pressed = false
	Input.parse_input_event(key.duplicate())
	Input.flush_buffered_events()
	check(game.controls.keyboard_seen and game.state.stage.phase == "clear","Real Enter executes a terminal command and detects a keyboard")
	if game.state.stage.phase != "clear": enter(game,"status")
	await capture(game,"04-clear")
	ui.result_next.pressed.emit()
	check(game.state.stage.index == 2,"One button advances to the next stage")
	var before = game.state.duplicate(true)
	game.dispatch({"type":"stage.select","payload":{"index":6}})
	check(game.state == before,"Uncleared stages cannot be selected")
	enter(game,"cat no-such-file")
	check(game.state.stage.phase == "playing" and ui.burst_count == 0,"Second practice stage still allows mistakes")
	enter(game,"ls")
	check(ui.terminal.text.contains("memo.txt"),"Directory lists the target file")
	enter(game,"cat print.log")
	enter(game,"cat memo.txt")
	check(game.state.stage.phase == "clear","File-reading practice clears")
	ui.next_stage()
	enter(game,"ps")
	enter(game,"cat print.log")
	await capture(game,"03-terminal")
	enter(game,"kill 21")
	check(game.state.stage.phase == "exploded" and ui.burst_count == 1 and not game.player.enabled,"Wrong target from stage three explodes the PC and blocks gameplay")
	check(is_instance_valid(ui.effects) and ui.effects.get_child_count() > 0,"Explosion creates visible debris")
	check(not game.detailed_world or game.stage_world.originals.size() > 0,"Explosion breaks the actual equipment mesh")
	await capture(game,"05-explosion")
	await get_tree().create_timer(.85).timeout
	ui.open_stage_picker()
	ui.picks.get_child(2).pressed.emit()
	check(game.stage_world.originals.is_empty(),"Selecting the failed stage restores its broken equipment")
	check(ui.mode == "field" and game.state.stage.index == 3 and game.state.stage.cleared == [1,2],"Retry immediately restores only the failed stage")
	enter(game,"hlpe")
	check(game.state.stage.phase == "exploded" and game.state.stage.blasts == 2,"A typo also explodes a dangerous PC")
	ui.retry_stage()
	enter(game,"kill 37")
	check(game.state.stage.phase == "clear","Correct process clears the dangerous stage")
	ui.next_stage()
	enter(game,"cat device.cfg")
	enter(game,"cat profiles.txt")
	enter(game,"set temp 24")
	ui.next_stage()
	ui.talk_to("oh")
	check(ui.mode == "stage_dialogue","NPC interaction opens conversation")
	await capture(game,"npc-conversation")
	ui.command_result(game.dispatch({"type":"stage.talk","payload":{"choice":0}}))
	check(game.state.stage.phase == "exploded","A wrong conversation choice can fail outside the terminal")
	ui.retry_stage()
	ui.talk_to("oh")
	ui.command_result(game.dispatch({"type":"stage.talk","payload":{"choice":1}}))
	ui.next_stage()
	check(game.stage_world.course.visible and game.player.enabled,"The final stage opens the rooftop course")
	game.player.global_position.y = 6.8
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(game.state.stage.phase == "exploded","Falling off the course fails the stage")
	ui.retry_stage()
	await capture(game,"roof-course")
	for frame in range(12): await get_tree().physics_frame
	for step in range(1,7):
		Input.action_press("forward")
		Input.action_press("jump")
		await get_tree().physics_frame
		Input.action_release("jump")
		for frame in range(60):
			await get_tree().physics_frame
			if game.player.global_position.x >= step*1.4-.05 or game.state.stage.phase != "playing": break
		Input.action_release("forward")
		for frame in range(30): await get_tree().physics_frame
		check(game.state.stage.phase == "playing" and game.player.is_on_floor(),"Player jumps onto rooftop platform %d" % step)
	check(game.stage_world.at_finish(),"The final platform is reachable and supports the player")
	game._use("shutdown_pc","device",true)
	check(game.state.stage.phase == "clear","The physical power switch clears the last stage")
	ui.next_stage()
	check(game.state.stage.phase == "complete" and game.state.stage.cleared == [1,2,3,4,5,6],"All six stages lead to the clock-out result")
	await capture(game,"08-finish")
	check(game.save_now(),"Stage progress saves")
	var loaded = game.store.load_state(game.content)
	check(loaded.has("state") and loaded.state.stage.index == 6 and loaded.state.stage.unlocked == 6 and loaded.state.stage.phase == "complete" and loaded.state.stage.blasts == 4 and loaded.state.stage.cleared.size() == 6,"Progress, unlocks and explosion count reload: "+loaded.get("error",""))
	if loaded.has("state"): game.state = loaded.state
	ui.open_stage_picker()
	await capture(game,"06-stages")
	game.dispatch({"type":"stage.select","payload":{"index":3}})
	ui.current_attempt = ""
	ui.begin_stage()
	enter(game,"exit")
	check(ui.mode == "pause" and not ui.command_input.has_focus(),"Exit returns to the menu without hidden terminal focus")
	var original_bindings = game.bindings.bindings.duplicate(true)
	game.bindings.bindings.pause = [KEY_P]
	game.bindings.apply()
	ui.begin_stage()
	ui.open_terminal()
	key = InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	key.pressed = true
	Input.parse_input_event(key.duplicate())
	Input.flush_buffered_events()
	await get_tree().process_frame
	key.pressed = false
	Input.parse_input_event(key.duplicate())
	Input.flush_buffered_events()
	check(ui.mode == "pause","Stage-game Escape remains available with an older custom movement profile")
	ui.close()
	check(ui.mode == "field" and game.player.enabled,"Closing pause resumes movement")
	ui.open_pause()
	game.bindings.bindings = original_bindings
	game.bindings.apply()
	ui.open_tablet(4)
	await get_tree().process_frame
	var review = load("res://prototype/tests/smoke.gd").new()
	add_child(review)
	await review.settings_dialog_checks(game,failures)
	await capture(game,"07-settings")
	ui.settings_screen.close_editor()
	check(ui.mode == "pause" and not game.player.enabled,"Settings return to the pause menu")
	var original = game.get_window().size
	for dimensions in [Vector2i(1280,720),Vector2i(1024,768),Vector2i(960,540),Vector2i(540,960)]:
		game.get_window().size = dimensions
		game._fit_screen()
		await get_tree().process_frame
		ui.fit_screen()
		ui.entry.show_menu(false)
		await get_tree().process_frame
		await get_tree().process_frame
		var bounds = get_viewport().get_visible_rect().grow(1)
		check(bounds.encloses(ui.entry.quit.get_global_rect()),"Main menu exit fits "+str(dimensions))
		ui.begin_stage()
		ui.open_terminal()
		await get_tree().process_frame
		check(bounds.encloses(ui.command_input.get_global_rect()),"Terminal input fits "+str(dimensions))
		await capture(game,"terminal-%dx%d" % [dimensions.x,dimensions.y])
		enter(game,"oops")
		await get_tree().create_timer(.85).timeout
		await get_tree().process_frame
		await get_tree().process_frame
		check(bounds.encloses(ui.result_retry.get_global_rect()) and bounds.encloses(ui.result_menu.get_global_rect()),"Explosion actions fit "+str(dimensions))
		await capture(game,"explosion-%dx%d" % [dimensions.x,dimensions.y])
		ui.retry_stage()
		ui.open_tablet(4)
		await get_tree().process_frame
		await get_tree().process_frame
		check(ui.settings_screen.get_visible_rect().grow(1).encloses(ui.settings_screen.save_button.get_global_rect()),"Settings save action fits "+str(dimensions))
		await capture(game,"settings-%dx%d" % [dimensions.x,dimensions.y])
		ui.settings_screen.close_editor()
	game.get_window().size = original
	game._fit_screen()
	ui.clear_effects()
	# Let a canceled reset countdown release its existing one-second wait.
	await get_tree().create_timer(1.05).timeout
	var summary = {"passed":failures.is_empty(),"failures":failures,"platform":OS.get_name(),"mobile":game.controls.mobile,"touchDefault":touch_default,"keyboardDetected":game.controls.keyboard_seen,"stages":6,"blasts":game.state.stage.blasts}
	print("INVESTIGATION_SMOKE ",JSON.stringify(summary))
	get_tree().quit(0 if failures.is_empty() else 1)
