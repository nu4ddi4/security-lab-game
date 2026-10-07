class_name InvestigationPrototype
extends Node3D

var content: Dictionary
var engine: InvestigationEngine
var state: Dictionary
var store = InvestigationStore.new()
var player: LabPlayer
var ui: InvestigationUI
var controls: InvestigationControls
var updates: InvestigationUpdates
var context = ""
var blocked_save = false
var save_timer: Timer
var targets = {}
var dialogue_camera_pose: Transform3D
var dialogue_camera_fov = 72.0
var dialogue_camera_active = false
var dialogue_camera_tween: Tween

func _ready():
	if OS.has_feature("Android"): get_tree().quit_on_go_back = false
	content = InvestigationContent.load_case()
	if content.has("error"):
		push_error(content.error)
		return
	engine = InvestigationEngine.new(content)
	var testing = "--prototype-smoke" in OS.get_cmdline_user_args()
	if testing: store.directory = "user://investigation-qa"
	var loaded = {"new":true} if testing else store.load_state(content)
	blocked_save = loaded.has("error")
	state = loaded.get("state",engine.create_state())
	_setup_input()
	player = LabPlayer.new()
	player.name = "Player"
	add_child(player)
	player.global_position = Vector3(-6,.01,5.6)
	_build_world()
	controls = InvestigationControls.new()
	add_child(controls)
	updates = InvestigationUpdates.new()
	add_child(updates)
	ui = InvestigationUI.new()
	add_child(ui)
	ui.setup(self)
	controls.setup(self)
	updates.changed.connect(ui.refresh_settings)
	controls.changed.connect(ui.refresh_settings)
	player.inspect_requested.connect(func(target): target.inspect())
	player.tool_requested.connect(func(target): _use(target.logical_id,target.kind,true))
	player.pause_requested.connect(ui.toggle)
	save_timer = Timer.new()
	save_timer.one_shot = true
	save_timer.wait_time = .4
	save_timer.timeout.connect(save_now)
	add_child(save_timer)
	if blocked_save: ui.notice(loaded.error + "\n새 조사를 시작하기 전 원본을 보존합니다.")
	print("PROTOTYPE_READY ",JSON.stringify({"day":state.day,"dummy":true,"devices":content.case.devices.size(),"npcs":content.case.npcs.size(),"isolatedSave":store.directory}))
	if testing:
		var smoke = load("res://prototype/tests/smoke.gd").new()
		add_child(smoke)
		smoke.run.call_deferred(self)
	elif controls.automatic_updates: updates.check.call_deferred()

func _setup_input():
	var mapping = {"forward":KEY_W,"back":KEY_S,"left":KEY_A,"right":KEY_D,"sprint":KEY_SHIFT,"crouch":KEY_C,"jump":KEY_SPACE,"inspect":KEY_E,"tool":KEY_F,"pause":KEY_ESCAPE}
	for action in mapping:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var event = InputEventKey.new()
		event.physical_keycode = mapping[action]
		InputMap.action_add_event(action,event)

func _use(id: String, kind: String, tool: bool):
	if kind == "npc": ui.open_dialogue(id); return
	if tool:
		context = id
		ui.open_terminal()
	else: ui.notice(content.case.devices[id].description)

func frame_speaker(id: String):
	if not targets.has(id): return
	if not dialogue_camera_active:
		dialogue_camera_pose = player.camera.global_transform
		dialogue_camera_fov = player.camera.fov
		dialogue_camera_active = true
	if dialogue_camera_tween != null: dialogue_camera_tween.kill()
	var head = targets[id].global_position + Vector3(0,.55,0)
	var pose = player.camera.global_transform.looking_at(head,Vector3.UP)
	dialogue_camera_tween = create_tween().set_parallel(true)
	dialogue_camera_tween.tween_property(player.camera,"global_transform",pose,.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	dialogue_camera_tween.tween_property(player.camera,"fov",68.0,.25)

func release_speaker():
	if not dialogue_camera_active: return
	if dialogue_camera_tween != null: dialogue_camera_tween.kill()
	player.camera.global_transform = dialogue_camera_pose
	player.camera.fov = dialogue_camera_fov
	dialogue_camera_active = false

func dispatch(action: Dictionary) -> Dictionary:
	if blocked_save:
		ui.notice("보존된 저장을 확인하거나 새 조사를 선택하세요.")
		return {"code":"SAVE_BLOCKED","text":"저장 확인이 필요합니다."}
	var result = engine.step(state,action)
	var changed = result.state != state
	state = result.state
	if action.get("type") != "memo": ui.refresh()
	if changed: save_timer.start()
	return result

func command(text: String):
	var action = engine.parse(text,context,state)
	if action.type == "pause":
		var preview = engine.step(state,action)
		if preview.code != "CONFIRM_PAUSE": ui.print_output(text,preview.text); return
		ui.confirm(engine._t("CONFIRM_PAUSE"),func():
			action.payload["confirmed"] = true
			ui.print_output(text,dispatch(action).text))
	else: ui.print_output(text,dispatch(action).text)

func save_now():
	if not blocked_save and not store.save(state,content): ui.notice(store.error)

func new_game():
	if not store.preserve(): ui.notice(store.error); return
	state = engine.create_state()
	blocked_save = false
	context = ""
	ui.reset_session()
	ui.sync_memo()
	ui.refresh()
	save_now()

func transfer_file(path: String, exporting: bool):
	if exporting:
		ui.notice("진행 파일을 내보냈습니다." if store.export_file(path,state,content) else store.error)
		return
	var candidate = store.import_file(path,content)
	if candidate.has("error"): ui.notice(candidate.error); return
	if not store.preserve(): ui.notice(store.error); return
	state = candidate.state
	blocked_save = false
	ui.reset_session()
	ui.sync_memo()
	ui.refresh()
	save_now()
	ui.notice("사건 진행을 가져왔습니다.")

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_TAB:
		if ui.mode == "field": ui.open_tablet()
		elif ui.mode == "tablet": ui.close()
		get_viewport().set_input_as_handled()

func _notification(what):
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and ui != null: ui.toggle()
	if what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_APPLICATION_FOCUS_OUT] and ui != null:
		save_now()
	if what == NOTIFICATION_WM_CLOSE_REQUEST and ui != null:
		save_now()
		get_tree().quit()

func _box(position: Vector3, size: Vector3, color: Color, collision = true):
	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = position
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .9
	mesh.material_override = material
	add_child(mesh)
	if collision:
		var body = StaticBody3D.new()
		body.collision_layer = 5
		mesh.add_child(body)
		var shape = CollisionShape3D.new()
		var bounds = BoxShape3D.new()
		bounds.size = size
		shape.shape = bounds
		body.add_child(shape)
	return mesh

func _label(text: String, position: Vector3, size = 40):
	var label = Label3D.new()
	label.text = text
	label.font = load("res://assets/fonts/NotoSansKR.ttf")
	label.font_size = size
	label.pixel_size = .004
	label.position = position
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func _target(id: String, kind: String, position: Vector3, text: String):
	var target = InvestigationTarget.new()
	target.logical_id = id
	target.kind = kind
	target.label = text
	target.position = position
	target.collision_layer = 2
	target.collision_mask = 0
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(.7,1.7,.6) if kind == "npc" else Vector3(1,.9,.4)
	shape.shape = box
	target.add_child(shape)
	add_child(target)
	targets[id] = target
	target.used.connect(_use)
	_label(text,position+Vector3(0,.9,0),28)

func _build_world():
	_box(Vector3(0,-.1,0),Vector3(20,.2,24),Color(.18,.23,.27))
	_box(Vector3(0,1.5,-8),Vector3(20,3,.2),Color(.3,.34,.38))
	for x in [-10,10]: _box(Vector3(x,1.5,0),Vector3(.2,3,24),Color(.3,.34,.38))
	for x in [-3.3,3.3]: _box(Vector3(x,1.5,-4.5),Vector3(.15,3,7),Color(.3,.34,.38))
	for spec in [["관제실",-6.5],["서버실",0],["업무 구역",6.5]]: _label(spec[0],Vector3(spec[1],2.7,-7),44)
	var positions = {"control_console":Vector3(-6.5,1.2,-4),"server_console":Vector3(0,1.2,-4),"project_pc":Vector3(6.5,1.2,-4),"approval_archive":Vector3(-6.5,1.2,-.5),"maintenance_terminal":Vector3(6.5,1.2,-.5),"briefing_board":Vector3(-3,1.2,3)}
	for id in positions:
		var p = positions[id]
		_box(p-Vector3(0,.5,0),Vector3(1.2,.8,.7),Color(.12,.28,.35))
		_box(p,Vector3(.85,.55,.15),Color(.2,.7,.7),false)
		_target(id,"device",p+Vector3(0,0,.15),content.case.devices[id].label)
	var people = {"oh":Vector3(-6,1,3),"park":Vector3(0,1,1),"han":Vector3(6,1,3),"seo":Vector3(8,1,1)}
	for id in people:
		var p = people[id]
		_box(p,Vector3(.6,1.7,.6),Color(.6,.45,.25))
		_target(id,"npc",p+Vector3(0,0,.4),content.case.npcs[id].name+" · "+content.case.npcs[id].role)
	var env = WorldEnvironment.new()
	var settings = Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(.12,.18,.24)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = .65
	env.environment = settings
	add_child(env)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-30,0)
	add_child(light)
