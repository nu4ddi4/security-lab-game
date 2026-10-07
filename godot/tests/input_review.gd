extends Node

var assertions = 0
var failures = []
var game: Node
var editor: LabInputRebinding
var directory = "user://input-review"
var activity = {"inspect":0,"tool":0,"pause":0}

func check(value: bool, text: String):
	assertions += 1
	if not value: failures.append(text); push_error(text)

func button_named(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found = button_named(child,text)
		if found != null: return found
	return null

func window_in(node: Node) -> LabInputRebinding:
	if node is LabInputRebinding: return node
	for child in node.get_children():
		var found = window_in(child)
		if found != null: return found
	return null

func send_key(code: int, target: Window = null, pressed = true, echo = false):
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	if target != null and DisplayServer.get_name() == "headless": target.window_input.emit(event)
	else:
		event.window_id = target.get_window_id() if target != null else game.get_window().get_window_id()
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	await get_tree().process_frame
	await get_tree().physics_frame

func capture(action: String, key: int):
	editor.buttons[action].pressed.emit()
	await send_key(key,editor)
	await send_key(key,editor,false)
	check(editor.capture_action.is_empty() and editor.draft[action] == [key],"Window captures physical key for "+action)

func close_ui():
	game.ui.close()
	await get_tree().process_frame

func run(root: Node):
	game = root
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--input-output="): directory = argument.trim_prefix("--input-output=")
	DirAccess.make_dir_recursive_absolute(directory)
	game.bindings.path = directory.path_join("input_bindings.json")
	game.player.inspect_requested.connect(func(_target): activity.inspect += 1)
	game.player.tool_requested.connect(func(_target): activity.tool += 1)
	game.player.pause_requested.connect(func(): activity.pause += 1)
	await close_ui()
	check(game.player.enabled,"Gameplay enabled before review")
	game.ui.open_tablet(4)
	await get_tree().process_frame
	editor = window_in(game.ui.root)
	check(editor != null and editor.visible and editor.buttons.size() == 9,"Investigation settings expose active actions in the shared editor")
	check(game.player.settings_input_blocked,"Settings capture window blocks gameplay")
	var position = game.player.global_position
	var jumps = game.player.jump_count
	var camera = game.player.camera.rotation
	Input.action_press("forward"); Input.action_press("jump")
	await get_tree().create_timer(.1).timeout
	game.player.look(Vector2(100,50))
	check(game.player.global_position.distance_to(position) < .02 and game.player.jump_count == jumps and game.player.camera.rotation == camera,"Capture window prevents movement, jump and mouse/touch look")
	Input.action_release("forward"); Input.action_release("jump")
	var reviewed_action = "forward"
	editor.buttons[reviewed_action].pressed.emit()
	await send_key(KEY_E,editor,true,true)
	check(editor.capture_action == reviewed_action,"Autorepeat cannot become a binding")
	await send_key(KEY_F,editor)
	await send_key(KEY_F,editor,false)
	check(editor.capture_action == reviewed_action and editor.status.text.contains("상세 도구"),"Conflicting F is rejected with action name")
	await send_key(KEY_ESCAPE,editor)
	await send_key(KEY_ESCAPE,editor,false)
	check(editor.capture_action == reviewed_action and editor.visible and editor.status.text.contains("일시정지"),"Conflicting Escape stays in capture instead of closing UI")
	var chord = InputEventKey.new()
	chord.physical_keycode = KEY_K
	chord.pressed = true
	chord.ctrl_pressed = true
	editor.handle_input(chord)
	check(editor.capture_action == reviewed_action and editor.status.text.contains("키 조합"),"Modifier chord is rejected without losing previous binding")
	check(activity.inspect == 0 and activity.tool == 0 and activity.pause == 0,"Capture cannot trigger inspect/tool/pause")
	editor.cancel_button.pressed.emit()
	check(editor.capture_action.is_empty() and editor.draft[reviewed_action] == [KEY_W],"Cancel keeps previous binding")
	await capture("forward",KEY_UP)
	await capture("tool",KEY_H)
	await capture("pause",KEY_P)
	await capture("jump",KEY_ESCAPE)
	check(editor.visible,"Assigning Escape does not close the settings window")
	check(game.bindings.bindings.jump == [KEY_SPACE],"Draft changes are not active before Save")
	editor.get("fields").sensitivity.value = .0022
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		editor.get_texture().get_image().save_png(directory.path_join("input-rebinding.png"))
	editor.save_button.pressed.emit()
	await get_tree().process_frame
	check(not game.player.settings_input_blocked and game.bindings.bindings.pause == [KEY_P],"Save applies bindings and restores input lock")
	check(is_equal_approx(game.player.sensitivity,.0022) and is_equal_approx(JSON.parse_string(FileAccess.get_file_as_string(game.settings.path)).sensitivity,.0022),"Settings Save applies and persists the mouse slider with the key profile")
	var restarted = LabInputBindings.new()
	restarted.path = game.bindings.path
	restarted.load_profile()
	check(restarted.bindings == game.bindings.bindings,"Saved profile restores in a fresh controller")
	await close_ui()
	position = game.player.global_position
	await send_key(KEY_UP)
	await get_tree().create_timer(.2).timeout
	await send_key(KEY_UP,null,false)
	check(game.player.global_position.distance_to(position) > .1,"Rebound forward key moves real CharacterBody")
	await send_key(KEY_P)
	await send_key(KEY_P,null,false)
	check(activity.pause == 1,"Rebound pause action works in gameplay")
	await close_ui()
	await get_tree().create_timer(.1).timeout
	jumps = game.player.jump_count
	await send_key(KEY_ESCAPE)
	await send_key(KEY_ESCAPE,null,false)
	check(game.player.jump_count == jumps+1 and activity.pause == 1,"Rebound Escape jumps without pausing")
	await get_tree().create_timer(.9).timeout
	# Runtime profile reset preserves defaults, mixed controls and ongoing save.
	game.ui.open_tablet(4)
	await get_tree().process_frame
	editor = window_in(game.ui.root)
	var saved_path = game.bindings.path
	game.bindings.path = directory.path_join("missing/input.json")
	editor.save_button.pressed.emit()
	check(editor.visible and editor.status.text.contains("저장") and game.bindings.bindings.pause == [KEY_P],"Save failure keeps editor open and old active bindings")
	game.bindings.path = saved_path
	editor.reset_button.pressed.emit()
	check(editor.draft == LabInputBindings.defaults() and game.bindings.bindings.pause == [KEY_P],"Restore button changes draft without silently applying")
	editor.save_button.pressed.emit()
	await get_tree().process_frame
	check(game.bindings.bindings == LabInputBindings.defaults(),"Defaults can be restored and persisted from actual UI")
	check(LabInputBindings.key_names("crouch") == "Ctrl / C" and LabInputBindings.key_names("pause") == "Escape","Both crouch aliases and pause restored")
	check(game.save_now() != false,"Investigation save works after rebinding")
	var report = {"passed":failures.is_empty(),"assertions":assertions,"failures":failures,"runtime":"beta","real_window_input":DisplayServer.get_name() != "headless"}
	var file = FileAccess.open(directory.path_join("input-review.json"),FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report,"\t")); file.close()
	print("INPUT_REVIEW ",JSON.stringify(report))
	await get_tree().create_timer(.6).timeout
	get_tree().quit(0 if failures.is_empty() else 1)
