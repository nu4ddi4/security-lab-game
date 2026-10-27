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
	if not game.ui.tabs.is_tab_hidden(2) or game.ui.work.text.contains("발생 보고") or game.ui.work.text.contains("수집 문서"):
		failures.append("Investigation UI stays absent before the team-lead assignment")
	if game.objective_marker == null: failures.append("Mission marker is built")
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
		await game.dialogue_camera_tween.finished
	var original_fov = game.player.camera.fov
	game.player.camera.fov = 90.0
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
	if not game.ui.dialogue_questions.get_child(0).text.contains("확인함"): failures.append("Previously asked questions stay available and are marked as read")
	await capture(game,"02-dialogue")
	var framed_pose = game.player.camera.global_transform
	game.ui.close()
	if not game.player.camera.global_transform.is_equal_approx(framed_pose): failures.append("Closing dialogue preserves the current camera angle")
	await game.dialogue_camera_tween.finished
	if not is_equal_approx(game.player.camera.fov,90.0): failures.append("Closing dialogue restores the player's custom field of view")
	game.player.camera.fov = original_fov
	game.player.look(Vector2(1,0))
	if absf(game.player.camera.rotation.y) > .001: failures.append("Framed camera yaw is synchronized with movement")
	game.dispatch({"type":"dialogue","payload":{"id":"park_intro"}})
	var initial = game.state.known.duplicate()
	game._use("server_console","device",false)
	if game.state.known != initial: failures.append("External inspection never awards evidence")
	game._use("server_console","device",true)
	if game.context != "server_console" or game.player.enabled or game.ui.mode != "terminal": failures.append("F opens only the current device terminal")
	if game.ui.command_sidebar.visible or game.ui.command_list.get_child_count() != 0 or game.ui.terminal.text.contains("pwd / ls"):
		failures.append("Device opening does not reveal command lists")
	game.ui.command_input.text = "help"
	game.ui.execute_command()
	if not game.ui.terminal.text.contains("inspect account") or game.ui.command_list.get_child_count() == 0: failures.append("Typing help reveals current-device commands")
	if game.ui.terminal.text.contains("inspect staging"): failures.append("Help does not expose unassigned investigation work")
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
	var server_output = game.ui.terminal.get_parsed_text()
	if not server_output.contains("sec.ops > status"): failures.append("Terminal shows the session transcript")
	await capture(game,"03-terminal")
	await get_tree().process_frame
	await get_tree().process_frame
	var output_scroll = game.ui.terminal.get_v_scroll_bar()
	if output_scroll.value+output_scroll.page < output_scroll.max_value-1: failures.append("Terminal keeps the latest command result in view after layout")
	game._use("project_pc","device",true)
	var bad = game.dispatch(game.engine.parse("logs access --task T-17",game.context,game.state))
	if bad.code != "WRONG_DEVICE": failures.append("Device command guard remains enforced")
	game._use("server_console","device",true)
	if game.ui.terminal.get_parsed_text() != server_output: failures.append("Returning to a device preserves its output")
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
	await note_and_terminal_checks(game,failures)
	game.ui.close()
	if not game.player.enabled: failures.append("Closing the UI restores movement")
	var original_touch = game.controls.touch_enabled
	game.ui.open_tablet(4)
	game.ui.touch_setting.button_pressed = true
	if not game.controls.touch_enabled: failures.append("Settings enable touch without disabling keyboard")
	await capture(game,"07-settings")
	for category in ["general","display","sound"]:
		game.ui.settings_screen.select_category(category)
		await capture(game,"07-settings-"+category)
	game.ui.settings_screen.select_category("controls")
	# Moving to another tablet page keeps the tablet open and never hands the pointer back to the game.
	var pointer = Input.mouse_mode
	game.ui.settings_screen.leave_for(1)
	if game.ui.mode != "tablet" or not game.ui.modal.visible or game.ui.tabs.current_tab != 1 or game.player.enabled or Input.mouse_mode != pointer or is_instance_valid(game.ui.settings_screen): failures.append("Leaving settings for a tablet page keeps the tablet open and the pointer free")
	game.ui.open_tablet(4)
	game.ui.settings_screen.close_editor()
	if game.ui.mode != "field" or not game.player.enabled or game.ui.modal.visible: failures.append("Closing settings returns to the game")
	settings_checks(game,failures)
	game.ui.open_tablet(4)
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
	game.ui.update_progress(.42)
	if not game.ui.update_hud.visible or roundi(game.ui.update_hud_bar.value) != 42: failures.append("Update download progress is shown in the field")
	game.ui.update_progress(-1.0)
	if game.ui.update_hud.visible: failures.append("Update progress disappears when no download runs")
	if game.updates.busy or not game.player.enabled or (is_instance_valid(game.ui.update_download) and game.ui.update_download.visible): failures.append("Update failures leave gameplay available and hide stale downloads")
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
	game.ui.close()
	game.controls.set_touch(true)
	var selection = InputEventScreenTouch.new()
	selection.index = 8
	selection.pressed = true
	selection.position = game.player.camera.unproject_position(game.targets.server_console.global_position)
	game.controls.handle_touch(selection)
	selection.pressed = false
	game.controls.handle_touch(selection)
	if game.player.target != game.targets.server_console or game.ui.mode != "field": failures.append("A touch selects equipment without opening it or moving the camera")
	var old_e = InputEventKey.new()
	old_e.pressed = true
	old_e.physical_keycode = KEY_E
	game.player._unhandled_input(old_e)
	if game.ui.mode != "field": failures.append("The former inspect key no longer duplicates interaction")
	game.player.interact()
	if game.ui.mode != "terminal": failures.append("Selected equipment uses the same single interaction")
	game.controls.set_touch(original_touch)
	game.ui.open_tablet()
	if game.player.enabled: failures.append("Tablet freezes movement")
	if game.detailed_world:
		game.ui.close()
		await aisle_checks(game,failures)
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
			if not game.controls.buttons.tool.visible or game.controls.buttons.has("inspect"): failures.append("Doors share the single interaction button")
			var door = game.player.target
			var old_angle = door.desired_angle
			game.player.interact()
			if door.desired_angle == old_angle or game.ui.mode != "field": failures.append("F interaction opens doors without opening a device terminal")
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
	var previous_state = game.state.duplicate(true)
	game.state.day = 4
	game.ui.refresh()
	if game.ui.tabs.is_tab_hidden(2) or not game.ui.work.text.contains("발생 보고"): failures.append("Investigation UI appears at the day-four assignment")
	game.state = previous_state
	game.ui.refresh()
	await progression_checks(game,failures)
	await focus_checks(game,failures)
	await interaction_checks(game,failures)
	await responsive_checks(game,failures)
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
	game.dispatch({"type":"memo","payload":{"text":"temporary note"}})
	game.reset_all_data()
	if game.state.memo != "" or game.state.day != 1 or game.blocked_save or game.ui.memo.text != "": failures.append("Full data reset returns to a fresh investigation")
	if game.ui.mode != "briefing": failures.append("A fresh investigation starts with the assignment briefing")
	game.ui.close()
	var summary = {"passed":failures.is_empty(),"failures":failures,"platform":OS.get_name(),"mobile":game.controls.mobile,"touchDefault":original_touch,"keyboardDetected":game.controls.keyboard_seen}
	var report = FileAccess.open("user://prototype-smoke-result.json",FileAccess.WRITE)
	if report != null: report.store_string(JSON.stringify(summary))
	print("INVESTIGATION_SMOKE ",JSON.stringify(summary))
	get_tree().quit(0 if failures.is_empty() else 1)

func note_and_terminal_checks(game, failures: Array):
	var original_memo = game.state.memo
	game.ui.notes.get_child(0).get_child(1).pressed.emit()
	if game.state.memo == original_memo or game.ui.memo.text != game.state.memo: failures.append("Quoting a note updates the persisted memo as well as the editor")
	game.save_now()
	var saved = game.store.load_state(game.content)
	if not saved.has("state") or saved.state.memo != game.ui.memo.text: failures.append("Quoted note survives a save reload")
	await capture(game,"05-notes-quoted")
	game.dispatch({"type":"memo","payload":{"text":original_memo}})
	game.ui.sync_memo()
	game.ui.memo.text = "x".repeat(int(game.content.rules.maxMemoLength)+1)
	game.ui.memo.text_changed.emit()
	if game.state.memo != original_memo or not game.ui.memo_status.text.contains("저장되지 않습니다"): failures.append("Oversized memo keeps the last accepted text and explains why the draft is not saved")
	game.ui.memo.text = original_memo
	game.ui.memo.text_changed.emit()
	if game.ui.memo_status.text.contains("저장되지 않습니다"): failures.append("Reducing the memo length clears the unsaved draft warning")
	game._use("server_console","device",true)
	game.ui.command_input.text = "inspect account"
	game._use("project_pc","device",true)
	if game.ui.command_input.text != "": failures.append("Pending server commands do not follow the player to another device")
	game.ui.command_input.text = "inspect files"
	game._use("server_console","device",true)
	if game.ui.command_input.text != "inspect account": failures.append("Returning to a device restores its pending command")
	game.ui.command_input.text = "logs t"
	game.ui.recall_command(-1)
	game.ui.recall_command(1)
	if game.ui.command_input.text != "logs t": failures.append("Leaving command history restores the command being written")
	game.ui.close()
	game._use("server_console","device",true)
	if game.ui.command_input.text != "logs t": failures.append("Closing and reopening a terminal preserves its pending input")
	game.ui.command_input.clear()
	game.ui.close()

func progression_checks(game, failures: Array):
	var original = game.state.duplicate(true)
	game.ui.finish_day(1)
	if game.state.day != 2 or game.ui.tabs.current_tab != 1 or game.ui.contact != "han": failures.append("Next day opens its business message")
	if game.ui.tabs.is_tab_hidden(2): failures.append("Optional occurrence reporting is available on day two")
	if game.ui.work.text.contains("미승인"): failures.append("Optional investigation does not appear as unfinished daily work")
	var daily_guide = game.ui.guide_info().text
	for word in ["B-05","T-17","staging","서유진","backup disable"]:
		if daily_guide.contains(word): failures.append("Daily work does not route the player to a case answer: "+word)
	for command in ["status","logs backups","backup disable B-05","verify service","logs access --task T-17","inspect staging"]:
		game.dispatch(game.engine.parse(command,"server_console",game.state))
	game.ui.open_tablet(0)
	if game.ui.notes.get_child_count() != game.state.known.size(): failures.append("Read originals remain available before the formal day-four assignment")
	game.ui.open_tablet(2)
	game.ui.claim.select(1)
	for slot in ["scope","access","collection"]:
		var id = {"scope":"approval","access":"access-night-1","collection":"staging-night-1"}[slot]
		var picker = game.ui.attachments[slot]
		for i in range(picker.item_count):
			if picker.get_item_metadata(i) == id: picker.select(i)
	game.ui.submit_report()
	if not game.state.report.approved or not game.ui.report_submit.disabled: failures.append("Early report grants permission without forcing a duplicate report")
	close_notices(game)
	game.ui.finish_day(2)
	game.dispatch(game.engine.parse("inspect files","project_pc",game.state))
	game.dispatch(game.engine.parse("logs indexing","project_pc",game.state))
	if game.ui.guide_info().text.contains("T-17") or game.ui.guide_info().text.contains("repair index"): failures.append("Search work does not explain the case or prescribe the fault's solution")
	await capture(game,"08-search-records")
	game.dispatch(game.engine.parse("repair index","server_console",game.state))
	game.dispatch(game.engine.parse("verify search","project_pc",game.state))
	game.ui.finish_day(3)
	if game.state.day != 4 or game.ui.contact != "oh" or not game.state.report.approved: failures.append("Day-four alternative assignment preserves early approval")
	await capture(game,"09-investigation-assignment")
	for command in ["logs submissions","logs application","inspect PKG-218-R2","inspect metadata","inspect T-19"]:
		game.dispatch(game.engine.parse(command,"control_console",game.state))
	var markup = InvestigationUI.terminal_markup([{ "kind":"output","text":"LUMEN | T-17 | INTERNAL\nSUCCESS | HOLD"}])
	if markup.contains("[color") or markup.contains("[b]"): failures.append("Record rendering does not rank or color case facts")
	game.ui.case_desk.open(game.ui,false)
	var desk = game.ui.case_desk
	if not desk.claim_picker.disabled: failures.append("Claim entry starts closed before originals are selected")
	desk.picks[0].show_popup()
	await get_tree().process_frame
	await get_tree().process_frame
	if not desk.picks[0].get_popup().visible: failures.append("Original record picker opens through the native control")
	await capture(game,"12-original-picker")
	desk.picks[0].get_popup().hide()
	select_record(desk.picks[0],"message")
	select_record(desk.picks[1],"submissions")
	if desk.claim_picker.disabled: failures.append("Connecting originals enables the comparison form")
	select_record(desk.claim_picker,"C05")
	press_text(desk.body,"대조 기록 접수")
	if not game.state.casework.links.has("C05"): failures.append("Comparison form records the player's selected independent originals")
	await capture(game,"12-comparison-form")
	desk.dialog.hide(); desk.dialog.queue_free()
	for day in range(4,7):
		game.dispatch(game.engine.parse("verify service","server_console",game.state))
		game.dispatch(game.engine.parse("verify search","project_pc",game.state))
		if day == 5: game.dispatch(game.engine.parse("logs requests","maintenance_terminal",game.state))
		if day == 6: game.dispatch(game.engine.parse("logs contracts","maintenance_terminal",game.state))
		game.ui.finish_day(day)
	var links = {"C06":["submissions","application","package"],"C07":["metadata","message","submissions"],"C08":["request","message","approval"],"C09":["purpose","package","metadata"],"C10":["application","transfer"]}
	for claim in links: game.dispatch({"type":"inference","payload":{"claim":claim,"records":links[claim]}})
	game._use("control_console","device",true)
	game.ui.case_work_button.pressed.emit()
	desk.view = 1; desk.build()
	select_record(desk.picks[0],"application")
	select_record(desk.picks[1],"transfer")
	press_text(desk.body,"조치 승인 요청")
	if not game.state.casework.control.approved: failures.append("Console control request uses the originals selected by the player")
	press_text(desk.body,"승인 조치 실행")
	confirm_open_dialog(game)
	if game.state.casework.control.mode != "blocked_pre_run": failures.append("Approved console control records a pre-run hold")
	desk.dialog.hide(); desk.dialog.queue_free()
	game.ui.clock_button.pressed.emit()
	confirm_open_dialog(game)
	if game.state.casework.dispatch != "not_run" or game.state.casework.minute != 1050: failures.append("Day-seven scheduled work resolves at 17:30")
	close_notices(game)
	game.dispatch(game.engine.parse("logs controls","control_console",game.state))
	game.dispatch(game.engine.parse("logs dispatch","control_console",game.state))
	game.dispatch(game.engine.parse("logs receipts","control_console",game.state))
	game._use("control_console","device",true)
	game.ui.case_work_button.pressed.emit()
	desk.view = 2; desk.build()
	for picker in desk.final_picks.values():
		if picker.get_item_metadata(picker.selected) != "unknown": failures.append("Final findings are never preselected from hidden case truth")
	var fields = {"scope":"violation","collection":"collected","submission":"seo","authorship":"vendor","awareness":"warning_seen","purpose":"contract_support","transfer":"not_run","material":"unknown"}
	for key in fields: select_record(desk.final_picks[key],fields[key])
	press_text(desk.body,"종결 보고 접수")
	if game.state.casework.final.is_empty(): failures.append("Final form submits the player's findings")
	await capture(game,"13-final-report")
	press_text(desk.body,"조사 종결")
	confirm_open_dialog(game)
	if not game.state.ended or game.state.casework.ending.get("id") != "A": failures.append("Final report and observed control outcome produce the selected ending")
	desk.view = 3; desk.build()
	await capture(game,"14-closing-document")
	if not game.save_now() or not game.store.load_state(game.content).has("state"): failures.append("Completed case saves and reloads")
	desk.dialog.hide(); desk.dialog.queue_free()
	game.state = original
	game.ui.reset_session()
	game.ui.sync_memo()
	game.ui.refresh()
	game.ui.close()

func select_record(picker: OptionButton, id: String):
	for i in range(picker.item_count):
		if picker.get_item_metadata(i) == id:
			picker.select(i)
			picker.item_selected.emit(i)
			return

func press_text(parent: Node, text: String):
	for node in parent.find_children("*","Button",true,false):
		if node.text == text: node.pressed.emit(); return

func confirm_open_dialog(game):
	for child in game.ui.root.find_children("*","ConfirmationDialog",true,false):
		if child.visible: child.confirmed.emit(); return

func close_notices(game):
	for child in game.ui.root.get_children():
		if child is AcceptDialog: child.hide(); child.queue_free()

func settings_checks(game, failures: Array):
	var original = game.settings.values.duplicate(true)
	var viewport = game.get_viewport()
	var original_scale = viewport.scaling_3d_scale
	var original_msaa = viewport.msaa_3d
	for quality in range(4):
		var candidate = original.duplicate(true)
		candidate.quality = quality
		candidate.master = .2
		if not game.settings.save_values(candidate).ok: failures.append("Settings save succeeds for quality "+str(quality))
		var expected_scale = .65 if game.controls.mobile else (.8 if quality == 0 else 1.0)
		var expected_msaa = Viewport.MSAA_DISABLED if game.controls.mobile else [Viewport.MSAA_DISABLED,Viewport.MSAA_2X,Viewport.MSAA_4X,Viewport.MSAA_8X][quality]
		if not is_equal_approx(viewport.scaling_3d_scale,expected_scale) or viewport.msaa_3d != expected_msaa:
			failures.append("Settings save preserves the platform's rendering profile at quality "+str(quality))
		var reloaded = LabSettings.new()
		game.add_child(reloaded)
		reloaded.setup(game)
		if reloaded.values.quality != quality or not is_equal_approx(viewport.scaling_3d_scale,expected_scale) or viewport.msaa_3d != expected_msaa:
			failures.append("Reloading settings preserves the platform's rendering profile at quality "+str(quality))
		reloaded.queue_free()
	if not game.settings.save_values(original).ok: failures.append("Original settings can be restored after the review")
	viewport.scaling_3d_scale = original_scale
	viewport.msaa_3d = original_msaa

func _dummy_server_pose(game):
	game.player.global_position = Vector3(0,.01,-2)
	game.player.camera.look_at(Vector3(0,1.2,-3.85))

func aisle_checks(game, failures: Array):
	var pose = game.player.global_transform
	var camera_pose = game.player.camera.transform
	for side in ["West","East"]:
		var anchors = game.investigation_environment.anchors
		var start = anchors["WALK_"+side+"_Start"].global_position
		var finish = anchors["WALK_"+side+"_End"].global_position
		for reverse in [false,true]:
			game.player.global_position = finish if reverse else start
			game.player.rotation = Vector3(0,PI if reverse else 0,0)
			game.player.velocity = Vector3.ZERO
			await get_tree().physics_frame
			Input.action_press("forward")
			await get_tree().create_timer(3.35).timeout
			Input.action_release("forward")
			var destination = start if reverse else finish
			if game.player.global_position.distance_to(destination) > .55:
				failures.append("Walk entire "+side+" aisle in both directions: "+str(game.player.global_position))
	game.player.global_transform = pose
	game.player.camera.transform = camera_pose
	game.player.velocity = Vector3.ZERO

func focus_checks(game, failures: Array):
	game.ui.close()
	var original_touch = game.controls.touch_enabled
	game.controls.set_touch(false)
	var pose = game.player.global_transform
	game.player._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	Input.action_press("forward")
	await get_tree().create_timer(.1).timeout
	Input.action_release("forward")
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE or game.player.global_transform != pose:
		failures.append("Losing focus releases the cursor and freezes movement")
	game.player._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	game.player.restore_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if OS.has_feature("mobile"):
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE or game.player.input_blocked():
			failures.append("Mobile focus return restores input without capturing the cursor")
	else:
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE or not game.player.input_blocked():
			failures.append("Focus return and editor restoration leave the cursor free")
		var click = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		game.player._unhandled_input(click)
		if game.player.input_blocked(): failures.append("A field click resumes gameplay after focus return")
	game.controls.set_touch(original_touch)

func interaction_checks(game, failures: Array):
	game.ui.open_tablet()
	var pose = game.player.global_transform
	var camera_pose = game.player.camera.transform
	game.player.global_position = Vector3(60,0,60)
	game.player.rotation = Vector3.ZERO
	game.player.camera.rotation = Vector3.ZERO
	var first = InvestigationTarget.new()
	first.collision_layer = 2
	first.position = Vector3(60,1.65,56.85)
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(.3,.3,.12)
	shape.shape = box
	first.add_child(shape)
	game.add_child(first)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if game.player.target != first: failures.append("Equipment at 3.15m is comfortably reachable")
	game.player.camera.rotation.y = -.075
	await get_tree().physics_frame
	await get_tree().physics_frame
	if game.player.target != first: failures.append("Aim assist tolerates a small miss at an equipment edge")
	var second = first.duplicate()
	second.position.x += .75
	game.add_child(second)
	game.player.camera.look_at(second.global_position)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if game.player.target != second: failures.append("Pointing at adjacent equipment selects only that equipment")
	var wall = StaticBody3D.new()
	wall.collision_layer = 4
	wall.position = Vector3(60,1.65,58.5)
	var blocker = CollisionShape3D.new()
	var slab = BoxShape3D.new()
	slab.size = Vector3(3,3,.1)
	blocker.shape = slab
	wall.add_child(blocker)
	game.add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if game.player.target != null: failures.append("Interaction cannot select equipment through a wall")
	wall.queue_free()
	second.queue_free()
	first.queue_free()
	game.player.global_transform = pose
	game.player.camera.transform = camera_pose
	await get_tree().physics_frame

func responsive_checks(game, failures: Array):
	var original = game.get_window().size
	var original_touch = game.controls.touch_enabled
	game.controls.set_touch(true)
	for dimensions in [Vector2i(1280,720),Vector2i(1024,768),Vector2i(960,540),Vector2i(540,960)]:
		game.get_window().size = dimensions
		game._fit_screen()
		await get_tree().process_frame
		game.ui.fit_screen()
		game.ui.open_tablet(4)
		await get_tree().process_frame
		await get_tree().process_frame
		var viewport = get_viewport().get_visible_rect()
		var settings = game.ui.settings_screen
		if not is_instance_valid(settings) or not settings.visible or not viewport.grow(1).encloses(Rect2(Vector2(settings.position),Vector2(settings.size))): failures.append("Embedded settings fit the viewport at "+str(dimensions))
		if viewport.size.x < viewport.size.y and settings.layout.get_global_rect().position.y > viewport.size.y*.3: failures.append("Portrait settings leave room for the content below navigation")
		await capture(game,"settings-%dx%d" % [dimensions.x,dimensions.y])
		game.ui.open_tablet(1)
		await get_tree().process_frame
		await get_tree().process_frame
		if viewport.size.x < viewport.size.y and game.ui.tabs.get_global_rect().position.y > viewport.size.y*.3: failures.append("Portrait tablet navigation does not consume the conversation area")
		game.ui.open_tablet(0)
		await get_tree().process_frame
		await get_tree().process_frame
		if game.ui.notes.get_global_rect().end.x > viewport.end.x: failures.append("Long note titles do not push citation buttons or the tablet outside the screen")
		if dimensions == Vector2i(540,960): await capture(game,"notes-540x960")
		game._use("control_console","device",true)
		game.ui.case_work_button.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		var desk = game.ui.case_desk
		if not viewport.grow(1).encloses(Rect2(Vector2(desk.dialog.position),Vector2(desk.dialog.size))): failures.append("Case forms fit aspect ratio: %s / %s in %s" % [dimensions,Rect2(Vector2(desk.dialog.position),Vector2(desk.dialog.size)),viewport])
		if desk.body.size.x > desk.dialog.size.x: failures.append("Case form content stays inside its window")
		desk.dialog.hide(); desk.dialog.queue_free()
		for panel in [game.ui.modal,game.ui.terminal_panel,game.ui.dialogue_panel,game.ui.briefing_panel]:
			if panel == game.ui.modal: game.ui.open_tablet(4)
			elif panel == game.ui.terminal_panel: game._use("server_console","device",true)
			elif panel == game.ui.dialogue_panel: game._use("oh","npc",true)
			else: game.ui.open_briefing()
			await get_tree().process_frame
			await get_tree().process_frame
			await get_tree().process_frame
			if not viewport.grow(1).encloses(panel.get_global_rect()): failures.append("Panel fits aspect ratio %dx%d: %s %s in %s" % [dimensions.x,dimensions.y,panel.name,panel.get_global_rect(),viewport])
		game.ui.close()
		game.controls._process(0)
		for id in game.controls.button_rects:
			if not viewport.grow(1).encloses(game.controls.button_rects[id]): failures.append("Touch button fits aspect ratio: "+id)
		if game.ui.field_objective.get_global_rect().intersects(game.controls.button_rects.tablet): failures.append("Portrait objective does not overlap the tablet touch button")
		if game.ui.field_objective.size.y > viewport.size.y*.45: failures.append("Objective panel shrinks to its text after orientation changes")
		if dimensions == Vector2i(960,540) or dimensions == Vector2i(540,960):
			await capture(game,"08-field-%dx%d" % [dimensions.x,dimensions.y])
			game._use("server_console","device",true)
			await capture(game,"09-terminal-%dx%d" % [dimensions.x,dimensions.y])
	game._use("control_console","device",true)
	game.ui.case_work_button.pressed.emit()
	game.get_window().size = Vector2i(960,540)
	game._fit_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var rotated = game.ui.case_desk.dialog
	if not get_viewport().get_visible_rect().grow(1).encloses(Rect2(Vector2(rotated.position),Vector2(rotated.size))): failures.append("Open case forms survive a change in orientation")
	rotated.hide(); rotated.queue_free()
	game.get_window().size = original
	game._fit_screen()
	await get_tree().process_frame
	game.ui.fit_screen()
	game.controls.set_touch(original_touch)
