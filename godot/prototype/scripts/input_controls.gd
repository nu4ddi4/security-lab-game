class_name InvestigationControls
extends CanvasLayer

signal changed

class Stick extends Control:
	var axes = Vector2.ZERO
	func _draw():
		draw_circle(Vector2(90,90),86,Color(.08,.14,.18,.65))
		draw_arc(Vector2(90,90),86,0,TAU,64,Color(.5,.85,.85,.7),3)
		draw_circle(Vector2(90,90)+axes*65,30,Color(.5,.85,.85,.8))

var mobile = OS.has_feature("mobile") or "--mobile-qa" in OS.get_cmdline_user_args()
var touch_enabled = false
var keyboard_seen = false
var automatic_updates = true
var game: InvestigationPrototype
var root: Control
var stick: Stick
var buttons = {}
var button_rects = {}
var move_finger = -1
var look_finger = -1
var move_origin = Vector2.ZERO
var axes = Vector2.ZERO
var config = ConfigFile.new()
var testing = "--prototype-smoke" in OS.get_cmdline_user_args()

func _init():
	if not testing: config.load("user://controls.cfg")
	touch_enabled = bool(config.get_value("input","touch",mobile))
	automatic_updates = bool(config.get_value("updates","automatic",true))

func setup(controller: InvestigationPrototype):
	game = controller
	layer = 10
	root = Control.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stick = Stick.new()
	stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stick)
	_add_button("tool","조작",func():
		var target = game.player.target
		if target != null: game.player.tool_requested.emit(target))
	_add_button("inspect","살펴보기",func():
		if game.player.target != null: game.player.inspect_requested.emit(game.player.target))
	_add_button("jump","점프",Callable(),"jump")
	_add_button("tablet","휴대 단말",func(): game.ui.open_tablet())
	apply()

func _add_button(id: String, text: String, callback: Callable, action = ""):
	var node = TouchScreenButton.new()
	node.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
	node.action = action
	var shape = RectangleShape2D.new()
	shape.size = Vector2(164,76)
	node.shape = shape
	root.add_child(node)
	var background = Polygon2D.new()
	background.polygon = PackedVector2Array([Vector2(-82,-38),Vector2(82,-38),Vector2(82,38),Vector2(-82,38)])
	background.color = Color(.08,.2,.24,.8)
	node.add_child(background)
	var text_label = Label.new()
	text_label.text = text
	text_label.position = Vector2(-82,-38)
	text_label.size = Vector2(164,76)
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_label.add_theme_font_override("font",load("res://assets/fonts/NotoSansKR.ttf"))
	text_label.add_theme_font_size_override("font_size",24)
	node.add_child(text_label)
	if callback.is_valid(): node.pressed.connect(callback)
	buttons[id] = node

func set_touch(value: bool):
	touch_enabled = value
	config.set_value("input","touch",value)
	_save()
	apply()
	changed.emit()

func set_automatic_updates(value: bool):
	automatic_updates = value
	config.set_value("updates","automatic",value)
	_save()
	changed.emit()

func _save():
	if not testing and config.save("user://controls.cfg") != OK:
		game.ui.notice("설정을 저장하지 못했습니다. 현재 실행에는 적용됩니다.")

func apply():
	release_touches()
	if game == null: return
	game.player.touch_controls_enabled = touch_enabled
	game.player.set_enabled(game.player.enabled)
	if game.ui != null: game.ui.refresh()

func release_touches():
	move_finger = -1
	look_finger = -1
	axes = Vector2.ZERO
	if game != null: game.player.touch_axes = Vector2.ZERO
	if stick != null:
		stick.axes = axes
		stick.queue_redraw()
	Input.action_release("jump")

func handle_touch(event: InputEvent) -> bool:
	if game == null or not touch_enabled or not game.player.enabled or game.player.input_blocked(): return false
	var size = get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		if not event.pressed:
			if event.index == move_finger:
				move_finger = -1
				_set_axes(Vector2.ZERO)
				return true
			if event.index == look_finger:
				look_finger = -1
				return true
			return false
		for id in button_rects:
			if buttons[id].visible and button_rects[id].has_point(event.position): return false
		if event.position.x < size.x*.3 and event.position.y > size.y*.5 and move_finger < 0:
			move_finger = event.index
			move_origin = event.position
			_set_axes(Vector2.ZERO)
			return true
		if event.position.x >= size.x*.3 and look_finger < 0:
			look_finger = event.index
			return true
	elif event is InputEventScreenDrag:
		if event.index == move_finger:
			_set_axes(((event.position-move_origin)/85.0).limit_length())
			return true
		if event.index == look_finger:
			game.player.look(event.relative*1.6)
			return true
	return false

func _set_axes(value: Vector2):
	axes = value
	game.player.touch_axes = axes
	stick.axes = axes
	stick.queue_redraw()

func _input(event: InputEvent):
	# Software keyboard events have no physical keycode. Hardware keys remain
	# active alongside touch; detecting them never changes the saved input mode.
	if event is InputEventKey and event.pressed and event.physical_keycode != 0 and not keyboard_seen:
		keyboard_seen = true
		changed.emit()
	if handle_touch(event): get_viewport().set_input_as_handled()

func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: release_touches()

func _process(_delta):
	if game == null or root == null: return
	root.visible = touch_enabled and game.ui.mode == "field"
	if not root.visible:
		if move_finger >= 0 or look_finger >= 0: release_touches()
		return
	var size = get_viewport().get_visible_rect().size
	stick.position = Vector2(36,size.y-230)
	var positions = {"tool":Vector2(size.x-120,size.y-205),"inspect":Vector2(size.x-305,size.y-115),"jump":Vector2(size.x-120,size.y-115),"tablet":Vector2(size.x-120,65)}
	for id in buttons:
		buttons[id].position = positions[id]
		button_rects[id] = Rect2(positions[id]-Vector2(82,38),Vector2(164,76))
	buttons.tool.visible = game.player.target is InvestigationTarget
	buttons.inspect.visible = game.player.target != null
	buttons.tool.get_child(1).text = "대화" if game.player.target is InvestigationTarget and game.player.target.kind == "npc" else "조작"
