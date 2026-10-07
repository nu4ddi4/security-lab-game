extends SceneTree

var assertions = 0
var failures = []
var path = "user://input-qa-%d/bindings.json" % Time.get_ticks_usec()

func check(value: bool, message: String):
	assertions += 1
	if not value: failures.append(message); push_error(message)

func write(raw: String):
	var file = FileAccess.open(path,FileAccess.WRITE)
	check(file != null,"Test profile opened")
	if file != null: file.store_string(raw); file.close()

func _initialize():
	var profile = LabInputBindings.new()
	profile.path = path
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	profile.load_profile()
	var defaults = LabInputBindings.defaults()
	check(profile.bindings == defaults and profile.load_status.is_empty(),"Missing profile uses original defaults")
	check(defaults == {"forward":[KEY_W],"back":[KEY_S],"left":[KEY_A],"right":[KEY_D],"sprint":[KEY_SHIFT],"crouch":[KEY_CTRL,KEY_C],"jump":[KEY_SPACE],"inspect":[KEY_E],"tool":[KEY_F],"pause":[KEY_ESCAPE]},"Original WASD/Shift/Ctrl-C/Space/E/F/Esc defaults preserved")
	for action in LabInputBindings.ACTIONS:
		check(InputMap.has_action(action.id),"Managed action exists: "+action.id)
		var events = InputMap.action_get_events(action.id)
		check(events.size() == action.defaults.size(),"No duplicate startup events: "+action.id)
		for index in range(events.size()): check(events[index] is InputEventKey and events[index].physical_keycode == action.defaults[index],"Physical key matches source: "+action.id)
	profile.apply()
	check(InputMap.action_get_events("crouch").size() == 2,"Repeated setup cannot duplicate aliases")
	var original_ui = InputMap.action_get_events("ui_accept").size()
	var draft = profile.replace_key(defaults,"forward",KEY_UP)
	check(draft.ok and draft.bindings.forward == [KEY_UP] and defaults.forward == [KEY_W],"Draft does not alter active profile or defaults")
	check(profile.save_profile(draft.bindings).ok,"Changed profile atomically saved")
	var event = InputEventKey.new()
	event.physical_keycode = KEY_UP
	event.pressed = true
	check(InputMap.event_is_action(event,"forward"),"Rebound InputMap matches new key")
	event.physical_keycode = KEY_W
	check(not InputMap.event_is_action(event,"forward"),"Old key removed after save")
	check(InputMap.action_get_events("ui_accept").size() == original_ui,"Godot UI input actions untouched")
	var restarted = LabInputBindings.new()
	restarted.path = path
	restarted.load_profile()
	check(restarted.bindings.forward == [KEY_UP] and LabInputBindings.key_names("forward") == "Up","Fresh instance restores saved physical bindings")
	var persisted = FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(persisted)
	check(parsed.schema == 1 and parsed.mode == "physical_keyboard" and parsed.actions.size() == 10,"Versioned keyboard-only format")
	var conflict = profile.replace_key(restarted.bindings,"tool",KEY_E)
	check(not conflict.ok and conflict.conflict == "inspect" and conflict.message.contains("조사"),"Conflict identifies existing action without stealing its key")
	check(profile.replace_key(defaults,"inspect",KEY_F).conflict == "tool","Conflict names old owner regardless of action order")
	check(FileAccess.get_file_as_string(path) == persisted,"Conflict never rewrites saved profile")
	for action in LabInputBindings.ACTIONS:
		var bad = defaults.duplicate(true)
		bad[action.id] = []
		check(not LabInputBindings.validate(bad).ok,"Essential action cannot be emptied: "+action.id)
		bad.erase(action.id)
		check(not LabInputBindings.validate(bad).ok,"Essential action cannot be omitted: "+action.id)
	for bad_key in [0,-1,KEY_META,KEY_TAB,true,"E",1.5,INF,999999999]: check(not LabInputBindings.valid_key(bad_key),"Unsupported or malformed key rejected")
	for good_key in [KEY_ESCAPE,KEY_ENTER,KEY_SPACE,KEY_CTRL,KEY_SHIFT,KEY_F1,KEY_F12,KEY_UP,KEY_A,KEY_KP_1]: check(LabInputBindings.valid_key(good_key),"Supported physical key accepted")
	var duplicate = defaults.duplicate(true)
	duplicate.crouch = [KEY_CTRL,KEY_CTRL]
	check(not LabInputBindings.validate(duplicate).ok,"Repeated aliases rejected")
	var changed = defaults.duplicate(true)
	changed.pause = [KEY_P]
	changed.jump = [KEY_ESCAPE]
	check(profile.save_profile(changed).ok,"Escape can be rebound after pause moves to a free key")
	check(LabInputBindings.hint("Esc · E · F · Shift · Ctrl·C · Space") == "P · E · F · Shift · Ctrl / C · Escape","Displayed hints follow current InputMap")
	changed.tool = [KEY_G]
	changed.inspect = [KEY_F]
	check(profile.save_profile(changed).ok and LabInputBindings.hint("E / F") == "F / G","Hint replacement is one pass, not recursive")
	var invalid_profiles = ["not JSON","null","[]","{}",JSON.stringify({"schema":2,"mode":"physical_keyboard","actions":defaults}),JSON.stringify({"schema":1,"mode":"gamepad","actions":defaults}),JSON.stringify({"schema":1,"mode":"physical_keyboard","actions":duplicate}),"X".repeat(16385)]
	for raw in invalid_profiles:
		write(raw)
		restarted.load_profile()
		check(restarted.bindings == defaults and not restarted.load_status.is_empty(),"Malformed/oversize profile restores full valid defaults")
	check(profile.save_profile(defaults).ok and profile.bindings == defaults,"Default restore can be saved")
	var snapshot = profile.bindings.duplicate(true)
	profile.path = path.get_base_dir().path_join("missing/subdir/input.json")
	check(not profile.save_profile(changed).ok and profile.bindings == snapshot,"Unwritable destination keeps active controls unchanged")
	check(FileAccess.get_file_as_string(path).contains("physical_keyboard"),"Save failure preserves prior file")
	print("INPUT_BINDINGS_TEST ",JSON.stringify({"passed":failures.is_empty(),"assertions":assertions,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
