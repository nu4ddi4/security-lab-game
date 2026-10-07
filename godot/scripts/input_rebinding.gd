class_name LabInputRebinding
extends Window

var bindings: LabInputBindings
var player: LabPlayer
var draft: Dictionary = {}
var buttons = {}
var status: Label
var reset_button: Button
var cancel_button: Button
var save_button: Button
var capture_action = ""
var release_key = 0
var held_keys = {}
var previous_blocked = false
var previous_mouse_mode = Input.MOUSE_MODE_VISIBLE

func configure(profile: LabInputBindings, actor: LabPlayer):
	bindings = profile
	player = actor
	draft = bindings.bindings.duplicate(true)

func _ready():
	title = "조작키"
	size = Vector2i(690,660)
	transient = true
	exclusive = true
	previous_blocked = player.settings_input_blocked
	previous_mouse_mode = Input.mouse_mode
	player.settings_input_blocked = true
	player.velocity = Vector3.ZERO
	player.touch_axes = Vector2.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	close_requested.connect(close_editor)
	focus_exited.connect(cancel_capture)
	window_input.connect(handle_input)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,20)
	add_child(margin)
	var body = VBoxContainer.new()
	body.add_theme_constant_override("separation",12)
	margin.add_child(body)
	add_label(body,"조작키 · 물리 키 위치 기준",22)
	add_label(body,"변경할 키를 누른 뒤 키 하나를 입력하세요. 기존 키를 교체합니다.\n입력 대기에서 Esc는 할당할 키이며, 취소 버튼으로 대기를 끝냅니다.",16)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",8)
	scroll.add_child(rows)
	for action in LabInputBindings.ACTIONS:
		if player.unified_interaction and action.id == "inspect": continue
		var row = HBoxContainer.new()
		rows.add_child(row)
		var title = "상호작용" if player.unified_interaction and action.id == "tool" else "일시정지 / 휴대 단말" if player.unified_interaction and action.id == "pause" else action.label
		var label = add_label(row,title,18)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var control = add_button(row,LabInputBindings.names(draft[action.id]),func(): begin_capture(action.id))
		control.custom_minimum_size = Vector2(230,34)
		buttons[action.id] = control
	status = add_label(body,bindings.load_status if not bindings.load_status.is_empty() else "변경 사항은 ‘조작키 적용하고 저장’을 눌러 확정합니다.",16)
	status.custom_minimum_size.y = 50
	var actions = HBoxContainer.new()
	body.add_child(actions)
	reset_button = add_button(actions,"기본값으로 복원",restore_defaults)
	cancel_button = add_button(actions,"입력 대기 취소",cancel_capture)
	var finish = HBoxContainer.new()
	body.add_child(finish)
	save_button = add_button(finish,"조작키 적용하고 저장",save_changes)
	add_button(finish,"닫기 · 미저장 변경 취소",close_editor)
	refresh_buttons()

func add_label(parent: Node, text: String, font_size: int) -> Label:
	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",font_size)
	parent.add_child(label)
	return label

func add_button(parent: Node, text: String, callback: Callable) -> Button:
	var control = Button.new()
	control.text = text
	control.pressed.connect(callback)
	parent.add_child(control)
	return control

func refresh_buttons():
	for action in buttons:
		buttons[action].text = "새 키를 누르세요…" if action == capture_action else LabInputBindings.names(draft[action])
		buttons[action].disabled = not capture_action.is_empty()
	cancel_button.disabled = capture_action.is_empty()
	reset_button.disabled = not capture_action.is_empty()
	save_button.disabled = not capture_action.is_empty()

func begin_capture(action: String):
	if not draft.has(action): return
	capture_action = action
	release_key = 0
	var focused = gui_get_focus_owner()
	if focused != null: focused.release_focus()
	status.text = LabInputBindings.label_for(action)+" · 새 키를 누르세요. Esc는 취소 키가 아닙니다."
	refresh_buttons()

func cancel_capture():
	if capture_action.is_empty(): return
	capture_action = ""
	status.text = "입력 대기를 취소했습니다. 아직 변경 사항을 저장하지 않았습니다."
	refresh_buttons()

func restore_defaults():
	cancel_capture()
	draft = LabInputBindings.defaults()
	status.text = "기본값으로 복원했습니다. 적용하고 저장을 눌러 확정하세요."
	refresh_buttons()

func handle_input(event: InputEvent):
	if not event is InputEventKey: return
	if event.pressed: held_keys[event.physical_keycode] = true
	else: held_keys.erase(event.physical_keycode)
	if release_key != 0 and event.physical_keycode == release_key:
		set_input_as_handled()
		if not event.pressed: release_key = 0
		return
	if not capture_action.is_empty():
		set_input_as_handled()
		if not event.pressed or event.echo: return
		var key = event.physical_keycode
		if (event.ctrl_pressed and key != KEY_CTRL) or (event.shift_pressed and key != KEY_SHIFT) or (event.alt_pressed and key != KEY_ALT) or event.meta_pressed:
			status.text = "키 조합은 지원하지 않습니다. 다른 키를 놓고 키 하나만 누르세요."
			return
		var result = bindings.replace_key(draft,capture_action,key)
		if not result.ok: status.text = result.message; return
		draft = result.bindings
		status.text = LabInputBindings.label_for(capture_action)+" → "+LabInputBindings.names([key])+" · 적용하고 저장을 눌러 확정하세요."
		capture_action = ""
		release_key = key
		refresh_buttons()
		return
	if event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		set_input_as_handled()
		close_editor()

func save_changes():
	var result = bindings.save_profile(draft)
	status.text = result.message
	if result.ok: close_editor()

func close_editor():
	capture_action = ""
	hide()
	queue_free()

func _exit_tree():
	if not is_instance_valid(player): return
	player.settings_input_blocked = previous_blocked
	player.release_keys = held_keys.keys().filter(func(key): return LabInputBindings.valid_key(key))
	for action in LabInputBindings.ACTIONS: Input.action_release(action.id)
	Input.mouse_mode = previous_mouse_mode
